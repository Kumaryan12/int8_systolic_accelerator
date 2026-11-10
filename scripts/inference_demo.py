"""Run a reproducible 3x5 by 5x7 quantized linear layer + ReLU in real RTL."""

import json
import math
import random

from quantization import fixed_point_scale, requantize_int
from tiled_gemm import quantize_symmetric_int8, tiled_gemm_int8
from waveform_svg import waveform_svg


def packed_hex(matrix):
    values = [item for row in matrix for item in row]
    return f"{sum((value & 255) << (8*i) for i, value in enumerate(values)):0{2*len(values)}x}"


def run_demo(run):
    # Exercise integer boundaries independently of the floating-point example.
    vectors = []
    boundary_values = (-2**31, -65536, -257, -255, -5, -3, -1, 0, 1, 3, 5, 255, 257, 65536, 2**31-1)
    for value in boundary_values:
        for multiplier in (0, 1, 2**30, 2**31-1):
            for shift in (0, 1, 7, 31, 63):
                for zero, relu in ((0,False), (-7,True), (11,False)):
                    vectors.append((value,multiplier,shift,zero,int(relu),requantize_int(value,multiplier,shift,zero,relu)))
    rng = random.Random(20261110)
    for _ in range(1000):
        value, multiplier, shift = rng.randint(-2**31,2**31-1), rng.randrange(2**31), rng.randrange(64)
        zero, relu = rng.randint(-128,127), bool(rng.randrange(2))
        vectors.append((value,multiplier,shift,zero,int(relu),requantize_int(value,multiplier,shift,zero,relu)))
    path = run.directory / "requantization_vectors.txt"
    path.write_text("".join(" ".join(map(str, vector))+"\n" for vector in vectors))
    executable = run.directory / "requantize_sim"
    run.run("requantize_build", [run.tool("iverilog"), "-g2012", "-s", "tb_requantize", "-o", str(executable),
            "rtl/requantize.sv", "tb/tb_requantize.sv"])
    run.run("requantize_vectors", [run.tool("vvp"), str(executable), f"+VECTORS={path}"], [r"PASS: RTL requantization"])

    a = [[round(math.sin(1+r*5+k)*1.8,4) for k in range(5)] for r in range(3)]
    b = [[round(math.cos(2+k*7+c)*1.2,4) for c in range(7)] for k in range(5)]
    reference = [[max(0.0,sum(a[r][k]*b[k][c] for k in range(5))) for c in range(7)] for r in range(3)]
    qa, scale_a = quantize_symmetric_int8(a)
    qb, scale_b = quantize_symmetric_int8(b)
    scale_out = max(max(row) for row in reference)/120
    multiplier, shift = fixed_point_scale(scale_a*scale_b/scale_out)
    golden_accum = tiled_gemm_int8(qa,qb)
    inputs = run.directory / "inference_input.txt"
    inputs.write_text(f"{packed_hex(qa)} {packed_hex(qb)} {multiplier} {shift}\n")
    outputs = run.directory / "inference_output.txt"
    executable = run.directory / "inference_sim"
    run.run("inference_build", [run.tool("iverilog"), "-g2012", "-s", "tb_inference", "-o", str(executable),
            "rtl/mac_pe.sv", "rtl/systolic_array.sv", "rtl/tiled_gemm.sv", "rtl/requantize.sv", "tb/tb_inference.sv"])
    run.run("inference_rtl", [run.tool("vvp"), str(executable), f"+INPUT={inputs}", f"+OUTPUT={outputs}",
            f"+WAVE={run.directory / 'inference.vcd'}"], [r"PASS: Inference RTL completed outputs=21 cycles=48"])
    waveform_svg(run.directory / "inference.vcd", run.directory / "inference.svg")
    actual = [tuple(map(int,line.split())) for line in outputs.read_text().splitlines()]
    expected = [(value,requantize_int(value,multiplier,shift,relu=True)) for row in golden_accum for value in row]
    if actual != expected:
        raise RuntimeError("RTL accumulator or requantized output differs from Python reference")
    # Run the same quantized layer through the narrow, RAM-backed host path.
    memory_output=run.directory/"memory_inference_output.txt"
    memory_executable=run.directory/"memory_inference_sim"
    run.run("memory_inference_build",[run.tool("iverilog"),"-g2012","-s","tb_memory_inference","-o",str(memory_executable),
            "rtl/mac_pe.sv","rtl/systolic_array.sv","rtl/sync_dp_ram.sv","rtl/memory_gemm.sv",
            "rtl/requantize.sv","tb/tb_memory_inference.sv"])
    memory_log=run.run("memory_inference_rtl",[run.tool("vvp"),str(memory_executable),f"+INPUT={inputs}",
                      f"+OUTPUT={memory_output}",f"+WAVE={run.directory/'memory_inference.vcd'}"],
                      [r"PASS: Memory inference outputs=21"])
    memory_actual=[tuple(map(int,line.split())) for line in memory_output.read_text().splitlines()]
    if memory_actual!=expected:
        raise RuntimeError("Memory-backed RTL inference differs from the integer reference")
    import re
    transfer_metrics={key:int(value) for key,value in re.findall(r"(\w+)=(\d+)",re.search(r"MEMORY_INFERENCE .*",memory_log)[0])}
    root="tb_memory_inference"
    waveform_svg(run.directory/"memory_inference.vcd",run.directory/"memory_inference.svg",
                 signals=[(f"{root}.{name}",label) for name,label in
                          (("load_valid","input valid"),("load_ready","input ready"),("busy","engine busy"),
                           ("compute_done","compute done"),("result_valid","output valid"),("result_ready","output ready"),
                           ("dut.tile_busy","tile busy"))],
                 title="Memory-backed RTL layer — recorded host transfers",
                 subtitle="3×5 by 5×7 · 50 input words · 21 output words · receiver backpressure")
    errors = [abs(actual[r*7+c][1]*scale_out-reference[r][c]) for r in range(3) for c in range(7)]
    metrics = {"operation": "linear layer without bias, followed by ReLU", "shape_M_K_N": [3,5,7],
               "integer_outputs_checked": len(actual), "integer_mismatches": 0,
               "requantization_vectors_checked": len(vectors), "cycles_after_accept": 48,
               "scale_a": scale_a, "scale_b": scale_b, "scale_out": scale_out,
               "multiplier": multiplier, "shift": shift,
               "max_absolute_error": max(errors), "rmse": math.sqrt(sum(e*e for e in errors)/len(errors)),
               "max_absolute_error_limit": 0.15,
               "memory_integer_outputs_checked":len(memory_actual),"memory_integer_mismatches":0,
               "memory_host_cycles":transfer_metrics,
               "float_reference": reference,
               "rtl_dequantized": [[actual[r*7+c][1]*scale_out for c in range(7)] for r in range(3)]}
    (run.directory / "inference.json").write_text(json.dumps(metrics,indent=2)+"\n")
    run.report["inference"] = metrics
    run.save()
    if metrics["max_absolute_error"] > metrics["max_absolute_error_limit"]:
        raise RuntimeError("Inference quantization error exceeds documented demo tolerance")
    print(f"  PASS Python/RTL inference: 21 exact integer outputs; max error={max(errors):.6f}", flush=True)
