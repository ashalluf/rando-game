#!/usr/bin/env python3
"""Which parts of a SMOKE_PROFILE=1 shard log raise its resident memory.

    python3 tools/perf_audit_4/gate_rss.py build/gate/shard_1.log [--top 12]

A PART line follows the part it names, so every TIME line belongs to the next PART line. Prints
the parts by how much they raised RSS (the last TIME line of the part against the one before it),
with Godot's own allocator ('godot') beside it.
"""
import re
import sys


def parts(path):
	cur = []
	out = []
	for line in open(path, errors="replace"):
		m = re.match(r"TIME ([\d.]+) s, rss (\d+) MB, frame \d+, godot (\d+) MB", line)
		if m:
			cur.append((int(m.group(2)), int(m.group(3))))
			continue
		m = re.match(r"PART (\S+)", line)
		if m:
			out.append((m.group(1), cur))
			cur = []
	return out


def main():
	if len(sys.argv) < 2:
		sys.exit(__doc__)
	top = int(sys.argv[sys.argv.index("--top") + 1]) if "--top" in sys.argv else 12
	rows = []
	prev = (0, 0)
	peak = 0
	for name, times in parts(sys.argv[1]):
		if not times:
			continue
		end = times[-1]
		hi = max(t[0] for t in times)
		peak = max(peak, hi)
		rows.append((end[0] - prev[0], name, prev, end, hi))
		prev = end
	for d, name, a, b, hi in sorted(rows, reverse=True)[:top]:
		print("%+6d MB rss  %-34s rss %5d -> %5d (peak %5d)  godot %5d -> %5d" % (d, name, a[0], b[0], hi, a[1], b[1]))
	print("peak %d MB" % peak)


if __name__ == "__main__":
	main()
