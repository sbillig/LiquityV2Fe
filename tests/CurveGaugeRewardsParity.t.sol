// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {CurveV2GaugeRewards} from "../reference/bold/contracts/lib/V2-gov/src/CurveV2GaugeRewards.sol";
import {BribeGovMock} from "./BribeInitiativeParity.t.sol";
import {UPVm,UPToken} from "./UserProxyParity.t.sol";
contract GaugeToken is UPToken {
 mapping(address=>mapping(address=>uint)) public allowance;
 function approve(address spender,uint amount) external returns(bool){allowance[msg.sender][spender]=amount;return true;}
}
contract CurveGaugeMock {
 uint public deposited;uint public duration;bool public fail;
 function setFail(bool value) external {fail=value;}
 function deposit_reward_token(address token,uint amount,uint d) external {
  require(!fail,"gauge failed");require(GaugeToken(token).allowance(msg.sender,address(this))==amount,"approval");
  GaugeToken(token).transferFrom(msg.sender,address(this),amount);deposited+=amount;duration=d;
 }
}
contract CurveGaugeRewardsParityTest {
 UPVm constant vm=UPVm(address(uint160(uint(keccak256("hevm cheat code")))));
 function make(bool fe,uint duration) internal returns(CurveV2GaugeRewards p,BribeGovMock gov,GaugeToken token,CurveGaugeMock gauge){
  gov=new BribeGovMock();token=new GaugeToken();gauge=new CurveGaugeMock();UPToken other=new UPToken();
  bytes memory code=fe?vm.parseBytes(vm.readFile("build/CurveV2GaugeRewards.bin")):type(CurveV2GaugeRewards).creationCode;
  bytes memory init=bytes.concat(code,abi.encode(gov,token,other,gauge,duration));address a;assembly{a:=create(0,add(init,32),mload(init))}require(a.code.length>0&&a.code.length<=24576,"deployment");p=CurveV2GaugeRewards(a);
 }
 function run(bool fe,uint d,uint available) internal returns(bytes32){
  (CurveV2GaugeRewards p,BribeGovMock gov,GaugeToken token,CurveGaugeMock gauge)=make(fe,d);
  require(address(p.gauge())==address(gauge)&&p.duration()==d,"configuration");token.mint(address(p),available);
  vm.prank(address(gov));p.onClaimForInitiative(1,d*1000-1);require(p.remainder()==d*1000-1&&gauge.deposited()==0,"queue");
  vm.prank(address(gov));p.onClaimForInitiative(2,1);uint expected=available<d*1000?available:d*1000;
  require(p.remainder()==0&&gauge.deposited()==expected&&gauge.duration()==d,"threshold and cap");
  require(token.balanceOf(address(p))+token.balanceOf(address(gauge))==available,"conservation");
  return keccak256(abi.encode(p.remainder(),gauge.deposited(),gauge.duration(),token.balanceOf(address(p))));
 }
 function testFuzzQueueThresholdAndBalanceCap(uint64 rawDuration,uint96 available) public {uint d=uint(rawDuration)+1;require(run(true,d,available)==run(false,d,available),"parity");}
 function rollback(bool fe) internal {
  (CurveV2GaugeRewards p,BribeGovMock gov,GaugeToken token,CurveGaugeMock gauge)=make(fe,1);token.mint(address(p),1000);
  vm.prank(address(gov));p.onClaimForInitiative(1,999);gauge.setFail(true);
  vm.prank(address(gov));(bool ok,bytes memory data)=address(p).call(abi.encodeCall(p.onClaimForInitiative,(2,1)));
  require(!ok&&keccak256(data)==keccak256(abi.encodeWithSignature("Error(string)","gauge failed")),"bubble");
  require(p.remainder()==999&&token.balanceOf(address(p))==1000&&token.allowance(address(p),address(gauge))==0,"rollback");
  (ok,data)=address(p).call(abi.encodeCall(p.onClaimForInitiative,(2,1)));require(!ok&&keccak256(data)==keccak256(abi.encodeWithSignature("Error(string)","BribeInitiative: invalid-sender")),"auth");
 }
 function testGaugeFailureRollbackAndAuthorization() public {rollback(true);rollback(false);}
 function edge(bool fe,uint duration,uint amount) internal returns(bytes32){
  (CurveV2GaugeRewards p,BribeGovMock gov,,CurveGaugeMock gauge)=make(fe,duration);
  vm.prank(address(gov));(bool ok,bytes memory data)=address(p).call(abi.encodeCall(p.onClaimForInitiative,(1,amount)));
  return keccak256(abi.encode(ok,data,p.remainder(),gauge.deposited(),gauge.duration()));
 }
 function testZeroDurationAndThresholdOverflow() public {
  require(edge(true,0,0)==edge(false,0,0),"zero duration");
  require(edge(true,type(uint).max,0)==edge(false,type(uint).max,0),"duration multiplication overflow");
  require(edge(true,type(uint).max/1000,1)==edge(false,type(uint).max/1000,1),"large queue");
 }

}
