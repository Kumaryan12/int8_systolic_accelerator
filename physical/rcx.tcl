# Re-extract the exact routed geometry with a selected calibrated RC model.
set corner $::env(RCX_CORNER)
read_liberty /OpenROAD-flow-scripts/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_db /project/design.odb
define_process_corner -ext_model_index 0 $corner
set_extraction_rules_file /project/rules.$corner
extract_parasitics -max_res 50 -coupling_threshold 0.1
write_spef /output/$corner.spef
puts "PASS: Independent RC extraction completed"
exit
