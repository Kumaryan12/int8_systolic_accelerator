"""Bit-exact integer output quantization, shared with RTL regression vectors."""

import math


def requantize_int(value, multiplier, shift, zero_point=0, relu=False):
    if any(type(item) is not int for item in (value, multiplier, shift, zero_point)):
        raise ValueError("Quantization operands must be integers")
    if not 0 <= multiplier < 2**31 or not 0 <= shift <= 63 or not -128 <= zero_point <= 127:
        raise ValueError("Multiplier, shift or zero point outside RTL representation")
    product = value*multiplier
    rounded = (abs(product)+(1 << (shift-1) if shift else 0)) >> shift
    output = (-rounded if product < 0 else rounded)+zero_point
    if relu:
        output = max(zero_point, output)
    return max(-128, min(127, output))


def fixed_point_scale(scale):
    """Approximate a positive real scale as multiplier / 2**shift."""
    if not math.isfinite(scale) or scale <= 0:
        raise ValueError("Scale must be finite and positive")
    mantissa, exponent = math.frexp(scale)
    multiplier = round(mantissa*(1 << 30))
    shift = 30-exponent
    if not 0 <= shift <= 63:
        raise ValueError("Scale cannot be represented by this multiplier/shift format")
    return multiplier, shift
