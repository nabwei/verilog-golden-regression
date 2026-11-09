library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_axi is end;
architecture test of tb_axi is
  signal clk : std_logic := '0';
  signal reset_n : std_logic := '0';
  signal awaddr, araddr : std_logic_vector(7 downto 0) := (others => '0');
  signal wdata, rdata : std_logic_vector(31 downto 0) := (others => '0');
  signal wstrb : std_logic_vector(3 downto 0) := "1111";
  signal awvalid, awready, wvalid, wready, bvalid, bready : std_logic := '0';
  signal arvalid, arready, rvalid, rready : std_logic := '0';
  signal bresp, rresp : std_logic_vector(1 downto 0);
begin
  clk <= not clk after 5 ns;
  dut : entity work.axi_timing generic map(RESET_VALUE => x"1234FFFFFFF0")
    port map(clk, reset_n, awaddr, "000", awvalid, awready, wdata, wstrb,
      wvalid, wready, bresp, bvalid, bready, araddr, "000", arvalid, arready,
      rdata, rresp, rvalid, rready);
  watchdog : process begin wait for 100 us; assert false report "AXI timeout" severity failure; end process;
  process
    variable observed, captured_low : std_logic_vector(31 downto 0);
    variable captured_at : time;
    procedure cycle is
    begin wait until rising_edge(clk); wait for 1 ns; end;
    procedure send_address(address : natural) is
    begin
      awaddr <= std_logic_vector(to_unsigned(address, 8)); awvalid <= '1';
      wait until rising_edge(clk) and awready = '1'; wait for 1 ns; awvalid <= '0';
    end;
    procedure send_payload(payload : natural) is
    begin
      wdata <= std_logic_vector(to_unsigned(payload, 32)); wvalid <= '1';
      wait until rising_edge(clk) and wready = '1'; wait for 1 ns; wvalid <= '0';
    end;
    procedure response(expected : std_logic_vector(1 downto 0)) is
    begin
      while bvalid = '0' loop cycle; end loop;
      for stall in 1 to 3 loop
        assert bvalid = '1' and bresp = expected report "write response/backpressure" severity failure;
        assert awready = '0' and wready = '0' report "extra write accepted while stalled" severity failure;
        cycle;
      end loop;
      bready <= '1'; cycle; bready <= '0';
    end;
    -- Bus procedure arguments model an external transaction and expected result.
    procedure read_register(address : natural; expected_response : std_logic_vector(1 downto 0);
                            variable payload : out std_logic_vector(31 downto 0)) is
    begin
      araddr <= std_logic_vector(to_unsigned(address, 8)); arvalid <= '1';
      wait until rising_edge(clk) and arready = '1'; wait for 1 ns; arvalid <= '0';
      while rvalid = '0' loop cycle; end loop;
      payload := rdata;
      for stall in 1 to 4 loop
        assert rvalid = '1' and rdata = payload and rresp = expected_response
          report "read response unstable under backpressure" severity failure;
        assert arready = '0' report "extra read accepted while stalled" severity failure;
        cycle;
      end loop;
      rready <= '1'; cycle; rready <= '0';
    end;
    procedure simultaneous_control(payload, previous : natural) is
      variable result : std_logic_vector(31 downto 0);
    begin
      assert awready = '1' and wready = '1' report "write channels unavailable" severity failure;
      awaddr <= x"00"; awvalid <= '1';
      wdata <= std_logic_vector(to_unsigned(payload, 32)); wvalid <= '1';
      cycle; awvalid <= '0'; wvalid <= '0';
      araddr <= x"00"; arvalid <= '1'; cycle; arvalid <= '0';
      assert bvalid = '1' and rvalid = '1' and unsigned(rdata) = previous
        report "same-edge control read must observe pre-write state" severity failure;
      response("00");
      assert rvalid = '1' and unsigned(rdata) = previous
        report "simultaneous read changed while write response drained" severity failure;
      rready <= '1'; cycle; rready <= '0';
      read_register(0, "00", result);
      assert unsigned(result) = payload report "control write did not commit" severity failure;
    end;
  begin
    cycle; cycle; reset_n <= '1'; cycle;
    read_register(8, "10", observed);
    read_register(0, "00", observed); assert observed = x"00000000" severity failure;
    -- AW-first and W-first are separate channels, with deliberate gaps.
    send_address(0); cycle; cycle; send_payload(1); response("00");
    read_register(4, "00", captured_low);
    captured_at := now;
    assert unsigned(captured_low) >= unsigned'(x"FFFFFFF0") report "unexpected early wrap" severity failure;
    for gap in 1 to 40 loop cycle; end loop;
    read_register(8, "00", observed);
    assert observed = x"00001234" report "torn snapshot across low-word rollover" severity failure;
    read_register(4, "00", observed);
    assert unsigned(observed) - unsigned(captured_low) = to_unsigned((now - captured_at) / 10 ns, 32)
      report "enabled counter did not advance exactly one tick per bus clock" severity failure;
    read_register(8, "00", observed);
    assert observed = x"00001235" report "counter did not advance across low-word rollover" severity failure;
    send_payload(0); cycle; cycle; send_address(0); response("00");
    read_register(4, "00", captured_low);
    for gap in 1 to 8 loop cycle; end loop;
    read_register(4, "00", observed);
    assert observed = captured_low report "disabled counter changed" severity failure;
    wstrb <= "1110"; send_address(0); send_payload(1); response("00");
    read_register(0, "00", observed); assert observed = x"00000000" report "WSTRB ignored" severity failure;
    wstrb <= "0000"; send_payload(1); send_address(0); response("00");
    read_register(0, "00", observed); assert observed = x"00000000" report "zero strobes wrote register" severity failure;
    wstrb <= "1111";
    for address in 1 to 15 loop
      send_address(address); send_payload(1); response("10");
    end loop;
    read_register(1, "10", observed); read_register(16, "10", observed);
    read_register(12, "00", observed); assert observed(0) = '1' severity failure;
    simultaneous_control(1, 0); simultaneous_control(0, 1);
    -- Reset after only AW must drop it, not pair it with a later W.
    send_address(0); reset_n <= '0'; cycle; reset_n <= '1'; cycle;
    send_payload(1); cycle; cycle;
    assert bvalid = '0' report "orphan address survived reset" severity failure;
    send_address(4); response("10");
    read_register(8, "10", observed);
    -- Reset after only W must not pair the discarded payload with a later AW.
    send_payload(1); reset_n <= '0'; cycle; reset_n <= '1'; cycle;
    send_address(0); cycle; cycle;
    assert bvalid = '0' report "orphan write data survived reset" severity failure;
    send_payload(0); response("00");
    read_register(0, "00", observed); assert observed = x"00000000" severity failure;
    -- Simultaneous channels, then reset while response is stalled.
    awaddr <= x"00"; awvalid <= '1'; wdata <= x"00000001"; wvalid <= '1';
    cycle; awvalid <= '0'; wvalid <= '0'; cycle;
    assert bvalid = '1' report "simultaneous write not completed" severity failure;
    araddr <= x"00"; arvalid <= '1'; cycle; arvalid <= '0';
    assert rvalid = '1' report "read response not pending before reset" severity failure;
    -- Arm IHI0022 A3.1.2 permits asynchronous assertion: VALID must fall during reset.
    wait for 2 ns; reset_n <= '0'; wait for 1 ns;
    assert bvalid = '0' and rvalid = '0'
      report "AXI VALID remained high during asynchronously asserted reset" severity failure;
    cycle;
    assert bvalid = '0' and rvalid = '0' report "reset left pending response" severity failure;
    reset_n <= '1'; cycle;
    read_register(0, "00", observed); assert observed = x"00000000" severity failure;
    read_register(4, "00", observed);
    assert observed = x"FFFFFFF0" report "held reset did not reload counter low word" severity failure;
    read_register(8, "00", observed);
    assert observed = x"00001234" report "held reset did not reload counter high word" severity failure;
    report "PASS AXI: split channels, stalls, snapshot rollover, WSTRB, errors, AW/W partial reset, simultaneous control read/write, asynchronous reset";
    finish;
  end process;
end;
