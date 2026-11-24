--------------------------------------------------------------------------------
-- File: input_debouncer.vhd
-- Description: 2-FF metastability synchronizer + ~12 ms glitch-free debouncer
--              for Zybo Z7-10 pushbuttons (BTN[0..3]) and slide switches (SW[0..3]).
-- Clock: 25.2083 MHz (pix_clk)
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity input_debouncer is
    Generic (
        WIDTH        : integer := 8;
        DEBOUNCE_MAX : integer := 300000  -- ~11.9 ms @ 25.2 MHz
    );
    Port (
        clk      : in  STD_LOGIC;
        rst      : in  STD_LOGIC;
        raw_in   : in  STD_LOGIC_VECTOR(WIDTH - 1 downto 0);
        clean_out: out STD_LOGIC_VECTOR(WIDTH - 1 downto 0)
    );
end input_debouncer;

architecture Behavioral of input_debouncer is
    signal sync_0 : STD_LOGIC_VECTOR(WIDTH - 1 downto 0) := (others => '0');
    signal sync_1 : STD_LOGIC_VECTOR(WIDTH - 1 downto 0) := (others => '0');
    signal state  : STD_LOGIC_VECTOR(WIDTH - 1 downto 0) := (others => '0');

    type cnt_array_t is array (0 to WIDTH - 1) of integer range 0 to DEBOUNCE_MAX;
    signal cnt : cnt_array_t := (others => 0);
begin

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                sync_0 <= (others => '0');
                sync_1 <= (others => '0');
                state  <= (others => '0');
                cnt    <= (others => 0);
            else
                sync_0 <= raw_in;
                sync_1 <= sync_0;

                for i in 0 to WIDTH - 1 loop
                    if sync_1(i) = state(i) then
                        cnt(i) <= 0;
                    else
                        if cnt(i) = DEBOUNCE_MAX then
                            state(i) <= sync_1(i);
                            cnt(i)   <= 0;
                        else
                            cnt(i) <= cnt(i) + 1;
                        end if;
                    end if;
                end loop;
            end if;
        end if;
    end process;

    clean_out <= state;

end Behavioral;
