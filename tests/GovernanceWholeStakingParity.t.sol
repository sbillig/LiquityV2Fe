// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {GovernanceDeployment} from "./GovernanceDeployment.sol";
import {GovernanceStakingParityTest} from "./GovernanceStakingParity.t.sol";
import {Governance} from "../reference/bold/contracts/lib/V2-gov/src/Governance.sol";
import {IGovernance} from "../reference/bold/contracts/lib/V2-gov/src/interfaces/IGovernance.sol";
import {UPToken,UPStaking} from "./UserProxyParity.t.sol";
contract GovernanceWholeStakingParityTest is GovernanceStakingParityTest {
 function make(bool fe) internal override returns(Governance p,UPToken lqty,UPToken lusd,UPStaking v1){
  if(!fe)return super.make(false);
  vm.warp(1000);lqty=new UPToken();lusd=new UPToken();v1=new UPStaking(lqty,lusd);vm.deal(address(v1),1e24);
  IGovernance.Configuration memory cfg=IGovernance.Configuration(0,1e16,2e18,4,1e16,1e18,5e18,1000,100,90);
  bytes memory init=bytes.concat(vm.parseBytes(vm.readFile("build/Governance.bin")),GovernanceDeployment.parameters(abi.encode(lqty,lusd,v1,address(4),cfg,address(this),new address[](0))));
  require(init.length<=49152,"EIP3860 initcode limit");address a;assembly{a:=create(0,add(init,32),mload(init))}
  require(a.code.length>0&&a.code.length<=24576,"EIP170 runtime limit");p=Governance(a);
 }
 function batchRun(bool fe,bool fail) internal returns(bytes32) {
  (Governance p,UPToken token,,UPStaking v1)=make(fe);token.mint(address(this),100);
  bytes[] memory nested=new bytes[](2);
  nested[0]=abi.encodeWithSignature("depositLQTY(uint256)",uint(60));
  nested[1]=abi.encodeWithSignature("depositLQTY(uint256)",uint(40));
  bytes[] memory calls=new bytes[](3);
  calls[0]=abi.encodeWithSignature("multiDelegateCall(bytes[])",nested);
  calls[1]=abi.encodeWithSignature("withdrawLQTY(uint256,bool,address)",fail?uint(101):uint(25),false,address(this));
  calls[2]=abi.encodeWithSignature("userStates(address)",address(this));
  (bool ok,bytes memory result)=address(p).call(abi.encodeWithSignature("multiDelegateCall(bytes[])",calls));
  require(ok!=fail,"batch outcome");address proxy=p.deriveUserProxyAddress(address(this));
  require(v1.stakes(proxy)==(fail?0:75),"batch stake");
  if(fail)require(proxy.code.length==0&&token.balanceOf(address(this))==100,"batch deployment rollback");
  return keccak256(abi.encode(ok,result,stateHash(p),token.balanceOf(address(this))));
 }
 function testNestedStakingMulticallAndRollback() public {
  require(batchRun(true,false)==batchRun(false,false),"connected multicall parity");
  require(batchRun(true,true)==batchRun(false,true),"connected rollback parity");
 }
}
