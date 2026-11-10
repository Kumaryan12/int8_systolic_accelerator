# Checkpoint 7 — synchronous memories and two job slots

Validated 10 November 2026:

- `make memory`: PASS. Seven (M,K,N) shapes × three seeds × eight completed
  jobs = 168 memory-backed GEMMs and 5,808 checked output elements.
- Each configuration rejects malformed frame boundaries and cancels partial
  loading, queued/running work, partially written output and stalled result
  delivery on reset. Random backpressure checks stable response payloads and
  both load/compute and drain/compute overlap.
- Synchronous RAM unit checks pass for registered-read latency, output hold,
  non-power-of-two depth and read-first behavior.
- `make memory-synth`: PASS. Exactly three memories retain one clocked read
  and one clocked write port: A=30×8, B=70×8, C=42×19 (1,598 bits total).
- Default generic fallback mapping: 20,025 cells. The previously measured
  packed-bus wrapper is 134,088 generic cells under the same flow/toolchain.
  SRAM macro area, physical timing and throughput are not inferred from this
  comparison.

Local evidence: `build/run_20261110T095014Z_kyaqsh1g` (functional tests),
`build/run_20261110T095030Z_t0lppm7z` (memory inference and generic synthesis).
See `docs/memory_interface.md` for the complete host/ownership/reset contract.
