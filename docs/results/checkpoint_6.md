# Checkpoint 6 — portfolio package and final checks

Validated 10 November 2026:

- Full local `make verify`: PASS across 67 compile/run/report steps in about
  53 seconds, including rebuilt UVM, temporal SVA, code coverage, seven tiled
  matrix shapes, quantization vectors and the Python/RTL layer demonstration.
- Targeted Python checks after adding process-group timeout handling: all
  18 unit tests passed. Missing markers, nonzero exits, UVM errors and timeouts
  are tested failure paths.
- Final `make sta`: PASS. Rebuilt the three base-tile synthesis variants,
  structurally synthesized the default GEMM wrapper and requantizer, passed
  the three-seed clean-netlist gate regression and reproduced positive timing
  slack. The requantizer uses a structural `-noabc` check; its generic optimizer
  was intentionally stopped after an expensive unconstrained arithmetic pass.
  No mapped PPA result for that postprocessor is claimed.
- Inference rerun after waveform export/idle-pulse checks: PASS, with unchanged
  bit-exact results and numerical error. The recorded SVG was rendered to PNG
  and visually inspected. Local Markdown links, SVG XML and whitespace checks
  passed; all Python sources compiled.
- GitHub's independent Ubuntu regression passed for checkpoint 5, including
  the Icarus 11 coverage-report portability fix. Every later push triggers the
  same workflow and retains source-specific evidence.

Evidence directories:

| Check | Local evidence |
|---|---|
| Full functional suite | `build/run_20261110T092614Z_httmiyil` |
| Final Python tests | `build/run_20261110T093129Z_bxar52hd` |
| Final synthesis/gate/STA | `build/run_20261110T093103Z_f35firng` |
| Final waveform/inference | `build/run_20261110T092735Z_g2wk_lb7` |

Current documentation covers architecture, cycle accounting, interface and
quantization contracts, verification scope, implementation assumptions, the
remaining roadmap, and accurate resume statements. Small result summaries are
committed; raw generated output remains in ignored run directories and CI
artifacts. Physical implementation/power, a scalable memory interface, full
coverage closure and trained-model evaluation remain explicitly open.
