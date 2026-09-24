// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {utils,numUtils} from "../reference/bold/contracts/src/NFTMetadata/utils/Utils.sol";
contract MetadataUtilsReference {
 function toLocale(string memory value) external pure returns(string memory) { return numUtils.toLocale(value); }
 function toLocaleString(uint256 value,uint8 divisor,uint8 precision) external pure returns(string memory) { return numUtils.toLocaleString(value,divisor,precision); }
 function setCssVar(string memory key,string memory value) external pure returns(string memory) { return utils.setCssVar(key,value); }
 function getCssVar(string memory key) external pure returns(string memory) { return utils.getCssVar(key); }
 function getDefURL(string memory key) external pure returns(string memory) { return utils.getDefURL(key); }
 function white_a(uint256 alpha) external pure returns(string memory) { return utils.white_a(alpha); }
 function black_a(uint256 alpha) external pure returns(string memory) { return utils.black_a(alpha); }
 function rgba(uint256 r,uint256 g,uint256 b,uint256 a) external pure returns(string memory) { return utils.rgba(r,g,b,a); }
 function cssBraces(string memory key,string memory value) external pure returns(string memory) { return utils.cssBraces(key,value); }
 function cssBraces(string[] memory keys,string[] memory values) external pure returns(string memory) { return utils.cssBraces(keys,values); }
 function points(uint256[2][] memory values) external pure returns(string memory) { return utils.points(values); }
 function points(uint256[2][] memory values,uint256 precision) external pure returns(string memory) { return utils.points(values,precision); }
 function stringsEqual(string memory a,string memory b) external pure returns(bool) { return utils.stringsEqual(a,b); }
 function utfStringLength(string memory value) external pure returns(uint256) { return utils.utfStringLength(value); }
 function toString(uint256 value,uint256 precision) external pure returns(string memory) { return utils.toString(value,precision); }
}
interface UVm {
 function readFile(string calldata) external view returns(string memory);
 function parseBytes(string calldata) external pure returns(bytes memory);
}
contract MetadataUtilsParityTest {
 UVm constant vm=UVm(address(uint160(uint(keccak256("hevm cheat code")))));
 address fe;address sol;
 function setUp() public {
  bytes memory init=vm.parseBytes(vm.readFile("build/MetadataUtilsHarness.bin"));address a;
  assembly{a:=create(0,add(init,32),mload(init))}
  require(a.code.length>0&&a.code.length<=24576,"deploy");fe=a;sol=address(new MetadataUtilsReference());
 }
 function compare(bytes memory data) internal {
  (bool ok,bytes memory a)=fe.call(data);(bool success,bytes memory b)=sol.call(data);
  require(ok==success&&keccak256(a)==keccak256(b),"Utils parity");
 }
 function testFuzzStrings(string memory key,string memory value) public {
  compare(abi.encodeWithSignature("toLocale(string)",value));
  compare(abi.encodeWithSignature("setCssVar(string,string)",key,value));
  compare(abi.encodeWithSignature("getCssVar(string)",key));
  compare(abi.encodeWithSignature("getDefURL(string)",key));
  compare(abi.encodeWithSignature("cssBraces(string,string)",key,value));
  compare(abi.encodeWithSignature("stringsEqual(string,string)",key,value));
  compare(abi.encodeWithSignature("stringsEqual(string,string)",key,key));
  compare(abi.encodeWithSignature("utfStringLength(string)",value));
 }
 function testFuzzNumeric(uint256 value,uint256 precision,uint8 divisor,uint8 decimals,uint256 green,uint256 blue,uint256 alpha) public {
  compare(abi.encodeWithSignature("toString(uint256,uint256)",value,precision));
  compare(abi.encodeWithSignature("toString(uint256,uint256)",value,precision%80));
  compare(abi.encodeWithSignature("toLocaleString(uint256,uint8,uint8)",value,divisor,decimals));
  compare(abi.encodeWithSignature("rgba(uint256,uint256,uint256,uint256)",value,green,blue,alpha));
  compare(abi.encodeWithSignature("white_a(uint256)",alpha));
  compare(abi.encodeWithSignature("black_a(uint256)",alpha));
 }
 function testFuzzArrays(string[] memory keys,string[] memory values,uint256[2][] memory coords,uint256 precision) public {
  compare(abi.encodeWithSignature("cssBraces(string[],string[])",keys,values));
  compare(abi.encodeWithSignature("cssBraces(string[],string[])",keys,keys));
  compare(abi.encodeWithSignature("points(uint256[2][])",coords));
  compare(abi.encodeWithSignature("points(uint256[2][],uint256)",coords,precision));
  compare(abi.encodeWithSignature("points(uint256[2][],uint256)",coords,precision%80));
 }
 function testBoundariesAndInvalidUtf8() public {
  for(uint p;p<81;p++) {
   compare(abi.encodeWithSignature("toString(uint256,uint256)",uint256(0),p));
   compare(abi.encodeWithSignature("toString(uint256,uint256)",uint256(1),p));
   compare(abi.encodeWithSignature("toString(uint256,uint256)",uint256(1000),p));
   compare(abi.encodeWithSignature("toString(uint256,uint256)",type(uint256).max,p));
  }
  for(uint a;a<102;a++)compare(abi.encodeWithSignature("white_a(uint256)",a));
  for(uint i;i<256;i++) {
   bytes memory one=new bytes(1);one[0]=bytes1(uint8(i));
   compare(abi.encodeWithSignature("utfStringLength(string)",string(one)));
  }
  compare(abi.encodeWithSignature("utfStringLength(string)",string(bytes(hex"c080eda080f0808080fffe00f0"))));
  string[] memory keys=new string[](0);string[] memory values=new string[](1);values[0]="";
  compare(abi.encodeWithSignature("cssBraces(string[],string[])",keys,values));
  compare(abi.encodeWithSignature("cssBraces(string[],string[])",keys,keys));
  for(uint n;n<5;n++) {
   uint256[2][] memory points=new uint256[2][](n);
   compare(abi.encodeWithSignature("points(uint256[2][])",points));
   compare(abi.encodeWithSignature("points(uint256[2][],uint256)",points,type(uint256).max));
   if(n>0)points[n-1][1]=1;
   compare(abi.encodeWithSignature("points(uint256[2][],uint256)",points,uint256(0)));
  }
 }
}
