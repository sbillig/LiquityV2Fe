// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {BribeInitiative} from "../reference/bold/contracts/lib/V2-gov/src/BribeInitiative.sol";
import {IGovernance} from "../reference/bold/contracts/lib/V2-gov/src/interfaces/IGovernance.sol";
import {IBribeInitiative} from "../reference/bold/contracts/lib/V2-gov/src/interfaces/IBribeInitiative.sol";
import {UPVm,UPToken} from "./UserProxyParity.t.sol";
interface BILogVm {
 struct Entry {bytes32[] topics;bytes data;address emitter;}
 function recordLogs() external;
 function getRecordedLogs() external returns(Entry[] memory);
 function load(address,bytes32) external view returns(bytes32);
}
contract BribeGovMock {
 uint public constant EPOCH_START=100;uint public constant EPOCH_DURATION=100;uint public epoch=1;
 function setEpoch(uint e) external {epoch=e;}
 function allocate(BribeInitiative p,address user,uint qty,uint offset,uint total,uint totalOffset) external {
  p.onAfterAllocateLQTY(epoch,user,IGovernance.UserState(0,0,0,0),IGovernance.Allocation(qty,offset,0,0,epoch),IGovernance.InitiativeState(total,totalOffset,0,0,0));
 }
}
contract BribeInitiativeParityTest {
 UPVm constant vm=UPVm(address(uint160(uint(keccak256("hevm cheat code")))));
 function make(bool fe) internal returns(BribeInitiative p,BribeGovMock gov,UPToken bold,UPToken token){
  gov=new BribeGovMock();bold=new UPToken();token=new UPToken();
  bytes memory code=fe?vm.parseBytes(vm.readFile("build/BribeInitiative.bin")):type(BribeInitiative).creationCode;
  bytes memory init=bytes.concat(code,abi.encode(gov,bold,token));address a;assembly{a:=create(0,add(init,32),mload(init))}require(a.code.length>0&&a.code.length<=24576,"deploy");p=BribeInitiative(a);
 }
 function run(bool fe,uint amount,uint qty) internal returns(bytes32){
  (BribeInitiative p,BribeGovMock gov,UPToken bold,UPToken token)=make(fe);
  BILogVm(address(vm)).recordLogs();
  bold.mint(address(this),amount);token.mint(address(this),amount+1);p.depositBribe(amount,amount+1,1);
  address alice=address(1001);address bob=address(1002);
  gov.allocate(p,alice,qty,qty*100,qty*3,qty*300);gov.allocate(p,bob,qty*2,qty*200,qty*3,qty*300);
  require(p.getMostRecentTotalEpoch()==1&&p.getMostRecentUserEpoch(alice)==1,"epochs");
  gov.setEpoch(2);
  IBribeInitiative.ClaimData[] memory data=new IBribeInitiative.ClaimData[](1);data[0]=IBribeInitiative.ClaimData(1,1,1);
  uint[4] memory rewards;vm.prank(alice);(rewards[0],rewards[1])=p.claimBribes(data);vm.prank(bob);(rewards[2],rewards[3])=p.claimBribes(data);
  require(rewards[0]+rewards[2]==amount&&rewards[1]+rewards[3]==amount+1,"conservation");
  require(bold.balanceOf(address(p))==0&&token.balanceOf(address(p))==0,"swept");
  require(p.claimedBribeAtEpoch(alice,1)&&p.claimedBribeAtEpoch(bob,1),"claimed");
  (uint rb,uint rt,uint votes)=p.bribeByEpoch(1);require(rb==0&&rt==0&&votes==qty*300,"accounting");
  vm.prank(alice);(bool ok,bytes memory reason)=address(p).call(abi.encodeCall(p.claimBribes,(data)));require(!ok&&keccak256(reason)==keccak256(abi.encodeWithSignature("Error(string)","BribeInitiative: already-claimed")),"duplicate");
  return keccak256(abi.encode(rewards,votes,logsHash(address(p))));
 }
 function logsHash(address emitter) internal returns(bytes32 h){
  BILogVm.Entry[] memory entries=BILogVm(address(vm)).getRecordedLogs();
  for(uint i;i<entries.length;i++){require(entries[i].emitter==emitter,"event emitter");h=keccak256(abi.encode(h,entries[i].topics,entries[i].data));}
 }
 function testFuzzClaimDistribution(uint96 amount,uint64 quantity) public {uint qty=uint(quantity)+1;require(run(true,uint(amount)+1,qty)==run(false,uint(amount)+1,qty),"parity");}
 function compare(address a,address b,bytes memory data,address sender) internal returns(bool){vm.prank(sender);(bool ok,bytes memory x)=a.call(data);vm.prank(sender);(bool success,bytes memory y)=b.call(data);require(ok==success&&keccak256(x)==keccak256(y),"call parity");return ok;}
 function history(BribeInitiative p,BribeGovMock gov) internal {
  gov.allocate(p,address(this),3,4,7,8);gov.allocate(p,address(this),5,6,9,10);
  gov.setEpoch(3);gov.allocate(p,address(this),7,8,11,12);
 }
 function testAllocationHistoryAndRevertOrder() public {
  (BribeInitiative a,BribeGovMock ga,UPToken ba,UPToken ta)=make(true);
  (BribeInitiative b,BribeGovMock gb,UPToken bb,UPToken tb)=make(false);
  history(a,ga);history(b,gb);
  for(uint epoch;epoch<5;epoch++){
   compare(address(a),address(b),abi.encodeCall(a.totalLQTYAllocatedByEpoch,(epoch)),address(this));
   compare(address(a),address(b),abi.encodeCall(a.lqtyAllocatedByUserAtEpoch,(address(this),epoch)),address(this));
  }
  require(!compare(address(a),address(b),abi.encodeCall(a.onRegisterInitiative,(1)),address(this)),"auth");
  require(!compare(address(a),address(b),abi.encodeCall(a.depositBribe,(1,2,2)),address(this)),"past");
  ba.mint(address(this),100);bb.mint(address(this),100);ta.mint(address(this),101);tb.mint(address(this),101);
  require(compare(address(a),address(b),abi.encodeCall(a.depositBribe,(100,101,3)),address(this)),"deposit");
  IBribeInitiative.ClaimData[] memory data=new IBribeInitiative.ClaimData[](1);data[0]=IBribeInitiative.ClaimData(3,3,3);
  require(!compare(address(a),address(b),abi.encodeCall(a.claimBribes,(data)),address(this)),"current");
  ga.setEpoch(4);gb.setEpoch(4);
  data[0]=IBribeInitiative.ClaimData(3,1,3);require(!compare(address(a),address(b),abi.encodeCall(a.claimBribes,(data)),address(this)),"old user hint");
  data[0]=IBribeInitiative.ClaimData(3,3,1);require(!compare(address(a),address(b),abi.encodeCall(a.claimBribes,(data)),address(this)),"old total hint");
  data[0]=IBribeInitiative.ClaimData(3,3,3);require(compare(address(a),address(b),abi.encodeCall(a.claimBribes,(data)),address(this)),"claim");
  require(!compare(address(a),address(b),abi.encodeCall(a.claimBribes,(data)),address(this)),"duplicate");
 }

 function testMalformedClaimArraysAndEmptyBatch() public {
  (BribeInitiative a,,,)=make(true);(BribeInitiative b,,,)=make(false);
  IBribeInitiative.ClaimData[] memory empty=new IBribeInitiative.ClaimData[](0);
  require(compare(address(a),address(b),abi.encodeCall(a.claimBribes,(empty)),address(this)),"empty");
  for(uint n;n<100;n++){
   bytes memory data=bytes.concat(a.claimBribes.selector,abi.encode(uint(32),uint(1)),new bytes(n));
   require(!compare(address(a),address(b),data,address(this)),"truncated or no bribe");
  }
  uint[5] memory lengths=[uint(1)<<64,type(uint64).max,type(uint).max,uint(1)<<255,uint(1)<<128];
  for(uint n;n<5;n++)require(!compare(address(a),address(b),bytes.concat(a.claimBribes.selector,abi.encode(uint(32),lengths[n])),address(this)),"excessive length");
 }

 function batchRun(bool fe,uint mode) internal returns(bytes32){
  (BribeInitiative p,BribeGovMock gov,UPToken bold,UPToken token)=make(fe);
  bold.mint(address(this),300);token.mint(address(this),500);
  p.depositBribe(100,200,1);p.depositBribe(200,300,2);
  gov.allocate(p,address(this),10,0,10,0);gov.setEpoch(3);
  IBribeInitiative.ClaimData[] memory data=new IBribeInitiative.ClaimData[](2);
  data[0]=IBribeInitiative.ClaimData(1,1,1);data[1]=IBribeInitiative.ClaimData(mode==1?1:2,1,1);
  if(mode==2)token.setMode(1);
  (bool ok,bytes memory result)=address(p).call(abi.encodeCall(p.claimBribes,(data)));
  require(ok==(mode==0),"batch outcome");
  if(mode!=0){
   require(!p.claimedBribeAtEpoch(address(this),1)&&!p.claimedBribeAtEpoch(address(this),2),"claim rollback");
   require(bold.balanceOf(address(p))==300&&token.balanceOf(address(p))==500,"transfer rollback");
   (uint b,uint t,uint v)=p.bribeByEpoch(1);require(b==100&&t==200&&v==0,"bribe rollback");
   if(mode==2)require(keccak256(result)==keccak256(abi.encodeWithSignature("SafeERC20FailedOperation(address)",address(token))),"token error");
  } else require(keccak256(result)==keccak256(abi.encode(uint(300),uint(500))),"aggregate return");
  return keccak256(abi.encode(ok,bold.balanceOf(address(this)),token.balanceOf(address(this)),bold.balanceOf(address(p)),token.balanceOf(address(p))));
 }
 function testBatchAggregationAndAtomicRollback() public {for(uint mode;mode<3;mode++)require(batchRun(true,mode)==batchRun(false,mode),"batch parity");}

}
