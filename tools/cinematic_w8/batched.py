#!/usr/bin/env python3
"""Shoot a refcams table in batches (one city load each), then join them into one run folder.

    GODOT=... REFCAMS_JSON=tools/refcams/cameras_w8.json \
        python3 tools/cinematic_w8/batched.py build/refcams/<label> [--size 6] [--only a,b]

A single load that shoots thirty-odd cameras grows past this box's 15 GB (each view streams its
own chunks; the w8 table was OOM-killed after eight). Every batch is a refcams.py `run` into
<label>/_bN; then the PNGs and frames.json shots are gathered into <label> and its report and
sheet are built there as for one run. A batch whose folder already has every shot is skipped, so
a killed run picks up where it stopped.
"""
import argparse, json, os, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tools", "refcams"))
import refcams  # noqa: E402


def main():
	p = argparse.ArgumentParser()
	p.add_argument("out")
	p.add_argument("--size", type=int, default=6)
	p.add_argument("--only", default="")
	p.add_argument("--timeout", type=int, default=5400)
	a = p.parse_args()
	names = [c["name"] for c in refcams.load_cameras()["cameras"]]
	if a.only:
		want = a.only.split(",")
		names = [n for n in names if n in want]
	os.makedirs(a.out, exist_ok=True)
	def have(n):
		return any(os.path.exists(os.path.join(a.out, d, n + ".png")) for d in os.listdir(a.out) if d.startswith("_b"))

	todo = [n for n in names if not have(n)]
	batches = [todo[i:i + a.size] for i in range(0, len(todo), a.size)]
	done = len([d for d in os.listdir(a.out) if d.startswith("_b")])
	for i, batch in enumerate(batches):
		bdir = os.path.join(a.out, "_b%d" % (done + i))
		print("batch %d/%d: %s" % (i + 1, len(batches), ",".join(batch)), flush=True)
		subprocess.call([sys.executable, os.path.join(ROOT, "tools", "refcams", "refcams.py"), "run", bdir,
			"--only", ",".join(batch), "--timeout", str(a.timeout)], cwd=ROOT)
	shots, meta = {}, None
	for d in sorted(x for x in os.listdir(a.out) if x.startswith("_b")):
		bdir = os.path.join(a.out, d)
		fp = os.path.join(bdir, "frames.json")
		if os.path.exists(fp):
			with open(fp) as f:
				m = json.load(f)
			meta = meta or m
			for s in m.get("shots", []):
				if s["name"] in names:
					shots[s["name"]] = s
		for n in names:
			src = os.path.join(bdir, n + ".png")
			if os.path.exists(src):
				shutil.copy(src, os.path.join(a.out, n + ".png"))
	shots = [shots[n] for n in names if n in shots]
	if meta is None:
		sys.exit("no batch produced frames.json")
	meta = dict(meta, shots=shots)
	with open(os.path.join(a.out, "frames.json"), "w") as f:
		json.dump(meta, f, indent=1)
	refcams.build_report(a.out)
	refcams.contact_sheet(a.out)


if __name__ == "__main__":
	main()
