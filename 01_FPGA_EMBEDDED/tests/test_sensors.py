"""Analytic sensor reference independent of Project G's integration and ray marcher."""
import csv
import io
import math
from pathlib import Path
import subprocess
import tempfile
import unittest

BUILD = Path(__file__).resolve().parents[1] / "build"


def replay(rows):
    with tempfile.TemporaryDirectory() as temporary:
        path = Path(temporary) / "sensors.csv"
        with path.open("w", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
        return subprocess.run([str(BUILD / "sensor_cosim"), "replay", str(path)], capture_output=True, text=True, timeout=15)


class SensorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        generated = subprocess.run([str(BUILD / "sensor_cosim"), "emit", str(BUILD / "hdl_ticks.txt")],
                                   capture_output=True, text=True, check=True, timeout=15)
        cls.rows = list(csv.DictReader(io.StringIO(generated.stdout)))
        (BUILD / "sensor_messages.csv").write_text(generated.stdout)

    def test_sensor_payloads_match_closed_form_geometry_and_encoder_angles(self):
        for row in self.rows:
            time = int(row["sequence"]) / 100
            # v=.6 m/s, omega=.5 rad/s in a 10x10 m empty room; the front ray hits x=10.
            x = 1 + 1.2 * math.sin(0.5 * time)
            expected_range = (10 - x) / math.cos(0.5 * time)
            self.assertAlmostEqual(float(row["left_angle_rad"]), 10 * time, places=12)
            self.assertAlmostEqual(float(row["right_angle_rad"]), 14 * time, places=12)
            self.assertLessEqual(abs(float(row["front_range_m"]) - expected_range), 0.0021)
        first, second = replay(self.rows), replay(self.rows)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(first.stdout, second.stdout)
        (BUILD / "sensor_replay.csv").write_text(first.stdout)

    def test_packet_gaps_preserve_sensor_time_and_geometry(self):
        thinned = self.rows[::4]
        result = replay(thinned)
        self.assertEqual(result.returncode, 0, result.stderr)
        last = list(csv.DictReader(io.StringIO(result.stdout)))[-1]
        self.assertAlmostEqual(float(last["time_s"]), 1.0)

    def test_timestamp_and_sensor_corruption_are_detected_independently(self):
        for field, offset in [("ticks", 5), ("front_range_m", 0.2)]:
            with self.subTest(field=field):
                corrupted = [dict(row) for row in self.rows]
                value = int(corrupted[50][field]) if field == "ticks" else float(corrupted[50][field])
                corrupted[50][field] = str(value + offset)
                result = replay(corrupted)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("sensor/timestamp mismatch", result.stderr)

    def test_missing_sensor_file_reports_open_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "missing.csv"
            result = subprocess.run([str(BUILD / "sensor_cosim"), "replay", str(path)],
                                    capture_output=True, text=True, timeout=15)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cannot open sensor message file", result.stderr)


if __name__ == "__main__":
    unittest.main()
