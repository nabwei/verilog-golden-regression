# Review handoff: A/B/C

Review package: `SPECIFICATION.md`, `rtl/`, `cpp/`, `tests/`, `run_tests.py`, and `../08_TEST_RESULTS/fpga/`. These files contain actual source and executed evidence; reading this note alone is not a technical review.

## Author's guard pass

Production review checked reset priority, modulo arithmetic, snapshot stability, independent AXI write channels, read/write backpressure, reset cancellation, byte strobes and unsupported addresses. The replay uses checked modulo timestamps and a finite-domain kinematics contract. A guard pass caught permissive unsigned parsing (`-1` could otherwise be accepted as an unsigned sequence); parsing now uses `std::from_chars` with complete-token checks and corresponding failure cases. Elapsed tick accumulation also rejects uint64 overflow.

Test review checked that real GHDL RTL, real compiled C++ and independent analytic references are exercised; no internal mocks replace the system under test. Three modified RTL copies must compile and fail specifically at golden assertions. Compile errors or timeouts do not count as killed mutations. The standalone C++ boundary executable runs with UndefinedBehaviorSanitizer. Five Python integration tests cover independent scenarios; malformed-input variants are grouped.

Documentation review checked named files and commands against the implementation and executed the reproduction commands. Hardware, v2 compatibility, formal equivalence and live lockstep claims are explicitly excluded. Source-copy reproduction produced byte-identical golden vectors, HDL traces, trajectory CSV and SVG.

This is a Codex author review, not independent Claude review. No external reviewer approval is invented.

## Questions for an independent reviewer

1. Can any legal AW/W ordering lose or duplicate a write in `axi_timing`? Are response payloads stable for arbitrary backpressure?
2. Does the low-read snapshot contract remain consistent if another client reads low before the first client's high read? The documented answer requires external serialization; confirm it is explicit in usage.
3. Are reset effects on outstanding read/write operations and counter state consistent with the synchronous reset specification?
4. Does the golden reference verify the actual 48-bit rollover without forcing private internal signals?
5. Are the scalar clock assumptions and half-range timestamp ambiguity adequately stated?
6. Are UIO memory attributes/barriers left honestly unverified on target hardware?

## Required remaining validation

- GitHub Actions execution: NOT RUN; a prepared workflow is not a remote CI result.
- Actual Linux UIO device and optional Zynq: BLOCKED by compatible hardware and deployment configuration.
- UART v2 compatibility or equivalence to prior tick RTL: BLOCKED until the authoritative source/specification is available and publication scope is cleared.
- Independent Claude review: controlled by the master model-selection status, not performed by this workstream.
- FPGA board timing/CDC/physical UART: NOT RUN; outside the verified single-clock simulation scope.

## Addendum 2026-10-28 (committee findings C-7, C-12, C-20)

- The "three modified RTL copies" above are now four: `run_tests.py` adds the `uart_tx` mutant `abort_omitted` (reset-branch abort replaced by `null;`), which must fail `tb_uart` with the abort or idle-window message. The earlier abort assertion in `tb_uart.vhd` was vacuous for byte 0x54 (reset landed on d2 = '1'); reset is now applied while d1 = '0' is on the wire and an independent monitor samples the wire every clock for ten bit-times after reset release.
The current regression and isolated reproduction receipts are linked from the A/B/C validation map in `../00_MASTER_CONTROL/FULL_ACCEPTANCE_MATRIX.md`. Compare their exact source hashes. Named older runs are historical evidence only.
- The CI workflow now lives at the repository root (`../.github/workflows/fpga.yml`); the project-local copy is an inert placeholder. GitHub Actions execution remains NOT RUN.
