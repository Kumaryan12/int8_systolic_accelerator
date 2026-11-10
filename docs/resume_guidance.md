# Evidence-based resume wording

**INT8 Systolic Matrix Accelerator** | SystemVerilog, UVM, Python, Yosys, OpenSTA

- Implemented a 4×4 signed-INT8 systolic tile with 16 MAC units and 18-bit
  accumulators, then added a hardware scheduler for rectangular tiled GEMM,
  zero-padded tails and wider cross-tile accumulation.
- Built a seeded RTL/UVM regression with six temporal assertions, reset-abort
  recovery and a scoreboard; validated 208 completed transactions and 3,328
  outputs per UVM seed, plus 777 tiled GEMMs across seven shapes/three seeds.
- Mapped the base tile to SKY130HD and checked mapped-netlist functionality;
  recorded 9,727 cells and 80,737 µm² summed cell area, with positive pre-layout
  slack at a 100 MHz target under typical-corner ideal-clock assumptions.
- Verified hardware requantization/ReLU against 1,900 integer vectors and a
  Python-referenced layer demo; automated source builds and evidence capture
  through GitHub Actions.

Select two or three bullets for a resume. Explain output-stationary dataflow,
wavefront skew, accumulator sizing, reset cancellation, padding and throughput
accounting in an interview. Follow the linked checkpoint evidence for exact
scope. The layer uses synthetic weights; the project has no placed/routed chip,
measured device Fmax, power result or model-accuracy benchmark.
