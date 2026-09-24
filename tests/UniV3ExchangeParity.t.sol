// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {UniV3Exchange} from "../reference/bold/contracts/src/Zappers/Modules/Exchanges/UniV3Exchange.sol";
import {UniPriceConverter} from "../reference/bold/contracts/src/Zappers/Modules/Exchanges/UniswapV3/UniPriceConverter.sol";
import {ISwapRouter} from "../reference/bold/contracts/src/Zappers/Modules/Exchanges/UniswapV3/ISwapRouter.sol";
import {GCZToken,GCZVm} from "./GasCompZapperParity.t.sol";
import {IERC20,SafeERC20} from "../reference/bold/contracts/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
contract UniExchangeRouter {
 using SafeERC20 for IERC20;
 uint public spare;bool public fail;uint24 public expectedFee;
 constructor(uint24 fee){expectedFee=fee;}
 function configure(uint unspent,bool shouldFail) external {spare=unspent;fail=shouldFail;}
 function exactOutputSingle(ISwapRouter.ExactOutputSingleParams calldata p) external returns(uint){
  require(!fail,"router failure");require(p.fee==expectedFee&&p.deadline==block.timestamp&&p.sqrtPriceLimitX96==0,"parameters");
  uint spent=p.amountInMaximum-spare;IERC20(p.tokenIn).safeTransferFrom(msg.sender,address(this),spent);
  GCZToken(p.tokenOut).mint(p.recipient,p.amountOut);return spent;
 }
 function exactInputSingle(ISwapRouter.ExactInputSingleParams calldata p) external returns(uint){
  require(!fail,"router failure");require(p.fee==expectedFee&&p.deadline==block.timestamp&&p.sqrtPriceLimitX96==0,"parameters");
  uint spent=p.amountIn-spare;uint output=2*spent+17;require(output>=p.amountOutMinimum,"slippage");
  IERC20(p.tokenIn).safeTransferFrom(msg.sender,address(this),spent);GCZToken(p.tokenOut).mint(p.recipient,output);return output;
 }
}
contract UniV3ExchangeParityTest {
 GCZVm constant vm=GCZVm(address(uint160(uint(keccak256("hevm cheat code")))));
 function deploy(bytes memory init) internal returns(address target){assembly{target:=create(0,add(init,32),mload(init))}}
 function make(bool fe,uint24 fee) internal returns(UniV3Exchange z,GCZToken coll,GCZToken bold,UniExchangeRouter router){
  coll=new GCZToken();bold=new GCZToken();router=new UniExchangeRouter(fee);
  bytes memory code=fe?vm.parseBytes(vm.readFile("build/UniV3Exchange.bin")):type(UniV3Exchange).creationCode;
  address target=deploy(bytes.concat(code,abi.encode(coll,bold,fee,router)));require(target.code.length>0&&target.code.length<=24576,"deploy");z=UniV3Exchange(target);
  coll.approve(target,type(uint).max);bold.approve(target,type(uint).max);coll.mint(address(this),1e36);bold.mint(address(this),1e36);coll.mint(target,123);bold.mint(target,456);
  require(address(z.collToken())==address(coll)&&address(z.boldToken())==address(bold)&&address(z.uniV3Router())==address(router)&&z.fee()==fee,"getters");
 }
 function run(bool fe,uint amount,uint spare,uint24 fee) internal returns(bytes32){
  (UniV3Exchange z,GCZToken coll,GCZToken bold,UniExchangeRouter router)=make(fe,fee);router.configure(spare,false);
  uint output=2*(amount-spare)+17;require(z.swapToBold(amount,output)==output);z.swapFromBold(amount,output);
  require(coll.balanceOf(address(z))==123&&bold.balanceOf(address(z))==456,"preserve balances");
  require(coll.allowance(address(z),address(router))==spare&&bold.allowance(address(z),address(router))==spare,"approvals");
  return keccak256(abi.encode(coll.balanceOf(address(this)),bold.balanceOf(address(this)),coll.balanceOf(address(router)),bold.balanceOf(address(router))));
 }
 function testBothDirectionsAndRefunds() public {require(run(true,1000,73,3000)==run(false,1000,73,3000));require(run(true,0,0,0)==run(false,0,0,0));}
 function testFuzzSwapAndRefund(uint96 raw,uint96 residue,uint24 fee) public {uint amount=uint(raw);uint spare=uint(residue)%(amount+1);require(run(true,amount,spare,fee)==run(false,amount,spare,fee));}
 function compare(address a,address b,bytes memory data) internal returns(bool){(bool ok,bytes memory x)=a.call(data);(bool success,bytes memory y)=b.call(data);require(ok==success&&keccak256(x)==keccak256(y),"return parity");return ok;}
 function testRollbackAndOptionalReturns() public {
  (UniV3Exchange a,GCZToken ca,,UniExchangeRouter ra)=make(true,3000);(UniV3Exchange b,GCZToken cb,,UniExchangeRouter rb)=make(false,3000);
  require(!compare(address(a),address(b),abi.encodeCall(a.swapToBold,(1000,99999))));
  ra.configure(0,true);rb.configure(0,true);require(!compare(address(a),address(b),abi.encodeCall(a.swapFromBold,(1000,0))));
  ra.configure(10,false);rb.configure(10,false);ca.setMode(2);cb.setMode(2);require(compare(address(a),address(b),abi.encodeCall(a.swapToBold,(1000,0))));
  require(ca.balanceOf(address(a))==123&&cb.balanceOf(address(b))==123);
 }
 function testConstructorFeeWidth() public {
  bytes memory f=vm.parseBytes(vm.readFile("build/UniV3Exchange.bin"));bytes memory s=type(UniV3Exchange).creationCode;
  bytes memory args=abi.encode(address(1),address(2),uint(1)<<24,address(3));
  require(deploy(bytes.concat(f,args))==address(0)&&deploy(bytes.concat(s,args))==address(0),"invalid fee");
 }
 function testFuzzPriceConversions(uint price,uint160 square,bool invert) public {
  (UniV3Exchange a,,,)=make(true,3000);(UniV3Exchange b,,,)=make(false,3000);
  compare(address(a),address(b),abi.encodeCall(a.priceToSqrtPriceX96,(price)));
  compare(address(a),address(b),abi.encodeCall(a.sqrtPriceX96ToPrice,(square)));
  compare(address(a),address(b),abi.encodeWithSelector(a.priceToSqrtPrice.selector,invert?address(1):address(2),invert?address(2):address(1),price));
 }
 function testConverterBoundariesAndNoncanonicalABI() public {
  UniPriceConverter a=UniPriceConverter(deploy(vm.parseBytes(vm.readFile("build/UniPriceConverter.bin"))));UniPriceConverter b=new UniPriceConverter();
  require(address(a).code.length>0);
  uint[8] memory prices=[uint(0),1,1e18,(uint(1)<<64)-1,uint(1)<<64,(uint(1)<<64)+1,115e57,type(uint).max];
  for(uint i;i<prices.length;i++)compare(address(a),address(b),abi.encodeCall(a.priceToSqrtPriceX96,(prices[i])));
  uint160[10] memory squares=[uint160(0),1,uint160(1)<<96,type(uint128).max,uint160(1)<<128,type(uint160).max,uint160(1054410137468020612616281021686),uint160(339116499156263406953227816330),uint160(339116499156263406953227816331),uint160(339116499156263406953227816332)];
  for(uint i;i<squares.length;i++)compare(address(a),address(b),abi.encodeCall(a.sqrtPriceX96ToPrice,(squares[i])));
  require(!compare(address(a),address(b),abi.encodePacked(a.sqrtPriceX96ToPrice.selector,bytes32(uint(1)<<160))));
 }
}
