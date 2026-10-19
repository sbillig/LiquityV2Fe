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
CONTRACTS = ['AddressesRegistry', 'GasPool', 'DefaultPool', 'CollSurplusPool', 'ActivePool', 'BoldToken', 'SortedTroves', 'TroveNFT', 'FixedAssetReader', 'MetadataNFT', 'AddRemoveManagers', 'LiquityBase', 'CollateralRegistry', 'StabilityPool', 'TroveManager', 'BorrowerOperations', 'WETHPriceFeed', 'RETHPriceFeed', 'WSTETHPriceFeed', 'HintHelpers', 'MultiTroveGetter', 'DebtInFrontHelper', 'Constants', 'RedemptionHelper', 'WETHZapper', 'GasCompZapper', 'LeverageWETHZapper', 'LeverageLSTZapper', 'CurveExchange', 'UniV3Exchange', 'UniPriceConverter', 'HybridCurveUniV3Exchange', 'HybridCurveUniV3ExchangeHelpers', 'HybridCurveUniV3ExchangeHelpersV2', 'BalancerFlashLoan', 'UserProxy', 'UserProxyFactory', 'BribeInitiative', 'CurveV2GaugeRewards', 'UniV4MerklRewards', 'Governance']
DECLARATION_ONLY = {
    'Governance': {('error', 'AddressInsufficientBalance(address)')},
    # Governance SafeERC20 calls carry zero ETH; this Address error is unreachable.
    'BribeInitiative': {('error', 'AddressInsufficientBalance(address)')},
    'CurveV2GaugeRewards': {('error', 'AddressInsufficientBalance(address)')},
    'AddRemoveManagers': {('error', 'NotOwnerNorAddManager()'), ('error', 'NotOwnerNorRemoveManager()')},
    'ActivePool': {('event', 'ActivePoolBoldDebtUpdated(uint256)')},
    'BoldToken': {('event', 'EIP712DomainChanged()'),
                  ('error', 'StringTooLong(string)'), ('error', 'InvalidShortString()')},
}

