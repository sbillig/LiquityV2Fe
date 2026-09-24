// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {Governance} from "../reference/bold/contracts/lib/V2-gov/src/Governance.sol";
import {IGovernance} from "../reference/bold/contracts/lib/V2-gov/src/interfaces/IGovernance.sol";
import {UPVm,UPToken} from "./UserProxyParity.t.sol";
interface GSVm is UPVm {function warp(uint) external;function store(address,bytes32,bytes32) external;function load(address,bytes32) external view returns(bytes32);}
contract GovernanceSnapshotParityTest {
 GSVm constant vm=GSVm(address(uint160(uint(keccak256("hevm cheat code")))));
 address fe;address sol;UPToken bold;address constant TARGET=address(777);
 function feInit(IGovernance.Configuration memory) internal virtual returns(bytes memory){return bytes.concat(vm.parseBytes(vm.readFile("build/GovernanceSnapshotHarness.bin")),abi.encode(bold,uint(1000),uint(100),uint(1e18),uint(5e18),uint(1e16),uint(2e18),uint(4)));}
 function setUp() public {
  vm.warp(1000);bold=new UPToken();
  IGovernance.Configuration memory cfg=IGovernance.Configuration(0,1e16,2e18,4,1e16,1e18,5e18,1000,100,90);
  sol=address(new Governance(address(1),address(2),address(3),address(bold),cfg,address(this),new address[](0)));
  bytes memory init=feInit(cfg);
  address a;assembly{a:=create(0,add(init,32),mload(init))}require(a.code.length>0&&a.code.length<=24576,"snapshot runtime size");fe=a;
  bold.mint(fe,10e18);bold.mint(sol,10e18);
 }
 function put(uint slot,uint value) internal {vm.store(fe,bytes32(slot),bytes32(value));vm.store(sol,bytes32(slot),bytes32(value));}
 function map(uint root) internal pure returns(uint){return uint(keccak256(abi.encode(TARGET,root)));}
 function compare(bytes memory data) internal returns(bool){(bool ok,bytes memory a)=fe.call(data);(bool success,bytes memory b)=sol.call(data);require(ok==success&&keccak256(a)==keccak256(b),"snapshot parity");return ok;}
 function sameStorage() internal view {
  for(uint i=2;i<8;i++)require(vm.load(fe,bytes32(i))==vm.load(sol,bytes32(i)),"global storage");
  for(uint i;i<4;i++)require(vm.load(fe,bytes32(map(5)+i))==vm.load(sol,bytes32(map(5)+i)),"initiative storage");
 }
 function testFuzzSnapshotsAndUpdates(uint96 qty,uint96 offset,uint32 delta,uint16 seed) public {
  vm.warp(1000+uint(delta));put(2,seed);put(3,123);put(4,uint(seed)%20);put(6,qty);put(7,offset);
  for(uint i;i<4;i++)put(map(5)+i,uint(seed)+i);
  put(map(9),qty);put(map(9)+1,offset);put(map(9)+2,uint(qty)/2);put(map(9)+3,uint(offset)/2);put(map(9)+4,uint(seed)%20);put(map(11),1);
  compare(abi.encodeWithSignature("epoch()"));compare(abi.encodeWithSignature("epochStart()"));compare(abi.encodeWithSignature("secondsWithinEpoch()"));
  compare(abi.encodeWithSignature("getTotalVotesAndState()"));compare(abi.encodeWithSignature("getInitiativeSnapshotAndState(address)",TARGET));
  compare(abi.encodeWithSignature("calculateVotingThreshold()"));sameStorage();
  compare(abi.encodeWithSignature("getInitiativeState(address)",TARGET));sameStorage();
 }
 function testFuzzThresholdOverflow(uint votes,uint accrued) public {put(2,accrued);compare(abi.encodeWithSignature("calculateVotingThreshold(uint256)",votes));}
 function testStatusPrecedenceAndZeroVotes() public {
  vm.warp(2000);
  IGovernance.VoteSnapshot memory votes=IGovernance.VoteSnapshot(100,10);
  IGovernance.InitiativeVoteSnapshot memory ivotes=IGovernance.InitiativeVoteSnapshot(50,10,4,10);
  IGovernance.InitiativeState memory state=IGovernance.InitiativeState(10,0,2,0,1);
  bytes memory data=abi.encodeWithSignature("getInitiativeState(address,(uint256,uint256),(uint256,uint256,uint256,uint256),(uint256,uint256,uint256,uint256,uint256))",TARGET,votes,ivotes,state);
  put(2,10e18);
  uint[4] memory registrations=[uint(0),11,type(uint).max,uint(1)];
  for(uint i;i<4;i++){put(map(11),registrations[i]);for(uint last;last<12;last++){put(map(9)+4,last);compare(data);}}
  put(map(9)+4,0);
  for(uint mode;mode<4;mode++){
   ivotes.votes=mode==0?50:0;ivotes.vetos=mode==1?99:0;state.lastEpochClaim=mode==2?10:1;
   compare(abi.encodeWithSignature("getInitiativeState(address,(uint256,uint256),(uint256,uint256,uint256,uint256),(uint256,uint256,uint256,uint256,uint256))",TARGET,votes,ivotes,state));
  }
  ivotes.votes=50;ivotes.vetos=0;votes.votes=0;
  compare(abi.encodeWithSignature("getInitiativeState(address,(uint256,uint256),(uint256,uint256,uint256,uint256),(uint256,uint256,uint256,uint256,uint256))",TARGET,votes,ivotes,state));
 }
}
