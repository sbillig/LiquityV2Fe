// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {bauhaus} from "../reference/bold/contracts/src/NFTMetadata/utils/bauhaus.sol";
import {json} from "../reference/bold/contracts/src/NFTMetadata/utils/JSON.sol";
import {numUtils, LibString} from "../reference/bold/contracts/src/NFTMetadata/utils/Utils.sol";
import {PoolVm} from "./DefaultPoolParity.t.sol";
interface MetadataEnvVm {function envOr(string calldata,string calldata) external returns(string memory);}
contract MetadataPrimitivesReference {
    function bauhausImage(string memory symbol,uint256 id) external pure returns(string memory){return bauhaus._bauhaus(symbol,id);}
    function decimal(uint256 value) external pure returns(string memory){return LibString.toString(value);}
    function hexNumber(uint256 value) external pure returns(string memory){return LibString.toHexString(value);}
    function hexAddress(address value) external pure returns(string memory){return LibString.toHexString(value);}
    function checksum(address value) external pure returns(string memory){return LibString.toHexStringChecksummed(value);}
    function slice(string memory value,uint256 start,uint256 end) external pure returns(string memory){return LibString.slice(value,start,end);}
    function base64(string memory value) external pure returns(string memory){return json.encode(bytes(value));}
    function locale(uint256 value,uint8 divisor,uint8 precision) external pure returns(string memory){return numUtils.toLocaleString(value,divisor,precision);}
}
contract MetadataPrimitivesParityTest {
    PoolVm constant vm=PoolVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    MetadataPrimitivesReference a;MetadataPrimitivesReference b;
    function setUp() public {
        bytes memory code=vm.parseBytes(vm.readFile(string.concat(MetadataEnvVm(address(vm)).envOr("LIQUITY_TEST_ARTIFACTS","build"),"/MetadataPrimitivesHarness.bin")));address created;
        assembly{created:=create(0,add(code,32),mload(code))}
        require(created.code.length>0);a=MetadataPrimitivesReference(created);b=new MetadataPrimitivesReference();
    }
    function compare(bytes memory data) internal view returns(bool) {
        (bool x,bytes memory p)=address(a).staticcall(data);(bool y,bytes memory q)=address(b).staticcall(data);
        require(x==y,"success mismatch");require(keccak256(p)==keccak256(q),"return/revert mismatch");return x;
    }
    function compareSuccess(bytes memory data) internal view {require(compare(data),"expected successful primitive");}
    function testBauhausAllVariants() public view {
        string[4] memory symbols=["WETH","wstETH","rETH","unknown"];
        for(uint i;i<symbols.length;i++)for(uint j;j<4;j++)compareSuccess(abi.encodeCall(a.bauhausImage,(symbols[i],j)));
    }
    function testFuzzBauhaus(string memory symbol,uint256 id) public view {compareSuccess(abi.encodeCall(a.bauhausImage,(symbol,id)));}
    function testFuzzNumbers(uint256 value,address account) public view {
        compareSuccess(abi.encodeCall(a.decimal,(value)));compareSuccess(abi.encodeCall(a.hexNumber,(value)));
        compareSuccess(abi.encodeCall(a.hexAddress,(account)));compareSuccess(abi.encodeCall(a.checksum,(account)));
    }
    function testFuzzStrings(string memory value,uint256 start,uint256 end) public view {
        compareSuccess(abi.encodeCall(a.base64,(value)));compareSuccess(abi.encodeCall(a.slice,(value,start,end)));
        compareSuccess(abi.encodeCall(a.slice,(value,start%(bytes(value).length+1),end%(bytes(value).length+1))));
    }
    function testFuzzLocale(uint256 value,uint8 divisor,uint8 precision) public view {compare(abi.encodeCall(a.locale,(value,divisor,precision)));}
    function testRendererFormattingBoundaries() public view {
        uint256[9] memory values=[uint256(0),1,9,10,999,1000,1e18-1,1e18,type(uint256).max];
        for(uint i;i<values.length;i++) {
            compareSuccess(abi.encodeCall(a.decimal,(values[i])));compareSuccess(abi.encodeCall(a.hexNumber,(values[i])));
            compare(abi.encodeCall(a.locale,(values[i],18,4)));compare(abi.encodeCall(a.locale,(values[i],18,2)));compare(abi.encodeCall(a.locale,(values[i],16,2)));
            for(uint8 d;d<5;d++)for(uint8 p;p<5;p++)compare(abi.encodeCall(a.locale,(values[i],d,p)));
        }
        compareSuccess(abi.encodeCall(a.base64,("")));compareSuccess(abi.encodeCall(a.base64,("f")));compareSuccess(abi.encodeCall(a.base64,("fo")));compareSuccess(abi.encodeCall(a.base64,("foo")));
    }
}
