# Processor boundary, same 50 MHz target and external budgets as the stream top.
create_clock -name core_clk -period 20.0 [get_ports aclk]
set_clock_uncertainty -setup 0.20 [get_clocks core_clk]
set_clock_uncertainty -hold 0.10 [get_clocks core_clk]
set_clock_transition 0.10 [get_clocks core_clk]
set synchronous_inputs [get_ports {s_axi_awaddr* s_axi_awprot* s_axi_awvalid s_axi_wdata* s_axi_wstrb* s_axi_wvalid s_axi_bready s_axi_araddr* s_axi_arprot* s_axi_arvalid s_axi_rready}]
set_input_delay -clock core_clk -max 2.0 $synchronous_inputs
set_input_delay -clock core_clk -min 0.2 $synchronous_inputs
set_input_transition 0.10 $synchronous_inputs
set_output_delay -clock core_clk -max 2.0 [all_outputs]
set_output_delay -clock core_clk -min 0.2 [all_outputs]
set_load 0.005 [all_outputs]
# Raw reset reaches only the two synchronizer asynchronous reset pins.
# The qualified reset is launched by stage two's Q and is NOT excepted:
# internal recovery/removal paths must be timed with propagated clock/RC.
set_false_path -from [get_ports aresetn]
