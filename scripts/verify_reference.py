#!/usr/bin/env python3
"""Reject drift in the pinned Solidity sources used as differential oracles."""
import hashlib
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / 'reference_manifest.json').read_text())
reference = root / 'reference/bold'
revision = subprocess.check_output(['git', '-C', str(reference), 'rev-parse', 'HEAD'], text=True).strip()
if revision != manifest['reference']['revision']:
    raise SystemExit('Reference revision differs from pinned manifest')
actual = {str(p.relative_to(reference)): hashlib.sha256(p.read_bytes()).hexdigest()
          for p in (reference / 'contracts/src').rglob('*.sol')}
if actual != manifest['sources']:
    raise SystemExit('Reference source inventory or contents differ from pinned manifest')
print(f'Verified {len(actual)} reference source files at {revision}')

for relative, expected in manifest.get('dependencies', {}).items():
    repo = reference / relative
    revision = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip()
    if revision != expected['revision']:
        raise SystemExit(f'Dependency revision drift: {relative}')
    source_dir = expected['source_directory']
    subprocess.run(['git', '-C', str(repo), 'diff', '--quiet', 'HEAD', '--', source_dir], check=True)
    tracked = subprocess.check_output(['git', '-C', str(repo), 'ls-tree', '-r', '--name-only', 'HEAD', '--', source_dir], text=True).splitlines()
    tracked = {x for x in tracked if x.endswith('.sol')}
    present = {str(p.relative_to(repo)) for p in (repo / source_dir).rglob('*.sol')}
    if tracked != present:
        raise SystemExit(f'Dependency Solidity source inventory drift: {relative}')
print(f"Verified {len(manifest.get('dependencies', {}))} pinned dependency source trees")
