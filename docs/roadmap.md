# Development roadmap

## Completed functional milestones

- [x] Parameterized INT8 systolic tile and signed accumulators.
- [x] Independent Python matrix and cycle-schedule models.
- [x] Reproducible from-source regression, pinned UVM, source hashes and CI.
- [x] Multiple seeds, N=2/3/4/8 RTL tests and reset-phase/recovery sweeps.
- [x] UVM driver, monitor, scoreboard, busy-start rejection and reset-abort handling.
- [x] Procedural and temporal assertions, defined functional bins and code-coverage exports.
- [x] Generic and SKY130 synthesis, mapped functional tests and pre-layout timing.
- [x] Cell-count/area comparisons across array sizes.
- [x] Hardware tiled GEMM with rectangular tails and wider partial-sum accumulation.
- [x] Integer rounding, requantization, saturation and ReLU in hardware.
- [x] Small quantized RTL layer with Python comparisons and numerical-error report.
- [x] Architecture/waveform documentation and evidence-based portfolio wording.

## Next architecture milestone — memory and integration

- [x] Specify a synchronous RAM organization and a tagged valid/ready host stream.
- [x] Add a narrow-interface successor to the wide register-backed wrapper.
- [x] Add two job slots and overlap input/output transfers with computation.
- [x] Add AXI4-Lite CSRs with channel-order/backpressure tests and synchronized reset release.
- [x] Bind a banked SKY130 SRAM backend and verify its response latency and macro synthesis.
- [ ] Physically integrate SRAM macros and connect a real processor or DMA.
- [x] Measure compute-completion interval and transfer-inclusive batch cycles for serial/overlapped hosts.

## Implementation and verification work still open

- [x] Pinned SKY130 flow: floorplan, placement, clock tree, routing, GDS and extraction.
- [x] Extracted typical-corner setup/hold analysis at 100 MHz.
- [x] Extracted TT/SS/FF cell-PVT sweep; strict setup/hold pass at 50 MHz with fixed RC.
- [x] Route AXI, run actual gate host tests and time internal qualified-reset recovery/removal at three cell PVTs.
- [ ] RC corners, reset pulse/MTBF characterization and foundry signoff.
- [x] Workload activity-based power estimate for the routed default memory-backed top.
- [ ] Map/time the complete classifier elaboration and postprocessing for a concrete target.
- [x] Flow implementation-transformation LEC and routed functional gate tests.
- [ ] Full RTL-to-layout formal proof where useful.
- [ ] Uncovered-point review and justified functional/code coverage closure.
- [ ] Additional parameter/width and host-protocol robustness cases.

## Model-level demonstration

- [x] Train a digit classifier and calibrate using training data only.
- [x] Implement classifier bias through a constant input feature in the RTL MACs.
- [ ] Add per-channel quantization if a larger target model requires it.
- [x] Evaluate all 1,797 official test images in RTL and report task accuracy.
- [ ] Measure performance on an actual FPGA or fabricated chip.

Keep base-tile pre-layout numbers, default memory-top routed estimates, and
classifier task accuracy distinct. Workload power is a tool estimate; no
measured-device speedup or production signoff claim is justified.
