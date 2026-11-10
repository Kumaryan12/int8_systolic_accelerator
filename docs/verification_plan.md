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
| Memory/stream path | Two job slots, seven shapes, frame errors, stalls, reset cancellation and seven stream/RAM properties | `make memory`, `make memory-sva` |
| Transfer-inclusive schedules | Serial and overlapped eight-job batches on identical interfaces | `make memory-bench` |
| Output quantization | INT32 limits, ties, saturation, zero points, ReLU and large shifts; 1,900 Python/RTL vectors | `make inference` |
| Layer numerical comparison | 21 exact integer results and bounded float-reference error | `make inference` |
| Structure and timing | Yosys checks and typical-corner base-tile OpenSTA | `make synth`, `make sta` |
| Routed default memory top | SKY130 placement/CTS/routing, extraction, router DRC and implementation LEC | `make physical` |
| Routed functional gates and power | Eight jobs, actual cell models, VCD activity, 100 MHz extracted timing | `make postroute PHYSICAL_RUN=...` |
| Trained model | All 1,797 official test images, 18,000 checked logits including padding | `make model` |

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
or SDF simulation. The physical flow separately includes extracted wires,
propagated clocks and workload-annotated power. Reset recovery/removal,
additional corners, SRAM macros and foundry signoff remain open.

`make axi` exercises seven matrix shapes at three seeds through the AXI4-Lite
register interface, seven reset situations per run, all AW/W arrival orders,
B/R stalls, byte strobes, SLVERR, counters, metadata and IRQ/W1C. Five temporal
response/ownership properties run under Verilator on the default shape. The
AXI suite is included in `make verify`.

`make pvt PHYSICAL_RUN=...` reuses validated routed artifacts at TT/SS/FF and
10/20 ns. A successful diagnostic run can contain timing failures; inspect
`timing_closed` or add `PVT_ARGS="--pvt-periods 20 --require-timing-closure"`
for a strict pass/fail gate. Libraries are pinned/checksummed and downloaded
into an ignored cache. RC and raw-reset exceptions remain unchanged.

`make sram` checks the banked OpenRAM backend through RAM unit/negative tests,
eight stream/AXI shapes at three seeds, temporal stream properties, synthesis
macro-count/fallback gates and matched backend cycle benchmarks. These checks
are included in `make verify`. SRAM views are pinned and vendored for offline CI.

`make rcx PHYSICAL_RUN=...` independently extracts RC-min/nom/max SPEFs from the
validated routed ODB using pinned public rule tables. Pass that successful
run via `make pvt PHYSICAL_RUN=... PVT_ARGS="--rcx-run build/run_... --pvt-periods 20 --require-timing-closure"`
to strictly gate all nine cell-PVT/RC combinations, including qualified reset
checks for AXI. The original fixed-SPEF path remains supported when this option
is absent. Unit gates reject malformed/nonfinite SPEFs, wrong units, incomplete
corner sets, layout/image mismatches and altered extraction artifacts.
