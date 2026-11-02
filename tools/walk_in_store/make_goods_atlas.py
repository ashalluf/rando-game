#!/usr/bin/env python3
"""The corner store's packaging atlas (CornerStoreKit goods, shaders/corner_store_goods.gdshader).

8 x 8 cells of 256 px in one 2048 px JPG: every cell is the FRONT of an invented product - a
ground colour from real-world shares (white, cream, black, red, brown, kraft, navy, green, a few
brights), bands of print, an invented abstract mark (rings, a star burst, a leaf, a wave, a
chevron: never a real brand's), a name in fake block lettering (bars, no real words), a smaller
line under it, a flavour photo blob, a barcode, and on boxes a nutrition panel. The shader picks
a cell per instance (INSTANCE_CUSTOM.r) and stretches it over the pack's front.

    python3 tools/walk_in_store/make_goods_atlas.py   (writes assets/textures/corner_store/goods_labels.jpg)
"""
import random
from PIL import Image, ImageDraw, ImageFilter

CELL = 256
N = 8
OUT = "assets/textures/corner_store/goods_labels.jpg"

# Ground colours and how often a real shelf shows them.
GROUNDS = [
    ((236, 234, 226), 18), ((246, 240, 222), 8), ((24, 24, 26), 12), ((176, 28, 30), 12),
    ((96, 58, 36), 8), ((190, 150, 104), 8), ((28, 44, 92), 8), ((30, 92, 54), 6),
    ((232, 186, 40), 5), ((214, 96, 30), 4), ((120, 40, 110), 3), ((60, 140, 190), 4),
    ((210, 60, 90), 2), ((160, 160, 164), 3),
]
INKS_DARK = [(20, 20, 22), (120, 20, 24), (30, 40, 90), (70, 40, 20)]
INKS_LIGHT = [(250, 248, 240), (250, 214, 60), (240, 236, 220)]
ACCENTS = [(206, 32, 36), (240, 190, 30), (30, 120, 70), (40, 80, 170), (230, 110, 30), (250, 250, 250), (20, 20, 20)]


def pick(rng, table):
    total = sum(w for _, w in table)
    r = rng.uniform(0, total)
    for c, w in table:
        r -= w
        if r <= 0:
            return c
    return table[-1][0]


def luma(c):
    return 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]


def block_text(d, rng, x0, y0, w, h, ink, letters=None):
    """Fake lettering: a row of bars and bowls, no real words."""
    n = letters or rng.randint(4, 9)
    lw = w / n
    for i in range(n):
        x = x0 + i * lw
        kind = rng.random()
        pad = lw * 0.12
        if kind < 0.35:
            d.rectangle([x + pad, y0, x + lw - pad, y0 + h], fill=ink)
            d.rectangle([x + lw * 0.35, y0 + h * 0.25, x + lw * 0.65, y0 + h * 0.75], fill=None)
        elif kind < 0.6:
            d.ellipse([x + pad, y0, x + lw - pad, y0 + h], fill=ink)
        elif kind < 0.8:
            d.rectangle([x + pad, y0, x + lw * 0.4, y0 + h], fill=ink)
            d.rectangle([x + pad, y0 + h * 0.8, x + lw - pad, y0 + h], fill=ink)
        else:
            d.polygon([(x + pad, y0 + h), (x + lw * 0.5, y0), (x + lw - pad, y0 + h)], fill=ink)


def mark(d, rng, cx, cy, r, ink, accent):
    k = rng.randrange(6)
    if k == 0:
        for i in range(3):
            rr = r * (1 - i * 0.28)
            d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=ink if i % 2 == 0 else accent, width=max(2, int(r * 0.12)))
    elif k == 1:
        pts = []
        import math
        for i in range(16):
            a = i * math.pi / 8
            rr = r if i % 2 == 0 else r * 0.45
            pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
        d.polygon(pts, fill=accent)
    elif k == 2:
        d.ellipse([cx - r, cy - r * 0.55, cx + r, cy + r * 0.55], fill=accent)
        d.line([cx - r, cy, cx + r, cy], fill=ink, width=3)
    elif k == 3:
        for i in range(3):
            y = cy - r * 0.5 + i * r * 0.5
            d.arc([cx - r, y - r * 0.4, cx + r, y + r * 0.4], 200, 340, fill=accent, width=max(2, int(r * 0.15)))
    elif k == 4:
        d.polygon([(cx - r, cy + r * 0.3), (cx, cy - r * 0.6), (cx + r, cy + r * 0.3), (cx + r * 0.6, cy + r * 0.3), (cx, cy - r * 0.15), (cx - r * 0.6, cy + r * 0.3)], fill=accent)
    else:
        d.rectangle([cx - r, cy - r * 0.6, cx + r, cy + r * 0.6], fill=accent)
        d.ellipse([cx - r * 0.45, cy - r * 0.45, cx + r * 0.45, cy + r * 0.45], fill=ink)


