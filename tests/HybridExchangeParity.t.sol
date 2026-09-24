// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {HybridCurveUniV3Exchange} from "../reference/bold/contracts/src/Zappers/Modules/Exchanges/HybridCurveUniV3Exchange.sol";
import {ISwapRouter} from "../reference/bold/contracts/src/Zappers/Modules/Exchanges/UniswapV3/ISwapRouter.sol";
import {GCZToken,GCZVm} from "./GasCompZapperParity.t.sol";
import {IERC20,SafeERC20} from "../reference/bold/contracts/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
contract HybridExchangeMarket {
 using SafeERC20 for IERC20;
 GCZToken public coll;GCZToken public bold;GCZToken public usdc;GCZToken public weth;
 uint128 public usdcIndex;uint128 public boldIndex;uint24 public feeUW;uint24 public feeWC;uint public spare;bool public failCurve;bool public failUni;
 constructor(bool lst,uint128 index,uint24 first,uint24 second){bold=new GCZToken();usdc=new GCZToken();weth=new GCZToken();coll=lst?new GCZToken():weth;usdcIndex=index;boldIndex=index^1;feeUW=first;feeWC=second;}
 function configure(uint unspent,bool curveFailure,bool uniFailure) external {spare=unspent;failCurve=curveFailure;failUni=uniFailure;}
 function exchange(int128 i,int128 j,uint amount,uint minimum) external returns(uint){
  require(!failCurve,"curve failure");bool fromBold=i==int128(boldIndex);require(i==int128(fromBold?boldIndex:usdcIndex)&&j==int128(fromBold?usdcIndex:boldIndex),"indices");
  GCZToken input=fromBold?bold:usdc;GCZToken output=fromBold?usdc:bold;uint spent=amount-spare;uint received=2*spent+17;require(received>=minimum,"curve slippage");
  IERC20(address(input)).safeTransferFrom(msg.sender,address(this),spent);output.mint(msg.sender,received);return received;
 }
 function exactInput(ISwapRouter.ExactInputParams calldata p) external returns(uint){
  require(!failUni,"uni failure");require(p.deadline==block.timestamp,"deadline");
  bytes calldata route=p.path;address first;assembly{first:=shr(96,calldataload(route.offset))}
  bool fromBold=first==address(usdc);bool single=coll==weth;
  bytes memory expected=fromBold?(single?abi.encodePacked(usdc,feeUW,weth):abi.encodePacked(usdc,feeUW,weth,feeWC,coll)):(single?abi.encodePacked(weth,feeUW,usdc):abi.encodePacked(coll,feeWC,weth,feeUW,usdc));
  require(keccak256(route)==keccak256(expected),"packed path");
  require(fromBold?p.recipient!=msg.sender:p.recipient==msg.sender,"recipient");
  uint spent=p.amountIn-spare;uint received=3*spent+19;require(received>=p.amountOutMinimum,"uni slippage");
  IERC20(first).safeTransferFrom(msg.sender,address(this),spent);(fromBold?coll:usdc).mint(p.recipient,received);
  // Unexpected intermediate WETH dust is swept along with input leftovers.
  weth.mint(msg.sender,7);return received;
 }
}
contract HybridExchangeParityTest {
 GCZVm constant vm=GCZVm(address(uint160(uint(keccak256("hevm cheat code")))));
 function make(bool fe,bool lst,uint128 index,uint24 uw,uint24 wc) internal returns(HybridCurveUniV3Exchange z,HybridExchangeMarket m){
  m=new HybridExchangeMarket(lst,index,uw,wc);
  bytes memory code=fe?vm.parseBytes(vm.readFile("build/HybridCurveUniV3Exchange.bin")):type(HybridCurveUniV3Exchange).creationCode;
  bytes memory init=bytes.concat(code,abi.encode(m.coll(),m.bold(),m.usdc(),m.weth(),m,index,index^1,uw,wc,m));address target;assembly{target:=create(0,add(init,32),mload(init))}
  require(target.code.length>0&&target.code.length<=24576,"deploy");z=HybridCurveUniV3Exchange(target);
  m.coll().mint(address(this),1e36);m.bold().mint(address(this),1e36);m.coll().approve(target,type(uint).max);m.bold().approve(target,type(uint).max);
  m.bold().mint(target,111);m.usdc().mint(target,222);m.weth().mint(target,333);if(lst)m.coll().mint(target,444);
  require(z.USDC_INDEX()==index&&z.BOLD_TOKEN_INDEX()==(index^1)&&z.feeUsdcWeth()==uw&&z.feeWethColl()==wc);
  require(address(z.collToken())==address(m.coll())&&address(z.boldToken())==address(m.bold())&&address(z.USDC())==address(m.usdc())&&address(z.WETH())==address(m.weth())&&address(z.curvePool())==address(m)&&address(z.uniV3Router())==address(m));
 }
 function run(bool fe,bool lst,uint128 index,uint24 uw,uint24 wc,uint amount,uint spare) internal returns(bytes32){
  (HybridCurveUniV3Exchange z,HybridExchangeMarket m)=make(fe,lst,index,uw,wc);m.configure(spare,false,false);
  uint output=2*(3*(amount-spare)+19-spare)+17;require(z.swapToBold(amount,output)==output);
  uint collateral=3*(2*(amount-spare)+17-spare)+19;z.swapFromBold(amount,collateral);
  require(m.bold().balanceOf(address(z))==111&&m.usdc().balanceOf(address(z))==222&&m.weth().balanceOf(address(z))==333,"preserve baseline");if(lst)require(m.coll().balanceOf(address(z))==444);
  return keccak256(abi.encode(m.coll().balanceOf(address(this)),m.bold().balanceOf(address(this)),m.usdc().balanceOf(address(this)),m.weth().balanceOf(address(this)),m.bold().balanceOf(address(m)),m.usdc().balanceOf(address(m)),m.coll().balanceOf(address(m))));
 }
 function testBothBranchesDirectionsAndLeftovers() public {for(uint branch;branch<2;branch++)require(run(true,branch==1,0,500,3000,1000,73)==run(false,branch==1,0,500,3000,1000,73));}
 function testFuzzPathsFeesAndSignedIndices(bool lst,uint128 index,uint24 uw,uint24 wc,uint96 raw) public {uint amount=uint(raw)+100;require(run(true,lst,index,uw,wc,amount,17)==run(false,lst,index,uw,wc,amount,17));}
 function compare(HybridCurveUniV3Exchange a,HybridCurveUniV3Exchange b,bytes memory data) internal returns(bool){(bool ok,bytes memory x)=address(a).call(data);(bool success,bytes memory y)=address(b).call(data);require(ok==success&&keccak256(x)==keccak256(y),"return parity");return ok;}
 function testRollbackAcrossBothMarketsAndOptionalReturns() public {
  (HybridCurveUniV3Exchange a,HybridExchangeMarket ma)=make(true,true,0,500,3000);(HybridCurveUniV3Exchange b,HybridExchangeMarket mb)=make(false,true,0,500,3000);
  ma.configure(0,false,true);mb.configure(0,false,true);require(!compare(a,b,abi.encodeCall(a.swapFromBold,(1000,0))));
  ma.configure(0,true,false);mb.configure(0,true,false);require(!compare(a,b,abi.encodeCall(a.swapToBold,(1000,0))));
  ma.configure(0,false,false);mb.configure(0,false,false);ma.coll().setMode(2);mb.coll().setMode(2);require(compare(a,b,abi.encodeCall(a.swapToBold,(1000,0))));
  require(ma.coll().balanceOf(address(a))==444&&mb.coll().balanceOf(address(b))==444&&ma.usdc().balanceOf(address(a))==222&&mb.usdc().balanceOf(address(b))==222);
 }
}
