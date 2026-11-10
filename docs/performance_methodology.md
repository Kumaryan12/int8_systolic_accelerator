# CPU and accelerator comparison

`make cpu-bench` trains the fixed linear classifier and writes a versioned
`workloads.json` corpus plus a simple text export. The corpus contains signed
INT8 operands, exact INT32 accumulators, requantization parameters and INT8
outputs. Both the CPU and actual RTL consume those same values. The cases are
3×5×7, 4×4×4, 8×8×8, a signed-extreme/tail case, and one-/four-image digit
layers (1×65×10 and 4×65×10). This is also the interchange format for a future
inference engine; no separate engine is required.

## CPU measurement

The C++17 benchmark has a non-vectorized scalar reference and a native Arm
NEON implementation. It widens signed 8-bit products before accumulating in
32 bits, including a scalar K tail. The implementation uses
[Arm's widening multiply and pairwise accumulation intrinsics](https://arm-software.github.io/acle/neon_intrinsics/advsimd.html).
For K < 16, this baseline uses only its scalar tail. It is a small handwritten
baseline, not a claim about the best available M5 or Accelerate implementation.

Each case warms code/data, calibrates a timed batch to at least 20 ms, then
reports the median and range of nine batches. A compiler memory barrier keeps
all outputs observable. Results are checked before and after timing.
One thread is used, with no affinity pinning or other system-wide changes.
The recorded machine, OS, compiler, source hashes and corpus checksum identify
the experiment. Ordinary OS scheduling, thermal state and frequency scaling
still affect these measurements. Run without other CPU-heavy work.

Two scopes are reported separately:

- `gemm_prepacked`: reusable transposed weights, INT32 result; packing,
  requantization and allocation excluded.
- `pack_gemm_requantize`: transpose weights on every call, GEMM, integer
  rounding and INT8 saturation; allocation excluded.

Both start with INT8 inputs. Input float quantization, model training, host
argmax, dataset loading and transfers to an external device are excluded.
Throughput is useful M×K×N MACs divided by wall time; one MAC is one multiply
and accumulate. A GMAC/s is not a GOP/s under a two-operations-per-MAC convention.

## Accelerator comparison

The same corpus is checked through the real packed `tiled_gemm` and
`requantize` RTL. Cycle counts include launch, zero-padded tiles, cross-tile
accumulation and completion. Reported latency is after input acceptance.
Conversion to time assumes 50 MHz. **That is an analytical estimate, not a
board measurement or a timing result for the classifier elaboration.**
The physical 50 MHz result elsewhere belongs to the default standard-cell
AXI peripheral. Packed-core comparison excludes host/AXI/RAM transfer time;
it must not be called end-to-end application speedup. CPU warm-cache execution
and an ASIC time estimate have different physical scopes.

The current tiny accelerator does not beat this M5 baseline on these cases.
Report that outcome along with the scopes; small arrays, padding and repeated
tile launches constrain useful throughput.

## Array-size sweep

`make design-space` synthesizes N=2,3,4,8 through the same SKY130HD mapping
template and runs OpenSTA on every mapped netlist. It records summed cell
area, setup/hold slack at 100 MHz and an estimated required clock period.
The period is the larger of OpenSTA's reported minimum period and
`10 ns - worst setup slack`, retaining the specified I/O budgets and uncertainty.
These are TT, 25°C, 1.8 V, ideal-clock **pre-layout estimates**, with no routed
parasitics. Raw reset recovery/removal is outside this base-tile sweep.

For a full N×N GEMM there are N³ useful MACs. Compute takes 3N−2 cycles after
capture; minimum capture-to-capture spacing is 3N−1 cycles. Useful throughput
is therefore `N³ × frequency / (3N−1)`. Peak `N² × frequency` is also recorded
but is not sustained throughput. The plot compares 50 MHz and each size's
estimated setup limit, excluding host transfers. No cross-size power result
is inferred.

Plotting is optional and isolated from stdlib-only verification:

```sh
python3 -m venv build/analysis_env
build/analysis_env/bin/python -m pip install -r scripts/requirements-analysis.txt
build/analysis_env/bin/python scripts/plot_design_space.py \
  --input build/run_<sweep>/design_space.json --output docs/assets/design_space.svg
```

## Energy

CPU energy is left unavailable when privileged `powermetrics` samples are not
available. TDP, charger ratings and battery percentages are not substituted
for a workload measurement.

`scripts/estimate_energy.py` derives a separate ASIC estimate from a passing
postroute run. It verifies the original activity-trace hash, counts completed
useful MACs, and computes `power × full VCD duration / useful MACs`.
The recorded trace includes reset, frame checks, protocol stalls and idle
time. It is a trace-inclusive energy estimate, not isolated PE energy.

For the existing streaming-memory trace: 27.69079 mW × 17.81 µs / 840 useful
MACs = **587.11 pJ per useful MAC** at TT/100 MHz. This uses a zero-delay gate
activity trace and Liberty/SPEF power estimation, not a measured device.
It is not AXI power, classifier energy, or a matched CPU energy comparison.

```sh
python3 scripts/estimate_energy.py --postroute-run build/run_<postroute> \
  --output build/energy_estimate.json
```
