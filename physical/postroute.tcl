read_liberty /OpenROAD-flow-scripts/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db /project/design.odb
read_sdc /project/design_100MHz.sdc
read_spef /project/design.spef
report_units
check_setup -verbose > /output/constraints.rpt
report_checks -path_delay max -group_path_count 5 -digits 6 > /output/setup.rpt
report_checks -path_delay min -group_path_count 5 -digits 6 > /output/hold.rpt
puts "POSTROUTE_100MHZ_SETUP"
report_worst_slack -max -digits 6
puts "POSTROUTE_100MHZ_HOLD"
report_worst_slack -min -digits 6
report_clock_min_period -include_port_paths
report_power -digits 6 > /output/power_vectorless_100MHz.rpt
read_vcd -scope tb_memory_gemm/dut/mapped /project/workload.vcd
puts "ACTIVITY_ANNOTATION_BEGIN"
report_activity_annotation
puts "ACTIVITY_ANNOTATION_END"
report_power -digits 6 > /output/power_workload_100MHz.rpt
puts "PASS: Postroute timing and activity analysis completed"
exit
