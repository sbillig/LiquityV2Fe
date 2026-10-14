#!/usr/bin/env python3
"""Create isolated pinned reference/compiler checkouts and build the local Fe CLI."""
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / 'reference_manifest.json').read_text())

def run(*args, cwd=root):
    subprocess.run(args, cwd=cwd, check=True)

def clone_at(path, url, revision):
    if path.exists():
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    run('git', 'clone', url, str(path))
    run('git', 'checkout', '--detach', revision, cwd=path)

ref = root / 'reference/bold'
clone_at(ref, manifest['reference']['url'], manifest['reference']['revision'])
run('git', 'submodule', 'update', '--init', '--recursive',
    'contracts/lib/openzeppelin-contracts', 'contracts/lib/V2-gov', 'contracts/lib/Solady', cwd=ref)
run('python3', 'scripts/verify_reference.py')
compiler = root / 'toolchain/fe'
clone_at(compiler, manifest['compiler']['url'], manifest['compiler']['revision'])
run('python3', 'scripts/verify_compiler.py')
run('npm', 'ci', '--prefix', 'crates/tree-sitter-fe', cwd=compiler)
run('cargo', 'build', '--release', '-p', 'fe', '--locked', cwd=compiler)
