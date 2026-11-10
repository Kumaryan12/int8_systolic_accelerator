# Project status — 10 November 2026

## What we are building

A SystemVerilog matrix-multiplication accelerator for ASIC design and verification
practice. Its default configuration multiplies two 4x4 signed INT8 matrices using
16 multiply-accumulate processing elements (PEs). A values travel right, B values
travel down, and each PE retains one output sum in an 18-bit accumulator.

The controller captures both input matrices on an accepted start, skews their
injection into the array, and completes after 10 compute clocks. The acceptance
edge is separate. Only one job can be active. Results are retained while idle
and cleared on the next accepted start. This is a compute-tile prototype;
memory integration and complete neural-network inference remain future work.

## Implemented and checked in this review

| Area | Evidence and result | Scope |
|---|---|---|
| RTL core | `rtl/mac_pe.sv`, `rtl/systolic_array.sv` | Signed arithmetic, skewed feeds, start/busy/done controller |
| Baseline simulation | `make sim`: 5 directed + 100 random pairs passed | Fresh Icarus compile and run |
| Advanced simulation | 207 completed jobs; 31 busy-start checks; 207 output-retention checks; 1 reset check; 207 latency checks | Fresh Icarus compile and run through the coverage wrapper |
| Protocol checker | 208 accepted launches, 207 completions, 1 reset abort; no assertion failures | Procedural immediate assertions, not a concurrent temporal-SVA suite |
| Functional coverage | 14/14 manually defined bins exercised | Operand categories, control scenarios, and output signs; not full coverage closure |
| UVM environment | Existing `obj_dir/Vtb_uvm_top` passed 206 transactions and 3,296 output-element comparisons, with zero UVM errors/fatals | Sequence, transaction, driver, monitor, agent, environment, scoreboard and test exist; executable was run without rebuilding in this review |
| Python models | `make python-test`: all 9 tests passed | Includes 800 randomized schedule comparisons across N=2,3,4,8; rectangular tiled GEMM, tail padding, multi-tile accumulation and quantization tests |

The advanced simulation log is at
`build/review_20261110.9ehCLn/coverage.log`. This fresh build used:

```sh
iverilog -g2012 -Wall -s tb_coverage \
  -o build/review_20261110.9ehCLn/coverage_sim \
  rtl/mac_pe.sv rtl/systolic_array.sv \
  tb/systolic_protocol_checker.sv tb/tb_advanced.sv tb/tb_coverage.sv
vvp build/review_20261110.9ehCLn/coverage_sim
```

Other commands executed were `make python-test`, `make sim`, and:

```sh
obj_dir/Vtb_uvm_top +UVM_VERBOSITY=UVM_LOW +verilator+seed+20261110
```

Simulators reported missing RTL timescale declarations. UVM reported two
warnings associated with its no-DPI configuration. These runs passed despite
those warnings. The Python suite reported approximately 0.043 seconds runtime.

## Existing synthesis and timing results

Scripts and generated reports show generic Yosys synthesis, SKY130 mapping,
timing-driven mapping, and OpenSTA analysis. These reports were inspected,
not regenerated in this review.

The clean timing-driven variant reports:

| Metric | Recorded result |
|---|---:|
| Standard-cell count | 9,727 |
| Summed standard-cell area | 80,737.4336 square micrometres |
| Target clock period | 10 ns / 100 MHz |
| Worst setup slack | +2.872 ns |
| Worst hold slack | +0.075 ns |
| Reported minimum period | 7.13 ns |
| Reported estimated maximum frequency | 140.29 MHz |

Sources: `build/synth_sky130_clean.log`, `build/sta_clean.log`, and
`build/sta_clean_setup.rpt`. These use SKY130HD at the typical 25 C, 1.8 V
corner with ideal clocks and no extracted interconnect parasitics. Cell area
is not placed die area. Frequency is a pre-layout estimate, not a measured
device result. No power estimate or physical implementation is present.

`build/sta_clean_constraints.rpt` flags missing input delay on `rst_n`.
The SDC deliberately leaves asynchronous reset outside the synchronous delay
model, and defers reset recovery/removal analysis to future work.

## Remaining work, in priority order

1. **Make the project reproducible.** Add Makefile targets for advanced tests,
   coverage, rebuilding/running UVM, synthesis and STA. Record tool versions,
   pin the UVM dependency, retain regression logs and seed information, and
   add CI. This folder has no Git repository, so establish version control and
   ignore generated outputs. Update the original roadmap, verification plan,
   and resume guidance to match the evidence above.
2. **Strengthen verification.** Add multiple seeds, wider scenario coverage,
   and temporal SVA where supported. Extend UVM stimulus to exercise reset
   during computation and start while busy; those scenarios currently run in
   the procedural advanced testbench, while the reviewed UVM sequence covers
   directed/random normal transactions. Validate reset-abort handling through
   the scoreboard. Measure code coverage and useful cross coverage, and make
   unmet required coverage bins fail regressions. Verify supported RTL array
   sizes explicitly; Python size sweeps do not prove hardware parameterization.
3. **Validate and develop implementation results.** Make synthesis and timing
   reproducible, check mapped-netlist equivalence or gate-level functionality,
   document constraints and reset timing, and compare architecture variants.
   For physical-design scope, perform placement, clock-tree synthesis, routing,
   extracted timing across relevant corners, and power analysis.
4. **Connect software tiling to hardware.** `scripts/tiled_gemm.py` currently
   calls the mathematical Python tile function. Add a host/testbench or RTL
   scheduler that actually dispatches tiles to the DUT, handles padded edges,
   accumulates partial sums with a sufficient width, and compares full GEMMs
   against the reference. Define buffering and data-transfer interfaces.
5. **Complete an inference demonstration.** Existing Python code quantizes
   floating-point inputs symmetrically and dequantizes integer outputs. Add
   explicit output requantization, rounding and saturation behavior where
   required, then demonstrate a small layer/model with measured numerical error.
6. **Prepare the portfolio package.** Add architecture and cycle diagrams,
   example waveforms, a reproducible regression summary, and qualified area,
   timing, latency and throughput results. Base resume statements on the
   measured scope, including the distinction between software models and RTL.

## Recommended next milestone

A clean checkout should be able to rebuild and run the existing verification
suite through documented commands and produce an unambiguous result summary.
The compute core already has passing functional tests; reproducibility and
verification depth are the most immediate gaps.

This review changed documentation only; it did not modify RTL or verification
source. It also generated a fresh coverage executable/log and rebuilt the
baseline simulation executable through the existing Makefile.
