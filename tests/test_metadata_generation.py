"""Regenerate metadata fragments from the pinned Solidity renderer."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MetadataGenerationTests(unittest.TestCase):
    def test_generators_reproduce_committed_literals(self):
        with tempfile.TemporaryDirectory(prefix='liquity-metadata-check-') as directory:
            for name in ('metadata_literals', 'bauhaus'):
                with self.subTest(generator=name):
                    source = 'metadata_bauhaus' if name == 'bauhaus' else name
                    output = Path(directory) / (source + '.fe')
                    result = subprocess.run(
                        [sys.executable, str(ROOT / f'scripts/generate_{name}.py'),
                         '--output', str(output)], cwd=ROOT, text=True,
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                    )
                    self.assertEqual(result.returncode, 0, result.stdout)
                    self.assertEqual(output.read_bytes(),
                                     (ROOT / f'src/{source}.fe').read_bytes())


if __name__ == '__main__':
    unittest.main()
