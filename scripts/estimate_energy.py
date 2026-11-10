"""Derive a trace-inclusive ASIC energy estimate from an existing validated power run."""

import argparse
import hashlib
import json
from pathlib import Path
import re


def vcd_duration(path):
    unit_seconds={"s":1,"ms":1e-3,"us":1e-6,"ns":1e-9,"ps":1e-12,"fs":1e-15}
    scale=None; first=None; last=None
    with path.open() as stream:
        in_scale=False
        for line in stream:
            if "$timescale" in line: in_scale=True
            if in_scale:
                match=re.search(r"\b(1|10|100)\s*(s|ms|us|ns|ps|fs)\b",line)
                if match: scale=int(match[1])*unit_seconds[match[2]]
                if "$end" in line: in_scale=False
            if line.startswith("#"):
                value=int(line[1:])
                if last is not None and value<last: raise ValueError("Nonmonotonic VCD")
                if first is None:first=value
                last=value
    if scale is None or first is None or last<=first: raise ValueError("Missing VCD time span")
    return (last-first)*scale


def energy_estimate(source):
    report=json.loads((source/"summary.json").read_text())
    if report["status"]!="PASS" or report["suite"]!="postroute":
        raise ValueError("Input must be a passing postroute run")
    trace=source/"analysis_sources/workload.vcd"
    checksum=hashlib.sha256(trace.read_bytes()).hexdigest()
    if checksum!=report["postroute_input_sha256"]["workload.vcd"]:
        raise ValueError("Power activity trace changed")
    log=(source/"physical_gate_workload.log").read_text()
    jobs=re.search(r"METRIC .*\bjobs=(\d+)",log)
    shape=re.search(r"PASS: Memory GEMM shape=(\d+)x(\d+)x(\d+)",log)
    if not jobs or not shape: raise ValueError("Missing completed-job evidence")
    m,k,n=map(int,shape.groups())
    count=int(jobs[1]); macs=count*m*k*n
    if macs<=0:raise ValueError("No completed useful MACs")
    seconds=vcd_duration(trace)
    watts=report["postroute"]["power"]["workload"]["total_W"]
    return {"estimated_pj_per_useful_mac":watts*seconds/macs*1e12,
            "estimated_trace_energy_j":watts*seconds,"estimated_power_w":watts,
            "trace_duration_seconds":seconds,"completed_jobs":count,"shape_M_K_N":[m,k,n],
            "useful_macs":macs,"trace_sha256":checksum,"source_run":source.name,
            "scope":"SKY130 standard-cell streaming memory top, TT 25C 1.8V at 100MHz; OpenSTA workload power times entire zero-delay gate VCD duration, including reset/protocol/idle overhead; not silicon measurement, AXI power, or a matched CPU energy comparison"}


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--postroute-run",type=Path,required=True)
    parser.add_argument("--output",type=Path,required=True)
    args=parser.parse_args()
    metrics=energy_estimate(args.postroute_run)
    args.output.write_text(json.dumps(metrics,indent=2)+"\n")
    print(json.dumps(metrics,indent=2))
