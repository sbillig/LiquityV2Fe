// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {FixedAssetReader} from "../reference/bold/contracts/src/NFTMetadata/utils/FixedAssets.sol";
import {SSTORE2} from "Solady/utils/SSTORE2.sol";
import {PoolVm} from "./DefaultPoolParity.t.sol";
import {StorageVm} from "./SortedTrovesParity.t.sol";
interface AssetVm {function etch(address,bytes calldata) external;}
contract FixedAssetReaderParityTest {
    PoolVm constant vm=PoolVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    FixedAssetReader a;FixedAssetReader b;
    function deploy(address pointer,bytes4[] memory sigs,FixedAssetReader.Asset[] memory assets) internal {
        bytes memory code=bytes.concat(vm.parseBytes(vm.readFile("build/FixedAssetReader.bin")),abi.encode(pointer,sigs,assets));
        address created;assembly{created:=create(0,add(code,32),mload(code))}
        require(created.code.length>0,"Fe deployment");a=FixedAssetReader(created);b=new FixedAssetReader(pointer,sigs,assets);
        require(a.pointer()==b.pointer(),"pointer");
        for(uint i;i<sigs.length;i++) {
            (uint128 sa,uint128 ea)=a.assets(sigs[i]);(uint128 sb,uint128 eb)=b.assets(sigs[i]);require(sa==sb&&ea==eb,"asset fields");
            bytes32 slot=keccak256(abi.encode(sigs[i],uint256(0)));
            require(StorageVm(address(vm)).load(address(a),slot)==StorageVm(address(vm)).load(address(b),slot),"packed storage");
        }
    }
    function compare(bytes4 sig) internal view {
        bytes memory data=abi.encodeCall(a.readAsset,(sig));
        (bool x,bytes memory p)=address(a).staticcall{gas:500000}(data);
        (bool y,bytes memory q)=address(b).staticcall{gas:500000}(data);
        require(x==y&&keccak256(p)==keccak256(q),"read mismatch");
    }
    function testFuzzSlices(bytes memory data,uint128 start,uint128 end) public {
        if(data.length>1024)return;
        bytes4[] memory sigs=new bytes4[](4);FixedAssetReader.Asset[] memory assets=new FixedAssetReader.Asset[](4);
        sigs[0]=0x11223344;sigs[1]=0;sigs[2]=0xabcdef01;sigs[3]=0x11223344;
        assets[0]=FixedAssetReader.Asset(0,1);assets[1]=FixedAssetReader.Asset(start,end);
        assets[2]=FixedAssetReader.Asset(uint128(start%(data.length+1)),uint128(end%(data.length+1)));
        assets[3]=FixedAssetReader.Asset(0,type(uint128).max);
        deploy(SSTORE2.write(data),sigs,assets);
        for(uint i;i<4;i++)compare(sigs[i]);compare(0xffffffff);
        require(keccak256(bytes(a.readAsset(sigs[3])))==keccak256(data),"full data");
    }
    function testBoundaryAndNonSstorePointers() public {
        bytes4[] memory sigs=new bytes4[](7);FixedAssetReader.Asset[] memory assets=new FixedAssetReader.Asset[](7);
        assets[0]=FixedAssetReader.Asset(0,0);assets[1]=FixedAssetReader.Asset(0,1);assets[2]=FixedAssetReader.Asset(1,0);
        assets[3]=FixedAssetReader.Asset(0,type(uint128).max);assets[4]=FixedAssetReader.Asset(type(uint128).max,0);
        assets[5]=FixedAssetReader.Asset(2,4);assets[6]=FixedAssetReader.Asset(type(uint128).max,type(uint128).max);
        for(uint i;i<7;i++)sigs[i]=bytes4(uint32(i));
        address pointer=address(0xface);
        bytes[4] memory code=[bytes(hex""),bytes(hex"00"),bytes(hex"ff0001ff00"),bytes(hex"0011223344")];
        for(uint j;j<code.length;j++){AssetVm(address(vm)).etch(pointer,code[j]);deploy(pointer,sigs,assets);for(uint i;i<7;i++)compare(sigs[i]);}
    }
    function testMaximumEndCap() public {
        bytes memory code=new bytes(65540);for(uint i;i<code.length;i++)code[i]=bytes1(uint8(i));
        address pointer=address(0xface);AssetVm(address(vm)).etch(pointer,code);
        bytes4[] memory sigs=new bytes4[](2);sigs[1]=0xffffffff;
        FixedAssetReader.Asset[] memory assets=new FixedAssetReader.Asset[](2);
        assets[0]=FixedAssetReader.Asset(65533,65539);assets[1]=FixedAssetReader.Asset(65535,type(uint128).max);
        deploy(pointer,sigs,assets);compare(sigs[0]);compare(sigs[1]);require(bytes(a.readAsset(sigs[0])).length==2);
    }
    function testMismatchedConstructorLengths() public {
        bytes4[] memory sigs=new bytes4[](1);FixedAssetReader.Asset[] memory assets=new FixedAssetReader.Asset[](0);
        bytes memory code=bytes.concat(vm.parseBytes(vm.readFile("build/FixedAssetReader.bin")),abi.encode(address(0),sigs,assets));
        address created;bytes memory reason;
        assembly{created:=create(0,add(code,32),mload(code)) reason:=mload(0x40) mstore(reason,returndatasize()) returndatacopy(add(reason,32),0,returndatasize()) mstore(0x40,add(add(reason,32),and(add(returndatasize(),31),not(31))))}
        require(created==address(0));
        try new FixedAssetReader(address(0),sigs,assets){revert("unexpected success");}catch(bytes memory refReason){require(keccak256(reason)==keccak256(refReason),"constructor revert");}
    }
}
