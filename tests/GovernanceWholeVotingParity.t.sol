// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {GovernanceVotingParityTest} from "./GovernanceVotingParity.t.sol";
import {GovernanceDeployment} from "./GovernanceDeployment.sol";
import {Governance} from "../reference/bold/contracts/lib/V2-gov/src/Governance.sol";
import {IGovernance} from "../reference/bold/contracts/lib/V2-gov/src/interfaces/IGovernance.sol";
import {UPToken} from "./UserProxyParity.t.sol";
import {GAStaking} from "./GovernanceActionsParity.t.sol";
contract GovernanceWholeVotingParityTest is GovernanceVotingParityTest {
 function feInit(UPToken bold,GAStaking staking) internal override returns(bytes memory init) {
  IGovernance.Configuration memory cfg=IGovernance.Configuration(7,1e16,2e18,4,1e16,1e18,5e18,1000,100,90);
  init=bytes.concat(vm.parseBytes(vm.readFile("build/Governance.bin")),GovernanceDeployment.parameters(abi.encode(address(1),address(2),staking,bold,cfg,address(this),new address[](0))));
  require(init.length<=49152,"Governance initcode size");
 }
 function make(bool fe,uint qty,uint offset) internal override returns(Governance p) {
  p=super.make(fe,qty,offset);require(address(p).code.length<=24576,"Governance runtime size");
 }
}
