#!/usr/bin/env python3
"""Join drive_strip.gd's stills into one strip per scenario.

    python3 tools/driving_camera/strips.py build/drivecam out_dir [prefix ...]

For each prefix (default "after_") and scenario (s30 s80 s150 corner jump) it lays the
<prefix><scenario>_<n>.jpg frames side by side at 480 px each, with a label, and writes
<out_dir>/<prefix><scenario>_strip.jpg."""
import os
import sys
from PIL import Image, ImageDraw

SCEN = ["s30", "s80", "s150", "corner", "jump"]
LABEL = {"s30": "30 km/h", "s80": "80 km/h", "s150": "150 km/h", "corner": "35 km/h right turn",
         "jump": "80 km/h hop: up, apex, landing, after"}


def main() -> None:
    src, out = sys.argv[1], sys.argv[2]
    prefixes = sys.argv[3:] or ["after_"]
    os.makedirs(out, exist_ok=True)
    for pre in prefixes:
        for sc in SCEN:
            frames = []
            for n in range(8):
                p = os.path.join(src, f"{pre}{sc}_{n}.jpg")
                if os.path.exists(p):
                    frames.append(Image.open(p).convert("RGB"))
            if not frames:
                continue
            w = 480
            h = int(frames[0].height * w / frames[0].width)
            strip = Image.new("RGB", (w * len(frames), h + 26), (16, 16, 16))
            for i, f in enumerate(frames):
                strip.paste(f.resize((w, h), Image.LANCZOS), (i * w, 26))
            d = ImageDraw.Draw(strip)
            d.text((8, 6), f"{pre.rstrip('_') or 'after'}: {LABEL[sc]}", fill=(240, 240, 240))
            dst = os.path.join(out, f"{pre}{sc}_strip.jpg")
            strip.save(dst, quality=86)
            print(dst, strip.size)


if __name__ == "__main__":
    main()
