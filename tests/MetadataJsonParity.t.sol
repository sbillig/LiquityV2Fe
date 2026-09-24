// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {json} from "../reference/bold/contracts/src/NFTMetadata/utils/JSON.sol";
interface JVm {
 function readFile(string calldata) external view returns(string memory);
 function parseBytes(string calldata) external pure returns(bytes memory);
}
contract MetadataJsonReference {
 function property(string memory key,string memory value,bool last) external pure returns(string memory){return json._prop(key,value,last);}
 function property(string memory key,string memory value) external pure returns(string memory){return json._prop(key,value);}
 function object(string memory key,string memory value) external pure returns(string memory){return json._object(key,value);}
 function xmlImage(string memory svg) external pure returns(string memory){return json._xmlImage(svg);}
 function encode(bytes memory value) external pure returns(string memory){return json.encode(value);}
 function formattedMetadata(string memory name,string memory description,string memory svg,string memory attributes) external pure returns(string memory){return json.formattedMetadata(name,description,svg,attributes);}
}
contract MetadataJsonParityTest {
 JVm constant vm=JVm(address(uint160(uint(keccak256("hevm cheat code")))));
 address fe;address sol;
 function setUp() public {
  bytes memory init=vm.parseBytes(vm.readFile("build/MetadataJsonHarness.bin"));address a;
  assembly{a:=create(0,add(init,32),mload(init))}require(a.code.length>0&&a.code.length<=24576,"deploy");fe=a;sol=address(new MetadataJsonReference());
 }
 function compare(bytes memory data) internal {
  (bool ok,bytes memory a)=fe.call(data);(bool success,bytes memory b)=sol.call(data);
  require(ok&&success&&keccak256(a)==keccak256(b),"JSON parity");
 }
 function testFuzzAllPropertiesAndEncoding(string memory key,string memory value,bool last) public {
  compare(abi.encodeWithSignature("property(string,string,bool)",key,value,last));
  compare(abi.encodeWithSignature("property(string,string)",key,value));
  compare(abi.encodeWithSignature("object(string,string)",key,value));
  compare(abi.encodeWithSignature("xmlImage(string)",value));
  compare(abi.encodeWithSignature("encode(bytes)",bytes(value)));
 }
 function testFuzzFormattedMetadata(string memory name,string memory description,string memory svg,string memory attributes) public {
  compare(abi.encodeWithSignature("formattedMetadata(string,string,string,string)",name,description,svg,attributes));
 }
 function testEmptyAndRawQuoteBytes() public {
  compare(abi.encodeWithSignature("formattedMetadata(string,string,string,string)","","","","[]"));
  bytes memory key=hex"00225cff";bytes memory value=hex"5c220a00";
  compare(abi.encodeWithSignature("property(string,string,bool)",string(key),string(value),true));
  for(uint i;i<7;i++)compare(abi.encodeWithSignature("encode(bytes)",new bytes(i)));
 }
}
