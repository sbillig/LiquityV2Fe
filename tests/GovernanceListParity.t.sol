// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {DoubleLinkedList} from "../reference/bold/contracts/lib/V2-gov/src/utils/DoubleLinkedList.sol";
import {UPVm} from "./UserProxyParity.t.sol";
contract GovListReference {
 using DoubleLinkedList for DoubleLinkedList.List;
 DoubleLinkedList.List private list;
 function item(uint id) external view returns(uint,uint,uint,uint){DoubleLinkedList.Item memory i=list.getItem(id);return(i.lqty,i.offset,i.prev,i.next);}
 function ends() external view returns(uint,uint){return(list.getHead(),list.getTail());}
 function contains(uint id) external view returns(bool){return list.contains(id);}
 function insert(uint id,uint lqty,uint offset,uint next) external {list.insert(id,lqty,offset,next);}
}
contract GovernanceListParityTest {
 UPVm constant vm=UPVm(address(uint160(uint(keccak256("hevm cheat code")))));
 address fe;address sol;
 function setUp() public {bytes memory code=vm.parseBytes(vm.readFile("build/GovernanceListHarness.bin"));address a;assembly{a:=create(0,add(code,32),mload(code))}require(a.code.length>0);fe=a;sol=address(new GovListReference());}
 function compare(bytes memory data) internal returns(bool){(bool ok,bytes memory a)=fe.call(data);(bool success,bytes memory b)=sol.call(data);require(ok==success&&keccak256(a)==keccak256(b),"list parity");return ok;}
 function check(uint n) internal {compare(abi.encodeWithSignature("ends()"));for(uint i;i<=n;i++){compare(abi.encodeWithSignature("item(uint256)",i));compare(abi.encodeWithSignature("contains(uint256)",i));}}
 function testFuzzInsertionAndSentinel(uint seed) public {
  check(1);
  for(uint i=1;i<=16;i++){
   seed=uint(keccak256(abi.encode(seed,i)));uint next=seed%i;
   require(compare(abi.encodeWithSignature("insert(uint256,uint256,uint256,uint256)",i,seed,type(uint).max-seed,next)),"insert");check(i+1);
  }
  require(!compare(abi.encodeWithSignature("insert(uint256,uint256,uint256,uint256)",uint(0),uint(1),uint(2),uint(0))),"zero id");
  require(!compare(abi.encodeWithSignature("insert(uint256,uint256,uint256,uint256)",uint(1),uint(1),uint(2),uint(99))),"duplicate before missing successor");
  require(!compare(abi.encodeWithSignature("insert(uint256,uint256,uint256,uint256)",uint(17),uint(1),uint(2),uint(99))),"missing successor");check(18);
 }
}
