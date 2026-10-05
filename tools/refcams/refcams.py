#!/usr/bin/env python3
"""The ten reference cameras: shoot them, measure them, compare two runs.

Usage (from the repo root; README.md in this folder is the long version):

  GODOT=/path/to/godot python3 tools/refcams/refcams.py run build/refcams/<label> [--only a,b] [--strict]
      Loads the city ONCE through opengl3 + Xvfb (tools/refcams/refcams_shot.gd), shoots every
      camera of cameras.json at its own hour and weather, then writes report.json, report.txt and
      sheet.jpg (2 x 5) into the folder. About 15-25 minutes; takes the opengl3 render lock.
  python3 tools/refcams/refcams.py report <dir>
      Re-measures the PNGs in a run folder (frames.json is the frame cost) and rewrites the report
      and the sheet.
  python3 tools/refcams/refcams.py compare <before_dir> <after_dir> [--out <dir>] [tolerances]
      Diffs two runs shot by shot: every number's change, pixel difference, and FLAGS each shot
      whose numbers moved past a tolerance. Writes compare.json, compare.txt, compare.jpg (before
      over after for each shot, flagged ones marked) and diff_<name>.jpg for every flagged shot.
      Exits 1 when anything is flagged, 0 otherwise.
  python3 tools/refcams/refcams.py sheet <dir> [--width 1280]
      Only the contact sheet.

Numbers per shot (report.json): luminance percentiles p1/p5/p50/p95/p99 (0-255, PIL's "L", the
same measure CLAUDE.md's grade targets use), share of clipped (>= 250) and crushed (<= 5) pixels,
mean saturation (HSV S, 0-1), mean colour (sRGB 0-255), colour temperature (McCamy's CCT from the
mean linear colour, kelvin; tells a warm frame from a cool one, not a measurement of the light)
and the frame cost from the GEO counters (triangles, draws, objects, camera / shadow split).
"""
import argparse
import resource
import json
import os
import subprocess
import sys
import time

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
CAMERAS = os.path.join(HERE, "cameras.json")

# Default tolerances for compare: a shot is FLAGGED when any is passed. Luminance in 0-255 levels,
# saturation in HSV S, temperature in mireds (1e6 / K: even steps to the eye, and steady where a
# dark frame's kelvin swing by thousands), cost in percent; pixel = mean |RGB| difference.
TOL = {
	"lum_p50": 6.0, "lum_p5": 8.0, "lum_p95": 8.0, "lum_p1": 10.0, "lum_p99": 10.0,
	"sat_mean": 0.03, "mired": 10.0, "clip_pct": 2.0, "crush_pct": 3.0,
	"tris_pct": 10.0, "draws_pct": 10.0, "pixel_mad": 6.0,
}


def load_cameras():
	with open(CAMERAS) as f:
		return json.load(f)


# ---------------------------------------------------------------- measuring

def _srgb_to_linear(c):
	c = c / 255.0
	return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def cct_of(rgb_lin):
	"""McCamy's correlated colour temperature of a linear sRGB colour (kelvin)."""
	r, g, b = rgb_lin
	x_ = 0.4124 * r + 0.3576 * g + 0.1805 * b
	y_ = 0.2126 * r + 0.7152 * g + 0.0722 * b
	z_ = 0.0193 * r + 0.1192 * g + 0.9505 * b
	s = x_ + y_ + z_
	if s <= 1e-9:
		return None
	x, y = x_ / s, y_ / s
	n = (x - 0.3320) / (0.1858 - y)
	cct = 449.0 * n ** 3 + 3525.0 * n ** 2 + 6823.3 * n + 5520.33
	return float(min(max(cct, 1000.0), 40000.0))


