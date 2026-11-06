#!/usr/bin/env python3
"""Compare two directories of sky stills pixel for pixel (tools/sky_day/shots.sh output).
Prints, per file both have: pixels that differ, max difference, and mean luminance either side.
  python3 tools/sky_day/diff.py <before_dir> <after_dir>
Exit 1 if any file differs (the bit-identical proof for the hours outside 09:00-16:00)."""
import os, sys
import numpy as np
from PIL import Image

a_dir, b_dir = sys.argv[1], sys.argv[2]
bad = 0
for f in sorted(os.listdir(a_dir)):
	if not f.endswith(".png") or not os.path.exists(os.path.join(b_dir, f)):
		continue
	a = np.asarray(Image.open(os.path.join(a_dir, f)).convert("RGB")).astype(int)
	b = np.asarray(Image.open(os.path.join(b_dir, f)).convert("RGB")).astype(int)
	d = np.abs(a - b).max(axis=2)
	n = int((d > 0).sum())
	la = a.mean(); lb = b.mean()
	print("%-16s differ %7d px  max %3d  mean %.1f -> %.1f" % (f, n, int(d.max()), la, lb))
	bad += n > 0
sys.exit(1 if bad else 0)
