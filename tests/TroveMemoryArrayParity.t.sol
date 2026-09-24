// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {PoolVm} from "./DefaultPoolParity.t.sol";
import {TroveDataVm} from "./TroveDataParity.t.sol";
contract SolidityMemoryArray {
    function batchLiquidateTroves(uint256[] memory ids) public pure returns(uint256){return ids.length;}
}
contract TroveMemoryArrayParityTest {
    PoolVm constant vm=PoolVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address a;SolidityMemoryArray b;
    function setUp() public {
        bytes memory code=vm.parseBytes(vm.readFile(string.concat(TroveDataVm(address(vm)).envOr("LIQUITY_MEMORY_ARRAY_ARTIFACTS","build"),"/MemoryArrayHarness.bin")));
        address created;assembly{created:=create(0,add(code,32),mload(code))}require(created.code.length>0);a=created;b=new SolidityMemoryArray();
    }
    function compare(bytes memory payload) internal {
        (bool x,bytes memory p)=a.call{gas:100000}(payload);(bool y,bytes memory q)=address(b).call{gas:100000}(payload);
        require(x==y&&keccak256(p)==keccak256(q),"array decoding mismatch");
    }
    function testMemoryAllocationBoundaries() public {
        uint[8] memory lengths=[uint(0),1,0x7fffffffffffff9,0x7fffffffffffffa,0x7fffffffffffffb,0x800000000000000,uint(type(uint64).max),type(uint).max];
        for(uint i;i<lengths.length;i++)compare(abi.encodePacked(b.batchLiquidateTroves.selector,uint(32),lengths[i]));
    }
    function testFuzzMemoryArrayHeader(uint offset,uint length) public {
        compare(abi.encodePacked(b.batchLiquidateTroves.selector,offset,length));
        compare(abi.encodePacked(b.batchLiquidateTroves.selector,uint(32),length));
    }
    function testFuzzMemoryArrayPayload(uint256[] memory ids) public {compare(abi.encodeCall(b.batchLiquidateTroves,(ids)));}
}
