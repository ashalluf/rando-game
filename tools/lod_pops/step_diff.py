#!/usr/bin/env python3
"""Mean absolute difference between consecutive frames of a car_pop_shot.gd run, per step, so a
pop shows as one big step among small ones.  python3 tools/lod_pops/step_diff.py build/pops/car/l0"""
import glob
import sys
import numpy as np
from PIL import Image

for pre in sys.argv[1:]:
    fs = sorted(glob.glob(pre + "_*.png"))
    a = [np.asarray(Image.open(f).convert("L"), dtype=np.float32) for f in fs]
    steps = []
    for i in range(1, len(a)):
        d = np.abs(a[i] - a[i - 1])
        steps.append("%s:%.2f/%.0f" % (fs[i].split("_")[-1][:-5], d.mean(), np.percentile(d, 99.5)))
    print(pre, " ".join(steps))
