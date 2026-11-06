#!/usr/bin/env python3
"""Ghost-sign lettering atlas for the murals (scripts/world/murals.gd, shaders/mural.gdshader).

A ghost sign is an old advertisement painted straight onto a brick wall a century ago and left
to fade: tall condensed capitals, a block shadow, a ruled panel. Every product and store here is
INVENTED (no real brand, company or person), and the lettering is drawn from system fonts that
are only rasterised into the texture (no font file ships):

    DejaVu Sans / Serif (Bitstream Vera licence), Liberation Sans / Serif (SIL OFL 1.1).

Output: assets/textures/murals/ghost_signs.png, 2048 x 2048, sixteen cells of 1024 x 256 (two
columns, eight rows; cell i at column i % 2, row i / 2). Each cell is three masks, not colours -
the shader paints them in the sign's faded period palette:

    R  the painted field (the panel the sign was painted on, its border rule cut out of it)
    G  the main lettering
    B  the secondary lettering, the main lettering's block shadow and the panel's rules

Run:  python3 tools/make_murals.py
Then: godot --headless --path . --import, and python3 tools/fix_texture_imports.py
      assets/textures/murals (VRAM compression, mipmaps); commit the PNG and its .import.
"""

import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures", "murals", "ghost_signs.png")
FONT_DIRS = ["/usr/share/fonts/truetype/dejavu", "/usr/share/fonts/truetype/liberation",
             "/usr/share/fonts/truetype/freefont"]
CELL_W, CELL_H = 1024, 256
SS = 2  # drawn at twice the size, then reduced: clean edges for the mips

# The signs, invented. Each: (main line, second line or "", style).
# Styles: "serif" a slab of tall serif capitals; "gothic" condensed sans; "split" the main line
# with a small line above it.
SIGNS = [
    ("HOTEL ALDERWICK", "ROOMS 75¢  •  BATHS  •  BY THE WEEK", "serif"),
    ("BASIN ICE & COAL CO.", "PROMPT DELIVERY  •  PHONE MAIN 2140", "gothic"),
    ("QUILLAN'S FURNITURE", "EASY TERMS  •  EVERYTHING FOR THE HOME", "serif"),
    ("GOLDEN ACRE CITRUS", "FRESH FROM THE GROVE", "gothic"),
    ("VELLMAR COFFEE", "ROASTED DAILY", "serif"),
    ("ORCHARD QUEEN", "PRESERVES  •  JAMS  •  JELLIES", "split"),
    ("EASTMOOR STEAM LAUNDRY", "WE CALL AND DELIVER", "gothic"),
    ("TREADMORE SHOES", "FOR THE WHOLE FAMILY", "serif"),
    ("DUVALL TRUNK & BAG CO.", "MANUFACTURERS", "gothic"),
    ("WHITCOMBE", "BAKING POWDER  •  ALWAYS RELIABLE", "split"),
    ("THESSALY CIGARS", "5¢  •  HAND ROLLED", "serif"),
    ("OSTERHOUT DRY GOODS", "WHOLESALE & RETAIL", "gothic"),
    ("LINDQVIST SODA", "ICE COLD  •  5¢", "serif"),
    ("IRONCLAD STORAGE", "FIREPROOF  •  MOVING  •  PACKING", "gothic"),
    ("BELLHAVEN CREAMERY", "MILK  •  BUTTER  •  ICE CREAM", "split"),
    ("ROSSITER PIANOS", "PLAYERS  •  ORGANS  •  RECORDS", "serif"),
]


def font(names, size):
    for name in names:
        for d in FONT_DIRS:
            p = os.path.join(d, name)
            if os.path.exists(p):
                return ImageFont.truetype(p, size)
    return ImageFont.load_default()


SERIF = ["DejaVuSerif-Bold.ttf", "LiberationSerif-Bold.ttf", "FreeSerifBold.ttf"]
SANS = ["LiberationSans-Bold.ttf", "DejaVuSans-Bold.ttf", "FreeSansBold.ttf"]


