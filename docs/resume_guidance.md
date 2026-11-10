# Evidence-based resume wording

**INT8 AI Inference Accelerator** | SystemVerilog, Python, UVM, AXI4-Lite, SKY130, OpenROAD

Choose three bullets that reflect work you can explain and reproduce:

- Implemented a parameterized INT8 systolic accelerator with a default 4×4
  array of 16 MAC units, tiled matrix multiplication, integer requantization,
  two job buffers and an AXI4-Lite interface.
- Evaluated linear and two-layer ReLU digit classifiers on all 1,797 official
  test images, achieving 95.05% and 95.77% INT8 accuracy; verified every layer
  against exact integer reference results in RTL.
- Completed SKY130 placement and routing for the default standard-cell AXI
  peripheral, with 21,653 cells, zero detailed-router DRC errors and 50 MHz
  timing closure across nine tested cell/interconnect combinations.
- Built a shared CPU/RTL workload corpus and single-threaded M5 NEON baseline;
  measured 25.39 GMAC/s for prepacked 4×65×10 GEMM and 6.54 GMAC/s including
  per-call weight packing and integer postprocessing.
- Automated a 232-step regression with 44 Python tests, seeded RTL/UVM
  scoreboards and assertions, and GitHub Actions source builds.

Use the CPU benchmark bullet when discussing performance methodology or an
inference-engine role. The CPU is faster on these small jobs; no accelerator
speedup or energy-efficiency advantage is established.

## Scope to explain in an interview

The linear model has 650 parameters; the ReLU MLP has 1,210. Both use the same
official optdigits split and train-only quantization calibration. Float64
accuracy is 94.9917% and 95.6594%, respectively. The small INT8 gains represent
one and two images on a fixed test split, not a general quantization benefit.

Classifier accuracy, base-tile pre-layout sweeps and the routed default AXI
configuration are separate results. The complete classifier has not been
physically timed. CPU measurements use warm repeated operands and exclude
allocation, float input quantization and argmax.

The separate 587.11 pJ/useful-MAC estimate belongs to an older streaming-memory
trace at TT/100 MHz and includes reset/protocol/idle overhead. CPU energy is
unavailable. Do not claim a matched energy comparison.

No FPGA/ASIC silicon measurement, tapeout, full foundry DRC/LVS signoff or
physically integrated hard-SRAM result is claimed. The hard-SRAM backend has
functional and synthesis-binding evidence only.

Sources: [comparison report](results/checkpoint_16.md),
[nine-corner timing](results/checkpoint_15.md),
[methodology](performance_methodology.md).
