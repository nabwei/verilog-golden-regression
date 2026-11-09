library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity snapshot_stream is
  port (clk, reset : in std_logic;
        ticks : in unsigned(47 downto 0);
        request_valid : in std_logic;
        request_ready : out std_logic;
        sequence_id : in std_logic_vector(7 downto 0);
        byte_valid : out std_logic;
        byte_ready : in std_logic;
        byte_data : out std_logic_vector(7 downto 0));
end entity;

architecture rtl of snapshot_stream is
  signal packet : std_logic_vector(63 downto 0) := (others => '0');
  signal active : std_logic := '0';
  signal index : natural range 0 to 7 := 0;
begin
  request_ready <= not active and not reset;
  byte_valid <= active and not reset;
  byte_data <= packet(8 * index + 7 downto 8 * index);
  process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        active <= '0';
        index <= 0;
        packet <= (others => '0');
      elsif active = '0' and request_valid = '1' then
        packet <= std_logic_vector(ticks) & sequence_id & x"54";
        active <= '1';
        index <= 0;
      elsif active = '1' and byte_ready = '1' then
        if index = 7 then active <= '0'; else index <= index + 1; end if;
      end if;
    end if;
  end process;
end architecture;
