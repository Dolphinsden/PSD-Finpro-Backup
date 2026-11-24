--------------------------------------------------------------------------------
-- File: zybo_doom_gpu_axi.vhd
-- Description: 100% Pure-VHDL AXI4-Lite GPU & HDMI Display Controller for DOOM
--              on the Digilent Zybo Z7-10 (XC7Z010-1CLG400C).
--
-- Features:
--   - Double-buffered 320x200 x 8-bit indexed BRAM framebuffer (128 KB total,
--     32 BRAM36 tiles = 53% of Z7-10 BRAM) with tear-free VSYNC page flip.
--   - 256 x 24-bit hardware Color Look-Up Table (Palette LUT) in BRAM.
--   - Hardware 2x pixel-perfect scaler (320x200 -> 640x400 centered inside
--     standard 640x480 @ 60 Hz HDMI with clean 40px letterbox bars).
--   - Built-in SMPTE color-bar boot & diagnostic screen (active at power-on
--     before ARM enables display, or anytime SW[3] = '1').
--   - Glitch-free debounced hardware input register for Zybo BTN[3:0] & SW[3:0].
--   - Direct custom VHDL DVI/HDMI TMDS TX (zero AXI VDMA, zero Digilent IP).
--
-- AXI4-Lite Address Map (128 KB window, default base 0x43C0_0000):
--   0x00000 - 0x0FFFF : Back-buffer pixel write window (16,000 x 32-bit words,
--                       4 packed 8-bit palette indices per 32-bit word:
--                       [p3(31:24) | p2(23:16) | p1(15:8) | p0(7:0)])
--   0x10000 - 0x103FC : 256-entry Palette LUT (write 0x00RRGGBB per entry)
--   0x10400           : REG_CTRL (W: bit0=request VSYNC swap, bit1=enable DOOM;
--                                 R: bit0=swap_pending, bit1=disp_en,
--                                    bit2=mmcm_locked, bit3=vsync, bit4=active_buf)
--   0x10404           : REG_INPUT (R: [3:0]=BTN[3:0], [7:4]=SW[3:0])
--   0x10408           : REG_LED   (RW: [3:0]=software LED bits)
--   0x1040C           : REG_FRAME_CNT (R: 32-bit 60 Hz frame counter)
--   0x10410           : REG_GPU_ID    (R: 0xD0000001 constant hardware ID)
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity zybo_doom_gpu_axi is
    Port (
        -- AXI4-Lite Slave Interface (connects to Zynq M_AXI_GP0 @ 100 MHz)
        s_axi_aclk    : in  STD_LOGIC;
        s_axi_aresetn : in  STD_LOGIC;
        s_axi_awaddr  : in  STD_LOGIC_VECTOR(16 downto 0);
        s_axi_awprot  : in  STD_LOGIC_VECTOR(2 downto 0);
        s_axi_awvalid : in  STD_LOGIC;
        s_axi_awready : out STD_LOGIC;
        s_axi_wdata   : in  STD_LOGIC_VECTOR(31 downto 0);
        s_axi_wstrb   : in  STD_LOGIC_VECTOR(3 downto 0);
        s_axi_wvalid  : in  STD_LOGIC;
        s_axi_wready  : out STD_LOGIC;
        s_axi_bresp   : out STD_LOGIC_VECTOR(1 downto 0);
        s_axi_bvalid  : out STD_LOGIC;
        s_axi_bready  : in  STD_LOGIC;
        s_axi_araddr  : in  STD_LOGIC_VECTOR(16 downto 0);
        s_axi_arprot  : in  STD_LOGIC_VECTOR(2 downto 0);
        s_axi_arvalid : in  STD_LOGIC;
        s_axi_arready : out STD_LOGIC;
        s_axi_rdata   : out STD_LOGIC_VECTOR(31 downto 0);
        s_axi_rresp   : out STD_LOGIC_VECTOR(1 downto 0);
        s_axi_rvalid  : out STD_LOGIC;
        s_axi_rready  : in  STD_LOGIC;

        -- Zybo Z7-10 Board Clock & Peripherals
        sysclk_125m   : in  STD_LOGIC;
        btn           : in  STD_LOGIC_VECTOR(3 downto 0);
        sw            : in  STD_LOGIC_VECTOR(3 downto 0);
        led           : out STD_LOGIC_VECTOR(3 downto 0);

        -- Zybo Z7-10 HDMI TX Differential Output (TMDS_33)
        hdmi_tx_clk_p : out STD_LOGIC;
        hdmi_tx_clk_n : out STD_LOGIC;
        hdmi_tx_d_p   : out STD_LOGIC_VECTOR(2 downto 0);
        hdmi_tx_d_n   : out STD_LOGIC_VECTOR(2 downto 0)
    );
