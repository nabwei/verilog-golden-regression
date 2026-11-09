library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_uart is end;
architecture test of tb_uart is
  constant BIT_TIME : time := 80 ns;
  type bytes is array(natural range <>) of std_logic_vector(7 downto 0);
  constant expected : bytes := (x"54", x"FE", x"AB", x"89", x"67", x"45", x"23", x"01");
  signal received : bytes(0 to 31);
  signal framing_errors : std_logic_vector(0 to 31) := (others => '0');
  signal received_count : natural := 0;
  signal clk, reset, request_valid : std_logic := '0';
  signal request_ready, serial_tx : std_logic;
  signal ticks : unsigned(47 downto 0) := x"0123456789AB";
  signal sequence_id : std_logic_vector(7 downto 0) := x"FE";
begin
  clk <= not clk after 5 ns;
  dut : entity work.snapshot_uart generic map(CLOCKS_PER_BIT => 8)
    port map(clk, reset, ticks, request_valid, request_ready, sequence_id, serial_tx);
  watchdog : process begin wait for 100 us; assert false report "UART timeout" severity failure; end process;
  -- Free-running receiver: transmitter reset is deliberately not connected here.
  -- Once a start edge is seen, later falling edges cannot re-arm it until all 10 bits elapsed.
  receiver : process
    variable decoded : std_logic_vector(7 downto 0);
  begin
    wait until falling_edge(serial_tx); wait for BIT_TIME / 2;
    if serial_tx = '0' then
      for bit_number in 0 to 7 loop
        wait for BIT_TIME; decoded(bit_number) := serial_tx;
      end loop;
      wait for BIT_TIME;
      received(received_count) <= decoded;
      framing_errors(received_count) <= not serial_tx;
      received_count <= received_count + 1;
      wait for BIT_TIME / 2;
    end if;
  end process;
  -- Independent idle-window monitor: armed by every reset assertion. From reset release it samples the wire on
  -- every clock edge for one complete frame (10 bit-times). The transmitter must hold idle-high for the whole
  -- window; a frozen frame bit or an early restart drives '0' inside it. It never touches the receiver above.
  idle_monitor : process
    variable released_at : time;
  begin
    wait until reset = '1';
    wait until reset = '0';
    released_at := now;
    while now <= released_at + 10 * BIT_TIME loop
      assert serial_tx = '1' report "UART wire not idle-high throughout the post-reset idle window" severity failure;
      wait until rising_edge(clk); wait for 1 ns;
    end loop;
  end process;
  process
    variable reset_released_at : time;
    procedure cycle is
    begin wait until rising_edge(clk); wait for 1 ns; end;
    procedure check_packet(first : natural) is
    begin
      for index in expected'range loop
        wait until received_count > first + index;
        assert received(first + index) = expected(index) and framing_errors(first + index) = '0'
          report "continuous UART receiver decoded wrong post-reset packet/framing" severity failure;
      end loop;
    end;
  begin
    reset <= '1'; cycle; reset <= '0'; cycle;
    assert serial_tx = '1' and request_ready = '1' report "UART idle state" severity failure;
    request_valid <= '1'; cycle; request_valid <= '0';
    ticks <= (others => '1'); sequence_id <= x"00";
    check_packet(0);
    wait for 2 * BIT_TIME;
    assert serial_tx = '1' and received_count = 8 report "UART emitted an extra byte" severity failure;
    request_valid <= '1'; cycle; request_valid <= '0';
    -- Byte8 is 0x54 = 0b01010100, sent LSB-first with frame = stop & data & start, so the wire carries
    -- start '0', d0 '0', d1 '0', d2 '1', d3 '0', d4 '1', d5 '0', d6 '1', d7 '0', stop '1'.
    -- Reset is asserted two bit-times after the start edge, i.e. while d1 = '0' is on the wire, so the abort check
    -- is falsifiable: a transmitter that ignores the abort keeps driving '0' at the sampling point. (Three bit-times
    -- would land on d2 = '1', making that sampled check vacuous by the bit map above.)
    -- The abort_omitted mutant demonstrates that this low-bit check can fail.
    wait until falling_edge(serial_tx); wait for 2 * BIT_TIME;
    reset <= '1'; cycle;
    assert serial_tx = '1' report "UART reset did not abort transmission" severity failure;
    reset <= '0'; reset_released_at := now; cycle; ticks <= x"0123456789AB"; sequence_id <= x"FE";
    request_valid <= '1'; cycle; request_valid <= '0';
    wait until falling_edge(serial_tx);
    assert now - reset_released_at >= 10 * BIT_TIME
      report "UART restarted before a complete post-reset idle frame" severity failure;
    -- Byte8 is the truncated old frame: the receiver sampled d0 = '0' before the abort, then reads idle-high for
    -- d1..d7 and the stop bit (decodes 0xFE, no framing error). It is corrupt and is discarded at packet level.
    -- The receiver must still complete it before byte9 starts, without being reset itself.
    check_packet(9);
    report "PASS UART: free-running 8N1 receiver, snapshot capture, byte order, transport backpressure, post-abort recovery";
    finish;
  end process;
end architecture;
