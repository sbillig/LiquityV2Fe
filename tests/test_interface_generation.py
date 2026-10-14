"""Regenerate the pinned bindings and compare them with the checked-in API."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class InterfaceGenerationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temporary = tempfile.TemporaryDirectory(prefix='liquity-interface-check-')
        cls.addClassCleanup(temporary.cleanup)
        cls.generated = Path(temporary.name)
        commands = [
            [sys.executable, str(ROOT / 'scripts/generate_interfaces.py'),
             '--repo', str(ROOT), '--output', str(cls.generated)],
            [sys.executable, str(ROOT / 'scripts/generate_interface_tests.py'),
             '--index', str(cls.generated / 'interface-index.json'),
             '--source-output', str(cls.generated / 'interfaces'),
             '--module-file', str(cls.generated / 'interfaces.fe'),
             '--test-output', str(cls.generated / 'tests')],
        ]
        for command in commands:
            result = subprocess.run(command, cwd=ROOT, text=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            if result.returncode:
                raise RuntimeError(result.stdout)

    def test_index_reproduces_committed_abi_inventory(self):
        self.assertEqual((self.generated / 'interface-index.json').read_bytes(),
                         (ROOT / 'interface-index.json').read_bytes())

    def test_bindings_reproduce_committed_files(self):
        generated = self.generated / 'interfaces'
        committed = ROOT / 'src/interfaces'
        self.assertEqual({p.name for p in generated.glob('*.fe')},
                         {p.name for p in committed.glob('*.fe')})
        for path in generated.glob('*.fe'):
            with self.subTest(module=path.name):
                self.assertEqual(path.read_bytes(), (committed / path.name).read_bytes())

    def test_exports_and_solidity_fixture_reproduce_committed_files(self):
        for generated, committed in (
            (self.generated / 'interfaces.fe', ROOT / 'src/interfaces.fe'),
            (self.generated / 'tests/InterfaceRecordParity.t.sol',
             ROOT / 'tests/InterfaceRecordParity.t.sol'),
        ):
            with self.subTest(path=committed.name):
                self.assertEqual(generated.read_bytes(), committed.read_bytes())


if __name__ == '__main__':
    unittest.main()
