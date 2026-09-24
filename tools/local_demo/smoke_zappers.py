#!/usr/bin/env python3
"""Check Fe zappers and exchange adapters against explicitly local market fixtures."""
from runtime import *
import hashlib
m=json.loads(Path(args.output).read_text());c=m['contracts'];plans=m['branches'];bold=c['BoldToken'];maxuint=2**256-1
weth=plans[0]['coll'];vault=c['externalBalancerVault'];router=c['externalUniRouter'];stable=c['externalStablePool'];usdc=c['usdc']
def balance(token,user):return number(token,'balanceOf(address)',user)
def arr(xs):return '['+','.join(map(str,xs))+']'
def zapper_id(z,index):return int(keccak('0x'+enc('address,address,uint256',z,alice,int(keccak('0x'+enc('address,uint256',alice,index)),16))),16)
def debt(manager,tid):return int(call(manager,'getLatestTroveData(uint256)',tid)[2:66],16)
def conserve():
 total=0
 for p in plans:
  a=p['addresses'];sp=a['StabilityPool'];active=a['ActivePool'];defaults=a['DefaultPool']
  assert balance(bold,sp)==sum(number(sp,f) for f in ['getTotalBoldDeposits()','getYieldGainsOwed()','getYieldGainsPending()'])
  for pool in [sp,active,defaults]:assert balance(p['coll'],pool)==number(pool,'getCollBalance()')
  total+=number(active,'aggRecordedDebt()')+number(defaults,'getBoldDebt()')
 assert number(bold,'totalSupply()')==total
# External fixture liquidity is funded using real BOLD borrowed from Fe.
tx('0x',weth,value=1000*10**18)
for p in plans:
 bo=p['addresses']['BorrowerOperations'];coll=p['coll']
 send(coll,'mint(address,uint256)',owner,101*10**18);send(weth,'mint(address,uint256)',owner,10**18)
 send(coll,'approve(address,uint256)',bo,maxuint);send(weth,'approve(address,uint256)',bo,maxuint)
 send(bo,'openTrove(address,uint256,uint256,uint256,uint256,uint256,uint256,uint256,address,address,address)',owner,99,100*10**18,50000*10**18,0,0,5*10**16,maxuint,zero,zero,zero)
 send(bold,'transfer(address,uint256)',p['externalCurvePool'],10000*10**18)
 for dst in [p['externalCurvePool'],router,vault]:send(coll,'mint(address,uint256)',dst,100*10**18)
