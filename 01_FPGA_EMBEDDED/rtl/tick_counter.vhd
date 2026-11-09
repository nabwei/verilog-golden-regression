library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tick_counter is
  generic (WIDTH : positive := 48;
           RESET_VALUE : unsigned(WIDTH - 1 downto 0) := (others => '0'));
  port (clk, reset, enable : in std_logic;
        ticks : out unsigned(WIDTH - 1 downto 0);
        rollover : out std_logic);
end entity;

architecture rtl of tick_counter is
  signal count : unsigned(WIDTH - 1 downto 0) := RESET_VALUE;
begin
  ticks <= count;
  process(clk)
  begin
    if rising_edge(clk) then
      rollover <= '0';
      if reset = '1' then
        count <= RESET_VALUE;
      elsif enable = '1' then
        count <= count + 1;
        if count = (count'range => '1') then rollover <= '1'; end if;
      end if;
    end if;
  end process;
end architecture;
