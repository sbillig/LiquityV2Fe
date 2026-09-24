// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {Governance} from "../reference/bold/contracts/lib/V2-gov/src/Governance.sol";
import {IGovernance} from "../reference/bold/contracts/lib/V2-gov/src/interfaces/IGovernance.sol";
import {BILogVm} from "./BribeInitiativeParity.t.sol";
import {UPToken} from "./UserProxyParity.t.sol";
import {GSVm} from "./GovernanceSnapshotParity.t.sol";
interface GAVm is GSVm {function etch(address,bytes calldata) external;}
contract GAStaking {uint public qty;function set(uint q) external {qty=q;}function stakes(address) external view returns(uint){return qty;}}
contract GAInitiative {
 bool public fail;uint public kind;uint public epoch;uint public amount;
 function reset(bool f) external {fail=f;kind=0;epoch=0;amount=0;}
 function check() internal {
  require(!fail,"hook failure");
  (bool ok,bytes memory data)=msg.sender.call(abi.encodeWithSignature("claimForInitiative(address)",address(this)));
  require(!ok&&keccak256(data)==keccak256(abi.encodeWithSignature("ReentrancyGuardReentrantCall()")),"hook reentrancy guard");
 }
 function onRegisterInitiative(uint e) external {check();kind=1;epoch=e;}
 function onUnregisterInitiative(uint e) external {check();kind=2;epoch=e;}
 function onClaimForInitiative(uint e,uint a) external {check();kind=3;epoch=e;amount=a;}
}
contract GovernanceActionsParityTest {
 GAVm constant vm=GAVm(address(uint160(uint(keccak256("hevm cheat code")))));
 address constant TARGET=address(777);
 function feInit(UPToken bold,GAStaking staking) internal virtual returns(bytes memory){return bytes.concat(vm.parseBytes(vm.readFile("build/GovernanceActionsHarness.bin")),abi.encode(bold,staking,uint(7),uint(1e16)));}
 function make(bool fe,bool fail) internal virtual returns(Governance p,UPToken bold,GAStaking staking){
  vm.warp(1000);vm.etch(TARGET,type(GAInitiative).runtimeCode);GAInitiative(TARGET).reset(fail);bold=new UPToken();staking=new GAStaking();
  if(fe){bytes memory init=feInit(bold,staking);address a;assembly{a:=create(0,add(init,32),mload(init))}require(a.code.length>0);p=Governance(a);}
  else {IGovernance.Configuration memory cfg=IGovernance.Configuration(7,1e16,2e18,4,1e16,1e18,5e18,1000,100,90);p=new Governance(address(1),address(2),address(staking),address(bold),cfg,address(this),new address[](0));}
  vm.warp(1300);BILogVm(address(vm)).recordLogs();
 }
 function logsHash(address emitter) internal returns(bytes32 h){BILogVm.Entry[] memory entries=BILogVm(address(vm)).getRecordedLogs();for(uint i;i<entries.length;i++){require(entries[i].emitter==emitter,"event emitter");h=keccak256(abi.encode(h,entries[i].topics,entries[i].data));}}
 function slot(uint root) internal pure returns(uint){return uint(keccak256(abi.encode(TARGET,root)));}
 function put(address p,uint s,uint v) internal {vm.store(p,bytes32(s),bytes32(v));}
 function load(address p,uint s) internal view returns(uint){return uint(vm.load(p,bytes32(s)));}
 function base(address p) internal {put(p,2,10e18);put(p,3,100);put(p,4,3);put(p,slot(5),50);put(p,slot(5)+1,3);put(p,slot(11),1);}
 function reg(bool fe,bool fail,bool enough) internal returns(bytes32){
  (Governance p,UPToken bold,GAStaking staking)=make(fe,fail);put(address(p),2,10e18);put(address(p),3,10000);put(address(p),4,3);
  bold.mint(address(this),7);staking.set(enough?1:0);
  (bool ok,bytes memory data)=address(p).call(abi.encodeCall(p.registerInitiative,(TARGET)));require(ok==enough,"registration outcome");
  require(load(address(p),slot(11))==(enough?4:0)&&load(address(p),slot(9)+4)==(enough?3:0),"registration state");
  require(bold.balanceOf(address(p))==(enough?7:0),"fee atomicity");require(load(address(p),0)==1,"guard");require(GAInitiative(TARGET).kind()==(enough&&!fail?1:0),"registration hook");
  return keccak256(abi.encode(ok,data,bold.balanceOf(address(this)),GAInitiative(TARGET).kind(),GAInitiative(TARGET).epoch(),logsHash(address(p))));
 }
 function testRegistrationFeeVotingPowerAndHookFailure() public {for(uint f;f<2;f++)for(uint e;e<2;e++)require(reg(true,f==1,e==1)==reg(false,f==1,e==1),"registration parity");}
 function claim(bool fe,bool fail,uint available) internal returns(bytes32){
  (Governance p,UPToken bold,)=make(fe,fail);base(address(p));bold.mint(address(p),available);
  uint amount=p.claimForInitiative(TARGET);uint expected=available<5e18?available:5e18;require(amount==expected,"cap");
  require(load(address(p),slot(9)+4)==3&&load(address(p),0)==1,"claim state");
  require(p.claimForInitiative(TARGET)==0,"second claim");require(GAInitiative(TARGET).kind()==(fail?0:3),"claim hook");
  return keccak256(abi.encode(amount,bold.balanceOf(TARGET),bold.balanceOf(address(p)),GAInitiative(TARGET).kind(),GAInitiative(TARGET).epoch(),GAInitiative(TARGET).amount(),logsHash(address(p))));
 }
 function testFuzzClaimCapAndHookFailure(uint96 amount,bool fail) public {require(claim(true,fail,amount)==claim(false,fail,amount),"claim parity");}
 function unregister(bool fe,bool fail,bool inconsistent) internal returns(bytes32){
  (Governance p,,)=make(fe,fail);base(address(p));vm.warp(2000);put(address(p),4,10);put(address(p),slot(5),0);put(address(p),slot(5)+1,10);
  put(address(p),6,inconsistent?3:100);put(address(p),7,200);put(address(p),slot(9),4);put(address(p),slot(9)+1,5);
  (bool ok,bytes memory data)=address(p).call(abi.encodeCall(p.unregisterInitiative,(TARGET)));require(ok!=inconsistent,"unregister outcome");
  require(load(address(p),slot(11))==(inconsistent?1:type(uint).max),"disable");require(load(address(p),0)==1,"guard");require(GAInitiative(TARGET).kind()==(!inconsistent&&!fail?2:0),"unregister hook");
  return keccak256(abi.encode(ok,data,load(address(p),6),load(address(p),7),GAInitiative(TARGET).kind(),GAInitiative(TARGET).epoch(),logsHash(address(p))));
 }
 function testUnregistrationAssertionsAndHookFailure() public {for(uint f;f<2;f++)for(uint inconsistent;inconsistent<2;inconsistent++)require(unregister(true,f==1,inconsistent==1)==unregister(false,f==1,inconsistent==1),"unregister parity");}
}
