# OpenRAM backend

Set `SRAM_IMPL=1` on `memory_gemm` or `axi_gemm` to use the pinned
`sky130_sram_1kbyte_1rw1r_32x256_8` macro. The default remains `SRAM_IMPL=0`
with inferred synchronous RAM and the original cycle schedule. All external
stream and AXI transaction rules remain applicable; software must poll status
rather than assume a fixed compute latency.

The macro provides one read/write port and one read port, each 32 bits wide
and 256 words deep. The adapter uses port 0 for writes and port 1 for reads.
It zero-extends narrow writes, uses all four byte enables and truncates read
results to the logical width. Widths 1–32 and positive depths are supported;
depths above 256 select additional macros using the upper address bits. The
logical depth is enforced in simulation even when the final macro has spare
locations. Same-address simultaneous read/write is prohibited; the GEMM
controller already avoids these collisions. Different banks can use the same
low address independently.

The [upstream model](../third_party/sky130_sram/README.md) samples controls on
a rising edge, performs the memory operation on a falling edge and invalidates
its output on subsequent cycles, including disabled reads. Connecting it to
the old single-edge RAM interface would expose stale/unknown data. The adapter
therefore captures the macro output into a held register on the rising edge
after the request. For a request at edge t, its response changes just after
t+1 and holds until another response. It has no data reset; core ownership and
validity cancel old jobs and ensure stale RAM contents cannot escape.

The compute controller delays tile metadata by one additional clock. Result
reads use one request in flight and a held response, supporting one output
every two clocks when the receiver is ready. This preserves payload stability
under arbitrary stalls and avoids overwriting an unread result. Raw macro
contents can still change after reset from an already accepted write; reset
cancels logical jobs and does not scrub memory.

| Eight-job overlapped batch, no artificial stalls | Inferred RAM clocks | SRAM adapter clocks |
|---|---:|---:|
| M=3, K=5, N=7 | 1,265 | 1,318 |
| M=8, K=8, N=8 | 2,570 | 2,698 |
| M=9, K=2, N=11 | 3,389 | 3,560 |

These are RTL schedule measurements with the same host bench and seed
20261110, not measured device performance. The model delay is not a substitute
for Liberty-based physical timing.

The default shape binds to exactly three macros, one each for A/B/C. They
provide 24,576 physical bits for 1,598 logical bits (about 6.5% utilization).
Each supplied macro's LEF/Liberty area is about 190,713 µm², so three macros
alone exceed the earlier small standard-cell implementation's area. This is
an integration/scaling option, not an area improvement for the tiny default.
The 4×65×10 test shape uses ten macros across its larger scratchpads. A smaller
custom SRAM or byte packing could reduce wasted capacity in later work.

`make sram` checks bank/depth boundaries and held outputs, explicitly rejects
collisions and invalid addresses, runs eight shapes at three seeds through
both stream and AXI interfaces, runs stream SVA on the macro backend and
requires synthesis to retain exactly three macro instances with no inferred
RAM fallback. It is included in `make verify` and CI. All views are pinned and
vendored with their license; no network is required for these checks.

Physical implementation is still open: GDS inclusion, macro placement and
power connections, clock delivery, routing and extracted timing. The vendor
view here only characterizes TT. SS/FF macro timing must be obtained or
characterized before claiming three-cell-corner timing for the SRAM version.
Existing routed/PVT results refer to the standard-cell RAM version.
