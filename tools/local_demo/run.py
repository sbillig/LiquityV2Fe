#!/usr/bin/env python3
"""Start an isolated Anvil and deploy the Fe protocol; --smoke checks it and exits."""
import argparse,datetime,json,subprocess,sys,time,urllib.request
from pathlib import Path
P=Path(__file__).resolve().parent
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo',type=Path,default=Path.cwd());parser.add_argument('--artifacts',type=Path)
parser.add_argument('--port',type=int,default=18545);parser.add_argument('--output-dir',type=Path)
parser.add_argument('--smoke',action='store_true');args=parser.parse_args()
root=args.repo.resolve();artifacts=(args.artifacts or root/'build').resolve()
for name in ['Governance','BorrowerOperations','TroveManager','MetadataNFT']:
 if not (artifacts/f'{name}.bin').is_file():raise SystemExit(f'Missing {name} artifact; run the project build first.')
out=(args.output_dir or root/'deployments'/datetime.datetime.now(datetime.timezone.utc).strftime('local-%Y%m%d-%H%M%S')).resolve()
out.mkdir(parents=True,exist_ok=False)
subprocess.run(['forge','build','--root',str(P)],check=True)
rpc=f'http://127.0.0.1:{args.port}'
with (out/'anvil.log').open('w') as log:
 node=subprocess.Popen(['anvil','--host','127.0.0.1','--port',str(args.port),'--hardfork','cancun','--gas-limit','100000000','--silent'],stdout=log,stderr=subprocess.STDOUT)
 try:
  deadline=time.monotonic()+10
  while True:
   if node.poll() is not None:raise RuntimeError('Anvil failed to start; see '+str(out/'anvil.log'))
   try:
    req=urllib.request.Request(rpc,json.dumps({'jsonrpc':'2.0','id':1,'method':'web3_clientVersion','params':[]}).encode(),{'Content-Type':'application/json'})
    with urllib.request.urlopen(req,timeout=.5) as r:version=json.load(r)['result']
    # Check our child again; a port collision must never reuse somebody else's node.
    time.sleep(.1)
    if node.poll() is not None:raise RuntimeError('Anvil port unavailable')
    if 'anvil' in version.lower():break
   except (OSError,KeyError):pass
   if time.monotonic()>deadline:raise TimeoutError('Anvil did not become ready')
   time.sleep(.1)
  flags=['--rpc',rpc,'--repo',str(root),'--artifacts',str(artifacts),'--output',str(out/'deployment.json')]
  subprocess.run([sys.executable,str(P/'deploy.py'),*flags],check=True)
  if args.smoke:
   subprocess.run([sys.executable,str(P/'smoke_zappers.py'),*flags],check=True)
   subprocess.run([sys.executable,str(P/'smoke.py'),*flags],check=True)
   print('Smoke checks passed. Evidence: '+str(out/'smoke-result.json'),flush=True)
  else:
   print(f'Local protocol ready at {rpc}\nManifest: {out / "deployment.json"}\nKeep this command running; Ctrl-C stops its Anvil.',flush=True)
   node.wait()
 except KeyboardInterrupt:pass
 finally:
  if node.poll() is None:
   node.terminate()
   try:node.wait(timeout=10)
   except subprocess.TimeoutExpired:node.kill();node.wait()
