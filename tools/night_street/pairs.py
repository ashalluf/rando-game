#!/usr/bin/env python3
"""Before / after pairs of the night street bookmarks, side by side (left before, right after),
1280 px wide JPEGs for the shots branch:
  python3 tools/night_street/pairs.py <before dir> <after dir> <out dir> [prefix]
Pairs every name both runs have (n*.png full city, or f*.png small scenes with PLACES)."""
import os, sys
from PIL import Image, ImageDraw
sys.path.insert(0, os.path.dirname(__file__))
import importlib.util
spec = importlib.util.spec_from_file_location("measure", os.path.join(os.path.dirname(__file__), "measure.py"))
b, a, out = sys.argv[1], sys.argv[2], sys.argv[3]
prefix = sys.argv[4] if len(sys.argv) > 4 else ""
sys.argv = [sys.argv[0]]
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
os.makedirs(out, exist_ok=True)
bf = dict(m.files(b))
k = 0
for name, f in m.files(a):
	if name not in bf:
		continue
	k += 1
	sheet = Image.new("RGB", (1280, 360))
	for i, src in enumerate((bf[name], f)):
		sheet.paste(Image.open(src).convert("RGB").resize((640, 360)), (i * 640, 0))
	d = ImageDraw.Draw(sheet)
	d.text((8, 6), "before", fill=(255, 255, 255))
	d.text((648, 6), "after", fill=(255, 255, 255))
	w, nm = name.split(" ")
	fn = "%s%02d_%s_%s.jpg" % (prefix, k, nm, "clear" if w == "c" else "rain")
	sheet.save(os.path.join(out, fn), quality=86)
	print(fn)
