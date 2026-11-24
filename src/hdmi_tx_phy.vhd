--------------------------------------------------------------------------------
-- File: hdmi_tx_phy.vhd
-- Description: Pure VHDL HDMI/DVI transmitter PHY for Xilinx 7-Series (Zybo Z7-10).
--              Instantiates 3 TMDS encoders + 4 cascaded 10:1 DDR OSERDESE2
--              serializers + 4 OBUFDS differential output buffers (TMDS_33).
--              Channel mapping (DVI/HDMI standard):
--                Lane 0 = Blue  + HSYNC/VSYNC control
--                Lane 1 = Green
--                Lane 2 = Red
--                Clock  = 10'b0000011111 pattern
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

library UNISIM;
use UNISIM.VComponents.ALL;

entity hdmi_tx_phy is
    Port (
        pix_clk       : in  STD_LOGIC;
        tmds_clk      : in  STD_LOGIC;
        rst           : in  STD_LOGIC;
        red           : in  STD_LOGIC_VECTOR(7 downto 0);
        green         : in  STD_LOGIC_VECTOR(7 downto 0);
        blue          : in  STD_LOGIC_VECTOR(7 downto 0);
        hsync         : in  STD_LOGIC;
        vsync         : in  STD_LOGIC;
        de            : in  STD_LOGIC;
        hdmi_tx_clk_p : out STD_LOGIC;
        hdmi_tx_clk_n : out STD_LOGIC;
        hdmi_tx_d_p   : out STD_LOGIC_VECTOR(2 downto 0);
        hdmi_tx_d_n   : out STD_LOGIC_VECTOR(2 downto 0)
    );
end hdmi_tx_phy;

architecture Behavioral of hdmi_tx_phy is
    type tmds_array_t is array (0 to 3) of STD_LOGIC_VECTOR(9 downto 0);
    signal tmds_words : tmds_array_t;

    signal ctrl_ch0   : STD_LOGIC_VECTOR(1 downto 0);
    signal serial_out : STD_LOGIC_VECTOR(3 downto 0);
    signal shift1     : STD_LOGIC_VECTOR(3 downto 0);
    signal shift2     : STD_LOGIC_VECTOR(3 downto 0);
begin

    ctrl_ch0 <= vsync & hsync;

    -- Channel 0: Blue + HSYNC/VSYNC
    u_enc_b : entity work.tmds_encoder
        port map (
            clk  => pix_clk,
            rst  => rst,
            de   => de,
            ctrl => ctrl_ch0,
            din  => blue,
            dout => tmds_words(0)
        );

    -- Channel 1: Green
    u_enc_g : entity work.tmds_encoder
        port map (
            clk  => pix_clk,
            rst  => rst,
            de   => de,
            ctrl => "00",
            din  => green,
            dout => tmds_words(1)
        );

    -- Channel 2: Red
    u_enc_r : entity work.tmds_encoder
        port map (
            clk  => pix_clk,
            rst  => rst,
            de   => de,
            ctrl => "00",
            din  => red,
            dout => tmds_words(2)
        );

    -- Channel 3: TMDS Pixel Clock (exact 50% duty cycle square wave)
    tmds_words(3) <= "0000011111";

    -- Generate 4 identical 10:1 DDR OSERDESE2 Master/Slave cascades (UG471)
    gen_serdes : for i in 0 to 3 generate
        u_oserdes_master : OSERDESE2
            generic map (
                DATA_RATE_OQ   => "DDR",
                DATA_RATE_TQ   => "SDR",
                DATA_WIDTH     => 10,
                INIT_OQ        => '0',
                INIT_TQ        => '0',
                SERDES_MODE    => "MASTER",
                SRVAL_OQ       => '0',
                SRVAL_TQ       => '0',
                TBYTE_CTL      => "FALSE",
                TBYTE_SRC      => "FALSE",
                TRISTATE_WIDTH => 1
            )
            port map (
                OFB       => open,
                OQ        => serial_out(i),
                SHIFTOUT1 => open,
                SHIFTOUT2 => open,
                TBYTEOUT  => open,
                TFB       => open,
                TQ        => open,
                CLK       => tmds_clk,
                CLKDIV    => pix_clk,
                D1        => tmds_words(i)(0),
                D2        => tmds_words(i)(1),
                D3        => tmds_words(i)(2),
                D4        => tmds_words(i)(3),
                D5        => tmds_words(i)(4),
                D6        => tmds_words(i)(5),
                D7        => tmds_words(i)(6),
                D8        => tmds_words(i)(7),
                OCE       => '1',
                RST       => rst,
                SHIFTIN1  => shift1(i),
                SHIFTIN2  => shift2(i),
                T1        => '0',
                T2        => '0',
                T3        => '0',
                T4        => '0',
                TBYTEIN   => '0',
                TCE       => '0'
            );

        u_oserdes_slave : OSERDESE2
            generic map (
                DATA_RATE_OQ   => "DDR",
                DATA_RATE_TQ   => "SDR",
                DATA_WIDTH     => 10,
                INIT_OQ        => '0',
                INIT_TQ        => '0',
                SERDES_MODE    => "SLAVE",
                SRVAL_OQ       => '0',
                SRVAL_TQ       => '0',
                TBYTE_CTL      => "FALSE",
                TBYTE_SRC      => "FALSE",
                TRISTATE_WIDTH => 1
            )
            port map (
                OFB       => open,
                OQ        => open,
                SHIFTOUT1 => shift1(i),
                SHIFTOUT2 => shift2(i),
                TBYTEOUT  => open,
                TFB       => open,
                TQ        => open,
                CLK       => tmds_clk,
                CLKDIV    => pix_clk,
                D1        => '0',
                D2        => '0',
                D3        => tmds_words(i)(8),
                D4        => tmds_words(i)(9),
                D5        => '0',
                D6        => '0',
                D7        => '0',
                D8        => '0',
                OCE       => '1',
                RST       => rst,
                SHIFTIN1  => '0',
                SHIFTIN2  => '0',
                T1        => '0',
                T2        => '0',
                T3        => '0',
                T4        => '0',
                TBYTEIN   => '0',
                TCE       => '0'
            );
    end generate;

    -- Differential TMDS output buffers
    gen_obuf_data : for i in 0 to 2 generate
        u_obuf_d : OBUFDS
            generic map (IOSTANDARD => "TMDS_33")
            port map (
                I  => serial_out(i),
                O  => hdmi_tx_d_p(i),
                OB => hdmi_tx_d_n(i)
            );
    end generate;

    u_obuf_clk : OBUFDS
        generic map (IOSTANDARD => "TMDS_33")
        port map (
            I  => serial_out(3),
            O  => hdmi_tx_clk_p,
            OB => hdmi_tx_clk_n
        );

end Behavioral;
