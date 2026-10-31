#!/usr/bin/env python3
"""Before / after pairs side by side: python3 tools/sky_day/sheet.py <before> <after> <out.jpg> [names...]"""
import os, sys
from PIL import Image, ImageDraw
a, b, out = sys.argv[1:4]
names = sys.argv[4:] or sorted(f[:-4] for f in os.listdir(a) if f.endswith(".png") and os.path.exists(os.path.join(b, f)))
W, H = 560, 315
sheet = Image.new("RGB", (W * 2, H * len(names)), (0, 0, 0))
for i, n in enumerate(names):
	for j, d in enumerate((a, b)):
		p = os.path.join(d, n + ".png")
		if os.path.exists(p):
			im = Image.open(p).convert("RGB").resize((W, H), Image.LANCZOS)
			sheet.paste(im, (j * W, i * H))
	ImageDraw.Draw(sheet).text((6, i * H + 4), n + "  before | after", fill=(255, 255, 0))
sheet.save(out, quality=88)
