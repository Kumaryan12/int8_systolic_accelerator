"""Shared exact workloads for native CPU and real RTL cycle comparisons."""

import hashlib
import json
import os
import platform
import random
import subprocess
import sys
from pathlib import Path

from digit_model import export_model, integer_logits, packed_values, read_dataset, train_classifier
from quantization import requantize_int


def gemm(a, b):
    return [[sum(x*y for x, y in zip(row, col)) for col in zip(*b)] for row in a]


def run_cpu_benchmark(run):
    root = Path(__file__).resolve().parents[1]
    manifest, splits = read_dataset(root)
    weights = train_classifier(splits["train"], manifest["training"])
    model = export_model(weights, splits["train"])
    rng = random.Random(20261110)
    jobs = []
    for m, k, n in ((3,5,7), (4,4,4), (8,8,8)):
        a = [[rng.randint(-128,127) for _ in range(k)] for _ in range(m)]
        b = [[rng.randint(-128,127) for _ in range(n)] for _ in range(k)]
        jobs.append(dict(name=f"gemm_{m}x{k}x{n}", a=a, b=b, multiplier=1, shift=10, relu=False))
    jobs.append(dict(name="signed_extremes_2x17x3",a=[[-128]*17,[127]*17],
                     b=[[-128,127,(-1 if i%2 else 1)] for i in range(17)],multiplier=1,shift=1,relu=False))
    b = [list(col) for col in zip(*model["weights_int8"])]
    for m in (1,4):
        a = [integer_logits(features, model)[0] for features, _ in splits["test"][:m]]
        jobs.append(dict(name=f"digits_{m}x65x10", a=a, b=b, multiplier=model["multiplier"], shift=model["shift"], relu=False))
    lines = [str(len(jobs))]
    for job in jobs:
        a, b = job["a"], job["b"]
        job["shape_M_K_N"] = [len(a),len(b),len(b[0])]
        job["accumulators"] = gemm(a,b)
        job["outputs"] = [[requantize_int(x,job["multiplier"],job["shift"],relu=job["relu"]) for x in row]
                          for row in job["accumulators"]]
        lines.append(" ".join(map(str,[job["name"],*job["shape_M_K_N"],job["multiplier"],job["shift"],int(job["relu"])])))
        for matrix in (a,b,job["accumulators"],job["outputs"]):
            lines.append(" ".join(str(x) for row in matrix for x in row))
    corpus = run.directory / "workloads.json"
    corpus.write_text(json.dumps({"schema_version":1,"dataset_sha256":manifest["sha256"],"jobs":jobs},indent=2)+"\n")
    vectors = run.directory / "workloads.txt"
    vectors.write_text("\n".join(lines)+"\n")
    executable = run.directory / "cpu_gemm"
    compiler = os.environ.get("CXX", "clang++")
    run.run("cpu_build", [compiler,"-O3","-std=c++17","-Wall","-Wextra","-Werror","bench/cpu_gemm.cpp","-o",str(executable)])
    output = run.run("cpu_measure", [str(executable),str(vectors)], [r'"mismatches":0'], timeout=180)
    metrics = json.loads(output)
    if platform.machine() == "arm64" and not metrics["neon_available"]:
        raise RuntimeError("Expected native NEON on arm64")
    metrics.update(machine=platform.machine(),os=platform.platform(),python=sys.version.split()[0],
                   compiler=subprocess.check_output([compiler,"--version"],text=True).splitlines()[0],
                   cpu=(subprocess.check_output(["sysctl","-n","machdep.cpu.brand_string"],text=True).strip()
                        if sys.platform=="darwin" else platform.processor()),
                   workload_sha256=hashlib.sha256(corpus.read_bytes()).hexdigest(),
                   source_sha256=run.report["source_sha256"],git_commit=run.report["git_commit"],
                   cpu_energy_pj_per_mac=None,
                   energy_scope="Unavailable: no privileged CPU power samples; no TDP-based estimate",
                   scope="Single thread; warm repeated operands; 9 samples; median wall time; allocation excluded; packed and pack+GEMM+requantize reported separately; no affinity pinning")
    # Run exactly the same matrices and integer postprocessing through RTL.
    for job in jobs:
        m,k,n = job["shape_M_K_N"]
        w = 16+(k-1).bit_length()
        inputs = run.directory / (job["name"]+"_rtl.txt")
        flat = lambda matrix: [x for row in matrix for x in row]
        inputs.write_text(" ".join([packed_values(flat(job["a"]),8),packed_values(flat(job["b"]),8),
                                   packed_values(flat(job["accumulators"]),w),packed_values(flat(job["outputs"]),8),
                                   str(job["multiplier"]),str(job["shift"]),str(int(job["relu"]))])+"\n")
        rtl = run.directory / (job["name"]+"_rtl")
        run.run(job["name"]+"_build",[run.tool("iverilog"),"-g2012","-s","tb_shared_gemm","-o",str(rtl),
                f"-Ptb_shared_gemm.M={m}",f"-Ptb_shared_gemm.K={k}",f"-Ptb_shared_gemm.N={n}",
                "rtl/mac_pe.sv","rtl/systolic_array.sv","rtl/tiled_gemm.sv","rtl/requantize.sv","tb/tb_shared_gemm.sv"])
        log=run.run(job["name"]+"_rtl",[run.tool("vvp"),str(rtl),f"+INPUT={inputs}"],[r"PASS: shared GEMM cycles=\d+"])
        import re
        cycles=int(re.search(r"cycles=(\d+)",log)[1])
        for row in metrics["results"]:
            if row["workload"]==job["name"]:
                row.update(rtl_cycles_after_accept=cycles,
                           rtl_estimated_ns_at_50mhz=cycles*20,
                           rtl_estimated_gmac_s_at_50mhz=(m*k*n)/(cycles*20),
                           rtl_scope="Cycle-verified packed tiled_gemm including requantization; 50MHz assumed, this elaboration not physically timed; no memory/AXI transfer")
    (run.directory/"cpu_benchmark.json").write_text(json.dumps(metrics,indent=2)+"\n")
    run.report["cpu_benchmark"]=metrics
    run.save()
