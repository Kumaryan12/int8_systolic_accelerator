"""Export selected one-bit inference VCD signals as a compact SVG (stdlib)."""

from html import escape
from pathlib import Path
import re


def waveform_svg(vcd_path, output_path):
    signals = [
        ("tb_inference.rst_n", "reset_n"),
        ("tb_inference.start", "host start"),
        ("tb_inference.busy", "host busy"),
        ("tb_inference.done", "host done"),
        ("tb_inference.dut.tile_start", "tile start"),
        ("tb_inference.dut.tile_busy", "tile busy"),
        ("tb_inference.dut.tile_done", "tile done"),
    ]
    wanted = dict(signals)
    codes, traces, scopes = {}, {name: [] for name in wanted}, []
    body = False
    time_ps = 0
    for raw in Path(vcd_path).read_text().splitlines():
        line = raw.strip()
        if line.startswith("$scope"):
            scopes.append(line.split()[2])
        elif line.startswith("$upscope"):
            scopes.pop()
        elif line.startswith("$var"):
            fields = line.split()
            name = ".".join(scopes+[fields[4]])
            if fields[2] == "1" and name in wanted:
                codes.setdefault(fields[3], []).append(name)
        elif line.startswith("$enddefinitions"):
            body = True
        elif body and line.startswith("#"):
            time_ps = int(line[1:])
        elif body and line and line[0] in "01xz" and line[1:] in codes:
            for name in codes[line[1:]]:
                traces[name].append((time_ps, line[0]))
    if any(not trace for trace in traces.values()):
        raise ValueError("Inference waveform is missing required signals")
    # The DUT/testbench use 1ps precision; reject other inputs rather than mislabel time.
    if not re.search(r"\$timescale\s+1ps\s+\$end", Path(vcd_path).read_text()):
        raise ValueError("This exporter expects the inference testbench's 1ps VCD time unit")
    width, left, top, row = 1050, 140, 95, 54
    right = width-30
    height = top+row*len(signals)+45
    xmax = ((time_ps//50000)+1)*50000
    x = lambda tick: left+(right-left)*tick/xmax
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
           f'<rect width="{width}" height="{height}" fill="#f8fafc"/>',
           '<g font-family="Arial,sans-serif" font-size="13" fill="#172033">',
           '<text x="24" y="30" font-size="21" font-weight="bold">Tiled RTL inference — recorded control waveform</text>',
           '<text x="24" y="54">3×5 by 5×7 · four tile jobs · output valid 48 clocks after acceptance</text>']
    for tick in range(0,xmax+1,50000):
        xp=x(tick)
        svg += [f'<path d="M{xp:.2f} 78 V{height-35}" stroke="#dbe2ea" stroke-dasharray="3 4"/>',
                f'<text x="{xp:.2f}" y="{height-12}" text-anchor="middle">{tick//1000} ns</text>']
    for index,(name,label) in enumerate(signals):
        base=top+row*index
        svg.append(f'<text x="24" y="{base+16}">{escape(label)}</text>')
        points=traces[name]
        level=lambda value: base if value=="1" else base+26
        path=f'M{x(0):.2f},{level(points[0][1])}'
        for tick,value in points:
            path+=f' H{x(tick):.2f} V{level(value)}'
        path+=f' H{x(xmax):.2f}'
        svg.append(f'<path d="{path}" fill="none" stroke="#1761c5" stroke-width="2"/>')
    svg += ['</g></svg>']
    Path(output_path).write_text("\n".join(svg)+"\n")
