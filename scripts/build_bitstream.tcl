################################################################################
# File: scripts/build_bitstream.tcl
# Description: Synthesizes, implements, generates bitstream (.bit), and exports
#              hardware platform (.xsa) for Vitis 2026.1.
#
# Usage:
#   vivado -mode batch -source scripts/build_bitstream.tcl
################################################################################

set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file normalize "$script_dir/.."]
set xpr_file   "$root_dir/vivado_proj/zybo_doom_vhdl.xpr"
set out_dir    "$root_dir/build"

file mkdir $out_dir

if {![file exists $xpr_file]} {
    puts "Project not found; running create_project.tcl first..."
    source "$script_dir/create_project.tcl"
} else {
    open_project $xpr_file
}

puts "=== Starting Synthesis ==="
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "Synthesis failed! Check vivado_proj/zybo_doom_vhdl.runs/synth_1/runme.log"
}

puts "=== Starting Implementation & Bitstream Generation ==="
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "Implementation/Bitstream failed! Check vivado_proj/zybo_doom_vhdl.runs/impl_1/runme.log"
}

# Copy .bit and export .xsa (with bitstream included) for Vitis 2026.1
set bit_src "$root_dir/vivado_proj/zybo_doom_vhdl.runs/impl_1/system_wrapper.bit"
file copy -force $bit_src "$out_dir/zybo_doom.bit"
write_hw_platform -fixed -include_bit -force -file "$out_dir/zybo_doom.xsa"

puts "=== Hardware Build Complete ==="
puts "Bitstream: $out_dir/zybo_doom.bit"
puts "XSA:       $out_dir/zybo_doom.xsa"
