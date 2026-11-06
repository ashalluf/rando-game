#!/usr/bin/env python3
"""Tabulate the TRUE lines (TRUE=1 on refcams_shot.gd) and GEO lines of one or two refcams runs.

    python3 tools/perf_audit_6/true_table.py build/refcams/<off>/godot.log [build/refcams/<on>/godot.log] [--md]

Per camera: the renderer's counter (GEO total) and each TRUE group's total (camera + shadow,
every instance counted), and with two logs the change.
"""
import re
import sys

GEO = re.compile(r"^GEO_(\S+) tris=(\d+) draws=(\d+)")
TRUE = re.compile(r"^TRUE_(\S+) (\S+) camera tris=(\d+) shadow tris=(\d+) total=(\d+)")
HOUSE = re.compile(r"^TRUE_(\S+) houses (\S+) camera tris=(\d+) shadow_reach tris=(\d+)")


def parse(path):
	out = {}
	order = []
	for line in open(path, errors="replace"):
		m = GEO.match(line)
		if m:
			out.setdefault(m.group(1), {})["GEO"] = (int(m.group(2)), int(m.group(3)))
			order.append(m.group(1))
			continue
		m = TRUE.match(line)
		if m:
			out.setdefault(m.group(1), {})[m.group(2)] = (int(m.group(3)), int(m.group(4)), int(m.group(5)))
			continue
		m = HOUSE.match(line)
		if m:
			d = out.setdefault(m.group(1), {})
			c, s = d.get("houses", (0, 0, 0))[:2]
			c += int(m.group(3))
			s += int(m.group(4))
			d["houses"] = (c, s, c + s)
	return out, order


def m(x):
	return "%.2f" % (x / 1e6)


def main():
	args = [a for a in sys.argv[1:] if not a.startswith("--")]
	md = "--md" in sys.argv
	a, order = parse(args[0])
	b = parse(args[1])[0] if len(args) > 1 else None
	groups = ["far_planting", "far_boxes", "roof_units", "facade_kit", "props", "plants", "houses"]
	head = ["camera", "GEO"] + groups
	if md:
		print("| " + " | ".join(head) + " |")
		print("|" + "---|" * len(head))
	for cam in order:
		row = [cam]
		ga = a[cam].get("GEO", (0, 0))[0]
		if b and cam in b:
			gb = b[cam].get("GEO", (0, 0))[0]
			row.append("%s -> %s" % (m(ga), m(gb)))
		else:
			row.append(m(ga))
		for g in groups:
			va = a[cam].get(g, (0, 0, 0))[2]
			if b and cam in b:
				vb = b[cam].get(g, (0, 0, 0))[2]
				row.append("%s -> %s" % (m(va), m(vb)))
			else:
				row.append(m(va))
		print(("| " + " | ".join(row) + " |") if md else "  ".join("%-16s" % c for c in row))


main()
