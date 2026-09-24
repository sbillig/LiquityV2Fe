// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {LeftoversSweep,IERC20} from "../reference/bold/contracts/src/Zappers/LeftoversSweep.sol";
interface SweepVm {function readFile(string calldata) external view returns(string memory);function parseBytes(string calldata) external pure returns(bytes memory);}
interface SweepDriver {function execute() external;}
contract SolidityLeftoversHarness is LeftoversSweep {
 function sweep(address[4] memory tokens,address receiver,address driver) external {
  InitialBalances memory initial;for(uint i;i<4;i++)initial.tokens[i]=IERC20(tokens[i]);
  _setInitialBalancesAndReceiver(initial,receiver);SweepDriver(driver).execute();_returnLeftovers(initial);
 }
}
contract SweepToken {
 mapping(address=>uint) public balanceOf;bool public failed;
 function setFailed(bool value) external {failed=value;}
 function mint(address to,uint value) external {balanceOf[to]+=value;}
 function burn(address from,uint value) external {balanceOf[from]-=value;}
 function transfer(address to,uint value) external returns(bool){balanceOf[msg.sender]-=value;balanceOf[to]+=value;return !failed;}
}
contract LeftoversParityTest {
 SweepVm constant vm=SweepVm(address(uint160(uint(keccak256("hevm cheat code")))));
 SolidityLeftoversHarness actual;SolidityLeftoversHarness expected;SweepToken[4] tokens;uint[4] changes;bool draining;
 function setUp() public {bytes memory init=vm.parseBytes(vm.readFile("build/LeftoversHarness.bin"));address target;assembly{target:=create(0,add(init,32),mload(init))}require(target.code.length>0);actual=SolidityLeftoversHarness(target);expected=new SolidityLeftoversHarness();for(uint i;i<4;i++){tokens[i]=new SweepToken();tokens[i].mint(address(actual),100);tokens[i].mint(address(expected),100);}}
 function execute() external {for(uint i;i<4;i++){if(draining)tokens[i].burn(msg.sender,changes[i]);else tokens[i].mint(msg.sender,changes[i]);}}
 function compare(address[4] memory list) internal returns(bool){bytes memory data=abi.encodeCall(actual.sweep,(list,address(this),address(this)));(bool ok,bytes memory a)=address(actual).call(data);(bool success,bytes memory b)=address(expected).call(data);require(ok==success&&keccak256(a)==keccak256(b),"parity");for(uint i;i<4;i++)require(tokens[i].balanceOf(address(actual))==tokens[i].balanceOf(address(expected)),"token balance");return ok;}
 function testSentinelDuplicatesAndExistingBalances() public {
  changes=[uint(10),20,30,40];address[4] memory list=[address(tokens[0]),address(tokens[1]),address(0),address(tokens[3])];require(compare(list));require(tokens[0].balanceOf(address(this))==20);require(tokens[2].balanceOf(address(actual))==130);
  list=[address(tokens[0]),address(tokens[0]),address(tokens[2]),address(tokens[3])];require(compare(list));require(tokens[0].balanceOf(address(this))==40);require(tokens[1].balanceOf(address(actual))==120);
 }
 function testDrainingAndFailedTransferRollback() public {
  address[4] memory list=[address(tokens[0]),address(tokens[1]),address(tokens[2]),address(tokens[3])];changes=[uint(10),20,30,40];draining=true;require(compare(list));require(tokens[0].balanceOf(address(this))==0);require(tokens[0].balanceOf(address(actual))==90);
  draining=false;tokens[2].setFailed(true);require(!compare(list));require(tokens[0].balanceOf(address(this))==0);require(tokens[0].balanceOf(address(actual))==90);
 }
 function testFuzzAmountsAndPrefix(uint64 a,uint64 b,uint64 c,uint64 d,uint8 stop) public {
  changes=[uint(a),uint(b),uint(c),uint(d)];address[4] memory list;uint n=uint(stop)%5;for(uint i;i<n;i++)list[i]=address(tokens[i]);require(compare(list));for(uint i;i<4;i++){require(tokens[i].balanceOf(address(actual))==100+(i<n?0:changes[i]));require(tokens[i].balanceOf(address(this))==(i<n?changes[i]*2:0));}
 }
}
