// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
contract InterfaceRecordReference {
 struct R0 { uint256 v0; uint256 v1; uint256 v2; uint256 v3; uint256 v4; uint256 v5; uint256 v6; uint256 v7; uint256 v8; uint256 v9; uint256 v10; uint256 v11; }
 function echo0(R0 calldata value) external pure returns(R0 memory) {return value;}
 struct R1 { address v0; address v1; address v2; address v3; address v4; address v5; address v6; address v7; address v8; address v9; address v10; address v11; address v12; address v13; address v14; address v15; address v16; address v17; }
 function echo1(R1 calldata value) external pure returns(R1 memory) {return value;}
 struct R2 { address v0; uint256 v1; uint256 v2; uint256 v3; uint256 v4; uint256 v5; address v6; uint256 v7; address v8; address v9; address v10; }
 function echo2(R2 calldata value) external pure returns(R2 memory) {return value;}
 struct R3 { uint256 v0; uint256 v1; uint256 v2; uint256 v3; uint256 v4; uint256 v5; uint256 v6; uint256 v7; uint256 v8; uint256 v9; uint256 v10; uint256 v11; address v12; uint256 v13; uint256 v14; uint256 v15; }
 function echo3(R3 calldata value) external pure returns(R3 memory) {return value;}
 struct R4 { address v0; address v1; bool v2; uint256 v3; uint256 v4; uint256 v5; uint256 v6; uint256 v7; }
 function echo4(R4 calldata value) external pure returns(R4 memory) {return value;}
 struct R5 { uint256 v0; uint256 v1; uint256 v2; uint256 v3; uint256 v4; uint256 v5; uint256 v6; uint256 v7; uint256 v8; uint256 v9; uint256 v10; uint256 v11; }
 function echo5(R5 calldata value) external pure returns(R5 memory) {return value;}
 struct R6 { uint256 v0; uint256 v1; uint256 v2; uint256 v3; uint256 v4; uint256 v5; uint256 v6; uint256 v7; uint256 v8; uint256 v9; }
 function echo6(R6 calldata value) external pure returns(R6 memory) {return value;}
 struct R7 { uint256 v0; uint256 v1; uint256 v2; uint256 v3; uint256 v4; uint256 v5; uint256 v6; uint256 v7; uint256 v8; uint256 v9; uint256 v10; uint256 v11; }
 function echo7(R7 calldata value) external pure returns(R7 memory) {return value;}
 struct R8 { uint256 v0; address v1; address v2; address v3; uint256 v4; uint256 v5; uint256 v6; uint8 v7; }
 function echo8(R8 calldata value) external pure returns(R8 memory) {return value;}
 struct R9 { address v0; uint256 v1; uint256 v2; uint256 v3; uint256 v4; uint256 v5; uint256 v6; uint256 v7; address v8; uint256 v9; address v10; address v11; address v12; }
 function echo9(R9 calldata value) external pure returns(R9 memory) {return value;}
 struct R10 { address v0; uint256 v1; uint256 v2; uint256 v3; uint256 v4; uint256 v5; uint256 v6; uint256 v7; address v8; uint256 v9; address v10; address v11; address v12; }
 function echo10(R10 calldata value) external pure returns(R10 memory) {return value;}
 struct R11 { address v0; uint256 v1; uint256 v2; uint256 v3; uint256 v4; uint256 v5; uint256 v6; address v7; uint256 v8; address v9; address v10; address v11; }
 function echo11(R11 calldata value) external pure returns(R11 memory) {return value;}
 struct R12 { address v0; uint256 v1; uint256 v2; uint256 v3; uint256 v4; uint256 v5; uint256 v6; address v7; uint256 v8; address v9; address v10; address v11; }
 function echo12(R12 calldata value) external pure returns(R12 memory) {return value;}
 struct R13 { uint256 v0; uint128 v1; uint256 v2; uint256 v3; uint256 v4; }
 function echo13(R13 calldata value) external pure returns(R13 memory) {return value;}
 struct R14 { uint256 v0; uint256 v1; uint256 v2; uint256 v3; uint256 v4; uint256 v5; }
 function echo14(R14 calldata value) external pure returns(R14 memory) {return value;}
 struct R15 { address v0; address v1; uint24 v2; int24 v3; int24 v4; uint256 v5; uint256 v6; uint256 v7; uint256 v8; address v9; uint256 v10; }
 function echo15(R15 calldata value) external pure returns(R15 memory) {return value;}
 struct R16 { address v0; address v1; uint256 v2; uint24 v3; uint160 v4; }
 function echo16(R16 calldata value) external pure returns(R16 memory) {return value;}
 struct R17 { address v0; address v1; uint256 v2; uint24 v3; uint160 v4; }
 function echo17(R17 calldata value) external pure returns(R17 memory) {return value;}
 struct R18 { address v0; address v1; uint24 v2; address v3; uint256 v4; uint256 v5; uint256 v6; uint160 v7; }
 function echo18(R18 calldata value) external pure returns(R18 memory) {return value;}
 struct R19 { address v0; address v1; uint24 v2; address v3; uint256 v4; uint256 v5; uint256 v6; uint160 v7; }
 function echo19(R19 calldata value) external pure returns(R19 memory) {return value;}
 struct R20 { address v0; address v1; uint256 v2; uint256 v3; uint8 v4; bytes32 v5; bytes32 v6; }
 function echo20(R20 calldata value) external pure returns(R20 memory) {return value;}
 struct R21 { uint256 v0; uint256 v1; uint256 v2; uint256 v3; uint256 v4; }
 function echo21(R21 calldata value) external pure returns(R21 memory) {return value;}
 struct R22 { uint256 v0; uint256 v1; uint256 v2; uint256 v3; uint256 v4; }
 function echo22(R22 calldata value) external pure returns(R22 memory) {return value;}
 struct R23 { uint256 v0; uint256 v1; uint256 v2; uint256 v3; uint256 v4; }
 function echo23(R23 calldata value) external pure returns(R23 memory) {return value;}
 struct R24 { address v0; address v1; uint256 v2; uint256 v3; uint8 v4; bytes32 v5; bytes32 v6; }
 function echo24(R24 calldata value) external pure returns(R24 memory) {return value;}
}
interface RIVm { function readFile(string calldata) external view returns(string memory); function parseBytes(string calldata) external pure returns(bytes memory); }
contract InterfaceRecordParityTest {
 RIVm constant vm=RIVm(address(uint160(uint(keccak256("hevm cheat code")))));address fe;address sol;
 function setUp() public {bytes memory init=vm.parseBytes(vm.readFile("build/InterfaceRecordRoundtrip.bin"));address a;assembly{a:=create(0,add(init,32),mload(init))}require(a.code.length>0&&a.code.length<=24576,"deploy");fe=a;sol=address(new InterfaceRecordReference());}
 function signature(uint i) internal pure returns(bytes4) {
  if(i==0)return bytes4(keccak256("echo0((uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256))"));
  if(i==1)return bytes4(keccak256("echo1((address,address,address,address,address,address,address,address,address,address,address,address,address,address,address,address,address,address))"));
  if(i==2)return bytes4(keccak256("echo2((address,uint256,uint256,uint256,uint256,uint256,address,uint256,address,address,address))"));
  if(i==3)return bytes4(keccak256("echo3((uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,address,uint256,uint256,uint256))"));
  if(i==4)return bytes4(keccak256("echo4((address,address,bool,uint256,uint256,uint256,uint256,uint256))"));
  if(i==5)return bytes4(keccak256("echo5((uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256))"));
  if(i==6)return bytes4(keccak256("echo6((uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256))"));
  if(i==7)return bytes4(keccak256("echo7((uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256))"));
  if(i==8)return bytes4(keccak256("echo8((uint256,address,address,address,uint256,uint256,uint256,uint8))"));
  if(i==9)return bytes4(keccak256("echo9((address,uint256,uint256,uint256,uint256,uint256,uint256,uint256,address,uint256,address,address,address))"));
  if(i==10)return bytes4(keccak256("echo10((address,uint256,uint256,uint256,uint256,uint256,uint256,uint256,address,uint256,address,address,address))"));
  if(i==11)return bytes4(keccak256("echo11((address,uint256,uint256,uint256,uint256,uint256,uint256,address,uint256,address,address,address))"));
  if(i==12)return bytes4(keccak256("echo12((address,uint256,uint256,uint256,uint256,uint256,uint256,address,uint256,address,address,address))"));
  if(i==13)return bytes4(keccak256("echo13((uint256,uint128,uint256,uint256,uint256))"));
  if(i==14)return bytes4(keccak256("echo14((uint256,uint256,uint256,uint256,uint256,uint256))"));
  if(i==15)return bytes4(keccak256("echo15((address,address,uint24,int24,int24,uint256,uint256,uint256,uint256,address,uint256))"));
  if(i==16)return bytes4(keccak256("echo16((address,address,uint256,uint24,uint160))"));
  if(i==17)return bytes4(keccak256("echo17((address,address,uint256,uint24,uint160))"));
  if(i==18)return bytes4(keccak256("echo18((address,address,uint24,address,uint256,uint256,uint256,uint160))"));
  if(i==19)return bytes4(keccak256("echo19((address,address,uint24,address,uint256,uint256,uint256,uint160))"));
  if(i==20)return bytes4(keccak256("echo20((address,address,uint256,uint256,uint8,bytes32,bytes32))"));
  if(i==21)return bytes4(keccak256("echo21((uint256,uint256,uint256,uint256,uint256))"));
  if(i==22)return bytes4(keccak256("echo22((uint256,uint256,uint256,uint256,uint256))"));
  if(i==23)return bytes4(keccak256("echo23((uint256,uint256,uint256,uint256,uint256))"));
  if(i==24)return bytes4(keccak256("echo24((address,address,uint256,uint256,uint8,bytes32,bytes32))"));
  revert();
 }
 function constraints(uint i) internal pure returns(bytes memory) {
  if(i==0)return hex"000000000000000000000000";
  if(i==1)return hex"141414141414141414141414141414141414";
  if(i==2)return hex"1400000000001400141414";
  if(i==3)return hex"00000000000000000000000014000000";
  if(i==4)return hex"1414410000000000";
  if(i==5)return hex"000000000000000000000000";
  if(i==6)return hex"00000000000000000000";
  if(i==7)return hex"000000000000000000000000";
  if(i==8)return hex"0014141400000001";
  if(i==9)return hex"14000000000000001400141414";
  if(i==10)return hex"14000000000000001400141414";
  if(i==11)return hex"140000000000001400141414";
  if(i==12)return hex"140000000000001400141414";
  if(i==13)return hex"0010000000";
  if(i==14)return hex"000000000000";
  if(i==15)return hex"1414038383000000001400";
  if(i==16)return hex"1414000314";
  if(i==17)return hex"1414000314";
  if(i==18)return hex"1414031400000014";
  if(i==19)return hex"1414031400000014";
  if(i==20)return hex"14140000016060";
  if(i==21)return hex"0000000000";
  if(i==22)return hex"0000000000";
  if(i==23)return hex"0000000000";
  if(i==24)return hex"14140000016060";
 revert();
 }
 function compare(bytes memory data,bool expected) internal { (bool a,bytes memory x)=fe.call(data);(bool b,bytes memory y)=sol.call(data);require(a==expected&&b==expected&&keccak256(x)==keccak256(y),"record roundtrip parity"); }
 function testFuzzAllRecordCodecs(bytes32 seed) public {for(uint i;i<25;i++) {
  bytes memory limits=constraints(i);bytes memory data=new bytes(4+limits.length*32);bytes4 sig=signature(i);assembly{mstore(add(data,32),sig)}
  for(uint j;j<limits.length;j++){uint k=uint8(limits[j]);uint value=uint(keccak256(abi.encode(seed,i,j)));if(k==65)value&=1;else if(k>=128){uint n=k-128;if(n>0){uint bits=n*8;value&=(uint(1)<<bits)-1;if(value&(uint(1)<<(bits-1))!=0)value|=type(uint).max<<bits;}}else if(k>64){uint n=k-64;if(n<32)value&=type(uint).max<<(256-n*8);}else if(k>0)value&=(uint(1)<<(k*8))-1;assembly{mstore(add(add(data,36),mul(j,32)),value)}}
  compare(data,true);uint length=data.length;assembly{mstore(data,sub(length,1))}compare(data,false);
 }}
 function testInvalidScalarCanonicalization() public {
 for(uint i;i<25;i++) {
  bytes memory limits=constraints(i);
  for(uint j;j<limits.length;j++) {
   uint k=uint8(limits[j]);if(k==0||k==128||k==96)continue;
   bytes memory data=new bytes(4+limits.length*32);bytes4 sig=signature(i);assembly{mstore(add(data,32),sig)}
   uint word;
   if(k==65)word=2;
   else if(k>=128)word=(uint(1)<<((k-128)*8))-1;
   else if(k>64)word=1;
   else word=uint(1)<<(k*8);
   assembly{mstore(add(add(data,36),mul(j,32)),word)}
   compare(data,false);
  }
 }
 }

}
