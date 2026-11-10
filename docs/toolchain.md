# Rebuilding the project

Clone with the pinned UVM submodule:

```sh
git clone --recurse-submodules https://github.com/Kumaryan12/int8_systolic_accelerator.git
cd int8_systolic_accelerator
# If already cloned:
git submodule update --init --recursive
make verify
```

`make verify` runs Python tests, rebuilds and runs baseline and advanced Icarus
tests, checks all 14 defined functional bins, then rebuilds and runs UVM through
Verilator. It requires Python 3.10+, Icarus/vvp, Verilator, a C++ compiler, and
make. The runner uses only Python's standard library. Missing tools are errors;
a zero process exit without required pass markers is also an error.

Each invocation writes a new `build/run_<UTC timestamp>_<unique suffix>/`
directory with logs and `summary.json`. The summary records exact commands,
seed list, tool versions, source Git commit and working-tree changes, UVM
revision, return codes, and execution times. Previous runs are retained.

Individual commands:

```sh
make python-test
make sim
make advanced
make coverage
make uvm
make verify SEEDS="2026 20261110 42" RANDOM_CASES=200 JOBS=2
make synth
make sta
```

Tool executables default to PATH and can be overridden with `IVERILOG`, `VVP`,
`VERILATOR`, `YOSYS`, and `STA` environment variables. For the current machine:

```sh
STA="$HOME/eda-tools/OpenSTA/build/sta" make sta
```

`make synth` regenerates generic, SKY130 baseline, and clean timing-driven
netlists in the new run directory. `make sta` performs those builds and runs
OpenSTA on the newly generated clean netlist. Its report is still pre-layout,
typical-corner analysis with ideal clocks; it is not physical timing signoff.

The initial local validation uses Python 3.14.7, Icarus 13.0, Verilator 5.054,
Yosys 0.70+post, and OpenSTA 3.2.0. UVM is pinned to
`656f20d087370a7c742e00188d20bbf30fa95339` from `verilator/uvm`.
CI installs Icarus on Ubuntu 24.04 and builds Verilator tag `v5.054`, then runs
three regression seeds and uploads evidence, including when the job fails.
Exact CI tool versions appear in its archived summary.

Generated binaries, netlists and large build directories are excluded from Git.
Small curated result summaries belong in `docs/results/` with their provenance.
