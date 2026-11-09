"""Rebuild an isolated source copy; preserve both original and reproduction evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
import uuid

ROOT = Path(__file__).resolve().parent
EVIDENCE_ROOT = ROOT.parent / "08_TEST_RESULTS" / "fpga"
ARTIFACTS = ("golden.txt", "hdl_ticks.txt", "trajectory.csv", "trajectory.svg", "sensor_messages.csv", "sensor_replay.csv")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def latest_run() -> Path:
    candidates = sorted(path for path in (EVIDENCE_ROOT / "runs").glob("*") if path.is_dir())
    if not candidates:
        raise ValueError("no default FPGA run exists; run run_tests.py or provide --source-run")
    return candidates[-1]


def main(source_run: Path, output: Path) -> None:
    source_run = source_run.resolve()
    output.mkdir(parents=True, exist_ok=False)
    report = {"status": "FAIL", "source_run": str(source_run)}
    try:
        original = json.loads((source_run / "results.json").read_text(encoding="utf-8"))
        if not original["commands"] or any(record["status"] != "PASS" for record in original["commands"]):
            raise ValueError("source run has missing or failed command acceptance")
        with tempfile.TemporaryDirectory(prefix="portfolio-fpga-repro-") as temporary:
            project = Path(temporary) / "project"
            shutil.copytree(ROOT, project, ignore=shutil.ignore_patterns("build", "__pycache__"))
            robot_relative = Path("02_ROBOTICS_NAVIGATION/robot_core")
            for relative in ("include/robot/core.hpp", "src/kinematics.cpp", "src/world.cpp", "src/lidar.cpp"):
                destination = project.parent / robot_relative / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT.parent / robot_relative / relative, destination)
            reproduced = output.resolve() / "rebuilt_run"
            run = subprocess.run([sys.executable, str(project / "run_tests.py"), "--output", str(reproduced)],
                                 cwd=project, capture_output=True, text=True, timeout=120)
            (output / "reproduction.log").write_text(run.stdout + run.stderr, encoding="utf-8")
            if run.returncode:
                raise RuntimeError("isolated reproduction failed; see reproduction.log")
            rebuilt = json.loads((reproduced / "results.json").read_text(encoding="utf-8"))
            if original["source_sha256"] != rebuilt["source_sha256"]:
                raise ValueError("source changed since recorded run; produce a new source run")
            comparisons = {name: {"original": digest(source_run / name), "reproduced": digest(reproduced / name)}
                           for name in ARTIFACTS}
            report["sha256"] = comparisons
            if not all(value["original"] == value["reproduced"] for value in comparisons.values()):
                raise RuntimeError("deterministic output mismatch")
            report["status"] = "PASS"
    except Exception as error:
        report["error"] = str(error)
        raise
    finally:
        (output / "reproduction.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"PASS isolated source rebuild and six deterministic artifact hashes; evidence: {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-run", type=Path, help="recorded run; default newest directory under fpga/runs, even if failed")
    parser.add_argument("--output", type=Path, help="new reproduction evidence directory; never overwritten")
    options = parser.parse_args()
    output = options.output or EVIDENCE_ROOT / "reproductions" / (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ") + "-" + uuid.uuid4().hex[:8])
    main(options.source_run or latest_run(), output)
