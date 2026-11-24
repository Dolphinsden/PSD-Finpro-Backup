################################################################################
# File: scripts/run_doom_jtag.tcl
# Description: Programs the Zybo Z7-10 FPGA bitstream, initializes Zynq PS/DDR3,
#              downloads build/zybo_doom.elf (with embedded DOOM1.WAD) over JTAG,
#              and starts DOOM automatically.
#
# Usage (from Vitis / Vivado 2026.1 Command Prompt):
#   xsdb scripts/run_doom_jtag.tcl
################################################################################

set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file normalize "$script_dir/.."]
set bit_file   "$root_dir/build/zybo_doom.bit"
set elf_file   "$root_dir/build/zybo_doom.elf"
set ps7_init   "$root_dir/vitis_ws/zybo_doom_plat/hw/sdt/ps7_init.tcl"

if {![file exists $ps7_init]} {
    set ps7_init "$root_dir/vitis_ws/zybo_doom_plat/hw/ps7_init.tcl"
}

if {![file exists $bit_file]} {
    error "Missing $bit_file — build Vivado bitstream first."
}
if {![file exists $elf_file]} {
    error "Missing $elf_file — build Vitis ELF first."
}

connect
puts "=== [1/4] Programming FPGA Bitstream ($bit_file) ==="
targets -set -nocase -filter {name =~ "*xc7z010*"}
fpga -file $bit_file

puts "=== [2/4] Initializing Zynq-7010 PS & 1 GB DDR3 ==="
targets -set -nocase -filter {name =~ "*ARM*#0"}
rst -processor
source $ps7_init
ps7_init
ps7_post_config

puts "=== [3/4] Downloading DOOM + Embedded DOOM1.WAD to DDR3 ==="
dow $elf_file

puts "=== [4/4] Launching DOOM! ==="
con
puts "DOOM is now running on HDMI! Start tools/doom_controller.py for WASD+Z controls."
