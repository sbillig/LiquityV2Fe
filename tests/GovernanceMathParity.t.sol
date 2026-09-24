// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {abs as absolute,add as addition,sub as subtraction,max as maximum} from "../reference/bold/contracts/lib/V2-gov/src/utils/Math.sol";
import {_lqtyToVotes} from "../reference/bold/contracts/lib/V2-gov/src/utils/VotingPower.sol";
import {UPVm} from "./UserProxyParity.t.sol";
contract GovMathReference {
 function abs(int value) external pure returns(uint){return absolute(value);}
 function add(uint a,int b) external pure returns(uint){return addition(a,b);}
 function sub(uint a,int b) external pure returns(uint){return subtraction(a,b);}
 function max(uint a,uint b) external pure returns(uint){return maximum(a,b);}
 function votes(uint a,uint t,uint o) external pure returns(uint){return _lqtyToVotes(a,t,o);}
}
contract GovernanceMathParityTest {
 UPVm constant vm=UPVm(address(uint160(uint(keccak256("hevm cheat code")))));
 address fe;address sol;
 function setUp() public {
  bytes memory code=vm.parseBytes(vm.readFile("build/GovernanceMathHarness.bin"));address a;assembly{a:=create(0,add(code,32),mload(code))}require(a.code.length>0);fe=a;sol=address(new GovMathReference());
 }
 function compare(bytes memory data) internal view {
  (bool ok,bytes memory a)=fe.staticcall(data);(bool success,bytes memory b)=sol.staticcall(data);require(ok==success&&keccak256(a)==keccak256(b),"math parity");
 }
 function testFuzzSignedArithmetic(uint a,int b) public view {
  compare(abi.encodeWithSignature("abs(int256)",b));compare(abi.encodeWithSignature("add(uint256,int256)",a,b));compare(abi.encodeWithSignature("sub(uint256,int256)",a,b));compare(abi.encodeWithSignature("max(uint256,uint256)",a,uint(b)));
 }
 function testFuzzVotes(uint a,uint t,uint o) public view {compare(abi.encodeWithSignature("votes(uint256,uint256,uint256)",a,t,o));}
 function testFuzzBoundedVotes(uint96 a,uint96 t,uint o) public view {compare(abi.encodeWithSignature("votes(uint256,uint256,uint256)",uint(a),uint(t),o));}
 function testArithmeticBoundaries() public view {
  uint[4] memory values=[uint(0),1,uint(type(int).max),type(uint).max];
  int[5] memory signedValues=[type(int).min,int(-1),int(0),int(1),type(int).max];
  for(uint i;i<4;i++)for(uint j;j<5;j++)testFuzzSignedArithmetic(values[i],signedValues[j]);
  compare(abi.encodeWithSignature("votes(uint256,uint256,uint256)",type(uint).max,uint(2),type(uint).max));
 }
}
