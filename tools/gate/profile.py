#!/usr/bin/env python3
"""Splits a smoke-test log run with SMOKE_PROFILE=1 into where the time went.

Usage: python3 tools/gate/profile.py <log> [top_n]
Each check is followed by a TIME line (wall seconds since start, resident MB, frame). Prints the
longest gaps between consecutive checks (the gap is charged to the check that ENDS it), the
total, and the peak resident memory seen.
"""
import re
import sys

path = sys.argv[1]
top = int(sys.argv[2]) if len(sys.argv) > 2 else 40
rows = []
label = None
for line in open(path, errors="replace"):
    line = line.rstrip("\n")
    if line.startswith("PASS ") or line.startswith("FAIL "):
        label = line
    m = re.match(r"TIME ([\d.]+) s, rss (\d+) MB, frame (\d+)", line)
    if m and label is not None:
        rows.append((float(m.group(1)), int(m.group(2)), int(m.group(3)), label))
        label = None
if not rows:
    sys.exit("no TIME lines (run with SMOKE_PROFILE=1)")
gaps = []
prev_t, prev_f = 0.0, 0
for t, rss, f, lab in rows:
    gaps.append((t - prev_t, f - prev_f, t, rss, lab))
    prev_t, prev_f = t, f
print("total %.1f s, %d checks, peak rss %d MB, %d frames" % (rows[-1][0], len(rows), max(r[1] for r in rows), rows[-1][2]))
for g, df, t, rss, lab in sorted(gaps, reverse=True)[:top]:
    print("%7.1f s %6d fr  at %7.1f  %5d MB  %s" % (g, df, t, rss, lab[:110]))
