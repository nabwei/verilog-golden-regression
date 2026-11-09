"""Run real HDL simulations and C++ integration; persist commands and exit status."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import uuid
from datetime import datetime, timezone

from tests.golden_vectors import generate

ROOT = Path(__file__).resolve().parent
BUILD = ROOT / "build"
EVIDENCE_ROOT = ROOT.parent / "08_TEST_RESULTS" / "fpga"
EVIDENCE = EVIDENCE_ROOT / "runs" / (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ") + "-" + uuid.uuid4().hex[:8])
ROBOT = ROOT.parent / "02_ROBOTICS_NAVIGATION" / "robot_core"


def invoke(command: list[str], log, records: list[dict]) -> None:
    log.write("$ " + " ".join(command) + "\n")
    log.flush()
    run = subprocess.run(command, cwd=BUILD, capture_output=True, text=True, timeout=60)
    log.write(run.stdout + run.stderr + f"exit_code={run.returncode}\n")
    log.flush()
    records.append({"command": command, "status": "PASS" if run.returncode == 0 else "FAIL",
                    "exit_code": run.returncode})
    if run.returncode:
        raise RuntimeError(f"failed command: {command}; see {EVIDENCE / 'execution.log'}")


def simulate(log, records: list[dict]) -> None:
    sources = [ROOT / "rtl" / filename for filename in
               ("tick_counter.vhd", "snapshot_stream.vhd", "uart_tx.vhd", "snapshot_uart.vhd", "axi_timing.vhd")]
    sources += sorted((ROOT / "tests").glob("tb_*.vhd"))
    invoke(["ghdl", "-a", "--std=08", "-Werror", *map(str, sources)], log, records)
    for entity in ("tb_counter", "tb_snapshot", "tb_uart", "tb_axi", "tb_trace"):
        invoke(["ghdl", "-e", "--std=08", entity], log, records)
        invoke(["ghdl", "-r", "--std=08", entity, "--assert-level=error"], log, records)
    for entity in ("tick_counter", "snapshot_stream", "uart_tx", "snapshot_uart", "axi_timing"):
        invoke(["ghdl", "--synth", "--std=08", entity], log, records)


def compile_cpp(log, records: list[dict]) -> None:
    for executable in ("replay", "timing_read", "sensor_cosim"):
        shared_sources = (["-I", str(ROBOT / "include"), str(ROBOT / "src" / "kinematics.cpp")]
                          if executable in ("replay", "sensor_cosim") else [])
        if executable == "sensor_cosim":
            shared_sources.extend(str(ROBOT / "src" / name) for name in ("world.cpp", "lidar.cpp"))
        invoke(["g++", "-std=c++17", "-O2", "-Wall", "-Wextra", "-Wpedantic", "-Werror",
                str(ROOT / "cpp" / (executable + ".cpp")), *shared_sources, "-o", str(BUILD / executable)], log, records)
    invoke(["g++", "-std=c++17", "-Wall", "-Wextra", "-Wpedantic", "-Werror",
            "-fsanitize=undefined", "-fno-sanitize-recover=all",
            str(ROOT / "cpp" / "test_timing.cpp"), "-o", str(BUILD / "test_timing")], log, records)
    invoke([str(BUILD / "test_timing")], log, records)
    invoke([sys.executable, str(ROOT / "tests" / "test_replay.py")], log, records)
    invoke([sys.executable, str(ROOT / "tests" / "test_sensors.py")], log, records)
    invoke([sys.executable, str(ROOT / "tests" / "test_evidence.py")], log, records)


COUNTER_MESSAGES = ("counter golden mismatch", "rollover pulse mismatch")
# One record per deliberate RTL mutation: the mutated file, a needle that must occur exactly once, its replacement,
# the sources analysed before and after the mutant (VHDL analysis order matters), the bench entity, and the
# assertion messages that count as detection. Compile errors or timeouts never count as a killed mutant.
MUTATIONS = (
    {"name": "increment_by_two", "source": "rtl/tick_counter.vhd",
     "needle": "count <= count + 1;", "replacement": "count <= count + 2;",
     "before": (), "after": ("tests/tb_counter.vhd",), "entity": "tb_counter", "messages": COUNTER_MESSAGES},
    {"name": "reset_loses_priority", "source": "rtl/tick_counter.vhd",
     "needle": "if reset = '1' then", "replacement": "if reset = '1' and enable = '0' then",
     "before": (), "after": ("tests/tb_counter.vhd",), "entity": "tb_counter", "messages": COUNTER_MESSAGES},
    {"name": "sticky_rollover", "source": "rtl/tick_counter.vhd",
     "needle": "rollover <= '0';", "replacement": "if enable = '1' or reset = '1' then rollover <= '0'; end if;",
     "before": (), "after": ("tests/tb_counter.vhd",), "entity": "tb_counter", "messages": COUNTER_MESSAGES},
    # Removes the reset-branch abort of uart_tx. The '0' in the needle distinguishes it from the start-of-frame
    # line "active <= '1'; bit_index <= 0; phase <= 0;". tb_uart asserts reset while a '0' data bit is on the
    # wire, so the un-aborted frame keeps driving '0' and the abort / idle-window assertions must fire.
    {"name": "abort_omitted", "source": "rtl/uart_tx.vhd",
     "needle": "active <= '0'; bit_index <= 0; phase <= 0;", "replacement": "null;",
     "before": ("rtl/snapshot_stream.vhd",), "after": ("rtl/snapshot_uart.vhd", "tests/tb_uart.vhd"),
     "entity": "tb_uart",
     "messages": ("UART reset did not abort transmission",
                  "UART wire not idle-high throughout the post-reset idle window")},
)


def mutation_checks(log, records: list[dict]) -> None:
    for mutation in MUTATIONS:
        name = mutation["name"]
        source = ROOT / mutation["source"]
        original = source.read_text(encoding="utf-8")
        if original.count(mutation["needle"]) != 1:
            raise RuntimeError(f"mutation location changed: {name}")
        directory = BUILD / name
        directory.mkdir(exist_ok=True)
        mutant = directory / source.name
        mutant.write_text(original.replace(mutation["needle"], mutation["replacement"]), encoding="utf-8")
        sources = [*(ROOT / path for path in mutation["before"]), mutant,
                   *(ROOT / path for path in mutation["after"])]
        compile_command = ["ghdl", "-a", "--std=08", f"--workdir={directory}", *map(str, sources)]
        invoke(compile_command, log, records)
        command = ["ghdl", "-r", "--std=08", f"--workdir={directory}", mutation["entity"], "--assert-level=error"]
        run = subprocess.run(command, cwd=BUILD, capture_output=True, text=True, timeout=30)
        detected = run.returncode != 0 and any(message in run.stdout for message in mutation["messages"])
        log.write(f"$ {' '.join(command)}\n{run.stdout}{run.stderr}expected_failure={detected}\n")
        records.append({"mutation": name, "command": command, "exit_code": run.returncode,
                        "expected_failure": True, "status": "PASS" if detected else "FAIL"})
        if not detected:
            raise RuntimeError(f"mutation not detected by bench assertions: {name}")


def write_trajectory() -> None:
    run = subprocess.run([str(BUILD / "replay"), str(BUILD / "hdl_ticks.txt")],
                         capture_output=True, text=True, check=True, timeout=10)
    (EVIDENCE / "trajectory.csv").write_text(run.stdout, encoding="utf-8")
    import csv
    import io
    rows = list(csv.DictReader(io.StringIO(run.stdout)))
    points = " ".join(f"{70 + 650 * float(row['x_m']):.2f},{400 - 650 * float(row['y_m']):.2f}" for row in rows)
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="640" height="480" viewBox="0 0 640 480">'
           '<rect width="640" height="480" fill="#f6f8fb"/>'
           '<text x="35" y="40" font-size="22">HDL timestamp → differential-drive replay</text>'
           '<text x="35" y="70" font-size="15">Synthetic, 1 kHz tick, 48-bit rollover, 1 second</text>'
           '<path d="M70 150 V400 H530" fill="none" stroke="#444"/>'
           f'<polyline points="{points}" fill="none" stroke="#1672b8" stroke-width="4"/>'
           '<text x="470" y="430">x (m)</text><text x="20" y="160">y (m)</text>'
           '<text x="60" y="425">0</text><text x="385" y="425">0.5</text>'
           '<text x="28" y="270">0.2</text></svg>')
    (EVIDENCE / "trajectory.svg").write_text(svg, encoding="utf-8")


def main() -> None:
    EVIDENCE.mkdir(parents=True, exist_ok=False)
    BUILD.mkdir(exist_ok=True)
    missing = [name for name in ("ghdl", "g++") if shutil.which(name) is None]
    if missing:
        raise SystemExit("BLOCKED: missing " + ", ".join(missing) + "; use Linux/WSL with trusted packages")
    generate(BUILD / "golden.txt")
    records = []
    try:
        with (EVIDENCE / "execution.log").open("w", encoding="utf-8") as log:
            for command in (["ghdl", "--version"], ["g++", "--version"], [sys.executable, "--version"]):
                invoke(command, log, records)
            simulate(log, records)
            mutation_checks(log, records)
            compile_cpp(log, records)
        write_trajectory()
        for filename in ("hdl_ticks.txt", "golden.txt", "sensor_messages.csv", "sensor_replay.csv"):
            shutil.copyfile(BUILD / filename, EVIDENCE / filename)
    finally:
        hashes = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in sorted(ROOT.rglob("*")) if path.is_file() and
                  "build" not in path.parts and "__pycache__" not in path.parts}
        for relative in ("include/robot/core.hpp", "src/kinematics.cpp", "src/world.cpp", "src/lidar.cpp"):
            hashes[f"../02_ROBOTICS_NAVIGATION/robot_core/{relative}"] = hashlib.sha256(
                (ROBOT / relative).read_bytes()).hexdigest()
        (EVIDENCE / "results.json").write_text(json.dumps({"utc": datetime.now(timezone.utc).isoformat(),
            "commands": records, "source_sha256": hashes}, indent=2), encoding="utf-8")
    print(f"PASS: HDL, synthesis checks, C++ build and cross-domain tests; evidence: {EVIDENCE}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="new evidence directory; an existing path is never overwritten")
    options = parser.parse_args()
    if options.output is not None:
        EVIDENCE = options.output.resolve()
    main()
