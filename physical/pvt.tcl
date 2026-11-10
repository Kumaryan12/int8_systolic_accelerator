# Each invocation starts a fresh timer; use the same extracted RC at every PVT.
read_liberty /project/corner.lib
read_db /project/design.odb
read_sdc /project/design.sdc
read_spef /project/design.spef
report_units
check_setup -verbose > /output/constraints.rpt
report_checks -path_delay max -group_path_count 5 -digits 6 > /output/setup.rpt
report_checks -path_delay min -group_path_count 5 -digits 6 > /output/hold.rpt
puts "PVT_SETUP"
report_worst_slack -max -digits 6
puts "PVT_HOLD"
report_worst_slack -min -digits 6
puts "PASS: PVT analysis completed"
exit
