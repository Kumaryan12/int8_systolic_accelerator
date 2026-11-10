# Memory-backed GEMM and host protocol

`rtl/memory_gemm.sv` is the narrow-interface successor to the packed-bus
`tiled_gemm` example. The latter remains a reference/latency comparison.
Dimensions are elaboration-time parameters M,K,N,TILE; the default is 3×5
by 5×7 using a 4×4 signed-INT8 tile. This module exposes a custom stream; the separate [AXI4-Lite wrapper](axi_interface.md)
adapts it for processor programmed I/O. DMA remains system integration work.

## Storage and scheduling

Three synchronous 1R1W RAMs hold A, B and C. Each RAM contains two job slots:

| RAM | Default organization | Contents |
|---|---:|---|
| A | 30 × 8 bits | two row-major 3×5 operands |
| B | 70 × 8 bits | two row-major 5×7 operands |
| C | 42 × 19 bits | two row-major 3×7 output matrices |

Total default storage is 1,598 bits. The RAM has a registered read output and
independent write port. Storage is not reset; validity and ownership are reset.
The controller prevents read/write collisions by using disjoint job slots.
`sync_dp_ram` defines old-data/read-first behavior for a same-address collision,
but a target-specific macro must still be mapped and verified separately.

A slot progresses `FREE → LOADING → READY → RUNNING → RESULT → FREE`.
Completing a valid frame marks it READY and automatically schedules it on the
single compute tile. The host can load another slot while the engine runs and
drain completed results while the engine computes another job. A slot is not
reusable until its final result is consumed. Output backpressure therefore
propagates to input availability without overwriting a live job.

The engine reads one A word and one B word per cycle into a small tile buffer,
pads tails with zeros, computes a partial product, and accumulates K partitions
in a TILE²-element output buffer. It then writes valid output words into C RAM.
It does not capture entire input/output matrices in wide register vectors.

## Input stream

An input transfer occurs only at a rising edge with `load_valid && load_ready`.
The host supplies:

- `load_bank`: job slot 0 or 1.
- `load_data`: one signed INT8 element.
- `load_tag`: host correlation tag; latched on the first word of a new frame.
- `load_last`: asserted only on the final B element.

Each frame is exactly M×K A words followed by K×N B words, both row-major.
There is no address channel. Partial frames may be interleaved across slots.
The host must hold valid and the complete input payload stable until accepted.
Tags on later words are ignored. Use distinct tags for simultaneously live jobs
if software needs unique job correlation.

An early or missing last marker discards that slot's frame, releases its slot
and raises `load_error` for one clock after the offending accepted beat.
The host can correlate that pulse with the preceding input handshake. A fresh
frame must overwrite every operand word before dispatch is possible. Loading
an occupied READY/RUNNING/RESULT slot is backpressured, not accepted.

## Output stream

A result transfer occurs only with `result_valid && result_ready` at a rising
edge. `result_data` is the signed full-precision accumulation, `result_index`
is the row-major output index, and `result_bank/result_tag` identify the job.
`result_last` marks index M×N−1. The full response is stable while stalled.
With a ready receiver, a selected completed matrix streams at one word/clock.
Data when `result_valid==0` is unspecified, including immediately after reset.

Ordering within a job is strict. Do not assume a global bank-order guarantee;
use the output tag. `compute_done/completed_tag` report publication to C memory,
not host consumption. `busy` indicates compute-engine activity; it may be low
while completed results are pending. `bank_free` reports completely free slots.

Asserting active-low reset cancels partial frames, queued/running jobs and
pending output beats. Reset does not scrub RAM. No old frame can be returned
until a complete new frame has loaded and its full output has been written.

## Verification and implementation scope

`make memory` tests seven shapes across three seeds, including both slots,
random bubbles/stalls, payload retention, malformed frames, asynchronous reset
during loading/computation/writeback/stalled output, and post-reset recovery.
It checks every output against independent full-matrix integer sums.
`make verify` includes these checks. `make memory-synth` checks inferred RAM
ports and separately builds a generic flip-flop fallback.

In the default local mapping, the generic fallback contains 20,025 cells versus
134,088 in the prior packed-bus wrapper, using the same Yosys generic flow.
This is a structural cost comparison, not an SRAM-macro area measurement or
a speedup claim. Serialized memory access adds latency; transfer-inclusive
latency and overlap measurements are reported separately.

The optional `SRAM_IMPL=1` backend uses a held two-edge response and supports
one outgoing word every two clocks. Default inferred RAM timing remains
unchanged. See [SRAM timing, capacity and collision contract](sram_backend.md).
