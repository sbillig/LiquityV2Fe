// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {CurveExchange} from "../reference/bold/contracts/src/Zappers/Modules/Exchanges/CurveExchange.sol";
import {GCZToken,GCZVm} from "./GasCompZapperParity.t.sol";
import {IERC20,SafeERC20} from "../reference/bold/contracts/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
contract CurveExchangePool {
 using SafeERC20 for IERC20;
 GCZToken public coll;GCZToken public bold;uint public spare;bool public fail;
 constructor(GCZToken c,GCZToken b){coll=c;bold=b;}
 function configure(uint unspent,bool shouldFail) external {spare=unspent;fail=shouldFail;}
 function exchange(uint i,uint j,uint amount,uint minimum) external returns(uint){
  require(!fail,"pool failure");require(i<2&&j==1-i,"indices");
  uint spent=amount-spare;uint output=2*spent+17;require(output>=minimum,"slippage");
  GCZToken input=i==0?coll:bold;GCZToken out=i==0?bold:coll;
  IERC20(address(input)).safeTransferFrom(msg.sender,address(this),spent);
  out.mint(address(this),output);IERC20(address(out)).safeTransfer(msg.sender,output);return output;
 }
}
contract CurveExchangeParityTest {
 GCZVm constant vm=GCZVm(address(uint160(uint(keccak256("hevm cheat code")))));
 function make(bool fe) internal returns(CurveExchange z,GCZToken coll,GCZToken bold,CurveExchangePool pool){
  coll=new GCZToken();bold=new GCZToken();pool=new CurveExchangePool(coll,bold);
  bytes memory code=fe?vm.parseBytes(vm.readFile("build/CurveExchange.bin")):type(CurveExchange).creationCode;
  bytes memory init=bytes.concat(code,abi.encode(coll,bold,pool,uint(0),uint(1)));address target;assembly{target:=create(0,add(init,32),mload(init))}
  require(target.code.length>0&&target.code.length<=24576,"deploy");z=CurveExchange(target);
  coll.approve(target,type(uint).max);bold.approve(target,type(uint).max);
  coll.mint(address(this),1e36);bold.mint(address(this),1e36);
  coll.mint(target,123);bold.mint(target,456);
  require(address(z.collToken())==address(coll)&&address(z.boldToken())==address(bold)&&address(z.curvePool())==address(pool));
  require(z.COLL_TOKEN_INDEX()==0&&z.BOLD_TOKEN_INDEX()==1);
 }
 function run(bool fe,uint amount,uint spare) internal returns(bytes32){
  (CurveExchange z,GCZToken coll,GCZToken bold,CurveExchangePool pool)=make(fe);pool.configure(spare,false);
  uint output=2*(amount-spare)+17;
  require(z.swapToBold(amount,output)==output,"swap output");z.swapFromBold(amount,output);
  require(coll.balanceOf(address(z))==123&&bold.balanceOf(address(z))==456,"preexisting balances");
  require(coll.allowance(address(z),address(pool))==spare&&bold.allowance(address(z),address(pool))==spare,"approvals");
  return keccak256(abi.encode(coll.balanceOf(address(this)),bold.balanceOf(address(this)),coll.balanceOf(address(pool)),bold.balanceOf(address(pool))));
 }
 function testBothDirectionsAndUnspentInput() public {require(run(true,1000,71)==run(false,1000,71));require(run(true,0,0)==run(false,0,0));}
 function testFuzzSwapAndRefund(uint96 raw,uint96 residue) public {uint amount=uint(raw);uint spare=uint(residue)%(amount+1);require(run(true,amount,spare)==run(false,amount,spare),"parity");}
 function compare(CurveExchange a,CurveExchange b,bytes memory data) internal returns(bool){(bool ok,bytes memory x)=address(a).call(data);(bool success,bytes memory y)=address(b).call(data);require(ok==success&&keccak256(x)==keccak256(y),"return parity");return ok;}
 function testSlippageAndPoolFailureRollback() public {
  (CurveExchange a,GCZToken ca,GCZToken ba,CurveExchangePool pa)=make(true);(CurveExchange b,GCZToken cb,GCZToken bb,CurveExchangePool pb)=make(false);
  require(!compare(a,b,abi.encodeCall(a.swapFromBold,(1000,9999))));require(!compare(a,b,abi.encodeCall(a.swapToBold,(1000,9999))));
  pa.configure(0,true);pb.configure(0,true);require(!compare(a,b,abi.encodeCall(a.swapToBold,(1000,0))));
  require(ca.balanceOf(address(a))==123&&cb.balanceOf(address(b))==123&&ba.balanceOf(address(a))==456&&bb.balanceOf(address(b))==456,"rollback");
 }
 function testOptionalCollateralReturnsAndFalseRollback() public {
  (CurveExchange a,GCZToken ca,,)=make(true);(CurveExchange b,GCZToken cb,,)=make(false);
  ca.setMode(2);cb.setMode(2);require(compare(a,b,abi.encodeCall(a.swapToBold,(1000,0))));require(compare(a,b,abi.encodeCall(a.swapFromBold,(1000,0))));
  ca.setMode(1);cb.setMode(1);require(!compare(a,b,abi.encodeCall(a.swapToBold,(1000,0))));
  require(ca.balanceOf(address(a))==123&&cb.balanceOf(address(b))==123,"false rollback");
 }
}