send(bold,'transfer(address,uint256)',router,30000*10**18);send(bold,'transfer(address,uint256)',stable,30000*10**18)
for dst in [router,stable]:send(usdc,'mint(address,uint256)',dst,100000*10**6)
send(bold,'transfer(address,uint256)',alice,1000*10**18)
for p in plans:
 a=p['addresses'];coll=p['coll'];lst=p['symbol']!='WETH';manager=a['TroveManager'];basic='GasCompZapper' if lst else 'WETHZapper';z=p['zappers'][basic]
 if lst:send(coll,'mint(address,uint256)',alice,100*10**18);send(coll,'approve(address,uint256)',z,maxuint,sender=alice)
 params=[alice,100,20*10**18,3000*10**18,0,0,5*10**16,zero,maxuint,zero,zero,zero]
 sig='openTroveWithRawETH((address,uint256,uint256,uint256,uint256,uint256,uint256,address,uint256,address,address,address))'
 tx(calldata(sig,'('+','.join(map(str,params))+')'),z,alice,375*10**14+(0 if lst else 20*10**18))
 tid=zapper_id(z,100);assert number(manager,'getTroveStatus(uint256)',tid)==1
 send(bold,'approve(address,uint256)',z,maxuint,sender=alice);send(z,'closeTroveToRawETH(uint256)',tid,sender=alice);assert number(manager,'getTroveStatus(uint256)',tid)==2
 conserve();print('Basic zapper open/close: '+p['symbol'],flush=True)
 for index,(name,z) in enumerate((entry for entry in p['zappers'].items() if entry[0]!=basic),200):
  if lst:send(coll,'approve(address,uint256)',z,maxuint,sender=alice)
  params=[alice,index,20*10**18,10**18,3000*10**18,0,0,5*10**16,zero,maxuint,zero,zero,zero]
  sig='openLeveragedTroveWithRawETH((address,uint256,uint256,uint256,uint256,uint256,uint256,uint256,address,uint256,address,address,address))'
  tx(calldata(sig,'('+','.join(map(str,params))+')'),z,alice,375*10**14+(0 if lst else 20*10**18))
  tid=zapper_id(z,index);assert number(manager,'getTroveStatus(uint256)',tid)==1
  send(z,'leverUpTrove((uint256,uint256,uint256,uint256))',f'({tid},{10**17},{500*10**18},{maxuint})',sender=alice)
  send(z,'leverDownTrove((uint256,uint256,uint256))',f'({tid},{10**17},{199*10**18})',sender=alice)
  conserve();assert number(c['BalancerFlashLoan'],'receiver()')==0
  loan=debt(manager,tid)//2000+10**15
  send(z,'closeTroveFromCollateral(uint256,uint256,uint256)',tid,loan,17*10**18,sender=alice)
  assert number(manager,'getTroveStatus(uint256)',tid)==2
  for token in [bold,coll]:assert balance(token,z)==0 and balance(token,c['BalancerFlashLoan'])==0
  assert int(rpc('eth_getBalance',z,'latest'),16)==0
  conserve();print('Leveraged open/up/down/flash-close: '+p['symbol']+' '+name,flush=True)
 # Query both Fe helper generations using the same external market prices.
 answer=call(c['HybridCurveUniV3ExchangeHelpers'],'getCollFromBold(uint256,address,uint256)',2000*10**18,coll,10**18)
 assert int(answer[2:66],16)==10**18
 answer=call(c['HybridCurveUniV3ExchangeHelpersV2'],'quoteExactInput(uint256,bool,address)',2000*10**18,'false',coll)
 assert int(answer,16)==10**18
for p in plans:
 for ex in p['exchanges'].values():
  for token in [bold,p['coll'],usdc,weth]:assert balance(token,ex)==0
# Exercise interest-batch membership and fee/rate updates on a real LP trove.
p=plans[0];bo=p['addresses']['BorrowerOperations'];manager=p['addresses']['TroveManager']
tid=int(keccak('0x'+enc('address,address,uint256',owner,owner,99)),16)
send(bo,'registerBatchManager(uint128,uint128,uint128,uint128,uint128)',5*10**15,25*10**17,7*10**16,10**16,3600,sender=bob)
send(bo,'setInterestBatchManager(uint256,address,uint256,uint256,uint256)',tid,bob,0,0,maxuint)
assert number(bo,'interestBatchManagerOf(uint256)',tid)==int(bob,16);conserve()
send(bo,'lowerBatchManagementFee(uint256)',5*10**15,sender=bob)
rpc('evm_increaseTime',3601);rpc('evm_mine')
send(bo,'setBatchManagerAnnualInterestRate(uint128,uint256,uint256,uint256)',9*10**16,0,0,maxuint,sender=bob)
send(bo,'applyPendingDebt(uint256,uint256,uint256)',tid,0,0)
assert number(manager,'getTroveAnnualInterestRate(uint256)',tid)==9*10**16
send(bo,'removeFromBatch(uint256,uint256,uint256,uint256,uint256)',tid,7*10**16,0,0,maxuint)
assert number(bo,'interestBatchManagerOf(uint256)',tid)==0
assert number(manager,'getTroveAnnualInterestRate(uint256)',tid)==7*10**16
conserve();print('Interest batch join, fee/rate changes, pending debt and exit passed',flush=True)
report={'result':'passed','deployment_sha256':hashlib.sha256(Path(args.output).read_bytes()).hexdigest(),'transactions':receipts,'scope':'All four actual Fe zapper types, three exchange adapters, two helper generations and the Fe Balancer adapter, plus batch lifecycle; external markets/vault are declared local fixtures.'}
Path(args.output).with_name('zapper-smoke-result.json').write_text(json.dumps(report,indent=2)+'\n')