end zybo_doom_gpu_axi;

architecture Behavioral of zybo_doom_gpu_axi is

    -- Vivado IP Integrator interface hints for clean VHDL module reference binding
    attribute X_INTERFACE_INFO : string;
    attribute X_INTERFACE_PARAMETER : string;
    attribute X_INTERFACE_INFO of s_axi_aclk    : signal is "xilinx.com:signal:clock:1.0 s_axi_aclk CLK";
    attribute X_INTERFACE_PARAMETER of s_axi_aclk : signal is "ASSOCIATED_BUSIF s_axi, ASSOCIATED_RESET s_axi_aresetn";
    attribute X_INTERFACE_INFO of s_axi_aresetn : signal is "xilinx.com:signal:reset:1.0 s_axi_aresetn RST";
    attribute X_INTERFACE_PARAMETER of s_axi_aresetn : signal is "POLARITY ACTIVE_LOW";
    attribute X_INTERFACE_INFO of sysclk_125m   : signal is "xilinx.com:signal:clock:1.0 sysclk_125m CLK";
    attribute X_INTERFACE_PARAMETER of sysclk_125m : signal is "FREQ_HZ 125000000";

    ----------------------------------------------------------------------------
    -- Clock & Reset signals
    ----------------------------------------------------------------------------
    signal pix_clk      : STD_LOGIC;
    signal tmds_clk     : STD_LOGIC;
    signal mmcm_locked  : STD_LOGIC;
    signal pix_rst      : STD_LOGIC;

    ----------------------------------------------------------------------------
    -- True Dual-Port BRAMs:
    --   fb_ram  : 32768 x 32-bit = 128 KB (2 x 64 KB buffers, 32 BRAM36 tiles)
    --   pal_ram : 256 x 24-bit   = 256 RGB colors (1 BRAM18 tile)
    ----------------------------------------------------------------------------
    type fb_ram_t  is array (0 to 32767) of STD_LOGIC_VECTOR(31 downto 0);
    type pal_ram_t is array (0 to 255)   of STD_LOGIC_VECTOR(23 downto 0);

    signal fb_ram  : fb_ram_t  := (others => (others => '0'));
    signal pal_ram : pal_ram_t := (others => (others => '0'));

    attribute ram_style : string;
    attribute ram_style of fb_ram  : signal is "block";
    attribute ram_style of pal_ram : signal is "block";

    -- BRAM Write Port (s_axi_aclk domain)
    signal fb_we       : STD_LOGIC := '0';
    signal fb_waddr    : unsigned(14 downto 0) := (others => '0');
    signal fb_wdata    : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');

    signal pal_we      : STD_LOGIC := '0';
    signal pal_waddr   : unsigned(7 downto 0) := (others => '0');
    signal pal_wdata   : STD_LOGIC_VECTOR(23 downto 0) := (others => '0');

    -- BRAM Read Port (pix_clk domain)
    signal fb_raddr    : unsigned(14 downto 0) := (others => '0');
    signal fb_rdata    : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');

    signal pal_raddr   : unsigned(7 downto 0) := (others => '0');
    signal pal_rdata   : STD_LOGIC_VECTOR(23 downto 0) := (others => '0');

    ----------------------------------------------------------------------------
    -- AXI4-Lite Slave State (s_axi_aclk domain)
    ----------------------------------------------------------------------------
    signal aw_seen     : STD_LOGIC := '0';
    signal aw_addr_reg : STD_LOGIC_VECTOR(16 downto 0) := (others => '0');
    signal w_seen      : STD_LOGIC := '0';
    signal w_data_reg  : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal bvalid_i    : STD_LOGIC := '0';

    signal arready_i   : STD_LOGIC := '0';
    signal rvalid_i    : STD_LOGIC := '0';
    signal rdata_i     : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');

    signal disp_en_axi      : STD_LOGIC := '0';
    signal swap_req_tog_axi : STD_LOGIC := '0';
    signal led_sw_axi       : STD_LOGIC_VECTOR(3 downto 0) := (others => '0');

    ----------------------------------------------------------------------------
    -- CDC Synchronizers (s_axi_aclk <-> pix_clk)
    ----------------------------------------------------------------------------
    attribute ASYNC_REG : string;

    -- pix_clk -> s_axi_aclk
    signal swap_ack_axi_s1   : STD_LOGIC := '0';
    signal swap_ack_axi_s2   : STD_LOGIC := '0';
    signal active_buf_axi_s1 : STD_LOGIC := '0';
    signal active_buf_axi_s2 : STD_LOGIC := '0';
    signal mmcm_lock_axi_s1  : STD_LOGIC := '0';
    signal mmcm_lock_axi_s2  : STD_LOGIC := '0';
    signal vsync_axi_s1      : STD_LOGIC := '1';
    signal vsync_axi_s2      : STD_LOGIC := '1';
    signal inputs_axi_s1     : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal inputs_axi_s2     : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal frame_cnt_axi_s1  : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal frame_cnt_axi_s2  : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');

    attribute ASYNC_REG of swap_ack_axi_s1   : signal is "TRUE";
    attribute ASYNC_REG of swap_ack_axi_s2   : signal is "TRUE";
    attribute ASYNC_REG of active_buf_axi_s1 : signal is "TRUE";
    attribute ASYNC_REG of active_buf_axi_s2 : signal is "TRUE";
    attribute ASYNC_REG of mmcm_lock_axi_s1  : signal is "TRUE";
    attribute ASYNC_REG of mmcm_lock_axi_s2  : signal is "TRUE";
    attribute ASYNC_REG of vsync_axi_s1      : signal is "TRUE";
    attribute ASYNC_REG of vsync_axi_s2      : signal is "TRUE";

    -- s_axi_aclk -> pix_clk
    signal swap_req_pix_s1 : STD_LOGIC := '0';
    signal swap_req_pix_s2 : STD_LOGIC := '0';
    signal disp_en_pix_s1  : STD_LOGIC := '0';
    signal disp_en_pix_s2  : STD_LOGIC := '0';
    signal led_sw_pix_s1   : STD_LOGIC_VECTOR(3 downto 0) := (others => '0');
    signal led_sw_pix_s2   : STD_LOGIC_VECTOR(3 downto 0) := (others => '0');

    attribute ASYNC_REG of swap_req_pix_s1 : signal is "TRUE";
    attribute ASYNC_REG of swap_req_pix_s2 : signal is "TRUE";
    attribute ASYNC_REG of disp_en_pix_s1  : signal is "TRUE";
    attribute ASYNC_REG of disp_en_pix_s2  : signal is "TRUE";

    ----------------------------------------------------------------------------
    -- Video Timing, Debounced Inputs & 3-Stage Pixel Pipeline (pix_clk domain)
    ----------------------------------------------------------------------------
    signal raw_inputs   : STD_LOGIC_VECTOR(7 downto 0);
    signal clean_inputs : STD_LOGIC_VECTOR(7 downto 0);
    signal btn_clean    : STD_LOGIC_VECTOR(3 downto 0);
    signal sw_clean     : STD_LOGIC_VECTOR(3 downto 0);

    signal h_cnt_0      : unsigned(9 downto 0);
    signal v_cnt_0      : unsigned(9 downto 0);
    signal hs_0         : STD_LOGIC;
    signal vs_0         : STD_LOGIC;
    signal de_0         : STD_LOGIC;
    signal vblank_start : STD_LOGIC;

    signal active_buf_pix   : STD_LOGIC := '0';
    signal swap_ack_tog_pix : STD_LOGIC := '0';
    signal frame_cnt_pix    : unsigned(31 downto 0) := (others => '0');

    -- Stage 1 registers (aligned with fb_rdata output)
    signal h_cnt_1    : unsigned(9 downto 0) := (others => '0');
    signal v_cnt_1    : unsigned(9 downto 0) := (others => '0');
    signal byte_sel_1 : unsigned(1 downto 0) := (others => '0');
    signal in_vp_1    : STD_LOGIC := '0';
    signal hs_1       : STD_LOGIC := '1';
    signal vs_1       : STD_LOGIC := '1';
    signal de_1       : STD_LOGIC := '0';

    -- Stage 2 registers (aligned with pal_rdata output)
    signal h_cnt_2    : unsigned(9 downto 0) := (others => '0');
    signal v_cnt_2    : unsigned(9 downto 0) := (others => '0');
    signal in_vp_2    : STD_LOGIC := '0';
    signal hs_2       : STD_LOGIC := '1';
    signal vs_2       : STD_LOGIC := '1';
    signal de_2       : STD_LOGIC := '0';

    -- Stage 3 registers (final RGB -> HDMI TX PHY)
    signal rgb_r      : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal rgb_g      : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal rgb_b      : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal hs_3       : STD_LOGIC := '1';
    signal vs_3       : STD_LOGIC := '1';
    signal de_3       : STD_LOGIC := '0';

