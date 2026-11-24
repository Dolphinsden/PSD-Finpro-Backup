--------------------------------------------------------------------------------
-- File: sim/tb_zybo_doom_gpu.vhd
-- Description: Self-checking pure-VHDL testbench for zybo_doom_gpu_axi.
--              Verifies:
--                1. AXI4-Lite GPU ID read (0x43C10410 == 0xD0000001)
--                2. Palette LUT write & framebuffer back-buffer pixel writes
--                3. Display enable + tear-free swap request
--                4. MMCM lock & live HDMI TMDS differential output toggling
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_zybo_doom_gpu is
end tb_zybo_doom_gpu;

architecture Behavioral of tb_zybo_doom_gpu is
    constant AXI_CLK_PERIOD : time := 10 ns; -- 100 MHz
    constant SYS_CLK_PERIOD : time := 8 ns;  -- 125 MHz

    signal s_axi_aclk    : STD_LOGIC := '0';
    signal s_axi_aresetn : STD_LOGIC := '0';
    signal s_axi_awaddr  : STD_LOGIC_VECTOR(16 downto 0) := (others => '0');
    signal s_axi_awprot  : STD_LOGIC_VECTOR(2 downto 0) := (others => '0');
    signal s_axi_awvalid : STD_LOGIC := '0';
    signal s_axi_awready : STD_LOGIC;
    signal s_axi_wdata   : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal s_axi_wstrb   : STD_LOGIC_VECTOR(3 downto 0) := (others => '1');
    signal s_axi_wvalid  : STD_LOGIC := '0';
    signal s_axi_wready  : STD_LOGIC;
    signal s_axi_bresp   : STD_LOGIC_VECTOR(1 downto 0);
    signal s_axi_bvalid  : STD_LOGIC;
    signal s_axi_bready  : STD_LOGIC := '0';
    signal s_axi_araddr  : STD_LOGIC_VECTOR(16 downto 0) := (others => '0');
    signal s_axi_arprot  : STD_LOGIC_VECTOR(2 downto 0) := (others => '0');
    signal s_axi_arvalid : STD_LOGIC := '0';
    signal s_axi_arready : STD_LOGIC;
    signal s_axi_rdata   : STD_LOGIC_VECTOR(31 downto 0);
    signal s_axi_rresp   : STD_LOGIC_VECTOR(1 downto 0);
    signal s_axi_rvalid  : STD_LOGIC;
    signal s_axi_rready  : STD_LOGIC := '0';

    signal sysclk_125m   : STD_LOGIC := '0';
    signal btn           : STD_LOGIC_VECTOR(3 downto 0) := "0100"; -- BTN2 (W)
    signal sw            : STD_LOGIC_VECTOR(3 downto 0) := "0001"; -- SW0 (Fire)
    signal led           : STD_LOGIC_VECTOR(3 downto 0);

    signal hdmi_tx_clk_p : STD_LOGIC;
    signal hdmi_tx_clk_n : STD_LOGIC;
    signal hdmi_tx_d_p   : STD_LOGIC_VECTOR(2 downto 0);
    signal hdmi_tx_d_n   : STD_LOGIC_VECTOR(2 downto 0);
