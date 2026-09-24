// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {HybridCurveUniV3ExchangeHelpers} from "../reference/bold/contracts/src/Zappers/Modules/Exchanges/HybridCurveUniV3ExchangeHelpers.sol";
import {HybridCurveUniV3ExchangeHelpersV2} from "../reference/bold/contracts/src/Zappers/Modules/Exchanges/HybridCurveUniV3ExchangeHelpersV2.sol";
import {GCZVm} from "./GasCompZapperParity.t.sol";
contract HybridQuoteMarket {
 uint public calls;bytes32 public lastPath;bool public failPool;bool public failQuoter;bool public raw;bytes public reply;
 int128 public usdcIndex;int128 public boldIndex;
 constructor(uint128 i){usdcIndex=int128(i);boldIndex=int128(i^1);}
 function configure(bool p,bool q) external {failPool=p;failQuoter=q;}
 function setReply(bytes calldata data) external {reply=data;raw=true;}
 function get_dy(int128 i,int128 j,uint amount) external view returns(uint){require(!failPool,"pool failure");require((i==usdcIndex&&j==boldIndex)||(i==boldIndex&&j==usdcIndex),"indices");return amount*2+7;}
 function get_dx(int128 i,int128 j,uint amount) external view returns(uint){require(!failPool,"pool failure");require((i==usdcIndex&&j==boldIndex)||(i==boldIndex&&j==usdcIndex),"indices");return amount/2+11;}
 function quote(bytes calldata path,uint amount,bool output) internal returns(uint,uint160[] memory prices,uint32[] memory ticks,uint){
  require(!failQuoter,"quoter failure");calls++;lastPath=keccak256(path);
  if(raw){bytes memory data=reply;assembly{return(add(data,32),mload(data))}}
  uint n=path.length==43?1:2;require(path.length==43||path.length==66,"path length");prices=new uint160[](n);ticks=new uint32[](n);
  for(uint i;i<n;i++){prices[i]=uint160(1)<<96;ticks[i]=uint32(i+1);}
  return(output?amount/3+17:amount*3+13,prices,ticks,1234);
 }
 function quoteExactInput(bytes calldata path,uint amount) external returns(uint,uint160[] memory,uint32[] memory,uint){return quote(path,amount,false);}
 function quoteExactOutput(bytes calldata path,uint amount) external returns(uint,uint160[] memory,uint32[] memory,uint){return quote(path,amount,true);}
}
contract HybridHelpersParityTest {
 GCZVm constant vm=GCZVm(address(uint160(uint(keccak256("hevm cheat code")))));
 function make(bool fe,bool v2,uint128 index) internal returns(address helper,HybridQuoteMarket market){
  market=new HybridQuoteMarket(index);
  bytes memory code=fe?vm.parseBytes(vm.readFile(v2?"build/HybridCurveUniV3ExchangeHelpersV2.bin":"build/HybridCurveUniV3ExchangeHelpers.bin")):(v2?type(HybridCurveUniV3ExchangeHelpersV2).creationCode:type(HybridCurveUniV3ExchangeHelpers).creationCode);
  bytes memory args=v2?abi.encode(address(1),address(2),market,int128(index),int128(index^1),uint24(500),uint24(3000),market):abi.encode(address(1),address(2),market,index,index^1,uint24(500),uint24(3000),market);
  bytes memory init=bytes.concat(code,args);assembly{helper:=create(0,add(init,32),mload(init))}require(helper.code.length>0&&helper.code.length<=24576,"deploy");
 }
 function compare(address a,address b,bytes memory data) internal returns(bool){(bool ok,bytes memory x)=a.call(data);(bool success,bytes memory y)=b.call(data);require(ok==success&&keccak256(x)==keccak256(y),"return parity");return ok;}
 function testFuzzBothQuoteDirections(uint96 amount,uint128 index,bool lst) public {
  (address a,HybridQuoteMarket ma)=make(true,true,index);(address b,HybridQuoteMarket mb)=make(false,true,index);address coll=lst?address(3):address(2);
  for(uint i;i<4;i++){
   bool output=i>=2;bool reverse=i%2==1;
   bytes memory data=abi.encodeWithSignature(output?"quoteExactOutput(uint256,bool,address)":"quoteExactInput(uint256,bool,address)",uint(amount),reverse,coll);require(compare(a,b,data));
   bool reversed=output?!reverse:reverse;
   bytes memory path=reversed?(lst?abi.encodePacked(coll,uint24(3000),address(2),uint24(500),address(1)):abi.encodePacked(address(2),uint24(500),address(1))):(lst?abi.encodePacked(address(1),uint24(500),address(2),uint24(3000),coll):abi.encodePacked(address(1),uint24(500),address(2)));
   require(ma.lastPath()==keccak256(path)&&mb.lastPath()==keccak256(path),"path");
  }
  require(ma.calls()==4&&mb.calls()==4,"quoter CALL");
 }
 function testFuzzLegacyDeviation(uint amount,uint desired,bool lst) public {
  (address a,)=make(true,false,0);(address b,)=make(false,false,0);
  compare(a,b,abi.encodeWithSignature("getCollFromBold(uint256,address,uint256)",amount,lst?address(3):address(2),desired));
 }
 function testDependencyFailuresAndRollback() public {
  (address a,HybridQuoteMarket ma)=make(true,true,0);(address b,HybridQuoteMarket mb)=make(false,true,0);ma.configure(true,true);mb.configure(true,true);
  for(uint i;i<4;i++)require(!compare(a,b,abi.encodeWithSignature(i>=2?"quoteExactOutput(uint256,bool,address)":"quoteExactInput(uint256,bool,address)",uint(10),i%2==1,address(3))));
  require(ma.calls()==0&&mb.calls()==0);
 }
 function testMalformedUnusedQuoteArrays() public {
  (address a,HybridQuoteMarket ma)=make(true,true,0);(address b,HybridQuoteMarket mb)=make(false,true,0);
  bytes memory data=abi.encodeWithSignature("quoteExactInput(uint256,bool,address)",uint(10),false,address(3));
  uint160[] memory prices=new uint160[](1);prices[0]=1;uint32[] memory ticks=new uint32[](1);ticks[0]=1;
  for(uint i;i<14;i++){
   bytes memory reply=abi.encode(uint(99),prices,ticks,uint(123));
   if(i==1)assembly{mstore(add(reply,192),not(0))}
   if(i==2)assembly{mstore(add(reply,256),not(0))}
   if(i==3)assembly{mstore(add(reply,64),not(0))}
   if(i==4)assembly{mstore(add(reply,160),not(0))}
   if(i==5)assembly{mstore(reply,127)}
   if(i==6)assembly{mstore(add(reply,96),not(0))}
   if(i==7)assembly{mstore(add(reply,224),not(0))}
   if(i==8)assembly{mstore(reply,255)}
   if(i>=9){uint count=uint(0x7fffffffffffffa)+i-11;assembly{mstore(add(reply,160),count)}}
   ma.setReply(reply);mb.setReply(reply);bool ok=compare(a,b,data);require(ok==(i==0),"array acceptance");
  }
 }
 function testAllocationPanicBoundariesBothVersionsAndPaths() public {
  for(uint version;version<2;version++){
   (address a,HybridQuoteMarket ma)=make(true,version==1,0);(address b,HybridQuoteMarket mb)=make(false,version==1,0);
   for(uint branch;branch<2;branch++)for(uint op;op<(version==1?4:1);op++){
    address coll=branch==0?address(2):address(3);
    bytes memory data=version==1?abi.encodeWithSignature(op>=2?"quoteExactOutput(uint256,bool,address)":"quoteExactInput(uint256,bool,address)",uint(10),op%2==1,coll):abi.encodeWithSignature("getCollFromBold(uint256,address,uint256)",uint(10),coll,uint(0));
    allocationCases(a,b,ma,mb,data);
   }
  }
 }
 function allocationCases(address a,address b,HybridQuoteMarket ma,HybridQuoteMarket mb,bytes memory data) internal {
    for(uint array;array<2;array++)for(uint padding;padding<3;padding++)for(uint k;k<33;k++){
     uint160[] memory prices=new uint160[](1);uint32[] memory ticks=new uint32[](1);
     bytes memory reply=bytes.concat(abi.encode(uint(99),prices,ticks,uint(123)),new bytes(padding*17));uint pos=array==0?160:224;uint count=uint(0x7ffffffffffffff)-k;
     assembly{mstore(add(reply,pos),count)}
     ma.setReply(reply);mb.setReply(reply);require(!compare(a,b,data));
    }
 }
}
