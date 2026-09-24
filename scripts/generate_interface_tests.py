#!/usr/bin/env python3
"""Generate selector and ABI-record differential tests from the pinned interface index."""
from pathlib import Path
import argparse,json,re
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--index',type=Path,required=True)
parser.add_argument('--source-output',type=Path,required=True)
parser.add_argument('--module-file',type=Path,required=True)
parser.add_argument('--test-output',type=Path,required=True)
args=parser.parse_args();idx=json.loads(args.index.read_text())
out=['use core::message::MsgVariant','use std::abi::Sol']
for e in idx:
 if not e['functions']:continue
 out += ['#[test]',f'fn selectors_{e["module"]}() {{']
 for f in e['functions']:out.append(f'    assert!(<super::{e["module"]}::{e["contract"]}::{f["variant"]} as MsgVariant<Sol>>::SELECTOR == 0x{f["selector"]})')
 out.append('}')
p=args.source_output;(p/'selector_tests.fe').write_text('\n'.join(out)+'\n');f=args.module_file;f.write_text(f.read_text().replace('pub use selector_tests\n','')+'pub use selector_tests\n')

records=[]
def walk(x,module):
 if x['type'].startswith('tuple'):
  cs=x['components'];name=x.get('internalType','').split('.')[-1].replace('struct ','').split('[')[0]
  if len(cs)>4 and all(re.fullmatch(r'(address|bool|u?int[0-9]+|bytes[0-9]+)',y['type']) for y in cs):
   if not any(r[0]==module and r[1]==name for r in records):records.append((module,name,cs))
  for c in cs:walk(c,module)
for e in idx:
 for a in e['abi']:
  for x in a.get('inputs',[])+a.get('outputs',[]):walk(x,e['module'])
fe=['use std::abi::sol','pub msg RecordRoundtripMsg {'];handlers=[]
sol=['// SPDX-License-Identifier: MIT','pragma solidity 0.8.24;','contract InterfaceRecordReference {'];types=[]
for i,(module,name,cs) in enumerate(records):
 ts=[c['type'] for c in cs];sig=f'echo{i}(('+','.join(ts)+'))';types.append(ts);qualified=f'R{i}'
 fe.insert(0,f'use super::{module}::{name} as R{i}')
 fe += [f'    #[selector = sol("{sig}")]',f'    Echo{i} {{ value: {qualified} }} -> {qualified},'];handlers.append(f'        Echo{i} {{ value }} -> {qualified} {{ value }}')
 sol.append(f' struct R{i} {{ '+' '.join(f'{t} v{j};' for j,t in enumerate(ts))+' }')
 sol.append(f' function echo{i}(R{i} calldata value) external pure returns(R{i} memory) {{return value;}}')
fe += ['}','pub contract InterfaceRecordRoundtrip {','    recv RecordRoundtripMsg {']+handlers+['    }','}'];sol.append('}')
p=args.source_output;(p/'record_roundtrip.fe').write_text('// SPDX-License-Identifier: MIT\n'+'\n'.join(fe)+'\n');f=args.module_file;f.write_text(f.read_text().replace('pub use record_roundtrip\n','')+'pub use record_roundtrip\n')
sol += ['interface RIVm { function readFile(string calldata) external view returns(string memory); function parseBytes(string calldata) external pure returns(bytes memory); }','contract InterfaceRecordParityTest {',' RIVm constant vm=RIVm(address(uint160(uint(keccak256("hevm cheat code")))));address fe;address sol;',' function setUp() public {bytes memory init=vm.parseBytes(vm.readFile("build/InterfaceRecordRoundtrip.bin"));address a;assembly{a:=create(0,add(init,32),mload(init))}require(a.code.length>0&&a.code.length<=24576,"deploy");fe=a;sol=address(new InterfaceRecordReference());}', ' function signature(uint i) internal pure returns(bytes4) {']
for i,ts in enumerate(types):sol.append(f'  if(i=={i})return bytes4(keccak256("echo{i}(('+','.join(ts)+'))"));')
sol += ['  revert();',' }',' function constraints(uint i) internal pure returns(bytes memory) {']
for i,ts in enumerate(types):
 # 0 denotes uint256, widths 1..31 bytes; sign bit encoded +128, bool=65,address20.
 marks=[]
 for t in ts:
  if t=='bool':marks.append(65)
  elif t=='address':marks.append(20)
  elif t.startswith('uint'):marks.append(int(t[4:])//8%32)
  elif t.startswith('int'):marks.append(128+int(t[3:])//8%32)
  elif t.startswith('bytes'):marks.append(64+int(t[5:]))
 sol.append(f'  if(i=={i})return hex"'+bytes(marks).hex()+'";')
sol += [' revert();',' }',' function compare(bytes memory data,bool expected) internal { (bool a,bytes memory x)=fe.call(data);(bool b,bytes memory y)=sol.call(data);require(a==expected&&b==expected&&keccak256(x)==keccak256(y),"record roundtrip parity"); }',f' function testFuzzAllRecordCodecs(bytes32 seed) public {{for(uint i;i<{len(types)};i++) {{', '  bytes memory limits=constraints(i);bytes memory data=new bytes(4+limits.length*32);bytes4 sig=signature(i);assembly{mstore(add(data,32),sig)}', '  for(uint j;j<limits.length;j++){uint k=uint8(limits[j]);uint value=uint(keccak256(abi.encode(seed,i,j)));if(k==65)value&=1;else if(k>=128){uint n=k-128;if(n>0){uint bits=n*8;value&=(uint(1)<<bits)-1;if(value&(uint(1)<<(bits-1))!=0)value|=type(uint).max<<bits;}}else if(k>64){uint n=k-64;if(n<32)value&=type(uint).max<<(256-n*8);}else if(k>0)value&=(uint(1)<<(k*8))-1;assembly{mstore(add(add(data,36),mul(j,32)),value)}}', '  compare(data,true);uint length=data.length;assembly{mstore(data,sub(length,1))}compare(data,false);', ' }}','}']
out=args.test_output;out.mkdir(parents=True,exist_ok=True);sol.insert(-1,' function testInvalidScalarCanonicalization() public {\n for(uint i;i<25;i++) {\n  bytes memory limits=constraints(i);\n  for(uint j;j<limits.length;j++) {\n   uint k=uint8(limits[j]);if(k==0||k==128||k==96)continue;\n   bytes memory data=new bytes(4+limits.length*32);bytes4 sig=signature(i);assembly{mstore(add(data,32),sig)}\n   uint word;\n   if(k==65)word=2;\n   else if(k>=128)word=(uint(1)<<((k-128)*8))-1;\n   else if(k>64)word=1;\n   else word=uint(1)<<(k*8);\n   assembly{mstore(add(add(data,36),mul(j,32)),word)}\n   compare(data,false);\n  }\n }\n }\n'.replace('i<25;', f'i<{len(records)};'));(out/'InterfaceRecordParity.t.sol').write_text('\n'.join(sol)+'\n')
print(len(records),'record codecs')
