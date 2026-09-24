// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import "./MultiBranchFixture.sol";
import {RETHPriceFeed} from "../reference/bold/contracts/src/PriceFeeds/RETHPriceFeed.sol";
import {WSTETHPriceFeed} from "../reference/bold/contracts/src/PriceFeeds/WSTETHPriceFeed.sol";
import {FeedRate} from "./PriceFeedParity.t.sol";
import {Governance} from "../reference/bold/contracts/lib/V2-gov/src/Governance.sol";
import {IGovernance} from "../reference/bold/contracts/lib/V2-gov/src/interfaces/IGovernance.sol";
import {BribeInitiative} from "../reference/bold/contracts/lib/V2-gov/src/BribeInitiative.sol";
import {IBribeInitiative} from "../reference/bold/contracts/lib/V2-gov/src/interfaces/IBribeInitiative.sol";
import {UPToken,UPStaking} from "./UserProxyParity.t.sol";
import {GovernanceDeployment} from "./GovernanceDeployment.sol";
contract MultiBranchSystemTest is MultiBranchFixture {
 bytes32 internal deploymentSalt;
 bool internal realFeeds;
 bool internal withGovernance;
 address internal interestRouter=ROUTER;
 struct GovBundle {Governance gov;BribeInitiative initiative;UPToken lqty;UPToken bribeToken;}
 GovBundle internal governance;
 mapping(address=>FeedOracle) internal secondaryOracles;
 mapping(address=>uint) internal feedKinds;
 struct Plan {System system;bytes[10] init;bytes[3] managerModules;bytes[3] borrowerModules;}
 struct Network {System[3] branches;BoldToken bold;CollateralRegistry registry;}
 function predict(bytes memory init) internal view override returns(address){return address(uint160(uint256(keccak256(abi.encodePacked(hex"ff",address(this),deploymentSalt,keccak256(init))))));}
 function deploy(bytes memory init) internal override returns(address target){
  require(init.length<=49152,"initcode");bytes32 salt=deploymentSalt;
  assembly{target:=create2(0,add(init,32),mload(init),salt)}require(target.code.length>0&&target.code.length<=24576,"deploy");
 }
 function prepare(bool fe,BoldToken bold,BorrowerSystemCollateral weth,uint kind) internal returns(Plan memory p){
  p.system.coll=new BorrowerSystemCollateral();p.system.weth=weth;p.system.feed=new BorrowerSystemPrice();p.system.bold=bold;
  p.system.registry=AddressesRegistry(deploy(bytes.concat(code("AddressesRegistry",fe),abi.encode(address(this),15e17,11e17,1e17,11e17,5e16,1e17))));
  AddressesRegistry r=p.system.registry;
  if(fe){
   p.borrowerModules[0]=bytes.concat(code("BorrowerOpening",true),abi.encode(r));
   p.borrowerModules[1]=bytes.concat(code("BorrowerAdjustments",true),abi.encode(r));
   p.borrowerModules[2]=bytes.concat(code("BorrowerBatches",true),abi.encode(r));
   p.init[8]=bytes.concat(code("BorrowerOperations",true),abi.encode(r,predict(p.borrowerModules[0]),predict(p.borrowerModules[1]),predict(p.borrowerModules[2])));
   p.managerModules[0]=code("TroveOperations",true);p.managerModules[1]=code("TroveRedemptions",true);p.managerModules[2]=bytes.concat(code("TroveLiquidations",true),abi.encode(r));
   p.init[3]=bytes.concat(code("TroveManager",true),abi.encode(r,predict(p.managerModules[0]),predict(p.managerModules[1]),predict(p.managerModules[2])));
  }else{p.init[8]=bytes.concat(code("BorrowerOperations",false),abi.encode(r));p.init[3]=bytes.concat(code("TroveManager",false),abi.encode(r));}
  p.init[0]=bytes.concat(code("ActivePool",fe),abi.encode(r));p.init[1]=bytes.concat(code("DefaultPool",fe),abi.encode(r));p.init[2]=bytes.concat(code("StabilityPool",fe),abi.encode(r));
  p.init[4]=bytes.concat(code("TroveNFT",fe),abi.encode(r));p.init[5]=bytes.concat(code("SortedTroves",fe),abi.encode(r));p.init[6]=bytes.concat(code("GasPool",fe),abi.encode(r));p.init[7]=bytes.concat(code("CollSurplusPool",fe),abi.encode(r));
  if(realFeeds) prepareFeed(p,fe,kind);

 }
 function prepareFeed(Plan memory p,bool fe,uint kind) internal {
  p.system.oracle=new FeedOracle(8,2000e8);feedKinds[address(p.system.oracle)]=kind;
  address bo=predict(p.init[8]);string memory name=kind==0?"WETHPriceFeed":kind==1?"RETHPriceFeed":"WSTETHPriceFeed";
  bytes memory feedCode;
  if(fe)feedCode=vm.parseBytes(vm.readFile(string.concat("build/",name,".bin")));
  else feedCode=kind==0?type(WETHPriceFeed).creationCode:kind==1?type(RETHPriceFeed).creationCode:type(WSTETHPriceFeed).creationCode;
  if(kind==0)p.init[9]=bytes.concat(feedCode,abi.encode(p.system.oracle,uint(3600),bo));
  else {
   FeedOracle secondary=new FeedOracle(kind==1?18:8,kind==1?int(1e18):int(2000e8));
   secondaryOracles[address(p.system.oracle)]=secondary;FeedRate rate=new FeedRate();rate.set(1e18,0);
   p.init[9]=bytes.concat(feedCode,abi.encode(p.system.oracle,secondary,rate,uint(3600),uint(3600),bo));
  }
 }
 function setPrice(System memory s,uint price) internal {
  if(!realFeeds){s.feed.set(price);return;}
  s.oracle.set(int(price/1e10),block.timestamp,0);
  FeedOracle secondary=secondaryOracles[address(s.oracle)];
  if(address(secondary)!=address(0))secondary.set(feedKinds[address(s.oracle)]==1?int(1e18):int(price/1e10),block.timestamp,0);
 }
 function finish(Plan memory p,bool fe,CollateralRegistry cr) internal returns(System memory s){
  s=p.system;s.cr=cr;
  address[18] memory vars;vars[0]=address(s.coll);vars[1]=predict(p.init[8]);vars[2]=predict(p.init[3]);vars[3]=predict(p.init[4]);vars[5]=predict(p.init[2]);vars[6]=realFeeds?predict(p.init[9]):address(s.feed);vars[7]=predict(p.init[0]);vars[8]=predict(p.init[1]);vars[9]=predict(p.init[6]);vars[10]=predict(p.init[7]);vars[11]=predict(p.init[5]);vars[12]=interestRouter;vars[15]=address(cr);vars[16]=address(s.bold);vars[17]=address(s.weth);
  (bool ok,)=address(s.registry).call(abi.encodePacked(AddressesRegistry.setAddresses.selector,abi.encode(vars)));require(ok,"registry configuration");
  if(fe){for(uint i;i<3;i++){deploy(p.managerModules[i]);deploy(p.borrowerModules[i]);}}
  s.active=ActivePool(deploy(p.init[0]));s.defaults=DefaultPool(deploy(p.init[1]));s.sp=StabilityPool(deploy(p.init[2]));s.manager=TroveManager(deploy(p.init[3]));s.nft=TroveNFT(deploy(p.init[4]));s.sorted=SortedTroves(deploy(p.init[5]));s.gasPool=deploy(p.init[6]);s.surplus=CollSurplusPool(deploy(p.init[7]));s.bo=BorrowerOperations(deploy(p.init[8]));
  if(realFeeds)s.oracleFeed=WETHPriceFeed(deploy(p.init[9]));
  s.bold.setBranchAddresses(address(s.manager),address(s.sp),address(s.bo),address(s.active));
 }
 function network(bool fe) internal returns(Network memory n){
  deploymentSalt=bytes32(0);n.bold=BoldToken(deploy(bytes.concat(code("BoldToken",fe),abi.encode(address(this)))));
  if(withGovernance){governance=deployGovernance(fe,n.bold);interestRouter=address(governance.gov);}
  BorrowerSystemCollateral weth=new BorrowerSystemCollateral();Plan[3] memory plans;
  address[] memory tokens=new address[](3);address[] memory managers=new address[](3);
  for(uint i;i<3;i++){deploymentSalt=bytes32(i+1);plans[i]=prepare(fe,n.bold,weth,i);tokens[i]=address(plans[i].system.coll);managers[i]=predict(plans[i].init[3]);}
  deploymentSalt=bytes32(0);n.registry=CollateralRegistry(deploy(bytes.concat(code("CollateralRegistry",fe),abi.encode(n.bold,tokens,managers))));
  for(uint i;i<3;i++){deploymentSalt=bytes32(i+1);n.branches[i]=finish(plans[i],fe,n.registry);}
  n.bold.setCollateralRegistry(address(n.registry));require(n.registry.totalCollaterals()==3,"three branches");
 }
 function deployGovernance(bool fe,BoldToken bold) internal returns(GovBundle memory g) {
  g.lqty=new UPToken();UPToken lusd=new UPToken();UPStaking staking=new UPStaking(g.lqty,lusd);ZapperSystemVm(address(vm)).deal(address(staking),1e24);g.bribeToken=new UPToken();
  IGovernance.Configuration memory cfg=IGovernance.Configuration(0,1e16,2e18,4,1e16,1e18,5e18,1000,100,90);
  bytes memory parameters=abi.encode(g.lqty,lusd,staking,bold,cfg,address(this),new address[](0));
  bytes memory initCode=fe?vm.parseBytes(vm.readFile("build/Governance.bin")):type(Governance).creationCode;
  g.gov=Governance(deploy(bytes.concat(initCode,fe?GovernanceDeployment.parameters(parameters):parameters)));
  initCode=fe?vm.parseBytes(vm.readFile("build/BribeInitiative.bin")):type(BribeInitiative).creationCode;
  g.initiative=BribeInitiative(deploy(bytes.concat(initCode,abi.encode(g.gov,bold,g.bribeToken))));
  address[] memory targets=new address[](1);targets[0]=address(g.initiative);g.gov.registerInitialInitiatives(targets);
 }
 function checkpoint(Network memory n) internal view returns(bytes32 h){
  uint recordedDebt;
  for(uint i;i<3;i++){
   System memory s=n.branches[i];conserve(s);recordedDebt+=s.active.aggRecordedDebt()+s.defaults.getBoldDebt();
   h=keccak256(abi.encode(h,s.active.getCollBalance(),s.active.getBoldDebt(),s.defaults.getCollBalance(),s.defaults.getBoldDebt(),s.sp.getTotalBoldDeposits(),s.sp.getCollBalance(),s.sp.getYieldGainsOwed(),s.sp.getYieldGainsPending()));
   h=keccak256(abi.encode(h,s.coll.balanceOf(ALICE),s.coll.balanceOf(BOB),s.sorted.getSize(),s.manager.getTroveIdsCount(),s.bo.hasBeenShutDown()));
  }
  require(n.bold.totalSupply()==recordedDebt,"shared supply equals recorded branch debt");
  h=keccak256(abi.encode(h,n.bold.totalSupply(),n.bold.balanceOf(ALICE),n.bold.balanceOf(BOB),n.bold.balanceOf(ROUTER),n.registry.baseRate(),n.registry.lastFeeOperationTime()));
 }
 function liquidateBranch(Network memory n) internal {
  uint zero=n.branches[0].sp.getTotalBoldDeposits();uint one=n.branches[1].sp.getTotalBoldDeposits();uint two=n.branches[2].sp.getTotalBoldDeposits();
  uint supply=n.bold.totalSupply();setPrice(n.branches[2],300e18);
  uint[] memory ids=new uint[](1);ids[0]=id(BOB,2);n.branches[2].manager.batchLiquidateTroves(ids);
  require(uint(n.branches[2].manager.getTroveStatus(id(BOB,2)))==3,"liquidated trove");
  require(n.branches[0].sp.getTotalBoldDeposits()==zero&&n.branches[1].sp.getTotalBoldDeposits()==one,"other branch stability deposits unchanged");
  require(n.branches[2].sp.getTotalBoldDeposits()<two&&n.bold.totalSupply()<supply,"local offset burns shared BOLD");
  require(n.branches[2].defaults.getBoldDebt()>0&&n.branches[2].defaults.getCollBalance()>0,"uncovered debt redistributed locally");
  n.branches[2].bo.applyPendingDebt(id(ALICE,1),0,0);setPrice(n.branches[2],2000e18);
 }
 function scenario(bool fe,uint requested,uint elapsed) internal returns(bytes32 h){
  TimeVm(address(vm)).warp(1000);Network memory n=network(fe);
  for(uint i;i<3;i++){
   open(n.branches[i],1,ALICE,20e18,5e16+i*1e16);open(n.branches[i],2,BOB,10e18,8e16+i*1e16);
   vm.prank(ALICE);n.branches[i].sp.provideToSP((i+1)*500e18,false);
  }
  h=checkpoint(n);TimeVm(address(vm)).warp(1000+elapsed);
  for(uint i;i<3;i++)setPrice(n.branches[i],2000e18);
  uint before=n.bold.balanceOf(ALICE);vm.prank(ALICE);n.registry.redeemCollateral(requested,0,1e18);
  require(n.bold.balanceOf(ALICE)<before,"redemption burns shared BOLD");
  for(uint i;i<3;i++)require(n.branches[i].coll.balanceOf(ALICE)>375e14,"each branch redeemed");
  h=keccak256(abi.encode(h,checkpoint(n)));
  liquidateBranch(n);h=keccak256(abi.encode(h,checkpoint(n)));
  setPrice(n.branches[1],50e18);n.branches[1].bo.shutdown();
  uint frozen=n.branches[1].active.getCollBalance();before=n.bold.balanceOf(ALICE);
  vm.prank(ALICE);n.registry.redeemCollateral(300e18,0,1e18);
  require(n.bold.balanceOf(ALICE)<before&&n.branches[1].active.getCollBalance()==frozen,"redemption skips shutdown branch");
  h=keccak256(abi.encode(h,checkpoint(n)));
 }
 function testMultiBranchReferenceLifecycle() public {scenario(false,1000e18,30 days);}
 function testMultiBranchConnectedRedemptionsAndShutdown() public {require(scenario(true,1000e18,30 days)==scenario(false,1000e18,30 days),"multi-branch lifecycle parity");}
 function testMultiBranchFuzzRedemptionLiquidationAndShutdown(uint96 amount,uint16 daysElapsed) public {
  uint requested=100e18+uint(amount)%1400e18;uint elapsed=(uint(daysElapsed)%60+1)*1 days;
  require(scenario(true,requested,elapsed)==scenario(false,requested,elapsed),"multi-branch fuzz parity");
 }
 function testMultiBranchAllThreeRealPriceFeeds() public {
  realFeeds=true;require(scenario(true,1000e18,30 days)==scenario(false,1000e18,30 days),"real feeds multi-branch parity");
 }
 function oracleFailure(bool fe) internal returns(bytes32 h) {
  TimeVm(address(vm)).warp(1000);Network memory n=network(fe);
  for(uint i;i<3;i++){open(n.branches[i],1,ALICE,20e18,5e16);open(n.branches[i],2,BOB,10e18,8e16);}
  TimeVm(address(vm)).warp(1000+1 days);for(uint i;i<3;i++)setPrice(n.branches[i],2000e18);
  uint frozen=n.branches[0].active.getCollBalance();n.branches[0].oracle.set(2000e8,block.timestamp,1);
  (,bool failed)=n.branches[0].oracleFeed.fetchPrice();require(failed&&n.branches[0].bo.hasBeenShutDown(),"oracle callback shuts down local branch");
  require(!n.branches[1].bo.hasBeenShutDown()&&!n.branches[2].bo.hasBeenShutDown(),"other branches remain live");
  uint before=n.bold.balanceOf(ALICE);vm.prank(ALICE);n.registry.redeemCollateral(1000e18,0,1e18);
  require(n.bold.balanceOf(ALICE)<before&&n.branches[0].active.getCollBalance()==frozen,"redemptions continue through remaining branches");
  require(n.branches[1].coll.balanceOf(ALICE)>375e14&&n.branches[2].coll.balanceOf(ALICE)>375e14,"remaining branches distribute collateral");
  h=checkpoint(n);
 }
 function testMultiBranchOracleFailureIsolation() public {realFeeds=true;require(oracleFailure(true)==oracleFailure(false),"oracle failure system parity");}
 function protocolYield(bool fe) internal returns(bytes32 h) {
  TimeVm(address(vm)).warp(1000);Network memory n=network(fe);GovBundle memory g=governance;
  for(uint i;i<3;i++){open(n.branches[i],1,ALICE,20e18,5e16);open(n.branches[i],2,BOB,10e18,8e16);}
  g.lqty.mint(ALICE,100e18);vm.prank(ALICE);g.gov.depositLQTY(100e18);
  TimeVm(address(vm)).warp(1100);address[] memory targets=new address[](1);targets[0]=address(g.initiative);
  int[] memory votes=new int[](1);votes[0]=100e18;vm.prank(ALICE);g.gov.allocateLQTY(new address[](0),targets,votes,new int[](1));
  vm.prank(ALICE);n.bold.approve(address(g.initiative),100e18);g.bribeToken.mint(ALICE,200);
  vm.prank(ALICE);g.initiative.depositBribe(100e18,200,2);
  TimeVm(address(vm)).warp(1000+30 days);
  for(uint i;i<3;i++){setPrice(n.branches[i],2000e18);vm.prank(BOB);n.branches[i].sp.provideToSP(100e18,false);}
  uint income=n.bold.balanceOf(address(g.gov));require(income>=5e18,"real branch interest reaches governance");
  require(g.gov.claimForInitiative(address(g.initiative))==income,"allocated initiative receives protocol income");
  IBribeInitiative.ClaimData[] memory claims=new IBribeInitiative.ClaimData[](1);claims[0]=IBribeInitiative.ClaimData(2,2,2);
  vm.prank(ALICE);(uint reward,uint bonus)=g.initiative.claimBribes(claims);require(reward==100e18&&bonus==200,"voter receives deposited bribe");
  require(n.bold.balanceOf(address(g.gov))==0&&n.bold.balanceOf(address(g.initiative))==income,"income and bribe conservation");
  vm.prank(ALICE);g.gov.resetAllocations(targets,true);vm.prank(ALICE);g.gov.withdrawLQTY(100e18,false,ALICE);
  require(g.lqty.balanceOf(ALICE)==100e18,"voter exits");h=keccak256(abi.encode(checkpoint(n),income,reward,bonus));
 }
 function testMultiBranchProtocolInterestToGovernanceAndBribes() public {
  realFeeds=true;withGovernance=true;require(protocolYield(true)==protocolYield(false),"complete protocol yield parity");
 }
}
