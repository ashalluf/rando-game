#!/usr/bin/env python3
"""The golden-hour review's numbers and hour strips (docs/HANDOFF.md, "The golden hour review").

A run is tools/refcams with this folder's table:

    GODOT=... REFCAMS_JSON=$PWD/tools/golden_hour/cameras.json SHEET_COLS=6 \
        python3 tools/refcams/refcams.py run build/gh/<label>

then

    python3 tools/golden_hour/strip.py numbers build/gh/<label>          # the table
    python3 tools/golden_hour/strip.py strips build/gh/before build/gh/after out/   # the strips

Numbers per shot (PIL "L" 0-255 unless noted): p5 / p50 / p95 of the frame, the SKY band (the top
fifth) and the GROUND band (the bottom two fifths) medians and their ratio (how far the sky
outshines the land: a dusk sky over a black city reads as a silhouette cut-out, a flat one as
haze), mean HSV saturation, the warmth (mean linear R / B), the ORANGE share (pixels whose hue is
15-45 degrees at saturation over 0.55: the "everything is orange" failure), and crushed (<= 6) /
clipped (>= 250) shares.
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw


def _lin(c):
	c = c / 255.0
	return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def measure(png):
	im = Image.open(png).convert("RGB")
	a = np.asarray(im).astype(np.float32)
	g = np.asarray(im.convert("L")).astype(np.float32)
	h = g.shape[0]
	hsv = np.asarray(im.convert("HSV")).astype(np.float32)
	hue = hsv[..., 0] * 360.0 / 255.0
	sat = hsv[..., 1] / 255.0
	lin = _lin(a)
	sky = g[: h // 5]
	ground = g[h * 3 // 5:]
	sky50 = float(np.percentile(sky, 50))
	gr50 = float(np.percentile(ground, 50))
	return {
		"p5": round(float(np.percentile(g, 5))), "p50": round(float(np.percentile(g, 50))),
		"p95": round(float(np.percentile(g, 95))),
		"sky50": round(sky50), "ground50": round(gr50),
		"sky_ground": round(sky50 / max(gr50, 1.0), 2),
		"ground_p5": round(float(np.percentile(ground, 5))),
		"sat": round(float(sat.mean()), 3),
		"warm": round(float(lin[..., 0].mean() / max(lin[..., 2].mean(), 1e-4)), 2),
		"orange": round(float(((hue > 15) & (hue < 45) & (sat > 0.55) & (g > 40)).mean()), 3),
		"crushed": round(float((g <= 6).mean()), 3),
		"clipped": round(float((g >= 250).mean()), 4),
	}


def _cams(run):
	fr = json.load(open(os.path.join(run, "frames.json")))
	return [s["name"] for s in fr["shots"]]


def numbers(run, out=None):
	rows = []
	for name in _cams(run):
		m = measure(os.path.join(run, name + ".png"))
		m["name"] = name
		rows.append(m)
	keys = ["p5", "p50", "p95", "sky50", "ground50", "sky_ground", "ground_p5", "sat", "warm", "orange", "crushed", "clipped"]
	lines = ["%-18s " % "shot" + " ".join("%9s" % k for k in keys)]
	for r in rows:
		lines.append("%-18s " % r["name"] + " ".join("%9s" % r[k] for k in keys))
	text = "\n".join(lines)
	print(text)
	json.dump(rows, open(out or os.path.join(run, "golden.json"), "w"), indent=1)
	open(os.path.join(run, "golden.txt"), "w").write(text + "\n")
	return rows


def strips(before, after, out, width=1920):
	"""One jpg per view: the six hours across, before on top, after under it, numbers under each."""
	os.makedirs(out, exist_ok=True)
	names = _cams(before)
	views = []
	for n in names:
		v = n.rsplit("_", 1)[0]
		if v not in views:
			views.append(v)
	made = []
	for v in views:
		shots = [n for n in names if n.rsplit("_", 1)[0] == v]
		cw = width // len(shots)
		ch = cw * 9 // 16
		cap = 34
		sheet = Image.new("RGB", (cw * len(shots), (ch + cap) * 2 + 24), (16, 16, 18))
		d = ImageDraw.Draw(sheet)
		d.text((6, 4), "%s   top: %s   bottom: %s" % (v, os.path.basename(before.rstrip("/")), os.path.basename(after.rstrip("/"))), fill=(235, 235, 235))
		for row, run in enumerate([before, after]):
			for i, n in enumerate(shots):
				p = os.path.join(run, n + ".png")
				if not os.path.exists(p):
					continue
				im = Image.open(p).convert("RGB").resize((cw - 2, ch - 2), Image.LANCZOS)
				x, y = i * cw, 24 + row * (ch + cap)
				sheet.paste(im, (x + 1, y + 1))
				m = measure(p)
				hh = n.rsplit("_", 1)[1]
				d.text((x + 4, y + ch + 2), "%s:%s  L %d/%d/%d  sat %.2f" % (hh[:2], hh[2:], m["p5"], m["p50"], m["p95"], m["sat"]), fill=(225, 225, 225))
				d.text((x + 4, y + ch + 17), "sky/gnd %.2f  warm %.2f  orange %.2f" % (m["sky_ground"], m["warm"], m["orange"]), fill=(160, 195, 230))
		path = os.path.join(out, "strip_%s.jpg" % v)
		sheet.save(path, quality=86)
		made.append(path)
		print(path)
	return made


if __name__ == "__main__":
	if len(sys.argv) >= 3 and sys.argv[1] == "numbers":
		numbers(sys.argv[2])
	elif len(sys.argv) >= 5 and sys.argv[1] == "strips":
		strips(sys.argv[2], sys.argv[3], sys.argv[4])
	else:
		sys.exit(__doc__)
