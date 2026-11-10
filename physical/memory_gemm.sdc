# Memory-backed host interface. Units follow the SKY130 platform (ns, pF).
create_clock -name core_clk -period 20.0 [get_ports clk]
set_clock_uncertainty -setup 0.20 [get_clocks core_clk]
set_clock_uncertainty -hold 0.10 [get_clocks core_clk]
set_clock_transition 0.10 [get_clocks core_clk]

set synchronous_inputs [get_ports {load_valid load_bank load_data* load_tag* load_last result_ready}]
set_input_delay -clock core_clk -max 2.0 $synchronous_inputs
set_input_delay -clock core_clk -min 0.2 $synchronous_inputs
set_input_transition 0.10 $synchronous_inputs
set_output_delay -clock core_clk -max 2.0 [all_outputs]
set_output_delay -clock core_clk -min 0.2 [all_outputs]
set_load 0.005 [all_outputs]

# External asynchronous reset release is not timed by this prototype flow.
# This is an explicit exception, not reset recovery/removal signoff. A target
# integration must define safe deassertion/synchronization and verify its tree.
set_false_path -from [get_ports rst_n]
