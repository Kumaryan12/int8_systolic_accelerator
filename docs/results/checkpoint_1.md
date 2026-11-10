# Checkpoint 1 — repeatable builds

Validated 10 November 2026 before committing the infrastructure change.

- `make verify`: PASS. Python: 13 tests; baseline: 105 matrix pairs;
  advanced: 207 completions and one reset abort; coverage: 14/14 defined bins;
  UVM rebuilt from source: 206 transactions and 3,296 output checks.
- Full verification including a fresh UVM compile took about 40 seconds locally.
- `STA="$HOME/eda-tools/OpenSTA/build/sta" make sta`: PASS. All three synthesis
  variants were rebuilt, then clean-netlist OpenSTA was rerun: setup slack
  +2.872 ns, hold slack +0.075 ns, estimated minimum period 7.13 ns at TT.
- Regression-gate tests check missing pass markers, nonzero exits, UVM error
  detection, and correct handling of zero-error UVM summaries.
- `git diff --check` and Python compilation passed.

Evidence directories (local, ignored):
`build/run_20261110T090808Z_g1ys8khy` and
`build/run_20261110T090651Z_85c_jg3j`.
Each contains a JSON summary with commands, versions and source state.
GitHub Actions independently rebuilds verification on pushes and retains logs.

No RTL behavior changed in this checkpoint. Reset timing, physical timing and
power remain outside the scope of these pre-layout results.
