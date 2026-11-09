library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axi_timing is
  generic (RESET_VALUE : unsigned(47 downto 0) := (others => '0'));
  port (clk, reset_n : in std_logic;
        awaddr : in std_logic_vector(7 downto 0);
        awprot : in std_logic_vector(2 downto 0);
        awvalid : in std_logic; awready : out std_logic;
        wdata : in std_logic_vector(31 downto 0);
        wstrb : in std_logic_vector(3 downto 0);
        wvalid : in std_logic; wready : out std_logic;
        bresp : out std_logic_vector(1 downto 0);
        bvalid : out std_logic; bready : in std_logic;
        araddr : in std_logic_vector(7 downto 0);
        arprot : in std_logic_vector(2 downto 0);
        arvalid : in std_logic; arready : out std_logic;
        rdata : out std_logic_vector(31 downto 0);
        rresp : out std_logic_vector(1 downto 0);
        rvalid : out std_logic; rready : in std_logic);
end entity;

architecture rtl of axi_timing is
  signal count, snapshot : unsigned(47 downto 0) := (others => '0');
  signal enabled, snapshot_valid : std_logic := '0';
  signal address_full, data_full, response_pending, read_pending : std_logic := '0';
  signal saved_address : std_logic_vector(7 downto 0);
  signal saved_data : std_logic_vector(31 downto 0);
  signal saved_strobes : std_logic_vector(3 downto 0);
begin
  counter : entity work.tick_counter
    generic map (RESET_VALUE => RESET_VALUE)
    port map (clk => clk, reset => not reset_n, enable => enabled, ticks => count, rollover => open);
  awready <= reset_n and not address_full and not response_pending;
  wready <= reset_n and not data_full and not response_pending;
  arready <= reset_n and not read_pending;
  bvalid <= response_pending;
  rvalid <= read_pending;

  process(clk, reset_n)
  begin
    if reset_n = '0' then
        address_full <= '0'; data_full <= '0'; response_pending <= '0';
        enabled <= '0'; bresp <= "00";
    elsif rising_edge(clk) then
        if awvalid = '1' and awready = '1' then
          saved_address <= awaddr; address_full <= '1';
        end if;
        if wvalid = '1' and wready = '1' then
          saved_data <= wdata; saved_strobes <= wstrb; data_full <= '1';
        end if;
        if response_pending = '1' and bready = '1' then response_pending <= '0'; end if;
        if address_full = '1' and data_full = '1' and response_pending = '0' then
          address_full <= '0'; data_full <= '0'; response_pending <= '1';
          bresp <= "10";
          if saved_address = x"00" then
            bresp <= "00";
            if saved_strobes(0) = '1' then enabled <= saved_data(0); end if;
          end if;
        end if;
    end if;
  end process;

  process(clk, reset_n)
  begin
    if reset_n = '0' then
        read_pending <= '0'; rdata <= (others => '0'); rresp <= "00";
        snapshot <= (others => '0'); snapshot_valid <= '0';
    elsif rising_edge(clk) then
        if read_pending = '1' and rready = '1' then read_pending <= '0'; end if;
        if arvalid = '1' and arready = '1' then
          read_pending <= '1'; rdata <= (others => '0'); rresp <= "00";
          case araddr is
            when x"00" => rdata(0) <= enabled;
            when x"04" =>
              snapshot <= count; snapshot_valid <= '1';
              rdata <= std_logic_vector(count(31 downto 0));
            when x"08" =>
              rdata(15 downto 0) <= std_logic_vector(snapshot(47 downto 32));
              if snapshot_valid = '0' then rresp <= "10"; end if;
            when x"0c" => rdata(0) <= snapshot_valid;
            when others => rresp <= "10";
          end case;
        end if;
    end if;
  end process;
end architecture;
