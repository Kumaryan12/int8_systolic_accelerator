# Checkpoint 5 — integer output scaling and inference

Validated 10 November 2026 with `make python-test inference`:

- All 17 Python tests passed.
- 1,900 RTL requantizer vectors matched the integer Python reference.
- The 3×5 by 5×7 RTL layer plus hardware ReLU/requantization completed in
  48 clocks and matched all 21 accumulator/output pairs exactly.
- Maximum absolute error against the floating-point ReLU reference:
  **0.0215193108**, within the demo's declared 0.15 tolerance.
- RMSE: **0.00751376195**.
- Output multiplier: 750,368,461; shift: 38; output scale: 0.0490581958333.

Evidence: `build/run_20261110T092237Z_zct4own5` and
`build/run_20261110T092238Z_eupg3gke`. JSON results and a VCD are generated,
and CI retains the inference JSON/waveform as artifacts.

CI exposed a portability issue with the coverage report's array loop in an
Icarus 11 `final` block. The monitor now reports through an explicit completion
event before `$finish`. The coverage gate still requires all bins; the local
three-seed rerun passed in `build/run_20261110T092334Z_xa2yw4ui`. Remote CI
verification is tracked separately from these local results.
