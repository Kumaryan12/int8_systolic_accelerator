# Checkpoint 15 — independent RC corners and nine-combination timing

The unchanged standard-cell AXI layout from checkpoint 13 was re-extracted
with three independently selected SKY130A rule tables. The published
[Open_PDKs rule files](https://github.com/fossi-foundation/open-pdks/tree/5740c4a81c42f9fe4af5ef2ee258a99151053d28/sky130/librelane)
are pinned by revision, URL and SHA256. Each corner starts a fresh OpenROAD
process, reads the same checksummed routed ODB, selects its own extraction
model, extracts and writes a new SPEF. No arbitrary R/C scale factors or
placement/routing changes are used. The .calibre file suffix is the publisher's
model name; calibration accuracy has not been independently established here.

| RC model | Extracted nets | Resistance segments | Sum of D_NET capacitance (pF) |
|---|---:|---:|---:|
| min | 16,503 | 63,584 | 73.081198 |
| nom | 16,503 | 65,336 | 81.261305 |
| max | 16,503 | 68,188 | 89.303845 |

These totals are network sanity checks, not a single lumped device capacitance
or resistance. Units, finite/positive values and distinct electrical networks
are required. The PVT runner verifies the image/layout identity, complete RC
corner set and every SPEF hash before consuming them.

At a 20 ns period (50 MHz), all nine combinations pass. Slacks in ns:

| Cell PVT | RC | Setup | Hold | Recovery | Removal |
|---|---|---:|---:|---:|---:|
| TT 25°C 1.80 V | min | +10.680676 | +0.152981 | +15.656861 | +0.483571 |
| TT 25°C 1.80 V | nom | +10.569346 | +0.141648 | +15.531054 | +0.504071 |
| TT 25°C 1.80 V | max | +10.460446 | +0.129785 | +15.390068 | +0.532356 |
| SS 100°C 1.60 V | min | +1.280345 | +0.443584 | +12.474114 | +0.883405 |
| SS 100°C 1.60 V | nom | +1.065247 | +0.430662 | +12.245263 | +0.919264 |
| SS 100°C 1.60 V | max | +0.853111 | +0.417382 | +11.990460 | +0.969110 |
| FF −40°C 1.95 V | min | +14.178344 | +0.109220 | +17.093119 | +0.308783 |
| FF −40°C 1.95 V | nom | +14.107427 | +0.101337 | +17.014736 | +0.323027 |
| FF −40°C 1.95 V | max | +14.037412 | +0.092626 | +16.926905 | +0.341796 |

The smallest synchronizer setup slack is +18.797691 ns at SS/max RC. Both
reset stages survive; internal qualified-reset recovery/removal remains timed
and raw reset into the synchronizer remains excepted. Three-seed routed host
gate tests also pass as part of this analysis. The 50 MHz target is supported
for these tested public models; full foundry signoff is not established.

```sh
make rcx PHYSICAL_RUN=build/run_20261110T105454Z__dbcos4i
make pvt PHYSICAL_RUN=build/run_20261110T105454Z__dbcos4i \
  PVT_ARGS="--rcx-run build/run_20261110T112745Z_kemk1thd --pvt-periods 20 --require-timing-closure"
```

Evidence: extraction `build/run_20261110T112745Z_kemk1thd`; strict nine-combination
analysis `build/run_20261110T112841Z__jyfx642`. The original fixed-SPEF path also
passes its strict three-PVT regression on the legacy memory top in
`build/run_20261110T112955Z_6sqw6div`.
Curated [extraction metrics](rcx_metrics.json) and [timing/reset metrics](rc_pvt_metrics.json)
retain hashes/numbers with local paths normalized. New unit tests reject
malformed/nonfinite SPEFs, wrong units, incomplete corners, mismatched images
and modified artifacts.

CI now installs a small pinned portable Yosys 0.70 distribution. Ubuntu's Yosys
0.33 cannot parse the existing RTL casts; a version preflight rejects older
synthesis tools before expensive tests. Structural SRAM binding uses generic
techmap without ABC: it checks macro retention, not library optimization/PPA.
The portable structural check passed in `build/run_20261110T113733Z_lkkkypw9`,
retaining three macros and 18,696 generic cells. The full regression using
that portable tool also passed all 232 steps and 38 Python tests in
`build/run_20261110T113829Z_si2rz890`. This pre-ABC cell count is not
comparable to checkpoint 14's ABC-optimized generic count. Native physical
mapping stays in the pinned OpenROAD container.

The manual physical CI workflow now extracts all three RC corners and strictly
gates the nine combinations, archiving SPEFs and reports. This result applies
to the checkpoint 13 standard-cell RAM layout, not the newly bound hard-SRAM
backend. Macro placement/power/GDS/routing and SS/FF macro characterization,
reset pulse/MTBF, foundry DRC/LVS and measured-device evidence remain open.
