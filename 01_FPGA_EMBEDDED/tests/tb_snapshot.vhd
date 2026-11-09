library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_snapshot is end;
architecture test of tb_snapshot is
  signal clk : std_logic := '0';
  signal reset, request_valid, request_ready, byte_valid, byte_ready : std_logic := '0';
  signal ticks : unsigned(47 downto 0) := x"0123456789AB";
  signal sequence_id, byte_data : std_logic_vector(7 downto 0) := x"FE";
begin
  clk <= not clk after 5 ns;
  dut : entity work.snapshot_stream port map(clk, reset, ticks, request_valid,
    request_ready, sequence_id, byte_valid, byte_ready, byte_data);
  process
    type bytes is array(natural range <>) of std_logic_vector(7 downto 0);
    constant expected : bytes := (x"54", x"FE", x"AB", x"89", x"67", x"45", x"23", x"01");
    procedure cycle is
    begin wait until rising_edge(clk); wait for 1 ns; end;
  begin
    reset <= '1'; cycle; reset <= '0'; cycle;
    assert request_ready = '1' severity failure;
    request_valid <= '1'; cycle;
    ticks <= (others => '1'); sequence_id <= x"00";
    for index in 0 to 7 loop
      byte_ready <= '0';
      for stall in 0 to index mod 3 loop
        cycle;
        assert byte_valid = '1' and byte_data = expected(index) and request_ready = '0'
          report "snapshot unstable under backpressure or busy request" severity failure;
      end loop;
      byte_ready <= '1'; cycle;
    end loop;
    request_valid <= '0'; byte_ready <= '0'; cycle;
    assert byte_valid = '0' and request_ready = '1' report "snapshot packet length" severity failure;
    request_valid <= '1'; cycle; request_valid <= '0';
    reset <= '1'; cycle; reset <= '0'; cycle;
    assert byte_valid = '0' and request_ready = '1' report "reset must discard partial packet" severity failure;
    report "PASS snapshot: capture, byte order, backpressure, busy requests, reset";
    finish;
  end process;
end;
