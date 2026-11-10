# Routed SKY130 prototype

```sh
# Requires a running Docker engine; the pinned image is pulled if missing.
make physical
```

The driver runs the official
[OpenROAD Flow Scripts](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts)
container pinned by digest in `toolchain.json`. Its bundled SKY130HD physical
and timing views are used consistently. A source snapshot is copied into a
network-isolated container; the workspace is not bind-mounted. Outputs and
diagnostic reports are copied back before the container is removed.

The target is `memory_gemm` with default M=3,K=5,N=7,TILE=4. Inferred RAMs use
the standard-cell fallback, not hard SRAM macros. The flow includes synthesis,
floorplanning, placement, clock-tree synthesis, detailed routing, parasitic
extraction, final ODB/DEF/GDS and a flow implementation-transformation
equivalence check. The script requires zero routing DRC errors and nonnegative
setup/hold slack, rather than treating file generation alone as success.

Recorded typical-corner result for the pinned run:

| Metric | Result |
|---|---:|
| Clock target | 20 ns / 50 MHz |
| Extracted setup slack | +11.0612 ns |
| Extracted hold slack | +0.139495 ns |
| Estimated minimum clock period | approximately 8.94 ns |
| Estimated maximum frequency | 111.871 MHz |
| Standard-cell count, excluding filler/tap cells | 20,630 |
| Standard-cell area | 203,764 µm² |
| Core area | 520,230 µm² |
| Die area | 550,779 µm² |
| Detailed-router reported DRC errors | 0 |
| Final implementation transformation equivalence | Passed |
| Vectorless power estimate at the 50 MHz target | 13.2859 mW |

These are tool estimates at SKY130HD TT, 25 C, 1.8 V, with extracted interconnect
and propagated clocks. The default power result uses estimated activity; it
is not a workload-based measurement. The flow's equivalence check covers
implementation transformations at mapped circuit cutpoints, not a complete
RTL-to-layout formal proof.

The external asynchronous reset is explicitly excepted in the SDC. Its safe
release and recovery/removal still need a target integration contract.
Additional timing corners, foundry DRC/LVS, package/IO integration and silicon
measurement remain open. Zero detailed-router errors is not full foundry
signoff. The physical configuration describes this default memory-backed top,
not every parameterization or the trained classifier elaboration.

`make physical` creates a new run folder containing `physical_metrics.json`,
all flow logs/reports and `results/sky130hd/int8_memory_gemm/base/6_final.*`.
Large physical artifacts stay out of Git. A manually triggered **SKY130
physical flow** Actions workflow can rebuild and archive them independently.
