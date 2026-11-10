"""Render the recorded sweep. Optional plotting dependency; verification stays stdlib-only."""
import argparse
import json
from pathlib import Path


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input",type=Path,required=True)
    parser.add_argument("--output",type=Path,required=True)
    args=parser.parse_args()
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    metrics=json.loads(args.input.read_text())
    rows=metrics["rows"]
    sizes=[r["N"] for r in rows]
    plt.rcParams.update({"font.size":10,"svg.fonttype":"none"})
    fig,axes=plt.subplots(1,3,figsize=(12,3.7),layout="constrained")
    axes[0].plot(sizes,[r["cell_area_um2"]/1000 for r in rows],"o-",color="#285f96")
    axes[0].set_ylabel("Mapped cell area (1,000 µm²)")
    axes[0].set_title("Area")
    axes[1].plot(sizes,[r["required_period_ns"] for r in rows],"o-",color="#975500")
    axes[1].set_ylabel("Estimated required period (ns)")
    axes[1].set_title("Pre-layout setup timing")
    axes[2].plot(sizes,[r["at_50mhz"]["useful_gmac_s"] for r in rows],"o-",label="At 50 MHz",color="#287248")
    axes[2].plot(sizes,[r["at_setup_limit"]["useful_gmac_s"] for r in rows],"s--",label="At estimated setup limit",color="#81549b")
    axes[2].set_ylabel("Useful throughput (GMAC/s)")
    axes[2].set_title("Full tile GEMMs, capture/restart included")
    axes[2].legend(fontsize=8)
    for ax in axes:
        ax.set_xticks(sizes)
        ax.set_xlabel("Array size N (N × N MAC units)")
        ax.set_ylim(bottom=0)
        ax.grid(alpha=0.22)
    fig.suptitle("SKY130HD base tile · TT 25°C, 1.8 V · ideal clocks, no extracted wires",fontsize=12)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    fig.savefig(args.output,metadata={"Date":None})
    fig.savefig(args.output.with_suffix(".png"),dpi=180)


if __name__=="__main__": main()
