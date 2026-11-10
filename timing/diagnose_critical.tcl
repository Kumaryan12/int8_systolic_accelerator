
# ============================================================
# INT8 SYSTOLIC ARRAY - CRITICAL PATH DIAGNOSIS
# ============================================================

set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set out_dir [file join $root build]

file mkdir $out_dir

# Load the same design and constraints as the baseline STA run.
read_liberty [file join $root \
    lib/sky130_fd_sc_hd__tt_025C_1v80.lib]

read_verilog [file join $root \
    build/systolic_sky130.v]

link_design systolic_array

read_sdc [file join $root \
    constraints/systolic.sdc]

puts "\n=========================================="
puts " CRITICAL PATH DIAGNOSIS"
puts "=========================================="

# ------------------------------------------------------------
# 1. Detailed worst setup paths
# ------------------------------------------------------------

report_checks \
    -path_delay max \
    -group_path_count 20 \
    -digits 3 \
    -fields {fanout capacitance slew net input_pin} \
    > [file join $out_dir critical_paths_detailed.rpt]

# ------------------------------------------------------------
# 2. Identify cell connections for the worst path
# ------------------------------------------------------------

set cell_report [file join $out_dir critical_cells.rpt]

report_instance _17814_ > $cell_report
report_instance _16427_ >> $cell_report
report_instance _16686_ >> $cell_report
report_instance _17699_ >> $cell_report

# ------------------------------------------------------------
# 3. Trace paths launched by the high-fanout register
# ------------------------------------------------------------

report_checks \
    -from [get_pins _17814_/Q] \
    -path_delay max \
    -group_path_count 10 \
    -digits 3 \
    -fields {fanout capacitance slew net} \
    > [file join $out_dir critical_launch_paths.rpt]

# ------------------------------------------------------------
# 4. Trace paths through the heavily loaded NOR gate
# ------------------------------------------------------------

report_checks \
    -through [get_pins _16427_/Y] \
    -path_delay max \
    -group_path_count 10 \
    -digits 3 \
    -fields {fanout capacitance slew net} \
    > [file join $out_dir critical_nor_paths.rpt]

# ------------------------------------------------------------
# 5. Timing summary
# ------------------------------------------------------------

puts "\nWorst setup slack:"
report_worst_slack -max -digits 3

puts "\nWorst hold slack:"
report_worst_slack -min -digits 3

puts "\nMinimum clock period:"
report_clock_min_period -include_port_paths

puts "\nGenerated diagnostic reports:"
puts "  build/critical_paths_detailed.rpt"
puts "  build/critical_cells.rpt"
puts "  build/critical_launch_paths.rpt"
puts "  build/critical_nor_paths.rpt"

puts "\nDIAGNOSIS COMPLETE"

exit
