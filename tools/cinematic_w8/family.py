#!/usr/bin/env python3
"""Judge many reference cameras as one picture of the game (wave 8's cinematic review).

    python3 tools/cinematic_w8/family.py <run_dir> [<run_dir> ...] [--sheet out.jpg] [--cols 6]

Reads each run's report.json (tools/refcams/refcams.py), puts every shot in a BAND by its hour
and weather (day, golden, dusk, night, rain-night, marine...), prints each band's median of the
grade numbers (luminance p5 / p50 / p95, black level p1, saturation, colour temperature in
mireds) and every shot that sits out of its band (past FLAG of the band's median), and writes a
contact sheet ordered by hour with the band under each shot. Several runs are pooled (the ten
originals with wave 8's), so a band is judged against every camera that shares it.
"""
import argparse, json, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

# Out of family: how far from the band's median a shot may sit.
FLAG = {"lum_p50": 22.0, "lum_p5": 14.0, "lum_p95": 28.0, "lum_p1": 10.0, "sat_mean": 0.09, "mired": 45.0}


def band(hour, weather):
	h = float(hour)
	wet = weather in ("rain", "storm")
	if weather == "marine":
		return "marine"
	if h >= 19.6 or h < 5.5:
		return "night_wet" if wet else "night"
	if 18.4 <= h < 19.6:
		return "dusk"
	if 16.9 <= h < 18.4 or 5.5 <= h < 7.5:
		return "golden"
	return "day_wet" if wet else "day"


def mired(cct):
	return None if not cct else 1e6 / float(cct)


def load(run_dir):
	with open(os.path.join(run_dir, "report.json")) as f:
		rep = json.load(f)
	out = []
	for s in rep["shots"]:
		s = dict(s)
		s["run"] = run_dir
		s["band"] = band(s["hour"], s["weather"])
		s["mired"] = mired(s.get("cct"))
		out.append(s)
	return out


def analyse(shots):
	bands = {}
	for s in shots:
		bands.setdefault(s["band"], []).append(s)
	lines, flags = [], []
	for b in ("day", "day_wet", "marine", "golden", "dusk", "night", "night_wet"):
		if b not in bands:
			continue
		group = sorted(bands[b], key=lambda s: s["hour"])
		med = {k: float(np.median([s[k] for s in group if s.get(k) is not None])) for k in FLAG}
		lines.append("%-10s n=%2d  median p1 %5.1f  p5 %5.1f  p50 %5.1f  p95 %5.1f  sat %.3f  mired %5.0f" % (
			b, len(group), med["lum_p1"], med["lum_p5"], med["lum_p50"], med["lum_p95"], med["sat_mean"], med["mired"]))
		for s in group:
			out = []
			for k, tol in FLAG.items():
				if s.get(k) is None or len(group) < 3:
					continue
				d = s[k] - med[k]
				if abs(d) > tol:
					out.append("%s %+.*f" % (k.replace("lum_", "").replace("_mean", ""), 3 if k == "sat_mean" else 0, d))
			tag = ("  << " + ", ".join(out)) if out else ""
			lines.append("   %-20s %5.2f %-9s p1 %3.0f p5 %3.0f p50 %3.0f p95 %3.0f sat %.3f %5.0fK%s" % (
				s["name"], s["hour"], s["weather"], s["lum_p1"], s["lum_p5"], s["lum_p50"], s["lum_p95"],
				s["sat_mean"], s.get("cct") or 0, tag))
			if out:
				flags.append((s["name"], b, out))
	return "\n".join(lines), flags


def sheet(shots, out, cols=6, width=2400):
	shots = sorted(shots, key=lambda s: (s["hour"] if s["hour"] >= 5.5 else s["hour"] + 24))
	cw = width // cols
	ch = cw * 9 // 16
	rows = (len(shots) + cols - 1) // cols
	img = Image.new("RGB", (width, rows * (ch + 34)), (16, 16, 16))
	d = ImageDraw.Draw(img)
	try:
		font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 15)
	except OSError:
		font = ImageFont.load_default()
	for i, s in enumerate(shots):
		x, y = (i % cols) * cw, (i // cols) * (ch + 34)
		png = os.path.join(s["run"], s["name"] + ".png")
		if os.path.exists(png):
			img.paste(Image.open(png).convert("RGB").resize((cw - 4, ch - 4)), (x + 2, y + 2))
		d.text((x + 4, y + ch), "%s %05.2f %s [%s]" % (s["name"], s["hour"], s["weather"], s["band"]), fill=(230, 230, 230), font=font)
		d.text((x + 4, y + ch + 16), "p5 %.0f p50 %.0f p95 %.0f sat %.2f %sK" % (
			s["lum_p5"], s["lum_p50"], s["lum_p95"], s["sat_mean"], s.get("cct") or "-"), fill=(170, 170, 170), font=font)
	img.save(out, quality=86)
	print("sheet", out)


def main():
	p = argparse.ArgumentParser()
	p.add_argument("runs", nargs="+")
	p.add_argument("--sheet", default="")
	p.add_argument("--cols", type=int, default=6)
	a = p.parse_args()
	shots = []
	for r in a.runs:
		shots += load(r)
	text, flags = analyse(shots)
	print(text)
	print("\n%d shots out of family" % len(flags))
	if a.sheet:
		sheet(shots, a.sheet, a.cols)


if __name__ == "__main__":
	main()
