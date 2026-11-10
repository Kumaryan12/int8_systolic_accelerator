# Checkpoint 11 — AXI4-Lite and qualified reset

Added a 32-bit processor register interface around the existing memory GEMM.
Independent AW/W buffers accept either channel order. One read and one write
response can be outstanding, with stable payloads under backpressure. Input
word counting supplies framing; result reads retain bank/tag/index/last metadata.
Byte strobes, SLVERR responses, sticky IRQ events, W1C, counters and dimension
registers are documented in [the interface contract](../axi_interface.md).

A two-stage reset synchronizer supplies asynchronous assertion and synchronous
release to the wrapper and engine. Reset cancels outstanding transactions and
jobs. Existing streaming-core behavior remains covered by its original tests.

Local AXI evidence: `build/run_20261110T104715Z_om_dhznz/summary.json`.
Icarus checked 84 completed jobs, 2,904 result values and 147 reset cases across
seven shapes and three seeds. Verilator additionally checked the default shape
at all three seeds with five response/ownership temporal assertions enabled.
No result or protocol mismatches occurred. The expanded full regression passed all 147 build/run/report steps, including
28 Python tests: `build/run_20261110T104848Z_9jb3_845/summary.json`.

Physical recovery/removal, synchronizer placement/MTBF, DMA and a real
processor/board are still target work. Existing routed GDS/timing/power apply
to `memory_gemm`, not this new wrapper.
