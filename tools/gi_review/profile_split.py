#!/usr/bin/env python3
"""gi_shot.gd's PROFILE=1 log (with --gpu-profile) as one table per shot: the frame's mean GPU
time and the passes the GI review cares about (SSAO, SSIL, SDFGI, the rest).

    python3 tools/gi_review/profile_split.py < log.txt
"""
import re
import sys

KEYS = ("ssao", "ssil", "sdfgi", "gi", "volumetric", "ssr", "shadow", "opaque", "transparent", "depth")
shots = []
cur = None
block = None
for line in sys.stdin:
    line = line.rstrip("\n")
    m = re.search(r"GPU_PROFILE_BEGIN shot (\d+)(.*)", line)
    if m:
        cur = {"shot": m.group(1) + m.group(2), "blocks": []}
        shots.append(cur)
        continue
    if "GPU_PROFILE_END" in line:
        cur = None
        continue
    if cur is None:
        continue
    m = re.match(r"GPU PROFILE \(total ([0-9.]+)ms\)", line.strip())
    if m:
        block = {"__total": float(m.group(1))}
        cur["blocks"].append(block)
        continue
    m = re.match(r"\s*-(.+): ([0-9.e-]+)ms", line)
    if m and block is not None:
        block[m.group(1).strip()] = float(m.group(2))

if not shots:
    sys.exit("no GPU_PROFILE_BEGIN shot markers - run gi_shot.gd with PROFILE=1 and --gpu-profile")
for s in shots:
    bl = s["blocks"]
    if not bl:
        print("shot %s: no GPU PROFILE blocks" % s["shot"])
        continue
    avg = {}
    for b in bl:
        for k, v in b.items():
            avg[k] = avg.get(k, 0.0) + v / len(bl)
    total = avg.pop("__total")
    print("shot %s: GPU frame %.1f ms (%d samples)" % (s["shot"], total, len(bl)))
    for k, v in sorted(avg.items(), key=lambda kv: -kv[1]):
        if any(w in k.lower() for w in KEYS) or v > total * 0.04:
            print("   %6.1f ms %5.1f %%  %s" % (v, 100.0 * v / total, k))
