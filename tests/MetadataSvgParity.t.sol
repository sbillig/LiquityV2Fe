// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {svg} from "../reference/bold/contracts/src/NFTMetadata/utils/SVG.sol";
import {JVm} from "./MetadataJsonParity.t.sol";
contract MetadataSvgReference {
 function el(string memory tag,string memory props) external pure returns(string memory){return svg.el(tag,props);}
 function el(string memory tag,string memory props,string memory children) external pure returns(string memory){return svg.el(tag,props,children);}
 function prop(string memory key,string memory value,bool last) external pure returns(string memory){return svg.prop(key,value,last);}
 function prop(string memory key,string memory value) external pure returns(string memory){return svg.prop(key,value);}
 function g(string memory props,string memory children) external pure returns(string memory){return svg.g(props,children);}
 function text(string memory props,string memory children) external pure returns(string memory){return svg.text(props,children);}
 function filter(string memory props,string memory children) external pure returns(string memory){return svg.filter(props,children);}
 function radialGradient(string memory props,string memory children) external pure returns(string memory){return svg.radialGradient(props,children);}
 function linearGradient(string memory props,string memory children) external pure returns(string memory){return svg.linearGradient(props,children);}
 function line(string memory props) external pure returns(string memory){return svg.line(props);}
 function line(string memory props,string memory children) external pure returns(string memory){return svg.line(props,children);}
 function ellipse(string memory props) external pure returns(string memory){return svg.ellipse(props);}
 function ellipse(string memory props,string memory children) external pure returns(string memory){return svg.ellipse(props,children);}
 function polygon(string memory props) external pure returns(string memory){return svg.polygon(props);}
 function polygon(string memory props,string memory children) external pure returns(string memory){return svg.polygon(props,children);}
 function polyline(string memory props) external pure returns(string memory){return svg.polyline(props);}
 function polyline(string memory props,string memory children) external pure returns(string memory){return svg.polyline(props,children);}
 function rect(string memory props) external pure returns(string memory){return svg.rect(props);}
 function rect(string memory props,string memory children) external pure returns(string memory){return svg.rect(props,children);}
 function circle(string memory props) external pure returns(string memory){return svg.circle(props);}
 function circle(string memory props,string memory children) external pure returns(string memory){return svg.circle(props,children);}
 function animateTransform(string memory props) external pure returns(string memory){return svg.animateTransform(props);}
 function animate(string memory props) external pure returns(string memory){return svg.animate(props);}
 function _svg(string memory props,string memory children) external pure returns(string memory){return svg._svg(props,children);}
 function style(string memory title,string memory props) external pure returns(string memory){return svg.style(title,props);}
 function path(string memory d) external pure returns(string memory){return svg.path(d);}
 function path(string memory d,string memory props) external pure returns(string memory){return svg.path(d,props);}
 function path(string memory d,string memory props,string memory children) external pure returns(string memory){return svg.path(d,props,children);}
 function circle(string memory cx,string memory cy,string memory r) external pure returns(string memory){return svg.circle(cx,cy,r);}
 function circle(string memory cx,string memory cy,string memory r,string memory children) external pure returns(string memory){return svg.circle(cx,cy,r,children);}
 function circle(string memory cx,string memory cy,string memory r,string memory props,string memory children) external pure returns(string memory){return svg.circle(cx,cy,r,props,children);}
 function cdata(string memory content) external pure returns(string memory){return svg.cdata(content);}
 function gradientStop(uint256 offset,string memory color,string memory props) external pure returns(string memory){return svg.gradientStop(offset,color,props);}
}
contract MetadataSvgParityTest {
 JVm constant vm=JVm(address(uint160(uint(keccak256("hevm cheat code")))));
 mapping(bytes4=>address) feTargets;address sol;
 function deploy(string memory name) internal returns(address a) {
  bytes memory init=vm.parseBytes(vm.readFile(string.concat("build/",name,".bin")));
  assembly{a:=create(0,add(init,32),mload(init))}require(a.code.length>0&&a.code.length<=24576,"deploy");
 }
 function setUp() public {
  address a=deploy("MetadataSvgHarnessA");address b=deploy("MetadataSvgHarnessB");
  feTargets[bytes4(keccak256("el(string,string)"))]=a;
  feTargets[bytes4(keccak256("el(string,string,string)"))]=a;
  feTargets[bytes4(keccak256("prop(string,string,bool)"))]=a;
  feTargets[bytes4(keccak256("prop(string,string)"))]=a;
  feTargets[bytes4(keccak256("g(string,string)"))]=a;
  feTargets[bytes4(keccak256("text(string,string)"))]=a;
  feTargets[bytes4(keccak256("filter(string,string)"))]=a;
  feTargets[bytes4(keccak256("radialGradient(string,string)"))]=a;
  feTargets[bytes4(keccak256("linearGradient(string,string)"))]=a;
  feTargets[bytes4(keccak256("line(string)"))]=a;
  feTargets[bytes4(keccak256("line(string,string)"))]=a;
  feTargets[bytes4(keccak256("ellipse(string)"))]=a;
  feTargets[bytes4(keccak256("ellipse(string,string)"))]=a;
  feTargets[bytes4(keccak256("polygon(string)"))]=a;
  feTargets[bytes4(keccak256("polygon(string,string)"))]=a;
  feTargets[bytes4(keccak256("polyline(string)"))]=a;
  feTargets[bytes4(keccak256("polyline(string,string)"))]=a;
  feTargets[bytes4(keccak256("rect(string)"))]=b;
  feTargets[bytes4(keccak256("rect(string,string)"))]=b;
  feTargets[bytes4(keccak256("circle(string)"))]=b;
  feTargets[bytes4(keccak256("circle(string,string)"))]=b;
  feTargets[bytes4(keccak256("animateTransform(string)"))]=b;
  feTargets[bytes4(keccak256("animate(string)"))]=b;
  feTargets[bytes4(keccak256("_svg(string,string)"))]=b;
  feTargets[bytes4(keccak256("style(string,string)"))]=b;
  feTargets[bytes4(keccak256("path(string)"))]=b;
  feTargets[bytes4(keccak256("path(string,string)"))]=b;
  feTargets[bytes4(keccak256("path(string,string,string)"))]=b;
  feTargets[bytes4(keccak256("circle(string,string,string)"))]=b;
  feTargets[bytes4(keccak256("circle(string,string,string,string)"))]=b;
  feTargets[bytes4(keccak256("circle(string,string,string,string,string)"))]=b;
  feTargets[bytes4(keccak256("cdata(string)"))]=b;
  feTargets[bytes4(keccak256("gradientStop(uint256,string,string)"))]=b;
  sol=address(new MetadataSvgReference());
 }
 function compare(bytes memory data) internal {
  (bool ok,bytes memory a)=feTargets[bytes4(data)].call(data);(bool success,bytes memory b)=sol.call(data);
  require(ok&&success&&keccak256(a)==keccak256(b),"SVG parity");
 }
 function all(string memory a,string memory b,string memory c,uint offset,bool last) internal {
  compare(abi.encodeWithSignature("el(string,string)",a,b));
  compare(abi.encodeWithSignature("el(string,string,string)",a,b,c));
  compare(abi.encodeWithSignature("prop(string,string,bool)",a,b,last));
  compare(abi.encodeWithSignature("prop(string,string)",a,b));
  compare(abi.encodeWithSignature("g(string,string)",a,b));
  compare(abi.encodeWithSignature("text(string,string)",a,b));
  compare(abi.encodeWithSignature("filter(string,string)",a,b));
  compare(abi.encodeWithSignature("radialGradient(string,string)",a,b));
  compare(abi.encodeWithSignature("linearGradient(string,string)",a,b));
  compare(abi.encodeWithSignature("line(string)",a));
  compare(abi.encodeWithSignature("line(string,string)",a,b));
  compare(abi.encodeWithSignature("ellipse(string)",a));
  compare(abi.encodeWithSignature("ellipse(string,string)",a,b));
  compare(abi.encodeWithSignature("polygon(string)",a));
  compare(abi.encodeWithSignature("polygon(string,string)",a,b));
  compare(abi.encodeWithSignature("polyline(string)",a));
  compare(abi.encodeWithSignature("polyline(string,string)",a,b));
  compare(abi.encodeWithSignature("rect(string)",a));
  compare(abi.encodeWithSignature("rect(string,string)",a,b));
  compare(abi.encodeWithSignature("circle(string)",a));
  compare(abi.encodeWithSignature("circle(string,string)",a,b));
  compare(abi.encodeWithSignature("animateTransform(string)",a));
  compare(abi.encodeWithSignature("animate(string)",a));
  compare(abi.encodeWithSignature("_svg(string,string)",a,b));
  compare(abi.encodeWithSignature("style(string,string)",a,b));
  compare(abi.encodeWithSignature("path(string)",a));
  compare(abi.encodeWithSignature("path(string,string)",a,b));
  compare(abi.encodeWithSignature("path(string,string,string)",a,b,c));
  compare(abi.encodeWithSignature("circle(string,string,string)",a,b,c));
  compare(abi.encodeWithSignature("circle(string,string,string,string)",a,b,c,a));
  compare(abi.encodeWithSignature("circle(string,string,string,string,string)",a,b,c,a,b));
  compare(abi.encodeWithSignature("cdata(string)",a));
  compare(abi.encodeWithSignature("gradientStop(uint256,string,string)",offset,a,b));
 }
 function testFuzzEverySvgOverload(string memory a,string memory b,string memory c,uint offset,bool last) public {all(a,b,c,offset,last);}
 function testEmptyAndWhitespace() public {all("","","",0,false);all(" ","\" ","<>&",type(uint).max,true);}
}
