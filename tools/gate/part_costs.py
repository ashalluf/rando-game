#!/usr/bin/env python3
"""Prints smoke_test.gd's PART_COST table from a whole run's log (SMOKE_PROFILE=1 prints a PART
line per part and check file). Paste the output over the table in tests/smoke_test.gd: only the
shards' deal depends on it, and a stale table deals a 150 s file as a 6 s one.

Usage: python3 tools/gate/part_costs.py <log>[ <log2> ...]
A sharded run's logs together give the whole table (each part ran in exactly one shard). A RESET
line (the reset and stage_home before a file, SMOKE_PROFILE=1) is added to its file's cost: it is
what the job costs the shard that takes it.
"""
import re
import sys

costs = {}
resets = {}
for path in sys.argv[1:]:
    for line in open(path, errors="replace"):
        m = re.match(r"PART (\w+) ([\d.]+) s", line)
        if m and m.group(1) != "city_files":
            costs[m.group(1)] = float(m.group(2))
        m = re.match(r"RESET (\w+) ([\d.]+) s", line)
        if m:
            resets[m.group(1)] = float(m.group(2))
for k, v in resets.items():
    if k in costs:
        costs[k] += v
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
