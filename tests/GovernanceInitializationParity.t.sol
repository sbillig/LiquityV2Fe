// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {GovernanceDeployment} from "./GovernanceDeployment.sol";
import {Governance} from "../reference/bold/contracts/lib/V2-gov/src/Governance.sol";
import {IGovernance} from "../reference/bold/contracts/lib/V2-gov/src/interfaces/IGovernance.sol";
import {BILogVm} from "./BribeInitiativeParity.t.sol";
import {GAVm} from "./GovernanceActionsParity.t.sol";
contract GInitialHook {uint public calls;function onRegisterInitiative(uint epoch) external {require(epoch==1);calls++;}}
contract GovernanceInitializationParityTest {
 GAVm constant vm=GAVm(address(uint160(uint(keccak256("hevm cheat code")))));
 function cfg() internal pure returns(IGovernance.Configuration memory){return IGovernance.Configuration(7,1e16,2e18,4,1e16,1e18,5e18,1000,100,90);}
 function args(IGovernance.Configuration memory c,address owner,address[] memory initial) internal pure returns(bytes memory){return abi.encode(address(1),address(2),address(3),address(4),c,owner,initial);}
 function deploy(bool fe,bytes memory parameters) internal returns(address p,bytes memory error){
  bytes memory code=fe?vm.parseBytes(vm.readFile("build/Governance.bin")):type(Governance).creationCode;
  if(fe)parameters=GovernanceDeployment.parameters(parameters);
  bytes memory init=bytes.concat(code,parameters);require(init.length<=49152,"initcode size");
  assembly{p:=create(0,add(init,32),mload(init)) error:=mload(0x40) mstore(error,returndatasize()) returndatacopy(add(error,32),0,returndatasize()) mstore(0x40,add(add(error,32),returndatasize()))}
  if(p!=address(0))require(p.code.length<=24576,"runtime size");
 }
 function reject(bytes memory parameters) internal { (address a,bytes memory x)=deploy(true,parameters);(address b,bytes memory y)=deploy(false,parameters);require(a==address(0)&&b==address(0)&&keccak256(x)==keccak256(y),"constructor revert parity");}
 function testConfigurationValidationOrder() public {
  vm.warp(1000);address[] memory initial=new address[](0);
  for(uint mode;mode<7;mode++){
   IGovernance.Configuration memory c=cfg();
   if(mode==0)c.minClaim=c.minAccrual+1;if(mode==1)c.registrationThresholdFactor=1e18;if(mode==2)c.unregistrationThresholdFactor=1e18;if(mode==3)c.votingThresholdFactor=1e18;if(mode==4)c.epochStart=1001;if(mode==5)c.epochDuration=0;if(mode==6)c.epochVotingCutoff=100;
   reject(args(c,address(this),initial));
  }
 }
 function run(bool fe,bool constructorInitial) internal returns(bytes32){
  vm.warp(1000);address[] memory initial=new address[](3);initial[0]=address(777);initial[1]=address(777);initial[2]=address(0);
  vm.etch(address(777),type(GInitialHook).runtimeCode);vm.store(address(777),bytes32(0),bytes32(0));
  BILogVm(address(vm)).recordLogs();
  (address deployed,)=deploy(fe,args(cfg(),address(this),constructorInitial?initial:new address[](0)));require(deployed!=address(0),"deploy");Governance p=Governance(deployed);
  if(!constructorInitial){require(p.owner()==address(this)&&p.isOwner(),"owner retained");p.registerInitialInitiatives(initial);}
  require(p.owner()==address(0)&&!p.isOwner()&&p.registeredInitiatives(address(777))==1&&p.registeredInitiatives(address(0))==1&&GInitialHook(address(777)).calls()==2,"initial registration");
  (bool ok,bytes memory data)=deployed.call(abi.encodeCall(p.registerInitialInitiatives,(initial)));require(!ok,"owner renounced");
  return keccak256(abi.encode(p.EPOCH_START(),p.EPOCH_DURATION(),p.EPOCH_VOTING_CUTOFF(),p.MIN_CLAIM(),p.MIN_ACCRUAL(),p.REGISTRATION_FEE(),p.REGISTRATION_THRESHOLD_FACTOR(),data,logsHash(deployed)));
 }
 function logsHash(address emitter) internal returns(bytes32 h) {
  BILogVm.Entry[] memory entries=BILogVm(address(vm)).getRecordedLogs();
  for(uint i;i<entries.length;i++){require(entries[i].emitter==emitter,"initial registration event emitter");h=keccak256(abi.encode(h,entries[i].topics,entries[i].data));}
 }
 function testInitialRegistrationAndRenunciation() public {require(run(true,true)==run(false,true));require(run(true,false)==run(false,false));}
 function testConstructorArrayMemoryBoundaries() public {
  vm.warp(1000);address[] memory initial=new address[](1);initial[0]=address(777);
  bytes memory parameters=args(cfg(),address(this),initial);assembly{mstore(add(parameters,576),not(0))}reject(parameters);
  for(uint padding; padding<3; padding++) {
   uint extra=padding==0?0:(padding==1?1:33);
   for(uint i;i<5;i++){
    parameters=bytes.concat(args(cfg(),address(this),new address[](0)),new bytes(extra));
    uint boundary=(type(uint64).max-576-parameters.length-320-32)/32;
    uint length=boundary+i-2;assembly{mstore(add(parameters,544),length)}reject(parameters);
   }
  }
  reject(args(cfg(),address(888),initial));
 }
 function testInitialRegistrationDecoderBeforeOwnerCheck() public {
  vm.warp(1000);(address a,)=deploy(true,args(cfg(),address(888),new address[](0)));
  (address b,)=deploy(false,args(cfg(),address(888),new address[](0)));require(a!=address(0)&&b!=address(0));
  for(uint mode;mode<7;mode++) {
   address[] memory initial=new address[](1);initial[0]=address(777);
   bytes memory data=abi.encodeWithSignature("registerInitialInitiatives(address[])",initial);
   if(mode==0){assembly{mstore(add(data,100),not(0))}}
   else if(mode<6){uint length=(type(uint64).max-128-32)/32+mode-3;assembly{mstore(add(data,68),length)}}
   (bool ok,bytes memory x)=a.call(data);(bool success,bytes memory y)=b.call(data);
   require(!ok&&!success&&keccak256(x)==keccak256(y),"initial decoder and ownership parity");
  }
 }
 function testReferenceConstructorAllocationBoundary() public {
  vm.warp(1000);
  for(uint padding; padding<3; padding++) {
   uint extra=padding==0?0:(padding==1?1:33);
   for(uint i;i<5;i++) {
    bytes memory parameters=bytes.concat(args(cfg(),address(this),new address[](0)),new bytes(extra));
    uint boundary=(type(uint64).max-576-parameters.length-320-32)/32;
    uint length=boundary+i-2;assembly{mstore(add(parameters,544),length)}
    (address a,bytes memory reason)=deploy(false,parameters);require(a==address(0));
    bytes memory expected=i>2?abi.encodeWithSignature("Panic(uint256)",uint(0x41)):bytes("");
    require(keccak256(reason)==keccak256(expected),"reference allocation boundary formula");
   }
  }
 }
}
