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

- [ ] Specify SRAM/BRAM organization and a host/transfer interface.
- [ ] Replace the expensive wide register-backed input/output implementation.
- [ ] Add double buffering and overlap transfer with computation.
- [ ] Measure initiation interval, useful utilization and transfer-inclusive throughput.

## Implementation and verification work still open

- [ ] Full physical PDK/tool flow, floorplan, placement, clock tree and routing.
- [ ] Extracted setup/hold analysis across relevant corners and reset recovery/removal.
- [ ] Activity-based power analysis and mapped timing for the complete GEMM layer.
- [ ] Formal equivalence or stronger bounded proofs where useful.
- [ ] Uncovered-point review and justified functional/code coverage closure.
- [ ] Additional parameter/width and host-protocol robustness cases.

## Model-level demonstration

- [ ] Integrate a trained model with representative calibration data.
- [ ] Add bias and per-channel quantization where the model requires them.
- [ ] Evaluate task-level accuracy and measured performance on an actual target.

Existing pre-layout estimates and synthetic layer results must retain their
scope when presented on GitHub or a resume. No production-IP, power or device
speedup claim is justified by the current results.
