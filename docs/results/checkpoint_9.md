# Checkpoint 9 — real model and routed implementation

Validated 10 November 2026:

- `make model` trained a 650-parameter linear classifier on UCI's supplied
  3,823 training examples and evaluated all 1,797 official test examples.
  Floating-point accuracy is 94.9917%; hardware INT8-logit accuracy is 95.0473%.
- All 450 four-image RTL batches passed: 17,970 real logits and 30 padded
  logits match the Python accumulator and requantization reference exactly.
  Hardware simulation took approximately 11.4 seconds locally. Training,
  calibration, dataset provenance/checksums and complete metrics are retained.
- `make physical` completed the pinned SKY130HD flow for the default
  memory-backed top, including extracted parasitics and GDS generation.
  Detailed-router DRC errors: 0. Extracted slack at the conservative 20 ns
  target: setup +11.0612 ns, hold +0.139495 ns. Standard-cell area: 203,764 µm².
  The flow's final implementation transformation equivalence check passed.
- The 13.2859 mW default power result is vectorless. It is not yet a measured
  workload activity estimate. External asynchronous reset release is excepted;
  additional corners and foundry signoff remain open.
- All 25 Python tests passed, including model determinism/quantization and
  rejection of missing/failed physical timing, DRC and equivalence metrics.

Evidence: `build/run_20261110T101308Z_1hr4zrf1` (full trained model),
`build/run_20261110T100446Z_7e1u3q9h` (physical run), and
`build/run_20261110T101814Z_2hv_tz4x` (Python checks). See
`examples/digits/README.md` and `physical/README.md` for exact scope and commands.
