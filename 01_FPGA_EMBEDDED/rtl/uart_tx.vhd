library ieee;
use ieee.std_logic_1164.all;

entity uart_tx is
  generic (CLOCKS_PER_BIT : positive := 8);
  port (clk, reset : in std_logic;
        byte_data : in std_logic_vector(7 downto 0);
        byte_valid : in std_logic; byte_ready : out std_logic;
        serial_tx : out std_logic);
end entity;

architecture rtl of uart_tx is
  signal active : std_logic := '0';
  signal frame : std_logic_vector(9 downto 0) := (others => '1');
  signal bit_index : natural range 0 to 9 := 0;
  signal phase : natural range 0 to CLOCKS_PER_BIT - 1 := 0;
  signal quarantine : natural range 0 to 10 * CLOCKS_PER_BIT + 1 := 10 * CLOCKS_PER_BIT + 1;
begin
  assert CLOCKS_PER_BIT >= 2 report "UART requires at least two clocks per bit" severity failure;
  byte_ready <= not active and not reset when quarantine = 0 else '0';
  serial_tx <= frame(bit_index) when active = '1' else '1';
  process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        active <= '0'; bit_index <= 0; phase <= 0;
        quarantine <= 10 * CLOCKS_PER_BIT + 1;
      elsif quarantine > 0 then
        -- A remote receiver is not reset with us: let its aborted frame finish.
        quarantine <= quarantine - 1;
      elsif active = '0' then
        if byte_valid = '1' then
          frame <= '1' & byte_data & '0';
          active <= '1'; bit_index <= 0; phase <= 0;
        end if;
      elsif phase = CLOCKS_PER_BIT - 1 then
        phase <= 0;
        if bit_index = 9 then active <= '0';
        else bit_index <= bit_index + 1; end if;
      else
        phase <= phase + 1;
      end if;
    end if;
  end process;
end architecture;
