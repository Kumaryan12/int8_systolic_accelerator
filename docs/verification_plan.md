# Verification plan and results

## DUT contracts

The base tile accepts a one-cycle `start` while idle, captures two square
signed-INT8 matrices, asserts `busy`, then pulses `done` after `3*N-2` compute
clocks. Results are signed and retained while idle until the next accepted
start clears them. Busy starts are ignored. Active-low asynchronous reset
clears datapath/control and aborts the pending job.

The hardware GEMM wrapper captures M×K and K×N operands, zero-pads partial
tiles and accumulates into `16+ceil(log2(K))` output bits. For TILE=4 it takes
12 clocks per dispatched tile after host acceptance; see `hardware_gemm.md`.
The integer postprocessor contract is specified in `quantization.md`.

## Regression matrix

| Check | Current coverage | Command |
|---|---|---|
| Golden math/cycle scheduling | Directed cases and 800 seeded Python random comparisons | `make python-test` |
| Baseline RTL | 5 directed + 100 randomized matrix pairs per seed | `make sim` |
| Size/control stress | N=2,3,4,8; 200 random inputs; resets across every compute boundary, recovery, busy starts, retained output and exact latency | `make advanced` |
| Functional scenario coverage | 14 scenario bins and nine operand-sign cross bins, required by runner | `make coverage` |
| UVM | Driver/monitor/agent/scoreboard; 208 normal completions plus reset abort/recovery per seed | `make uvm` |
| Temporal assertions | Acceptance clearing, control exclusion, done pulse, early/exact completion and idle retention | `make sva` and UVM |
| Code coverage | Verilator line/toggle/branch/expression reports and LCOV | `make sva` |
| Mapped functionality | Clean SKY130 netlist, Liberty-derived functional models, advanced protocol/arithmetic tests | `make gate` |
| Hardware tiling | Seven M,K,N shapes, tails, K partitions, range extremes and three reset positions | `make gemm` |
| Output quantization | INT32 limits, ties, saturation, zero points, ReLU and large shifts; 1,900 Python/RTL vectors | `make inference` |
| Layer numerical comparison | 21 exact integer results and bounded float-reference error | `make inference` |
| Structure and timing | Yosys checks and typical-corner base-tile OpenSTA | `make synth`, `make sta` |

Default seeds are 2026, 20261110 and 42. `make verify` rebuilds all functional
checks from source and rejects missing tools, simulation failures, missing pass
markers, missing required bins, UVM errors/fatals, integer mismatches and a layer
error above the documented tolerance. CI uses an independent Linux toolchain.
A coverage-report portability issue found by CI was fixed by reporting from an
explicit completion event rather than relying on an array loop in `final`.

## Evidence and remaining gaps

Each run records source SHA256 hashes, Git state, pinned UVM revision, tools,
commands, seeds, return codes, logs and elapsed times. Small checkpoint summaries
are in `docs/results/`. Generated logs, LCOV and inference waveforms are retained
locally and uploaded by CI.

Manual functional bins are a finite test plan, not exhaustive coverage closure.
Verilator summaries include verification code and collapse repeated instance
paths. Inspect uncovered points before claiming closure. Gate simulation uses
functional library models without delays; it is not a formal equivalence proof
or SDF simulation. Reset recovery/removal, physical parasitics, additional timing
corners and power require further implementation work.
