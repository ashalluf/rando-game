"""Plot tools/drive_steer/probe.tscn TRACE=1 runs, before against after.
  python3 tools/drive_steer/plot.py before.log after.log out_dir
Writes one chart per traced test (yaw rate and heading over time), 1280 px wide."""
import sys, os, collections
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def read(path):
    runs = collections.defaultdict(list)
    for line in open(path):
        if line.startswith("TR "):
            _, tag, t, st, yaw, hd = line.split()
            runs[tag].append((float(t), float(st), float(yaw), float(hd)))
    return runs


def main():
    a, b, out = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(out, exist_ok=True)
    ra, rb = read(a), read(b)
    for tag in sorted(set(ra) | set(rb)):
        fig, ax = plt.subplots(2, 1, figsize=(12.8, 7.2), dpi=100, sharex=True)
        for runs, name, col in ((ra, "main", "#c0392b"), (rb, "DriveHandling", "#2471a3")):
            pts = runs.get(tag, [])
            if not pts:
                continue
            t0 = pts[0][0]
            h0 = pts[0][3]
            ts = [p[0] - t0 for p in pts]
            ax[0].plot(ts, [p[2] for p in pts], color=col, label=name)
            ax[1].plot(ts, [((p[3] - h0 + 180) % 360) - 180 for p in pts], color=col, label=name)
        ax[0].set_ylabel("yaw rate (deg/s)")
        ax[1].set_ylabel("heading change (deg)")
        ax[1].set_xlabel("seconds")
        ax[0].set_title("Sedan, %s (headless probe, simulated keys)" % tag)
        ax[0].legend()
        for x in ax:
            x.grid(alpha=0.3)
        fig.tight_layout()
        fig.savefig(os.path.join(out, "%s.png" % tag))
        plt.close(fig)


main()
