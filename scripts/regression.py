"""Rebuild, execute, and retain evidence for accelerator checks (stdlib only)."""

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
RTL = ["rtl/mac_pe.sv", "rtl/systolic_array.sv"]
ADVANCED = ["tb/systolic_protocol_checker.sv", "tb/tb_advanced.sv"]


class Regression:
    def __init__(self, args):
        self.args = args
        (ROOT / "build").mkdir(exist_ok=True)
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        self.directory = Path(tempfile.mkdtemp(prefix=f"run_{stamp}_", dir=ROOT / "build"))
        self.report = {"suite": args.suite, "started_utc": stamp, "seeds": args.seeds,
                       "random_cases": args.random_cases, "sizes": getattr(args, "sizes", [4]),
                       "tools": {}, "steps": [], "status": "RUNNING"}
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
                result = subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT,
                                        timeout=timeout, env=env)
            content = log.read_text(errors="replace")
            step["returncode"] = result.returncode
            if result.returncode != 0:
                raise RuntimeError(f"{name} exited with {result.returncode}")
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

    def synthesis(self):
        for variant in ("generic", "sky130_map", "sky130_timing_clean"):
            original = (ROOT / f"synth/{variant}.ys").read_text()
            script = re.sub(r"build/([\w.]+)", lambda match: f'"{self.directory / match[1]}"', original)
            path = self.directory / f"{variant}.ys"
            path.write_text(script)
            self.run(f"synth_{variant}", [self.tool("yosys"), "-Q", "-s", str(path)],
                     [r"Found and reported 0 problems", r"End of script"])

    def timing(self):
        env = dict(os.environ, NETLIST_FILE=str(self.directory / "systolic_sky130_clean.v"),
                   REPORT_DIR=str(self.directory))
        self.run("sta", [self.tool("sta"), "-exit", "timing/run_sta_clean.tcl"],
                 [r"CLEAN NETLIST STA COMPLETE", r"wns max 0\.000", r"wns min 0\.000"], env=env)

    def execute(self):
        suite = self.args.suite
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
        if suite in ("synth", "ppa"):
            self.synthesis()
        if suite == "ppa":
            self.timing()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=["verify", "python", "sim", "advanced", "coverage", "uvm", "sva", "synth", "ppa"], default="verify")
    parser.add_argument("--seeds", type=int, nargs="+", default=[20261110])
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--sizes", type=int, nargs="+", default=[2, 3, 4, 8])
    parser.add_argument("--random-cases", type=int, default=200)
    args = parser.parse_args()
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
