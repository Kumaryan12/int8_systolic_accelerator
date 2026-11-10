# Development roadmap

## Phase 1 — Functional RTL baseline (this starter repository)
- 4x4 signed INT8 systolic MAC array, skewed feed and 18-bit accumulation.
- Matrix-capture controller with start/busy/done.
- Self-checking directed/random SystemVerilog tests against integer golden products.
- Pure Python independent reference and cycle schedule models.
- **To complete:** run `make sim`, debug simulator/tool compatibility, record passing logs.

## Phase 2 — Verification excellence (most relevant for Cisco)
- Write SystemVerilog interface + transactions with reproducible seeds.
- Class-based constrained-random stimulus and driver/monitor/scoreboard.
- Functional coverage: min/max/zero, sign combinations, reset during job,
  start while busy, multi-job sequences, output range, corner timing.
- Add SVA assertions for valid transaction protocol and done latency.
- Build repeatable regression automation, coverage report and bug tracker.

## Phase 3 — Architecture and PPA
- Explore PE pipeline options; compare accumulator widths and array sizes.
- Synthesize RTL with an FPGA or standard-cell tool and save cell count/Fmax reports.
- Document cost of input/output staging; compare 2x2, 4x4 and 8x8 array variants.
- Explain arithmetic throughput vs. end-to-end latency vs. utilization.

## Phase 4 — AI inference connection
- Implement tiled GEMM for larger matrices, including tail padding and multi-tile accumulation.
- Add INT8 quantization scales, accumulation, requantization and saturation rules.
- Compare the reference inference outputs with NumPy/PyTorch (optional dependency).
- Report exact model size and numerical tolerance; no unsupported speedup claims.

## Phase 5 — Polished presentation
- Architecture diagram, datapath/wavefront timing diagram, verification plan,
  regression log, synthesis results and limitations.
- Demo on GitHub with reproducible instructions and project screenshots.
