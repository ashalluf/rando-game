#!/usr/bin/env python3
"""Night street numbers for every PNG in a folder (or the files given): luminance p1/p5/p50/p95/p99,
clipped (>=250) and crushed (<=4) shares, the lower half's p50 (the pavement and road), the share
of 32 px tiles whose mean is under 8 (black holes) and over 200 (blown), mean saturation, and the
mean colour of the lit pixels (luminance over the frame's p90: what the lights tint).
  python3 tools/night_street/measure.py build/night/after [build/night/before]
With two folders it prints the pairs side by side."""
import sys, os
import numpy as np
from PIL import Image


def stats(path):
	a = np.asarray(Image.open(path).convert("RGB")).astype(float)
	g = 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]
	p = [float(np.percentile(g, q)) for q in (1, 5, 50, 95, 99)]
	h, w = g.shape
	low = float(np.percentile(g[h // 2:], 50))
	t = g[: h // 32 * 32, : w // 32 * 32].reshape(h // 32, 32, w // 32, 32).mean(axis=(1, 3))
	mx = a.max(axis=2); mn = a.min(axis=2)
	sat = float(np.mean(np.where(mx > 0, (mx - mn) / np.maximum(mx, 1), 0)))
	lit = a[g > np.percentile(g, 90)].mean(axis=0)
	return dict(p=p, clip=float((g >= 250).mean() * 100), crush=float((g <= 4).mean() * 100), low=low,
		holes=float((t < 8).mean() * 100), blown=float((t > 200).mean() * 100), sat=sat, lit=lit)


def line(name, s):
	p = s["p"]
	return "%-14s p1/5/50/95/99 %3.0f/%3.0f/%3.0f/%3.0f/%3.0f low %3.0f clip %4.1f%% crush %4.1f%% holes %4.1f%% blown %4.1f%% sat %.2f lit %3.0f/%3.0f/%3.0f" % (
		name, p[0], p[1], p[2], p[3], p[4], s["low"], s["clip"], s["crush"], s["holes"], s["blown"], s["sat"], *s["lit"])


PLACES = ["broadway", "wilshire", "suburb", "beach"]
NAMES = ["%s %s_%s" % (w[0], p, h) for w in ("clear", "rain") for h in ("2100", "0030") for p in PLACES]


# The small scenes (shoot_fwd.sh): f.png, f_1.png ... place by place (PLACES, as given to it),
# each clear 21:00, clear 00:30, rain 21:00, rain 00:30.
SMALL = {"bw": "broadway", "wil": "wilshire", "sub": "suburb", "beach": "beach"}


def files(d):
	out = []
	if os.path.exists(os.path.join(d, "f.png")):
		k = 0
		for pl in os.environ.get("PLACES", "bw wil sub beach").split():
			for w, h in (("c", "2100"), ("c", "0030"), ("r", "2100"), ("r", "0030")):
				f = os.path.join(d, "f.png" if k == 0 else "f_%d.png" % k)
				k += 1
				if os.path.exists(f):
					out.append(("%s %s_%s" % (w, SMALL[pl], h), f))
		return sorted(out, key=lambda t: NAMES.index(t[0]) if t[0] in NAMES else 99)
	for i, n in enumerate(NAMES):
		f = os.path.join(d, "n.png" if i == 0 else "n_%d.png" % i)
		if os.path.exists(f):
			out.append((n, f))
	return out


dirs = sys.argv[1:]
if len(dirs) == 1:
	for n, f in files(dirs[0]):
		print(line(n, stats(f)))
else:
	b = dict(files(dirs[1]))
	for n, f in files(dirs[0]):
		if n in b:
			print(line(n, stats(b[n])).replace(n, n + " B", 1))
		print(line(n, stats(f)).replace(n, n + " A", 1))
