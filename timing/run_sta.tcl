
# ============================================================
# INT8 SYSTOLIC ARRAY - STATIC TIMING ANALYSIS
# ============================================================
#
# Design      : 4x4 INT8 Systolic Array
# Technology  : SKY130HD
# Corner      : Typical, 25 C, 1.8 V
# Tool        : OpenSTA
#
# Analysis:
#   1. Load standard-cell timing library
#   2. Load synthesized gate-level netlist
#   3. Apply SDC timing constraints
#   4. Check timing constraints
#   5. Analyze setup timing
#   6. Analyze hold timing
#   7. Report WNS, TNS and minimum clock period
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
    build/systolic_sky130.v]

set sdc_file [file join $project_root \
    constraints/systolic.sdc]

set report_dir [file join $project_root build]

file mkdir $report_dir

# Check required input files
foreach input_file [list $lib_file $netlist_file $sdc_file] {
    if {![file isfile $input_file]} {
        error "Required input file not found: $input_file"
    }
}

puts "============================================"
puts " INT8 SYSTOLIC ARRAY - OPENSTA"
puts "============================================"

puts "Library : $lib_file"
puts "Netlist : $netlist_file"
puts "SDC     : $sdc_file"

# ------------------------------------------------------------
# 2. LOAD SKY130 STANDARD CELL LIBRARY
# ------------------------------------------------------------

puts "\n[format {%s} {STEP 1: Loading Liberty library}]"

read_liberty $lib_file

# ------------------------------------------------------------
# 3. LOAD SYNTHESIZED VERILOG NETLIST
# ------------------------------------------------------------

puts "\n[format {%s} {STEP 2: Loading mapped netlist}]"

read_verilog $netlist_file

# ------------------------------------------------------------
# 4. LINK DESIGN
# ------------------------------------------------------------

puts "\n[format {%s} {STEP 3: Linking design}]"

link_design systolic_array

# ------------------------------------------------------------
# 5. APPLY TIMING CONSTRAINTS
# ------------------------------------------------------------

puts "\n[format {%s} {STEP 4: Loading SDC constraints}]"

read_sdc $sdc_file

# ------------------------------------------------------------
# 6. REPORT UNITS
# ------------------------------------------------------------

puts "\n========== TIMING UNITS =========="

report_units

# ------------------------------------------------------------
# 7. CHECK CONSTRAINT COMPLETENESS
# ------------------------------------------------------------

puts "\n========== CONSTRAINT CHECK =========="

check_setup -verbose > \
    [file join $report_dir sta_constraint_checks.rpt]

puts "Constraint check saved to:"
puts "build/sta_constraint_checks.rpt"

# ------------------------------------------------------------
# 8. SETUP TIMING ANALYSIS
# ------------------------------------------------------------

puts "\n========== SETUP TIMING =========="

report_checks \
    -path_delay max \
    -group_path_count 10 \
    -digits 3 \
    -fields {slew capacitance fanout} \
    > [file join $report_dir sta_setup_paths.rpt]

puts "Setup timing paths saved to:"
puts "build/sta_setup_paths.rpt"

# ------------------------------------------------------------
# 9. HOLD TIMING ANALYSIS
# ------------------------------------------------------------

puts "\n========== HOLD TIMING =========="

report_checks \
    -path_delay min \
    -group_path_count 10 \
    -digits 3 \
    -fields {slew capacitance fanout} \
    > [file join $report_dir sta_hold_paths.rpt]

puts "Hold timing paths saved to:"
puts "build/sta_hold_paths.rpt"

# ------------------------------------------------------------
# 10. WORST SLACK
# ------------------------------------------------------------

puts "\n========== WORST SETUP SLACK =========="

report_worst_slack -max -digits 3

puts "\n========== WORST HOLD SLACK =========="

report_worst_slack -min -digits 3

# ------------------------------------------------------------
# 11. WORST NEGATIVE SLACK
# ------------------------------------------------------------

puts "\n========== SETUP WNS =========="

report_wns -max -digits 3

puts "\n========== HOLD WNS =========="

report_wns -min -digits 3

# ------------------------------------------------------------
# 12. TOTAL NEGATIVE SLACK
# ------------------------------------------------------------

puts "\n========== SETUP TNS =========="

report_tns -max -digits 3

puts "\n========== HOLD TNS =========="

report_tns -min -digits 3

# ------------------------------------------------------------
# 13. MINIMUM CLOCK PERIOD
# ------------------------------------------------------------

puts "\n========== MINIMUM CLOCK PERIOD =========="

report_clock_min_period -include_port_paths

# ------------------------------------------------------------
# 14. ANALYSIS LIMITATIONS
# ------------------------------------------------------------

puts "\n============================================"
puts " STA ANALYSIS COMPLETED"
puts "============================================"

puts "Analysis corner: TT, 25 C, 1.8 V"
puts "Requested clock period: 10 ns"

puts "This is pre-placement static timing analysis."
puts "No extracted routing parasitics are included."
puts "The clock network is not physically implemented."
puts "Reset recovery/removal must be reviewed separately."

puts "Generated reports:"
puts "  build/sta_constraint_checks.rpt"
puts "  build/sta_setup_paths.rpt"
puts "  build/sta_hold_paths.rpt"

puts "============================================"

exit
