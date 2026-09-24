#!/usr/bin/env python3
"""Generate typed Fe bindings from every pinned Solidity interface, without network access."""
import argparse,hashlib,json,re,subprocess,tempfile
from pathlib import Path
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo',type=Path,default=Path.cwd())
parser.add_argument('--output',type=Path,required=True,help='Output directory: interfaces.fe, interfaces/*.fe and interface-index.json')
args=parser.parse_args();root=args.repo.resolve();args.output=args.output.resolve();out=args.output/'interfaces';out.mkdir(parents=True,exist_ok=True)
manifest=json.loads((root/'reference_manifest.json').read_text());inputs=[]
for inventory,prefix,group,pins in [('port_status.json','reference/bold/','core',manifest['sources']),('governance_status.json','reference/bold/contracts/lib/V2-gov/','gov',manifest['governance_sources'])]:
 for name in json.loads((root/inventory).read_text()):
  path=root/(prefix+name);source=path.read_text()
  assert hashlib.sha256(path.read_bytes()).hexdigest()==pins[name],name
  if re.search(r'^interface\s+\w+',source,re.M):inputs.append({'group':group,'inventory':name,'source':prefix+name})
all_artifacts=[]
with tempfile.TemporaryDirectory(prefix='liquity-interfaces-') as temporary:
 project=Path(temporary);(project/'src').mkdir();(project/'reference').symlink_to(root/'reference',target_is_directory=True)
 (project/'remappings.txt').write_text((root/'remappings.txt').read_text())
 (project/'foundry.toml').write_text('[profile.default]\nsrc = "src"\nsolc_version = "0.8.24"\nevm_version = "cancun"\noptimizer = true\n')
 (project/'src/AllInterfaces.sol').write_text('// SPDX-License-Identifier: MIT\npragma solidity 0.8.24;\n'+''.join(f'import * as Source{i} from "../{e["source"]}";\n' for i,e in enumerate(inputs)))
 subprocess.run(['forge','build','--root',str(project)],check=True)
 for p in (project/'out').rglob('*.json'):
  d=json.loads(p.read_text());target=d.get('metadata',{}).get('settings',{}).get('compilationTarget',{})
  for path,name in target.items():all_artifacts.append((path,name,d,p))
index=[];modules=[]
def sigtype(x):
 t=x['type']
 if t.startswith('tuple'):return '('+','.join(sigtype(y) for y in x['components'])+')'+t[5:]
 return t

def typ(x,imports):
 t=x['type'];m=re.search(r'\[([0-9]*)\]$',t)
 if m:
  item=dict(x,type=t[:m.start()]);inner=typ(item,imports)
  if m[1]:return f'[{inner}; {m[1]}]'
  imports.add('DynArray');return f'DynArray<{inner}>'
 if t=='tuple' and len(x['components'])>4 and all(re.fullmatch(r'(address|bool|u?int[0-9]+|bytes[0-9]+)',y['type']) for y in x['components']):
  record=x.get('internalType','').split('.')[-1].replace('struct ','').split('[')[0] or 'Record'+str(len(records))
  if record in records:assert records[record]==x['components'],record
  records[record]=x['components']
  return record
 if t=='tuple':
  items=[typ(y,imports) for y in x['components']];return '('+', '.join(items)+(',' if len(items)==1 else '')+')'
 if t=='address':return 'Address'
 if t=='bool':return 'bool'
 if t in ('string','bytes'):v={'string':'DynString','bytes':'Bytes'}[t];imports.add(v);return v
 m=re.fullmatch('(uint|int)([0-9]+)',t)
 if m:
  sign,n=m.groups()
  if int(n) in (8,16,32,64,128,256):return ('u' if sign=='uint' else 'i')+n
  v=('Uint' if sign=='uint' else 'Int')+n;imports.add(v);return v
 if re.fullmatch(r'bytes\d+',t):v='Bytes'+t[5:];imports.add(v);return v
 raise ValueError(t)

def name(s,fallback):
 s=re.sub(r'(?<!^)(?=[A-Z])','_',s).lower().strip('_') or fallback
 s=re.sub('[^a-z0-9_]','_',s)
 if s in ['type','self','super','in','pub','fn','mod','use','const','let','mut','match','return','move','ref','own','contract','event','error','where','impl','trait','struct','enum','as','for','while','loop','if','else','true','false']:s+='_' 
 return s