def text_mask(text, fnt, height, width_limit, condense):
    """The text as a mask `height` px tall (cap height fills it), squeezed horizontally by
    `condense` (the tall narrow capitals of the period) and never wider than width_limit."""
    l, t, r, b = fnt.getbbox(text)
    img = Image.new("L", (r - l + 8, b - t + 8), 0)
    ImageDraw.Draw(img).text((4 - l, 4 - t), text, font=fnt, fill=255)
    w = max(1, int(img.width * height / img.height * condense))
    w = min(w, width_limit)
    return img.resize((w, height), Image.LANCZOS)


def cell(main, sub, style, index):
    W, H = CELL_W * SS, CELL_H * SS
    field = Image.new("L", (W, H), 0)
    mainm = Image.new("L", (W, H), 0)
    second = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(field)
    m = 10 * SS
    # The panel, with clipped corners on some.
    if index % 3 == 0:
        c = 26 * SS
        d.polygon([(m + c, m), (W - m - c, m), (W - m, m + c), (W - m, H - m - c), (W - m - c, H - m),
                   (m + c, H - m), (m, H - m - c), (m, m + c)], fill=255)
    else:
        d.rectangle([m, m, W - m, H - m], fill=255)
    # Its rules: a thin line inset round the panel.
    ds = ImageDraw.Draw(second)
    rr = 22 * SS
    ds.rectangle([rr, rr, W - rr, H - rr], outline=255, width=4 * SS)
    fnames = SERIF if style == "serif" else SANS
    condense = 0.78 if style == "serif" else 0.62
    inner_w = W - 2 * rr - 40 * SS
    if style == "split":
        top_h = int(H * 0.17)
        main_h = int(H * 0.40)
        sub_h = int(H * 0.13)
        t = text_mask("THE ORIGINAL", font(SANS, 120), top_h, inner_w // 2, 0.7)
        second.paste(255, ((W - t.width) // 2, int(H * 0.12)), t)
        mm = text_mask(main, font(SERIF, 220), main_h, inner_w, 0.85)
        my = int(H * 0.32)
        sm = text_mask(sub, font(SANS, 120), sub_h, inner_w, 0.66)
        sy = int(H * 0.74)
    else:
        main_h = int(H * (0.46 if sub else 0.62))
        sub_h = int(H * 0.14)
        mm = text_mask(main, font(fnames, 220), main_h, inner_w, condense)
        my = int(H * (0.15 if sub else 0.19))
        sm = text_mask(sub, font(SANS, 120), sub_h, inner_w, 0.66) if sub else None
        sy = int(H * 0.69)
    mx = (W - mm.width) // 2
    # The block shadow: the lettering again, down and to the right, in the second colour.
    sh = 7 * SS
    for k in range(1, sh + 1):
        second.paste(255, (mx + k, my + k), mm)
    mainm.paste(255, (mx, my), mm)
    # The shadow never shows through the face of the letters.
    second = Image.fromarray(np.minimum(np.asarray(second), 255 - np.asarray(mainm)))
    if sm is not None:
        second.paste(255, ((W - sm.width) // 2, sy), sm)
        # A rule either side of the line under the name.
        ds = ImageDraw.Draw(second)
        y = sy + sm.height // 2
        if (W - sm.width) // 2 - 60 * SS > rr + 30 * SS:
            ds.line([(rr + 30 * SS, y), ((W - sm.width) // 2 - 30 * SS, y)], fill=255, width=4 * SS)
            ds.line([((W + sm.width) // 2 + 30 * SS, y), (W - rr - 30 * SS, y)], fill=255, width=4 * SS)
    # The rules and lettering are cut out of the field (they are painted in other colours).
    f = np.asarray(field).astype(np.float32)
    g = np.asarray(mainm).astype(np.float32)
    b = np.asarray(second).astype(np.float32)
    out = np.stack([f, g, b], axis=-1).astype(np.uint8)
    img = Image.fromarray(out, "RGB").resize((CELL_W, CELL_H), Image.LANCZOS)
    return img


def main():
    atlas = Image.new("RGB", (CELL_W * 2, CELL_H * 8), (0, 0, 0))
    for i, (main_line, sub, style) in enumerate(SIGNS):
        atlas.paste(cell(main_line, sub, style, i), ((i % 2) * CELL_W, (i // 2) * CELL_H))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    atlas.save(OUT, optimize=True)
    print("wrote", OUT, atlas.size, "signs", len(SIGNS))


if __name__ == "__main__":
    sys.exit(main())
