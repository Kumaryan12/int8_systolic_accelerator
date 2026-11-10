# INT8 Systolic Array Accelerator

**Goal:** Build an interview-ready AI-hardware project: a 4x4 signed INT8
matrix-multiplication tile in SystemVerilog, then improve its verification
in ways relevant to ASIC Design & Verification roles.

**Status:** The compute tile has passing Python, Icarus RTL, and UVM tests.
`make verify` rebuilds and runs the verification suite, retaining logs and a
machine-readable summary. SKY130 synthesis and pre-layout timing scripts are
included. See [toolchain instructions](docs/toolchain.md) and
[project status](docs/project_status.md) for evidence and remaining work.

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
# Initialize the pinned UVM dependency after cloning
git submodule update --init --recursive

# Rebuild and run the complete verification suite
make verify

# Python-only checks, no third-party Python libraries required
make python-test
python3 scripts/reference.py
```

`make verify` requires Icarus/vvp, Verilator, a C++ compiler, make, and Python.
`make sim` runs the baseline tests alone. See the toolchain guide for individual
targets, multiple seeds, and synthesis/timing commands.

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
1. Expand seeded regression, temporal assertions and UVM control scenarios.
2. Validate mapped-netlist equivalence and document implementation assumptions.
3. Connect tiled GEMM to the hardware and complete an inference demonstration.
4. Measure physical timing and power when the physical-design flow is available.

**Note:** This is a learning/portfolio prototype, not a production IP core.
