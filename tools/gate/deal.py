#!/usr/bin/env python3
"""Prints the shards' deal as tests/smoke_test.gd's shard_plan() makes it, and each share's
predicted seconds (its parts' PART_COST plus a city load), without running Godot.

Usage: python3 tools/gate/deal.py [shards] [smoke_test.gd]
Compare with a real run: `python3 tools/gate/deal.py 3` before a change to PART_COST, and the
shards' SMOKE TIME lines after. Mirrors shard_plan() (keep the two in step).
"""
import os
import re
import sys

count = int(sys.argv[1]) if len(sys.argv) > 1 else 3
path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), "../../tests/smoke_test.gd")
src = open(path).read()
table = src[src.index("const PART_COST := {"):src.index("\n}\n", src.index("const PART_COST := {"))]
cost = {k: float(v) for k, v in re.findall(r'"(\w+)": ([\d.]+)', table)}
default = float(re.search(r"const DEFAULT_COST := ([\d.]+)", src).group(1))
load = float(re.search(r"const CITY_LOAD_COST := ([\d.]+)", src).group(1))
parts = re.search(r"const CITY_PARTS := \[(.*?)\]", src, re.S).group(1)
inline = re.search(r"const INLINE_FILES := \[(.*?)\]", src, re.S).group(1)
names = ["room"] + re.findall(r'"(\w+)"', parts)
skip = set(re.findall(r'"(\w+)"', inline))
tests = os.path.dirname(path)
names += sorted(f[:-3] for f in os.listdir(tests) if f.endswith("_checks.gd") and f[:-3] not in skip)
names.sort(key=lambda n: (-cost.get(n, default), n))
busy, city, shares = [0.0] * count, [False] * count, [[] for _ in range(count)]
for n in names:
    c = cost.get(n, default)
    is_city = n != "room"
    ends = [busy[i] + c + (load if is_city and not city[i] else 0.0) for i in range(count)]
    best = min(range(count), key=lambda i: (ends[i], i))
    shares[best].append(n)
    busy[best] = ends[best]
    city[best] = city[best] or is_city
missing = [n for n in names if n not in cost]
for i in range(count):
    print("share %d/%d: %.0f s predicted, %d parts" % (i, count, busy[i], len(shares[i])))
print("%d parts, %d not in PART_COST (dealt at %.0f s)" % (len(names), len(missing), default))
