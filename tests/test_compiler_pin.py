"""Integration checks for the reproducible compiler gate."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CompilerPinTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'scripts').mkdir()
        shutil.copyfile(ROOT / 'scripts/verify_compiler.py', self.root / 'scripts/verify_compiler.py')
        self.compiler = self.root / 'toolchain/fe'
        self.compiler.mkdir(parents=True)
        self.git('init', '--quiet')
        (self.compiler / 'source.fe').write_text('// pinned compiler source\n')
        (self.compiler / '.gitignore').write_text('/target/\n')
        self.git('add', '.')
        self.git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '--quiet', '-m', 'Fixture')
        self.pin = {'revision': self.git('rev-parse', 'HEAD'), 'tree': self.git('rev-parse', 'HEAD^{tree}')}
        self.manifest = self.root / 'reference_manifest.json'
        self.write_pin()
        self.binary = self.compiler / 'target/release/fe'
        self.binary.parent.mkdir(parents=True)
        self.write_binary(self.pin['revision'][:9])

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.compiler), *args], text=True).strip()

    def write_pin(self):
        self.manifest.write_text(json.dumps({'compiler': self.pin}))

    def write_binary(self, revision):
        self.binary.write_text(f'#!/bin/sh\necho "fe 26.4.0 ({revision})"\n')
        self.binary.chmod(0o755)

    def verify(self):
        return subprocess.run([sys.executable, str(self.root / 'scripts/verify_compiler.py'), '--binary'], capture_output=True, text=True)

    def assert_rejected(self, reason):
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(reason, result.stderr)

    def test_accepts_clean_pin_and_matching_binary(self):
        self.assertEqual(self.verify().returncode, 0)

    def test_rejects_wrong_revision(self):
        self.pin['revision'] = '0' * 40
        self.write_pin()
        self.assert_rejected('Compiler revision differs')

    def test_rejects_wrong_source_tree(self):
        self.pin['tree'] = '0' * 40
        self.write_pin()
        self.assert_rejected('Compiler source tree differs')

    def test_rejects_modified_source(self):
        (self.compiler / 'source.fe').write_text('// changed compiler source\n')
        self.assert_rejected('uncommitted changes')

    def test_rejects_untracked_source(self):
        (self.compiler / 'extra.fe').write_text('// extra compiler source\n')
        self.assert_rejected('uncommitted changes')

    def test_rejects_stale_binary(self):
        self.write_binary('000000000')
        self.assert_rejected('Compiler binary differs')

    def test_rejects_binary_without_revision(self):
        self.binary.write_text('#!/bin/sh\necho "fe 26.4.0"\n')
        self.assert_rejected('Compiler binary differs')


if __name__ == '__main__':
    unittest.main()
