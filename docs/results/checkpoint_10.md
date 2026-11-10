# Checkpoint 10 — routed gate simulation, extracted timing and power

Validated 10 November 2026 with:

```sh
make postroute PHYSICAL_RUN=build/run_20261110T100446Z_7e1u3q9h
make verify
```

The physical run's checksummed GDS/ODB/SPEF files are reused. The routed
netlist passes an eight-job signed-GEMM scoreboard with stalls, malformed-frame
handling and reset recovery. Its VCD is annotated onto the extracted design.

- At a 10 ns clock, setup slack is +1.061157 ns and hold slack +0.139495 ns.
- VCD annotation covers 53,754 pins, with two unannotated (99.9963%).
- Workload power estimate at 100 MHz: 27.69079 mW; vectorless comparison at
  the same frequency: 26.57180 mW. These are Liberty/SPEF-based estimates,
  not measured silicon power. The VCD includes eight jobs plus protocol/reset
  preparations and uses zero-delay functional cells, not SDF/glitch simulation.
- A GDS routing-layer overview was generated through KLayout and inspected.
- Full local `make verify` passed all 115 build/run/report steps in about
  58 seconds, including 28 Python tests. The separate trained-model GitHub
  workflow also passed all 1,797 official test images independently.

Final postroute evidence: `build/run_20261110T102732Z_sct5zey2`; final functional
regression: `build/run_20261110T102520Z_h288qep1`. Curated JSON metrics and the
layout PNG are committed. Complete raw output is retained in ignored run folders.

Remaining signoff scope: additional PVT/RC corners, asynchronous-reset release
and recovery/removal, foundry DRC/LVS, a real SRAM/BRAM mapping, external bus/IO
integration, and real-device measurements. The flow's mapped implementation
transformation LEC is not an exhaustive RTL-to-layout formal proof.
