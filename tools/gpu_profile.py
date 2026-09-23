#!/usr/bin/env python3
"""Averages the `--gpu-profile` blocks Godot prints between GPU_PROFILE_BEGIN and _END
(see tools/gpu_profile.gd) and lists the passes by share of the frame."""
import re
import sys

inside = False
blocks = []
current = None
geo = ""
for line in sys.stdin:
    line = line.rstrip("\n")
    if "GPU_PROFILE_BEGIN" in line:
        inside = True
        continue
    if "GPU_PROFILE_END" in line:
        inside = False
        continue
    if line.startswith("GEO ") or line.startswith("MEM "):
        geo += line + "\n"
    if not inside:
        continue
    m = re.match(r"GPU PROFILE \(total ([0-9.]+)ms\)", line.strip())
    if m:
        current = {"__total": float(m.group(1))}
        blocks.append(current)
        continue
    m = re.match(r"\s*-(.+): ([0-9.e-]+)ms", line)
    if m and current is not None:
        current[m.group(1)] = float(m.group(2))

if not blocks:
    sys.exit("no GPU PROFILE blocks between the markers - was --gpu-profile passed?")
totals = {}
for b in blocks:
    for k, v in b.items():
        totals[k] = totals.get(k, 0.0) + v / len(blocks)
frame = totals.pop("__total")
print("GPU frame %.1f ms over %d samples (software GPU: read the shares)" % (frame, len(blocks)))
for k, v in sorted(totals.items(), key=lambda kv: -kv[1])[:int(sys.argv[1]) if len(sys.argv) > 1 else 30]:
    print("  %8.2f ms  %5.1f%%  %s" % (v, 100.0 * v / frame if frame else 0.0, k))
if geo:
    print(geo.rstrip())
