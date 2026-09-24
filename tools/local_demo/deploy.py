#!/usr/bin/env python3
from runtime import *
factory=mock('DevCreate2');records['factory']=factory

def predict(init,salt):return '0x'+keccak('0xff'+factory[2:]+salt.to_bytes(32,'big').hex()+keccak('0x'+init)[2:])[-40:]
def deploy(name,types='',*values,salt=0,label=None):
 init=bytecode(name)+enc(types,*values);return deploy_init(init,salt,label or name)
def deploy_init(init,salt,label):
 address=predict(init,salt);assert rpc('eth_getCode',address,'latest')=='0x',f'already deployed {label}'
 send(factory,'deploy(bytes32,bytes)','0x'+salt.to_bytes(32,'big').hex(),'0x'+init)
 size=(len(rpc('eth_getCode',address,'latest'))-2)//2;assert 0<size<=24576
 records[label]=address;print(f'{label}: {address} ({size} bytes)',flush=True);return address

def arr(xs):return '['+','.join(map(str,xs))+']'
deploy('Constants')
bold=deploy('BoldToken','address',owner)
lqty=mock('DevToken','string,string','Local LQTY','LQTY');lusd=mock('DevToken','string,string','Local LUSD','LUSD');staking=mock('DevStaking','address',lqty);bonus=mock('DevToken','string,string','Local reward','REWARD')
mods=[deploy('Governance'+n+'Module') for n in ('Staking','Voting','Actions')]
now=int(rpc('eth_getBlockByNumber','latest',False)['timestamp'],16)
cfg=(0,10**16,2*10**18,4,10**16,10**18,5*10**18,now,86400,77760)
gov=deploy('Governance','address,address,address,address,('+','.join(['uint256']*10)+'),address,address[],address,address,address',lqty,lusd,staking,bold,'('+','.join(map(str,cfg))+')',owner,'[]',*mods)
bribe=deploy('BribeInitiative','address,address,address',gov,bold,bonus)
gauge=mock('DevGauge');records['externalGauge']=gauge
curve_rewards=deploy('CurveV2GaugeRewards','address,address,address,address,uint256',gov,bold,bonus,gauge,7*86400)
creator='0x8bb4c975ff3c250e0ceea271728547f3802b36fd'
creator_code=json.loads((P/'out'/'DevDependencies.sol'/'DevDistributionCreator.json').read_text())['deployedBytecode']['object']
assert rpc('eth_getCode',creator,'latest')=='0x';rpc('anvil_setCode',creator,creator_code);records['externalDistributionCreator']=creator
merkl_rewards=deploy('UniV4MerklRewards','address,address,uint256,bytes32,uint32,uint32,uint32',gov,bold,10**18,'0x'+(123).to_bytes(32,'big').hex(),6000,4000,0)
send(gov,'registerInitialInitiatives(address[])',arr([bribe,curve_rewards,merkl_rewards]))
records.update(lqty=lqty,lusd=lusd,stakingV1=staking,bonus=bonus)
# SSTORE2 code is STOP + the pinned production font and logo payloads.
payload=b'';sigs=[];ranges=[]
for name,file in [('geist','geist'),('BOLD','bold_logo'),('WETH','weth_logo'),('wstETH','wsteth_logo'),('rETH','reth_logo')]:
 data=(ROOT/'reference/bold/contracts/utils/assets'/f'{file}.txt').read_bytes();sigs.append(keccak(name)[:10]);ranges.append(f'({len(payload)},{len(payload)+len(data)})');payload+=data
