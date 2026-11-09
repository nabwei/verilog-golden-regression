library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity snapshot_uart is
  generic (CLOCKS_PER_BIT : positive := 8);
  port (clk, reset : in std_logic;
        ticks : in unsigned(47 downto 0);
        request_valid : in std_logic; request_ready : out std_logic;
        sequence_id : in std_logic_vector(7 downto 0);
        serial_tx : out std_logic);
end entity;

architecture rtl of snapshot_uart is
  signal data : std_logic_vector(7 downto 0);
  signal valid, ready : std_logic;
begin
  packet : entity work.snapshot_stream
    port map(clk, reset, ticks, request_valid, request_ready, sequence_id, valid, ready, data);
  transmitter : entity work.uart_tx generic map(CLOCKS_PER_BIT => CLOCKS_PER_BIT)
    port map(clk, reset, data, valid, ready, serial_tx);
end architecture;
