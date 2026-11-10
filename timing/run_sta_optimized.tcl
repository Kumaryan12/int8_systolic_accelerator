
# ============================================================
# INT8 SYSTOLIC ARRAY - OPTIMIZED NETLIST STA
# ============================================================
#
# Design     : 4x4 INT8 Systolic Array
# Technology : SKY130HD
# Corner     : TT, 25 C, 1.8 V
# Tool       : OpenSTA
#
# Purpose:
# Compare timing-driven synthesis against baseline synthesis.
#
# ============================================================

# ------------------------------------------------------------
# 1. PROJECT PATHS
# ------------------------------------------------------------

set script_dir [file dirname [file normalize [info script]]]

set root [file normalize [file join $script_dir ..]]

set lib_file [file join $root \
    lib/sky130_fd_sc_hd__tt_025C_1v80.lib]

set netlist_file [file join $root \
    build/systolic_sky130_timing.v]

set sdc_file [file join $root \
    constraints/systolic.sdc]

set report_dir [file join $root build]

file mkdir $report_dir

# ------------------------------------------------------------
# 2. CHECK INPUT FILES
# ------------------------------------------------------------

foreach input_file [list $lib_file $netlist_file $sdc_file] {

    if {![file isfile $input_file]} {
        error "Missing file: $input_file"
    }

}

puts "=========================================="
puts " OPTIMIZED SYSTOLIC ARRAY - OPENSTA"
puts "=========================================="

# ------------------------------------------------------------
# 3. LOAD LIBRARY
# ------------------------------------------------------------

read_liberty $lib_file

# ------------------------------------------------------------
# 4. LOAD OPTIMIZED NETLIST
# ------------------------------------------------------------

read_verilog $netlist_file

link_design systolic_array

# ------------------------------------------------------------
# 5. LOAD ORIGINAL TIMING CONSTRAINTS
# ------------------------------------------------------------

read_sdc $sdc_file

puts "Library : $lib_file"
puts "Netlist : $netlist_file"
puts "SDC     : $sdc_file"

# ------------------------------------------------------------
# 6. CHECK TIMING CONSTRAINTS
# ------------------------------------------------------------

check_setup -verbose > \
    [file join $report_dir sta_optimized_checks.rpt]

# ------------------------------------------------------------
# 7. SETUP TIMING PATHS
# ------------------------------------------------------------

report_checks \
    -path_delay max \
    -group_path_count 10 \
    -digits 3 \
    -fields {fanout capacitance slew net} \
    > [file join $report_dir sta_optimized_setup.rpt]

# ------------------------------------------------------------
# 8. HOLD TIMING PATHS
# ------------------------------------------------------------

report_checks \
    -path_delay min \
    -group_path_count 10 \
    -digits 3 \
    -fields {fanout capacitance slew net} \
    > [file join $report_dir sta_optimized_hold.rpt]

# ------------------------------------------------------------
# 9. SETUP TIMING METRICS
# ------------------------------------------------------------

puts "\n========== SETUP RESULTS =========="

puts "\nWorst setup slack:"
report_worst_slack -max -digits 3

puts "\nSetup WNS:"
report_wns -max -digits 3

puts "\nSetup TNS:"
report_tns -max -digits 3

# ------------------------------------------------------------
# 10. HOLD TIMING METRICS
# ------------------------------------------------------------

puts "\n========== HOLD RESULTS =========="

puts "\nWorst hold slack:"
report_worst_slack -min -digits 3

puts "\nHold WNS:"
report_wns -min -digits 3

puts "\nHold TNS:"
report_tns -min -digits 3

# ------------------------------------------------------------
# 11. MINIMUM CLOCK PERIOD
# ------------------------------------------------------------

puts "\n========== CLOCK PERFORMANCE =========="

report_clock_min_period -include_port_paths

# ------------------------------------------------------------
# 12. REPORT SUMMARY
# ------------------------------------------------------------

puts "\n=========================================="
puts " OPTIMIZED STA COMPLETED"
puts "=========================================="

puts "Clock target: 10 ns (100 MHz)"

puts "Reports generated:"
puts "  build/sta_optimized_checks.rpt"
puts "  build/sta_optimized_setup.rpt"
puts "  build/sta_optimized_hold.rpt"

puts ""
puts "NOTE:"
puts "Pre-placement timing only."
puts "No extracted routing parasitics."
puts "No physical clock tree."
puts "Results are not signoff timing."

puts "=========================================="

exit