runtime=b'\0'+payload;size=len(runtime);assert size<=24576
asset_init='61'+size.to_bytes(2,'big').hex()+'600e60003961'+size.to_bytes(2,'big').hex()+'6000f3'+runtime.hex()
pointer=deploy_init(asset_init,0,'AssetPointer')
reader=deploy('FixedAssetReader','address,bytes4[],(uint128,uint128)[]',pointer,arr(sigs),arr(ranges))
metadata=deploy('MetadataNFT','address',reader)
weth=mock('DevToken','string,string','Wrapped Ether','WETH');rate=mock('DevRate');plans=[]
for i,symbol in enumerate(['WETH','rETH','wstETH']):
 salt=i+1;coll=weth if i==0 else mock('DevToken','string,string','Local '+symbol,symbol)
 registry=deploy('AddressesRegistry','address,uint256,uint256,uint256,uint256,uint256,uint256',owner,15*10**17,11*10**17,10**17,11*10**17,5*10**16,10**17,salt=salt,label=symbol+'.AddressesRegistry')
 inits={}
 for name in ['BorrowerOpening','BorrowerAdjustments','BorrowerBatches','TroveLiquidations','ActivePool','DefaultPool','StabilityPool','TroveNFT','SortedTroves','GasPool','CollSurplusPool']:
  inits[name]=bytecode(name)+enc('address',registry)
 for name in ['TroveOperations','TroveRedemptions']:inits[name]=bytecode(name)
 inits['BorrowerOperations']=bytecode('BorrowerOperations')+enc('address,address,address,address',registry,*[predict(inits[n],salt) for n in ['BorrowerOpening','BorrowerAdjustments','BorrowerBatches']])
 inits['TroveManager']=bytecode('TroveManager')+enc('address,address,address,address',registry,*[predict(inits[n],salt) for n in ['TroveOperations','TroveRedemptions','TroveLiquidations']])
 oracle=mock('DevOracle','uint8,int256',8,2000*10**8);second=None;feed=['WETHPriceFeed','RETHPriceFeed','WSTETHPriceFeed'][i]
 if i==0:inits[feed]=bytecode(feed)+enc('address,uint256,address',oracle,7*86400,predict(inits['BorrowerOperations'],salt))
 else:
  second=mock('DevOracle','uint8,int256',18 if i==1 else 8,10**18 if i==1 else 2000*10**8)
  inits[feed]=bytecode(feed)+enc('address,address,address,uint256,uint256,address',oracle,second,rate,7*86400,7*86400,predict(inits['BorrowerOperations'],salt))
 plans.append(dict(symbol=symbol,coll=coll,registry=registry,inits=inits,salt=salt,oracle=oracle,secondary=second,feedName=feed))
cr=deploy('CollateralRegistry','address,address[],address[]',bold,arr([p['coll'] for p in plans]),arr([predict(p['inits']['TroveManager'],p['salt']) for p in plans]))
hints=deploy('HintHelpers','address',cr);multi=deploy('MultiTroveGetter','address',cr);deploy('DebtInFrontHelper','address,address',cr,hints)
for p in plans:
 addresses={name:predict(init,p['salt']) for name,init in p['inits'].items()}
 a=addresses
 values=[p['coll'],a['BorrowerOperations'],a['TroveManager'],a['TroveNFT'],metadata,a['StabilityPool'],a[p['feedName']],a['ActivePool'],a['DefaultPool'],a['GasPool'],a['CollSurplusPool'],a['SortedTroves'],gov,hints,multi,cr,bold,weth]
 send(p['registry'],'setAddresses(('+','.join(['address']*18)+'))','('+','.join(values)+')')
 for name,init in p['inits'].items():deploy_init(init,p['salt'],p['symbol']+'.'+name)
 send(bold,'setBranchAddresses(address,address,address,address)',a['TroveManager'],a['StabilityPool'],a['BorrowerOperations'],a['ActivePool'])
 p['addresses']=addresses;p.pop('inits')
