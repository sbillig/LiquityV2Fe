// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {Governance} from "../reference/bold/contracts/lib/V2-gov/src/Governance.sol";
import {IGovernance} from "../reference/bold/contracts/lib/V2-gov/src/interfaces/IGovernance.sol";
import {UPToken} from "./UserProxyParity.t.sol";
import {GAStaking,GAVm} from "./GovernanceActionsParity.t.sol";
import {BILogVm} from "./BribeInitiativeParity.t.sol";
contract GVInitiative {
 uint public calls;bytes32 public argsHash;bytes32 public storedHash;
 function reset() external {calls=0;argsHash=0;storedHash=0;}
 function onAfterAllocateLQTY(uint epoch,address user,IGovernance.UserState calldata us,IGovernance.Allocation calldata allocation,IGovernance.InitiativeState calldata state) external {
  calls++;argsHash=keccak256(abi.encode(epoch,user,us,allocation,state));
  (uint a,uint b,uint c,uint d)=Governance(msg.sender).userStates(user);storedHash=keccak256(abi.encode(a,b,c,d));
  address[] memory none=new address[](0);(bool ok,bytes memory reason)=msg.sender.call(abi.encodeWithSignature("resetAllocations(address[],bool)",none,false));
  require(!ok&&keccak256(reason)==keccak256(abi.encodeWithSignature("ReentrancyGuardReentrantCall()")),"guard");
 }
}
contract GovernanceVotingParityTest {
 GAVm constant vm=GAVm(address(uint160(uint(keccak256("hevm cheat code")))));
 GAStaking internal lastStaking;
 address constant A=address(777);address constant B=address(778);
 function put(address p,uint slot,uint value) internal {vm.store(p,bytes32(slot),bytes32(value));}
 function map(address a,uint root) internal pure returns(uint){return uint(keccak256(abi.encode(a,root)));}
 function feInit(UPToken bold,GAStaking staking) internal virtual returns(bytes memory){return bytes.concat(vm.parseBytes(vm.readFile("build/GovernanceVotingHarness.bin")),abi.encode(bold,staking,uint(7),uint(1e16)));}
 function make(bool fe,uint qty,uint offset) internal virtual returns(Governance p){
  vm.warp(1000);GAStaking staking=new GAStaking();lastStaking=staking;staking.set(qty);UPToken bold=new UPToken();
  if(fe){bytes memory init=feInit(bold,staking);address a;assembly{a:=create(0,add(init,32),mload(init))}require(a.code.length>0);p=Governance(a);}
  else {IGovernance.Configuration memory cfg=IGovernance.Configuration(7,1e16,2e18,4,1e16,1e18,5e18,1000,100,90);p=new Governance(address(1),address(2),address(staking),address(bold),cfg,address(this),new address[](0));}
  vm.warp(1300);put(address(p),4,3);put(address(p),map(address(this),8),qty);put(address(p),map(address(this),8)+1,offset);
  for(uint i;i<2;i++){address target=i==0?A:B;vm.etch(target,type(GVInitiative).runtimeCode);GVInitiative(target).reset();put(address(p),map(target,11),1);put(address(p),map(target,5)+1,3);put(address(p),map(target,9)+4,3);}
 }
 function stateHash(address p) internal view returns(bytes32 h){
  for(uint i;i<4;i++)h=keccak256(abi.encode(h,vm.load(p,bytes32(map(address(this),8)+i))));
  for(uint i=6;i<8;i++)h=keccak256(abi.encode(h,vm.load(p,bytes32(i))));
  for(uint j;j<2;j++){address t=j==0?A:B;for(uint i;i<5;i++)h=keccak256(abi.encode(h,vm.load(p,bytes32(map(t,9)+i)),vm.load(p,bytes32(map(t,map(address(this),10))+i))));h=keccak256(abi.encode(h,GVInitiative(t).calls(),GVInitiative(t).argsHash(),GVInitiative(t).storedHash()));}
 }
 function logsHash(address p) internal returns(bytes32 h){BILogVm.Entry[] memory e=BILogVm(address(vm)).getRecordedLogs();for(uint i;i<e.length;i++){require(e[i].emitter==p,"emitter");h=keccak256(abi.encode(h,e[i].topics,e[i].data));}}
 function run(bool fe,uint qty,uint offset,bool reverse) internal returns(bytes32 h){
  Governance p=make(fe,qty,offset);address[] memory targets=new address[](2);targets[0]=reverse?B:A;targets[1]=reverse?A:B;
  int[] memory votes=new int[](2);int[] memory vetos=new int[](2);votes[0]=int(qty/3);vetos[1]=int(qty/4);
  BILogVm(address(vm)).recordLogs();p.allocateLQTY(new address[](0),targets,votes,vetos);
  require(GVInitiative(targets[0]).calls()==1&&GVInitiative(targets[1]).calls()==0,"veto hook suppression");
  require(GVInitiative(targets[0]).storedHash()==keccak256(abi.encode(qty,offset,uint(0),uint(0))),"cached user state during hook");
  h=keccak256(abi.encode(stateHash(address(p)),logsHash(address(p))));
  vm.warp(1391);votes[0]-=1;vetos[1]+=1;BILogVm(address(vm)).recordLogs();p.allocateLQTY(targets,targets,votes,vetos);
  h=keccak256(abi.encode(h,stateHash(address(p)),logsHash(address(p))));
  BILogVm(address(vm)).recordLogs();p.resetAllocations(targets,true);
  (uint unallocated,uint off,uint allocated,uint allocatedOff)=p.userStates(address(this));require(unallocated==qty&&off==offset&&allocated==0&&allocatedOff==0,"reset restores exact offsets");
  require(vm.load(address(p),bytes32(0))==bytes32(uint(1)),"guard restored");
  h=keccak256(abi.encode(h,stateHash(address(p)),logsHash(address(p))));
 }
 function testFuzzAllocationResetRoundingAndCutoff(uint64 raw,uint64 offset,bool reverse) public {uint qty=uint(raw)+12;uint off=qty*1000+uint(offset)%qty;require(run(true,qty,off,reverse)==run(false,qty,off,reverse),"voting parity");}
 function compare(Governance a,Governance b,bytes memory data) internal returns(bool){(bool ok,bytes memory x)=address(a).call(data);(bool success,bytes memory y)=address(b).call(data);require(ok==success&&keccak256(x)==keccak256(y),"error parity");return ok;}
 function testValidationResetRequirementAndLateVoteLimits() public {
  Governance a=make(true,100,100001);Governance b=make(false,100,100001);
  address[] memory none=new address[](0);address[] memory targets=new address[](1);targets[0]=A;int[] memory votes=new int[](1);int[] memory vetos=new int[](1);
  require(!compare(a,b,abi.encodeCall(a.allocateLQTY,(none,targets,new int[](0),vetos))),"length");
  votes[0]=-1;require(!compare(a,b,abi.encodeCall(a.allocateLQTY,(none,targets,votes,vetos))),"negative");
  votes[0]=0;require(!compare(a,b,abi.encodeCall(a.allocateLQTY,(none,targets,votes,vetos))),"no-op");
  votes[0]=1;vetos[0]=1;require(!compare(a,b,abi.encodeCall(a.allocateLQTY,(none,targets,votes,vetos))),"vote and veto");
  vetos[0]=0;votes[0]=10;require(compare(a,b,abi.encodeCall(a.allocateLQTY,(none,targets,votes,vetos))),"initial vote");
  require(!compare(a,b,abi.encodeCall(a.allocateLQTY,(none,targets,votes,vetos))),"reset required");
  vm.warp(1391);votes[0]=11;require(!compare(a,b,abi.encodeCall(a.allocateLQTY,(targets,targets,votes,vetos))),"late increase");
  address[] memory added=new address[](1);added[0]=B;votes[0]=1;require(!compare(a,b,abi.encodeCall(a.allocateLQTY,(targets,added,votes,vetos))),"late new vote");
  votes[0]=0;vetos[0]=1;require(compare(a,b,abi.encodeCall(a.allocateLQTY,(targets,added,votes,vetos))),"late new veto allowed");
  require(!compare(a,b,abi.encodeCall(a.resetAllocations,(none,true))),"complete reset required");
  require(compare(a,b,abi.encodeCall(a.resetAllocations,(added,true))),"complete reset");
 }

 function testDisabledResetAndFinalStakeCheckRollback() public {
  Governance a=make(true,100,100001);GAStaking sa=lastStaking;Governance b=make(false,100,100001);GAStaking sb=lastStaking;
  address[] memory targets=new address[](1);targets[0]=A;address[] memory none=new address[](0);int[] memory votes=new int[](1);votes[0]=10;int[] memory vetos=new int[](1);
  bytes memory data=abi.encodeCall(a.allocateLQTY,(none,targets,votes,vetos));
  sa.set(0);sb.set(0);bytes32 oldA=stateHash(address(a));bytes32 oldB=stateHash(address(b));
  require(!compare(a,b,data),"stake cap");require(stateHash(address(a))==oldA&&stateHash(address(b))==oldB,"state and hook rollback");
  sa.set(100);sb.set(100);require(compare(a,b,data),"allocate");
  put(address(a),map(A,11),type(uint).max);put(address(b),map(A,11),type(uint).max);
  put(address(a),6,0);put(address(a),7,0);put(address(b),6,0);put(address(b),7,0);
  require(compare(a,b,abi.encodeCall(a.resetAllocations,(targets,true))),"disabled withdrawal skips global subtraction");
  require(!compare(a,b,data),"disabled positive allocation rejected");
  address[] memory duplicate=new address[](2);duplicate[0]=A;duplicate[1]=A;
  require(!compare(a,b,abi.encodeCall(a.resetAllocations,(duplicate,false))),"duplicate reset");
 }

}