# Remaining raw effects have no shared equivalent for these operations.
READ_ONLY_CAPABILITIES = {
    'RedemptionHelper': ('SLOAD and empty revert', {'addresses(uint256)'}),
    'MultiTroveGetter': ('STATICCALL and explicit returndata', {'getDebtPerInterestRateAscending(uint256,uint256,uint256)'}),
    'FixedAssetReader': ('EXTCODECOPY', {'readAsset(bytes4)'}),
}
STATIC_TUPLE_OUTPUTS = {
    'BribeInitiative': {'bribeByEpoch', 'totalLQTYAllocatedByEpoch', 'lqtyAllocatedByUserAtEpoch', 'claimBribes'},
    'CurveV2GaugeRewards': {'bribeByEpoch', 'totalLQTYAllocatedByEpoch', 'lqtyAllocatedByUserAtEpoch', 'claimBribes'},
    'UserProxy': {'stake', 'unstake'},
    'HybridCurveUniV3ExchangeHelpers': {'getCollFromBold'},
    'GasCompZapper': {'removeManagerReceiverOf'},
    'LeverageWETHZapper': {'removeManagerReceiverOf'},
    'LeverageLSTZapper': {'removeManagerReceiverOf'},
    'WETHZapper': {'removeManagerReceiverOf'},
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
    if contract == 'Governance':
        for companion in ['GovernanceStakingModule', 'GovernanceVotingModule', 'GovernanceActionsModule']:
            module_abi = json.loads((ROOT / 'build' / (companion + '.abi.json')).read_text())
            compiled += [e for e in module_abi if e['type'] in ('event', 'error')]
        for name in ['depositLQTYViaPermit', 'registerInitialInitiatives', 'multiDelegateCall']:
            entries = [e for e in reference if e.get('name') == name]
            assert entries and not any(e.get('name') == name for e in compiled)
            compiled += copy.deepcopy(entries)
        refinements.append('numeric selectors: permit overloads, initial registration and multicall use custom wire decoders; differential runtime validation is required separately')
        constructor = next(e for e in compiled if e['type'] == 'constructor')
        assert len(constructor['inputs']) == 10 and typ(constructor['inputs'][6]) == '(address[])'
        constructor['inputs'][6] = dict(type='address[]', name='initialInitiatives')
        reference_constructor = next(e for e in reference if e['type'] == 'constructor')
        assert len(reference_constructor['inputs']) == 7
        reference_constructor['inputs'] += [dict(type='address', internalType='address', name=n)
                                           for n in ['stakingModule', 'votingModule', 'actionsModule']]
        refinements.append('constructor: original arguments plus three fixed delegate modules; custom InitialAddresses decoder has flat address[] wire format')
    if contract == 'UserProxy':
        compiled.append(copy.deepcopy(next(e for e in reference if e.get('name') == 'stakeViaPermit')))
        refinements.append('stakeViaPermit: numeric selector preserves Solidity lazy calldata validation; wire signature and malformed fields covered by differential tests')
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
    if contract == 'RedemptionHelper':
        redeem_key = ('function', 'redeemCollateral(uint256,uint256,uint256,uint256[])')
        assert redeem_key not in {key(e) for e in compiled}
        compiled.append(copy.deepcopy(next(e for e in reference if key(e) == redeem_key)))
        refinements.append('redeemCollateral: numeric selector with runtime-tested Solidity memory-array decoder')
        constructor = next(e for e in compiled if e['type'] == 'constructor')
        assert [typ(f) for f in constructor['inputs']] == ['address', '(address[])']
        constructor['inputs'][1] = dict(type='address[]', name='branches')
        refinements.append('constructor: AddressMemoryArray explicitly decodes a flat address[] with eager allocation panic and address validation')
    if contract in {'LeverageWETHZapper', 'LeverageLSTZapper'}:
        module_abi = json.loads((ROOT / 'build' / (contract + 'Leverage.abi.json')).read_text())
        compiled += [e for e in module_abi if e['type'] in ('event', 'error')]
        refinements.append('constructor creates a fixed delegate companion with immutable branch configuration; original three constructor arguments and runtime selectors are preserved')
    normalized = copy.deepcopy(compiled)
    for entry in normalized:
        if contract == 'Governance' and entry['type'] == 'function':
            outputs = entry['outputs']
            if len(outputs) == 1 and outputs[0]['type'] == 'tuple':
                # All Governance return tuples are static, including nested state tuples.
                def static(field):
                    return all(static(c) for c in field['components']) if field['type'] == 'tuple' else field['type'] in ('uint256', 'uint8', 'address', 'bool')
                assert static(outputs[0])
                entry['outputs'] = outputs[0]['components']
                refinements.append(entry['name'] + ': outer static tuple has identical flat wire encoding')
        if contract == 'UniV4MerklRewards' and entry.get('name') in {'onRegisterInitiative', 'onUnregisterInitiative', 'onAfterAllocateLQTY', 'onClaimForInitiative'}:
            assert entry['stateMutability'] == ('view' if entry['name'] == 'onClaimForInitiative' else 'pure')
            entry['stateMutability'] = 'nonpayable'
            refinements.append(entry['name'] + ': no-op or authorization-only callback preserves nonpayable guard')
        if (contract == 'BribeInitiative' and entry.get('name') in {'onRegisterInitiative', 'onUnregisterInitiative', 'onClaimForInitiative'}) or (contract == 'CurveV2GaugeRewards' and entry.get('name') in {'onRegisterInitiative', 'onUnregisterInitiative'}):
            assert entry['stateMutability'] == 'view'
            entry['stateMutability'] = 'nonpayable'
            refinements.append(entry['name'] + ': authorization-only callback preserves nonpayable guard')
        if contract in {'WETHZapper', 'GasCompZapper'} and entry.get('name') in {'receiveFlashLoanOnOpenLeveragedTrove', 'receiveFlashLoanOnLeverUpTrove', 'receiveFlashLoanOnLeverDownTrove'}:
            assert entry['stateMutability'] == 'pure'
            entry['stateMutability'] = 'nonpayable'
            refinements.append(entry['name'] + ': pure implementation of the reference no-op callback; nonpayable value guard retained')
        if contract in {'UserProxy', 'WETHZapper', 'GasCompZapper', 'LeverageWETHZapper', 'LeverageLSTZapper'} and entry['type'] == 'fallback':
            assert entry['stateMutability'] == 'payable'
            entry['type'] = 'receive'
            refinements.append('receive: payable fallback accepts only empty calldata; non-empty unknown calldata reverts, matching Solidity receive-only behavior')
        if contract == 'RedemptionHelper' and entry.get('name') in {'simulateRedemption', 'truncateRedemption'}:
            outputs = entry['outputs']
            expected = ['tuple[]', 'uint256'] if entry['name'] == 'simulateRedemption' else ['uint256', 'uint256', 'tuple[]']
            if len(outputs) == 1 and outputs[0]['type'] == 'tuple':
                assert [c['type'] for c in outputs[0]['components']] == expected
                entry['outputs'] = outputs[0]['components']
            else:
                assert [o['type'] for o in outputs] == expected
            refinements.append(entry['name'] + ': explicit flat runtime return with dynamic array')
        if contract == 'MultiTroveGetter' and key(entry) == ('function', 'getDebtPerInterestRateAscending(uint256,uint256,uint256)'):
            outputs = entry['outputs']
            if len(outputs) == 1 and outputs[0]['type'] == 'tuple':
                assert [c['type'] for c in outputs[0]['components']] == ['tuple[]', 'uint256']
                entry['outputs'] = outputs[0]['components']
            else:
                assert [o['type'] for o in outputs] == ['tuple[]', 'uint256']
            refinements.append('getDebtPerInterestRateAscending: explicit flat dynamic-array and cursor runtime return')
        if contract == 'BoldToken' and key(entry) == ('function', 'eip712Domain()'):
            outputs = entry['outputs']
            if len(outputs) == 1 and outputs[0]['type'] == 'tuple':
                entry['outputs'] = outputs[0]['components']
            refinements.append('eip712Domain: explicit flat runtime return')
        operation, view_signatures = READ_ONLY_CAPABILITIES.get(contract, ('', set()))
        if key(entry)[0] == 'function' and key(entry)[1] in view_signatures:
            assert entry['stateMutability'] == 'nonpayable'
            entry['stateMutability'] = 'view'
            refinements.append(entry['name'] + ': read-only ' + operation + '; Fe capability conservatively implies nonpayable')
        if entry.get('name') in STATIC_TUPLE_OUTPUTS.get(contract, set()):
            outputs = entry['outputs']
            if len(outputs) == 1 and outputs[0]['type'] == 'tuple':
                assert all(c['type'] in ('uint256', 'uint128', 'uint64', 'uint8', 'address', 'bool') for c in outputs[0]['components'])
                entry['outputs'] = outputs[0]['components']
            else:
                assert all(o['type'] in ('uint256', 'uint128', 'uint64', 'uint8', 'address', 'bool') for o in outputs)
            refinements.append(entry['name'] + ': static tuple has identical flat runtime encoding')
    fe = {key(e): e for e in normalized}
    sol = {key(e): e for e in reference}
    missing = set(sol) - set(fe)
    extra = set(fe) - set(sol)
    assert missing <= DECLARATION_ONLY.get(contract, set()), (contract, 'missing ABI entries', missing)
    # Solidity omits its implicit standard errors from ABI metadata.
    assert extra <= {('error', 'Error(string)'), ('error', 'Panic(uint256)')}, (contract, 'extra ABI entries', extra)
    def flat(outputs):
        def is_static(f):
            if f['type'].startswith('tuple'):
                return all(is_static(c) for c in f.get('components', []))
            return f['type'] in ('uint256', 'uint128', 'uint64', 'uint8', 'address', 'bool', 'bytes1', 'bytes32') or (f['type'].startswith('bytes') and f['type'] not in ('bytes',)) 
        if len(outputs) == 1 and outputs[0].get('type') == 'tuple' and is_static(outputs[0]):
            return outputs[0].get('components', [])
        return outputs
    for k in sorted(set(sol) & set(fe)):
        x, y = fe[k], sol[k]
        assert [typ(f) for f in flat(x.get('outputs', []))] == [typ(f) for f in flat(y.get('outputs', []))], (contract, k, 'return shape')
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
for contract in ['LeverageWETHZapperLeverage', 'LeverageLSTZapperLeverage', 'MetadataGeometry', 'TroveOperations', 'TroveRedemptions', 'TroveLiquidations', 'BorrowerOpening', 'BorrowerAdjustments', 'BorrowerBatches', 'GovernanceStakingModule', 'GovernanceVotingModule', 'GovernanceActionsModule']:
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
