--------------------------------------------------------------------------------
-- File: tmds_encoder.vhd
-- Description: Full DVI 1.0 / HDMI TMDS 8b/10b encoder with transition
--              minimization and running DC disparity balancing.
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tmds_encoder is
    Port (
        clk  : in  STD_LOGIC;
        rst  : in  STD_LOGIC;
        de   : in  STD_LOGIC;
        ctrl : in  STD_LOGIC_VECTOR(1 downto 0);
        din  : in  STD_LOGIC_VECTOR(7 downto 0);
        dout : out STD_LOGIC_VECTOR(9 downto 0)
    );
end tmds_encoder;

architecture Behavioral of tmds_encoder is
    signal disparity : signed(4 downto 0) := (others => '0');

    function popcount8(v : STD_LOGIC_VECTOR(7 downto 0)) return integer is
        variable cnt : integer := 0;
    begin
        for i in 0 to 7 loop
            if v(i) = '1' then
                cnt := cnt + 1;
            end if;
        end loop;
        return cnt;
    end function;
begin

    process(clk)
        variable n1_d    : integer range 0 to 8;
        variable q_m     : STD_LOGIC_VECTOR(8 downto 0);
        variable n1_qm   : integer range 0 to 8;
        variable n0_qm   : integer range 0 to 8;
        variable diff_qm : integer range -8 to 8;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                disparity <= (others => '0');
                dout      <= "1101010100";
            elsif de = '0' then
                disparity <= (others => '0');
                case ctrl is
                    when "00"   => dout <= "1101010100";
                    when "01"   => dout <= "0010101011";
                    when "10"   => dout <= "0101010100";
                    when others => dout <= "1010101011";
                end case;
            else
                -- Stage 1: Minimize transitions (XOR vs XNOR)
                n1_d := popcount8(din);
                if (n1_d > 4) or (n1_d = 4 and din(0) = '0') then
                    q_m(0) := din(0);
                    for i in 1 to 7 loop
                        q_m(i) := q_m(i - 1) xnor din(i);
                    end loop;
                    q_m(8) := '0';
                else
                    q_m(0) := din(0);
                    for i in 1 to 7 loop
                        q_m(i) := q_m(i - 1) xor din(i);
                    end loop;
                    q_m(8) := '1';
                end if;

                -- Stage 2: Balance DC disparity
                n1_qm   := popcount8(q_m(7 downto 0));
                n0_qm   := 8 - n1_qm;
                diff_qm := n1_qm - n0_qm;

                if (disparity = 0) or (n1_qm = n0_qm) then
                    dout(9) <= not q_m(8);
                    dout(8) <= q_m(8);
                    if q_m(8) = '0' then
                        dout(7 downto 0) <= not q_m(7 downto 0);
                        disparity <= disparity - to_signed(diff_qm, 5);
                    else
                        dout(7 downto 0) <= q_m(7 downto 0);
                        disparity <= disparity + to_signed(diff_qm, 5);
                    end if;
                else
                    if ((disparity > 0) and (n1_qm > n0_qm)) or
                       ((disparity < 0) and (n0_qm > n1_qm)) then
                        dout(9)          <= '1';
                        dout(8)          <= q_m(8);
                        dout(7 downto 0) <= not q_m(7 downto 0);
                        if q_m(8) = '1' then
                            disparity <= disparity + to_signed(2 - diff_qm, 5);
                        else
                            disparity <= disparity - to_signed(diff_qm, 5);
                        end if;
                    else
                        dout(9)          <= '0';
                        dout(8)          <= q_m(8);
                        dout(7 downto 0) <= q_m(7 downto 0);
                        if q_m(8) = '0' then
                            disparity <= disparity + to_signed(diff_qm - 2, 5);
                        else
                            disparity <= disparity + to_signed(diff_qm, 5);
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

end Behavioral;
