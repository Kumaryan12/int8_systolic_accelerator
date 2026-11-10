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
import tempfile
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


def parse_path_slack(text):
    values=re.findall(r"^\s*(\S+)\s+slack \((?:MET|VIOLATED)\)",text,re.MULTILINE)
    try: slacks=[float(value) for value in values]
    except ValueError as error: raise RuntimeError("Invalid reset path slack") from error
    if not slacks or not all(math.isfinite(value) for value in slacks):
        raise RuntimeError("Missing or non-finite reset path slack")
    return min(slacks)


def checked_library(path,expected):
    if hashlib.sha256(path.read_bytes()).hexdigest()!=expected:
        raise RuntimeError(f"Library checksum mismatch: {path.name}")
    return path


def fetch_library(cache,corner,metadata):
    cache.mkdir(parents=True,exist_ok=True)
    path=cache/f"sky130_fd_sc_hd__{corner}.lib"
    if not path.is_file():
        with tempfile.NamedTemporaryFile(dir=cache,prefix=f"{corner}_",suffix=".download",delete=False) as temporary_file:
            temporary=Path(temporary_file.name)
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
    previous=validate_source(source,config)
    design=previous["physical_toolchain"]["design"]
    nickname=previous["physical_toolchain"].get("nickname",f"int8_{design}")
    if design not in ("memory_gemm","axi_gemm"):
        raise RuntimeError("Unsupported physical top")
    manifest=json.loads((root/"physical/pvt_libraries.json").read_text())
    libraries={corner:fetch_library(root/"build/pvt_cache",corner,metadata)
               for corner,metadata in manifest["downloads"].items()}
    stage=run.directory/"pvt_sources"
    stage.mkdir()
    result=source/f"results/sky130hd/{nickname}/base"
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
                    if design=="axi_gemm": run_axi_gate(run,result,tt)
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
            row={"corner":corner,"period_ns":period,**parse_timing(log)}
            if design=="axi_gemm":
                for check in ("recovery","removal"):
                    if f"library {check} time" not in (output/f"{check}.rpt").read_text():
                        raise RuntimeError(f"Qualified reset has no reported {check} paths")
                for check in ("recovery","removal","reset_sync_setup"):
                    row[f"{check}_slack_ns"]=parse_path_slack((output/f"{check}.rpt").read_text())
                    row["timing_closed"] &= row[f"{check}_slack_ns"]>=0
                row["qualified_reset_checks_reported"]=True
                stages=re.search(r"^RESET_SYNC_STAGES (.+)$",log,re.MULTILINE)
                if not stages or stages[1].count("release_pipe")!=2:
                    raise RuntimeError("Expected two preserved reset synchronizer stages")
                row["reset_stages"]=stages[1]
                spacing=re.search(r"^RESET_SYNC_SPACING_UM (\S+)$",log,re.MULTILINE)
                if not spacing or not math.isfinite(float(spacing[1])):
                    raise RuntimeError("Missing reset synchronizer physical spacing")
                row["reset_stage_manhattan_um"]=float(spacing[1])
                sync_report=(output/"reset_sync_setup.rpt").read_text()
                if "Startpoint: reset_release.release_pipe[0]" not in sync_report or "Endpoint: reset_release.release_pipe[1]" not in sync_report:
                    raise RuntimeError("Reset synchronizer interstage timing path missing")
            metrics.append(row)
    report={"physical_run":str(source),"design":design,"corners":metrics,
            "all_timing_closed":all(row["timing_closed"] for row in metrics),
            "scope":"three cell PVT corners; same routed ODB and extracted RC; propagated clocks; raw reset excepted; no RC-corner/foundry signoff",
            "libraries":manifest,"image":config["image"],
            "physical_input_sha256":{f"6_final.{ext}":hashlib.sha256((result/f"6_final.{ext}").read_bytes()).hexdigest() for ext in ("odb","spef","sdc")}}
    if design=="axi_gemm":
        report["scope"]="three cell PVTs; same extracted RC; propagated clocks; internal qualified-reset recovery/removal timed; only raw reset into synchronizer excepted; no RC-corner/foundry signoff"
    run.report["pvt"]=report
    (run.directory/"pvt_metrics.json").write_text(json.dumps(report,indent=2)+"\n")
    run.save()
    if run.args.require_timing_closure and not report["all_timing_closed"]:
        raise RuntimeError("PVT timing closure required, but one or more corners have negative slack")


def run_axi_gate(run,result,liberty):
    """Reuse the protocol/scoreboard test against the exact routed AXI netlist."""
    models=run.directory/"axi_physical_cells.v"
    script=run.directory/"axi_physical_models.ys"
    script.write_text(f'read_liberty -ignore_miss_func "{liberty}"\nwrite_verilog -noattr "{models}"\n')
    run.run("axi_physical_cell_models",[run.tool("yosys"),"-Q","-s",str(script)],[r"End of script"])
    netlist,count=re.subn(r"\bmodule axi_gemm\s*\(","module axi_gemm_gate (",(result/"6_final.v").read_text())
    if count!=1: raise RuntimeError("Cannot identify routed AXI module")
    gate=run.directory/"axi_physical_gate.v"
    gate.write_text(netlist)
    executable=run.directory/"axi_physical_sim"
    run.run("axi_physical_build",[run.tool("iverilog"),"-g2012","-DPHYSICAL_AXI","-s","tb_axi_gemm","-o",str(executable),
                                str(models),str(gate),"tb/tb_axi_gemm.sv"])
    for seed in run.args.seeds:
        run.run(f"axi_physical_seed{seed}",[run.tool("vvp"),str(executable),f"+SEED={seed}"],
                [r"PASS: AXI GEMM",r"resets=7"],timeout=300)
    run.report["axi_routed_gate_seeds"]=run.args.seeds
    run.report["axi_routed_netlist_sha256"]=hashlib.sha256((result/"6_final.v").read_bytes()).hexdigest()
    run.save()
