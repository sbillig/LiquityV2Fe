// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {Governance} from "../reference/bold/contracts/lib/V2-gov/src/Governance.sol";
import {IGovernance} from "../reference/bold/contracts/lib/V2-gov/src/interfaces/IGovernance.sol";
import {BribeInitiative} from "../reference/bold/contracts/lib/V2-gov/src/BribeInitiative.sol";
import {IBribeInitiative} from "../reference/bold/contracts/lib/V2-gov/src/interfaces/IBribeInitiative.sol";
import {UPToken,UPStaking} from "./UserProxyParity.t.sol";
import {GSVm} from "./GovernanceSnapshotParity.t.sol";
import {GaugeToken} from "./CurveGaugeRewardsParity.t.sol";
import {GovernanceDeployment} from "./GovernanceDeployment.sol";
abstract contract GovernanceLifecycleBase {
 bool internal referenceGovernance;
 GSVm constant vm=GSVm(address(uint160(uint(keccak256("hevm cheat code")))));
 receive() external payable {}
 function create(bytes memory code,bytes memory arguments) internal returns(address a) {
  bytes memory init=bytes.concat(code,arguments);require(init.length<=49152,"initcode size");
  assembly{a:=create(0,add(init,32),mload(init))}
  require(a.code.length>0&&a.code.length<=24576,"runtime size");
 }
 struct Env {Governance gov;BribeInitiative initiative;UPToken lqty;UPToken bold;UPToken bribeToken;UPStaking staking;}
 function make(bool fe) internal returns(Env memory e) {
  vm.warp(1000);UPToken lqty=new UPToken();UPToken lusd=new UPToken();UPToken bold=new GaugeToken();UPToken bribeToken=new UPToken();
  UPStaking staking=new UPStaking(lqty,lusd);vm.deal(address(staking),1e24);
  IGovernance.Configuration memory cfg=IGovernance.Configuration(0,1e16,2e18,4,1e16,1e18,5e18,1000,100,90);
  bytes memory parameters=abi.encode(lqty,lusd,staking,bold,cfg,address(this),new address[](0));
  bool feGovernance=fe&&!referenceGovernance;
  bytes memory code=feGovernance?vm.parseBytes(vm.readFile("build/Governance.bin")):type(Governance).creationCode;
  Governance gov=Governance(create(code,feGovernance?GovernanceDeployment.parameters(parameters):parameters));
  code=fe?vm.parseBytes(vm.readFile("build/BribeInitiative.bin")):type(BribeInitiative).creationCode;
  BribeInitiative initiative=BribeInitiative(create(code,abi.encode(gov,bold,bribeToken)));
  e=Env(gov,initiative,lqty,bold,bribeToken,staking);
 }
}
contract GovernanceBribeLifecycleTest is GovernanceLifecycleBase {
 function run(bool fe,uint qty,uint amount) internal returns(bytes32) {
  Env memory e=make(fe);
  address[] memory targets=new address[](1);targets[0]=address(e.initiative);e.gov.registerInitialInitiatives(targets);
  e.lqty.mint(address(this),qty);e.gov.depositLQTY(qty);
  e.bold.mint(address(this),amount);e.bribeToken.mint(address(this),amount+1);e.initiative.depositBribe(amount,amount+1,2);
  {vm.warp(1100);int[] memory votes=new int[](1);votes[0]=int(qty);int[] memory vetos=new int[](1);
  e.gov.allocateLQTY(new address[](0),targets,votes,vetos);}
  require(e.initiative.getMostRecentTotalEpoch()==2&&e.initiative.getMostRecentUserEpoch(address(this))==2,"actual allocation callback");
  vm.warp(1200);e.bold.mint(address(e.gov),10e18);uint governanceReward=e.gov.claimForInitiative(address(e.initiative));
  require(governanceReward==10e18&&e.gov.claimForInitiative(address(e.initiative))==0,"governance accrual and claim");
  uint paidBold;uint paidBribe;{IBribeInitiative.ClaimData[] memory claims=new IBribeInitiative.ClaimData[](1);claims[0]=IBribeInitiative.ClaimData(2,2,2);
  (paidBold,paidBribe)=e.initiative.claimBribes(claims);}
  require(paidBold==amount&&paidBribe==amount+1,"bribe distribution");
  require(e.bold.balanceOf(address(e.initiative))==governanceReward,"separate governance and bribe accounting");
  e.gov.resetAllocations(targets,true);e.gov.withdrawLQTY(qty,false,address(this));
  {(uint a,uint b,uint c,uint d)=e.gov.userStates(address(this));require(a==0&&b==0&&c==0&&d==0,"closed user position");}
  require(e.staking.stakes(e.gov.deriveUserProxyAddress(address(this)))==0&&e.lqty.balanceOf(address(this))==qty,"stake conservation");
  return keccak256(abi.encode(governanceReward,paidBold,paidBribe,e.bold.balanceOf(address(this)),e.bribeToken.balanceOf(address(this)),e.initiative.claimedBribeAtEpoch(address(this),2)));
 }
 function testFeBribeWithReferenceGovernance() public {referenceGovernance=true;require(run(true,100,123)==run(false,100,123));}
 function testReferenceLifecycle() public {run(false,100,123);}
 function testFuzzConnectedStakeVoteClaimBribeAndExit(uint64 quantity,uint64 bribe) public {
  require(run(true,uint(quantity)+1,uint(bribe)+1)==run(false,uint(quantity)+1,uint(bribe)+1),"connected governance lifecycle parity");
 }
}
