#!/usr/bin/env python3
"""A contact sheet of a night street run (n*.png or f*.png), 4 across, for a quick look:
  python3 tools/night_street/sheet.py <dir> <out.jpg> [width per tile, default 400]"""
import sys, os, glob, re
from PIL import Image
d, out = sys.argv[1], sys.argv[2]
w = int(sys.argv[3]) if len(sys.argv) > 3 else 400
fs = sorted(glob.glob(os.path.join(d, "[nf].png")) + glob.glob(os.path.join(d, "[nf]_*.png")),
	key=lambda f: int(re.findall(r"_(\d+)\.png$", f)[0]) if "_" in os.path.basename(f) else 0)
ims = [Image.open(f).convert("RGB") for f in fs]
h = int(w * ims[0].height / ims[0].width)
rows = (len(ims) + 3) // 4
sheet = Image.new("RGB", (w * 4, h * rows))
for i, im in enumerate(ims):
	sheet.paste(im.resize((w, h)), ((i % 4) * w, (i // 4) * h))
sheet.save(out, quality=85)
