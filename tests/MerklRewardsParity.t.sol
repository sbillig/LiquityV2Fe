// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {UniV4MerklRewards} from "../reference/bold/contracts/lib/V2-gov/src/UniV4MerklRewards.sol";
import {IDistributionCreator} from "../reference/bold/contracts/lib/V2-gov/src/interfaces/IDistributionCreator.sol";
import {UPVm} from "./UserProxyParity.t.sol";
import {GaugeToken} from "./CurveGaugeRewardsParity.t.sol";
interface MerklVm is UPVm {function etch(address,bytes calldata) external;}
contract MerklGovMock {
 uint public EPOCH_START;uint public EPOCH_DURATION;uint public epoch=4;uint public claimable;uint public mintAmount;GaugeToken public token;
 constructor(uint start,uint duration,GaugeToken t){EPOCH_START=start;EPOCH_DURATION=duration;token=t;}
 function configure(uint c,uint m,uint e) external {claimable=c;mintAmount=m;epoch=e;}
 function claimForInitiative(address p) external returns(uint){require(p==msg.sender,"initiative");token.mint(p,mintAmount);UniV4MerklRewards(p).onClaimForInitiative(epoch-1,claimable);return claimable;}
}
contract MerklCreatorMock {
 uint public calls;uint public amount;uint public timestamp;uint public duration;bytes32 public dataHash;bool public accepted;
 function acceptConditions() external {accepted=true;calls=0;amount=0;timestamp=0;duration=0;dataHash=0;}
 function createCampaign(IDistributionCreator.CampaignParameters calldata p) external returns(bytes32){
  require(accepted&&p.creator==msg.sender&&p.campaignId==bytes32(0)&&p.campaignType==13,"params");
  require(GaugeToken(p.rewardToken).allowance(msg.sender,address(this))==type(uint).max,"approval");
  calls++;amount=p.amount;timestamp=p.startTimestamp;duration=p.duration;dataHash=keccak256(p.campaignData);
  GaugeToken(p.rewardToken).transferFrom(msg.sender,address(this),p.amount);return bytes32(uint(123));
 }
}
contract MerklRewardsParityTest {
 MerklVm constant vm=MerklVm(address(uint160(uint(keccak256("hevm cheat code")))));
 address constant CREATOR=0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd;
 function make(bool fe,uint threshold,uint start,uint duration,uint32 fee,bytes32 pool) internal returns(UniV4MerklRewards p,MerklGovMock gov,GaugeToken token){
  vm.etch(CREATOR,type(MerklCreatorMock).runtimeCode);token=new GaugeToken();gov=new MerklGovMock(start,duration,token);
  bytes memory code=fe?vm.parseBytes(vm.readFile("build/UniV4MerklRewards.bin")):type(UniV4MerklRewards).creationCode;
  bytes memory init=bytes.concat(code,abi.encode(gov,token,threshold,pool,fee,uint32(10000-fee),uint32(0)));address a;assembly{a:=create(0,add(init,32),mload(init))}require(a.code.length>0&&a.code.length<=24576,"deploy");p=UniV4MerklRewards(a);
 }
 function expectedData(uint32 fee,bytes32 pool) internal pure returns(bytes memory){
  uint[20] memory words=[uint(416),0,uint(fee),10000-uint(fee),0,480,512,576,0,0,0,0,608,32,uint(pool),0,1,uint(uint160(0xF06016D822943C42e3Cb7FC3a6A3B1889C1045f8)),0,0];
  return abi.encode(words);
 }
 function run(bool fe,uint amount,uint threshold,uint start,uint duration,uint32 fee,bytes32 pool) internal returns(bytes32){
  (UniV4MerklRewards p,MerklGovMock gov,GaugeToken token)=make(fe,threshold,start,duration,fee,pool);
  bytes memory expected=expectedData(fee,pool);
  require(keccak256(p.getCampaignData())==keccak256(expected),"campaign bytes");
  gov.configure(amount,amount,4);p.claimForInitiative();MerklCreatorMock creator=MerklCreatorMock(CREATOR);
  if(amount>=threshold){require(creator.calls()==1&&creator.amount()==amount&&creator.timestamp()==uint32(start+3*duration)&&creator.duration()==uint32(duration),"campaign fields");require(creator.dataHash()==keccak256(expected),"campaign data");require(token.balanceOf(address(p))==0,"spent");}
  else require(creator.calls()==0&&token.balanceOf(address(p))==amount,"below threshold");
  return keccak256(abi.encode(creator.calls(),creator.amount(),creator.timestamp(),creator.duration(),creator.dataHash(),token.balanceOf(address(p))));
 }
 function testFuzzCampaignEncodingAndThreshold(uint96 amount,uint96 threshold,uint64 start,uint64 duration,uint16 fee,bytes32 pool) public {uint a=uint(amount)+1;uint32 f=uint32(fee)%10001;require(run(true,a,threshold,start,duration,f,pool)==run(false,a,threshold,start,duration,f,pool),"parity");}
 function compare(address a,address b,bytes memory data) internal returns(bool){(bool ok,bytes memory x)=a.call(data);(bool success,bytes memory y)=b.call(data);require(ok==success&&keccak256(x)==keccak256(y),"call parity");return ok;}
 function testClaimAssertionsAndAuthorization() public {
  (UniV4MerklRewards a,MerklGovMock ga,GaugeToken ta)=make(true,100,0,100,5000,bytes32(0));
  (UniV4MerklRewards b,MerklGovMock gb,GaugeToken tb)=make(false,100,0,100,5000,bytes32(0));
  require(!compare(address(a),address(b),abi.encodeCall(a.onClaimForInitiative,(1,0))),"authorization");
  require(compare(address(a),address(b),abi.encodeCall(a.onRegisterInitiative,(1))),"register noop");
  require(compare(address(a),address(b),abi.encodeCall(a.onUnregisterInitiative,(1))),"unregister noop");
  require(!compare(address(a),address(b),abi.encodeCall(a.claimForInitiative,())),"zero funds");
  ga.configure(2,1,4);gb.configure(2,1,4);require(!compare(address(a),address(b),abi.encodeCall(a.claimForInitiative,())),"claim assertion");
  require(ta.balanceOf(address(a))==0&&tb.balanceOf(address(b))==0,"mint rollback");
  ga.configure(1,1,4);gb.configure(1,1,4);require(compare(address(a),address(b),abi.encodeCall(a.claimForInitiative,())),"below threshold");
  require(ta.balanceOf(address(a))==1&&tb.balanceOf(address(b))==1,"queued");
 }

 function badWeights(bool fe,uint32 x,uint32 y,uint32 z) internal returns(bytes32){
  bytes memory code=fe?vm.parseBytes(vm.readFile("build/UniV4MerklRewards.bin")):type(UniV4MerklRewards).creationCode;
  bytes memory init=bytes.concat(code,abi.encode(address(1),address(2),uint(0),bytes32(0),x,y,z));address a;bytes memory result;
  assembly{a:=create(0,add(init,32),mload(init)) result:=mload(0x40) mstore(result,returndatasize()) returndatacopy(add(result,32),0,returndatasize()) mstore(0x40,add(add(result,32),returndatasize()))}
  require(a==address(0),"constructor rejection");return keccak256(result);
 }
 function testConstructorWeightChecks() public {
  require(badWeights(true,0,0,0)==badWeights(false,0,0,0),"wrong sum");
  require(badWeights(true,type(uint32).max,1,0)==badWeights(false,type(uint32).max,1,0),"first sum overflow");
  require(badWeights(true,1,0,type(uint32).max)==badWeights(false,1,0,type(uint32).max),"second sum overflow");
 }
 function overflow(bool fe,bool belowThreshold) internal returns(bytes32){
  (UniV4MerklRewards p,MerklGovMock gov,GaugeToken token)=make(fe,belowThreshold?2:1,type(uint).max,1,0,bytes32(0));
  gov.configure(1,1,4);(bool ok,bytes memory result)=address(p).call(abi.encodeCall(p.claimForInitiative,()));
  require(ok==belowThreshold,"threshold before timestamp arithmetic");
  return keccak256(abi.encode(ok,result,token.balanceOf(address(p))));
 }
 function testTimestampOverflowAndThresholdOrdering() public {require(overflow(true,false)==overflow(false,false));require(overflow(true,true)==overflow(false,true));}

}
