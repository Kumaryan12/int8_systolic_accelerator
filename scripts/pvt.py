"""Analyze a checksummed routed design at three PVTs with unchanged extracted RC.

PASS means that all analyses executed, not that all requested clocks closed.
Use --require-timing-closure to turn any negative slack into a failing run.
"""

import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import urllib.request


def parse_timing(text):
    result={}
    for label,kind in (("setup","max"),("hold","min")):
        match=re.search(rf"PVT_{label.upper()}\s+worst slack {kind} (\S+)",text)
        if not match:
            raise RuntimeError(f"Missing {label} slack in PVT report")
        try: value=float(match[1])
        except ValueError as error: raise RuntimeError("Invalid PVT slack") from error
        if not math.isfinite(value): raise RuntimeError("Non-finite PVT slack")
        result[f"{label}_slack_ns"]=value
    result["timing_closed"]=all(value>=0 for value in result.values())
    return result


def checked_library(path,expected):
    if hashlib.sha256(path.read_bytes()).hexdigest()!=expected:
        raise RuntimeError(f"Library checksum mismatch: {path.name}")
    return path


def fetch_library(cache,corner,metadata):
    cache.mkdir(parents=True,exist_ok=True)
    path=cache/f"sky130_fd_sc_hd__{corner}.lib"
    if not path.is_file():
        temporary=path.with_suffix(".download")
        try:
            with urllib.request.urlopen(metadata["url"],timeout=60) as response, temporary.open("wb") as output:
                shutil.copyfileobj(response,output)
            checked_library(temporary,metadata["sha256"])
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)
    return checked_library(path,metadata["sha256"])


def validate_source(source,config):
    previous=json.loads((source/"summary.json").read_text())
    if previous["status"]!="PASS" or previous.get("suite")!="physical":
        raise RuntimeError("PVT input must be a successful physical run")
    if previous["physical_toolchain"]["image"]!=config["image"]:
        raise RuntimeError("Physical run and PVT image differ")
    for relative,metadata in previous["physical_artifacts"].items():
        if hashlib.sha256((source/relative).read_bytes()).hexdigest()!=metadata["sha256"]:
            raise RuntimeError("A physical input artifact changed after validation")
    return previous


def run_pvt(run):
    root=Path(__file__).resolve().parents[1]
    source=Path(run.args.physical_run).resolve()
    config=json.loads((root/"physical/toolchain.json").read_text())
    validate_source(source,config)
    manifest=json.loads((root/"physical/pvt_libraries.json").read_text())
    libraries={corner:fetch_library(root/"build/pvt_cache",corner,metadata)
               for corner,metadata in manifest["downloads"].items()}
    stage=run.directory/"pvt_sources"
    stage.mkdir()
    result=source/"results/sky130hd/int8_memory_gemm/base"
    for ext in ("odb","spef"):
        shutil.copy2(result/f"6_final.{ext}",stage/f"design.{ext}")
    shutil.copy2(root/"physical/pvt.tcl",stage/"pvt.tcl")
    docker=run.tool("docker")
    tt=run.directory/"sky130_fd_sc_hd__tt_025C_1v80.lib"
    metrics=[]
    for corner in ("tt_025C_1v80","ss_100C_1v60","ff_n40C_1v95"):
        for period in run.args.pvt_periods:
            label=f"{corner}_{period:g}ns"
            output=run.directory/label
            output.mkdir()
            sdc,count=re.subn(r"(-period\s+)[0-9.]+",rf"\g<1>{period}",(result/"6_final.sdc").read_text(),count=1)
            if count!=1: raise RuntimeError("Cannot identify final clock constraint")
            (stage/"design.sdc").write_text(sdc)
            name=f"int8-pvt-{run.directory.name}-{label}".lower().replace("_","-")
            created=False
            success=False
            try:
                run.run(f"{label}_create",[docker,"create","--name",name,"--platform",config["platform"],"--network","none",
                    config["image"],"bash","-c","source /OpenROAD-flow-scripts/env.sh && mkdir -p /output && "
                    "openroad -no_init -exit /project/pvt.tcl"],timeout=120)
                created=True
                if corner=="tt_025C_1v80" and not tt.exists():
                    run.run("pvt_tt_copy",[docker,"cp",f"{name}:/OpenROAD-flow-scripts/flow/platforms/sky130hd/lib/{tt.name}",str(tt)],timeout=120)
                    checked_library(tt,manifest[corner]["sha256"])
                    libraries[corner]=tt
                shutil.copy2(libraries[corner],stage/"corner.lib")
                run.run(f"{label}_copy",[docker,"cp",str(stage),f"{name}:/project"],timeout=120)
                log=run.run(f"{label}_analysis",[docker,"start","--attach",name],[r"PASS: PVT analysis completed"],timeout=300)
                success=True
            finally:
                if created:
                    if not success: subprocess.run([docker,"stop","--time","5",name],capture_output=True,timeout=30)
                    collected=subprocess.run([docker,"cp",f"{name}:/output/.",str(output)],capture_output=True,text=True,timeout=120)
                    (output/"collect.log").write_text(collected.stdout+collected.stderr)
                subprocess.run([docker,"rm","-f",name],capture_output=True,timeout=30)
            if collected.returncode: raise RuntimeError("Cannot collect PVT outputs")
            metrics.append({"corner":corner,"period_ns":period,**parse_timing(log)})
    report={"physical_run":str(source),"design":"memory_gemm","corners":metrics,
            "all_timing_closed":all(row["timing_closed"] for row in metrics),
            "scope":"three cell PVT corners; same routed ODB and extracted RC; propagated clocks; raw reset excepted; no RC-corner/foundry signoff",
            "libraries":manifest,"image":config["image"],
            "physical_input_sha256":{f"6_final.{ext}":hashlib.sha256((result/f"6_final.{ext}").read_bytes()).hexdigest() for ext in ("odb","spef","sdc")}}
    run.report["pvt"]=report
    (run.directory/"pvt_metrics.json").write_text(json.dumps(report,indent=2)+"\n")
    run.save()
    if run.args.require_timing_closure and not report["all_timing_closed"]:
        raise RuntimeError("PVT timing closure required, but one or more corners have negative slack")
