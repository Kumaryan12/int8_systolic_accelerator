
# ============================================================
# INT8 SYSTOLIC ARRAY - CLEAN NETLIST STA
# ============================================================
#
# Design     : 4x4 Signed INT8 Systolic Array
# Technology : SKY130HD
# Corner     : Typical, 25 C, 1.8 V
# Tool       : OpenSTA
#
# Purpose:
#   Analyze the timing-driven netlist after excluding
#   clock-tree and specialized low-power cells.
#
# ============================================================

# ------------------------------------------------------------
# 1. PROJECT PATHS
# ------------------------------------------------------------

set script_dir [file dirname [file normalize [info script]]]
set project_root [file normalize [file join $script_dir ..]]

set lib_file [file join $project_root \
    lib/sky130_fd_sc_hd__tt_025C_1v80.lib]

set netlist_file [file join $project_root \
    build/systolic_sky130_clean.v]

set sdc_file [file join $project_root \
    constraints/systolic.sdc]

set report_dir [file join $project_root build]

if {[info exists ::env(NETLIST_FILE)]} {
    set netlist_file $::env(NETLIST_FILE)
}
if {[info exists ::env(REPORT_DIR)]} {
    set report_dir $::env(REPORT_DIR)
}

file mkdir $report_dir

# ------------------------------------------------------------
# 2. CHECK REQUIRED FILES
# ------------------------------------------------------------

foreach input_file [list $lib_file $netlist_file $sdc_file] {

    if {![file isfile $input_file]} {
        error "Required file not found: $input_file"
    }

}

puts "============================================"
puts " CLEAN SKY130 SYSTOLIC ARRAY - OPENSTA"
puts "============================================"

puts "Library : $lib_file"
puts "Netlist : $netlist_file"
puts "SDC     : $sdc_file"

# ------------------------------------------------------------
# 3. LOAD LIBERTY TIMING LIBRARY
# ------------------------------------------------------------

read_liberty $lib_file

# ------------------------------------------------------------
# 4. LOAD CLEAN TECHNOLOGY-MAPPED NETLIST
# ------------------------------------------------------------

read_verilog $netlist_file

link_design systolic_array

# ------------------------------------------------------------
# 5. APPLY TIMING CONSTRAINTS
# ------------------------------------------------------------

read_sdc $sdc_file

# ------------------------------------------------------------
# 6. CHECK TIMING CONSTRAINTS
# ------------------------------------------------------------

puts "\n========== CONSTRAINT CHECK =========="

check_setup -verbose > \
    [file join $report_dir sta_clean_constraints.rpt]

puts "Saved: build/sta_clean_constraints.rpt"

# ------------------------------------------------------------
# 7. SETUP TIMING PATHS
# ------------------------------------------------------------

puts "\n========== SETUP PATH ANALYSIS =========="

report_checks \
    -path_delay max \
    -group_path_count 10 \
    -digits 3 \
    -fields {fanout capacitance slew net} \
    > [file join $report_dir sta_clean_setup.rpt]

puts "Saved: build/sta_clean_setup.rpt"

# ------------------------------------------------------------
# 8. HOLD TIMING PATHS
# ------------------------------------------------------------

puts "\n========== HOLD PATH ANALYSIS =========="

report_checks \
    -path_delay min \
    -group_path_count 10 \
    -digits 3 \
    -fields {fanout capacitance slew net} \
    > [file join $report_dir sta_clean_hold.rpt]

puts "Saved: build/sta_clean_hold.rpt"

# ------------------------------------------------------------
# 9. SETUP SLACK SUMMARY
# ------------------------------------------------------------

puts "\n========== SETUP TIMING RESULTS =========="

puts "\nWorst setup slack:"
report_worst_slack -max -digits 3

puts "\nSetup WNS:"
report_wns -max -digits 3

puts "\nSetup TNS:"
report_tns -max -digits 3

# ------------------------------------------------------------
# 10. HOLD SLACK SUMMARY
# ------------------------------------------------------------

puts "\n========== HOLD TIMING RESULTS =========="

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
# 12. FINISH
# ------------------------------------------------------------

puts "\n============================================"
puts " CLEAN NETLIST STA COMPLETE"
puts "============================================"

puts "Target clock period: 10 ns"
puts "Target frequency: 100 MHz"

puts "Analysis assumptions:"
puts "  SKY130HD TT, 25 C, 1.8 V"
puts "  Ideal clock network"
puts "  No extracted interconnect parasitics"
puts "  No physical placement or routing"

puts "\nGenerated reports:"
puts "  build/sta_clean_constraints.rpt"
puts "  build/sta_clean_setup.rpt"
puts "  build/sta_clean_hold.rpt"

puts "============================================"

exit
