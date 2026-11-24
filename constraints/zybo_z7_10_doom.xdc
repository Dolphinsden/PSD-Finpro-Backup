##------------------------------------------------------------------------------
## File: zybo_z7_10_doom.xdc
## Board: Digilent Zybo Z7-10 (XC7Z010-1CLG400C)
## Tool:  AMD Vivado 2026.1
## Pinout verified against Digilent official Zybo-Z7-Master.xdc
##------------------------------------------------------------------------------

## 125 MHz Onboard System Clock (Bank 35)
set_property -dict { PACKAGE_PIN K17   IOSTANDARD LVCMOS33 } [get_ports { sysclk_125m }];
create_clock -add -name sys_clk_pin -period 8.000 -waveform {0 4} [get_ports { sysclk_125m }];

## Slide Switches (SW[0] = Fire Toggle, SW[1] = Use/Enter, SW[2] = Map/Weapon, SW[3] = HDMI Test Bars)
set_property -dict { PACKAGE_PIN G15   IOSTANDARD LVCMOS33 } [get_ports { sw[0] }];
set_property -dict { PACKAGE_PIN P15   IOSTANDARD LVCMOS33 } [get_ports { sw[1] }];
set_property -dict { PACKAGE_PIN W13   IOSTANDARD LVCMOS33 } [get_ports { sw[2] }];
set_property -dict { PACKAGE_PIN T16   IOSTANDARD LVCMOS33 } [get_ports { sw[3] }];

## Pushbuttons (BTN3=A Left, BTN2=W Forward, BTN1=S Back, BTN0=D Right)
set_property -dict { PACKAGE_PIN K18   IOSTANDARD LVCMOS33 } [get_ports { btn[0] }];
set_property -dict { PACKAGE_PIN P16   IOSTANDARD LVCMOS33 } [get_ports { btn[1] }];
set_property -dict { PACKAGE_PIN K19   IOSTANDARD LVCMOS33 } [get_ports { btn[2] }];
set_property -dict { PACKAGE_PIN Y16   IOSTANDARD LVCMOS33 } [get_ports { btn[3] }];

## Status LEDs (LED0=MMCM Lock, LED1=DOOM Active, LED2=Fire Active, LED3=60Hz Heartbeat)
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
set_property -dict { PACKAGE_PIN M15   IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
set_property -dict { PACKAGE_PIN G14   IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
set_property -dict { PACKAGE_PIN D18   IOSTANDARD LVCMOS33 } [get_ports { led[3] }];

## HDMI TX Differential TMDS Output (Bank 35, 3.3V TMDS_33)
set_property -dict { PACKAGE_PIN H16   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_clk_p }];
set_property -dict { PACKAGE_PIN H17   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_clk_n }];
set_property -dict { PACKAGE_PIN D19   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_d_p[0] }];
set_property -dict { PACKAGE_PIN D20   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_d_n[0] }];
set_property -dict { PACKAGE_PIN C20   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_d_p[1] }];
set_property -dict { PACKAGE_PIN B20   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_d_n[1] }];
set_property -dict { PACKAGE_PIN B19   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_d_p[2] }];
set_property -dict { PACKAGE_PIN A20   IOSTANDARD TMDS_33  } [get_ports { hdmi_tx_d_n[2] }];

##------------------------------------------------------------------------------
## Clock Domain Crossing Constraints
## Zynq FCLK_CLK0 (100 MHz AXI) and HDMI MMCM clocks (from 125 MHz sysclk)
## are asynchronous and safely bridged via 2-FF ASYNC_REG synchronizers and
## dual-clock True Dual-Port BRAMs inside zybo_doom_gpu_axi.vhd.
##------------------------------------------------------------------------------
set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks clk_fpga_0] \
    -group [get_clocks -include_generated_clocks sys_clk_pin]
