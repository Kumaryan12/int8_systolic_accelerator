# Checkpoint 14 — banked SKY130 hard-SRAM binding

Added an optional OpenRAM backend to the existing RAM, GEMM and AXI modules.
The default inferred path remains covered by its original tests. Pinned,
licensed Verilog/TT Liberty/LEF views are small enough to vendor for offline CI.
The controller now accounts for the macro's falling-edge read and output
invalidation through a registered adapter and delayed metadata.

Validation on 10 November 2026:

- Full `make verify`: 232 build/run/report steps and 34 Python tests passed.
- Macro stream path: 192 completed jobs across eight shapes/three seeds.
- Macro AXI path: 96 jobs across the same shapes/seeds; seven reset situations
  per run, byte strobes, independent channels, response stalls and IRQ/W1C.
- Combined Icarus macro scoreboards checked 10,152 result words.
- Verilator also passed the default macro stream at three seeds with the
  existing seven temporal properties enabled.
- Dedicated 513-word, 19-bit RAM test exercises three physical banks, both
  255/256 boundaries, the partially used final bank, back-to-back reads,
  disabled-read hold and simultaneous operations in distinct banks.
- Negative controls reject same-address read/write and out-of-depth reads.
- Yosys retains exactly three named hard macros in the default AXI top and no
  inferred memory fallback; 17,399 generic cells including the three macros.
- `make memory-synth` still retains three synchronous inferred memories for
  the default backend. Timing/area of the old routed layout are not reassigned
  to the new backend.

Full evidence: `build/run_20261110T112241Z_88bmjij7`; inferred-memory synthesis:
`build/run_20261110T112300Z_qy1ytqt4`. Curated [metrics](sram_metrics.json) include
matched eight-job cycle measurements. The SRAM path takes 1,318 vs 1,265 clocks
for the default batch due to its extra response stage; there is no speedup claim.

See the [backend contract](../sram_backend.md) for the capacity/area tradeoff,
exact latency, model provenance and remaining physical work. Three 1KB macros
are substantially overprovisioned for the tiny default. Macro placement/PDN,
GDS/routing, extracted timing and SS/FF macro characterization remain open.
