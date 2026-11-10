# Checkpoint 13 — routed AXI boundary and timed qualified reset

The default M=3, K=5, N=7, TILE=4 AXI peripheral was synthesized, placed,
clocked, routed and extracted using the pinned SKY130HD flow. This is a separate
implementation from the earlier streaming top.

- 21,653 standard cells, 211,912 µm² summed cell area.
- Die area 570,622 µm²; core area 539,843 µm².
- Zero reported detailed-router DRC errors.
- Passed final flow implementation-transformation LEC. This is not a full
  RTL-to-GDS formal proof or foundry DRC/LVS.
- Routed zero-delay gate simulation: three seeds, 12 completed jobs and 252
  result checks, all address/data orderings, byte strobes, response stalls,
  occupied-bank concurrent read/write, IRQ/W1C and 21 reset cases.

At a 20 ns period (50 MHz), with propagated clocks and the same extracted
interconnect at all three cell corners:

| Cell corner | Setup (ns) | Hold (ns) | Recovery (ns) | Removal (ns) | Synchronizer setup (ns) |
|---|---:|---:|---:|---:|---:|
| TT 25°C 1.80 V | +10.544124 | +0.167608 | +15.514723 | +0.504976 | +19.338448 |
| SS 100°C 1.60 V | +1.016677 | +0.474279 | +12.216547 | +0.918667 | +18.798719 |
| FF −40°C 1.95 V | +14.091461 | +0.118431 | +17.004272 | +0.323768 | +19.507902 |

The two reset synchronizer flops survive in the mapped design. Their placement
origins are 9.62 µm apart in Manhattan distance. Their clocked interstage path
is explicitly reported. The only reset false path begins at raw external
`aresetn`, which feeds the synchronizer's asynchronous pins. Qualified reset
launched by stage two is timed into the internal asynchronous control pins;
recovery/removal reports must contain actual library checks for the strict gate
to pass. Spacing and setup slack do not establish a metastability MTBF.

```sh
make physical PHYSICAL_DESIGN=axi_gemm
make pvt PHYSICAL_RUN=build/run_20261110T105454Z__dbcos4i \
  PVT_ARGS="--pvt-periods 20 --require-timing-closure"
make verify
```

Physical evidence: `build/run_20261110T105454Z__dbcos4i` (515.6 s flow).
Routed gates and strict PVT/reset evidence: `build/run_20261110T110334Z_0s8niaav`.
Full functional regression: `build/run_20261110T110123Z_ch6sen_5`, all 147 steps
passed. After adding reset-report failure gates, all 34 Python tests also
passed in `build/run_20261110T110232Z_4hwqquur`.
Curated [physical metrics](axi_physical_metrics.json) and
[PVT/reset metrics](axi_pvt_metrics.json) are committed. The manual physical
GitHub workflow can select either top and defaults to AXI; it installs the
routed-gate tools and strictly gates all three cell corners at 50 MHz.

Still open: hard SRAM mapping, RC-min/max extraction, library reset pulse and
metastability characterization, foundry DRC/LVS, target power integrity/thermal,
IO/package and device measurements. The classifier's larger elaboration is not
this physical design. The earlier workload power estimate belongs to the
streaming top; no activity-based AXI power estimate is claimed.
