library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;
use std.env.all;

entity tb_trace is end;
architecture test of tb_trace is
  signal clk : std_logic := '0';
  signal reset : std_logic := '1';
  signal ticks : unsigned(47 downto 0);
begin
  clk <= not clk after 500 us;
  dut : entity work.tick_counter generic map(RESET_VALUE => x"FFFFFFFFFFF6")
    port map(clk, reset, '1', ticks, open);
  process
    file trace_file : text open write_mode is "hdl_ticks.txt";
    variable row : line;
  begin
    wait until rising_edge(clk); wait for 1 ns; reset <= '0';
    for sample in 0 to 100 loop
      write(row, sample); write(row, string'(" ")); hwrite(row, std_logic_vector(ticks));
      writeline(trace_file, row);
      for cycle in 1 to 10 loop wait until rising_edge(clk); wait for 1 ns; end loop;
    end loop;
    report "PASS trace: 101 samples from HDL, 48-bit rollover included";
    finish;
  end process;
end;
