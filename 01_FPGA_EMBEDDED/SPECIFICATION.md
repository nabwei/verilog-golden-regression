# Independently specified timing extension

This implementation is independent educational RTL, not a translation of university production source and not a claim of equivalence to any private or production hardware.

## A: counter, snapshot and UART transport

At each rising clock edge, synchronous active-high reset has priority over enable. Reset loads `RESET_VALUE` (default zero). Enabled edges increment modulo 2^WIDTH; disabled edges hold. `rollover` pulses only on an enabled transition from all ones to zero, and is low during reset and hold. Production default WIDTH is 48. Nonzero reset values permit testing the actual 48-bit rollover without simulating 2^48 cycles.

`snapshot_stream` accepts a request only when `request_ready` is high. The tick and request sequence are captured on that edge, before any simultaneous counter increment. It produces eight bytes: 0x54, sequence, and six timestamp bytes in little-endian order. Output byte and valid remain stable until a ready/valid transfer. Requests while busy are not accepted. `snapshot_uart` connects this interface to `uart_tx`: an actual synthesizable UART transmitter, 8 data bits, no parity, one stop bit (8N1), LSB first, idle high. Each bit lasts `CLOCKS_PER_BIT` clocks (integer >= 2, default 8), giving baud = clock frequency / CLOCKS_PER_BIT. Synchronous reset aborts the active frame and packet. After reset release the transmitter holds idle high and byte_ready low for at least one complete10-bit frame (10*CLOCKS_PER_BIT plus one clock-phase guard); the snapshot buffer may accept a request during that idle interval. A free-running external receiver finishes its old truncated frame before the next start bit. That old byte can be corrupt and the application must discard any incomplete old packet: this unprotected packet format does not promise application-level self-synchronization. The independent test receiver is never reset with the transmitter and samples complete8N1 frames at bit centres, proving the following packet is decoded correctly. CRC framing, UART receive, physical electrical timing and compatibility with the user's unavailable protocol v2 are not claimed; this is a public independent packet format.

## B: single-clock AXI4-Lite

32-bit data, 8-bit byte address, one outstanding read and write. All five channels follow independent ready/valid handshakes. AW and W may arrive in either order. Responses and read data remain stable under backpressure. Reset discards in-flight transactions. All addresses must match a defined aligned register exactly. Unsupported accesses return SLVERR (10). AWPROT/ARPROT are ignored: no security boundary is implemented.

| Address | Register | Behavior |
|---|---|---|
| 0x00 | CONTROL | bit 0 enable, reset value 0; only WSTRB[0] changes it; reserved bits ignored |
| 0x04 | SNAP_LOW | read captures the complete pre-edge counter and returns bits 31:0 |
| 0x08 | SNAP_HIGH | read returns zero-extended bits 47:32 of last snapshot; SLVERR before first low read |
| 0x0c | STATUS | bit 0 snapshot valid |

Registers 0x04/0x08/0x0c are read-only. Low then high is consistent across counter rollover. Concurrent clients must serialize each low/high pair; this is not a multi-reader snapshot bank. External reset resets counter, enable and snapshot validity. Counter state increments with the pre-edge enable value. A read accepted on the same edge as a control write observes pre-edge state.

AXI `reset_n` asserts asynchronously for bus state: pending BVALID/RVALID, partial AW/W transactions, enable and snapshot validity clear without waiting for a clock edge. Deassertion must be synchronized to `clk` by the integration environment. Hold reset across at least one rising edge to load the counter's independently specified synchronous reset value. This implements Arm IHI0022H A3.1.2; FPGA pin/reset timing and recovery/removal still require target implementation checks.

## C: trace-driven software co-simulation

GHDL produces real HDL tick traces, including 48-bit rollover. A C++ replay uses Project G's shared `robot::wheel_twist` and `robot::integrate`, unwraps modulo 2^48 under the assumption of forward steps smaller than 2^47, and converts ticks to elapsed seconds. Heading follows G's wrapped angle convention. Analytic circular motion is the independent trajectory reference. Packet gaps preserve elapsed time; duplicates and backwards stamps are rejected. Injected timestamp offsets must change position measurably.

`sensor_cosim emit` attaches the actual HDL timestamps to simulated left/right wheel encoder angles and one forward LiDAR range from Project G's world/ray marcher. Plant sampling uses sequence-relative 10 ms intervals independently of the HDL timestamps. The room is 10 x 10 m, initial pose (1,1,0), wheel angular rates 10 and 14 rad/s, radius .05 m, axle .4 m. CSV columns are sequence,ticks,left_angle_rad,right_angle_rad,front_range_m; ticks are decimal unsigned 48-bit integers. Replay accepts LF or CRLF, requires the initial zero-angle observation and increasing sequence/timestamps, and treats later missing packets as time gaps. It rejects timestamp/sensor inconsistencies above .005 rad encoder residual or .004 m range residual. These are ideal simulation limits, not calibrated hardware tolerances.

The independent Python oracle uses x(t)=1+1.2*sin(.5*t), wall distance (10-x)/cos(.5*t), and wheel angles 10*t and 14*t, with a .0021 m allowance for the G ray marcher's .002 m step. It does not call the production integrator or ray marcher. Tests inject +5 ticks into one timestamp and +.2 m into one range separately; both must fail for cross-domain inconsistency. Retaining every fourth packet must preserve the final one-second time. Sensor generation/replay are also compared byte-for-byte after isolated source rebuild.

This is trace-driven software co-simulation, not live lockstep co-simulation or physical Hardware-in-the-Loop. Clock-domain crossing, metastability, FPGA timing closure, board UART timing and Zynq deployment require separate verification.

## Sources

- [Arm IHI0022H A3.1.2 reset specification](https://documentation-service.arm.com/static/602a9df190ee6824a1e02b98): asynchronous assertion and synchronous deassertion of ARESETn, with subordinate VALID low during reset.
- [Arm AXI specification](https://documentation-service.arm.com/static/6425706579edab6d64fb6f54): independent channels and held VALID handshake contract.
- [GHDL documentation](https://ghdl.github.io/ghdl/using/InvokingGHDL.html): analyzer, elaboration and simulation commands; local executable help/version is recorded with results.