begin

    ----------------------------------------------------------------------------
    -- 1. HDMI Clock Generator (125 MHz -> 25.2083 MHz pix_clk + 126.0417 MHz)
    ----------------------------------------------------------------------------
    u_clkgen : entity work.clock_gen_hdmi
        port map (
            sysclk_125m => sysclk_125m,
            ext_reset   => '0',
            pix_clk     => pix_clk,
            tmds_clk    => tmds_clk,
            locked      => mmcm_locked,
            pix_rst     => pix_rst
        );

    ----------------------------------------------------------------------------
    -- 2. Hardware Input Debouncer (BTN[3:0] & SW[3:0])
    ----------------------------------------------------------------------------
    raw_inputs <= sw & btn;

    u_debounce : entity work.input_debouncer
        generic map (
            WIDTH        => 8,
            DEBOUNCE_MAX => 300000
        )
        port map (
            clk       => pix_clk,
            rst       => pix_rst,
            raw_in    => raw_inputs,
            clean_out => clean_inputs
        );

    btn_clean <= clean_inputs(3 downto 0);
    sw_clean  <= clean_inputs(7 downto 4);

    ----------------------------------------------------------------------------
    -- 3. 640x480 @ 60 Hz VESA Timing Generator
    ----------------------------------------------------------------------------
    u_timing : entity work.vga_timing_gen
        port map (
            pix_clk      => pix_clk,
            rst          => pix_rst,
            h_count      => h_cnt_0,
            v_count      => v_cnt_0,
            hsync        => hs_0,
            vsync        => vs_0,
            de           => de_0,
            vblank_start => vblank_start
        );

    ----------------------------------------------------------------------------
    -- 4. AXI4-Lite Slave Interface (s_axi_aclk domain)
    ----------------------------------------------------------------------------
    s_axi_awready <= '1' when (aw_seen = '0' and bvalid_i = '0') else '0';
    s_axi_wready  <= '1' when (w_seen  = '0' and bvalid_i = '0') else '0';
    s_axi_bresp   <= "00";  -- OKAY
    s_axi_bvalid  <= bvalid_i;

    s_axi_arready <= arready_i;
    s_axi_rdata   <= rdata_i;
    s_axi_rresp   <= "00";  -- OKAY
    s_axi_rvalid  <= rvalid_i;

    -- CDC into s_axi_aclk domain
    process(s_axi_aclk)
    begin
        if rising_edge(s_axi_aclk) then
            swap_ack_axi_s1   <= swap_ack_tog_pix;
            swap_ack_axi_s2   <= swap_ack_axi_s1;
            active_buf_axi_s1 <= active_buf_pix;
            active_buf_axi_s2 <= active_buf_axi_s1;
            mmcm_lock_axi_s1  <= mmcm_locked;
            mmcm_lock_axi_s2  <= mmcm_lock_axi_s1;
            vsync_axi_s1      <= vs_0;
            vsync_axi_s2      <= vsync_axi_s1;
            inputs_axi_s1     <= clean_inputs;
            inputs_axi_s2     <= inputs_axi_s1;
            frame_cnt_axi_s1  <= std_logic_vector(frame_cnt_pix);
            frame_cnt_axi_s2  <= frame_cnt_axi_s1;
        end if;
    end process;

    -- AXI4-Lite Write & Read FSM
    process(s_axi_aclk)
        variable eff_aw_seen : STD_LOGIC;
        variable eff_w_seen  : STD_LOGIC;
        variable eff_aw_addr : STD_LOGIC_VECTOR(16 downto 0);
        variable eff_w_data  : STD_LOGIC_VECTOR(31 downto 0);
        variable swap_pend   : STD_LOGIC;
    begin
        if rising_edge(s_axi_aclk) then
            fb_we  <= '0';
            pal_we <= '0';

            if s_axi_aresetn = '0' then
                aw_seen          <= '0';
                w_seen           <= '0';
                bvalid_i         <= '0';
                arready_i        <= '0';
                rvalid_i         <= '0';
                rdata_i          <= (others => '0');
                disp_en_axi      <= '0';
                swap_req_tog_axi <= '0';
                led_sw_axi       <= (others => '0');
            else
                ----------------------------------------------------------------
                -- Write Channel (accepts AW & W in same or separate cycles)
                ----------------------------------------------------------------
                eff_aw_seen := aw_seen;
                eff_w_seen  := w_seen;
                eff_aw_addr := aw_addr_reg;
                eff_w_data  := w_data_reg;

                if (aw_seen = '0' and bvalid_i = '0' and s_axi_awvalid = '1') then
                    aw_seen     <= '1';
                    aw_addr_reg <= s_axi_awaddr;
                    eff_aw_seen := '1';
                    eff_aw_addr := s_axi_awaddr;
                end if;

                if (w_seen = '0' and bvalid_i = '0' and s_axi_wvalid = '1') then
                    w_seen     <= '1';
                    w_data_reg <= s_axi_wdata;
                    eff_w_seen := '1';
                    eff_w_data := s_axi_wdata;
                end if;

                if (eff_aw_seen = '1' and eff_w_seen = '1' and bvalid_i = '0') then
                    aw_seen  <= '0';
                    w_seen   <= '0';
                    bvalid_i <= '1';

                    -- Address decode
                    if eff_aw_addr(16) = '0' then
                        -- 0x00000..0x0FFFF: Framebuffer back-buffer write (4 pixels/word)
                        fb_we    <= '1';
                        fb_waddr <= unsigned(STD_LOGIC_VECTOR'((not active_buf_axi_s2) & eff_aw_addr(15 downto 2)));
                        fb_wdata <= eff_w_data;
                    elsif eff_aw_addr(15 downto 10) = "000000" then
                        -- 0x10000..0x103FC: 256-color Palette LUT write (0x00RRGGBB)
                        pal_we    <= '1';
                        pal_waddr <= unsigned(eff_aw_addr(9 downto 2));
                        pal_wdata <= eff_w_data(23 downto 0);
                    elsif eff_aw_addr(15 downto 10) = "000001" then
                        -- 0x10400..0x1041C: Control/LED registers
                        case eff_aw_addr(5 downto 2) is
                            when "0000" => -- 0x10400 REG_CTRL
                                disp_en_axi <= eff_w_data(1);
                                if eff_w_data(0) = '1' then
                                    swap_req_tog_axi <= not swap_req_tog_axi;
                                end if;
                            when "0010" => -- 0x10408 REG_LED
                                led_sw_axi <= eff_w_data(3 downto 0);
                            when others =>
                                null;
                        end case;
                    end if;
                elsif (bvalid_i = '1' and s_axi_bready = '1') then
                    bvalid_i <= '0';
                end if;

                ----------------------------------------------------------------
                -- Read Channel
                ----------------------------------------------------------------
                arready_i <= '0';
                if (s_axi_arvalid = '1' and rvalid_i = '0' and arready_i = '0') then
                    arready_i <= '1';
                    rvalid_i  <= '1';

                    if swap_req_tog_axi /= swap_ack_axi_s2 then
                        swap_pend := '1';
                    else
                        swap_pend := '0';
                    end if;

                    if (s_axi_araddr(16) = '1' and s_axi_araddr(15 downto 10) = "000001") then
                        case s_axi_araddr(5 downto 2) is
                            when "0000" => -- 0x10400 REG_CTRL
                                rdata_i <= (31 downto 5 => '0') &
                                           active_buf_axi_s2 &
                                           vsync_axi_s2 &
                                           mmcm_lock_axi_s2 &
                                           disp_en_axi &
                                           swap_pend;
                            when "0001" => -- 0x10404 REG_INPUT
                                rdata_i <= (31 downto 8 => '0') & inputs_axi_s2;
                            when "0010" => -- 0x10408 REG_LED
                                rdata_i <= (31 downto 4 => '0') & led_sw_axi;
                            when "0011" => -- 0x1040C REG_FRAME_CNT
                                rdata_i <= frame_cnt_axi_s2;
                            when "0100" => -- 0x10410 REG_GPU_ID
                                rdata_i <= x"D0000001";
                            when others =>
                                rdata_i <= (others => '0');
                        end case;
                    else
                        rdata_i <= (others => '0');
                    end if;
                elsif (rvalid_i = '1' and s_axi_rready = '1') then
                    rvalid_i <= '0';
                end if;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- 5. Simple Dual-Port BRAM Write Port (s_axi_aclk) & Read Port (pix_clk)
    ----------------------------------------------------------------------------
    process(s_axi_aclk)
    begin
        if rising_edge(s_axi_aclk) then
            if fb_we = '1' then
                fb_ram(to_integer(fb_waddr)) <= fb_wdata;
            end if;
            if pal_we = '1' then
                pal_ram(to_integer(pal_waddr)) <= pal_wdata;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- 6. Real-Time 2x Scaler, Palette Lookup & SMPTE Test Screen (pix_clk)
    ----------------------------------------------------------------------------
    -- Combinatorial next-address for Stage 0 -> BRAM synchronous read (arrives Stage 1)
    process(h_cnt_0, v_cnt_0, active_buf_pix)
        variable doom_x    : unsigned(8 downto 0);
        variable doom_y    : unsigned(7 downto 0);
        variable y_times80 : unsigned(13 downto 0);
        variable word_idx  : unsigned(13 downto 0);
    begin
        if (h_cnt_0 < 640 and v_cnt_0 >= 40 and v_cnt_0 < 440) then
            doom_x    := h_cnt_0(9 downto 1);                        -- 0..319
            doom_y    := resize(shift_right(v_cnt_0 - 40, 1), 8);    -- 0..199
            -- doom_y * 80 = (doom_y << 6) + (doom_y << 4)
            y_times80 := shift_left(resize(doom_y, 14), 6) +
                         shift_left(resize(doom_y, 14), 4);
            word_idx  := y_times80 + resize(doom_x(8 downto 2), 14);
            fb_raddr  <= unsigned(STD_LOGIC_VECTOR'(active_buf_pix & std_logic_vector(word_idx)));
        else
            fb_raddr  <= unsigned(STD_LOGIC_VECTOR'(active_buf_pix & "00000000000000"));
        end if;
    end process;

    -- Extract 8-bit indexed pixel from 32-bit BRAM word (Stage 1 -> Palette BRAM)
    process(fb_rdata, byte_sel_1)
    begin
        case byte_sel_1 is
            when "00"   => pal_raddr <= unsigned(fb_rdata(7 downto 0));
            when "01"   => pal_raddr <= unsigned(fb_rdata(15 downto 8));
            when "10"   => pal_raddr <= unsigned(fb_rdata(23 downto 16));
            when others => pal_raddr <= unsigned(fb_rdata(31 downto 24));
        end case;
    end process;

    -- Synchronous BRAM Reads (no reset on RAM reads -> clean RAMB36E1/RAMB18E1 inference)
    process(pix_clk)
    begin
        if rising_edge(pix_clk) then
            fb_rdata  <= fb_ram(to_integer(fb_raddr));
            pal_rdata <= pal_ram(to_integer(pal_raddr));
        end if;
    end process;

    -- CDC into pix_clk + VSYNC Buffer Flip + 3-Stage Aligned Pixel Pipeline
    process(pix_clk)
        variable anim_x : unsigned(9 downto 0);
    begin
        if rising_edge(pix_clk) then
            if pix_rst = '1' then
                swap_req_pix_s1  <= '0';
                swap_req_pix_s2  <= '0';
                disp_en_pix_s1   <= '0';
                disp_en_pix_s2   <= '0';
                led_sw_pix_s1    <= (others => '0');
                led_sw_pix_s2    <= (others => '0');
                active_buf_pix   <= '0';
                swap_ack_tog_pix <= '0';
                frame_cnt_pix    <= (others => '0');
                de_1 <= '0'; de_2 <= '0'; de_3 <= '0';
                hs_1 <= '1'; hs_2 <= '1'; hs_3 <= '1';
                vs_1 <= '1'; vs_2 <= '1'; vs_3 <= '1';
                in_vp_1 <= '0'; in_vp_2 <= '0';
                rgb_r <= (others => '0');
                rgb_g <= (others => '0');
                rgb_b <= (others => '0');
            else
                -- CDC synchronizers
                swap_req_pix_s1 <= swap_req_tog_axi;
                swap_req_pix_s2 <= swap_req_pix_s1;
                disp_en_pix_s1  <= disp_en_axi;
                disp_en_pix_s2  <= disp_en_pix_s1;
                led_sw_pix_s1   <= led_sw_axi;
                led_sw_pix_s2   <= led_sw_pix_s1;

                -- Tear-free page flip strictly at VBLANK start
                if vblank_start = '1' then
                    frame_cnt_pix <= frame_cnt_pix + 1;
                    if swap_req_pix_s2 /= swap_ack_tog_pix then
                        active_buf_pix   <= not active_buf_pix;
                        swap_ack_tog_pix <= swap_req_pix_s2;
                    end if;
                end if;

                -- Pipeline Stage 0 -> Stage 1
                h_cnt_1    <= h_cnt_0;
                v_cnt_1    <= v_cnt_0;
                byte_sel_1 <= h_cnt_0(2 downto 1); -- doom_x(1 downto 0)
                if (h_cnt_0 < 640 and v_cnt_0 >= 40 and v_cnt_0 < 440) then
                    in_vp_1 <= '1';
                else
                    in_vp_1 <= '0';
                end if;
                hs_1 <= hs_0;
                vs_1 <= vs_0;
                de_1 <= de_0;

                -- Pipeline Stage 1 -> Stage 2
                h_cnt_2 <= h_cnt_1;
                v_cnt_2 <= v_cnt_1;
                in_vp_2 <= in_vp_1;
                hs_2    <= hs_1;
                vs_2    <= vs_1;
                de_2    <= de_1;

                -- Pipeline Stage 2 -> Stage 3 (final RGB mux)
                hs_3 <= hs_2;
                vs_3 <= vs_2;
                de_3 <= de_2;

                if de_2 = '0' then
                    rgb_r <= (others => '0');
                    rgb_g <= (others => '0');
                    rgb_b <= (others => '0');
                elsif (sw_clean(3) = '1' or disp_en_pix_s2 = '0') then
                    -- Built-in SMPTE 8-bar test screen + moving white scan bar
                    -- Immediately verifies HDMI output even before Vitis boots DOOM
                    anim_x := resize(shift_left(frame_cnt_pix(7 downto 0), 2), 10);
                    if (v_cnt_2 >= 420 and v_cnt_2 < 452 and
                        h_cnt_2 >= anim_x and h_cnt_2 < anim_x + 48) then
                        rgb_r <= x"FF"; rgb_g <= x"FF"; rgb_b <= x"FF";
                    elsif (h_cnt_2 < 80) then
                        rgb_r <= x"E0"; rgb_g <= x"E0"; rgb_b <= x"E0"; -- White
                    elsif (h_cnt_2 < 160) then
                        rgb_r <= x"E0"; rgb_g <= x"E0"; rgb_b <= x"00"; -- Yellow
                    elsif (h_cnt_2 < 240) then
                        rgb_r <= x"00"; rgb_g <= x"E0"; rgb_b <= x"E0"; -- Cyan
                    elsif (h_cnt_2 < 320) then
                        rgb_r <= x"00"; rgb_g <= x"E0"; rgb_b <= x"00"; -- Green
                    elsif (h_cnt_2 < 400) then
                        rgb_r <= x"E0"; rgb_g <= x"00"; rgb_b <= x"E0"; -- Magenta
                    elsif (h_cnt_2 < 480) then
                        rgb_r <= x"E0"; rgb_g <= x"00"; rgb_b <= x"00"; -- Red
                    elsif (h_cnt_2 < 560) then
                        rgb_r <= x"00"; rgb_g <= x"00"; rgb_b <= x"E0"; -- Blue
                    else
                        rgb_r <= x"18"; rgb_g <= x"18"; rgb_b <= x"18"; -- Dark Gray
                    end if;
                elsif in_vp_2 = '1' then
                    -- Live DOOM 2x scaled pixel through 24-bit hardware Palette LUT
                    rgb_r <= pal_rdata(23 downto 16);
                    rgb_g <= pal_rdata(15 downto 8);
                    rgb_b <= pal_rdata(7 downto 0);
                else
                    -- Clean top/bottom 40px letterbox borders
                    rgb_r <= x"00";
                    rgb_g <= x"00";
                    rgb_b <= x"00";
                end if;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- 7. Zybo Z7-10 Status LEDs
    --    LED0 = HDMI MMCM Locked
    --    LED1 = DOOM Live Display Enabled
    --    LED2 = Fire Toggle (SW0) Active OR SW LED[2]
    --    LED3 = 60 Hz Heartbeat (~1 Hz blink) OR SW LED[3]
    ----------------------------------------------------------------------------
    led(0) <= mmcm_locked;
    led(1) <= disp_en_pix_s2 or led_sw_pix_s2(1);
    led(2) <= sw_clean(0) or led_sw_pix_s2(2);
    led(3) <= frame_cnt_pix(5) or led_sw_pix_s2(3);

    ----------------------------------------------------------------------------
    -- 8. Custom Pure-VHDL HDMI/DVI TMDS Transmitter PHY
    ----------------------------------------------------------------------------
    u_hdmi_phy : entity work.hdmi_tx_phy
        port map (
            pix_clk       => pix_clk,
            tmds_clk      => tmds_clk,
            rst           => pix_rst,
            red           => rgb_r,
            green         => rgb_g,
            blue          => rgb_b,
            hsync         => hs_3,
            vsync         => vs_3,
            de            => de_3,
            hdmi_tx_clk_p => hdmi_tx_clk_p,
            hdmi_tx_clk_n => hdmi_tx_clk_n,
            hdmi_tx_d_p   => hdmi_tx_d_p,
            hdmi_tx_d_n   => hdmi_tx_d_n
        );

end Behavioral;
