library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;
use std.env.all;

entity tb_counter is end;
architecture test of tb_counter is
  signal clk : std_logic := '0';
  signal reset, enable : std_logic := '0';
  signal zero_ticks, wrap_ticks : unsigned(47 downto 0);
  signal small_ticks : unsigned(2 downto 0);
  signal zero_wrap, near_wrap, small_wrap : std_logic;
begin
  clk <= not clk after 5 ns;
  normal : entity work.tick_counter port map(clk, reset, enable, zero_ticks, zero_wrap);
  near_limit : entity work.tick_counter generic map(48, x"FFFFFFFFFFFB")
    port map(clk, reset, enable, wrap_ticks, near_wrap);
  small : entity work.tick_counter generic map(WIDTH => 3)
    port map(clk, reset, enable, small_ticks, small_wrap);
  process
    file vectors : text open read_mode is "golden.txt";
    variable row : line;
    variable rst, en, p0, p1, p2 : integer;
    variable e0, e1 : std_logic_vector(47 downto 0);
    variable e2 : std_logic_vector(3 downto 0);
    variable cycles : natural := 0;
  begin
    while not endfile(vectors) loop
      readline(vectors, row);
      read(row, rst); read(row, en); hread(row, e0); read(row, p0);
      hread(row, e1); read(row, p1); hread(row, e2); read(row, p2);
      reset <= std_logic'val(rst + 2); enable <= std_logic'val(en + 2);
      wait until rising_edge(clk); wait for 1 ns;
      assert zero_ticks = unsigned(e0) and wrap_ticks = unsigned(e1) and
             small_ticks = unsigned(e2(2 downto 0)) report "counter golden mismatch cycle " & integer'image(cycles) severity failure;
      assert zero_wrap = std_logic'val(p0 + 2) and near_wrap = std_logic'val(p1 + 2) and
             small_wrap = std_logic'val(p2 + 2) report "rollover pulse mismatch" severity failure;
      cycles := cycles + 1;
      wait until falling_edge(clk);
    end loop;
    assert cycles = 5000 report "truncated golden vectors" severity failure;
    report "PASS counter: 5000 cycles, three widths/initial states";
    finish;
  end process;
end;
