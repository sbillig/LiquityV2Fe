#!/usr/bin/env python3
"""Audit Fe ABI shapes and export Solidity-compatible protocol ABI metadata.

This is a metadata gate, not a replacement for runtime differential testing.
The EIP712 handler explicitly returns a flat payload; Fe's declared tuple remains
visible in its unmodified compiler ABI. Pure getters refine Solidity view getters.
The allowlists below contain declarations unreachable in the reference runtime.
"""
import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACTS = ['AddressesRegistry', 'GasPool', 'DefaultPool', 'CollSurplusPool', 'ActivePool', 'BoldToken', 'SortedTroves', 'TroveNFT', 'FixedAssetReader', 'MetadataNFT', 'AddRemoveManagers', 'LiquityBase', 'CollateralRegistry', 'StabilityPool', 'TroveManager', 'BorrowerOperations', 'WETHPriceFeed', 'RETHPriceFeed', 'WSTETHPriceFeed', 'HintHelpers', 'MultiTroveGetter', 'DebtInFrontHelper', 'Constants']
DECLARATION_ONLY = {
    'AddRemoveManagers': {('error', 'NotOwnerNorAddManager()'), ('error', 'NotOwnerNorRemoveManager()')},
    'ActivePool': {('event', 'ActivePoolBoldDebtUpdated(uint256)')},
    'BoldToken': {('event', 'EIP712DomainChanged()'),
                  ('error', 'StringTooLong(string)'), ('error', 'InvalidShortString()')},
}

READ_ONLY_CAPABILITIES = {
    'DebtInFrontHelper': ('STATICCALL', {'getDebtBetweenInterestRates(uint256,uint256,uint256,uint256,uint256,uint256)', 'getDebtBetweenInterestRateAndTrove(uint256,uint256,uint256,uint256,uint256,uint256)'}),
    'HintHelpers': ('STATICCALL', {
        'getApproxHint(uint256,uint256,uint256,uint256)',
        'predictOpenTroveUpfrontFee(uint256,uint256,uint256)',
        'predictAdjustInterestRateUpfrontFee(uint256,uint256,uint256)',
        'forcePredictAdjustInterestRateUpfrontFee(uint256,uint256,uint256)',
        'predictAdjustTroveUpfrontFee(uint256,uint256,uint256)',
        'predictAdjustBatchInterestRateUpfrontFee(uint256,address,uint256)',
        'predictOpenTroveAndJoinBatchUpfrontFee(uint256,uint256,address)',
        'predictJoinBatchInterestRateUpfrontFee(uint256,uint256,address)',
        'predictRemoveFromBatchUpfrontFee(uint256,uint256,uint256)',
    }),
    'MultiTroveGetter': ('STATICCALL', {'getMultipleSortedTroves(uint256,int256,uint256)', 'getDebtPerInterestRateAscending(uint256,uint256,uint256)'}),
    'BorrowerOperations': ('STATICCALL', {'getEntireBranchColl()', 'getEntireBranchDebt()'}),
    'TroveManager': ('STATICCALL', {'getEntireBranchColl()', 'getEntireBranchDebt()'}),
    'StabilityPool': ('STATICCALL', {'getEntireBranchColl()', 'getEntireBranchDebt()', 'getDepositorYieldGainWithPending(address)'}),
    'CollateralRegistry': ('STATICCALL', {'getRedemptionRateForRedeemedAmount(uint256)', 'getEffectiveRedemptionFeeInBold(uint256)'}),
    'LiquityBase': ('STATICCALL', {'getEntireBranchColl()', 'getEntireBranchDebt()'}),
    'SortedTroves': ('STATICCALL', {'validInsertPosition(uint256,uint256,uint256)', 'findInsertPosition(uint256,uint256,uint256)'}),
    'TroveNFT': ('STATICCALL', {'tokenURI(uint256)'}),
    'FixedAssetReader': ('EXTCODECOPY', {'readAsset(bytes4)'}),
    'MetadataNFT': ('STATICCALL', {
        'uri((uint256,address,address,address,uint256,uint256,uint256,uint8))',
        'dynamicTextComponents((uint256,address,address,address,uint256,uint256,uint256,uint8))',
    }),
}
STATIC_TUPLE_OUTPUTS = {
    'DebtInFrontHelper': {'getDebtBetweenInterestRates', 'getDebtBetweenInterestRateAndTrove'},
    'HintHelpers': {'getApproxHint'},
    'WETHPriceFeed': {'ethUsdOracle', 'fetchPrice', 'fetchRedemptionPrice'},
    'RETHPriceFeed': {'ethUsdOracle', 'rEthEthOracle', 'fetchPrice', 'fetchRedemptionPrice'},
    'WSTETHPriceFeed': {'ethUsdOracle', 'stEthUsdOracle', 'fetchPrice', 'fetchRedemptionPrice'},
    'BorrowerOperations': {'removeManagerReceiverOf'},
    'TroveManager': {'Troves', 'rewardSnapshots', 'getUnbackedPortionPriceAndRedeemability'},
    'StabilityPool': {'depositSnapshots'},
    'AddRemoveManagers': {'removeManagerReceiverOf'},
    'SortedTroves': {'nodes', 'batches', 'findInsertPosition'},
    'FixedAssetReader': {'assets'},
}

