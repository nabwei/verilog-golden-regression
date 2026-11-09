# VHDL timing, AXI-Lite and robot co-simulation extension

Projects A/B/C extend this repository alongside the existing Verilog regression.
The VHDL-2008 counter/AXI/UART code is independently specified; it is not a port
verified against confidential production RTL. No physical hardware validation is claimed.

From the repository root, on Ubuntu 24.04 with Python 3.12, GHDL 4 and g++:

```sh
python3 fetch_robot_dependency.py
python3 01_FPGA_EMBEDDED/run_tests.py
python3 01_FPGA_EMBEDDED/verify_reproducibility.py
```

The fetch step retrieves four exact source files from a pinned published revision of
`nabwei/engineering-portfolio`; SHA-256 mismatches fail. They are a build dependency,
not a second robot project. The manifest is `robot_dependency.json` at the repo root.
The original Verilog checks remain `python3 run_tests.py`.

The runner executes five VHDL testbenches, structural synthesis, C++ integration,
four deliberate mutations and independent sensor/replay checks. Reproduction compares
six output hashes in an isolated source copy. Logs are under `08_TEST_RESULTS/fpga/`.
The new root workflow `timing-extension.yml` executes these commands on GitHub.

See [SPECIFICATION.md](SPECIFICATION.md) for the actual interface and register map.
The snapshot interface is independently defined; authoritative legacy UART-v2
compatibility is not claimed. AXI simulation and simulated userspace reads are tested;
physical UIO/Zynq access, memory ordering, place-and-route and CDC remain unverified.
Co-simulation is one-way trace-driven software integration, not physical HIL.

The [portfolio validation summary](https://github.com/nabwei/engineering-portfolio/blob/main/docs/VALIDATION.md)
and [AI development disclosure](../docs/AI_DEVELOPMENT.md) explain scope and evidence.
