# Each invocation starts a fresh timer with the selected cell and RC views.
read_liberty /project/corner.lib
read_db /project/design.odb
read_sdc /project/design.sdc
read_spef /project/design.spef
report_units
check_setup -verbose > /output/constraints.rpt
report_checks -path_delay max -group_path_count 5 -digits 6 > /output/setup.rpt
report_checks -path_delay min -group_path_count 5 -digits 6 > /output/hold.rpt
# The legacy raw-reset top has no timed async paths. The AXI boundary does:
# stage-two Q launches the qualified reset into all internal async controls.
report_checks -to [all_registers -async_pins] -path_delay max -group_path_count 5 -digits 6 > /output/recovery.rpt
report_checks -to [all_registers -async_pins] -path_delay min -group_path_count 5 -digits 6 > /output/removal.rpt
set sync_stages {}
set sync_locations {}
foreach inst [all_registers -cells] {
    if {![string match *release_pipe* [get_full_name $inst]]} { continue }
    set db_inst [sta::sta_to_db_inst $inst]
    lappend sync_stages [list [$db_inst getName] [$db_inst getLocation]]
    lappend sync_locations [$db_inst getLocation]
}
puts "RESET_SYNC_STAGES $sync_stages"
if {[llength $sync_locations]==2} {
    lassign [lindex $sync_locations 0] x0 y0
    lassign [lindex $sync_locations 1] x1 y1
    set dbu [[[ord::get_db] getTech] getDbUnitsPerMicron]
    puts "RESET_SYNC_SPACING_UM [expr {(abs($x0-$x1)+abs($y0-$y1))/double($dbu)}]"
}
set sync_data {}
foreach pin [all_registers -data_pins] {
    if {[string match *release_pipe* [get_full_name $pin]]} { lappend sync_data $pin }
}
if {[llength $sync_data]>0} {
    report_checks -to $sync_data -path_delay max -group_path_count 2 -digits 6 > /output/reset_sync_setup.rpt
}
puts "PVT_SETUP"
report_worst_slack -max -digits 6
puts "PVT_HOLD"
report_worst_slack -min -digits 6
puts "PASS: PVT analysis completed"
exit
