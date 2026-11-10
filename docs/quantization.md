# Quantized RTL layer demonstration

`make inference` runs a deterministic 3×5 by 5×7 linear layer without bias,
followed by ReLU. Python symmetrically quantizes floating-point inputs to
[-127,127], using one scale per operand and Python's nearest-even rounding.
The actual GEMM runs through `rtl/tiled_gemm.sv`. Twenty-one instantiated
`rtl/requantize.sv` blocks convert its integer sums to INT8 outputs.

The postprocessing contract is separate and bit-exact:

```text
product = accumulator × multiplier
rounded_magnitude = (abs(product) + (shift ? 2^(shift-1) : 0)) >> shift
scaled = sign(product) × rounded_magnitude + zero_point
if relu: scaled = max(zero_point, scaled)
result = clamp(scaled, -128, 127)
```

This rounds half ties away from zero, including negative values. Multiplier is
unsigned 31-bit, shift is 0..63, and zero point is signed INT8. Python's
`requantize_int` implements the identical integer rule. The demo approximates
`scale_A × scale_B / scale_output` as `multiplier / 2**shift`; no floating-point
arithmetic runs inside the DUT.

`make inference` checks 1,900 directed/random postprocessor vectors, including
INT32 limits, signed half ties, multiplier limits, zero multiplier, large shifts,
nonzero zero points, ReLU and both saturation limits. It then compares every
GEMM accumulator and INT8 layer output against Python, dequantizes the RTL
outputs, and measures error against independent floating-point matrix sums.
Its declared maximum-absolute-error tolerance for this fixed example is 0.15.
This tolerance does not describe general model accuracy.

The run directory includes `inference.json`, input/output vectors and
`inference.vcd`. Open the VCD with a waveform viewer, or use the generated
control-waveform illustration in the architecture documentation. Outputs become
valid 48 clocks after acceptance; the postprocessor is combinational. There is
no synthesis timing result for the complete GEMM-plus-postprocessing path.

The example calibrates output scale from its deterministic reference values
and uses synthetic inputs/weights. It is an arithmetic demonstration, not a
trained model benchmark. A real deployment needs representative calibration,
model-specific bias/activation rules and task-level accuracy evaluation.
