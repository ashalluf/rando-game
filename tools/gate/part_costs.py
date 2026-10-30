#!/usr/bin/env python3
"""Prints smoke_test.gd's PART_COST table from a whole run's log (SMOKE_PROFILE=1 prints a PART
line per part and check file). Paste the output over the table in tests/smoke_test.gd: only the
shards' deal depends on it, and a stale table deals a 150 s file as a 6 s one.

Usage: python3 tools/gate/part_costs.py <log>
"""
import re
import sys

costs = {}
for line in open(sys.argv[1], errors="replace"):
    m = re.match(r"PART (\w+) ([\d.]+) s", line)
    if m and m.group(1) != "city_files":
        costs[m.group(1)] = float(m.group(2))
src = open("tests/smoke_test.gd").read()
inline = re.search(r"const INLINE_FILES := \[(.*?)\]", src, re.S).group(1)
for name in re.findall(r'"(\w+)"', inline):
    costs.pop(name, None)
costs.setdefault("room", 30.0)
lines, cur = [], "\t"
for k, v in sorted(costs.items(), key=lambda kv: (-kv[1], kv[0])):
    item = '"%s": %.1f, ' % (k, v)
    if len(cur) + len(item) > 100:
        lines.append(cur.rstrip())
        cur = "\t"
    cur += item
lines.append(cur.rstrip().rstrip(","))
print("const PART_COST := {\n" + "\n".join(lines) + "\n}")
