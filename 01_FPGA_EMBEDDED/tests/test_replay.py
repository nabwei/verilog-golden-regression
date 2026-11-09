"""Cross-domain trajectory reference is a closed-form circular arc."""
import csv
import io
import math
from pathlib import Path
import subprocess
import tempfile
import unittest

BUILD = Path(__file__).resolve().parents[1] / "build"


def execute(trace: str) -> subprocess.CompletedProcess:
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "trace.txt"
        path.write_text(trace, encoding="ascii")
        return subprocess.run([str(BUILD / "replay"), str(path)], capture_output=True,
                              text=True, timeout=10, check=False)


class CrossDomainTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.trace = (BUILD / "hdl_ticks.txt").read_text(encoding="ascii")

    def test_hdl_timestamps_match_analytic_trajectory_and_replay_exactly(self):
        run = execute(self.trace)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout, execute(self.trace).stdout)
        trajectory = list(csv.DictReader(io.StringIO(run.stdout)))
        self.assertEqual(len(trajectory), 101)
        for sample in trajectory:
            seconds = int(sample["sequence"]) / 100
            self.assertAlmostEqual(float(sample["x_m"]), 1.2 * math.sin(0.5 * seconds), places=12)
            self.assertAlmostEqual(float(sample["y_m"]), 1.2 * (1 - math.cos(0.5 * seconds)), places=12)
            self.assertAlmostEqual(float(sample["heading_rad"]), seconds / 2, places=12)

    def test_packet_loss_preserves_elapsed_time_and_endpoint(self):
        rows = self.trace.splitlines()
        sparse = "\n".join(row for index, row in enumerate(rows) if index % 3 != 1 or index == 100)
        dense_run, sparse_run = execute(self.trace), execute(sparse)
        self.assertEqual(sparse_run.returncode, 0, sparse_run.stderr)
        dense_last = list(csv.DictReader(io.StringIO(dense_run.stdout)))[-1]
        sparse_last = list(csv.DictReader(io.StringIO(sparse_run.stdout)))[-1]
        for column in ("x_m", "y_m", "heading_rad"):
            self.assertAlmostEqual(float(dense_last[column]), float(sparse_last[column]), places=12)

    def test_timestamp_delay_causes_expected_position_error(self):
        rows = self.trace.splitlines()
        delayed = [rows[0]]
        for row in rows[1:]:
            sequence, ticks = row.split()
            delayed.append(f"{sequence} {(int(ticks, 16) + 2) % 2**48:012X}")
        run = execute("\n".join(delayed))
        self.assertEqual(run.returncode, 0, run.stderr)
        endpoint = list(csv.DictReader(io.StringIO(run.stdout)))[-1]
        error = math.hypot(float(endpoint["x_m"]) - 1.2 * math.sin(0.5),
                           float(endpoint["y_m"]) - 1.2 * (1 - math.cos(0.5)))
        self.assertAlmostEqual(error, 2.4 * math.sin(0.0005), places=12)

    def test_duplicate_backwards_out_of_range_and_malformed_traces_fail(self):
        traces = ["0 1\n1 1", "0 2\n1 1", "0 0\n1 1000000000000",
                  "0 0\n1 nope", "0 0", "0 0\n0 1", "0 0\n1 1 extra",
                  "0 0\n-1 1", "0 0\n1 -1", "0 0\n1 1xyz"]
        for trace in traces:
            with self.subTest(trace=trace):
                run = execute(trace)
                self.assertNotEqual(run.returncode, 0)
                self.assertTrue(run.stderr.strip())

    def test_userspace_simulated_snapshot_crosses_low_word_wrap(self):
        run = subprocess.run([str(BUILD / "timing_read"), "--simulate"], capture_output=True,
                             text=True, timeout=10, check=False)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(int(run.stdout), 0x1234FFFFFFFF)


if __name__ == "__main__":
    unittest.main(verbosity=2)
