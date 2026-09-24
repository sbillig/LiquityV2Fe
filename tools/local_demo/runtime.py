#!/usr/bin/env python3
"""Deploy real Fe core/governance bytecode to a local Anvil, with explicit dev dependencies."""
import argparse,json,subprocess,time,urllib.request,urllib.parse
from pathlib import Path
P=Path(__file__).resolve().parent
parser=argparse.ArgumentParser();parser.add_argument('--rpc',default='http://127.0.0.1:18545');parser.add_argument('--output',default=str(P/'deployment.json'));parser.add_argument('--repo',type=Path,default=Path.cwd());parser.add_argument('--artifacts',type=Path);args=parser.parse_args()
ROOT=args.repo.resolve()
ARTIFACTS=(args.artifacts or ROOT/'build').resolve()
if urllib.parse.urlparse(args.rpc).hostname not in ('127.0.0.1','localhost','::1'):raise SystemExit('This development command requires a local Anvil endpoint')
def rpc(method,*params):
 req=urllib.request.Request(args.rpc,json.dumps({'jsonrpc':'2.0','id':1,'method':method,'params':params}).encode(),{'Content-Type':'application/json'})
 with urllib.request.urlopen(req,timeout=60) as r:d=json.load(r)
 if 'error' in d:raise RuntimeError(f'{method}: {d["error"]}')
 return d['result']
assert 'anvil' in rpc('web3_clientVersion').lower()
assert int(rpc('eth_chainId'),16)==31337
accounts=rpc('eth_accounts');owner=accounts[0];alice=accounts[1];bob=accounts[2];zero='0x'+'00'*20
records={};receipts=[]
def cast(*a):return subprocess.check_output(['cast',*map(str,a)],text=True).strip()
def enc(types,*values):return cast('abi-encode','f('+types+')',*values)[2:]
def calldata(signature,*values):return cast('calldata',signature,*values)
def keccak(data):return cast('keccak',data)
def tx(data,to=None,sender=owner,value=0):
 obj={'from':sender,'data':data,'gas':hex(95000000),'value':hex(value)}
 if to:obj['to']=to
 h=rpc('eth_sendTransaction',obj);deadline=time.monotonic()+60
 while True:
  r=rpc('eth_getTransactionReceipt',h)
  if r:break
  if time.monotonic()>deadline:raise TimeoutError(h)
  time.sleep(.05)
 receipts.append({'transactionHash':h,'gasUsed':int(r['gasUsed'],16)})
 if int(r['status'],16)!=1:
  try:
   trace=rpc('debug_traceTransaction',h,{'tracer':'callTracer'});detail=trace.get('output',trace.get('returnValue',''))
  except Exception:detail='trace unavailable'
  raise RuntimeError(f'Transaction reverted: {h}, target={to}, output={detail}')
 return r

def send(to,sig,*vals,sender=owner):return tx(calldata(sig,*vals),to,sender)
def call(to,sig,*vals):return rpc('eth_call',{'to':to,'data':calldata(sig,*vals)},'latest')
def number(to,sig,*vals):return int(call(to,sig,*vals),16)
def bytecode(name):return (ARTIFACTS/f'{name}.bin').read_text().strip().removeprefix('0x')
def mock(name,types='',*values):
 init=json.loads((P/'out'/'DevDependencies.sol'/f'{name}.json').read_text())['bytecode']['object']
 return tx(init+enc(types,*values))['contractAddress']
