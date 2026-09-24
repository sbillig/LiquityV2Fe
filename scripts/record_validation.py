#!/usr/bin/env python3
"""Record hashes for a completed scripts/test.sh run without rerunning tests.

Run immediately after the suite, before changing any source or test files.
Usage: python3 scripts/record_validation.py tests/results/checkpoint.log
"""
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
log = ROOT / sys.argv[1]
content = log.read_text()
fe = re.search(r'test result: ok\. (\d+) passed; 0 failed', content)
evm = re.search(r'Ran \d+ test suites .*?: (\d+) tests passed, 0 failed, 0 skipped', content)
assert fe and evm and 'ABI shape audit passed for ' in content, 'Incomplete or failing validation log'
manifest = json.loads((ROOT / 'reference_manifest.json').read_text())

def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT / 'toolchain/fe'), *args], text=True).strip()

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def hashes(paths):
    return {str(p.relative_to(ROOT)): digest(p) for p in sorted(paths)}

assert not git('status', '--porcelain'), 'Compiler checkout has uncommitted changes'
assert git('rev-parse', 'HEAD^{tree}') == manifest['compiler']['integration_tree'], 'Compiler source tree differs from manifest'
for revision in [manifest['compiler']['upstream_master']] + [f['revision'] for f in manifest['compiler']['fixes']]:
    subprocess.run(['git', '-C', str(ROOT / 'toolchain/fe'), 'merge-base', '--is-ancestor', revision, 'HEAD'], check=True)
report = {
    'validated_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'command': './scripts/test.sh',
    'result': 'passed',
    'fe_unit_tests': int(fe[1]),
    'evm_tests': int(evm[1]),
    'fuzz_runs_per_test': 1024,
    'cached_fuzz_regressions_also_run': True,
    'compiler_revision': git('rev-parse', 'HEAD'),
    'compiler_tree': git('rev-parse', 'HEAD^{tree}'),
    'upstream_master': manifest['compiler']['upstream_master'],
    'compiler_binary_sha256': digest(ROOT / 'toolchain/fe/target/release/fe'),
    'compiler_dirty': '',
    'sources_sha256': hashes((ROOT / 'src').rglob('*.fe')),
    'configuration_sha256': hashes(ROOT / name for name in ['fe.toml', 'foundry.toml', 'remappings.txt', 'interface-index.json']),
    'deployment_sources_sha256': hashes(list((ROOT / 'tools/local_demo').glob('*.py')) + list((ROOT / 'tools/local_demo/src').glob('*.sol')) + [ROOT / 'tools/local_demo/foundry.toml']),
    'tests_sha256': hashes((ROOT / 'tests').glob('*.sol')),
    'scripts_sha256': hashes(p for p in (ROOT / 'scripts').iterdir() if p.is_file()),
    # Isolated experiments under build/*-validation are outside this suite.
    'artifacts_sha256': hashes([p for p in (ROOT / 'build').iterdir() if p.is_file()] +
                              [p for p in (ROOT / 'build/protocol').rglob('*') if p.is_file()]),
    'log_sha256': digest(log),
    'reference_manifest_sha256': digest(ROOT / 'reference_manifest.json'),
}
log.with_suffix('.json').write_text(json.dumps(report, indent=2) + '\n')
print(f'Recorded {report["evm_tests"]} EVM tests and {report["fe_unit_tests"]} Fe tests in {log.with_suffix(".json").relative_to(ROOT)}')
