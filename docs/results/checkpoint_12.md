# Checkpoint 12 — extracted three-corner timing

The routed `memory_gemm` design was analyzed with three cell libraries, its
propagated clock tree and the same extracted SPEF at each PVT. This separates
cell PVT sensitivity from interconnect-corner coverage. SS/FF libraries come
from the [Efabless SKY130 library mirror](https://github.com/efabless/skywater-pdk-libs-sky130_fd_sc_hd/tree/5a42fd01a0eeb2338340438443c7062e198d97a4/timing),
with pinned revision and SHA256 in `physical/pvt_libraries.json`. TT is the
checksummed library from the already pinned ORFS image.

| Cell corner | Clock | Setup slack (ns) | Hold slack (ns) | Closure |
|---|---|---:|---:|---|
| Typical, 25°C, 1.80 V | 100 MHz | +1.061157 | +0.139495 | Pass |
| Slow, 100°C, 1.60 V | 100 MHz | −8.143339 | +0.434713 | **Fail** |
| Fast, −40°C, 1.95 V | 100 MHz | +4.406778 | +0.090783 | Pass |
| Typical, 25°C, 1.80 V | 50 MHz | +11.061157 | +0.139495 | Pass |
| Slow, 100°C, 1.60 V | 50 MHz | +1.856661 | +0.434713 | Pass |
| Fast, −40°C, 1.95 V | 50 MHz | +14.406778 | +0.090783 | Pass |

100 MHz is a typical-corner result; it is not supported across these three
corners. The tested design closes setup and hold at 50 MHz for this sweep.
No RTL, placement or routing was changed to obtain these results. The raw
external reset is still explicitly excepted in this legacy physical top;
the new AXI wrapper's qualified reset is a separate implementation.

```sh
# Diagnostic sweep: successful execution may include negative slacks.
make pvt PHYSICAL_RUN=build/run_20261110T100446Z_7e1u3q9h
# Strict release gate: any setup/hold violation makes the command fail.
make pvt PHYSICAL_RUN=build/run_20261110T100446Z_7e1u3q9h \
  PVT_ARGS="--pvt-periods 20 --require-timing-closure"
```

Diagnostic evidence: `build/run_20261110T105103Z_qtwodczg/summary.json`.
Curated raw metrics: [pvt_metrics.json](pvt_metrics.json). Strict 50 MHz analysis passed in
`build/run_20261110T105225Z_qiiqkpkn`. A negative-control strict 100 MHz run
correctly failed (`build/run_20261110T105320Z_epxgnyok`) while retaining its
reports. All 31 offline Python tests passed. Missing/nonfinite slacks and modified
cached libraries fail closed; offline unit tests cover those cases.

Remaining: RC-min/max extraction, qualified-reset physical implementation and
recovery/removal, synchronizer placement/MTBF, foundry DRC/LVS, power integrity,
IO/package and actual-device measurement. This sweep is not foundry signoff.
