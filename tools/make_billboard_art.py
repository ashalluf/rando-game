#!/usr/bin/env python3
"""Billboard ad art: one atlas of invented advertising for the city's billboards.

Everything here is ORIGINAL and drawn by this script: invented films, a soda, a phone, a
personal-injury lawyer, an energy drink, a streaming show, an airline (SUNCREST AIR, the airport's
sunset-liveried carrier), a burger stand, a tequila, an electric car, a radio station, sneakers.
No real brand, product, logo, slogan, person or phone number (every number is a 555 number).

Writes assets/textures/billboards/billboard_ads.jpg (2048 x 3072, sRGB):
  * 12 bulletins (14 x 48 ft, 3.43:1) of 1024 x 298 in 2 columns x 6 rows (rows 0 .. 1788),
  * 12 posters (12 x 24 ft, 2:1) of 512 x 256 in 4 columns x 3 rows (rows 1788 .. 2556),
  * 6 portraits (bus-shelter panels and tower supergraphics, 2:3) of 341 x 512 (rows 2556 .. 3068).
scripts/world/billboards.gd holds the same grid (CELLS_*). Paper seams, fade, tears, the vinyl's
sheen and the night lighting are the shader's (shaders/billboard_face.gdshader), per instance.
It also writes scripts/world/billboard_table.gd: the linear mean colour of every cell, which the
far boxes (building_lod.gdshader) draw a board as.

Each cell is drawn at twice its size and filtered down. Fonts: DejaVu Sans / Serif (Bitstream Vera
licence) and Liberation Sans / Serif (SIL OFL 1.1) from the system's font packages, rasterised into
the texture only (no font file ships).

    python3 tools/make_billboard_art.py             # atlas + table
    python3 tools/make_billboard_art.py --preview   # also build/billboard_preview.jpg (a contact sheet)

Then `godot --headless --path . --import` and `python3 tools/fix_texture_imports.py` on the new
.import (VRAM compression, mipmaps), and commit the .jpg, its .import and the table.
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
OUT = os.path.join(ROOT, "assets", "textures", "billboards", "billboard_ads.jpg")
TABLE = os.path.join(ROOT, "scripts", "world", "billboard_table.gd")
SEED = 20261004
SS = 2

W, H = 2048, 3072
BUL = (1024, 298)
POS = (512, 256)
POR = (341, 512)
BUL_Y = 0
POS_Y = 1788
POR_Y = 2556

FONT_DIRS = ["/usr/share/fonts/truetype/dejavu", "/usr/share/fonts/truetype/liberation"]
SANS_B = "DejaVuSans-Bold.ttf"
SANS_C = "LiberationSans-Bold.ttf"
SERIF_B = "DejaVuSerif-Bold.ttf"
LIB_B = "LiberationSans-Bold.ttf"
LIB_N = "LiberationSans-Bold.ttf"
LIB_SERIF_B = "LiberationSerif-Bold.ttf"
LIB_SERIF_I = "LiberationSerif-BoldItalic.ttf"
LIB = "LiberationSans-Regular.ttf"
LIB_I = "LiberationSans-BoldItalic.ttf"


def font(name, size):
    for d in FONT_DIRS:
        p = os.path.join(d, name)
        if os.path.exists(p):
            return ImageFont.truetype(p, max(6, int(size)))
    for d in FONT_DIRS:
        p = os.path.join(d, SANS_B)
        if os.path.exists(p):
            return ImageFont.truetype(p, max(6, int(size)))
    return ImageFont.load_default()


# ------------------------------------------------------------------------------------ helpers

def hexc(s, a=255):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), a)


def comp(img, layer, pos=(0, 0)):
    """Alpha-composite an RGBA layer onto the cell (which is RGB, so ImageDraw blends its fills)."""
    if img.mode == "RGBA":
        img.alpha_composite(layer, (int(pos[0]), int(pos[1])))
    else:
        img.paste(layer.convert("RGB"), (int(pos[0]), int(pos[1])), layer)


def gradient(w, h, top, bottom, horizontal=False):
    a = np.array(top[:3], float)
    b = np.array(bottom[:3], float)
    t = np.linspace(0.0, 1.0, w if horizontal else h)
    col = a[None, :] * (1 - t[:, None]) + b[None, :] * t[:, None]
    if horizontal:
        arr = np.repeat(col[None, :, :], h, axis=0)
    else:
        arr = np.repeat(col[:, None, :], w, axis=1)
    return Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGB").convert("RGBA")


def radial(w, h, cx, cy, r, inner, outer):
    y, x = np.mgrid[0:h, 0:w].astype(float)
    d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / max(r, 1.0)
    t = np.clip(d, 0.0, 1.0)[..., None]
    t = t * t * (3 - 2 * t)
    a = np.array(inner[:3], float)
    b = np.array(outer[:3], float)
    arr = a * (1 - t) + b * t
    return Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGB").convert("RGBA")


def glow(img, cx, cy, r, color, strength=1.0):
    w, h = img.size
    y, x = np.mgrid[0:h, 0:w].astype(float)
    d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / max(r, 1.0)
    a = np.exp(-d * d * 2.5) * strength
    base = np.asarray(img.convert("RGB"), float)
    c = np.array(color[:3], float)
    out = base + (c[None, None, :] - base) * np.clip(a, 0, 1)[..., None] * 0.0 + c[None, None, :] * a[..., None] * 0.6
    img.paste(Image.fromarray(out.clip(0, 255).astype(np.uint8), "RGB").convert("RGBA"))


def fit_font(name, text, max_w, max_h):
    size = max_h
    while size > 8:
        f = font(name, size)
        b = f.getbbox(text)
        if b[2] - b[0] <= max_w and b[3] - b[1] <= max_h:
            return f
        size = int(size * 0.94)
    return font(name, 8)


def text(img, xy, s, fname, max_w, max_h, fill, anchor="lm", shadow=None, stroke=0, stroke_fill=None):
    d = ImageDraw.Draw(img, "RGBA")
    f = fit_font(fname, s, max_w, max_h)
    if shadow is not None:
        sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(sh).text((xy[0] + shadow[0], xy[1] + shadow[1]), s, font=f, fill=shadow[2], anchor=anchor)
        sh = sh.filter(ImageFilter.GaussianBlur(shadow[3] if len(shadow) > 3 else 4))
        comp(img, sh)
    d.text(xy, s, font=f, fill=fill, anchor=anchor, stroke_width=stroke, stroke_fill=stroke_fill)
    return f


def noise_layer(w, h, scale, rnd, amp=18):
    small = (np.random.default_rng(rnd.randint(0, 1 << 30)).random((max(2, h // scale), max(2, w // scale))) * 255).astype(np.uint8)
    n = Image.fromarray(small, "L").resize((w, h), Image.BICUBIC)
    return n, amp


def grain(img, rnd, amp=6.0):
    arr = np.asarray(img.convert("RGB"), float)
    g = np.random.default_rng(rnd.randint(0, 1 << 30)).normal(0.0, amp, arr.shape[:2])
    arr += g[..., None]
    return Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGB").convert("RGBA")


def vignette(img, amount=0.35):
    w, h = img.size
    y, x = np.mgrid[0:h, 0:w].astype(float)
    d = np.sqrt(((x - w / 2) / (w / 2)) ** 2 + ((y - h / 2) / (h / 2)) ** 2)
    f = 1.0 - amount * np.clip(d - 0.4, 0, 1)
    arr = np.asarray(img.convert("RGB"), float) * f[..., None]
    return Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGB").convert("RGBA")


def shaded_ellipse(img, box, base, light=(1.35, 1.35, 1.35), dark=0.45, lx=-0.4, ly=-0.5):
    """A sphere-ish ellipse shaded from the top-left: products, planets, buns."""
    x0, y0, x1, y1 = [int(v) for v in box]
    w, h = max(2, x1 - x0), max(2, y1 - y0)
    y, x = np.mgrid[0:h, 0:w].astype(float)
    nx = (x / w) * 2 - 1
    ny = (y / h) * 2 - 1
    r2 = nx * nx + ny * ny
    inside = r2 <= 1.0
    nz = np.sqrt(np.clip(1 - r2, 0, 1))
    lam = np.clip(nx * lx + ny * ly + nz * 0.75, 0, 1)
    spec = np.clip(nx * lx + ny * ly + nz * 0.8, 0, 1) ** 24
    c = np.array(base[:3], float)
    col = c * (dark + (1 - dark) * lam)[..., None] + 255 * spec[..., None] * 0.6
    alpha = (inside * 255).astype(np.uint8)
    tile = Image.fromarray(np.dstack([col.clip(0, 255).astype(np.uint8), alpha]), "RGBA")
    tile = tile.filter(ImageFilter.GaussianBlur(0.6))
    comp(img, tile, (x0, y0))


def cylinder(img, box, base, label=None, cap=(200, 200, 205)):
    """A can or bottle body: a vertical cylinder shaded across, with a lit edge and a top ellipse."""
    x0, y0, x1, y1 = [int(v) for v in box]
    w, h = x1 - x0, y1 - y0
    x = np.linspace(-1, 1, w)
    lam = np.sqrt(np.clip(1 - x * x, 0, 1))
    shade = 0.35 + 0.65 * np.clip(lam * 0.9 + (-x) * 0.25, 0, 1)
    spec = np.exp(-((x + 0.45) / 0.09) ** 2) * 0.9 + np.exp(-((x - 0.7) / 0.05) ** 2) * 0.35
    c = np.array(base[:3], float)
    row = c[None, :] * shade[:, None] + 255 * spec[:, None]
    arr = np.repeat(row[None, :, :], h, axis=0)
    body = Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGB").convert("RGBA")
    if label is not None:
        label(body)
        # The label is shaded with the body.
        la = np.asarray(body.convert("RGB"), float)
        la = la * (0.45 + 0.55 * shade[None, :, None]) + 255 * spec[None, :, None] * 0.7
        body = Image.fromarray(la.clip(0, 255).astype(np.uint8), "RGB").convert("RGBA")
    mask = Image.new("L", (w, h), 0)
    md = ImageDraw.Draw(mask)
    e = max(4, w // 7)
    md.rectangle([0, e // 2, w, h - e // 2], fill=255)
    md.ellipse([0, h - e, w, h], fill=255)
    md.ellipse([0, 0, w, e], fill=255)
    img.paste(body, (x0, y0), mask)
    d = ImageDraw.Draw(img, "RGBA")
    d.ellipse([x0 + 2, y0, x1 - 2, y0 + e], fill=cap + (255,), outline=(120, 120, 125, 255), width=max(1, w // 60))


def smooth(pts, n):
    """Catmull-Rom through `pts` (an open polyline), n samples a span."""
    out = []
    for i in range(len(pts) - 1):
        p0 = pts[max(0, i - 1)]
        p1, p2 = pts[i], pts[i + 1]
        p3 = pts[min(len(pts) - 1, i + 2)]
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * (2 * p1[j] + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2 + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3) for j in range(2)))
    out.append(pts[-1])
    return out


def star(d, cx, cy, r, fill, points=5, inner=0.45, rot=-math.pi / 2):
    pts = []
    for i in range(points * 2):
        rr = r if i % 2 == 0 else r * inner
        a = rot + i * math.pi / points
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    d.polygon(pts, fill=fill)


def figure(d, cx, base_y, hgt, fill):
    """A standing human silhouette (head, shoulders, coat), hgt tall, feet at base_y."""
    hw = hgt * 0.18
    head = hgt * 0.12
    d.ellipse([cx - head * 0.5, base_y - hgt, cx + head * 0.5, base_y - hgt + head], fill=fill)
    d.polygon([(cx - hw * 0.35, base_y - hgt + head * 0.95), (cx + hw * 0.35, base_y - hgt + head * 0.95),
               (cx + hw, base_y - hgt * 0.68), (cx + hw * 0.75, base_y), (cx - hw * 0.75, base_y),
               (cx - hw, base_y - hgt * 0.68)], fill=fill)


# ------------------------------------------------------------------------------------- the ads
# Every draw function takes (img, w, h, fmt, rnd), fmt "b" bulletin, "p" poster, "q" portrait,
# and paints the whole cell (w x h, already at SS times its atlas size).

def ad_orbit(img, w, h, fmt, rnd):
    # Film: THE LAST ORBIT. Deep space, a lit planet limb, a lone astronaut, the date.
    img.paste(radial(w, h, w * 0.7, h * 0.4, max(w, h) * 0.9, (40, 70, 120), (4, 6, 16)))
    d = ImageDraw.Draw(img, "RGBA")
    r = random.Random(rnd.random())
    for _ in range(int(w * h / 900)):
        x, y = r.random() * w, r.random() * h
        s = r.random() ** 6 * 3 * SS
        d.ellipse([x - s, y - s, x + s, y + s], fill=(255, 255, 255, int(120 + r.random() * 135)))
    big = h * 1.5 if fmt == "b" else h * 1.2
    px, py = (w * 0.78, h * 1.25) if fmt != "q" else (w * 0.5, h * 1.05)
    shaded_ellipse(img, [px - big * 0.5, py - big * 0.5, px + big * 0.5, py + big * 0.5], (70, 120, 190), dark=0.08, lx=-0.7, ly=-0.6)
    glow(img, px - big * 0.32, py - big * 0.38, big * 0.25, (120, 190, 255), 0.6)
    d = ImageDraw.Draw(img, "RGBA")
    if fmt == "q":
        figure(d, w * 0.5, h * 0.62, h * 0.18, (8, 10, 16, 255))
        text(img, (w * 0.5, h * 0.16), "THE LAST", SANS_B, w * 0.7, h * 0.06, (210, 225, 240, 255), "mm")
        text(img, (w * 0.5, h * 0.26), "ORBIT", SERIF_B, w * 0.9, h * 0.13, (255, 255, 255, 255), "mm", shadow=(0, 0, (90, 170, 255, 200), 10))
        text(img, (w * 0.5, h * 0.92), "IN THEATERS JUNE 12", SANS_C, w * 0.8, h * 0.035, (190, 210, 230, 255), "mm")
    else:
        figure(d, w * 0.64, h * 0.86, h * 0.48, (8, 10, 16, 255))
        x0 = w * 0.05
        text(img, (x0, h * 0.22), "THE LAST", SANS_B, w * 0.3, h * 0.13, (210, 225, 240, 255), "lm")
        text(img, (x0, h * 0.5), "ORBIT", SERIF_B, w * 0.5, h * 0.36, (255, 255, 255, 255), "lm", shadow=(0, 0, (90, 170, 255, 220), 12))
        text(img, (x0, h * 0.82), "IN THEATERS JUNE 12", SANS_C, w * 0.34, h * 0.08, (190, 210, 230, 255), "lm")
        if fmt == "b":
            text(img, (w * 0.97, h * 0.88), "NO SIGNAL. NO WAY HOME.", LIB_N, w * 0.24, h * 0.06, (160, 180, 200, 255), "rm")


def ad_fizzly(img, w, h, fmt, rnd):
    # Soda: FIZZLY. Hot orange, bubbles, a sweating can.
    img.paste(radial(w, h, w * 0.4, h * 0.4, max(w, h) * 0.8, (255, 160, 40), (220, 40, 30)))
    d = ImageDraw.Draw(img, "RGBA")
    r = random.Random(rnd.random())
    for _ in range(int(w * h / 4000)):
        x, y = r.random() * w, r.random() * h
        s = (2 + r.random() ** 3 * 18) * SS
        d.ellipse([x - s, y - s, x + s, y + s], outline=(255, 235, 200, 150), width=max(1, SS))
    def label(body):
        bw, bh = body.size
        bd = ImageDraw.Draw(body, "RGBA")
        bd.rectangle([0, bh * 0.32, bw, bh * 0.68], fill=(255, 245, 230, 255))
        text(body, (bw * 0.5, bh * 0.5), "FIZZLY", SANS_B, bw * 0.95, bh * 0.2, (230, 50, 30, 255), "mm")
    if fmt == "q":
        cw, ch = w * 0.42, h * 0.48
        cylinder(img, [w * 0.29, h * 0.36, w * 0.29 + cw, h * 0.36 + ch], (240, 70, 40), label)
        text(img, (w * 0.5, h * 0.13), "FIZZLY", SANS_B, w * 0.85, h * 0.12, (255, 255, 255, 255), "mm", shadow=(4, 6, (120, 20, 0, 160), 6))
        text(img, (w * 0.5, h * 0.25), "Taste the Loud.", LIB_I, w * 0.8, h * 0.06, (255, 240, 200, 255), "mm")
        text(img, (w * 0.5, h * 0.92), "ORANGE  ·  CHERRY  ·  LIME", LIB_B, w * 0.85, h * 0.03, (255, 230, 200, 255), "mm")
    else:
        ch = h * 0.84
        cw = ch * 0.5
        for k, (dx, col) in enumerate([(0.62, (240, 70, 40)), (0.74, (200, 30, 60)), (0.86, (120, 190, 40))]):
            if fmt == "p" and k > 0:
                break
            x = w * dx - cw * 0.5 if fmt == "b" else w * 0.78 - cw * 0.5
            cylinder(img, [x, h * 0.1, x + cw, h * 0.1 + ch], col, label)
        text(img, (w * 0.05, h * 0.42), "FIZZLY", SANS_B, w * (0.48 if fmt == "b" else 0.55), h * 0.46, (255, 255, 255, 255), "lm", shadow=(5, 7, (120, 20, 0, 170), 8))
        text(img, (w * 0.055, h * 0.8), "Taste the Loud.", LIB_I, w * 0.4, h * 0.14, (255, 240, 200, 255), "lm")


def ad_lumen(img, w, h, fmt, rnd):
    # Phone: LUMEN X. Black, one phone at an angle with a lit screen, a thin line of copy.
    img.paste(gradient(w, h, (18, 18, 22), (2, 2, 4)))
    glow(img, w * (0.7 if fmt != "q" else 0.5), h * 0.5, max(w, h) * 0.35, (90, 60, 200), 0.5)
    pw = (h * 0.42 if fmt != "q" else w * 0.5)
    ph = pw * 2.05
    cx = w * (0.72 if fmt != "q" else 0.5)
    cy = h * 0.5 if fmt != "q" else h * 0.47
    phone = Image.new("RGBA", (int(pw) + 8, int(ph) + 8), (0, 0, 0, 0))
    pd = ImageDraw.Draw(phone, "RGBA")
    pd.rounded_rectangle([0, 0, pw, ph], radius=pw * 0.14, fill=(40, 40, 46, 255), outline=(160, 160, 170, 255), width=max(2, int(pw / 60)))
    scr = gradient(int(pw * 0.88), int(ph * 0.92), (255, 120, 60), (60, 30, 160))
    m = Image.new("L", scr.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, scr.size[0], scr.size[1]], radius=pw * 0.1, fill=255)
    phone.paste(scr, (int(pw * 0.06), int(ph * 0.04)), m)
    shaded_ellipse(phone, [pw * 0.25, ph * 0.3, pw * 0.75, ph * 0.3 + pw * 0.5], (255, 220, 140), dark=0.6)
    pd.rounded_rectangle([pw * 0.38, ph * 0.055, pw * 0.62, ph * 0.08], radius=pw * 0.02, fill=(0, 0, 0, 255))
    phone = phone.rotate(-14, resample=Image.BICUBIC, expand=True)
    comp(img, phone, (int(cx - phone.size[0] / 2), int(cy - phone.size[1] / 2)))
    if fmt == "q":
        text(img, (w * 0.5, h * 0.88), "LUMEN X", SANS_B, w * 0.7, h * 0.06, (240, 240, 245, 255), "mm")
        text(img, (w * 0.5, h * 0.94), "See the night.", LIB, w * 0.6, h * 0.03, (170, 170, 180, 255), "mm")
    else:
        text(img, (w * 0.06, h * 0.42), "LUMEN X", SANS_B, w * 0.42, h * 0.3, (245, 245, 250, 255), "lm")
        text(img, (w * 0.065, h * 0.68), "See the night.", LIB, w * 0.3, h * 0.12, (170, 170, 185, 255), "lm")


def ad_lawyer(img, w, h, fmt, rnd):
    # Personal-injury lawyer: yellow and black, a man in a suit, a huge 555 number.
    img.paste(gradient(w, h, (255, 214, 0), (250, 190, 0)))
    d = ImageDraw.Draw(img, "RGBA")
    band = h * (0.3 if fmt != "q" else 0.18)
    d.rectangle([0, h - band, w, h], fill=(16, 16, 18, 255))
    # The lawyer: suit, white shirt, red tie, a confident head.
    if fmt == "q":
        cx, top, s = w * 0.5, h * 0.32, h * 0.5
    else:
        cx, top, s = w * (0.84 if fmt == "b" else 0.8), h * 0.06, h * 0.95
    d.polygon([(cx - s * 0.36, top + s * 0.95), (cx - s * 0.3, top + s * 0.48), (cx, top + s * 0.4), (cx + s * 0.3, top + s * 0.48), (cx + s * 0.36, top + s * 0.95)], fill=(30, 34, 48, 255))
    d.polygon([(cx - s * 0.07, top + s * 0.42), (cx + s * 0.07, top + s * 0.42), (cx, top + s * 0.7)], fill=(250, 250, 250, 255))
    d.polygon([(cx - s * 0.025, top + s * 0.45), (cx + s * 0.025, top + s * 0.45), (cx + s * 0.035, top + s * 0.66), (cx, top + s * 0.7), (cx - s * 0.035, top + s * 0.66)], fill=(190, 20, 30, 255))
    shaded_ellipse(img, [cx - s * 0.12, top + s * 0.05, cx + s * 0.12, top + s * 0.38], (205, 150, 115), dark=0.55)
    d = ImageDraw.Draw(img, "RGBA")
    d.chord([cx - s * 0.125, top + s * 0.03, cx + s * 0.125, top + s * 0.24], 180, 360, fill=(40, 30, 25, 255))
    if fmt == "q":
        text(img, (w * 0.5, h * 0.09), "HURT?", SANS_B, w * 0.8, h * 0.1, (16, 16, 18, 255), "mm")
        text(img, (w * 0.5, h * 0.2), "RAMIREZ & KOLB", SANS_C, w * 0.9, h * 0.05, (16, 16, 18, 255), "mm")
        text(img, (w * 0.5, h - band * 0.5), "555-0144", SANS_B, w * 0.85, band * 0.6, (255, 214, 0, 255), "mm")
    else:
        text(img, (w * 0.04, h * 0.2), "HURT IN A CRASH?", SANS_B, w * 0.6, h * 0.2, (16, 16, 18, 255), "lm")
        text(img, (w * 0.04, h * 0.45), "RAMIREZ & KOLB", SANS_C, w * 0.55, h * 0.2, (16, 16, 18, 255), "lm")
        text(img, (w * 0.045, h * 0.6), "WE FIGHT. YOU HEAL.  NO FEE UNLESS WE WIN.", LIB_B, w * 0.6, h * 0.07, (60, 50, 10, 255), "lm")
        text(img, (w * 0.04, h - band * 0.5), "1-800-555-0144", SANS_B, w * 0.62, band * 0.72, (255, 214, 0, 255), "lm")


def ad_zapwolf(img, w, h, fmt, rnd):
    # Energy drink: ZAPWOLF. Black, acid green claw slashes, a tall can.
    img.paste(gradient(w, h, (10, 14, 10), (0, 0, 0)))
    d = ImageDraw.Draw(img, "RGBA")
    r = random.Random(rnd.random())
    for k in range(3):
        x = w * (0.35 + k * 0.08) if fmt != "q" else w * (0.2 + k * 0.25)
        pts = [(x, h * 0.02), (x + w * 0.03, h * 0.02), (x - w * 0.05 + h * 0.2, h * 0.98), (x - w * 0.07 + h * 0.2, h * 0.98)]
        if fmt == "q":
            pts = [(x, 0), (x + w * 0.06, 0), (x + w * 0.02 - h * 0.05, h * 0.55), (x - h * 0.05, h * 0.55)]
        d.polygon(pts, fill=(120, 255, 40, 70))
    def label(body):
        bw, bh = body.size
        bd = ImageDraw.Draw(body, "RGBA")
        for k in range(3):
            y = bh * (0.3 + k * 0.05)
            bd.polygon([(0, y), (bw, y - bh * 0.08), (bw, y - bh * 0.06), (0, y + bh * 0.02)], fill=(140, 255, 50, 255))
        text(body, (bw * 0.5, bh * 0.62), "ZAP", SANS_B, bw * 0.9, bh * 0.14, (140, 255, 50, 255), "mm")
    if fmt == "q":
        cw, ch = w * 0.36, h * 0.52
        cylinder(img, [w * 0.32, h * 0.34, w * 0.32 + cw, h * 0.34 + ch], (25, 25, 28), label, cap=(170, 175, 170))
        text(img, (w * 0.5, h * 0.2), "ZAPWOLF", SANS_B, w * 0.9, h * 0.1, (140, 255, 50, 255), "mm", shadow=(0, 0, (80, 255, 0, 180), 12))
        text(img, (w * 0.5, h * 0.93), "UNLEASH THE NIGHT", SANS_C, w * 0.8, h * 0.035, (220, 255, 200, 255), "mm")
    else:
        ch = h * 0.9
        cw = ch * 0.36
        x = w * 0.83 - cw * 0.5
        cylinder(img, [x, h * 0.06, x + cw, h * 0.06 + ch], (25, 25, 28), label, cap=(170, 175, 170))
        text(img, (w * 0.05, h * 0.4), "ZAPWOLF", SANS_B, w * 0.55, h * 0.42, (140, 255, 50, 255), "lm", shadow=(0, 0, (80, 255, 0, 200), 14))
        text(img, (w * 0.055, h * 0.78), "UNLEASH THE NIGHT.  ZERO SUGAR.", SANS_C, w * 0.5, h * 0.1, (220, 255, 200, 255), "lm")


def ad_sand(img, w, h, fmt, rnd):
    # Streaming show: SAND & SMOKE, season 2 on HALCYON+. Dusty sunset desert, two riders.
    img.paste(gradient(w, h, (60, 40, 70), (240, 130, 60)))
    d = ImageDraw.Draw(img, "RGBA")
    sun_y = h * (0.62 if fmt != "q" else 0.55)
    sx = w * (0.7 if fmt != "q" else 0.5)
    glow(img, sx, sun_y, max(w, h) * 0.25, (255, 200, 120), 0.9)
    d = ImageDraw.Draw(img, "RGBA")
    d.ellipse([sx - h * 0.12, sun_y - h * 0.12, sx + h * 0.12, sun_y + h * 0.12], fill=(255, 225, 160, 255))
    # Mesas.
    r = random.Random(rnd.random())
    ground = h * (0.72 if fmt != "q" else 0.68)
    pts = [(0, h)]
    x = 0.0
    while x < w:
        y = ground - r.random() * h * 0.12
        pts += [(x, y), (x + w * 0.08, y)]
        x += w * (0.06 + r.random() * 0.12)
    pts += [(w, ground), (w, h)]
    d.polygon(pts, fill=(60, 30, 30, 255))
    d.rectangle([0, ground + h * 0.02, w, h], fill=(40, 20, 22, 255))
    for k, dx in enumerate([-0.05, 0.05]):
        fx = sx + w * dx * (1 if fmt != "q" else 2.5)
        figure(d, fx, ground + h * 0.03, h * (0.36 if fmt != "q" else 0.2), (20, 10, 12, 255))
    if fmt == "q":
        text(img, (w * 0.5, h * 0.14), "SAND & SMOKE", SERIF_B, w * 0.9, h * 0.08, (255, 240, 220, 255), "mm", shadow=(3, 4, (40, 10, 10, 200), 6))
        text(img, (w * 0.5, h * 0.84), "SEASON 2", SANS_B, w * 0.6, h * 0.05, (255, 220, 170, 255), "mm")
        text(img, (w * 0.5, h * 0.92), "HALCYON+  ·  NOW STREAMING", LIB_B, w * 0.85, h * 0.03, (255, 230, 210, 255), "mm")
    else:
        text(img, (w * 0.05, h * 0.3), "SAND & SMOKE", SERIF_B, w * 0.5, h * 0.3, (255, 240, 220, 255), "lm", shadow=(4, 5, (40, 10, 10, 200), 8))
        text(img, (w * 0.055, h * 0.56), "SEASON 2  ·  NOW STREAMING", SANS_C, w * 0.4, h * 0.1, (255, 220, 170, 255), "lm")
        text(img, (w * 0.055, h * 0.88), "HALCYON+", SANS_B, w * 0.18, h * 0.1, (255, 255, 255, 255), "lm")


def ad_suncrest(img, w, h, fmt, rnd):
    # Airline: SUNCREST AIR (the airport's sunset carrier: red-orange tail, yellow accent).
    img.paste(gradient(w, h, (40, 120, 210), (170, 210, 245)))
    d = ImageDraw.Draw(img, "RGBA")
    r = random.Random(rnd.random())
    for _ in range(9):
        cx, cy = r.random() * w, h * (0.55 + r.random() * 0.4)
        for k in range(6):
            rr = h * (0.06 + r.random() * 0.1)
            ox = (r.random() - 0.5) * rr * 3
            d.ellipse([cx + ox - rr, cy - rr * 0.7, cx + ox + rr, cy + rr * 0.7], fill=(255, 255, 255, 220))
    # The jet, from below-side: fuselage, swept wing, the red-orange tail with its disc.
    jw = w * (0.55 if fmt == "b" else 0.7) if fmt != "q" else w * 0.95
    jx = w * (0.62 if fmt != "q" else 0.5)
    jy = h * (0.4 if fmt != "q" else 0.4)
    jh = jw * 0.09
    jet = Image.new("RGBA", (int(jw * 1.1), int(jw * 0.5)), (0, 0, 0, 0))
    jd = ImageDraw.Draw(jet, "RGBA")
    oy = jw * 0.22
    jd.polygon([(jw * 0.45, oy), (jw * 0.62, oy + jw * 0.2), (jw * 0.55, oy + jw * 0.21), (jw * 0.36, oy + jh * 0.6)], fill=(200, 205, 212, 255))
    jd.rounded_rectangle([0, oy - jh * 0.5, jw, oy + jh * 0.5], radius=jh * 0.5, fill=(245, 245, 248, 255))
    jd.rectangle([jw * 0.08, oy + jh * 0.05, jw * 0.92, oy + jh * 0.2], fill=(240, 160, 20, 255))
    jd.polygon([(jw * 0.82, oy - jh * 0.3), (jw * 0.9, oy - jh * 0.3), (jw * 1.02, oy - jw * 0.16), (jw * 0.95, oy - jw * 0.16)], fill=(200, 40, 10, 255))
    jd.ellipse([jw * 0.9, oy - jw * 0.12, jw * 0.96, oy - jw * 0.07], fill=(255, 200, 30, 255))
    for k in range(18):
        x = jw * (0.12 + k * 0.038)
        jd.ellipse([x, oy - jh * 0.22, x + jh * 0.14, oy - jh * 0.05], fill=(40, 50, 70, 255))
    jet = jet.rotate(6, resample=Image.BICUBIC, expand=True)
    comp(img, jet, (int(jx - jet.size[0] / 2), int(jy - jet.size[1] / 2)))
    navy = (16, 30, 70, 255)
    if fmt == "q":
        text(img, (w * 0.5, h * 0.12), "SUNCREST AIR", SANS_B, w * 0.9, h * 0.06, navy, "mm")
        text(img, (w * 0.5, h * 0.7), "HONOLULU", SANS_B, w * 0.8, h * 0.07, navy, "mm", shadow=(0, 0, (255, 255, 255, 230), 6))
        text(img, (w * 0.5, h * 0.79), "from $129", LIB_B, w * 0.6, h * 0.05, (200, 40, 10, 255), "mm", shadow=(0, 0, (255, 255, 255, 230), 5))
    else:
        text(img, (w * 0.04, h * 0.2), "SUNCREST AIR", SANS_B, w * 0.32, h * 0.13, navy, "lm")
        text(img, (w * 0.04, h * 0.52), "Honolulu", LIB_SERIF_I, w * 0.3, h * 0.28, navy, "lm", shadow=(0, 0, (255, 255, 255, 220), 8))
        text(img, (w * 0.045, h * 0.8), "NONSTOP FROM $129", SANS_C, w * 0.3, h * 0.1, (200, 40, 10, 255), "lm", shadow=(0, 0, (255, 255, 255, 220), 6))


def ad_comet(img, w, h, fmt, rnd):
    # Burger stand: STARDUST DRIVE-IN. Teal and cream, a big burger, a starburst price.
    img.paste(gradient(w, h, (20, 150, 150), (10, 100, 110)))
    d = ImageDraw.Draw(img, "RGBA")
    for k in range(0, w + h, int(h * 0.12)):
        d.line([(k, 0), (k - h, h)], fill=(255, 255, 255, 18), width=int(h * 0.04))
    bs = h * 0.78 if fmt != "q" else w * 0.75
    bx = w * (0.74 if fmt == "b" else 0.72) if fmt != "q" else w * 0.5
    by = h * 0.55 if fmt != "q" else h * 0.52
    # Bottom bun, patty, cheese, lettuce, top bun.
    shaded_ellipse(img, [bx - bs * 0.5, by + bs * 0.08, bx + bs * 0.5, by + bs * 0.32], (210, 140, 60), dark=0.5)
    shaded_ellipse(img, [bx - bs * 0.52, by - bs * 0.02, bx + bs * 0.52, by + bs * 0.18], (90, 45, 25), dark=0.4)
    d = ImageDraw.Draw(img, "RGBA")
    d.polygon([(bx - bs * 0.5, by), (bx + bs * 0.5, by), (bx + bs * 0.42, by + bs * 0.1), (bx + bs * 0.2, by + bs * 0.03), (bx - bs * 0.1, by + bs * 0.12), (bx - bs * 0.45, by + bs * 0.04)], fill=(255, 190, 20, 255))
    for k in range(9):
        x = bx - bs * 0.52 + k * bs * 0.13
        d.ellipse([x, by - bs * 0.06, x + bs * 0.16, by + bs * 0.04], fill=(80, 170, 40, 255))
    shaded_ellipse(img, [bx - bs * 0.5, by - bs * 0.42, bx + bs * 0.5, by + bs * 0.02], (225, 150, 60), dark=0.45)
    d = ImageDraw.Draw(img, "RGBA")
    r = random.Random(rnd.random())
    for _ in range(28):
        a = r.random() * math.pi
        rr = r.random() ** 0.5 * 0.4
        x = bx + math.cos(a) * bs * rr
        y = by - bs * 0.2 - math.sin(a) * bs * rr * 0.45
        d.ellipse([x, y, x + bs * 0.018, y + bs * 0.01], fill=(255, 240, 200, 255))
    cream = (255, 245, 220, 255)
    if fmt == "q":
        text(img, (w * 0.5, h * 0.1), "STARDUST", SANS_B, w * 0.9, h * 0.08, cream, "mm")
        text(img, (w * 0.5, h * 0.18), "DRIVE-IN", LIB_SERIF_I, w * 0.6, h * 0.05, (255, 200, 60, 255), "mm")
        star(d, w * 0.75, h * 0.82, w * 0.17, (230, 40, 40, 255), 12, 0.78)
        text(img, (w * 0.75, h * 0.82), "$4.99", SANS_B, w * 0.22, h * 0.05, cream, "mm")
    else:
        text(img, (w * 0.05, h * 0.3), "STARDUST", SANS_B, w * 0.42, h * 0.3, cream, "lm", shadow=(4, 5, (0, 40, 40, 170), 6))
        text(img, (w * 0.055, h * 0.58), "DRIVE-IN BURGERS  ·  OPEN LATE", SANS_C, w * 0.42, h * 0.1, (255, 210, 90, 255), "lm")
        if fmt == "b":
            star(d, w * 0.53, h * 0.72, h * 0.25, (230, 40, 40, 255), 12, 0.78)
            text(img, (w * 0.53, h * 0.72), "$4.99", SANS_B, h * 0.32, h * 0.13, cream, "mm")
        text(img, (w * 0.055, h * 0.84), "EXIT NOW", SANS_B, w * 0.2, h * 0.12, cream, "lm")


def ad_lunara(img, w, h, fmt, rnd):
    # Tequila: CASA LUNARA. Night blue, a moon, an agave silhouette, a bottle.
    img.paste(gradient(w, h, (10, 18, 50), (40, 50, 110)))
    d = ImageDraw.Draw(img, "RGBA")
    mx, my = (w * 0.2, h * 0.32) if fmt != "q" else (w * 0.72, h * 0.16)
    glow(img, mx, my, h * 0.4, (190, 200, 255), 0.6)
    d = ImageDraw.Draw(img, "RGBA")
    d.ellipse([mx - h * 0.16, my - h * 0.16, mx + h * 0.16, my + h * 0.16] if fmt != "q" else [mx - w * 0.14, my - w * 0.14, mx + w * 0.14, my + w * 0.14], fill=(240, 240, 220, 255))
    # Agave field.
    r = random.Random(rnd.random())
    base = h * 0.98
    for k in range(int(w / (h * 0.25)) + 3):
        cx = k * h * 0.25 + r.random() * h * 0.1
        for a in range(-60, 61, 20):
            rad = math.radians(a - 90)
            ll = h * (0.12 + r.random() * 0.08)
            d.polygon([(cx - h * 0.012, base), (cx + h * 0.012, base), (cx + math.cos(rad) * ll, base + math.sin(rad) * ll)], fill=(10, 30, 35, 255))
    # The bottle: tall, frosted, a gold label.
    bw = h * 0.2 if fmt != "q" else w * 0.28
    bh = bw * 3.4
    bx = w * (0.8 if fmt != "q" else 0.5) - bw * 0.5
    by = h * 0.92 - bh
    if fmt == "q":
        by = h * 0.84 - bh
    def label(body):
        lw, lh = body.size
        ld = ImageDraw.Draw(body, "RGBA")
        ld.rectangle([lw * 0.1, lh * 0.5, lw * 0.9, lh * 0.8], fill=(210, 170, 70, 255))
        text(body, (lw * 0.5, lh * 0.65), "LUNARA", SERIF_B, lw * 0.75, lh * 0.06, (40, 25, 10, 255), "mm")
    neck = bw * 0.32
    d.rectangle([bx + (bw - neck) / 2, by - bh * 0.18, bx + (bw + neck) / 2, by + bh * 0.05], fill=(180, 200, 210, 255))
    d.rectangle([bx + (bw - neck) / 2 - 2, by - bh * 0.24, bx + (bw + neck) / 2 + 2, by - bh * 0.17], fill=(60, 40, 20, 255))
    cylinder(img, [bx, by, bx + bw, by + bh], (170, 195, 210), label, cap=(170, 195, 210))
    gold = (225, 190, 100, 255)
    if fmt == "q":
        text(img, (w * 0.5, h * 0.36), "CASA LUNARA", SERIF_B, w * 0.85, h * 0.06, gold, "mm")
        text(img, (w * 0.5, h * 0.92), "Drink responsibly.", LIB, w * 0.5, h * 0.025, (180, 180, 200, 255), "mm")
    else:
        text(img, (w * 0.32 if fmt == "b" else w * 0.06, h * 0.35), "CASA LUNARA", SERIF_B, w * 0.4, h * 0.22, gold, "lm")
        text(img, (w * 0.322 if fmt == "b" else w * 0.062, h * 0.6), "Born under the moon.", LIB_SERIF_I, w * 0.34, h * 0.12, (220, 220, 240, 255), "lm")


def ad_corvo(img, w, h, fmt, rnd):
    # Electric car: CORVO ARIA EV. Pale studio grey, a low silver car, range figure.
    img.paste(gradient(w, h, (226, 228, 232), (180, 184, 190)))
    d = ImageDraw.Draw(img, "RGBA")
    cw = w * (0.5 if fmt == "b" else 0.62) if fmt != "q" else w * 0.92
    cx = w * (0.7 if fmt != "q" else 0.5)
    cy = h * (0.68 if fmt != "q" else 0.6)
    ch = cw * 0.28
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([cx - cw * 0.55, cy + ch * 0.35, cx + cw * 0.55, cy + ch * 0.65], fill=(0, 0, 0, 140))
    comp(img, sh.filter(ImageFilter.GaussianBlur(ch * 0.15)))
    d = ImageDraw.Draw(img, "RGBA")
    prof = [(-0.5, 0.28), (-0.51, 0.05), (-0.46, -0.08), (-0.3, -0.2), (-0.14, -0.55), (0.06, -0.62), (0.2, -0.56),
            (0.36, -0.26), (0.48, -0.16), (0.52, 0.02), (0.5, 0.28)]
    body = [(cx + cw * x, cy + ch * y) for x, y in smooth(prof, 8)]
    d.polygon(body, fill=(150, 28, 40, 255))
    # A lit shoulder line and the glasshouse.
    glass = [(cx + cw * x, cy + ch * y) for x, y in smooth([(-0.24, -0.22), (-0.12, -0.5), (0.05, -0.56), (0.18, -0.5), (0.31, -0.25)], 8)]
    d.polygon(glass, fill=(26, 30, 40, 255))
    d.line([(cx - cw * 0.46, cy - ch * 0.06), (cx + cw * 0.47, cy - ch * 0.12)], fill=(235, 150, 160, 255), width=max(2, int(ch * 0.035)))
    d.line([(cx - cw * 0.5, cy + ch * 0.22), (cx + cw * 0.5, cy + ch * 0.2)], fill=(70, 12, 20, 255), width=max(2, int(ch * 0.06)))
    d.ellipse([cx + cw * 0.44, cy - ch * 0.1, cx + cw * 0.51, cy - ch * 0.02], fill=(255, 250, 230, 255))
    for wx in (-0.3, 0.3):
        x = cx + cw * wx
        d.ellipse([x - ch * 0.3, cy + ch * 0.02, x + ch * 0.3, cy + ch * 0.62], fill=(20, 20, 22, 255))
        d.ellipse([x - ch * 0.18, cy + ch * 0.14, x + ch * 0.18, cy + ch * 0.5], fill=(160, 165, 170, 255))
    dark = (30, 32, 38, 255)
    if fmt == "q":
        text(img, (w * 0.5, h * 0.14), "CORVO ARIA", SANS_B, w * 0.85, h * 0.07, dark, "mm")
        text(img, (w * 0.5, h * 0.82), "380 MILES. ZERO GAS.", SANS_C, w * 0.85, h * 0.04, dark, "mm")
    else:
        text(img, (w * 0.05, h * 0.3), "CORVO ARIA", SANS_B, w * 0.36, h * 0.24, dark, "lm")
        text(img, (w * 0.052, h * 0.56), "380 MILES. ZERO GAS.", SANS_C, w * 0.34, h * 0.12, (90, 30, 40, 255), "lm")
        text(img, (w * 0.052, h * 0.8), "corvomotors · test drive today", LIB, w * 0.3, h * 0.08, (80, 82, 90, 255), "lm")


def ad_radio(img, w, h, fmt, rnd):
    # Radio: RANDO FM 104.1 "THE DRIFT". Magenta to violet, a sound wave, a DJ duo's names.
    img.paste(gradient(w, h, (240, 40, 140), (70, 20, 160), horizontal=True))
    d = ImageDraw.Draw(img, "RGBA")
    mid = h * 0.5
    for x in range(0, w, SS * 3):
        a = (math.sin(x * 0.02 / SS) * 0.5 + math.sin(x * 0.0071 / SS + 1.0) * 0.5) * h * 0.18
        a *= 0.5 + 0.5 * math.sin(x * 0.0013 / SS) ** 2
        d.line([(x, mid - abs(a)), (x, mid + abs(a))], fill=(255, 255, 255, 60), width=SS * 2)
    if fmt == "q":
        text(img, (w * 0.5, h * 0.3), "104.1", SANS_B, w * 0.9, h * 0.16, (255, 255, 255, 255), "mm", shadow=(0, 0, (255, 120, 220, 220), 14))
        text(img, (w * 0.5, h * 0.45), "THE DRIFT", SANS_C, w * 0.8, h * 0.06, (255, 230, 250, 255), "mm")
        text(img, (w * 0.5, h * 0.88), "MORNINGS WITH DEX & PAZ", LIB_B, w * 0.85, h * 0.03, (255, 230, 250, 255), "mm")
    else:
        text(img, (w * 0.05, h * 0.42), "104.1", SANS_B, w * 0.36, h * 0.6, (255, 255, 255, 255), "lm", shadow=(0, 0, (255, 120, 220, 230), 16))
        text(img, (w * 0.95, h * 0.36), "THE DRIFT", SANS_B, w * 0.42, h * 0.28, (255, 255, 255, 255), "rm")
        text(img, (w * 0.95, h * 0.66), "MORNINGS WITH DEX & PAZ", SANS_C, w * 0.42, h * 0.1, (255, 225, 245, 255), "rm")


def ad_hollow(img, w, h, fmt, rnd):
    # Film 2: THE HOLLOW HOUSE (horror). Near-black, a lone lit window, scratched title.
    img.paste(gradient(w, h, (30, 32, 36), (6, 6, 8)))
    d = ImageDraw.Draw(img, "RGBA")
    hx = w * (0.72 if fmt != "q" else 0.5)
    hy = h * (0.9 if fmt != "q" else 0.75)
    s = h * (0.75 if fmt != "q" else 0.42)
    d.polygon([(hx - s * 0.5, hy), (hx - s * 0.5, hy - s * 0.5), (hx, hy - s * 0.92), (hx + s * 0.5, hy - s * 0.5), (hx + s * 0.5, hy)], fill=(12, 12, 14, 255))
    glow(img, hx + s * 0.15, hy - s * 0.32, s * 0.25, (255, 150, 60), 0.6)
    d = ImageDraw.Draw(img, "RGBA")
    d.rectangle([hx + s * 0.08, hy - s * 0.42, hx + s * 0.22, hy - s * 0.22], fill=(255, 190, 90, 255))
    figure(d, hx + s * 0.15, hy - s * 0.22, s * 0.16, (40, 20, 10, 255))
    r = random.Random(rnd.random())
    for _ in range(14):
        x = r.random() * w
        d.line([(x, 0), (x + (r.random() - 0.5) * w * 0.05, h)], fill=(255, 255, 255, 10), width=SS)
    red = (190, 20, 20, 255)
    if fmt == "q":
        text(img, (w * 0.5, h * 0.14), "THE HOLLOW", LIB_SERIF_B, w * 0.85, h * 0.07, (230, 225, 220, 255), "mm")
        text(img, (w * 0.5, h * 0.23), "HOUSE", LIB_SERIF_B, w * 0.9, h * 0.1, red, "mm")
        text(img, (w * 0.5, h * 0.92), "OCTOBER 30", SANS_C, w * 0.6, h * 0.035, (200, 195, 190, 255), "mm")
    else:
        text(img, (w * 0.05, h * 0.3), "THE HOLLOW HOUSE", LIB_SERIF_B, w * 0.52, h * 0.22, (230, 225, 220, 255), "lm")
        text(img, (w * 0.052, h * 0.56), "SOMEONE NEVER LEFT.", SANS_C, w * 0.34, h * 0.1, red, "lm")
        text(img, (w * 0.052, h * 0.82), "ONLY IN THEATERS OCTOBER 30", SANS_C, w * 0.36, h * 0.07, (190, 185, 180, 255), "lm")


def ad_stride(img, w, h, fmt, rnd):
    # Sneakers: STRIDE CO. White, one bold colour block, a sneaker in profile.
    img.paste(gradient(w, h, (248, 246, 240), (232, 228, 220)))
    d = ImageDraw.Draw(img, "RGBA")
    d.polygon([(w * 0.48, 0), (w, 0), (w, h), (w * 0.38, h)] if fmt != "q" else [(0, h * 0.45), (w, h * 0.3), (w, h * 0.75), (0, h * 0.85)], fill=(20, 90, 220, 255))
    sw = w * (0.4 if fmt == "b" else 0.5) if fmt != "q" else w * 0.9
    sx = w * (0.7 if fmt != "q" else 0.5)
    sy = h * (0.62 if fmt != "q" else 0.6)
    sh = sw * 0.36
    d.polygon([(sx - sw * 0.5, sy + sh * 0.3), (sx - sw * 0.48, sy - sh * 0.1), (sx - sw * 0.2, sy - sh * 0.4), (sx - sw * 0.02, sy - sh * 0.15),
               (sx + sw * 0.3, sy - sh * 0.05), (sx + sw * 0.48, sy + sh * 0.12), (sx + sw * 0.5, sy + sh * 0.3)], fill=(250, 250, 252, 255))
    d.rectangle([sx - sw * 0.5, sy + sh * 0.22, sx + sw * 0.5, sy + sh * 0.42], fill=(235, 70, 30, 255))
    d.polygon([(sx - sw * 0.32, sy + sh * 0.12), (sx + sw * 0.05, sy - sh * 0.1), (sx + sw * 0.2, sy + sh * 0.08)], fill=(20, 22, 30, 255))
    for k in range(5):
        x = sx - sw * 0.12 + k * sw * 0.045
        d.line([(x, sy - sh * 0.22 + k * sh * 0.03), (x + sw * 0.03, sy - sh * 0.12 + k * sh * 0.03)], fill=(30, 30, 35, 255), width=max(2, int(sh * 0.03)))
    ink = (20, 22, 30, 255)
    if fmt == "q":
        text(img, (w * 0.5, h * 0.14), "STRIDE CO.", SANS_B, w * 0.85, h * 0.07, ink, "mm")
        text(img, (w * 0.5, h * 0.92), "RUN THE CITY.", SANS_C, w * 0.7, h * 0.04, ink, "mm")
    else:
        text(img, (w * 0.05, h * 0.36), "RUN THE", SANS_B, w * 0.32, h * 0.26, ink, "lm")
        text(img, (w * 0.05, h * 0.64), "CITY.", SANS_B, w * 0.32, h * 0.3, (20, 90, 220, 255), "lm")
        text(img, (w * 0.05, h * 0.88), "STRIDE CO.", SANS_C, w * 0.2, h * 0.08, ink, "lm")


# The order IS the ad index everywhere (Billboards.AD_*, the table). Bulletins 0-11 and posters
# 0-11 are these twelve; portraits 0-5 are PORTRAITS.
CAMPAIGNS = [ad_orbit, ad_fizzly, ad_lumen, ad_lawyer, ad_zapwolf, ad_sand, ad_suncrest, ad_comet, ad_lunara, ad_corvo, ad_radio, ad_hollow]
PORTRAITS = [ad_fizzly, ad_lawyer, ad_sand, ad_zapwolf, ad_suncrest, ad_stride]
NAMES = ["the_last_orbit", "fizzly", "lumen_x", "ramirez_kolb", "zapwolf", "sand_and_smoke", "suncrest_air", "stardust_drive_in", "casa_lunara", "corvo_aria", "drift_104", "hollow_house"]
PORTRAIT_NAMES = ["fizzly", "ramirez_kolb", "sand_and_smoke", "zapwolf", "suncrest_air", "stride_co"]


def render_cell(fn, size, fmt, idx):
    w, h = size[0] * SS, size[1] * SS
    img = Image.new("RGB", (w, h), (0, 0, 0))
    rnd = random.Random(SEED * 31 + idx * 7 + {"b": 0, "p": 1, "q": 2}[fmt])
    fn(img, w, h, fmt, rnd)
    img = vignette(img.convert("RGBA"), 0.18)
    img = grain(img, rnd, 3.0)
    return img.convert("RGB").resize(size, Image.LANCZOS)


def srgb_to_linear(c):
    c = c / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def main():
    atlas = Image.new("RGB", (W, H), (20, 20, 20))
    means = {"b": [], "p": [], "q": []}
    for i, fn in enumerate(CAMPAIGNS):
        cell = render_cell(fn, BUL, "b", i)
        atlas.paste(cell, ((i % 2) * BUL[0], BUL_Y + (i // 2) * BUL[1]))
        means["b"].append(srgb_to_linear(np.asarray(cell, float)).reshape(-1, 3).mean(0))
        cell = render_cell(fn, POS, "p", i)
        atlas.paste(cell, ((i % 4) * POS[0], POS_Y + (i // 4) * POS[1]))
        means["p"].append(srgb_to_linear(np.asarray(cell, float)).reshape(-1, 3).mean(0))
        print("ad", i, NAMES[i])
    for i, fn in enumerate(PORTRAITS):
        cell = render_cell(fn, POR, "q", 100 + i)
        atlas.paste(cell, (i * POR[0], POR_Y))
        means["q"].append(srgb_to_linear(np.asarray(cell, float)).reshape(-1, 3).mean(0))
        print("portrait", i, PORTRAIT_NAMES[i])
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    atlas.save(OUT, quality=90, optimize=True)
    print("wrote", OUT, os.path.getsize(OUT) // 1024, "KB")
    with open(TABLE, "w") as f:
        f.write("class_name BillboardTable\n")
        f.write("## GENERATED by tools/make_billboard_art.py - do not edit. The LINEAR mean colour of every\n")
        f.write("## cell of assets/textures/billboards/billboard_ads.jpg, for the far boxes (Billboards.far_color()).\n\n")
        for key, label in (("b", "BULLETIN"), ("p", "POSTER"), ("q", "PORTRAIT")):
            rows = ", ".join("Color(%.4f, %.4f, %.4f)" % tuple(m) for m in means[key])
            f.write("const %s_MEAN: Array[Color] = [%s]\n" % (label, rows))
        f.write("const NAMES: Array[String] = [%s]\n" % ", ".join('"%s"' % n for n in NAMES))
        f.write("const PORTRAIT_NAMES: Array[String] = [%s]\n" % ", ".join('"%s"' % n for n in PORTRAIT_NAMES))
    print("wrote", TABLE)
    if "--preview" in sys.argv:
        os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
        prev = atlas.resize((W // 2, H // 2), Image.LANCZOS)
        prev.save(os.path.join(ROOT, "build", "billboard_preview.jpg"), quality=88)


if __name__ == "__main__":
    main()
