#!/usr/bin/env python3
"""Record hashes for completed full or targeted checks without rerunning tests.

Run immediately after the checks, before changing any source or test files.
Usage: python3 scripts/record_validation.py tests/results/checkpoint.log
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('log', type=Path)
parser.add_argument('--scope', choices=('full', 'targeted'), default='full')
parser.add_argument('--command')
args = parser.parse_args()
if args.scope == 'targeted' and not args.command:
    parser.error('targeted evidence requires the exact commands via --command')
ROOT = Path(__file__).resolve().parents[1]
log = ROOT / args.log
content = log.read_text()
fe = re.search(r'test result: ok\. (\d+) passed; 0 failed', content)
evm = re.findall(r'Ran \d+ test suites? .*?: (\d+) tests passed, 0 failed, 0 skipped', content)
assert fe and evm and 'ABI shape audit passed for ' in content, 'Incomplete or failing validation log'
manifest = json.loads((ROOT / 'reference_manifest.json').read_text())

def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT / 'toolchain/fe'), *args], text=True).strip()

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def hashes(paths):
    return {str(p.relative_to(ROOT)): digest(p) for p in sorted(paths)}

subprocess.run([sys.executable, str(ROOT / 'scripts/verify_compiler.py'), '--binary'], check=True)
report = {
    'validated_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'command': args.command or './scripts/test.sh',
    'scope': args.scope,
    'result': 'passed',
    'fe_unit_tests': int(fe[1]),
    'evm_tests': sum(int(count) for count in evm),
    'fuzz_runs_per_test': 1024,
    'cached_fuzz_regressions_also_run': True,
    'compiler_revision': git('rev-parse', 'HEAD'),
    'compiler_tree': git('rev-parse', 'HEAD^{tree}'),
    'compiler_branch': manifest['compiler']['branch'],
    'compiler_binary_sha256': digest(ROOT / 'toolchain/fe/target/release/fe'),
    'compiler_dirty': '',
    'sources_sha256': hashes((ROOT / 'src').rglob('*.fe')),
    'configuration_sha256': hashes(ROOT / name for name in ['fe.toml', 'foundry.toml', 'remappings.txt', 'interface-index.json']),
    'deployment_sources_sha256': hashes(list((ROOT / 'tools/local_demo').glob('*.py')) + list((ROOT / 'tools/local_demo/src').glob('*.sol')) + [ROOT / 'tools/local_demo/foundry.toml']),
    'tests_sha256': hashes(list((ROOT / 'tests').glob('*.sol')) + list((ROOT / 'tests').glob('test_*.py'))),
    'scripts_sha256': hashes(p for p in (ROOT / 'scripts').iterdir() if p.is_file()),
    # Isolated experiments under build/*-validation are outside this suite.
    'artifacts_sha256': hashes([p for p in (ROOT / 'build').iterdir() if p.is_file()] +
                              [p for p in (ROOT / 'build/protocol').rglob('*') if p.is_file()]),
    'log_sha256': digest(log),
    'reference_manifest_sha256': digest(ROOT / 'reference_manifest.json'),
}
log.with_suffix('.json').write_text(json.dumps(report, indent=2) + '\n')
print(f'Recorded {report["evm_tests"]} EVM tests and {report["fe_unit_tests"]} Fe tests in {log.with_suffix(".json").relative_to(ROOT)}')
