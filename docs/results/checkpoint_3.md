# Checkpoint 3 — mapped functionality and architecture costs

Validated 10 November 2026. `make sta` rebuilds all synthesis variants, generates
functional SKY130 models from the checked-in Liberty, simulates the clean
mapped netlist with the advanced coverage testbench for three seeds, then
checks OpenSTA setup/hold results. Gate tests exercise 217 completed jobs and
10 reset aborts per seed, with 14/14 scenario and 9/9 sign-cross bins.

The simulations check functionality without cell delays. They are not a formal
equivalence proof or an SDF-annotated timing simulation. No RTL datapath change
was needed. The standalone clean 4x4 mapping reports 9,727 cells and
80,737.4336 square micrometres; typical-corner pre-layout timing reports
+2.872 ns setup and +0.075 ns hold slack at a 10 ns clock target.

`make architecture` independently maps wrappers for each array size:

| N | MAC units | Compute clocks | Accumulator bits | Cells | Cell area (µm²) |
|---|---:|---:|---:|---:|---:|
| 2 | 4 | 4 | 17 | 2,420 | 19,934.1184 |
| 3 | 9 | 7 | 18 | 5,678 | 46,429.5296 |
| 4 | 16 | 10 | 18 | 9,710 | 80,846.2880 |
| 8 | 64 | 22 | 19 | 41,699 | 340,466.5344 |

These are mapped standard-cell sums, not floorplan areas. The wrapper-based
4x4 result differs slightly from the standalone mapping; compare variants
within the same flow. No cross-size frequency or power claim is made.

Local evidence: `build/run_20261110T091438Z_7chh_0n1` (first gate/STA run),
`build/run_20261110T091604Z_iwhjv81w` (size sweep), and
`build/run_20261110T091634Z_nfpmdzn4` (final gate/STA run with JSON metrics).

Remaining implementation work requires physical views and a physical-design
flow: placement, clock-tree synthesis, routing, parasitic extraction, timing at
additional corners, reset recovery/removal, and power estimation. This checkout
has a typical Liberty file but no complete physical PDK/LEF/GDS flow. The reset
constraint warning is retained and documented rather than hidden.
