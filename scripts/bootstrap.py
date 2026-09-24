#!/usr/bin/env python3
"""Create isolated pinned reference/compiler checkouts and build the local Fe CLI."""
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / 'reference_manifest.json').read_text())

def run(*args, cwd=root):
    subprocess.run(args, cwd=cwd, check=True)

def clone_at(path, url, revision, branch=None):
    if path.exists():
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    run('git', 'clone', url, str(path))
    if branch:
        run('git', 'switch', '-c', branch, revision, cwd=path)
    else:
        run('git', 'checkout', '--detach', revision, cwd=path)
    return True

ref = root / 'reference/bold'
clone_at(ref, manifest['reference']['url'], manifest['reference']['revision'])
run('git', 'submodule', 'update', '--init', '--recursive',
    'contracts/lib/openzeppelin-contracts', 'contracts/lib/V2-gov', 'contracts/lib/Solady', cwd=ref)
run('python3', 'scripts/verify_reference.py')
compiler = root / 'toolchain/fe'
if clone_at(compiler, manifest['compiler']['url'], manifest['compiler']['upstream_master'], 'liquity-v2-integration'):
    run('git', 'remote', 'rename', 'origin', 'upstream', cwd=compiler)
    for fix in manifest['compiler']['fixes']:
        run('git', 'fetch', 'upstream', fix['revision'], cwd=compiler)
        run('git', 'branch', fix['branch'], fix['revision'], cwd=compiler)
        run('git', 'merge', '--no-ff', '--no-edit', fix['branch'], cwd=compiler)
# Local merge commit IDs include local timestamps; pin the complete source tree
# as well as every input commit so a fresh checkout can reproduce the build.
actual_tree = subprocess.check_output(['git', 'rev-parse', 'HEAD^{tree}'], cwd=compiler, text=True).strip()
if actual_tree != manifest['compiler']['integration_tree']:
    raise SystemExit('Compiler source tree differs from the pinned integration')
for revision in [manifest['compiler']['upstream_master']] + [f['revision'] for f in manifest['compiler']['fixes']]:
    run('git', 'merge-base', '--is-ancestor', revision, 'HEAD', cwd=compiler)
run('npm', 'ci', '--prefix', 'crates/tree-sitter-fe', cwd=compiler)
run('cargo', 'build', '--release', '-p', 'fe', '--locked', cwd=compiler)