def typ(field):
    t = field['type']
    return '(' + ','.join(typ(c) for c in field['components']) + ')' + t[5:] if t.startswith('tuple') else t

def key(item):
    return item['type'], item.get('name', '') + '(' + ','.join(typ(f) for f in item.get('inputs', [])) + ')'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

reports = {}
out = ROOT / 'build/protocol'
out.mkdir(parents=True, exist_ok=True)
for contract in CONTRACTS:
    fe_path = ROOT / 'build' / (contract + '.abi.json')
    source_file = {'FixedAssetReader': 'FixedAssets'}.get(contract, contract)
    sol_path = ROOT / 'tests/out' / (source_file + '.sol') / (contract + '.json')
    compiled = json.loads(fe_path.read_text())
    reference = json.loads(sol_path.read_text())['abi']
    refinements = []
    if contract == 'BorrowerOperations':
        for companion in ['BorrowerOpening', 'BorrowerAdjustments', 'BorrowerBatches']:
            module_abi = json.loads((ROOT / 'build' / (companion + '.abi.json')).read_text())
            compiled += [e for e in module_abi if e['type'] in ('event', 'error')]
        constructor = next(e for e in reference if e['type'] == 'constructor')
        assert [typ(f) for f in constructor['inputs']] == ['address']
        constructor['inputs'] += [dict(type='address', internalType='address', name=n)
                                  for n in ['openingModule', 'adjustmentsModule', 'batchesModule']]
        refinements.append('constructor: registry plus three fixed, non-upgradeable delegate modules; each module reads immutable configuration from the same configured branch registry')
    if contract == 'TroveManager':
        # Fixed delegate modules preserve runtime selectors and manager storage.
        # Deployment explicitly supplies three module addresses; export the real
        # four-argument constructor, never the incompatible Solidity constructor.
        for companion in ['TroveOperations', 'TroveRedemptions', 'TroveLiquidations']:
            module_abi = json.loads((ROOT / 'build' / (companion + '.abi.json')).read_text())
            compiled += [e for e in module_abi if e['type'] in ('event', 'error')]
        memory_array_key = ('function', 'batchLiquidateTroves(uint256[])')
        assert memory_array_key not in {key(e) for e in compiled}
        # Fe deliberately omits numeric-selector receivers from ABI metadata.
        # This receiver uses a custom decoder for Solidity memory-allocation
        # error ordering; its unchanged wire signature is exercised directly.
        compiled.append(copy.deepcopy(next(e for e in reference if key(e) == memory_array_key)))
        refinements.append('batchLiquidateTroves: compiler omits explicit numeric selector 0xef49a6b4; custom uint256[] memory-array decoder is tested at the Solidity wire signature')
        constructor = next(e for e in reference if e['type'] == 'constructor')
        assert [typ(f) for f in constructor['inputs']] == ['address']
        constructor['inputs'] += [dict(type='address', internalType='address', name=n)
                                  for n in ['operationsModule', 'redemptionsModule', 'liquidationsModule']]
        refinements.append('constructor: registry plus three fixed, non-upgradeable delegate modules; event/error ABI includes module emissions at the manager address')
    normalized = copy.deepcopy(compiled)
    for entry in normalized:
        if contract == 'MultiTroveGetter' and key(entry) == ('function', 'getDebtPerInterestRateAscending(uint256,uint256,uint256)'):
            outputs = entry['outputs']
            assert len(outputs) == 1 and outputs[0]['type'] == 'tuple'
            assert [c['type'] for c in outputs[0]['components']] == ['tuple[]', 'uint256']
            entry['outputs'] = outputs[0]['components']
            refinements.append('getDebtPerInterestRateAscending: explicit flat dynamic-array and cursor runtime return')
        if contract == 'BoldToken' and key(entry) == ('function', 'eip712Domain()'):
            outputs = entry['outputs']
            assert len(outputs) == 1 and outputs[0]['type'] == 'tuple'
            entry['outputs'] = outputs[0]['components']
            refinements.append('eip712Domain: explicit flat runtime return')
        operation, view_signatures = READ_ONLY_CAPABILITIES.get(contract, ('', set()))
        if key(entry)[0] == 'function' and key(entry)[1] in view_signatures:
            assert entry['stateMutability'] == 'nonpayable'
            entry['stateMutability'] = 'view'
            refinements.append(entry['name'] + ': read-only ' + operation + '; Fe capability conservatively implies nonpayable')
        if entry.get('name') in STATIC_TUPLE_OUTPUTS.get(contract, set()):
            outputs = entry['outputs']
            assert len(outputs) == 1 and outputs[0]['type'] == 'tuple'
            assert all(c['type'] in ('uint256', 'uint128', 'uint64', 'uint8', 'address', 'bool') for c in outputs[0]['components'])
            entry['outputs'] = outputs[0]['components']
            refinements.append(entry['name'] + ': static tuple has identical flat runtime encoding')
    fe = {key(e): e for e in normalized}
    sol = {key(e): e for e in reference}
    missing = set(sol) - set(fe)
    extra = set(fe) - set(sol)
    assert missing <= DECLARATION_ONLY.get(contract, set()), (contract, 'missing ABI entries', missing)
    # Solidity omits its implicit standard errors from ABI metadata.
    assert extra <= {('error', 'Error(string)'), ('error', 'Panic(uint256)')}, (contract, 'extra ABI entries', extra)
    for k in sorted(set(sol) & set(fe)):
        x, y = fe[k], sol[k]
        assert [typ(f) for f in x.get('outputs', [])] == [typ(f) for f in y.get('outputs', [])], (contract, k, 'return shape')
        if k[0] in ('constructor', 'function'):
            fm, sm = x.get('stateMutability'), y.get('stateMutability')
            assert fm == sm or (fm, sm) == ('pure', 'view'), (contract, k, fm, sm)
            if fm != sm:
                refinements.append(k[1] + ': pure implementation of view function')
        if k[0] == 'event':
            assert x.get('anonymous', False) == y.get('anonymous', False)
            assert [f.get('indexed', False) for f in x['inputs']] == [f.get('indexed', False) for f in y['inputs']], (contract, k, 'indexed fields')
    target = out / (contract + '.abi.json')
    target.write_text(json.dumps(reference, indent=2) + '\n')
    runtime_size = len(bytes.fromhex((ROOT / 'build' / (contract + '.runtime.bin')).read_text().strip().removeprefix('0x')))
    init_size = len(bytes.fromhex((ROOT / 'build' / (contract + '.bin')).read_text().strip().removeprefix('0x')))
    assert runtime_size <= 24576, (contract, 'EIP170 runtime limit', runtime_size)
    assert init_size <= 49152, (contract, 'EIP3860 initcode limit before constructor arguments', init_size)
    reports[contract] = {
        'runtime_bytes': runtime_size, 'initcode_bytes_before_arguments': init_size,
        'compiler_abi_sha256': digest(fe_path), 'reference_artifact_sha256': digest(sol_path),
        'protocol_abi_sha256': digest(target), 'metadata_refinements': refinements,
        'declaration_only': sorted(map(list, missing)),
        'compiler_standard_errors': sorted(map(list, extra)),
        'function_count': sum(e['type'] == 'function' for e in reference),
    }