def measure(png):
	img = Image.open(png).convert("RGB")
	rgb = np.asarray(img).astype(np.float64)
	lum = np.asarray(img.convert("L")).astype(np.float64)
	sat = np.asarray(img.convert("HSV"))[:, :, 1].astype(np.float64) / 255.0
	p = [float(np.percentile(lum, q)) for q in (1, 5, 50, 95, 99)]
	mean_rgb = rgb.reshape(-1, 3).mean(axis=0)
	lin = _srgb_to_linear(rgb.reshape(-1, 3)).mean(axis=0)
	return {
		"lum_p1": round(p[0], 1), "lum_p5": round(p[1], 1), "lum_p50": round(p[2], 1),
		"lum_p95": round(p[3], 1), "lum_p99": round(p[4], 1),
		"lum_mean": round(float(lum.mean()), 1),
		"clip_pct": round(float((lum >= 250).mean() * 100.0), 2),
		"crush_pct": round(float((lum <= 5).mean() * 100.0), 2),
		"sat_mean": round(float(sat.mean()), 4),
		"mean_rgb": [round(float(v), 1) for v in mean_rgb],
		"cct": None if cct_of(lin) is None else round(cct_of(lin)),
		"size": list(img.size),
	}


def build_report(run_dir):
	frames_path = os.path.join(run_dir, "frames.json")
	frames = {}
	meta = {}
	if os.path.exists(frames_path):
		with open(frames_path) as f:
			meta = json.load(f)
		frames = {s["name"]: s for s in meta.get("shots", [])}
	cams = load_cameras()["cameras"]
	shots = []
	for cam in cams:
		png = os.path.join(run_dir, cam["name"] + ".png")
		if not os.path.exists(png):
			continue
		row = {"name": cam["name"], "label": cam.get("label", cam["name"]), "hour": cam["hour"],
			"weather": cam["weather"]}
		row.update(measure(png))
		fr = frames.get(cam["name"], {})
		row["geo"] = fr.get("geo", {})
		row["shot_ms"] = fr.get("shot_ms")
		shots.append(row)
	report = {
		"run": os.path.basename(os.path.normpath(run_dir)),
		"commit": _git("rev-parse", "--short", "HEAD"),
		"renderer": meta.get("renderer"), "method": meta.get("method"),
		"resolution": meta.get("resolution"), "load_ms": meta.get("load_ms"),
		"strict": meta.get("strict", False), "live_time": meta.get("live_time", True),
		"peak_rss_mb": _run_meta(run_dir).get("peak_rss_mb"),
		"shots": shots,
	}
	with open(os.path.join(run_dir, "report.json"), "w") as f:
		json.dump(report, f, indent=1)
	text = report_text(report)
	with open(os.path.join(run_dir, "report.txt"), "w") as f:
		f.write(text)
	print(text)
	return report


def _run_meta(run_dir):
	path = os.path.join(run_dir, "run_meta.json")
	return json.load(open(path)) if os.path.exists(path) else {}


def report_text(report):
	lines = ["refcams %s  commit %s  %s %s  %s  load %s ms  peak %s MB%s" % (report["run"], report["commit"],
		report["renderer"], report["method"], report["resolution"], report.get("load_ms"),
		report.get("peak_rss_mb"), "  STRICT" if report.get("strict") else "")]
	lines.append("%-16s %5s %-8s  %5s %5s %5s %5s %5s  %5s %5s  %5s %6s  %9s %6s %9s" % (
		"shot", "hour", "weather", "p1", "p5", "p50", "p95", "p99", "clip%", "crsh%", "sat", "CCT",
		"tris", "draws", "shadow"))
	for s in report["shots"]:
		g = s.get("geo", {})
		lines.append("%-16s %5.2f %-8s  %5.0f %5.0f %5.0f %5.0f %5.0f  %5.1f %5.1f  %5.3f %6s  %9s %6s %9s" % (
			s["name"], s["hour"], s["weather"], s["lum_p1"], s["lum_p5"], s["lum_p50"], s["lum_p95"],
			s["lum_p99"], s["clip_pct"], s["crush_pct"], s["sat_mean"], s["cct"] or "-",
			g.get("tris", "-"), g.get("draws", "-"), g.get("shadow_tris", "-")))
	return "\n".join(lines) + "\n"


def _git(*args):
	try:
		return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()
	except Exception:
		return None


# ---------------------------------------------------------------- the sheet

def _font(size):
	for path in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
			"/usr/share/fonts/TTF/DejaVuSans.ttf"):
		if os.path.exists(path):
			return ImageFont.truetype(path, size)
	return ImageFont.load_default()


def _fit_size(draw, text, width, size):
	"""The largest font size up to `size` at which `text` fits `width` pixels."""
	while size > 7 and draw.textlength(text, font=_font(size)) > width:
		size -= 1
	return size


