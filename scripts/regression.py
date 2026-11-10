"""Rebuild, execute, and retain evidence for accelerator checks (stdlib only)."""

import argparse
import hashlib
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
RTL = ["rtl/mac_pe.sv", "rtl/systolic_array.sv"]
ADVANCED = ["tb/systolic_protocol_checker.sv", "tb/tb_advanced.sv"]
MEMORY_RTL = RTL + ["rtl/sync_dp_ram.sv", "rtl/memory_gemm.sv"]


class Regression:
    def __init__(self, args):
        self.args = args
        (ROOT / "build").mkdir(exist_ok=True)
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        self.directory = Path(tempfile.mkdtemp(prefix=f"run_{stamp}_", dir=ROOT / "build"))
        self.report = {"suite": args.suite, "started_utc": stamp, "seeds": args.seeds,
                       "random_cases": args.random_cases, "sizes": getattr(args, "sizes", [4]),
                       "tools": {}, "steps": [], "status": "RUNNING"}
        sources = [ROOT / "Makefile"]
        for folder in ("rtl", "tb", "scripts", "synth", "timing", "constraints", "lib", "physical", "examples", "ci", "bench"):
            sources.extend(path for path in (ROOT / folder).rglob("*")
                           if path.is_file() and "__pycache__" not in path.parts)
        self.report["source_sha256"] = {
            str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(sources) if path.is_file()
        }
        for label, command in {
            "git_commit": ["git", "rev-parse", "HEAD"],
            "git_changes": ["git", "status", "--porcelain"],
            "uvm_commit": ["git", "-C", "third_party/uvm", "rev-parse", "HEAD"],
        }.items():
            result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
            self.report[label] = result.stdout.strip() if result.returncode == 0 else None
        print(f"Evidence: {self.directory.relative_to(ROOT)}", flush=True)
        self.save()

    def save(self):
        (self.directory / "summary.json").write_text(json.dumps(self.report, indent=2) + "\n")

    def tool(self, name):
        if name not in self.report["tools"]:
            executable = shutil.which(os.environ.get(name.upper(), name))
            if executable is None:
                raise RuntimeError(f"Required tool {name} missing; install it or set {name.upper()} to its path")
            version_arg = {"iverilog": "-V", "vvp": "-V", "yosys": "-V", "sta": "-version"}.get(name, "--version")
            result = subprocess.run([executable, version_arg], capture_output=True, text=True)
            self.report["tools"][name] = {"path": executable, "version": (result.stdout + result.stderr).splitlines()[0]}
            self.save()
        return self.report["tools"][name]["path"]

    def run(self, name, command, markers=(), timeout=300, env=None):
        log = self.directory / f"{name}.log"
        step = {"name": name, "command": command, "log": log.name, "status": "RUNNING"}
        self.report["steps"].append(step)
        self.save()
        print(f"  RUN  {name}: {shlex.join(command)}", flush=True)
        started = time.monotonic()
        try:
            with log.open("w") as output:
                process = subprocess.Popen(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT,
                                           env=env, start_new_session=True)
                try:
                    process.wait(timeout=timeout)
                except subprocess.TimeoutExpired:
                    # Compilers/synthesis tools spawn children; stop the full
                    # process group so a timed-out run cannot leave CPU jobs behind.
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
                    raise
            content = log.read_text(errors="replace")
            step["returncode"] = process.returncode
            if process.returncode != 0:
                raise RuntimeError(f"{name} exited with {process.returncode}")
            for marker in markers:
                if not re.search(marker, content):
                    raise RuntimeError(f"{name} did not report required result: {marker}")
            if re.search(r"^UVM_(?:ERROR|FATAL)[ \t]+[^ \t:\r\n]", content, re.MULTILINE):
                raise RuntimeError(f"{name} reported a UVM error/fatal")
            if re.search(r"^(?:Error:|%Error)", content, re.MULTILINE):
                raise RuntimeError(f"{name} reported a tool error")
            step["status"] = "PASS"
            return content
        except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
            step["status"] = "FAIL"
            step["error"] = str(error)
            print(log.read_text(errors="replace")[-6000:], file=sys.stderr)
            raise
        finally:
            step["seconds"] = round(time.monotonic() - started, 3)
            self.save()
            print(f"  {step['status']:4} {name} ({step['seconds']}s)", flush=True)

    def python(self):
        self.report["tools"]["python"] = {"path": sys.executable, "version": sys.version.splitlines()[0]}
        self.run("python", [sys.executable, "-m", "unittest", "discover", "-s", "scripts",
                            "-p", "test_*.py", "-v"], [r"\bOK\b"])

    def simulation(self, kind, size=4):
        top = {"sim": "tb_systolic_array", "advanced": "tb_advanced", "coverage": "tb_coverage"}[kind]
        sources = RTL + (["tb/tb_systolic_array.sv"] if kind == "sim" else ADVANCED)
        if kind == "coverage":
            sources += ["tb/tb_coverage.sv"]
        label = f"{kind}_n{size}"
        executable = self.directory / label
        command = [self.tool("iverilog"), "-g2012", "-Wall", "-s", top, "-o", str(executable)]
        if kind == "advanced":
            command += [f"-Ptb_advanced.RANDOM_CASES={self.args.random_cases}", f"-Ptb_advanced.N={size}"]
        elif kind == "coverage":
            command += [f"-Ptb_coverage.RANDOM_CASES={self.args.random_cases}"]
        self.run(f"{label}_build", command + sources)
        for seed in self.args.seeds:
            markers = [r"PASS: 5 directed"] if kind == "sim" else [r"PASS: Advanced verification completed"]
            if kind == "coverage":
                markers += [r"Bins covered : 14 / 14", r"Sign-pair bins : 9 / 9", r"PASS: All defined bins exercised"]
            self.run(f"{label}_seed{seed}", [self.tool("vvp"), str(executable), f"+SEED={seed}"], markers)

    def uvm(self):
        source = ROOT / "third_party/uvm/src"
        if not (source / "uvm_pkg.sv").is_file():
            raise RuntimeError("UVM missing: run git submodule update --init --recursive")
        obj = self.directory / "uvm_obj"
        self.run("uvm_build", [self.tool("verilator"), "--binary", "--timing", "--assert", "--sv",
                 "-Wno-fatal", "--top-module", "tb_uvm_top", "--Mdir", str(obj), "-j", str(self.args.jobs),
                 "+define+UVM_NO_DPI", f"-I{source}", "-Itb/uvm", str(source / "uvm_pkg.sv")]
                 + RTL + ["tb/systolic_sva.sv", "tb/uvm/systolic_if.sv", "tb/uvm/systolic_uvm_pkg.sv", "tb/uvm/tb_uvm_top.sv"],
                 timeout=900)
        for seed in self.args.seeds:
            self.run(f"uvm_seed{seed}", [str(obj / "Vtb_uvm_top"), "+UVM_VERBOSITY=UVM_LOW",
                     f"+NUM_RANDOM={self.args.random_cases}", f"+verilator+seed+{seed}"],
                     [r"\[TEST_PASS\]", r"\[CONTROL_PASS\]", r"UVM_ERROR\s*:\s*0", r"UVM_FATAL\s*:\s*0"])

    def gemm(self):
        for m, k, n in ((1,1,1), (3,5,7), (4,4,4), (7,9,5), (8,8,8), (9,2,11), (2,17,3)):
            label = f"gemm_{m}x{k}x{n}"
            executable = self.directory / label
            self.run(f"{label}_build", [self.tool("iverilog"), "-g2012", "-s", "tb_tiled_gemm",
                     "-o", str(executable), f"-Ptb_tiled_gemm.M={m}", f"-Ptb_tiled_gemm.K={k}",
                     f"-Ptb_tiled_gemm.N={n}"] + RTL + ["rtl/tiled_gemm.sv", "tb/tb_tiled_gemm.sv"])
            for seed in self.args.seeds:
                self.run(f"{label}_seed{seed}", [self.tool("vvp"), str(executable), f"+SEED={seed}"],
                         [r"PASS: Tiled RTL GEMM", r"reset_aborts=3"])

    def sva(self):
        obj = self.directory / "sva_obj"
        self.run("sva_build", [self.tool("verilator"), "--cc", "--exe", "--build", "--timing", "--assert",
                 "--coverage", "-Wno-fatal", "--top-module", "tb_sva_top", "--Mdir", str(obj),
                 "-j", str(self.args.jobs)] + RTL + ADVANCED + ["tb/systolic_sva.sv", "tb/tb_sva_top.sv",
                 str(ROOT / "tb/sva_main.cpp")], timeout=900)
        data = []
        for seed in self.args.seeds:
            path = self.directory / f"coverage_seed{seed}.dat"
            self.run(f"sva_seed{seed}", [str(obj / "Vtb_sva_top"), f"+SEED={seed}",
                     f"+verilator+coverage+file+{path}"], [r"PASS: Advanced verification completed"])
            data.append(str(path))
        self.run("code_coverage", [self.tool("verilator_coverage"), "--report", "summary,hier"] + data)
        self.run("lcov_export", [self.tool("verilator_coverage"), "--write-info",
                 str(self.directory / "coverage.info")] + data)

    def axi(self):
        sources = MEMORY_RTL + ["rtl/reset_sync.sv", "rtl/axi_gemm.sv", "tb/tb_axi_gemm.sv"]
        for m, k, n in ((1,1,1), (3,5,7), (4,4,4), (7,9,5), (8,8,8), (9,2,11), (2,17,3)):
            label = f"axi_{m}x{k}x{n}"
            executable = self.directory / label
            self.run(f"{label}_build", [self.tool("iverilog"), "-g2012", "-s", "tb_axi_gemm",
                     "-o", str(executable), f"-Ptb_axi_gemm.M={m}", f"-Ptb_axi_gemm.K={k}",
                     f"-Ptb_axi_gemm.N={n}"] + sources)
            for seed in self.args.seeds:
                self.run(f"{label}_seed{seed}", [self.tool("vvp"), str(executable), f"+SEED={seed}"],
                         [r"PASS: AXI GEMM", r"resets=7"])
        obj = self.directory / "axi_sva_obj"
        self.run("axi_sva_build", [self.tool("verilator"), "--binary", "--timing", "--assert",
                 "-Wno-fatal", "--top-module", "tb_axi_gemm", "--Mdir", str(obj),
                 "-j", str(self.args.jobs)] + sources, timeout=900)
        for seed in self.args.seeds:
            self.run(f"axi_sva_seed{seed}", [str(obj / "Vtb_axi_gemm"), f"+SEED={seed}"],
                     [r"PASS: AXI GEMM", r"resets=7"])

    def memory(self):
        executable = self.directory / "ram_sim"
        self.run("ram_build", [self.tool("iverilog"), "-g2012", "-s", "tb_sync_dp_ram", "-o", str(executable),
                 "rtl/sync_dp_ram.sv", "tb/tb_sync_dp_ram.sv"])
        self.run("ram_test", [self.tool("vvp"), str(executable)], [r"PASS: Synchronous RAM"])
        results = []
        shapes = ((1,1,1), (3,5,7), (4,4,4), (7,9,5), (8,8,8), (9,2,11), (2,17,3))
        for m,k,n in shapes:
            label=f"memory_{m}x{k}x{n}"
            executable=self.directory/label
            self.run(f"{label}_build", [self.tool("iverilog"), "-g2012", "-s", "tb_memory_gemm", "-o", str(executable),
                     f"-Ptb_memory_gemm.M={m}", f"-Ptb_memory_gemm.K={k}", f"-Ptb_memory_gemm.N={n}"]
                     + MEMORY_RTL + ["tb/tb_memory_gemm.sv"])
            for seed in self.args.seeds:
                log=self.run(f"{label}_seed{seed}", [self.tool("vvp"), str(executable), f"+SEED={seed}"],
                             [r"PASS: Memory GEMM", r"jobs=8"])
                metrics={key:int(value) for key,value in re.findall(r"(\w+)=(\d+)", re.search(r"METRIC .*",log)[0])}
                results.append({"shape":[m,k,n],"seed":seed,**metrics})
        self.report["memory_tests"]=results
        self.save()

    def memory_synthesis(self):
        for variant in ("memory_gemm", "memory_gemm_generic"):
            source=(ROOT/f"synth/{variant}.ys").read_text()
            script=re.sub(r"(?<![/\w])build/([\w.]+)",lambda match:f'"{self.directory/match[1]}"',source)
            path=self.directory/f"{variant}.ys"
            path.write_text(script)
            self.run(f"synth_{variant}",[self.tool("yosys"),"-Q","-s",str(path)],
                     [r"Found and reported 0 problems",r"End of script"])
        retained=json.loads((self.directory/"memory_gemm_ram.json").read_text())["modules"]["memory_gemm"]["cells"]
        memories={name:cell["parameters"] for name,cell in retained.items() if cell["type"]=="$mem_v2"}
        if len(memories)!=3 or any(int(p["RD_CLK_ENABLE"],2)!=1 or int(p["WR_CLK_ENABLE"],2)!=1 for p in memories.values()):
            raise RuntimeError("Expected three synchronous-read/write inferred memories")
        self.report["inferred_memories"]={name:{key:int(p[key],2) for key in ("WIDTH","SIZE","RD_PORTS","WR_PORTS")}
                                          for name,p in memories.items()}
        generic=json.loads((self.directory/"memory_gemm_generic.json").read_text())["modules"]["memory_gemm"]["cells"]
        self.report["memory_generic_cells"]=len(generic)
        self.save()

    def memory_sva(self):
        obj=self.directory/"memory_sva_obj"
        self.run("memory_sva_build",[self.tool("verilator"),"--binary","--timing","--assert","-Wno-fatal",
                 "--top-module","tb_memory_gemm","--Mdir",str(obj),"-j",str(self.args.jobs)]
                 +MEMORY_RTL+["tb/memory_stream_sva.sv","tb/tb_memory_gemm.sv"],timeout=900)
        for seed in self.args.seeds:
            self.run(f"memory_sva_seed{seed}",[str(obj/"Vtb_memory_gemm"),f"+SEED={seed}"],[r"PASS: Memory GEMM"])

    def memory_benchmark(self):
        benchmarks=[]
        for m,k,n in ((3,5,7),(8,8,8),(9,2,11)):
            modes={}
            for overlap in (0,1):
                label=f"bench_{m}x{k}x{n}_overlap{overlap}"
                executable=self.directory/label
                self.run(f"{label}_build",[self.tool("iverilog"),"-g2012","-s","tb_memory_gemm","-o",str(executable),
                         f"-Ptb_memory_gemm.M={m}",f"-Ptb_memory_gemm.K={k}",f"-Ptb_memory_gemm.N={n}",
                         f"-Ptb_memory_gemm.OVERLAP={overlap}","-Ptb_memory_gemm.STALLS=0"]
                         +MEMORY_RTL+["tb/tb_memory_gemm.sv"])
                log=self.run(label,[self.tool("vvp"),str(executable),"+SEED=20261110"],[r"PASS: Memory GEMM"])
                metrics={key:int(value) for key,value in re.findall(r"(\w+)=(\d+)",re.search(r"METRIC .*",log)[0])}
                modes["overlapped" if overlap else "serial"]=metrics
            if modes["overlapped"]["cycles"]>=modes["serial"]["cycles"]:
                raise RuntimeError("Overlapped host schedule did not reduce batch cycles")
            pipelined=modes["overlapped"]
            modes.update(shape=[m,k,n],seed=20261110,cycle_reduction_ratio=1-pipelined["cycles"]/modes["serial"]["cycles"],
                         schedule_speedup=modes["serial"]["cycles"]/pipelined["cycles"],
                         useful_MACs_per_clock=pipelined["jobs"]*m*k*n/pipelined["cycles"],
                         mean_compute_completion_interval=pipelined["compute_interval_sum"]/(pipelined["jobs"]-1))
            benchmarks.append(modes)
        self.report["memory_benchmarks"]=benchmarks
        self.save()
        (self.directory/"memory_benchmarks.json").write_text(json.dumps(benchmarks,indent=2)+"\n")

    def synthesis(self):
        for variant in ("generic", "sky130_map", "sky130_timing_clean", "tiled_gemm", "requantize"):
            original = (ROOT / f"synth/{variant}.ys").read_text()
            script = re.sub(r"(?<![/\w])build/([\w.]+)", lambda match: f'"{self.directory / match[1]}"', original)
            path = self.directory / f"{variant}.ys"
            path.write_text(script)
            log = self.run(f"synth_{variant}", [self.tool("yosys"), "-Q", "-s", str(path)],
                     [r"Found and reported 0 problems", r"End of script"])
            name = {"generic": "systolic_netlist", "sky130_map": "systolic_sky130",
                    "sky130_timing_clean": "systolic_sky130_clean", "tiled_gemm": "tiled_gemm_netlist",
                    "requantize": "requantize_netlist"}[variant]
            netlist = json.loads((self.directory / f"{name}.json").read_text())
            area = re.search(r"Chip area for module.*: ([\d.]+)", log)
            self.report.setdefault("synthesis", {})[variant] = {
                "cells": len(netlist["modules"][variant if variant in ("tiled_gemm", "requantize") else "systolic_array"]["cells"]),
                "cell_area_um2": float(area[1]) if area else None,
            }
            self.save()

    def gate(self):
        models = self.directory / "sky130_models.v"
        script = self.directory / "gate_models.ys"
        script.write_text("read_liberty -ignore_miss_func lib/sky130_fd_sc_hd__tt_025C_1v80.lib\n"
                          f'write_verilog -noattr "{models}"\n')
        self.run("gate_models", [self.tool("yosys"), "-Q", "-s", str(script)], [r"End of script"])
        original = (self.directory / "systolic_sky130_clean.v").read_text()
        renamed, count = re.subn(r"\bmodule systolic_array\(", "module systolic_array_gate(", original)
        if count != 1:
            raise RuntimeError("Cannot identify mapped top module for gate simulation")
        netlist = self.directory / "gate_netlist.v"
        netlist.write_text(renamed)
        executable = self.directory / "gate_sim"
        self.run("gate_build", [self.tool("iverilog"), "-g2012", "-s", "tb_coverage", "-o", str(executable),
                 f"-Ptb_coverage.RANDOM_CASES={self.args.random_cases}",
                 str(models), str(netlist), "tb/gate_adapter.sv"] + ADVANCED + ["tb/tb_coverage.sv"])
        for seed in self.args.seeds:
            self.run(f"gate_seed{seed}", [self.tool("vvp"), str(executable), f"+SEED={seed}"],
                     [r"PASS: Advanced verification completed", r"Bins covered : 14 / 14", r"Sign-pair bins : 9 / 9"])

    def architecture(self):
        results = []
        template = (ROOT / "synth/sky130_timing_clean.ys").read_text()
        for size in self.args.sizes:
            directory = self.directory / f"n{size}"
            directory.mkdir()
            wrapper = directory / "architecture_top.sv"
            data_bits = size*size*8
            acc_bits = size*size*(16+(size-1).bit_length())
            wrapper.write_text(f"module architecture_top(input clk, rst_n, start, "
                               f"input [{data_bits-1}:0] a_matrix, b_matrix, output busy, done, "
                               f"output [{acc_bits-1}:0] c_matrix);\n"
                               f"systolic_array #(.N({size})) tile (.*);\nendmodule\n")
            script = template.replace("hierarchy -check", f'read_verilog -sv "{wrapper}"\nhierarchy -check')
            script = script.replace("-top systolic_array", "-top architecture_top")
            script = re.sub(r"(?<![/\w])build/([\w.]+)", lambda match: f'"{directory / match[1]}"', script)
            path = directory / "synth.ys"
            path.write_text(script)
            log = self.run(f"architecture_n{size}", [self.tool("yosys"), "-Q", "-s", str(path)], [r"End of script"])
            netlist = json.loads((directory / "systolic_sky130_clean.json").read_text())
            area = re.search(r"Chip area for module.*: ([\d.]+)", log)
            results.append({"N": size, "MAC_units": size*size, "compute_cycles": 3*size-2,
                            "accumulator_bits": 16+(size-1).bit_length(),
                            "cells": len(netlist["modules"]["architecture_top"]["cells"]),
                            "cell_area_um2": float(area[1])})
        self.report["architecture"] = results
        self.save()
        (self.directory / "architecture.json").write_text(json.dumps(results, indent=2) + "\n")

    def timing(self):
        env = dict(os.environ, NETLIST_FILE=str(self.directory / "systolic_sky130_clean.v"),
                   REPORT_DIR=str(self.directory))
        log = self.run("sta", [self.tool("sta"), "-exit", "timing/run_sta_clean.tcl"],
                 [r"CLEAN NETLIST STA COMPLETE", r"wns max 0\.000", r"wns min 0\.000"], env=env)
        self.report["timing"] = {
            "setup_slack_ns": float(re.search(r"worst slack max ([-\d.]+)", log)[1]),
            "hold_slack_ns": float(re.search(r"worst slack min ([-\d.]+)", log)[1]),
            "period_min_ns": float(re.search(r"period_min = ([\d.]+)", log)[1]),
            "estimated_fmax_MHz": float(re.search(r"fmax = ([\d.]+)", log)[1]),
            "scope": "pre-layout SKY130HD TT 25C 1.8V; ideal clocks; no extracted wires",
        }
        self.save()

    def require_synthesis_tool(self):
        self.tool("yosys")
        version=self.report["tools"]["yosys"]["version"]
        match=re.search(r"Yosys (\d+)\.(\d+)",version)
        if not match or tuple(map(int,match.groups()))<(0,68):
            raise RuntimeError("Yosys 0.68+ required for this RTL; use native 0.70 or pinned ci/requirements-yosys.txt with YOSYS=yowasp-yosys")

    def execute(self):
        suite = self.args.suite
        if suite in ("verify","sram","sram-synth","synth","ppa","gate","architecture","design-space","memory-synth"):
            self.require_synthesis_tool()
        if suite in ("python", "verify"):
            self.python()
        for kind in ("sim", "advanced", "coverage"):
            if suite in (kind, "verify"):
                for size in (self.args.sizes if kind == "advanced" else [4]):
                    self.simulation(kind, size)
        if suite in ("uvm", "verify"):
            self.uvm()
        if suite in ("sva", "verify"):
            self.sva()
        if suite in ("gemm", "verify"):
            self.gemm()
        if suite in ("sram", "sram-synth", "verify"):
            from sram import run_sram
            run_sram(self,synthesis_only=(suite=="sram-synth"))
        if suite in ("axi", "verify"):
            self.axi()
        if suite in ("memory", "verify"):
            self.memory()
        if suite in ("memory-sva", "verify"):
            self.memory_sva()
        if suite in ("memory-bench","verify"):
            self.memory_benchmark()
        if suite=="memory-synth":
            self.memory_synthesis()
        if suite in ("inference", "verify"):
            from inference_demo import run_demo
            run_demo(self)
        if suite in ("synth", "ppa", "gate"):
            self.synthesis()
        if suite in ("ppa", "gate"):
            self.gate()
        if suite == "ppa":
            self.timing()
        if suite == "architecture":
            self.architecture()
        if suite == "design-space":
            from design_space import run_design_space
            run_design_space(self)
        if suite == "cpu-bench":
            from cpu_benchmark import run_cpu_benchmark
            run_cpu_benchmark(self)
        if suite == "accuracy":
            from accuracy_study import run_accuracy_study
            run_accuracy_study(self)
        if suite=="physical":
            from physical_flow import run_physical
            run_physical(self)
        if suite=="model":
            from digit_model import run_model
            run_model(self)
        if suite=="rcx":
            if not self.args.physical_run:
                raise RuntimeError("Set --physical-run to a successful physical run directory")
            from rcx import run_rcx
            run_rcx(self)
        if suite=="pvt":
            if not self.args.physical_run:
                raise RuntimeError("Set --physical-run to a successful physical run directory")
            from pvt import run_pvt
            run_pvt(self)
        if suite=="postroute":
            if not self.args.physical_run:
                raise RuntimeError("Set --physical-run to a successful physical run directory")
            from postroute import run_postroute
            run_postroute(self)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=["verify", "python", "sim", "advanced", "coverage", "uvm", "sva", "gemm", "memory", "memory-sva", "memory-bench", "memory-synth", "inference", "synth", "ppa", "gate", "architecture", "design-space", "cpu-bench", "accuracy", "physical", "postroute", "model", "axi", "pvt", "sram", "sram-synth", "rcx"], default="verify")
    parser.add_argument("--physical-run")
    parser.add_argument("--rcx-run")
    parser.add_argument("--physical-design", choices=["memory_gemm","axi_gemm"], default="memory_gemm")
    parser.add_argument("--require-timing-closure", action="store_true")
    parser.add_argument("--pvt-periods", type=float, nargs="+", default=[10.0,20.0])
    parser.add_argument("--seeds", type=int, nargs="+", default=[20261110])
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--sizes", type=int, nargs="+", default=[2, 3, 4, 8])
    parser.add_argument("--random-cases", type=int, default=200)
    args = parser.parse_args()
    if any(not math.isfinite(period) or period<=0 for period in args.pvt_periods):
        parser.error("PVT clock periods must be positive and finite")
    if args.jobs < 1 or args.random_cases < 0 or any(size < 2 for size in args.sizes) or any(not 0 < seed < 2**32 for seed in args.seeds):
        parser.error("jobs must be positive, random cases nonnegative, seeds in [1, 2**32-1]")
    run = Regression(args)
    try:
        run.execute()
        run.report["status"] = "PASS"
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        run.report["status"] = "FAIL"
        run.report["error"] = str(error)
        print(f"FAIL: {error}", file=sys.stderr)
    finally:
        run.save()
    print(f"{run.report['status']}: {run.directory / 'summary.json'}", flush=True)
    return 0 if run.report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
