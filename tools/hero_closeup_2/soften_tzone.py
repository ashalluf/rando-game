#!/usr/bin/env python3
"""Softens the oily T-zone the hero's skin maps carry (hero-closeup-2).

tools/hero/prep_textures.py built the T-zone from hard steps across the face (`ax < 0.02` for the
nose, `ax < 0.055` for the forehead), so the roughness map and the mask's oil channel held two
sharp-edged rectangles: in the game a pale, sky-coloured trapezoid down the bridge of the nose and
across the forehead - the waxy look. prep_textures.py now uses smooth edges; this applies the same
fix to the shipped maps without a whole hero rebuild (which needs Blender and MPFB):

    python3 tools/hero_closeup_2/soften_tzone.py            # rewrites both maps in place

roughness = base - 0.14 * tzone (prep_textures.py), so the hard tzone is swapped for a blurred
one in both maps. Run it once; a second run blurs a blurred zone (harmless but wider).
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
MASK = os.path.join(ROOT, "assets/models/hero_x_skin_mask.png")
ROUGH = os.path.join(ROOT, "assets/models/hero_hero_skin_roughness.png")
TZONE_ROUGH = 0.14   # prep_textures.py: rough = 0.52 - 0.14 * tzone ...
RADIUS = 9.0         # px of the 1024 maps, ~6 mm on the face
# The nose's own oily patch (hero-face-2's `- 0.05 * nose * noise`, the same hard `ax < 0.02`
# box): found by its step edges in the 1024 roughness map, smoothed inside a feathered window.
NOSE_BOX = (812, 490, 877, 566)  # x0, y0, x1, y1
NOSE_FEATHER = 8.0
NOSE_RADIUS = 6.0


def main() -> int:
    m = Image.open(MASK)
    assert m.mode == "RGBA", m.mode
    a = np.asarray(m).astype(np.float32) / 255.0
    tz = a[..., 3]
    soft = np.asarray(Image.fromarray((tz * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(RADIUS))).astype(np.float32) / 255.0
    # keep the zone's strength in its middle: a blur also lowers a narrow strip's peak
    soft = np.clip(soft * 1.15, 0.0, 1.0) * 0.85
    r_img = Image.open(ROUGH)
    mode = r_img.mode
    r = np.asarray(r_img).astype(np.float32) / 255.0
    delta = TZONE_ROUGH * (tz - soft)
    if r.ndim == 3:
        r[..., :3] += delta[..., None]
    else:
        r += delta
    x0, y0, x1, y1 = NOSE_BOX
    h, w = r.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    edge = np.minimum(np.minimum(xx - x0, x1 - xx), np.minimum(yy - y0, y1 - yy)).astype(np.float32)
    win = np.clip(edge / NOSE_FEATHER, 0.0, 1.0)
    blur = np.asarray(Image.fromarray((np.clip(r, 0, 1) * 255).astype(np.uint8), mode).filter(ImageFilter.GaussianBlur(NOSE_RADIUS))).astype(np.float32) / 255.0
    r = r + (blur - r) * (win[..., None] if r.ndim == 3 else win)
    Image.fromarray((np.clip(r, 0, 1) * 255 + 0.5).astype(np.uint8), mode).save(ROUGH)
    a[..., 3] = soft
    Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(MASK)
    print("softened the T-zone: mean |delta| %.4f, max %.3f" % (float(np.abs(delta).mean()), float(np.abs(delta).max())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