def contact_sheet(run_dir, width=1920, out=None):
	path = os.path.join(run_dir, "report.json")
	report = json.load(open(path)) if os.path.exists(path) else build_report(run_dir)
	shots = report["shots"]
	cols, rows = 5, 2
	cell_w = width // cols
	cell_h = cell_w * 9 // 16
	cap = max(30, cell_w // 7)
	sheet = Image.new("RGB", (cell_w * cols, (cell_h + cap) * rows + cap), (18, 18, 20))
	draw = ImageDraw.Draw(sheet)
	f_big = _font(max(10, cap // 2 - 2))
	draw.text((6, 4), "refcams %s  %s  %s" % (report["run"], report.get("commit") or "", report.get("renderer") or ""),
		fill=(230, 230, 230), font=f_big)
	for i, s in enumerate(shots[:cols * rows]):
		x, y = (i % cols) * cell_w, cap + (i // cols) * (cell_h + cap)
		im = Image.open(os.path.join(run_dir, s["name"] + ".png")).convert("RGB").resize((cell_w - 4, cell_h - 4), Image.LANCZOS)
		sheet.paste(im, (x + 2, y + 2))
		g = s.get("geo", {})
		head = "%s  %05.2f %s" % (s["name"], s["hour"], s["weather"])
		nums = "L %d/%d/%d  sat %.2f  %sK  %.2fM tris  %s draws" % (s["lum_p5"], s["lum_p50"], s["lum_p95"],
			s["sat_mean"], s["cct"] or "-", (g.get("tris") or 0) / 1e6, g.get("draws", "-"))
		size = _fit_size(draw, nums, cell_w - 8, cap // 2 - 2)
		draw.text((x + 4, y + cell_h + 1), head, fill=(240, 240, 240), font=_font(min(size + 3, cap // 2 - 2)))
		draw.text((x + 4, y + cell_h + cap // 2), nums, fill=(170, 200, 230), font=_font(size))
	out = out or os.path.join(run_dir, "sheet.jpg")
	sheet.save(out, quality=88)
	print("sheet", out)
	return out


# ---------------------------------------------------------------- compare

def _pct(a, b):
	if not a:
		return 0.0 if not b else 100.0
	return (b - a) * 100.0 / a


def compare(dir_a, dir_b, out_dir, tol):
	rep_a = _ensure_report(dir_a)
	rep_b = _ensure_report(dir_b)
	by_b = {s["name"]: s for s in rep_b["shots"]}
	os.makedirs(out_dir, exist_ok=True)
	rows = []
	for a in rep_a["shots"]:
		b = by_b.get(a["name"])
		if b is None:
			rows.append({"name": a["name"], "missing": True, "flags": ["missing in " + dir_b]})
			continue
		d = {}
		flags = []
		for k in ("lum_p1", "lum_p5", "lum_p50", "lum_p95", "lum_p99", "sat_mean", "clip_pct", "crush_pct"):
			d[k] = round(b[k] - a[k], 4)
			if abs(d[k]) > tol[k]:
				flags.append("%s %+g" % (k, d[k]))
		if a.get("cct") and b.get("cct"):
			d["cct"] = b["cct"] - a["cct"]
			d["mired"] = round(1e6 / b["cct"] - 1e6 / a["cct"], 1)
			if abs(d["mired"]) > tol["mired"]:
				flags.append("colour %+.1f mired (%dK -> %dK)" % (d["mired"], a["cct"], b["cct"]))
		ga, gb = a.get("geo", {}), b.get("geo", {})
		for k, t in (("tris", "tris_pct"), ("draws", "draws_pct")):
			if k in ga and k in gb:
				d[k + "_pct"] = round(_pct(ga[k], gb[k]), 1)
				if abs(d[k + "_pct"]) > tol[t]:
					flags.append("%s %+.1f%% (%d -> %d)" % (k, d[k + "_pct"], ga[k], gb[k]))
		ia = np.asarray(Image.open(os.path.join(dir_a, a["name"] + ".png")).convert("RGB")).astype(np.int16)
		ib_img = Image.open(os.path.join(dir_b, a["name"] + ".png")).convert("RGB")
		if ib_img.size != (ia.shape[1], ia.shape[0]):
			ib_img = ib_img.resize((ia.shape[1], ia.shape[0]))
		ib = np.asarray(ib_img).astype(np.int16)
		diff = np.abs(ia - ib)
		d["pixel_mad"] = round(float(diff.mean()), 2)
		d["pixel_changed_pct"] = round(float((diff.max(axis=2) > 24).mean() * 100.0), 2)
		if d["pixel_mad"] > tol["pixel_mad"]:
			flags.append("pixels %.1f mean |d|" % d["pixel_mad"])
		if flags:
			heat = np.clip(diff.max(axis=2) * 4, 0, 255).astype(np.uint8)
			Image.fromarray(heat).convert("RGB").save(os.path.join(out_dir, "diff_%s.jpg" % a["name"]), quality=85)
		rows.append({"name": a["name"], "before": _pick(a), "after": _pick(b), "delta": d, "flags": flags})
	result = {"before": rep_a["run"], "after": rep_b["run"], "before_commit": rep_a.get("commit"),
		"after_commit": rep_b.get("commit"), "tolerance": tol, "shots": rows,
		"flagged": [r["name"] for r in rows if r["flags"]]}
	with open(os.path.join(out_dir, "compare.json"), "w") as f:
		json.dump(result, f, indent=1)
	text = compare_text(result)
	with open(os.path.join(out_dir, "compare.txt"), "w") as f:
		f.write(text)
	print(text)
	compare_sheet(dir_a, dir_b, result, os.path.join(out_dir, "compare.jpg"))
	return result


def _pick(s):
	g = s.get("geo", {})
	return {k: s.get(k) for k in ("lum_p5", "lum_p50", "lum_p95", "sat_mean", "cct")} | {
		"tris": g.get("tris"), "draws": g.get("draws")}


def compare_text(result):
	lines = ["refcams compare %s (%s) -> %s (%s)" % (result["before"], result["before_commit"],
		result["after"], result["after_commit"])]
	lines.append("%-16s %6s %6s %6s %7s %6s %7s %7s %6s  %s" % ("shot", "dp5", "dp50", "dp95", "dsat",
		"dmired", "tris%", "draws%", "pix", "flags"))
	for r in result["shots"]:
		if r.get("missing"):
			lines.append("%-16s MISSING" % r["name"])
			continue
		d = r["delta"]
		lines.append("%-16s %+6.1f %+6.1f %+6.1f %+7.3f %+6s %+7.1f %+7.1f %6.2f  %s" % (
			r["name"], d["lum_p5"], d["lum_p50"], d["lum_p95"], d["sat_mean"], d.get("mired", "-"),
			d.get("tris_pct", 0.0), d.get("draws_pct", 0.0), d["pixel_mad"],
			"FLAG: " + "; ".join(r["flags"]) if r["flags"] else "ok"))
	lines.append("%d of %d shots flagged%s" % (len(result["flagged"]), len(result["shots"]),
		(": " + ", ".join(result["flagged"])) if result["flagged"] else ""))
	return "\n".join(lines) + "\n"


def compare_sheet(dir_a, dir_b, result, out, width=1920):
	rows = [r for r in result["shots"] if not r.get("missing")]
	cols = 5
	cell_w = width // cols
	cell_h = cell_w * 9 // 16
	cap = max(26, cell_w // 9)
	blocks = (len(rows) + cols - 1) // cols
	sheet = Image.new("RGB", (cell_w * cols, cap + blocks * (2 * cell_h + cap)), (18, 18, 20))
	draw = ImageDraw.Draw(sheet)
	f = _font(max(9, cap // 2 - 1))
	draw.text((6, 4), "before %s (top) / after %s (bottom)" % (result["before"], result["after"]), fill=(230, 230, 230), font=f)
	for i, r in enumerate(rows):
		x = (i % cols) * cell_w
		y = cap + (i // cols) * (2 * cell_h + cap)
		for k, d in enumerate((dir_a, dir_b)):
			im = Image.open(os.path.join(d, r["name"] + ".png")).convert("RGB").resize((cell_w - 4, cell_h - 4), Image.LANCZOS)
			sheet.paste(im, (x + 2, y + 2 + k * cell_h))
		col = (255, 110, 90) if r["flags"] else (150, 220, 150)
		if r["flags"]:
			draw.rectangle([x + 1, y + 1, x + cell_w - 2, y + 2 * cell_h - 2], outline=col, width=3)
		draw.text((x + 4, y + 2 * cell_h + 2), "%s %s" % (r["name"], "FLAG" if r["flags"] else "ok"), fill=col, font=f)
	sheet.save(out, quality=88)
	print("compare sheet", out)


def _ensure_report(run_dir):
	path = os.path.join(run_dir, "report.json")
	if os.path.exists(path):
		return json.load(open(path))
	return build_report(run_dir)


# ---------------------------------------------------------------- shooting

def run(out_dir, only=None, strict=False, timeout=3600, live=False):
	godot = os.environ.get("GODOT")
	if not godot:
		sys.exit("set GODOT to the Godot 4.7.2 binary")
	cams = load_cameras()
	first = [c for c in cams["cameras"] if not only or c["name"] in only][0]
	w, h = cams.get("resolution", [960, 540])
	os.makedirs(out_dir, exist_ok=True)
	env = dict(os.environ, OUT_DIR=os.path.abspath(out_dir), LIBGL_ALWAYS_SOFTWARE="1")
	if only:
		env["ONLY"] = ",".join(only)
	if strict:
		env["STRICT"] = "1"
	if live:
		env["LIVE_TIME"] = "1"
	lock = os.environ.get("LOCK", "/tmp/rando_render_gl.lock")
	cmd = ["flock", "-o", lock, "timeout", str(timeout), "xvfb-run", "-a", "-s", "-screen 0 1280x720x24",
		godot, "--rendering-driver", "opengl3", "--display-driver", "x11", "--audio-driver", "Dummy",
		"--path", ROOT, "--script", "tools/refcams/refcams_shot.gd", "--resolution", "%dx%d" % (w, h),
		"--", "--nohud", "--quality=0", "--weather=%s" % first["weather"], "--hour=%s" % first["hour"],
		"--spawn=%s,%s,%s,%s" % (first["eye"][0], first["eye"][2], first["eye"][3], first["eye"][4])]
	start = time.time()
	log = os.path.join(out_dir, "godot.log")
	with open(log, "w") as f:
		code = subprocess.call(cmd, cwd=ROOT, env=env, stdout=f, stderr=subprocess.STDOUT)
	peak_mb = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss // 1024
	print("godot exited %d after %d s, peak RSS %d MB (log %s)" % (code, time.time() - start, peak_mb, log))
	with open(os.path.join(out_dir, "run_meta.json"), "w") as f:
		json.dump({"exit": code, "seconds": round(time.time() - start), "peak_rss_mb": peak_mb}, f)
	if not os.path.exists(os.path.join(out_dir, "frames.json")):
		sys.exit("no frames.json: the run failed, see " + log)
	build_report(out_dir)
	contact_sheet(out_dir)


def main():
	ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	sub = ap.add_subparsers(dest="cmd", required=True)
	p = sub.add_parser("run")
	p.add_argument("out")
	p.add_argument("--only", default="")
	p.add_argument("--strict", action="store_true")
	p.add_argument("--live", action="store_true", help="let shader TIME run (water, clouds move)")
	p.add_argument("--timeout", type=int, default=3600)
	p = sub.add_parser("report")
	p.add_argument("dir")
	p = sub.add_parser("sheet")
	p.add_argument("dir")
	p.add_argument("--width", type=int, default=1920)
	p.add_argument("--out")
	p = sub.add_parser("compare")
	p.add_argument("before")
	p.add_argument("after")
	p.add_argument("--out")
	for k, v in TOL.items():
		p.add_argument("--" + k.replace("_", "-"), type=float, default=v)
	a = ap.parse_args()
	if a.cmd == "run":
		run(a.out, [n for n in a.only.split(",") if n], a.strict, a.timeout, a.live)
	elif a.cmd == "report":
		build_report(a.dir)
		contact_sheet(a.dir)
	elif a.cmd == "sheet":
		contact_sheet(a.dir, a.width, a.out)
	elif a.cmd == "compare":
		tol = {k: getattr(a, k) for k in TOL}
		res = compare(a.before, a.after, a.out or os.path.join(a.after, "compare_vs_" + os.path.basename(os.path.normpath(a.before))), tol)
		sys.exit(1 if res["flagged"] else 0)


if __name__ == "__main__":
	main()
