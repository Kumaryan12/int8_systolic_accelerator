# Pinned SKY130 SRAM views

Source: [VLSIDA/sky130_sram_macros](https://github.com/VLSIDA/sky130_sram_macros/tree/965df150c754fe2b3f93a0bd1f9883eb114279b2),
revision `965df150c754fe2b3f93a0bd1f9883eb114279b2`, Apache-2.0; see LICENSE.
`manifest.json` records exact hashes of the unmodified Verilog, TT Liberty,
LEF and license. These small views support reproducible offline simulation and
hard-macro synthesis binding without downloading an entire PDK.

`scripts/sram.py` checks the hashes before use and writes an isolated simulation
copy with an explicit 1ns/1ps time unit and the memory declaration moved before
its first reference. This declaration-only change supports Icarus 13; upstream
read/write, output invalidation and delay behavior are retained. The upstream
model's DELAY/T_HOLD parameters are explicitly arbitrary, not timing signoff.

The supplied Liberty is TT 1.8 V 25°C only. No SS/FF macro characterization or
macro physical integration is implied. No GDS is vendored here. See the
[backend contract](../../docs/sram_backend.md) for latency, collision rules,
capacity and the physical work still required.
