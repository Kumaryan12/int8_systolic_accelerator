"""Run a pinned, network-isolated OpenROAD container with isolated outputs."""

import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def extract_metrics(directory):
    logs=directory/"logs/sky130hd/int8_memory_gemm/base"
    route=json.loads((logs/"5_2_route.json").read_text())
    finish=json.loads((logs/"6_report.json").read_text())
    keys={"setup_slack_ns":"finish__timing__setup__ws","hold_slack_ns":"finish__timing__hold__ws",
          "cell_area_um2":"finish__design__instance__area__stdcell","stdcell_count":"finish__design__instance__count__stdcell",
          "die_area_um2":"finish__design__die__area","core_area_um2":"finish__design__core__area",
          "estimated_fmax_Hz":"finish__timing__fmax","vectorless_power_W":"finish__power__total"}
    if any(key not in finish for key in keys.values()) or "detailedroute__route__drc_errors" not in route:
        raise RuntimeError("Missing physical metrics in flow reports")
    result={name:finish[key] for name,key in keys.items()}
    result["route_drc_errors"]=route["detailedroute__route__drc_errors"]
    if result["route_drc_errors"]!=0 or result["setup_slack_ns"]<0 or result["hold_slack_ns"]<0:
        raise RuntimeError("Routed design has routing DRC or timing violations")
    proof=(logs/"6_final_lec_check.log").read_text()
    if "Circuits are IDENTICAL" not in proof:
        raise RuntimeError("Final implementation transformation equivalence check did not pass")
    result["implementation_lec_passed"]=True
    result["scope"]="SKY130HD TT 25C 1.8V, extracted wires, propagated clock, 20ns target; async reset release excepted"
    return result


def run_physical(run):
    root=Path(__file__).resolve().parents[1]
    config=json.loads((root/"physical/toolchain.json").read_text())
    docker=run.tool("docker")
    run.report["physical_toolchain"]=config
    run.save()
    name=f"int8-{run.directory.name}".lower().replace("_","-")
    # Copy a source snapshot rather than bind-mounting the user's workspace.
    # This also works when Docker Desktop file sharing is unavailable.
    staging=run.directory/"physical_sources"
    for relative in ("rtl/mac_pe.sv","rtl/systolic_array.sv","rtl/sync_dp_ram.sv","rtl/memory_gemm.sv",
                     "physical/config.mk","physical/memory_gemm.sdc"):
        target=staging/relative
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(root/relative,target)
    command=[docker,"create","--name",name,"--platform",config["platform"],"--network","none",
             config["image"],"bash","-c",
             "source /OpenROAD-flow-scripts/env.sh && mkdir -p /output && "
             "cd /OpenROAD-flow-scripts/flow && "
             f"make DESIGN_CONFIG=/project/physical/config.mk WORK_HOME=/output NUM_CORES={run.args.jobs} finish"]
    created=False
    succeeded=False
    try:
        run.run("physical_create",command,timeout=120)
        created=True
        run.run("physical_source_copy",[docker,"cp",str(staging),f"{name}:/project"],timeout=120)
        run.run("physical_flow",[docker,"start","--attach",name],timeout=1800)
        succeeded=True
    finally:
        if created:
            if not succeeded:
                subprocess.run([docker,"stop","--time","5",name],capture_output=True,timeout=30)
            collected=subprocess.run([docker,"cp",f"{name}:/output/.",str(run.directory)],capture_output=True,text=True,timeout=120)
            (run.directory/"physical_collect.log").write_text(collected.stdout+collected.stderr)
        subprocess.run([docker,"rm","-f",name],capture_output=True,text=True,timeout=30)
    if collected.returncode:
        raise RuntimeError("Could not collect the physical-flow outputs")
    result=run.directory/"results/sky130hd/int8_memory_gemm/base"
    required=[result/"6_final.gds",result/"6_final.odb"]
    if not all(path.is_file() for path in required):
        raise RuntimeError("OpenROAD did not produce both final GDS and ODB")
    spef=list(result.glob("*spef*"))
    if not spef:
        raise RuntimeError("No extracted-parasitic SPEF file was produced")
    run.report["physical_artifacts"]={str(path.relative_to(run.directory)):{
        "bytes":path.stat().st_size,"sha256":hashlib.sha256(path.read_bytes()).hexdigest()}
        for path in required+spef}
    run.report["physical_metrics"]=extract_metrics(run.directory)
    (run.directory/"physical_metrics.json").write_text(json.dumps(run.report["physical_metrics"],indent=2)+"\n")
    run.save()
