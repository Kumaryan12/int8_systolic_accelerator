"""Pre-layout timing and useful-throughput accounting for the mapped tile sweep."""

import json
import math
import re


def tile_performance(size, frequency_mhz):
    if size < 2 or not math.isfinite(frequency_mhz) or frequency_mhz <= 0:
        raise ValueError("Invalid array size or clock frequency")
    # The next job is captured one edge after the previous done edge.
    interval = 3 * size - 1
    return {"acceptance_interval_cycles": interval,
            "useful_macs_per_job": size ** 3,
            "peak_gmac_s": size ** 2 * frequency_mhz / 1000,
            "useful_gmac_s": size ** 3 * frequency_mhz / (1000 * interval)}


def run_design_space(run):
    run.architecture()
    rows = run.report["architecture"]
    for row in rows:
        size = row["N"]
        directory = run.directory / f"n{size}"
        script = directory / "timing.tcl"
        script.write_text("""read_liberty lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_verilog {%s}
link_design architecture_top
read_sdc constraints/systolic.sdc
report_checks -path_delay max -digits 6
report_worst_slack -max -digits 6
report_worst_slack -min -digits 6
report_clock_min_period -include_port_paths -digits 6
puts {DESIGN SPACE STA COMPLETE}
exit
""" % (directory / "systolic_sky130_clean.v"))
        log = run.run(f"design_timing_n{size}", [run.tool("sta"), "-exit", str(script)],
                      ["DESIGN SPACE STA COMPLETE"])
        slack = re.search(r"worst slack max\s+([-\d.]+)", log)
        hold = re.search(r"worst slack min\s+([-\d.]+)", log)
        period = re.search(r"period_min\s*=\s*([\d.]+)", log)
        if not (slack and hold and period):
            raise RuntimeError("Missing cross-size timing results")
        # Include the specified I/O budgets and uncertainty, not just the
        # register-only minimum-period statistic. Hold does not improve with period.
        required = max(float(period[1]), 10.0 - float(slack[1]))
        if not math.isfinite(required) or required <= 0:
            raise RuntimeError("Invalid required clock period")
        row.update(setup_slack_at_100mhz_ns=float(slack[1]), hold_slack_ns=float(hold[1]),
                   required_period_ns=required, estimated_setup_limit_mhz=1000 / required,
                   at_50mhz=tile_performance(size, 50),
                   at_setup_limit=tile_performance(size, 1000 / required))
    metrics = {"rows": rows, "scope": "SKY130HD TT 25C 1.8V; pre-layout; ideal clocks; no extracted wires; raw reset untimed",
               "throughput_scope": "Full N x N GEMMs on the packed base tile; includes capture/restart; excludes host I/O; 1 MAC = 1 multiply plus accumulate",
               "source_sha256": run.report["source_sha256"], "tools": run.report["tools"]}
    (run.directory / "design_space.json").write_text(json.dumps(metrics, indent=2) + "\n")
    run.report["design_space"] = metrics
    run.save()
