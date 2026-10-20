import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent


def simulate(width, mutation):
    executable = ROOT / "build" / f"bars-{width}-{mutation}.vvp"
    command = [os.environ.get("IVERILOG", "iverilog")]
    if os.environ.get("IVERILOG_BASE"):
        command.extend(["-B", os.environ["IVERILOG_BASE"]])
    command.extend([
        "-g2012", "-Wall", "-s", "compare_patterns",
        f"-Pcompare_patterns.BAR_WIDTH={width}",
        f"-Pcompare_patterns.MUTATION={mutation}", "-o", str(executable),
        "rtl/pattern_old.v", "rtl/pattern_new.v", "tb/compare_patterns.v",
    ])
    subprocess.run(command, cwd=ROOT, check=True, timeout=30)
    return subprocess.run(
        [os.environ.get("VVP", "vvp"), str(executable)], cwd=ROOT,
        text=True, capture_output=True, timeout=10,
    )


def main():
    (ROOT / "build").mkdir(exist_ok=True)
    for width in (1, 4, 7):
        for mutation in range(4):
            simulation = simulate(width, mutation)
            print(f"width={width} mutation={mutation}: {simulation.stdout.strip()}")
            if mutation == 0:
                passed = simulation.returncode == 0 and "PASS cycles=180" in simulation.stdout
            else:
                passed = simulation.returncode != 0 and "MISMATCH cycle=" in simulation.stdout
            if not passed:
                raise RuntimeError(f"Unexpected simulation outcome: {simulation.stderr}")
    print("PASS: 3 equivalence runs; all 9 mutation runs detected their first mismatch")


if __name__ == "__main__":
    main()
