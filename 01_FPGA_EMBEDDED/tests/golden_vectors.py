"""Independent integer specification: reset dominates, count modulo 2**width."""
from pathlib import Path
import random


def generate(destination: Path) -> None:
    rng = random.Random(20261025)
    widths = (48, 48, 3)
    initial = (0, (1 << 48) - 5, 0)
    counts = list(initial)
    rows = []
    for cycle in range(5000):
        reset = int(cycle == 0 or rng.random() < 0.008)
        enable = int(rng.random() < 0.77)
        pulses = [0, 0, 0]
        for channel, width in enumerate(widths):
            if reset:
                counts[channel] = initial[channel]
            elif enable:
                total = counts[channel] + 1
                pulses[channel], counts[channel] = divmod(total, 2**width)
        rows.append(f"{reset} {enable} {counts[0]:012X} {pulses[0]} "
                    f"{counts[1]:012X} {pulses[1]} {counts[2]:X} {pulses[2]}\n")
    destination.write_text("".join(rows), encoding="ascii")


if __name__ == "__main__":
    generate(Path("golden.txt"))
