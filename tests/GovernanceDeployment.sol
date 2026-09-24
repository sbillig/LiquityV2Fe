// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
interface GDVm {
 function readFile(string calldata) external view returns(string memory);
 function parseBytes(string calldata) external pure returns(bytes memory);
}
library GovernanceDeployment {
 GDVm constant vm=GDVm(address(uint160(uint(keccak256("hevm cheat code")))));
 function module(string memory name) private returns(address deployed) {
  bytes memory init=vm.parseBytes(vm.readFile(string.concat("build/",name,".bin")));
  require(init.length<=49152,"module initcode size");
  assembly { deployed:=create(0,add(init,32),mload(init)) }
  require(deployed.code.length>0&&deployed.code.length<=24576,"module runtime size");
 }
 // Preserve arbitrary reference constructor inputs, including malformed array tails.
 // Three immutable module addresses extend the static head by 96 bytes.
 function parameters(bytes memory original) internal returns(bytes memory result) {
  require(original.length>=512,"reference constructor head");
  address staking=module("GovernanceStakingModule");
  address voting=module("GovernanceVotingModule");
  address actions=module("GovernanceActionsModule");
  result=new bytes(original.length+96);
  for(uint i;i<512;i++) result[i]=original[i];
  assembly {
   mstore(add(result,512),add(mload(add(original,512)),96))
   mstore(add(result,544),staking)
   mstore(add(result,576),voting)
   mstore(add(result,608),actions)
  }
  for(uint i=512;i<original.length;i++) result[i+96]=original[i];
 }
}
