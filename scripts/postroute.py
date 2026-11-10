"""Validate a routed netlist, annotate measured activity, and render its GDS."""

import json
import hashlib
import math
from pathlib import Path
import re
import shutil
import subprocess


def parse_activity(text):
    annotated=re.search(r"^vcd\s+(\d+)",text,re.MULTILINE)
    unannotated=re.search(r"^unannotated\s+(\d+)",text,re.MULTILINE)
    if not annotated or not unannotated:
        raise RuntimeError("Cannot parse activity annotation report")
    known,missing=int(annotated[1]),int(unannotated[1])
    fraction=known/(known+missing) if known+missing else 0
    if fraction<0.95: raise RuntimeError("Too few pins have measured activity annotations")
    return {"vcd_pins":known,"unannotated_pins":missing,"fraction":fraction}


def parse_power(text):
    match=re.search(r"^Total\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)",text,re.MULTILINE)
    if not match: raise RuntimeError("Cannot parse power report")
    result={key:float(value) for key,value in zip(("internal_W","switching_W","leakage_W","total_W"),match.groups())}
    if any(not math.isfinite(value) or value<0 for value in result.values()) or result["total_W"]==0:
        raise RuntimeError("Invalid power result")
    return result


def run_postroute(run):
    root=Path(__file__).resolve().parents[1]
    source=Path(run.args.physical_run).resolve()
    previous=json.loads((source/"summary.json").read_text())
    if previous["status"]!="PASS" or previous.get("suite")!="physical":
        raise RuntimeError("Postroute input must be a successful physical run")
    config=json.loads((root/"physical/toolchain.json").read_text())
    if previous["physical_toolchain"]["image"]!=config["image"]:
        raise RuntimeError("Physical run and analysis image differ")
    for relative,metadata in previous["physical_artifacts"].items():
        if hashlib.sha256((source/relative).read_bytes()).hexdigest()!=metadata["sha256"]:
            raise RuntimeError("A physical input artifact changed after validation")
    result=source/"results/sky130hd/int8_memory_gemm/base"
    stage=run.directory/"analysis_sources"
    stage.mkdir()
    for extension in ("v","odb","spef","gds"):
        shutil.copy2(result/f"6_final.{extension}",stage/f"design.{extension}")
    sdc=(result/"6_final.sdc").read_text()
    sdc,count=re.subn(r"(-period\s+)[0-9.]+",r"\g<1>10.0",sdc,count=1)
    if count!=1: raise RuntimeError("Cannot identify final clock constraint")
    (stage/"design_100MHz.sdc").write_text(sdc)
    shutil.copy2(root/"physical/postroute.tcl",stage/"postroute.tcl")
    shutil.copy2(root/"physical/render_layout.py",stage/"render_layout.py")
    docker=run.tool("docker")
    name=f"int8-analysis-{run.directory.name}".lower().replace("_","-")
    created=False
    success=False
    try:
        run.run("postroute_create",[docker,"create","--name",name,"--platform",config["platform"],"--network","none",
                config["image"],"bash","-c","source /OpenROAD-flow-scripts/env.sh && mkdir -p /output && "
                "openroad -no_init -exit /project/postroute.tcl && "
                "QT_QPA_PLATFORM=offscreen klayout -z -r /project/render_layout.py"],timeout=120)
        created=True
        liberty=run.directory/"physical_cells.lib"
        run.run("physical_liberty_copy",[docker,"cp",f"{name}:/OpenROAD-flow-scripts/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib",str(liberty)],timeout=120)
        models=run.directory/"physical_cell_models.v"
        ys=run.directory/"physical_models.ys"
        ys.write_text(f'read_liberty -ignore_miss_func "{liberty}"\nwrite_verilog -noattr "{models}"\n')
        run.run("physical_cell_models",[run.tool("yosys"),"-Q","-s",str(ys)],[r"End of script"])
        netlist,count=re.subn(r"\bmodule memory_gemm\s*\(","module memory_gemm_gate (",(stage/"design.v").read_text())
        if count!=1: raise RuntimeError("Cannot identify physical top module")
        gate=run.directory/"physical_gate.v"
        gate.write_text(netlist)
        executable=run.directory/"physical_gate_sim"
        run.run("physical_gate_build",[run.tool("iverilog"),"-g2012","-DPHYSICAL_NETLIST","-s","tb_memory_gemm","-o",str(executable),
                str(models),str(gate),"tb/physical_memory_adapter.sv","tb/tb_memory_gemm.sv"])
        run.run("physical_gate_workload",[run.tool("vvp"),str(executable),"+SEED=20261110",f"+WAVE={stage/'workload.vcd'}"],
                [r"PASS: Memory GEMM",r"jobs=8"],timeout=300)
        run.run("postroute_inputs",[docker,"cp",str(stage),f"{name}:/project"],timeout=120)
        log=run.run("postroute_analysis",[docker,"start","--attach",name],[r"PASS: Postroute timing and activity analysis completed"],timeout=300)
        success=True
    finally:
        if created:
            if not success:
                subprocess.run([docker,"stop","--time","5",name],capture_output=True,timeout=30)
            collected=subprocess.run([docker,"cp",f"{name}:/output/.",str(run.directory)],capture_output=True,text=True,timeout=120)
            (run.directory/"postroute_collect.log").write_text(collected.stdout+collected.stderr)
        subprocess.run([docker,"rm","-f",name],capture_output=True,timeout=30)
    if collected.returncode: raise RuntimeError("Cannot collect postroute analysis outputs")
    annotation=re.search(r"ACTIVITY_ANNOTATION_BEGIN\n(.*?)ACTIVITY_ANNOTATION_END",log,re.DOTALL)
    if not annotation: raise RuntimeError("Missing activity-annotation report")
    (run.directory/"activity_annotation.rpt").write_text(annotation[1])
    annotation_metrics=parse_activity(annotation[1])
    setup=float(re.search(r"worst slack max ([-\d.]+)",log)[1])
    hold=float(re.search(r"worst slack min ([-\d.]+)",log)[1])
    if setup<0 or hold<0: raise RuntimeError("Routed design does not meet the 100MHz analysis constraints")
    powers={}
    for label in ("vectorless","workload"):
        text=(run.directory/f"power_{label}_100MHz.rpt").read_text()
        powers[label]=parse_power(text)
    if not (run.directory/"layout.png").is_file(): raise RuntimeError("GDS rendering was not produced")
    run.report["postroute"]={"physical_run":str(source),"clock_period_ns":10,
                            "setup_slack_ns":setup,"hold_slack_ns":hold,"power":powers,
                            "activity_annotation":annotation_metrics,
                            "activity_scope":"zero-delay routed-netlist simulation; eight jobs plus protocol/reset preparations"}
    run.report["postroute_input_sha256"]={path.name:hashlib.sha256(path.read_bytes()).hexdigest()
                                          for path in stage.iterdir() if path.is_file()}
    (run.directory/"postroute_metrics.json").write_text(json.dumps(run.report["postroute"],indent=2)+"\n")
    run.save()
