"""Evidence CLI regression: rejected reruns must leave previous bytes intact."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class EvidenceTests(unittest.TestCase):
    def test_existing_output_is_rejected_without_overwriting_evidence(self):
        for runner in ("run_tests.py", "verify_reproducibility.py"):
            with self.subTest(runner=runner), tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "saved"
                output.mkdir()
                (output / "results.json").write_bytes(b"preserved historical result\n")
                command = [sys.executable, str(ROOT / runner), "--output", str(output)]
                if runner == "verify_reproducibility.py":
                    command.extend(["--source-run", str(output)])
                completed = subprocess.run(command, capture_output=True, text=True, timeout=10)
                self.assertNotEqual(completed.returncode, 0)
                self.assertIn("FileExistsError", completed.stderr)
                self.assertEqual({path.name: path.read_bytes() for path in output.iterdir()},
                                 {"results.json": b"preserved historical result\n"})


if __name__ == "__main__":
    unittest.main()
