#!/usr/bin/env python3
"""Luminance numbers for the GI review's stills: the whole frame's p5 / p50 / p95 and, with
--box x0,y0,x1,y1 (fractions of the frame), the mean of a region (the ground under a car, the
underpass's shade), so a before / after pair is a pair of numbers, not a squint.

    python3 tools/gi_review/measure.py before.png after.png [--box 0.3,0.7,0.6,0.85]
"""
import sys

import numpy as np
from PIL import Image

box = None
files = []
args = sys.argv[1:]
i = 0
while i < len(args):
    if args[i] == "--box":
        box = [float(v) for v in args[i + 1].split(",")]
        i += 2
        continue
    files.append(args[i])
    i += 1
for f in files:
    g = np.asarray(Image.open(f).convert("L")).astype(float)
    line = "%s  p5/p50/p95 %s" % (f, [round(float(np.percentile(g, p))) for p in (5, 50, 95)])
    if box:
        h, w = g.shape
        r = g[int(box[1] * h):int(box[3] * h), int(box[0] * w):int(box[2] * w)]
        line += "  box mean %.1f p10 %.0f" % (r.mean(), np.percentile(r, 10))
    print(line)
