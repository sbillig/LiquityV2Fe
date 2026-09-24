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
CONTRACTS = ['AddressesRegistry', 'GasPool', 'DefaultPool', 'CollSurplusPool', 'ActivePool', 'BoldToken']
DECLARATION_ONLY = {
    'ActivePool': {('event', 'ActivePoolBoldDebtUpdated(uint256)')},
    'BoldToken': {('event', 'EIP712DomainChanged()'),
                  ('error', 'StringTooLong(string)'), ('error', 'InvalidShortString()')},
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
    sol_path = ROOT / 'tests/out' / (contract + '.sol') / (contract + '.json')
    compiled = json.loads(fe_path.read_text())
    reference = json.loads(sol_path.read_text())['abi']
    normalized = copy.deepcopy(compiled)
    refinements = []
    for entry in normalized:
        if contract == 'BoldToken' and key(entry) == ('function', 'eip712Domain()'):
            outputs = entry['outputs']
            assert len(outputs) == 1 and outputs[0]['type'] == 'tuple'
            entry['outputs'] = outputs[0]['components']
            refinements.append('eip712Domain: explicit flat runtime return')
    fe = {key(e): e for e in normalized}
    sol = {key(e): e for e in reference}
    missing = set(sol) - set(fe)
    extra = set(fe) - set(sol)
    assert missing <= DECLARATION_ONLY.get(contract, set()), (contract, 'missing ABI entries', missing)
    assert extra <= {('error', 'Error(string)')}, (contract, 'extra ABI entries', extra)
    for k in set(sol) & set(fe):
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
    reports[contract] = {
        'compiler_abi_sha256': digest(fe_path), 'reference_artifact_sha256': digest(sol_path),
        'protocol_abi_sha256': digest(target), 'metadata_refinements': refinements,
        'declaration_only': sorted(map(list, missing)),
        'compiler_standard_errors': sorted(map(list, extra)),
        'function_count': sum(e['type'] == 'function' for e in reference),
    }
(ROOT / 'tests/results/abi-audit.json').write_text(json.dumps(reports, indent=2) + '\n')
print('ABI shape audit passed for ' + ', '.join(CONTRACTS))