for e in inputs:
 declared=set(re.findall(r'^interface\s+(\w+)',Path(root,e['source']).read_text(),re.M))
 matches=[x for x in all_artifacts if x[0]==e['source'] and x[1] in declared]
 assert matches,e
 for source,contract,d,artifact in matches:
  module=e['group']+'_'+name(contract,'interface');modules.append(module);imports={'sol'};lines=[];functions=[];records={}
  abi=d['abi'];fns=[x for x in abi if x['type']=='function'];counts={}
  for f in fns:counts[f['name']]=counts.get(f['name'],0)+1
  if fns:
   lines.append('pub msg '+contract+' {')
   for i,f in enumerate(fns):
    signature=f['name']+'('+','.join(sigtype(x) for x in f['inputs'])+')'
    variant=''.join(part[:1].upper()+part[1:] for part in name(f['name'],'method').split('_'))
    if counts[f['name']]>1:variant+=str(i)
    fields=', '.join(name(x.get('name',''),f'arg{j}')+': '+typ(x,imports) for j,x in enumerate(f['inputs']))
    outputs=[typ(x,imports) for x in f['outputs']];returns=(' -> '+outputs[0]) if len(outputs)==1 else (' -> ('+', '.join(outputs)+')') if outputs else ''
    lines.extend([f'    // Solidity: {f["stateMutability"]}',f'    #[selector = sol("{signature}")]',f'    {variant} {{ {fields} }}{returns},'])
    functions.append({'signature':signature,'selector':d['methodIdentifiers'][signature],'variant':variant,'mutability':f['stateMutability']})
   lines.append('}')
  else:lines.extend(['// Marker-only interface; Solidity declares no callable methods.',f'pub struct {contract} {{}}'])
  for f in abi:
   if f['type'] not in ('event','error'):continue
   assert not f.get('anonymous',False),f
   lines.extend([f'#[{f["type"]}]',f'pub struct {f["name"]} {{'])
   for j,x in enumerate(f['inputs']):
    if x.get('indexed'):lines.append('    #[indexed]')
    lines.append('    pub '+name(x.get('name',''),f'arg{j}')+': '+typ(x,imports)+',')
   lines.append('}')
  for record,fields in records.items():
   imports.add('Sol');size=len(fields)*32
   fields=[(name(f.get('name',''),f'field{i}'),typ(f,imports)) for i,f in enumerate(fields)]
   lines.extend(['pub struct '+record+' {']+['    pub '+n+': '+t+',' for n,t in fields]+['}'])
   lines.extend([f'impl AbiSize for {record} {{ const HEAD_SIZE: u256 = {size}\n    const IS_DYNAMIC: bool = false }}',f'impl AbiSpan<Sol> for {record} {{',f'    fn payload_end<I: ByteInput>(_ input: I, base: u256, pos: u256) -> u256 {{ checked_frame_end<Sol>(pos, {size}, input.len()) }}','}'])
   lines.extend([f'impl Decode<Sol> for {record} {{','    fn decode_payload<D: AbiDecoder<Sol>>(_ d: mut D) -> Self {'])
   lines.extend(['        let pos = d.pos()',f'        let end = checked_frame_end<Sol>(pos, {size}, d.input().len())','        d.set_pos(end)','        let input = d.input()'])
   lines.extend(f'        let {n} = <{t} as Decode<Sol>>::decode_from(input, pos + {i*32})' for i,(n,t) in enumerate(fields))
   lines.extend(['        Self { '+', '.join(n for n,t in fields)+' }','    }','}'])
   lines.extend([f'impl Encode<Sol> for {record} {{','    fn encode(own self, _ ptr: *u8) {'])
   lines.extend(f'        <{t} as Encode<Sol>>::encode(self.{n}, core::ptr::offset_bytes(ptr, {i*32}))' for i,(n,t) in enumerate(fields))
   lines.extend(['    }','}'])
  raw=Path(root,source).read_text();license=re.search(r'SPDX-License-Identifier:\s*(\S+)',raw)[1]
  text=f'// SPDX-License-Identifier: {license}\n// Generated from pinned Solidity interface {e["inventory"]}.\n// Solidity tuple fields are represented by Fe tuples; integer widths use std ABI wrappers.\nuse std::abi::{{'+', '.join(sorted(imports))+'}\nuse std::evm::Address\n'+('use core::abi::{AbiSize, AbiSpan, AbiDecoder, ByteInput, Decode, Encode, checked_frame_end}\n' if records else '')+'\n'.join(lines)+'\n'
  (out/f'{module}.fe').write_text(text)
  index.append(dict(e,contract=contract,module=module,functions=functions,abi=abi,reference_sha256=hashlib.sha256(raw.encode()).hexdigest()))
(args.output/'interfaces.fe').write_text(''.join('pub use '+m+'\n' for m in modules))
(args.output/'interface-index.json').write_text(json.dumps(index,indent=2)+'\n')
print(len(index),'interfaces,',sum(len(x['functions']) for x in index),'callable methods')
