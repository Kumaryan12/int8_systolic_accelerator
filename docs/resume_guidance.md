# Resume guidance: do not claim unfinished work

## Current honest wording (prototype, until HDL simulation)
**INT8 Systolic Array Accelerator (in progress)** | SystemVerilog, Python
- Designed a 4x4 output-stationary systolic datapath with 16 signed INT8 MAC units and 18-bit accumulators for 4x4 matrix multiplication.
- Developed a golden matrix-multiplication model and a cycle-level wavefront model in Python; drafted a self-checking SystemVerilog testbench for directed and randomized inputs.

## Replace only after verification
- Implemented and simulated a 4x4 INT8 systolic-array accelerator with 16 signed MAC units and 18-bit accumulation, validated against a Python reference using [number] test vectors.
- Built [actual SV/UVM coverage approach], achieving [measured coverage] and [measured synthesis/timing result] on [tool and process/device].

## Where it sits in the Cisco resume
1. Accelerator project, once functional.
2. Verified Wallace-tree multiplier project (accurately describe own contribution).
3. One software project emphasizing Python/C++, automated tests, CI/CD.
Keep IIT Madras internship, shorten AI-only project details.
