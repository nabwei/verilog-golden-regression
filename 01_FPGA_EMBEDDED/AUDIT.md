# FPGA source audit and reuse decisions

Audit performed 2026-10-25 before implementation.

| Scope | Actual files examined | Decision |
|---|---|---|
| Public `nabwei/verilog-golden-regression` | `rtl/pattern_new.v`, `tb/compare_patterns.v`, `run_tests.py`; commit `a2e11428e12591a121bdc23162acf8e2160d35a3` | EXISTING: retain existing gray-bar regression; do not create another copy. EXTENSION: apply independently specified golden vectors to timing RTL. |
| Private reference checkout | A private reference checkout was inspected read-only before implementation; its identity, file paths and revision are withheld from this public tree | EXISTING, private reference only; nothing was copied or modified; no equivalence or compatibility with it is claimed. Repository hardware rules read and respected. |
| User's 48-bit counter and UART v2 | The authoritative legacy 48-bit counter / UART v2 source was not available in the inspected material | BLOCKED: legacy equivalence verification is BLOCKED until the authoritative version is available. This observation does not establish absence from all other user work. |
| A: VHDL counter, snapshot adapter and golden harness | Independent contract in `SPECIFICATION.md` | EXTENSION: adds VHDL implementation and regression coverage to portfolio timing concepts. NEW source from mathematical spec; no production-equivalence claim. |
| B: AXI-Lite peripheral and userspace example | No AXI-Lite implementation in the examined paths | NEW extension, with independent channels and captured counter reads. |
| C: HDL-to-C++ robot timing replay | No such integration in the examined paths | NEW software co-simulation integration. |

The public gray-bar source was cloned into the ignored audit reference directory. Its source is not vendored into release code. Its `run_tests.py` is a useful existing example of mutation-sensitive regression; the new timing harness uses a separately specified integer recurrence.

Pre-existing private and university files remain untouched. Publication requires the user's explicit approval and a separate provenance review. Inspecting private source is not a legal clean-room process; the new modules implement elementary independent counter/bus contracts and do not claim formal clean-room certification.

Redaction note (2026-10-28): private repository identities, internal file paths, private commit hashes and remarks about the private code's protocol version were removed from this file for publication hygiene. The complete audit detail is retained only in the master-control audit record, which is excluded from published archives.