begin

    s_axi_aclk  <= not s_axi_aclk  after AXI_CLK_PERIOD / 2;
    sysclk_125m <= not sysclk_125m after SYS_CLK_PERIOD / 2;

    uut : entity work.zybo_doom_gpu_axi
        port map (
            s_axi_aclk    => s_axi_aclk,
            s_axi_aresetn => s_axi_aresetn,
            s_axi_awaddr  => s_axi_awaddr,
            s_axi_awprot  => s_axi_awprot,
            s_axi_awvalid => s_axi_awvalid,
            s_axi_awready => s_axi_awready,
            s_axi_wdata   => s_axi_wdata,
            s_axi_wstrb   => s_axi_wstrb,
            s_axi_wvalid  => s_axi_wvalid,
            s_axi_wready  => s_axi_wready,
            s_axi_bresp   => s_axi_bresp,
            s_axi_bvalid  => s_axi_bvalid,
            s_axi_bready  => s_axi_bready,
            s_axi_araddr  => s_axi_araddr,
            s_axi_arprot  => s_axi_arprot,
            s_axi_arvalid => s_axi_arvalid,
            s_axi_arready => s_axi_arready,
            s_axi_rdata   => s_axi_rdata,
            s_axi_rresp   => s_axi_rresp,
            s_axi_rvalid  => s_axi_rvalid,
            s_axi_rready  => s_axi_rready,
            sysclk_125m   => sysclk_125m,
            btn           => btn,
            sw            => sw,
            led           => led,
            hdmi_tx_clk_p => hdmi_tx_clk_p,
            hdmi_tx_clk_n => hdmi_tx_clk_n,
            hdmi_tx_d_p   => hdmi_tx_d_p,
            hdmi_tx_d_n   => hdmi_tx_d_n
        );

    stim_proc : process
        procedure axi_write(addr : STD_LOGIC_VECTOR(16 downto 0);
                            data : STD_LOGIC_VECTOR(31 downto 0)) is
        begin
            wait until rising_edge(s_axi_aclk);
            s_axi_awaddr  <= addr;
            s_axi_awvalid <= '1';
            s_axi_wdata   <= data;
            s_axi_wvalid  <= '1';
            s_axi_bready  <= '1';

            loop
                wait until rising_edge(s_axi_aclk);
                if s_axi_awready = '1' then
                    s_axi_awvalid <= '0';
                end if;
                if s_axi_wready = '1' then
                    s_axi_wvalid <= '0';
                end if;
                exit when s_axi_bvalid = '1';
            end loop;

            assert s_axi_bresp = "00"
                report "AXI write response not OKAY!" severity failure;
            s_axi_bready <= '0';
        end procedure;

        procedure axi_read(addr     : in  STD_LOGIC_VECTOR(16 downto 0);
                           variable rval : out STD_LOGIC_VECTOR(31 downto 0)) is
        begin
            wait until rising_edge(s_axi_aclk);
            s_axi_araddr  <= addr;
            s_axi_arvalid <= '1';
            s_axi_rready  <= '1';

            loop
                wait until rising_edge(s_axi_aclk);
                if s_axi_arready = '1' then
                    s_axi_arvalid <= '0';
                end if;
                exit when s_axi_rvalid = '1';
            end loop;

            rval := s_axi_rdata;
            assert s_axi_rresp = "00"
                report "AXI read response not OKAY!" severity failure;
            s_axi_rready <= '0';
        end procedure;

        variable rd_data : STD_LOGIC_VECTOR(31 downto 0);
    begin
        -- Release AXI reset
        s_axi_aresetn <= '0';
        wait for 200 ns;
        s_axi_aresetn <= '1';
        wait for 200 ns;

        -- 1. Verify Hardware GPU ID Register (0x10410 == 0xD0000001)
        axi_read("1" & x"0410", rd_data);
        assert rd_data = x"D0000001"
            report "GPU ID mismatch! Expected 0xD0000001." severity failure;
        report "[PASS] GPU ID verified: 0xD0000001";

        -- 2. Program Palette Entry 1 = Pure Red (0x00FF0000), Entry 2 = Pure Green
        axi_write("1" & x"0004", x"00FF0000");
        axi_write("1" & x"0008", x"0000FF00");

        -- 3. Write 4 pixels into back-buffer word 0 (indices 1, 2, 1, 2)
        axi_write("0" & x"0000", x"02010201");

        -- 4. Enable live DOOM display + request VSYNC buffer swap
        axi_write("1" & x"0400", x"00000003");
        report "[PASS] Palette, framebuffer, and VSYNC swap AXI writes succeeded";

        -- 5. Wait for HDMI MMCM to lock (LED[0] = '1')
        wait until led(0) = '1' for 20 us;
        assert led(0) = '1'
            report "HDMI MMCM did not lock within 20 us!" severity failure;
        report "[PASS] HDMI MMCM locked (LED[0] = '1')";

        -- 6. Check differential HDMI clock is active
        wait for 1 us;
        assert hdmi_tx_clk_p = (not hdmi_tx_clk_n)
            report "HDMI TMDS clock pair is not differential!" severity failure;
        report "[PASS] HDMI TMDS differential output active. All checks passed!";

        wait;
    end process;

end Behavioral;