send(bold,'setCollateralRegistry(address)',cr)
deploy('RedemptionHelper','address,address[]',cr,arr([p['registry'] for p in plans]))
# Balancer's canonical external vault address is immutable in the upstream adapter.
# Install only the explicit external dev vault fixture there; all Fe contracts
# are deployed by transactions and keep the standard EVM limits.
vault='0xba12222222228d8ba445958a75a0704d566bf2c8'
vault_code=json.loads((P/'out'/'DevDependencies.sol'/'DevBalancerVault.json').read_text())['deployedBytecode']['object']
assert rpc('eth_getCode',vault,'latest')=='0x'
rpc('anvil_setCode',vault,vault_code);records['externalBalancerVault']=vault
flash=deploy('BalancerFlashLoan');usdc=mock('DevToken','string,string','Local USDC','USDC');send(usdc,'setDecimals(uint8)',6)
router=mock('DevUniRouter');stable=mock('DevCurvePool','address,address,uint256',usdc,bold,10**12)
records.update(usdc=usdc,externalUniRouter=router,externalStablePool=stable)
for token,price in [(bold,1),(usdc,10**12),(weth,2000)]+[(p['coll'],2000) for p in plans]:send(router,'setPrice(address,uint256)',token,price)
for p in plans:
 pool=mock('DevCurvePool','address,address,uint256',p['coll'],bold,2000)
 exchanges={}
 exchanges['CurveExchange']=deploy('CurveExchange','address,address,address,uint256,uint256',p['coll'],bold,pool,0,1,label=p['symbol']+'.CurveExchange')
 exchanges['UniV3Exchange']=deploy('UniV3Exchange','address,address,uint24,address',p['coll'],bold,3000,router,label=p['symbol']+'.UniV3Exchange')
 exchanges['HybridCurveUniV3Exchange']=deploy('HybridCurveUniV3Exchange','address,address,address,address,address,uint128,uint128,uint24,uint24,address',p['coll'],bold,usdc,weth,stable,0,1,500,3000,router,label=p['symbol']+'.HybridCurveUniV3Exchange')
 p['externalCurvePool']=pool;p['exchanges']=exchanges;p['zappers']={}
 basic='WETHZapper' if p['symbol']=='WETH' else 'GasCompZapper'
 leveraged='LeverageWETHZapper' if p['symbol']=='WETH' else 'LeverageLSTZapper'
 p['zappers'][basic]=deploy(basic,'address,address,address',p['registry'],flash,exchanges['CurveExchange'],label=p['symbol']+'.'+basic)
 p['zappers'][leveraged]=deploy(leveraged,'address,address,address',p['registry'],flash,exchanges['CurveExchange'],label=p['symbol']+'.'+leveraged)
 # Alternative deployments exercise each actual exchange adapter through a zapper.
 for kind in ['UniV3Exchange','HybridCurveUniV3Exchange']:
  p['zappers'][leveraged+'.'+kind]=deploy(leveraged,'address,address,address',p['registry'],flash,exchanges[kind],label=p['symbol']+'.'+leveraged+'.'+kind)
for name,indices in [('HybridCurveUniV3ExchangeHelpers','uint128,uint128'),('HybridCurveUniV3ExchangeHelpersV2','int128,int128')]:
 deploy(name,'address,address,address,'+indices+',uint24,uint24,address',usdc,weth,stable,0,1,500,3000,router)
assert number(cr,'totalCollaterals()')==3
manifest={'chainId':31337,'rpc':args.rpc,'owner':owner,'alice':alice,'bob':bob,'contracts':records,'branches':plans,'transactions':receipts,'external_dependencies':'DevToken, DevOracle, DevRate, DevStaking, DevBalancerVault, DevCurvePool, DevUniRouter, DevGauge and DevDistributionCreator are controlled local Solidity fixtures. The external Balancer vault and Merkl creator fixtures are installed at their canonical addresses using anvil_setCode; no Fe protocol code is injected. All named Liquity core/governance/metadata/helper contracts use Fe bytecode.'}
Path(args.output).write_text(json.dumps(manifest,indent=2)+'\n');print('Deployment manifest: '+args.output,flush=True)