def barcode(d, rng, x0, y0, w, h):
    d.rectangle([x0 - 4, y0 - 4, x0 + w + 4, y0 + h + 4], fill=(248, 248, 246))
    x = x0
    while x < x0 + w:
        bw = rng.choice([1, 1, 2, 3])
        if rng.random() < 0.55:
            d.rectangle([x, y0, x + bw - 1, y0 + h], fill=(16, 16, 16))
        x += bw


def nutrition(d, rng, x0, y0, w, h):
    d.rectangle([x0, y0, x0 + w, y0 + h], fill=(250, 250, 248), outline=(16, 16, 16), width=2)
    y = y0 + 6
    while y < y0 + h - 6:
        lw = rng.uniform(0.3, 0.9) * (w - 12)
        d.line([x0 + 6, y, x0 + 6 + lw, y], fill=(30, 30, 30), width=2)
        y += rng.choice([6, 7, 10])


def cell(rng, kind):
    img = Image.new("RGB", (CELL, CELL), (0, 0, 0))
    d = ImageDraw.Draw(img)
    ground = pick(rng, GROUNDS)
    d.rectangle([0, 0, CELL, CELL], fill=ground)
    dark = luma(ground) > 120
    ink = rng.choice(INKS_DARK) if dark else rng.choice(INKS_LIGHT)
    accent = rng.choice([a for a in ACCENTS if abs(luma(a) - luma(ground)) > 50] or ACCENTS)
    # Bands of print.
    for _ in range(rng.randint(0, 3)):
        y = rng.randint(0, CELL)
        hh = rng.randint(8, 50)
        d.rectangle([0, y, CELL, y + hh], fill=rng.choice([accent, ink, ground]))
    if rng.random() < 0.4:
        y = rng.randint(130, 200)
        d.polygon([(0, y), (CELL, y - rng.randint(-40, 60)), (CELL, CELL), (0, CELL)], fill=accent)
    # A flavour "photo": soft blobs.
    if rng.random() < 0.6:
        blob = Image.new("RGB", (CELL, CELL), (0, 0, 0))
        mask = Image.new("L", (CELL, CELL), 0)
        bd = ImageDraw.Draw(blob)
        md = ImageDraw.Draw(mask)
        cx, cy = rng.randint(70, 186), rng.randint(130, 200)
        base = rng.choice([(200, 120, 40), (150, 40, 30), (230, 200, 120), (90, 140, 60), (120, 70, 40), (230, 230, 210)])
        for _ in range(9):
            r = rng.randint(14, 40)
            ox, oy = cx + rng.randint(-50, 50), cy + rng.randint(-25, 25)
            sh = rng.uniform(0.7, 1.15)
            bd.ellipse([ox - r, oy - r, ox + r, oy + r], fill=tuple(min(255, int(c * sh)) for c in base))
            md.ellipse([ox - r, oy - r, ox + r, oy + r], fill=255)
        mask = mask.filter(ImageFilter.GaussianBlur(3))
        img.paste(blob, (0, 0), mask)
    # The mark and the name.
    mark(d, rng, rng.randint(50, 80), rng.randint(40, 70), rng.randint(20, 34), ink, accent)
    nx = rng.randint(90, 120)
    block_text(d, rng, nx, rng.randint(30, 60), CELL - nx - 14, rng.randint(26, 42), ink)
    block_text(d, rng, 20, rng.randint(98, 120), rng.randint(110, 200), rng.randint(10, 16), ink if rng.random() < 0.7 else accent)
    # Small print, a barcode, a nutrition panel on boxes.
    for i in range(rng.randint(1, 3)):
        y = 214 + i * 9
        d.line([16, y, 16 + rng.randint(60, 200), y], fill=ink, width=2)
    if kind == "box" and rng.random() < 0.5:
        nutrition(d, rng, 170, 160, 70, 80)
    if rng.random() < 0.7:
        barcode(d, rng, rng.choice([16, 170]), 228, 64, 20)
    # A thin border some packs have.
    if rng.random() < 0.3:
        d.rectangle([3, 3, CELL - 4, CELL - 4], outline=accent, width=4)
    return img


def main():
    rng = random.Random(4242)
    atlas = Image.new("RGB", (CELL * N, CELL * N))
    for i in range(N * N):
        kind = "box" if i % 3 == 0 else "label"
        atlas.paste(cell(rng, kind), ((i % N) * CELL, (i // N) * CELL))
    # A whisper of print blur: real packs are not vector-sharp at 256 px a face.
    atlas = atlas.filter(ImageFilter.GaussianBlur(0.6))
    atlas.save(OUT, quality=90)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
