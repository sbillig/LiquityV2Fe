// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {AddressesRegistry} from "../reference/bold/contracts/src/AddressesRegistry.sol";
interface RegistryVm {
    struct Log { bytes32[] topics; bytes data; address emitter; }
    function readFile(string calldata) external view returns (string memory);
    function parseBytes(string calldata) external pure returns (bytes memory);
    function prank(address) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
}
contract RegistryParityTest {
    RegistryVm constant vm=RegistryVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    bytes feCode;
    function setUp() public { feCode=vm.parseBytes(vm.readFile("build/AddressesRegistry.bin")); }
    function deploy(bytes memory code, bytes memory args) internal returns(address deployed,bytes memory error) {
        bytes memory input=bytes.concat(code,args);
        assembly {
            deployed := create(0,add(input,32),mload(input))
            let n := returndatasize()
            error := mload(0x40)
            mstore(error,n)
            returndatacopy(add(error,32),0,n)
            mstore(0x40,and(add(add(error,63),n),not(31)))
        }
    }
    function logsEqual(RegistryVm.Log[] memory a,RegistryVm.Log[] memory b) internal pure {
        require(a.length==b.length,"log count");
        for(uint i;i<a.length;i++) {
            require(keccak256(abi.encode(a[i].topics))==keccak256(abi.encode(b[i].topics)),"log topics");
            require(keccak256(a[i].data)==keccak256(b[i].data),"log data");
        }
    }
    function pair(bytes memory args) internal returns(address a,address b) {
        vm.recordLogs(); bytes memory x; (a,x)=deploy(feCode,args);
        RegistryVm.Log[] memory l=vm.getRecordedLogs();
        vm.recordLogs(); bytes memory y; (b,y)=deploy(type(AddressesRegistry).creationCode,args);
        logsEqual(l,vm.getRecordedLogs());
        require((a==address(0))==(b==address(0)),"constructor success");
        if(a==address(0)) require(keccak256(x)==keccak256(y),"constructor error");
    }
    function compare(address a,address b,address caller,bytes memory data) internal {
        vm.recordLogs();vm.prank(caller);(bool x,bytes memory rx)=a.call(data);
        RegistryVm.Log[] memory l=vm.getRecordedLogs();
        vm.recordLogs();vm.prank(caller);(bool y,bytes memory ry)=b.call(data);
        logsEqual(l,vm.getRecordedLogs());
        require(x==y,"call success");require(keccak256(rx)==keccak256(ry),"call result");
    }
    function validArgs(address owner) internal pure returns(bytes memory) {
        return abi.encode(owner,1.5e18,1.1e18,0.1e18,1.1e18,0.05e18,0.1e18);
    }
    function testFuzzConstructor(uint256 ccr,uint256 mcr,uint256 bcr,uint256 scr,uint256 sp,uint256 redist) public {
        pair(abi.encode(address(this),ccr,mcr,bcr,scr,sp,redist));
    }
    function testFuzzValidConstructor(uint256 seed) public {
        uint256 ccr=1e18+1+seed%(1e18-1);
        uint256 bcr=5e16+seed%45e16;
        uint256 sp=5e16+seed%(15e16+1);
        (address a,address b)=pair(abi.encode(address(this),ccr,ccr,bcr,ccr,sp,2e17));
        require(a!=address(0),"valid constructor");
        compareGetters(a,b);
    }
    function testConstructorBoundaries() public {
        uint256[6] memory defaults=[uint256(15e17),11e17,1e17,11e17,5e16,1e17];
        uint256[9] memory values=[uint256(0),5e16-1,5e16,2e17,2e17+1,5e17,1e18,1e18+1,2e18];
        for(uint i;i<6;i++) for(uint j;j<values.length;j++) {
            uint256[6] memory p=defaults;p[i]=values[j];
            pair(abi.encode(address(this),p));
        }
    }
    function testFuzzSetAddresses(address[18] memory values,address stranger) public {
        (address a,address b)=pair(validArgs(address(this)));
        bytes memory data=abi.encodePacked(AddressesRegistry.setAddresses.selector,abi.encode(values));
        if(stranger!=address(this)) compare(a,b,stranger,data);
        compareGetters(a,b);
        compare(a,b,address(this),data);
        compareGetters(a,b);
        compare(a,b,address(this),data); // owner is renounced; cannot set twice
    }
    function testMalformedAddressTuple() public {
        (address a,address b)=pair(validArgs(address(this)));
        for(uint i;i<18;i++) {
            uint256[18] memory words; words[i]=1<<160;
            compare(a,b,address(this),abi.encodePacked(AddressesRegistry.setAddresses.selector,abi.encode(words)));
        }
        compare(a,b,address(this),abi.encodePacked(AddressesRegistry.setAddresses.selector,uint256(0)));
    }
    function compareGetters(address a,address b) internal {
        compare(a,b,address(this),abi.encodeWithSignature("collToken()"));
        compare(a,b,address(this),abi.encodeWithSignature("borrowerOperations()"));
        compare(a,b,address(this),abi.encodeWithSignature("troveManager()"));
        compare(a,b,address(this),abi.encodeWithSignature("troveNFT()"));
        compare(a,b,address(this),abi.encodeWithSignature("metadataNFT()"));
        compare(a,b,address(this),abi.encodeWithSignature("stabilityPool()"));
        compare(a,b,address(this),abi.encodeWithSignature("priceFeed()"));
        compare(a,b,address(this),abi.encodeWithSignature("activePool()"));
        compare(a,b,address(this),abi.encodeWithSignature("defaultPool()"));
        compare(a,b,address(this),abi.encodeWithSignature("gasPoolAddress()"));
        compare(a,b,address(this),abi.encodeWithSignature("collSurplusPool()"));
        compare(a,b,address(this),abi.encodeWithSignature("sortedTroves()"));
        compare(a,b,address(this),abi.encodeWithSignature("interestRouter()"));
        compare(a,b,address(this),abi.encodeWithSignature("hintHelpers()"));
        compare(a,b,address(this),abi.encodeWithSignature("multiTroveGetter()"));
        compare(a,b,address(this),abi.encodeWithSignature("collateralRegistry()"));
        compare(a,b,address(this),abi.encodeWithSignature("boldToken()"));
        compare(a,b,address(this),abi.encodeWithSignature("WETH()"));
        compare(a,b,address(this),abi.encodeWithSignature("CCR()"));
        compare(a,b,address(this),abi.encodeWithSignature("MCR()"));
        compare(a,b,address(this),abi.encodeWithSignature("BCR()"));
        compare(a,b,address(this),abi.encodeWithSignature("SCR()"));
        compare(a,b,address(this),abi.encodeWithSignature("LIQUIDATION_PENALTY_SP()"));
        compare(a,b,address(this),abi.encodeWithSignature("LIQUIDATION_PENALTY_REDISTRIBUTION()"));
        compare(a,b,address(this),abi.encodeWithSignature("owner()"));
        compare(a,b,address(this),abi.encodeWithSignature("isOwner()"));
    }
}
