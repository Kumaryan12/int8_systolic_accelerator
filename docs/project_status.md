# Project status — 10 November 2026

The functional prototype now includes a verified compute tile, hardware tiled
GEMM, and hardware output requantization/ReLU. A single `make verify` rebuilds
and checks Python references, RTL, UVM, temporal assertions, coverage, tiled
matrices, and the small quantized layer example.

## Completed checkpoints

| Checkpoint | Delivered | Evidence |
|---|---|---|
| 1 | Git/GitHub, pinned UVM submodule, isolated regression logs, CI, synthesis/STA commands | [Results](results/checkpoint_1.md) |
| 2 | Three seeds, four RTL sizes, reset-phase sweeps, UVM busy/reset/recovery, abort-aware scoreboard, temporal SVA and coverage exports | [Results](results/checkpoint_2.md) |
| 3 | Functional mapped-netlist regression and N=2,3,4,8 area comparison | [Results](results/checkpoint_3.md) |
| 4 | RTL tiled GEMM, tail padding, wider accumulation and reset recovery | [Results](results/checkpoint_4.md) |
| 5 | Hardware requantization/ReLU, 1,900 boundary/random vectors, Python/RTL layer comparison | [Results](results/checkpoint_5.md) |
| 6 | Architecture explanation, recorded waveform illustration, updated verification plan, scope and resume wording | [Architecture](architecture.md) |

The project is stored in the private GitHub repository
[Kumaryan12/int8_systolic_accelerator](https://github.com/Kumaryan12/int8_systolic_accelerator).
Each checkpoint is committed and pushed separately. CI results and archived
logs are accessible through its Actions tab. Local run directories are ignored
by Git; curated checkpoint summaries are committed.

## Current functional evidence

- 18 Python unit tests, including regression failure/timeout handling.
- Baseline: 105 matrix pairs per seed, across three seeds.
- Advanced RTL: 211/214/217/229 completions per seed for N=2/3/4/8,
  with 4/7/10/22 reset-abort positions and a recovery after each abort.
- Functional coverage: 14/14 scenario bins and 9/9 operand-sign cross bins.
- UVM: 208 completions plus one reset abort and 3,328 output comparisons per seed.
- Six temporal assertions, measured code coverage, and LCOV exports.
- Hardware tiled GEMM: 777 completed jobs across seven shapes and three seeds.
- Requantization: 1,900 bit-exact vectors; layer demo: 21 exact integer outputs,
  48 clocks, max float-reference error 0.0215193, RMSE 0.00751376.
- Clean mapped base tile: three-seed functional gate tests and pre-layout STA.

## Remaining work

1. **Physical implementation:** acquire a complete physical PDK/flow, perform
   placement, clock-tree synthesis, routing, parasitic extraction and power
   analysis. Add corner coverage and reset recovery/removal analysis. Current
   area and frequency estimates are synthesis/pre-layout results only.
2. **Memory architecture:** replace broad register-backed buses with a defined
   SRAM/BRAM and host/DMA interface; add buffering and transfer/computation
   overlap. The current hardware scheduler is functional but expensive: its
   default wrapper synthesizes to about 134,088 generic cells, not SKY130 cells.
3. **Verification closure:** analyze uncovered expression/branch cases, add
   justified coverage goals, consider formal equivalence and reset assumptions,
   and expand supported parameter/configuration validation. Passing defined bins
   and finite seed sets are not exhaustive proof.
4. **Model integration:** use a trained model and representative calibration,
   add bias/per-channel quantization where required, measure task accuracy and
   end-to-end transfer-inclusive performance. The current demo is synthetic.

The next substantial design decision is the memory/host interface. Physical
signoff also needs technology views not present in this checkout. Neither is
silently counted as complete by the functional regression.