# Implementation companions have no direct Solidity protocol ABI counterpart.
# MetadataGeometry is created by the renderer; TroveManager modules are deployed
# explicitly and their immutable addresses are supplied to its constructor.
for contract in ['MetadataGeometry', 'TroveOperations', 'TroveRedemptions', 'TroveLiquidations', 'BorrowerOpening', 'BorrowerAdjustments', 'BorrowerBatches']:
    runtime = ROOT / 'build' / (contract + '.runtime.bin')
    init = ROOT / 'build' / (contract + '.bin')
    runtime_size = len(bytes.fromhex(runtime.read_text().strip().removeprefix('0x')))
    init_size = len(bytes.fromhex(init.read_text().strip().removeprefix('0x')))
    assert runtime_size <= 24576, (contract, 'EIP170 runtime limit', runtime_size)
    assert init_size <= 49152, (contract, 'EIP3860 initcode limit', init_size)
    reports[contract] = {'implementation_companion': True,
        'runtime_bytes': runtime_size, 'initcode_bytes_before_arguments': init_size,
        'runtime_sha256': digest(runtime), 'initcode_sha256': digest(init)}
(ROOT / 'tests/results/abi-audit.json').write_text(json.dumps(reports, indent=2) + '\n')
print('ABI shape audit passed for ' + ', '.join(CONTRACTS))
