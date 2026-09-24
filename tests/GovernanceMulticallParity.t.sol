// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {MultiDelegateCall} from "../reference/bold/contracts/lib/V2-gov/src/utils/MultiDelegateCall.sol";
import {UPVm} from "./UserProxyParity.t.sol";
contract GMultiReference is MultiDelegateCall {
 uint public value;
 function add(uint n) external returns(address,uint){value+=n;return(msg.sender,value);}
 function echo(bytes calldata data) external pure returns(bytes memory){return data;}
 function fail(bytes memory data) external pure {assembly{revert(add(data,32),mload(data))}}
}
contract GovernanceMulticallParityTest {
 UPVm constant vm=UPVm(address(uint160(uint(keccak256("hevm cheat code")))));
 address fe;address sol;
 function setUp() public {bytes memory code=vm.parseBytes(vm.readFile("build/GovernanceMulticallHarness.bin"));address a;assembly{a:=create(0,add(code,32),mload(code))}require(a.code.length>0);fe=a;sol=address(new GMultiReference());}
 function compare(bytes memory data) internal returns(bool){(bool ok,bytes memory a)=fe.call(data);(bool success,bytes memory b)=sol.call(data);require(ok==success&&keccak256(a)==keccak256(b),"multicall parity");return ok;}
 function multi(bytes[] memory inputs) internal pure returns(bytes memory){return abi.encodeWithSignature("multiDelegateCall(bytes[])",inputs);}
 function testFuzzNestedCallsAndDynamicReturns(bytes memory payload,uint96 amount) public {
  bytes[] memory inner=new bytes[](2);inner[0]=abi.encodeWithSignature("add(uint256)",uint(amount));inner[1]=abi.encodeWithSignature("echo(bytes)",payload);
  bytes[] memory outer=new bytes[](3);outer[0]=multi(inner);outer[1]=abi.encodeWithSignature("add(uint256)",uint(7));outer[2]=multi(new bytes[](0));
  require(compare(multi(outer)),"nested success");require(compare(abi.encodeWithSignature("value()")),"state");
 }
 function testRevertBubblingLazyDecodeAndRollback() public {
  bytes[] memory inputs=new bytes[](2);inputs[0]=abi.encodeWithSignature("fail(bytes)",hex"feedbeef");inputs[1]=hex"00";
  bytes memory data=multi(inputs);assembly{mstore(add(data,132),0xffffffffffffffff)}
  require(!compare(data),"first revert before malformed second entry");
  inputs[0]=abi.encodeWithSignature("add(uint256)",uint(9));inputs[1]=abi.encodeWithSignature("fail(bytes)",hex"aabbcc");require(!compare(multi(inputs)),"rollback");
  require(compare(abi.encodeWithSignature("value()")),"equal state");(,bytes memory result)=fe.call(abi.encodeWithSignature("value()"));require(abi.decode(result,(uint))==0,"atomic batch");
 }
 function testFuzzMalformedInput(bytes memory payload) public {compare(bytes.concat(bytes4(0x415c2d96),payload));}
 function testOffsetBoundaries() public {
  uint[8] memory values=[uint(0),1,31,32,type(uint64).max,uint(1)<<64,type(uint).max,type(uint).max-31];
  for(uint i;i<8;i++)compare(bytes.concat(bytes4(0x415c2d96),abi.encode(values[i],uint(0),uint(0))));
  bytes[] memory inputs=new bytes[](1);inputs[0]=abi.encodeWithSignature("value()");
  for(uint i;i<8;i++){bytes memory data=multi(inputs);uint off=values[i];assembly{mstore(add(data,100),off)}compare(data);}
 }
}
