#!/usr/bin/env python3
"""Operate the deployed contracts through actual local transactions."""
from runtime import *
import base64,hashlib
m=json.loads(Path(args.output).read_text());c=m['contracts'];plans=m['branches'];bold=c['BoldToken'];gov=c['Governance'];bribe=c['BribeInitiative'];maxuint=2**256-1
assert m['chainId']==31337 and m['owner'].lower()==owner.lower()
def arr(xs):return '['+','.join(map(str,xs))+']'
def trove(user,index):return int(keccak('0x'+enc('address,address,uint256',user,user,index)),16)
def balance(token,user):return number(token,'balanceOf(address)',user)
def mine(timestamp):rpc('evm_setNextBlockTimestamp',timestamp);rpc('evm_mine')
def now():return int(rpc('eth_getBlockByNumber','latest',False)['timestamp'],16)
def price(p,value):
 send(p['oracle'],'set(int256)',value//10**10)
 if p['secondary']:send(p['secondary'],'set(int256)',10**18 if p['symbol']=='rETH' else value//10**10)
def conserve():
 debt=0
 for p in plans:
  a=p['addresses'];sp=a['StabilityPool'];active=a['ActivePool'];defaults=a['DefaultPool'];coll=p['coll']
  assert balance(bold,sp)==sum(number(sp,f) for f in ['getTotalBoldDeposits()','getYieldGainsOwed()','getYieldGainsPending()'])
  for pool in [sp,active,defaults]:assert balance(coll,pool)==number(pool,'getCollBalance()')
  debt+=number(active,'aggRecordedDebt()')+number(defaults,'getBoldDebt()')
 assert number(bold,'totalSupply()')==debt
for p in plans:
 a=p['addresses'];bo=a['BorrowerOperations'];weth='0x'+call(p['registry'],'WETH()')[-40:]
 for user,index,amount,rate in [(alice,1,20*10**18,5*10**16),(bob,2,10*10**18,8*10**16)]:
  send(p['coll'],'mint(address,uint256)',user,amount+375*10**14)
  if weth.lower()!=p['coll'].lower():send(weth,'mint(address,uint256)',user,375*10**14)
  send(p['coll'],'approve(address,uint256)',bo,maxuint,sender=user)
  if weth.lower()!=p['coll'].lower():send(weth,'approve(address,uint256)',bo,maxuint,sender=user)
  send(bo,'openTrove(address,uint256,uint256,uint256,uint256,uint256,uint256,uint256,address,address,address)',user,index,amount,3000*10**18,0,0,rate,maxuint,zero,zero,zero,sender=user)
  assert number(a['TroveManager'],'getTroveStatus(uint256)',trove(user,index))==1
 send(a['StabilityPool'],'provideToSP(uint256,bool)',500*10**18,'false',sender=alice)
 raw=bytes.fromhex(call(a['TroveNFT'],'tokenURI(uint256)',trove(alice,1))[2:]);offset=int.from_bytes(raw[:32]);length=int.from_bytes(raw[offset:offset+32]);uri=raw[offset+32:offset+32+length].decode()
 assert uri.startswith('data:application/json;base64,');metadata=json.loads(base64.b64decode(uri.split(',',1)[1]));assert metadata['image'].startswith('data:image/svg+xml;base64,')
 assert '<svg ' in base64.b64decode(metadata['image'].split(',',1)[1]).decode()
 print('Opened both troves, deposited BOLD and rendered NFT: '+p['symbol'],flush=True)
conserve()
# LQTY approval goes to the deterministic UserProxy, as on the real token.
proxy='0x'+call(gov,'deriveUserProxyAddress(address)',alice)[-40:]
send(c['lqty'],'mint(address,uint256)',alice,100*10**18);send(c['lqty'],'approve(address,uint256)',proxy,maxuint,sender=alice)
send(gov,'depositLQTY(uint256)',100*10**18,sender=alice)
start=number(gov,'EPOCH_START()');duration=number(gov,'EPOCH_DURATION()');epoch=(now()-start)//duration+1
mine(start+epoch*duration);epoch+=1
targets=[bribe,c['CurveV2GaugeRewards'],c['UniV4MerklRewards']]
send(gov,'allocateLQTY(address[],address[],int256[],int256[])','[]',arr(targets),arr([40*10**18,30*10**18,30*10**18]),'[0,0,0]',sender=alice)
send(bold,'approve(address,uint256)',bribe,maxuint,sender=alice);send(c['bonus'],'mint(address,uint256)',alice,200*10**18);send(c['bonus'],'approve(address,uint256)',bribe,maxuint,sender=alice)
send(bribe,'depositBribe(uint256,uint256,uint256)',100*10**18,200*10**18,epoch,sender=alice)
mine(now()+30*86400)
for p in plans:
 price(p,2000*10**18);send(p['addresses']['StabilityPool'],'provideToSP(uint256,bool)',100*10**18,'false',sender=bob)
income=balance(bold,gov);assert income>=5*10**18
send(gov,'claimForInitiative(address)',bribe)
send(gov,'claimForInitiative(address)',c['CurveV2GaugeRewards'])
send(c['UniV4MerklRewards'],'claimForInitiative()')
send(bribe,'claimBribes((uint256,uint256,uint256)[])',f'[({epoch},{epoch},{epoch})]',sender=alice)
assert balance(bold,gov)<=2 and balance(c['bonus'],alice)==200*10**18
assert balance(bold,gov)+balance(bold,bribe)+balance(bold,c['externalGauge'])+balance(bold,c['externalDistributionCreator'])==income
assert number(c['externalGauge'],'deposited()')==balance(bold,c['externalGauge'])>0
assert number(c['externalDistributionCreator'],'calls()')==1 and number(c['externalDistributionCreator'],'amount()')==balance(bold,c['externalDistributionCreator'])>0
send(gov,'resetAllocations(address[],bool)',arr(targets),'true',sender=alice);send(gov,'withdrawLQTY(uint256,bool,address)',100*10**18,'false',alice,sender=alice)
assert balance(c['lqty'],alice)==100*10**18
conserve();print('Governance income, bribe claims, Curve gauge, Merkl campaign and LQTY withdrawal passed',flush=True)
cr=c['CollateralRegistry'];before=balance(bold,alice);send(cr,'redeemCollateral(uint256,uint256,uint256)',1000*10**18,0,10**18,sender=alice);assert balance(bold,alice)<before
p=plans[2];price(p,300*10**18);send(p['addresses']['TroveManager'],'batchLiquidateTroves(uint256[])',arr([trove(bob,2)]));assert number(p['addresses']['TroveManager'],'getTroveStatus(uint256)',trove(bob,2))==3
price(p,2000*10**18);conserve()
p=plans[1];price(p,50*10**18);send(p['addresses']['BorrowerOperations'],'shutdown()');frozen=number(p['addresses']['ActivePool'],'getCollBalance()')
send(cr,'redeemCollateral(uint256,uint256,uint256)',300*10**18,0,10**18,sender=alice);assert number(p['addresses']['ActivePool'],'getCollBalance()')==frozen
conserve();print('Redemption, liquidation, branch shutdown and conservation passed',flush=True)
report={'result':'passed','deployment':args.output,'deployment_sha256':hashlib.sha256(Path(args.output).read_bytes()).hexdigest(),'smoke_transactions':receipts,'governance_income':income,'scope':'Real Fe core/governance/metadata/helper deployment with local external fixtures; ordinary transactions with normal size limits. Only external Balancer/Merkl fixtures are installed at canonical addresses; no Fe protocol code is injected.'}
Path(args.output).with_name('smoke-result.json').write_text(json.dumps(report,indent=2)+'\n')
