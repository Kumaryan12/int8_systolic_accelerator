# INT8 Systolic Array Accelerator

A SystemVerilog matrix-multiplication prototype for ASIC design and verification:
a parameterized systolic tile, a rectangular hardware GEMM scheduler, and
integer output requantization with ReLU.

[![Verification](https://github.com/Kumaryan12/int8_systolic_accelerator/actions/workflows/verify.yml/badge.svg)](https://github.com/Kumaryan12/int8_systolic_accelerator/actions/workflows/verify.yml)

```sh
git clone --recurse-submodules https://github.com/Kumaryan12/int8_systolic_accelerator.git
cd int8_systolic_accelerator
make verify
```

`make verify` rebuilds every verification executable and retains a fresh log
folder and JSON summary. Requirements: Python 3.10+, Icarus/vvp, Verilator
5.054, a C++ compiler, and make. No third-party Python packages are needed.
See [toolchain setup](docs/toolchain.md) for versions and individual commands.

## Implemented and verified

| Part | Evidence |
|---|---|
| Default 4×4 signed INT8 tile | 16 MAC units, 18-bit sums, 10 compute clocks after capture |
| RTL size/seed regression | N=2,3,4,8; three seeds; reset at every compute boundary |
| Assertions and coverage | Procedural checker, six temporal properties, 14 scenario bins and nine sign-cross bins; code coverage/LCOV exports |
| UVM | 208 completed transactions, 3,328 output checks and one reset abort per seed; busy-start rejection and recovery |
| Hardware tiled GEMM | Seven shapes, three seeds, 777 completed GEMMs; padding and cross-tile accumulation |
| Integer postprocessing | 1,900 Python/RTL comparisons of rounding, saturation, zero points and ReLU |
| RTL layer demo | 21 exact integer outputs; 48 clocks; max float-reference error 0.02152 |
| Base-tile implementation | SKY130 mapping, functional gate simulation and pre-layout OpenSTA; array-size area comparison |

## Architecture and recorded waveform

A travels right and B travels down through the array; each processing element
keeps its own output sum. The hardware GEMM scheduler feeds zero-padded tiles
and accumulates partial results into a wider output matrix. Input/output ports
are packed row-major buses, with one outstanding job.

![Recorded tiled inference control waveform](docs/assets/inference.svg)

[Architecture and performance accounting](docs/architecture.md) ·
[Hardware GEMM contract](docs/hardware_gemm.md) ·
[Quantization contract](docs/quantization.md)

## Commands

```sh
make verify                    # Complete functional regression from source
make inference                 # Python/RTL layer comparison, JSON, VCD and SVG
make gate                      # Rebuild and test the mapped base-tile netlist
make sta                       # Synthesis, gate tests and OpenSTA (STA on PATH)
make architecture              # N=2,3,4,8 mapped cell-count/area sweep
```

Every run creates `build/run_<UTC timestamp>_<unique suffix>/`. Its summary
records source hashes, Git state, UVM revision, seeds, tool versions, commands,
execution times and failures. Build products are ignored by Git. GitHub Actions
runs the functional regression on Ubuntu and archives evidence.

## Implementation results and scope

The standalone clean 4×4 SKY130HD mapping reports **9,727 cells** and
**80,737.4336 µm² of summed cell area**. At TT, 25 C, 1.8 V with ideal clocks
and no extracted wires, OpenSTA reports **+2.872 ns setup slack** at a 10 ns
clock target and an estimated minimum period of **7.13 ns**. These results
apply to the base tile, not the tiled wrapper plus output postprocessing.

The prototype has no placed/routed implementation or power measurement. It
uses register-backed operand storage rather than SRAM/DMA, and the layer demo
uses synthetic inputs and weights. See [current status](docs/project_status.md),
[verification plan](docs/verification_plan.md), [roadmap](docs/roadmap.md), and
[checkpoint results](docs/results/) for completed work and remaining milestones.
