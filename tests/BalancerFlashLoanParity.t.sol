// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {BalancerFlashLoan} from "../reference/bold/contracts/src/Zappers/Modules/FlashLoans/BalancerFlashLoan.sol";
import {IFlashLoanProvider} from "../reference/bold/contracts/src/Zappers/Interfaces/IFlashLoanProvider.sol";
import {IFlashLoanReceiver} from "../reference/bold/contracts/src/Zappers/Interfaces/IFlashLoanReceiver.sol";
import {ILeverageZapper} from "../reference/bold/contracts/src/Zappers/Interfaces/ILeverageZapper.sol";
import {IZapper} from "../reference/bold/contracts/src/Zappers/Interfaces/IZapper.sol";
import {GCZToken} from "./GasCompZapperParity.t.sol";
import {IERC20,SafeERC20} from "../reference/bold/contracts/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
interface BLVm {function etch(address,bytes calldata) external;function store(address,bytes32,bytes32) external;function load(address,bytes32) external view returns(bytes32);function prank(address) external;function readFile(string calldata) external view returns(string memory);function parseBytes(string calldata) external pure returns(bytes memory);}
contract BLVault {
 using SafeERC20 for IERC20;
 uint public fee;bool public skipCallback;bool public rejectLoan;
 function configure(uint f,bool skip,bool reject) external {fee=f;skipCallback=skip;rejectLoan=reject;}
 function flashLoan(address recipient,IERC20[] calldata tokens,uint[] calldata amounts,bytes calldata data) external {
  require(!rejectLoan,"vault failure");require(tokens.length==1&&amounts.length==1&&recipient==msg.sender,"loan parameters");
  if(skipCallback)return;
  uint beforeBalance=tokens[0].balanceOf(address(this));uint[] memory fees=new uint[](1);fees[0]=fee;
  tokens[0].safeTransfer(recipient,amounts[0]);BalancerFlashLoan(recipient).receiveFlashLoan(tokens,amounts,fees,data);
  require(tokens[0].balanceOf(address(this))==beforeBalance+fee,"repayment");
 }
}
contract BLReceiver is IFlashLoanReceiver {
 using SafeERC20 for IERC20;
 BalancerFlashLoan public provider;GCZToken public token;uint public amount;uint public effective;uint public operation;bytes32 public paramsHash;bool public reject;
 constructor(BalancerFlashLoan p,GCZToken t){provider=p;token=t;}
 function setReject(bool value) external {reject=value;}
 function run(uint a,IFlashLoanProvider.Operation op,bytes calldata data) external {amount=a;provider.makeFlashLoan(IERC20(address(token)),a,op,data);}
 function callback(uint op,uint net,bytes memory data) internal {
  require(address(provider.receiver())==address(0),"receiver not reset");require(!reject,"callback failure");
  operation=op;effective=net;paramsHash=keccak256(data);IERC20(address(token)).safeTransfer(address(provider),amount);
 }
 function receiveFlashLoanOnOpenLeveragedTrove(ILeverageZapper.OpenLeveragedTroveParams calldata p,uint net) external {callback(0,net,abi.encode(p));}
 function receiveFlashLoanOnCloseTroveFromCollateral(IZapper.CloseTroveParams calldata p,uint net) external {callback(1,net,abi.encode(p));}
 function receiveFlashLoanOnLeverUpTrove(ILeverageZapper.LeverUpTroveParams calldata p,uint net) external {callback(2,net,abi.encode(p));}
 function receiveFlashLoanOnLeverDownTrove(ILeverageZapper.LeverDownTroveParams calldata p,uint net) external {callback(3,net,abi.encode(p));}
}
contract BalancerFlashLoanParityTest {
 BLVm constant vm=BLVm(address(uint160(uint(keccak256("hevm cheat code")))));
 address constant VAULT=0xBA12222222228d8Ba445958a75a0704d566BF2C8;
 function make(bool fe) internal returns(BalancerFlashLoan p,GCZToken token,BLReceiver receiver){
  vm.etch(VAULT,type(BLVault).runtimeCode);BLVault(VAULT).configure(1,false,false);
  bytes memory code=fe?vm.parseBytes(vm.readFile("build/BalancerFlashLoan.bin")):type(BalancerFlashLoan).creationCode;
  address deployed;assembly{deployed:=create(0,add(code,32),mload(code))}require(deployed.code.length>0&&deployed.code.length<=24576,"deploy");p=BalancerFlashLoan(deployed);
  token=new GCZToken();receiver=new BLReceiver(p,token);token.mint(VAULT,1e36);token.mint(address(receiver),1e36);token.mint(deployed,123);
 }
 function params(uint op,uint amount) internal pure returns(bytes memory){
  if(op==0)return abi.encode(ILeverageZapper.OpenLeveragedTroveParams(address(1),2,3,amount,5,6,7,8,address(9),10,address(11),address(12),address(13)));
  if(op==1)return abi.encode(IZapper.CloseTroveParams(1,amount,3,address(4)));
  if(op==2)return abi.encode(ILeverageZapper.LeverUpTroveParams(1,amount,3,4));
  return abi.encode(ILeverageZapper.LeverDownTroveParams(1,amount,3));
 }
 function run(bool fe,uint amount,uint fee,uint op,uint mode) internal returns(bytes32){
  (BalancerFlashLoan p,GCZToken token,BLReceiver receiver)=make(fe);BLVault(VAULT).configure(fee,false,false);token.setMode(mode);
  bytes memory data=params(op,amount);receiver.run(amount,IFlashLoanProvider.Operation(op),bytes.concat(data,hex"abcdef"));
  require(receiver.operation()==op&&receiver.effective()==amount-fee&&receiver.paramsHash()==keccak256(data),"callback params");
  require(address(p.receiver())==address(0)&&token.balanceOf(address(p))==123,"reset and preserve balance");
  return keccak256(abi.encode(token.balanceOf(VAULT),token.balanceOf(address(receiver)),token.balanceOf(address(p)),receiver.effective(),receiver.paramsHash()));
 }
 function testAllCallbacksFeesAndOptionalTokenReturns() public {for(uint op;op<4;op++)for(uint mode;mode<2;mode++)require(run(true,1000,17,op,mode*2)==run(false,1000,17,op,mode*2),"parity");}
 function testFuzzLoanAccounting(uint96 raw,uint96 f,uint8 operation) public {uint amount=uint(raw);uint fee=uint(f)%(amount+1);uint op=uint(operation)%4;require(run(true,amount,fee,op,0)==run(false,amount,fee,op,0));}
 function compare(address a,address b,bytes memory data,address caller) internal returns(bool){vm.prank(caller);(bool ok,bytes memory x)=a.call(data);vm.prank(caller);(bool success,bytes memory y)=b.call(data);require(ok==success&&keccak256(x)==keccak256(y),"return parity");return ok;}
 function testCallerGuardsAndInvalidOperation() public {
  (BalancerFlashLoan a,,)=make(true);(BalancerFlashLoan b,,)=make(false);
  IERC20[] memory tokens=new IERC20[](0);uint[] memory amounts=new uint[](0);bytes memory data=abi.encodeCall(a.receiveFlashLoan,(tokens,amounts,amounts,hex""));
  require(!compare(address(a),address(b),data,address(this)));require(!compare(address(a),address(b),data,VAULT));
  data=abi.encodeWithSelector(a.makeFlashLoan.selector,address(123),uint(10),uint(4),hex"");require(!compare(address(a),address(b),data,address(this)));
  vm.store(address(a),0,bytes32(uint(uint160(address(this)))));vm.store(address(b),0,bytes32(uint(uint160(address(this)))));
  data=abi.encodeCall(a.receiveFlashLoan,(tokens,amounts,amounts,abi.encode(uint(4))));require(!compare(address(a),address(b),data,VAULT));
 }
 function testCallbackAndVaultRollback() public {
  (BalancerFlashLoan a,GCZToken ta,BLReceiver ra)=make(true);(BalancerFlashLoan b,GCZToken tb,BLReceiver rb)=make(false);
  ra.setReject(true);rb.setReject(true);bytes memory data=abi.encodeCall(ra.run,(1000,IFlashLoanProvider.Operation.LeverUpTrove,params(2,1000)));
  require(!compare(address(ra),address(rb),data,address(this)));require(ta.balanceOf(address(a))==123&&tb.balanceOf(address(b))==123&&address(a.receiver())==address(0)&&address(b.receiver())==address(0));
  BLVault(VAULT).configure(1,false,true);require(!compare(address(ra),address(rb),data,address(this)));
 }
 function testPersistentReceiverAndPackedSlot() public {
  (BalancerFlashLoan a,,BLReceiver ra)=make(true);(BalancerFlashLoan b,,BLReceiver rb)=make(false);BLVault(VAULT).configure(0,true,false);
  bytes32 high=bytes32(type(uint).max<<160);vm.store(address(a),0,high);vm.store(address(b),0,high);
  ra.run(1000,IFlashLoanProvider.Operation.LeverDownTrove,params(3,1000));rb.run(1000,IFlashLoanProvider.Operation.LeverDownTrove,params(3,1000));
  require(address(a.receiver())==address(ra)&&address(b.receiver())==address(rb));require(uint(vm.load(address(a),0))>>160==uint(high)>>160&&uint(vm.load(address(b),0))>>160==uint(high)>>160);
 }
 function testMemoryStructValidation() public {
  (BalancerFlashLoan a,,)=make(true);(BalancerFlashLoan b,,)=make(false);BLVault(VAULT).configure(0,true,false);
  for(uint op;op<4;op++){
   bytes memory p=params(op,1000);assembly{mstore(p,sub(mload(p),1))}bytes memory data=abi.encodeWithSelector(a.makeFlashLoan.selector,address(123),uint(1000),op,p);require(!compare(address(a),address(b),data,address(this)));
  }
  bytes memory p=params(0,1000);assembly{mstore(add(p,32),not(0))}
  require(!compare(address(a),address(b),abi.encodeWithSelector(a.makeFlashLoan.selector,address(123),uint(1000),uint(0),p),address(this)));
 }
 function testReceiveArrayBoundsFeeAndAddressValidation() public {
  (BalancerFlashLoan a,GCZToken token,BLReceiver ra)=make(true);(BalancerFlashLoan b,,BLReceiver rb)=make(false);token.mint(address(b),1000);
  for(uint mode;mode<7;mode++){
   vm.store(address(a),0,bytes32(uint(uint160(mode==4?address(0xdead):address(ra)))));vm.store(address(b),0,bytes32(uint(uint160(mode==4?address(0xdead):address(rb)))));
   IERC20[] memory tokens=new IERC20[](mode==0?0:1);if(tokens.length>0)tokens[0]=IERC20(address(token));
   uint[] memory amounts=new uint[](mode==1?0:1);if(amounts.length>0)amounts[0]=10;
   uint[] memory fees=new uint[](mode==2?0:1);if(fees.length>0)fees[0]=mode==3?11:1;
   bytes memory userData=bytes.concat(abi.encode(uint(2)),params(2,10));
   if(mode==5){assembly{mstore(add(tokens,32),not(0))}}
   if(mode==6){userData=bytes.concat(abi.encode(uint(1)),params(1,10));assembly{mstore(add(userData,160),not(0))}}
   bytes memory data=abi.encodeCall(a.receiveFlashLoan,(tokens,amounts,fees,userData));
   // abi.encode cleans typed addresses, so dirty the encoded token word itself.
   if(mode==5)assembly{let offset:=mload(add(data,36)) mstore(add(add(data,68),offset),not(0))}
   require(!compare(address(a),address(b),data,VAULT));
  }
 }
}
