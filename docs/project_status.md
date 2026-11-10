# Project status — 10 November 2026

The prototype now includes memory-backed GEMM, an AXI4-Lite peripheral, a trained
classifier and routed SKY130 implementations. AXI reset recovery/removal and
three cell PVT corners are timed; the earlier stream top has workload power. A single `make verify` rebuilds
and checks Python references, RTL, UVM, temporal assertions, coverage, tiled
matrices, and the small quantized layer example.

## Completed checkpoints

| Checkpoint | Delivered | Evidence |
|---|---|---|
| 1 | Git/GitHub, pinned UVM submodule, isolated regression logs, CI, synthesis/STA commands | [Results](results/checkpoint_1.md) |
| 2 | Three seeds, four RTL sizes, reset-phase sweeps, UVM busy/reset/recovery, abort-aware scoreboard, temporal SVA and coverage exports | [Results](results/checkpoint_2.md) |
| 3 | Functional mapped-netlist regression and N=2,3,4,8 area comparison | [Results](results/checkpoint_3.md) |
| 4 | RTL tiled GEMM, tail padding, wider accumulation and reset recovery | [Results](results/checkpoint_4.md) |
| 5 | Hardware requantization/ReLU, 1,900 boundary/random vectors, Python/RTL layer comparison | [Results](results/checkpoint_5.md) |
| 6 | Architecture explanation, recorded waveform illustration, updated verification plan, scope and resume wording | [Architecture](architecture.md) |
| 7 | Three synchronous RAMs, two tagged job slots, narrow host streams, backpressure and reset cancellation | [Results](results/checkpoint_7.md) |
| 8 | Measured serial/overlapped schedules, stream assertions and the same layer through the memory-backed interface | [Results](results/checkpoint_8.md) |
| 9 | Trained classifier evaluated entirely in RTL and a pinned routed SKY130 flow | [Results](results/checkpoint_9.md) |
| 10 | Routed gate tests, extracted 100 MHz analysis, workload power and layout image | [Results](results/checkpoint_10.md) |
| 11 | AXI4-Lite CSRs, independent channels, IRQs, byte strobes and qualified reset | [Results](results/checkpoint_11.md) |
| 12 | Extracted TT/SS/FF timing sweep and strict timing gates | [Results](results/checkpoint_12.md) |
| 13 | Routed AXI, actual gate host tests and qualified-reset timing at three cell PVTs | [Results](results/checkpoint_13.md) |

The project is stored in the private GitHub repository
[Kumaryan12/int8_systolic_accelerator](https://github.com/Kumaryan12/int8_systolic_accelerator).
Each checkpoint is committed and pushed separately. CI results and archived
logs are accessible through its Actions tab. Local run directories are ignored
by Git; curated checkpoint summaries are committed.

## Current functional evidence

- AXI peripheral: 84 GEMMs and 2,904 result checks across seven shapes/three seeds, plus five temporal assertions on the default shape.
- 34 Python unit tests, including model training and physical/power report failure gates.
- Baseline: 105 matrix pairs per seed, across three seeds.
- Advanced RTL: 211/214/217/229 completions per seed for N=2/3/4/8,
  with 4/7/10/22 reset-abort positions and a recovery after each abort.
- Functional coverage: 14/14 scenario bins and 9/9 operand-sign cross bins.
- UVM: 208 completions plus one reset abort and 3,328 output comparisons per seed.
- Six temporal assertions, measured code coverage, and LCOV exports.
- Hardware tiled GEMM: 777 completed jobs across seven shapes and three seeds.
- Requantization: 1,900 bit-exact vectors; layer demo: 21 exact integer outputs,
  48 clocks, max float-reference error 0.0215193, RMSE 0.00751376.
- Clean mapped base tile: three-seed functional gate tests and pre-layout STA.
- Memory-backed successor: 168 GEMMs, 5,808 output checks, and three retained
  synchronous 1R1W memories; default generic fallback maps to 20,025 cells.

- Trained model: 650 parameters, 3,823 training images, all 1,797 official test
  images evaluated in RTL, 95.0473% INT8 accuracy and 18,000 exact logits including
  padding. Dataset/license/seed/calibration provenance is recorded.
- Routed default memory top: 20,630 standard cells, 203,764 µm² cell area,
  zero reported detailed-router DRC errors and a passed flow transformation LEC.
  At 100 MHz after extraction: +1.061157 ns setup and +0.139495 ns hold slack.
  A cell-PVT sweep finds 100 MHz fails at SS; all three tested corners pass
  setup/hold at 50 MHz with the same extracted RC.
  Workload-annotated power estimate: 27.69079 mW; 53,754 pins annotated, two not.

- Routed AXI top: 21,653 cells, 211,912 µm² area and zero router DRC errors.
  Three-seed routed gate tests pass. At 50 MHz, all three tested cell PVTs pass
  setup/hold, internal reset recovery/removal and synchronizer setup with fixed RC.

## Remaining target-specific work

1. **Physical signoff:** extend beyond the tested three cell PVTs to RC corners,
   reset pulse/MTBF characterization, foundry DRC/LVS, power-integrity/thermal checks
   and package/IO integration. AXI internal reset recovery/removal is timed;
   production signoff and silicon measurement are not.
2. **Memory/bus integration:** map the retained 1R1W memories to an actual SRAM
   macro or FPGA BRAM, and integrate the verified AXI4-Lite peripheral or a DMA adapter into a concrete system.
   The portable stream, ownership, buffering and cycle benchmarks are complete.
3. **Verification closure:** review remaining uncovered expressions/branches,
   set target-specific coverage goals and consider a full RTL-to-layout formal
   proof. Defined functional bins, stream properties and implementation LEC
   do not establish exhaustive correctness for every parameter/configuration.
4. **Deployment:** integrate a larger model/application and measure hardware
   performance including the actual host bus. The trained digit classifier
   now provides real task accuracy, with all official test examples checked
   in RTL; its parameterization has not been placed/routed.
