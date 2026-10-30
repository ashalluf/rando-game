#!/usr/bin/env python3
"""Pixel diff of two stills of the same frame, for before/after checks.

    python3 tools/glshot/img_diff.py before.png after.png [heat.png]

Prints the mean and percentiles of the per-pixel difference (the largest of R, G, B, 0-255) and
how many pixels differ at all and by more than 2, 8 and 32. With a third path it writes a
heatmap: the frame dimmed to a quarter, every differing pixel red, brighter the more it differs.
Shoot both sides with DIFF=1 on tools/glshot/still_shot.gd, or the frames will differ anyway
(clouds, sway, grain, traffic and the clock all move between two runs).
"""
import sys

import numpy as np
from PIL import Image


def main() -> None:
    a = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(np.int16)
    b = np.asarray(Image.open(sys.argv[2]).convert("RGB")).astype(np.int16)
    d = np.abs(a - b).max(axis=2)
    n = d.size
    print("mean %.4f  p99 %.1f  p99.9 %.1f  max %d  pixels>0: %d (%.3f%%)  >2: %d  >8: %d  >32: %d" % (
        d.mean(), np.percentile(d, 99), np.percentile(d, 99.9), d.max(), (d > 0).sum(),
        100.0 * (d > 0).sum() / n, (d > 2).sum(), (d > 8).sum(), (d > 32).sum()))
    if len(sys.argv) > 3:
        heat = np.repeat((a.mean(axis=2) * 0.25).astype(np.uint8)[..., None], 3, axis=2)
        m = d > 0
        heat[m] = 0
        heat[m, 0] = np.clip(d[m].astype(np.float32) * 16.0 + 64.0, 0, 255).astype(np.uint8)
        Image.fromarray(heat).save(sys.argv[3])


if __name__ == "__main__":
    main()
