#!/usr/bin/env python3
"""Find pops in a pop_strip.gd run: regions that change in ONE frame instead of smoothly.

    python3 tools/lod_pops/pops.py build/pops/drive [--top 30] [--crops out_dir]

Per 16 px tile, D(t) is the mean absolute difference of frame t against t-1 (luma, 0-255).
Camera motion, traffic and people change a tile a little every frame; a pop changes it a lot
once. A tile's spike is D(t) - max(D(t-1), D(t+1)) and an event is a frame with spike tiles
over --thresh, grouped into connected blobs. Prints one POP line per blob (frame, box, size,
strength) with the chunk events logged on that frame and the one before, and a SUMMARY line
(events, total pop area per 100 frames: the number to bring down). --crops writes a
before / after crop of each of the top events."""
import os
import sys
import numpy as np
from PIL import Image

TILE = 16


def main() -> None:
    d = sys.argv[1]
    args = sys.argv[2:]
    top = int(args[args.index("--top") + 1]) if "--top" in args else 30
    thresh = float(args[args.index("--thresh") + 1]) if "--thresh" in args else 14.0
    crops = args[args.index("--crops") + 1] if "--crops" in args else ""
    files = sorted(f for f in os.listdir(d) if f.startswith("f") and f.endswith(".jpg"))
    frames = [np.asarray(Image.open(os.path.join(d, f)).convert("L"), dtype=np.float32) for f in files]
    n = len(frames)
    if n < 4:
        print("too few frames")
        return
    h, w = frames[0].shape
    th, tw = h // TILE, w // TILE

    def tiles(a):
        return a[: th * TILE, : tw * TILE].reshape(th, TILE, tw, TILE).mean(axis=(1, 3))
    D = [None] + [tiles(np.abs(frames[i] - frames[i - 1])) for i in range(1, n)]
    ev = {}
    for line in open(os.path.join(d, "events.txt")):
        p = line.split(" ", 1)
        if p[1].startswith("CAM"):
            continue
        ev.setdefault(int(p[0]), []).append(p[1].strip())
    pops = []
    for t in range(2, n - 1):
        spike = D[t] - np.maximum(D[t - 1], D[t + 1])
        mask = spike > thresh
        # Things leaving or entering at the frame's edge spike too: not pops.
        mask[:, :1] = False
        mask[:, -1:] = False
        mask[:1, :] = False
        mask[-1:, :] = False
        if not mask.any():
            continue
        # Connected blobs (4-neighbour flood fill on the tile grid).
        seen = np.zeros_like(mask)
        for y, x in zip(*np.nonzero(mask)):
            if seen[y, x]:
                continue
            stack = [(y, x)]
            seen[y, x] = True
            cells = []
            while stack:
                cy, cx = stack.pop()
                cells.append((cy, cx))
                for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                    if 0 <= ny < th and 0 <= nx < tw and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            ys = [c[0] for c in cells]
            xs = [c[1] for c in cells]
            strength = float(sum(spike[c] for c in cells))
            pops.append((strength, t, min(xs) * TILE, min(ys) * TILE, (max(xs) + 1) * TILE, (max(ys) + 1) * TILE, len(cells)))
    pops.sort(reverse=True)
    area = sum(p[6] for p in pops)
    print("SUMMARY frames=%d pops=%d tiles=%d per100=%.1f strength=%.0f" % (n, len(pops), area, area * 100.0 / n, sum(p[0] for p in pops)))
    if crops:
        os.makedirs(crops, exist_ok=True)
    for i, (s, t, x0, y0, x1, y1, cells) in enumerate(pops[:top]):
        e = ev.get(t, []) + ev.get(t - 1, [])
        print("POP f%04d box=%d,%d-%d,%d tiles=%d strength=%.0f events=%s" % (t, x0, y0, x1, y1, cells, s, "; ".join(e[:6])))
        if crops:
            pad = 24
            box = (max(0, x0 - pad), max(0, y0 - pad), min(w, x1 + pad), min(h, y1 + pad))
            a = Image.open(os.path.join(d, files[t - 1])).crop(box)
            b = Image.open(os.path.join(d, files[t])).crop(box)
            sc = max(1, int(240 / max(1, a.height)))
            a = a.resize((a.width * sc, a.height * sc))
            b = b.resize((b.width * sc, b.height * sc))
            out = Image.new("RGB", (a.width * 2 + 4, a.height), "white")
            out.paste(a, (0, 0))
            out.paste(b, (a.width + 4, 0))
            out.save(os.path.join(crops, "pop%02d_f%04d.jpg" % (i, t)))


if __name__ == "__main__":
    main()
