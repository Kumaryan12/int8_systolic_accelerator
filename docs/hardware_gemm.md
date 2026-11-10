# Hardware tiled GEMM interface

`rtl/tiled_gemm.sv` computes an M×K by K×N multiplication by reusing one
TILE×TILE `systolic_array`. Defaults are M=3, K=5, N=7, TILE=4 and signed INT8
inputs. Dimensions are elaboration-time parameters, not runtime registers.

The packed row-major operand ports contain all M×K and K×N elements. An idle
`start` captures both operands into registers, clears the output, and asserts
`busy`. Starts and operand changes while busy are ignored. `done` pulses for
one cycle after the final partial tile is accumulated. Outputs remain valid
until the next accepted start. Active-low asynchronous reset aborts the entire
job and clears control, captured operands and results.

The controller walks row blocks, column blocks and K partitions. It pads
out-of-bounds tile elements with zeros and writes only valid output positions.
Its signed output width defaults to `16 + ceil(log2(K))`, so the accumulation
can exceed the base tile's 18-bit range without losing results. Valid
configurations require positive M,K,N, TILE>=2, and a sufficient output width.

The wrapper uses `IDLE → LAUNCH → WAIT_RESULT`; each tile takes `3*TILE`
clocks including dispatch and result collection. Host latency after the
acceptance edge is therefore:

```text
ceil(M/TILE) × ceil(N/TILE) × ceil(K/TILE) × (3*TILE) clocks
```

For 3×5 by 5×7 with TILE=4, four tile jobs take 48 clocks. For 8×8 by 8×8,
eight tile jobs take 96 clocks. The regression checks exact completion timing,
all output elements, captured-input isolation, idle retention and three reset
positions with successful recovery.

This interface uses registers and broad packed buses. It demonstrates hardware
scheduling and arithmetic, rather than a scalable memory subsystem. SRAM/BRAM,
DMA, AXI interfaces, double buffering, and overlapped transfers remain future
architecture work. Base-tile SKY130 area/frequency numbers do not describe this
larger wrapper. Its generic Yosys synthesis check is part of `make synth`.
