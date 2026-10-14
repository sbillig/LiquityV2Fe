#!/usr/bin/env python3
"""Reject compiler revision, source, and release-binary drift from the MVS pin."""
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
expected = json.loads((root / 'reference_manifest.json').read_text())['compiler']
compiler = root / 'toolchain/fe'

def git(*args):
    return subprocess.check_output(['git', '-C', str(compiler), *args], text=True).strip()

if git('rev-parse', 'HEAD') != expected['revision']:
    raise SystemExit('Compiler revision differs from pinned manifest')
if git('rev-parse', 'HEAD^{tree}') != expected['tree']:
    raise SystemExit('Compiler source tree differs from pinned manifest')
if git('status', '--porcelain'):
    raise SystemExit('Compiler checkout has uncommitted changes')
if '--binary' in sys.argv:
    version = subprocess.check_output([str(compiler / 'target/release/fe'), '--version'], text=True).strip()
    commit = version.rsplit('(', 1)[-1].removesuffix(')')
    if len(commit) < 7 or not expected['revision'].startswith(commit):
        raise SystemExit(f'Compiler binary differs from pinned manifest: {version}')
print(f"Verified compiler at {expected['revision']}")
