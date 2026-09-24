// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {GovernanceLifecycleBase} from "./GovernanceBribeLifecycle.t.sol";
import {CurveV2GaugeRewards} from "../reference/bold/contracts/lib/V2-gov/src/CurveV2GaugeRewards.sol";
import {UniV4MerklRewards} from "../reference/bold/contracts/lib/V2-gov/src/UniV4MerklRewards.sol";
import {CurveGaugeMock} from "./CurveGaugeRewardsParity.t.sol";
import {MerklCreatorMock,MerklVm} from "./MerklRewardsParity.t.sol";
contract GovernanceRewardsLifecycleTest is GovernanceLifecycleBase {
 address constant CREATOR=0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd;
 function vote(Env memory e,address target) internal {
  address[] memory targets=new address[](1);targets[0]=target;e.gov.registerInitialInitiatives(targets);
  e.lqty.mint(address(this),100);e.gov.depositLQTY(100);vm.warp(1100);
  int[] memory votes=new int[](1);votes[0]=100;e.gov.allocateLQTY(new address[](0),targets,votes,new int[](1));
 }
 function curve(bool fe,bool failFirst) internal returns(bytes32) {
  Env memory e=make(fe);CurveGaugeMock gauge=new CurveGaugeMock();
  bytes memory code=fe?vm.parseBytes(vm.readFile("build/CurveV2GaugeRewards.bin")):type(CurveV2GaugeRewards).creationCode;
  CurveV2GaugeRewards initiative=CurveV2GaugeRewards(create(code,abi.encode(e.gov,e.bold,e.bribeToken,gauge,uint(1))));
  vote(e,address(initiative));gauge.setFail(failFirst);
  vm.warp(1200);e.bold.mint(address(e.gov),10e18);require(e.gov.claimForInitiative(address(initiative))==10e18,"first governance claim");
  require(gauge.deposited()==(failFirst?0:10e18),"first hook outcome");
  require(e.gov.claimForInitiative(address(initiative))==0,"failed hook does not reopen claim");
  gauge.setFail(false);vm.warp(1300);e.bold.mint(address(e.gov),10e18);
  require(e.gov.claimForInitiative(address(initiative))==10e18,"second governance claim");
  require(gauge.deposited()==(failFirst?10e18:20e18)&&gauge.duration()==1,"gauge distribution");
  require(e.bold.balanceOf(address(gauge))+e.bold.balanceOf(address(initiative))==20e18,"reward conservation");
  return keccak256(abi.encode(gauge.deposited(),initiative.remainder(),e.bold.balanceOf(address(initiative))));
 }
 function merkl(bool fe) internal returns(bytes32) {
  Env memory e=make(fe);MerklVm(address(vm)).etch(CREATOR,type(MerklCreatorMock).runtimeCode);
  bytes memory code=fe?vm.parseBytes(vm.readFile("build/UniV4MerklRewards.bin")):type(UniV4MerklRewards).creationCode;
  UniV4MerklRewards initiative=UniV4MerklRewards(create(code,abi.encode(e.gov,e.bold,uint(20e18),bytes32(uint(123)),uint32(6000),uint32(4000),uint32(0))));
  vote(e,address(initiative));vm.warp(1200);e.bold.mint(address(e.gov),10e18);initiative.claimForInitiative();
  MerklCreatorMock creator=MerklCreatorMock(CREATOR);
  require(creator.calls()==0&&e.bold.balanceOf(address(initiative))==10e18,"queued below threshold");
  vm.warp(1300);e.bold.mint(address(e.gov),10e18);initiative.claimForInitiative();
  require(creator.calls()==1&&creator.amount()==20e18&&creator.timestamp()==1300&&creator.duration()==100,"campaign after second accrual");
  require(e.bold.balanceOf(address(initiative))==0&&e.bold.balanceOf(CREATOR)==20e18,"campaign conservation");
  return keccak256(abi.encode(creator.calls(),creator.amount(),creator.timestamp(),creator.duration(),creator.dataHash()));
 }
 function testFeRewardsWithReferenceGovernance() public {referenceGovernance=true;require(curve(true,false)==curve(false,false));require(curve(true,true)==curve(false,true));require(merkl(true)==merkl(false));}
 function testReferenceRewardsLifecycles() public {curve(false,false);curve(false,true);merkl(false);}
 function testConnectedCurveClaimsAndNonfatalHookFailure() public {require(curve(true,false)==curve(false,false));require(curve(true,true)==curve(false,true));}
 function testConnectedMerklAccrualAndCampaign() public {require(merkl(true)==merkl(false));}
}
