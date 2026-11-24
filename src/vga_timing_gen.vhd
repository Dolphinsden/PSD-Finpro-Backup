--------------------------------------------------------------------------------
-- File: vga_timing_gen.vhd
-- Description: Standard VESA 640x480 @ 60 Hz video timing generator.
--              Total frame: 800 x 525 pixels (active 640 x 480).
--              Emits a single-cycle frame_start pulse at start of VBLANK (y=480, x=0)
--              so the raycaster and game engine update tear-free during VBLANK.
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity vga_timing_gen is
    Port (
        pix_clk      : in  STD_LOGIC;
        rst          : in  STD_LOGIC;
        h_count      : out unsigned(9 downto 0);
        v_count      : out unsigned(9 downto 0);
        hsync        : out STD_LOGIC;  -- Active-low VESA sync
        vsync        : out STD_LOGIC;  -- Active-low VESA sync
        de           : out STD_LOGIC;  -- Data Enable (active video)
        vblank_start : out STD_LOGIC   -- 1-cycle pulse at (x=0, y=480)
    );
end vga_timing_gen;

architecture Behavioral of vga_timing_gen is
    -- Horizontal timings (pixels)
    constant H_ACTIVE : integer := 640;
    constant H_FP     : integer := 16;
    constant H_SYNC   : integer := 96;
    constant H_TOTAL  : integer := 800;

    -- Vertical timings (lines)
    constant V_ACTIVE : integer := 480;
    constant V_FP     : integer := 10;
    constant V_SYNC   : integer := 2;
    constant V_TOTAL  : integer := 525;

    signal h_cnt : unsigned(9 downto 0) := (others => '0');
    signal v_cnt : unsigned(9 downto 0) := (others => '0');
begin

    process(pix_clk)
    begin
        if rising_edge(pix_clk) then
            if rst = '1' then
                h_cnt <= (others => '0');
                v_cnt <= (others => '0');
            else
                if h_cnt = H_TOTAL - 1 then
                    h_cnt <= (others => '0');
                    if v_cnt = V_TOTAL - 1 then
                        v_cnt <= (others => '0');
                    else
                        v_cnt <= v_cnt + 1;
                    end if;
                else
                    h_cnt <= h_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    h_count <= h_cnt;
    v_count <= v_cnt;

    de    <= '1' when (h_cnt < H_ACTIVE and v_cnt < V_ACTIVE) else '0';
    hsync <= '0' when (h_cnt >= H_ACTIVE + H_FP and h_cnt < H_ACTIVE + H_FP + H_SYNC) else '1';
    vsync <= '0' when (v_cnt >= V_ACTIVE + V_FP and v_cnt < V_ACTIVE + V_FP + V_SYNC) else '1';

    vblank_start <= '1' when (h_cnt = 0 and v_cnt = V_ACTIVE) else '0';

end Behavioral;
