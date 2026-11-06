#!/usr/bin/env python3
"""Rank every refcam's systems by cost from a refcams run made with SPLIT=1 (and OSPLIT=1).

    SPLIT=1 OSPLIT=1 GODOT=... python3 tools/refcams/refcams.py run build/refcams/<label> --timeout 9000
    python3 tools/perf_audit_4/split_table.py build/refcams/<label>/godot.log [--top 10] [--stems]

Prints, per camera (the SPLITCAM lines head each), the frame (GEO_<name>), then the top N
categories (SPLIT lines) or, with --stems, the top N OSPLIT stems and BSPLIT kinds mixed, by
triangles. --md writes a markdown table of the top N categories per camera (for HANDOFF).
"""
import re
import sys

GEO = re.compile(r"^GEO_(\S+) tris=(\d+) draws=(\d+) objects=(\d+) \| camera tris=(\d+) draws=(\d+) \| shadow tris=(\d+) draws=(\d+)")
SPLIT = re.compile(r"^SPLIT (\S+)\s+nodes\s+(\d+)\s+tris\s+(-?\d+) \(\s*(-?[\d.]+)%\)\s+draws\s+(-?\d+)\s+objects\s+(-?\d+)\s+\| shadow tris\s+(-?\d+) draws\s+(-?\d+)")
OSPLIT = re.compile(r"^OSPLIT (\S+)\s+nodes\s+(\d+)\s+tris\s+(-?\d+)\s+draws\s+(-?\d+)\s+objects\s+(-?\d+)\s+\| shadow tris\s+(-?\d+) draws\s+(-?\d+)")
BSPLIT = re.compile(r"^BSPLIT (\S+)\s+nodes\s+(\d+)\s+tris\s+(-?\d+)\s+draws\s+(-?\d+)")


def parse(path):
	cams = {}
	order = []
	cur = None
	for line in open(path, errors="replace"):
		line = line.rstrip()
		m = GEO.match(line)
		if m:
			name = m.group(1)
			cams[name] = {"geo": [int(x) for x in m.groups()[1:]], "split": [], "stems": []}
			order.append(name)
			continue
		if line.startswith("SPLITCAM "):
			cur = line.split()[1]
			continue
		if cur is None or cur not in cams:
			continue
		m = SPLIT.match(line)
		if m:
			cams[cur]["split"].append((m.group(1), int(m.group(3)), int(m.group(5)), int(m.group(7)), int(m.group(8))))
			continue
		m = OSPLIT.match(line)
		if m:
			cams[cur]["stems"].append((m.group(1), int(m.group(3)), int(m.group(4)), int(m.group(6)), int(m.group(7))))
			continue
		m = BSPLIT.match(line)
		if m:
			cams[cur]["stems"].append(("Building/" + m.group(1), int(m.group(3)), int(m.group(4)), 0, 0))
	return cams, order


def main():
	args = sys.argv[1:]
	if not args:
		sys.exit(__doc__)
	top = 10
	if "--top" in args:
		top = int(args[args.index("--top") + 1])
	cams, order = parse(args[0])
	md = "--md" in args
	for name in order:
		c = cams[name]
		g = c["geo"]
		rows = c["stems"] if "--stems" in args else c["split"]
		rows = sorted(rows, key=lambda r: -r[1])[:top]
		if md:
			cells = ", ".join("%s %.2f M" % (r[0], r[1] / 1e6) for r in rows)
			print("| %s | %.2f M (%.2f / %.2f) / %d | %s |" % (name, g[0] / 1e6, g[3] / 1e6, g[5] / 1e6, g[1], cells))
			continue
		print("%s  tris %.2f M (camera %.2f / shadow %.2f)  draws %d (camera %d / shadow %d)" % (
			name, g[0] / 1e6, g[3] / 1e6, g[5] / 1e6, g[1], g[4], g[6]))
		for r in rows:
			print("    %-40s tris %8.3f M  draws %5d  | shadow tris %8.3f M  draws %5d" % (r[0], r[1] / 1e6, r[2], r[3] / 1e6, r[4]))


if __name__ == "__main__":
	main()
