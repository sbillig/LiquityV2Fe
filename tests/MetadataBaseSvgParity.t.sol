// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {baseSVG} from "../reference/bold/contracts/src/NFTMetadata/utils/baseSVG.sol";
import {FixedAssetReader} from "../reference/bold/contracts/src/NFTMetadata/utils/FixedAssets.sol";
contract MetadataBaseSvgReference {
 function svgProps() external view returns(string memory) { return baseSVG._svgProps(); }
 function baseElements(address reader) external view returns(string memory) { return baseSVG._baseElements(FixedAssetReader(reader)); }
 function leverageLogo() external view returns(string memory) { return baseSVG._leverageLogo(); }
 function boldLogo(address reader) external view returns(string memory) { return baseSVG._boldLogo(FixedAssetReader(reader)); }
 function staticTextEls() external view returns(string memory) { return baseSVG._staticTextEls(); }
 function formattedDynamicEl(string memory value,uint256 x,uint256 y) external view returns(string memory) { return baseSVG._formattedDynamicEl(value,x,y); }
 function formattedIdEl(string memory id) external view returns(string memory) { return baseSVG._formattedIdEl(id); }
 function formattedAddressEl(address value) external view returns(string memory) { return baseSVG._formattedAddressEl(value); }
 function collLogo(string memory name,address reader) external view returns(string memory) { return baseSVG._collLogo(name,FixedAssetReader(reader)); }
 function statusEl(string memory value) external view returns(string memory) { return baseSVG._statusEl(value); }
 function dynamicTextEls(uint256 debt,uint256 coll,uint256 interest) external view returns(string memory) { return baseSVG._dynamicTextEls(debt,coll,interest); }
}
interface BSVm {
 function readFile(string calldata) external view returns(string memory);
 function parseBytes(string calldata) external pure returns(bytes memory);
}
contract BaseSvgAssets {
 mapping(bytes4=>string) values;
 bool fail;
 function set(string memory name,string memory value) external {values[bytes4(keccak256(bytes(name)))]=value;}
 function setFail(bool value) external {fail=value;}
 function readAsset(bytes4 key) external view returns(string memory) {require(!fail,"asset failure");return values[key];}
}
contract MetadataBaseSvgParityTest {
 BSVm constant vm=BSVm(address(uint160(uint(keccak256("hevm cheat code")))));
 address fe;address sol;BaseSvgAssets assets;
 function setUp() public {
  bytes memory init=vm.parseBytes(vm.readFile("build/MetadataBaseSvgHarness.bin"));address a;
  assembly{a:=create(0,add(init,32),mload(init))}
  require(a.code.length>0&&a.code.length<=24576,"deploy");fe=a;sol=address(new MetadataBaseSvgReference());assets=new BaseSvgAssets();
 }
 function compare(bytes memory data) internal {
  (bool ok,bytes memory a)=fe.call(data);(bool success,bytes memory b)=sol.call(data);
  require(ok==success&&keccak256(a)==keccak256(b),"baseSVG parity");
 }
 function testStaticElements() public {
  compare(abi.encodeWithSignature("svgProps()"));compare(abi.encodeWithSignature("leverageLogo()"));compare(abi.encodeWithSignature("staticTextEls()"));
 }
 function testFuzzFormatting(string memory value,uint256 x,uint256 y,address owner,uint256 rate) public {
  compare(abi.encodeWithSignature("formattedDynamicEl(string,uint256,uint256)",value,x,y));
  compare(abi.encodeWithSignature("formattedIdEl(string)",value));
  compare(abi.encodeWithSignature("formattedAddressEl(address)",owner));
  compare(abi.encodeWithSignature("statusEl(string)",value));
  compare(abi.encodeWithSignature("dynamicTextEls(uint256,uint256,uint256)",x,y,rate));
 }
 function testFuzzAssets(string memory name,string memory value,string memory font,string memory bold) public {
  assets.set(name,value);assets.set("geist",font);assets.set("BOLD",bold);
  compare(abi.encodeWithSignature("baseElements(address)",address(assets)));
  compare(abi.encodeWithSignature("boldLogo(address)",address(assets)));
  compare(abi.encodeWithSignature("collLogo(string,address)",name,address(assets)));
 }
 function testAssetFailuresAndEmpty() public {
  compare(abi.encodeWithSignature("baseElements(address)",address(assets)));
  assets.setFail(true);
  compare(abi.encodeWithSignature("baseElements(address)",address(assets)));
  compare(abi.encodeWithSignature("boldLogo(address)",address(assets)));
  compare(abi.encodeWithSignature("collLogo(string,address)","WETH",address(assets)));
 }
}
