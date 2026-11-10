# FPGA demonstration status

No board is available. No FPGA bitstream, utilization, clock, power or board
execution result is claimed. The existing SKY130 GDS is an ASIC artifact and
cannot be programmed into an FPGA.

Once a board is available, record its exact FPGA part, onboard clock,
programming interface and supported toolchain, then:

1. Wrap the narrow memory-backed interface in a board-specific host transport
   (UART or an available processor/AXI bridge), clock and reset circuitry.
2. Infer/bind the board's block RAM and verify the actual read latency against
   `docs/memory_interface.md`. Avoid the SKY130-specific SRAM backend.
3. Add real pin/clock constraints, synthesize, implement and review timing,
   memory mapping and resource utilization.
4. Send the same `make cpu-bench` corpus to the board and check INT32 and INT8
   outputs, including signed extremes, tails, reset and backpressure.
5. Measure cycles and host-inclusive elapsed time. Report energy only with
   suitable board power measurements and a defined idle baseline.

Board-specific RTL and constraints should be added after identifying the
target; placeholder constraints do not constitute a hardware demo.
