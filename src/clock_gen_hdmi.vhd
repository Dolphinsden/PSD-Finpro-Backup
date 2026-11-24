--------------------------------------------------------------------------------
-- File: clock_gen_hdmi.vhd
-- Description: Pure VHDL clock generator for Zybo Z7-10 HDMI output.
--              Uses Xilinx 7-Series MMCME2_BASE to derive:
--                - pix_clk  = 25.2083 MHz (640x480 @ 60.02 Hz, +0.13% of 25.175 MHz)
--                - tmds_clk = 126.0417 MHz (exact phase-locked 5x pix_clk for DDR OSERDESE2)
--              from the Zybo Z7-10 onboard 125 MHz crystal (pin K17).
-- Target: XC7Z010-1CLG400C (Vivado 2026.1)
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library UNISIM;
use UNISIM.VComponents.ALL;

entity clock_gen_hdmi is
    Port (
        sysclk_125m : in  STD_LOGIC;
        ext_reset   : in  STD_LOGIC;  -- Active-high asynchronous reset
        pix_clk     : out STD_LOGIC;  -- 25.2083 MHz pixel & game clock
        tmds_clk    : out STD_LOGIC;  -- 126.0417 MHz 5x DDR TMDS serial clock
        locked      : out STD_LOGIC;  -- MMCM lock indicator
        pix_rst     : out STD_LOGIC   -- Synchronous active-high reset in pix_clk domain
    );
end clock_gen_hdmi;

architecture Behavioral of clock_gen_hdmi is
    signal clkfb_mmcm   : STD_LOGIC;
    signal clkfb_buf    : STD_LOGIC;
    signal pix_clk_raw  : STD_LOGIC;
    signal tmds_clk_raw : STD_LOGIC;
    signal pix_clk_i    : STD_LOGIC;
    signal mmcm_locked  : STD_LOGIC;
    signal rst_shift    : STD_LOGIC_VECTOR(3 downto 0) := (others => '1');
begin

    -- VCO = 125 MHz / 5 * 30.250 = 756.250 MHz (valid 600..1200 MHz for -1 speed grade)
    -- CLKOUT0 = 756.250 / 30.000 = 25.20833 MHz (pixel clock)
    -- CLKOUT1 = 756.250 / 6      = 126.04167 MHz (exact 5x pixel clock)
    u_mmcm : MMCME2_BASE
        generic map (
            BANDWIDTH          => "OPTIMIZED",
            CLKFBOUT_MULT_F    => 30.250,
            CLKFBOUT_PHASE     => 0.0,
            CLKIN1_PERIOD      => 8.000,   -- 125 MHz
            CLKOUT0_DIVIDE_F   => 30.000,  -- 25.2083 MHz
            CLKOUT1_DIVIDE     => 6,       -- 126.0417 MHz
            CLKOUT2_DIVIDE     => 1,
            CLKOUT3_DIVIDE     => 1,
            CLKOUT4_DIVIDE     => 1,
            CLKOUT5_DIVIDE     => 1,
            CLKOUT6_DIVIDE     => 1,
            CLKOUT0_DUTY_CYCLE => 0.5,
            CLKOUT1_DUTY_CYCLE => 0.5,
            CLKOUT0_PHASE      => 0.0,
            CLKOUT1_PHASE      => 0.0,
            CLKOUT4_CASCADE    => FALSE,
            DIVCLK_DIVIDE      => 5,
            REF_JITTER1        => 0.010,
            STARTUP_WAIT       => FALSE
        )
        port map (
            CLKOUT0   => pix_clk_raw,
            CLKOUT0B  => open,
            CLKOUT1   => tmds_clk_raw,
            CLKOUT1B  => open,
            CLKOUT2   => open,
            CLKOUT2B  => open,
            CLKOUT3   => open,
            CLKOUT3B  => open,
            CLKOUT4   => open,
            CLKOUT5   => open,
            CLKOUT6   => open,
            CLKFBOUT  => clkfb_mmcm,
            CLKFBOUTB => open,
            LOCKED    => mmcm_locked,
            CLKIN1    => sysclk_125m,
            PWRDWN    => '0',
            RST       => '0',
            CLKFBIN   => clkfb_buf
        );

    u_bufg_fb : BUFG
        port map (I => clkfb_mmcm, O => clkfb_buf);

    u_bufg_pix : BUFG
        port map (I => pix_clk_raw, O => pix_clk_i);

    u_bufg_tmds : BUFG
        port map (I => tmds_clk_raw, O => tmds_clk);

    pix_clk <= pix_clk_i;
    locked  <= mmcm_locked;

    -- Synchronous reset release: holds reset high for 4 pix_clk cycles after MMCM locks
    -- (also satisfies OSERDESE2 minimum reset pulse requirement).
    process(pix_clk_i, mmcm_locked, ext_reset)
    begin
        if mmcm_locked = '0' or ext_reset = '1' then
            rst_shift <= (others => '1');
        elsif rising_edge(pix_clk_i) then
            rst_shift <= rst_shift(2 downto 0) & '0';
        end if;
    end process;

    pix_rst <= rst_shift(3);

end Behavioral;
