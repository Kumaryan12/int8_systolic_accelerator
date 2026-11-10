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

- Built a two-slot synchronous-memory host interface; reduced the default
  generic implementation from 134,088 to 20,025 cells, with independently
  measured transfer-overlap cycle improvements on the same interface.
- Routed the default memory-backed top in SKY130HD with typical-corner extracted 100 MHz
  setup/hold slack of +1.061/+0.139 ns and zero detailed-router DRC errors;
  estimated 27.69 mW from an annotated routed-netlist activity trace at TT.
- Trained a 650-parameter digit classifier and evaluated all 1,797 official
  held-out test images in RTL, matching all integer logits and achieving
  95.05% INT8 classification accuracy.

Select two or three bullets for a resume. Keep parameterizations distinct:
base-tile mapping, default memory-top routing and classifier accuracy are
separate results. Routed power/frequency are tool estimates, not silicon
measurements. Three tested cell PVT corners close at 50 MHz with fixed extracted
RC; 100 MHz fails at SS. RC corners, physical reset release and foundry signoff
remain open.
