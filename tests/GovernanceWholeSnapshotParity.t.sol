// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {GovernanceSnapshotParityTest} from "./GovernanceSnapshotParity.t.sol";
import {GovernanceDeployment} from "./GovernanceDeployment.sol";
import {IGovernance} from "../reference/bold/contracts/lib/V2-gov/src/interfaces/IGovernance.sol";
contract GovernanceWholeSnapshotParityTest is GovernanceSnapshotParityTest {
 function feInit(IGovernance.Configuration memory cfg) internal override returns(bytes memory init) {
  init=bytes.concat(vm.parseBytes(vm.readFile("build/Governance.bin")),GovernanceDeployment.parameters(abi.encode(address(1),address(2),address(3),bold,cfg,address(this),new address[](0))));
  require(init.length<=49152,"Governance initcode size");
 }
}
