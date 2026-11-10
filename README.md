# INT8 Systolic Array Accelerator — RTL + Verification Starter

**Goal:** Build an interview-ready AI-hardware project: a 4x4 signed INT8
matrix-multiplication tile in SystemVerilog, then improve its verification
in ways relevant to ASIC Design & Verification roles.

**Status (reviewed 10 November 2026):** Baseline and advanced RTL simulations
pass, as do all 9 Python tests. The existing UVM executable also passes its
206-transaction test. SKY130 synthesis and pre-layout timing reports are available.
See [current project status](docs/project_status.md) for evidence, limitations,
and the remaining work; the original phase documents below describe the starter
plan and have not yet been fully updated.

## Architecture

```
       B[0,j] skewed on top edge, then flows DOWN
              v       v       v       v
 A[i,0] --> [PE00] -> [PE01] -> [PE02] -> [PE03]
              |         |         |         |
 A[i,1] --> [PE10] -> [PE11] -> [PE12] -> [PE13]
              |         |         |         |
 A[i,2] --> [PE20] -> [PE21] -> [PE22] -> [PE23]
              |         |         |         |
 A[i,3] --> [PE30] -> [PE31] -> [PE32] -> [PE33]

Each PE holds a signed 18-bit accumulator, forwards A rightward and B downward.
```

The ASCII labels A[i,0] denote row-edge injections (one row per cycle-skewed stream),
not single matrix entries. The controller captures two 4x4 matrices, then injects
A[i,k] at `t=k+i` and B[k,j] at `t=k+j`. PE(i,j) multiplies the matching pair
at `t=k+i+j`. The final result becomes valid after **10 compute cycles**
for N=4 (plus one clock edge to accept the transaction).

### Representation
- Input signed INT8: -128 to +127; all elements stored row-major.
- Output signed INT18: -131072 to +131071 (the actual N=4 dot product fits).
- 16 MAC PEs; each PE accumulates four products per job.
- One outstanding matrix multiplication; no hardware tiling or external memory yet.
  Python tiled GEMM and input quantization/dequantization models are available.

## Get started

```bash
# Works anywhere with Python 3, with no third-party libraries
make python-test
python3 scripts/reference.py

# Requires Icarus Verilog / vvp installed
make sim
```

`make sim` compiles the RTL and runs 5 directed + 100 random matrix tests.
It fails on any mismatch. It must be executed before claiming RTL validation.

## Repository layout

```
rtl/mac_pe.sv                Signed multiply-accumulate processing element
rtl/systolic_array.sv       Skewed feed, wavefront, matrix controller
tb/tb_systolic_array.sv    Self-checking directed and random testbench
scripts/reference.py        Golden model and cycle-schedule model
scripts/test_reference.py   Pure Python unit tests
docs/verification_plan.md  Verification targets and status
docs/roadmap.md            Future SV/UVM, synthesis and ML inference work
docs/resume_guidance.md     Accurate resume wording
```

## Next technical milestones
1. Run HDL simulator and debug until all tests pass.
2. Add reset-during-operation/start-while-busy tests, SVA, coverage.
3. Build a class-based SystemVerilog/UVM verification environment.
4. Run synthesis and document actual area/timing.
5. Extend to tiled GEMM and INT8 quantization/requantization.

**Note:** This is a learning/portfolio prototype, not a production IP core.
