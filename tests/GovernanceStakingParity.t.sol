// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {Governance} from "../reference/bold/contracts/lib/V2-gov/src/Governance.sol";
import {IGovernance} from "../reference/bold/contracts/lib/V2-gov/src/interfaces/IGovernance.sol";
import {PermitParams} from "../reference/bold/contracts/lib/V2-gov/src/utils/Types.sol";
import {UPToken,UPStaking} from "./UserProxyParity.t.sol";
import {GSVm} from "./GovernanceSnapshotParity.t.sol";
contract GSRewardReceiver {
 address public target;bool public reject;bytes public reason;
 constructor(address t,bool r){target=t;reject=r;}
 receive() external payable {
  require(!reject,"reject ETH");(bool ok,bytes memory data)=target.call(abi.encodeWithSignature("depositLQTY(uint256)",uint(1)));
  require(!ok,"reentrant call succeeded");reason=data;
 }
}
contract GovernanceStakingParityTest {
 GSVm constant vm=GSVm(address(uint160(uint(keccak256("hevm cheat code")))));
 function make(bool fe) internal virtual returns(Governance p,UPToken lqty,UPToken lusd,UPStaking v1){
  vm.warp(1000);lqty=new UPToken();lusd=new UPToken();v1=new UPStaking(lqty,lusd);vm.deal(address(v1),1e24);
  if(fe){bytes memory init=bytes.concat(vm.parseBytes(vm.readFile("build/GovernanceStakingHarness.bin")),abi.encode(lqty,lusd,v1));address a;assembly{a:=create(0,add(init,32),mload(init))}require(a.code.length>0);p=Governance(a);}
  else {IGovernance.Configuration memory cfg=IGovernance.Configuration(0,1e16,2e18,4,1e16,1e18,5e18,1000,100,90);p=new Governance(address(lqty),address(lusd),address(v1),address(4),cfg,address(this),new address[](0));}
 }
 function stateHash(Governance p) internal view returns(bytes32){(uint a,uint b,uint c,uint d)=p.userStates(address(this));return keccak256(abi.encode(a,b,c,d));}
 function run(bool fe,uint amount,uint withdrawAmount,bool send) internal returns(bytes32){
  (Governance p,UPToken lqty,UPToken lusd,UPStaking v1)=make(fe);
  address recipient=address(1234);vm.deal(recipient,0);lqty.mint(address(this),amount*3);
  p.depositLQTY(amount);vm.warp(2000);p.depositLQTY(amount*2,send,recipient);
  address proxy=p.deriveUserProxyAddress(address(this));require(proxy.code.length==45&&v1.stakes(proxy)==amount*3,"proxy stake");
  require(stateHash(p)==keccak256(abi.encode(amount*3,amount*5000,uint(0),uint(0))),"offset accumulation");
  p.withdrawLQTY(withdrawAmount,false,recipient);
  uint offset=withdrawAmount<amount*3?amount*5000-withdrawAmount*(amount*5000)/(amount*3):0;
  require(stateHash(p)==keccak256(abi.encode(amount*3-withdrawAmount,offset,uint(0),uint(0))),"offset decrease");
  lqty.mint(proxy,7);bytes32 beforeState=stateHash(p);p.claimFromStakingV1(recipient);require(stateHash(p)==beforeState,"claim leaves trackers");
  require(v1.stakes(proxy)==amount*3-withdrawAmount&&lqty.balanceOf(recipient)==withdrawAmount+7,"balances");
  require(vm.load(address(p),bytes32(0))==bytes32(uint(1)),"guard reset");
  return keccak256(abi.encode(beforeState,lqty.balanceOf(recipient),lusd.balanceOf(recipient),recipient.balance));
 }
 function testFuzzDepositWithdrawalAndRewards(uint96 raw,uint96 withdrawal,bool send) public {uint amount=uint(raw)+1;uint w=uint(withdrawal)%(amount*3+1);require(run(true,amount,w,send)==run(false,amount,w,send),"staking parity");}
 function compare(address a,address b,bytes memory data) internal returns(bool){(bool ok,bytes memory x)=a.call(data);(bool success,bytes memory y)=b.call(data);require(ok==success&&keccak256(x)==keccak256(y),"call parity");return ok;}
 function testGuardsAndLazyPermitValidation() public {
  (Governance a,UPToken ta,,)=make(true);(Governance b,UPToken tb,,)=make(false);
  require(!compare(address(a),address(b),abi.encodeWithSignature("withdrawLQTY(uint256)",uint(0))),"missing proxy");
  require(!compare(address(a),address(b),abi.encodeWithSignature("depositLQTY(uint256)",uint(0))),"zero amount");
  ta.mint(address(this),100);tb.mint(address(this),100);ta.setPermitFails(true);tb.setPermitFails(true);
  PermitParams memory params=PermitParams(address(this),address(0),0,0,27,bytes32(0),bytes32(0));
  bytes memory data=abi.encodeWithSignature("depositLQTYViaPermit(uint256,(address,address,uint256,uint256,uint8,bytes32,bytes32))",uint(10),params);
  require(compare(address(a),address(b),data),"permit failure ignored");
  require(stateHash(a)==stateHash(b),"permit trackers");
  for(uint i;i<3;i++){
   data=abi.encodeWithSignature("depositLQTYViaPermit(uint256,(address,address,uint256,uint256,uint8,bytes32,bytes32),bool,address)",uint(10),params,false,address(this));
   uint index=i==2?5:i+1;assembly{mstore(add(add(data,36),mul(index,32)),not(0))}
   require(!compare(address(a),address(b),data),"dirty permit");require(stateHash(a)==stateHash(b),"rollback");
  }
  vm.store(address(a),bytes32(0),bytes32(uint(2)));vm.store(address(b),bytes32(0),bytes32(uint(2)));
  require(!compare(address(a),address(b),abi.encodeWithSignature("depositLQTY(uint256)",uint(0))),"reentrant before amount");
 }
 function callbackRun(bool fe,bool reject) internal returns(bytes32){
  (Governance p,UPToken lqty,,UPStaking v1)=make(fe);GSRewardReceiver receiver=new GSRewardReceiver(address(p),reject);
  lqty.mint(address(this),50);address proxy=p.deriveUserProxyAddress(address(this));
  (bool ok,bytes memory data)=address(p).call(abi.encodeWithSignature("depositLQTY(uint256,bool,address)",uint(50),true,receiver));
  require(ok!=reject,"callback outcome");
  if(reject){require(proxy.code.length==0&&v1.stakes(proxy)==0&&lqty.balanceOf(address(this))==50,"deployment and balance rollback");require(stateHash(p)==keccak256(abi.encode(uint(0),uint(0),uint(0),uint(0))),"tracker rollback");}
  else require(keccak256(receiver.reason())==keccak256(abi.encodeWithSignature("ReentrancyGuardReentrantCall()")),"guarded callback");
  require(vm.load(address(p),bytes32(0))==bytes32(uint(1)),"guard restored");
  return keccak256(abi.encode(ok,data,stateHash(p),address(receiver).balance));
 }
 function testCallbackReentrancyAndFirstDepositRollback() public {
  require(callbackRun(true,false)==callbackRun(false,false),"reentry parity");require(callbackRun(true,true)==callbackRun(false,true),"rollback parity");
 }

}
