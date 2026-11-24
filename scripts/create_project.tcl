################################################################################
# File: scripts/create_project.tcl
# Description: One-command Vivado 2026.1 project & Block Design generator for
#              DOOM on Digilent Zybo Z7-10 (100% VHDL PL + Zynq-7010 PS).
#
# Usage (from Vivado Tcl Console or Windows Command Prompt):
#   vivado -mode batch -source scripts/create_project.tcl
#   (or in Vivado GUI: Tools -> Run Tcl Script -> select create_project.tcl)
################################################################################

set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file normalize "$script_dir/.."]
set proj_name  "zybo_doom_vhdl"
set proj_dir   "$root_dir/vivado_proj"

puts "=== Creating Vivado Project: $proj_name ==="
puts "Project directory: $proj_dir"

create_project $proj_name $proj_dir -part xc7z010clg400-1 -force

# Strictly generate VHDL wrappers (no Verilog)
set_property target_language VHDL [current_project]
set_property simulator_language VHDL [current_project]

# Auto-detect Digilent Zybo Z7-10 board files if installed
set zybo_boards [get_board_parts -quiet *zybo-z7-10*]
set use_board_preset 0
if {[llength $zybo_boards] > 0} {
    set chosen_board [lindex $zybo_boards end]
    puts "Found Digilent board part: $chosen_board"
    set_property board_part $chosen_board [current_project]
    set use_board_preset 1
} else {
    puts "Digilent Zybo Z7-10 board files not installed - applying built-in Z7-10 PS/DDR3 preset."
}

# Add all pure-VHDL RTL sources
add_files -norecurse [list \
    "$root_dir/src/clock_gen_hdmi.vhd" \
    "$root_dir/src/input_debouncer.vhd" \
    "$root_dir/src/vga_timing_gen.vhd" \
    "$root_dir/src/tmds_encoder.vhd" \
    "$root_dir/src/hdmi_tx_phy.vhd" \
    "$root_dir/src/zybo_doom_gpu_axi.vhd" \
]

# Add Zybo Z7-10 XDC constraints
add_files -fileset constrs_1 -norecurse "$root_dir/constraints/zybo_z7_10_doom.xdc"

# Add VHDL simulation testbench
add_files -fileset sim_1 -norecurse "$root_dir/sim/tb_zybo_doom_gpu.vhd"
set_property top tb_zybo_doom_gpu [get_filesets sim_1]

update_compile_order -fileset sources_1

################################################################################
# Create Zynq-7010 + Custom VHDL GPU Block Design
################################################################################
create_bd_design "system"

# 1. Zynq-7010 Processing System
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0

if {$use_board_preset == 1} {
    apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
        -config {apply_board_preset "1" make_external "FIXED_IO, DDR" Master "Disable" Slave "Disable"} \
        [get_bd_cells processing_system7_0]
} else {
    # Exact Zybo Z7-10 Rev B/C PS configuration (33.333 MHz crystal, 1GB MT41K256M16 DDR3L, UART1 MIO 48-49)
    set_property -dict [list \
        CONFIG.PCW_CRYSTAL_PERIPHERAL_FREQMHZ {33.333333} \
        CONFIG.PCW_APU_PERIPHERAL_FREQMHZ {667} \
        CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 1.8V} \
        CONFIG.PCW_UIPARAM_DDR_MEMORY_TYPE {DDR 3} \
        CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41K256M16 RE-125} \
        CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {32 Bit} \
        CONFIG.PCW_UIPARAM_DDR_DRAM_WIDTH {16 Bits} \
        CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_0 {-0.050} \
        CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_1 {-0.044} \
        CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_2 {-0.035} \
        CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_3 {-0.100} \
        CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY0 {0.221} \
        CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY1 {0.222} \
        CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY2 {0.217} \
        CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY3 {0.244} \
        CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
        CONFIG.PCW_UART1_UART1_IO {MIO 48 .. 49} \
        CONFIG.PCW_UART_PERIPHERAL_FREQMHZ {100} \
        CONFIG.PCW_EN_CLK0_PORT {1} \
        CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
        CONFIG.PCW_USE_M_AXI_GP0 {1} \
    ] [get_bd_cells processing_system7_0]

    apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
        -config {make_external "FIXED_IO, DDR" Master "Disable" Slave "Disable"} \
        [get_bd_cells processing_system7_0]
}

