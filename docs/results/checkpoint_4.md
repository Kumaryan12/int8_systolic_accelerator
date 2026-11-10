# Checkpoint 4 — hardware tiled GEMM

`make gemm` passed on 10 November 2026 for seven (M,K,N) shapes:
(1,1,1), (3,5,7), (4,4,4), (7,9,5), (8,8,8), (9,2,11), and (2,17,3).
Each shape ran seeds 2026, 20261110 and 42, with 37 completed jobs and three
reset aborts per seed: 777 completed GEMMs in total.

The tests cover zero and extreme signed operands, mixed signs, randomized
matrices, tails in every dimension, accumulation across K tiles, busy-start
rejection, operand changes after capture, exact completion latency, retained
results, and reset at initial/middle/final computation positions. Mathematical
full-matrix sums are independent of tile scheduling.

`make synth` also passed, including a structural Yosys check of the new default
wrapper. Its generic synthesis took about 51 seconds on the local toolchain;
it is not a mapped area or frequency measurement.

Evidence: `build/run_20261110T091900Z_sl9nhmq8` and
`build/run_20261110T091923Z_iwdmrhum`. See `docs/hardware_gemm.md` for interface,
latency and scope. Existing base-tile RTL was reused without behavior changes.