# Guarantee M_AXI_GP0, 100 MHz FCLK_CLK0, and UART1 are enabled even if board preset differed
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART1_UART1_IO {MIO 48 .. 49} \
] [get_bd_cells processing_system7_0]

# 2. Add Custom Pure-VHDL DOOM GPU Module Reference
create_bd_cell -type module -reference zybo_doom_gpu_axi zybo_doom_gpu_0

# 3. Connect Zynq M_AXI_GP0 -> zybo_doom_gpu_0/s_axi (auto creates AXI Interconnect + Reset)
apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config { \
        Clk_master {/processing_system7_0/FCLK_CLK0 (100 MHz)} \
        Clk_slave  {Auto} \
        Clk_xbar   {Auto} \
        Master     {/processing_system7_0/M_AXI_GP0} \
        Slave      {/zybo_doom_gpu_0/s_axi} \
        ddr_seg    {Auto} \
        intc_ip    {Auto} \
        master_apm {0} \
    } [get_bd_intf_pins zybo_doom_gpu_0/s_axi]

# 4. Export Board Ports matching zybo_z7_10_doom.xdc
create_bd_port -dir I -type clk -freq_hz 125000000 sysclk_125m
create_bd_port -dir I -from 3 -to 0 btn
create_bd_port -dir I -from 3 -to 0 sw
create_bd_port -dir O -from 3 -to 0 led
create_bd_port -dir O hdmi_tx_clk_p
create_bd_port -dir O hdmi_tx_clk_n
create_bd_port -dir O -from 2 -to 0 hdmi_tx_d_p
create_bd_port -dir O -from 2 -to 0 hdmi_tx_d_n

connect_bd_net [get_bd_ports sysclk_125m]   [get_bd_pins zybo_doom_gpu_0/sysclk_125m]
connect_bd_net [get_bd_ports btn]           [get_bd_pins zybo_doom_gpu_0/btn]
connect_bd_net [get_bd_ports sw]            [get_bd_pins zybo_doom_gpu_0/sw]
connect_bd_net [get_bd_ports led]           [get_bd_pins zybo_doom_gpu_0/led]
connect_bd_net [get_bd_ports hdmi_tx_clk_p] [get_bd_pins zybo_doom_gpu_0/hdmi_tx_clk_p]
connect_bd_net [get_bd_ports hdmi_tx_clk_n] [get_bd_pins zybo_doom_gpu_0/hdmi_tx_clk_n]
connect_bd_net [get_bd_ports hdmi_tx_d_p]   [get_bd_pins zybo_doom_gpu_0/hdmi_tx_d_p]
connect_bd_net [get_bd_ports hdmi_tx_d_n]   [get_bd_pins zybo_doom_gpu_0/hdmi_tx_d_n]

# 5. Lock AXI Address Map to 0x43C0_0000 (128 KB window) to match doomgeneric_zybo.c
assign_bd_address
set gpu_seg [get_bd_addr_segs processing_system7_0/Data/SEG_zybo_doom_gpu_0_reg0]
if {[llength $gpu_seg] == 0} {
    set gpu_seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces processing_system7_0/Data] *zybo_doom_gpu_0*]
}
set_property range 128K $gpu_seg
set_property offset 0x43C00000 $gpu_seg

regenerate_bd_layout
validate_bd_design
save_bd_design

# 6. Generate Pure-VHDL Top Wrapper (system_wrapper.vhd)
set bd_file [get_files system.bd]
set wrapper_path [make_wrapper -files $bd_file -top]
add_files -norecurse $wrapper_path
set_property top system_wrapper [current_fileset]
update_compile_order -fileset sources_1

puts "=== Project created successfully! ==="
puts "Next: run scripts/build_bitstream.tcl (or click 'Generate Bitstream' in Vivado GUI)."
