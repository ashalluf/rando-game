#!/usr/bin/env python3
"""Street-level wear atlases: spray-painted tags, wheat-paste posters and stickers.

Everything here is ORIGINAL and drawn by this script from a fixed seed: the tags are abstract
letterform scribbles (no real tag, crew, gang sign, number or symbol), the posters are invented
gigs, club nights, lost pets and hand bills with invented names or illegible text blocks, the
stickers invented little emblems and nonsense words. No brand, logo, artist or real place.

Writes two PNGs next to each other in assets/textures/street_wear/:

* street_wear_tags.png (2048 x 1024, LINEAR masks, 4 x 4 cells of 512 x 256):
  R = the paint's fill (a handstyle's whole line, a throw-up's inside), G = the outline under it
  (a throw-up's outline, which includes the inside: the shader paints G in the second colour and
  R over it), B = the shine (white highlights on a throw-up). Soft overspray and speckle are in
  the masks themselves. Cells 0-7 handstyles, 8-13 throw-ups, 14-15 blocky roller letters.
* street_wear_paper.png (2048 x 1024, sRGB colour + alpha): 8 x 2 posters of 256 x 384 in the top
  768 rows (the shader tears, fades and wrinkles them per instance), then 16 x 2 stickers of
  128 x 128 (die-cut, with their white border).

Both are drawn at twice the size and filtered down, and every cell keeps a transparent margin so
the mip chain never bleeds one cell into the next. scripts/world/street_wear.gd holds the same grid.

Fonts: DejaVu Sans / Serif (Bitstream Vera licence) and Liberation Sans / Serif (SIL OFL 1.1),
both from the system's font packages, rasterised into the texture only (no font file ships).

    python3 tools/make_street_wear.py            # writes both PNGs
    python3 tools/make_street_wear.py --preview  # also writes build/street_wear_preview.png

Then `godot --headless --path . --import` and `python3 tools/fix_texture_imports.py` on the two
new .import files (VRAM compression, mipmaps), and commit the PNGs and their .import files.
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.environ.get("OUT_DIR", os.path.join(HERE, "..", "assets", "textures", "street_wear"))
SEED = 20260925

FONT_DIRS = ["/usr/share/fonts/truetype/dejavu", "/usr/share/fonts/truetype/liberation"]


def font(name, size):
    for d in FONT_DIRS:
        p = os.path.join(d, name)
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


SANS_B = "DejaVuSans-Bold.ttf"
SERIF_B = "DejaVuSerif-Bold.ttf"
LIB_B = "LiberationSans-Bold.ttf"
LIB_SERIF_B = "LiberationSerif-Bold.ttf"
LIB = "LiberationSans-Regular.ttf"


# --- Tags --------------------------------------------------------------------------------------
# Pseudo-letter skeletons in a unit box (x right, y UP), each a list of strokes (point lists).
# They are shaped like hand-written letterforms without being any letter in particular.
GLYPHS = [
    [[(0.05, 0.0), (0.12, 1.0), (0.25, 0.5), (0.85, 0.62), (0.5, 0.3), (0.95, 0.0)]],
    [[(0.0, 0.05), (0.3, 1.0), (0.55, 0.1), (0.85, 1.0), (1.0, 0.25)]],
    [[(0.85, 0.85), (0.35, 1.0), (0.0, 0.5), (0.3, 0.0), (0.95, 0.2)]],
    [[(0.1, 1.0), (0.1, 0.1), (0.5, 0.0), (0.9, 0.45)]],
    [[(0.0, 0.4), (0.9, 0.62), (0.6, 1.0), (0.1, 0.72), (0.22, 0.08), (0.95, 0.02)]],
    [[(0.9, 0.9), (0.45, 1.0), (0.1, 0.78), (0.82, 0.3), (0.6, 0.0), (0.0, 0.12)]],
    [[(0.0, 0.0), (0.05, 0.8), (0.5, 1.0), (0.95, 0.8), (1.0, 0.0)]],
    [[(0.1, 1.0), (0.1, 0.0)], [(0.9, 1.0), (0.15, 0.45), (0.95, 0.0)]],
    [[(0.5, 1.0), (0.1, 0.62), (0.3, 0.0), (0.8, 0.2), (0.82, 0.9), (0.5, 1.0), (1.0, 0.0)]],
    [[(0.0, 1.0), (0.5, 0.0), (1.0, 1.0)], [(0.2, 0.45), (0.8, 0.5)]],
    [[(0.1, 0.0), (0.1, 1.0), (0.8, 0.85), (0.75, 0.52), (0.1, 0.5), (0.9, 0.0)]],
    [[(0.95, 1.0), (0.05, 1.0), (0.55, 0.5), (0.05, 0.0), (0.95, 0.0)]],
]
# Bubble-letter skeletons for throw-ups: fewer, rounder, fatter strokes.
BUBBLES = [
    [[(0.2, 0.0), (0.2, 1.0), (0.75, 0.8), (0.3, 0.5), (0.8, 0.25), (0.2, 0.0)]],
    [[(0.8, 0.85), (0.3, 1.0), (0.1, 0.5), (0.3, 0.0), (0.8, 0.15)]],
    [[(0.15, 0.0), (0.2, 1.0), (0.85, 0.0), (0.85, 1.0)]],
    [[(0.5, 0.0), (0.1, 0.5), (0.5, 1.0), (0.9, 0.5), (0.5, 0.0)]],
    [[(0.85, 0.9), (0.2, 0.75), (0.8, 0.3), (0.15, 0.05)]],
    [[(0.1, 1.0), (0.15, 0.1), (0.85, 0.1), (0.9, 1.0)]],
    [[(0.1, 0.0), (0.5, 1.0), (0.9, 0.0)], [(0.3, 0.4), (0.7, 0.4)]],
]


def catmull(points, per=10):
    if len(points) < 3:
        out = []
        for i in range(len(points) - 1):
            for k in range(per):
                t = k / per
                out.append((points[i][0] + (points[i + 1][0] - points[i][0]) * t,
                            points[i][1] + (points[i + 1][1] - points[i][1]) * t))
        out.append(points[-1])
        return out
    p = [points[0]] + list(points) + [points[-1]]
    out = []
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
        for k in range(per):
            t = k / per
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2
                                    + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3) for j in range(2)))
    out.append(p[-2])
    return out


def draw_poly(draw, pts, width, fill=255):
    for i in range(len(pts) - 1):
        draw.line([pts[i], pts[i + 1]], fill=fill, width=int(max(1, width)))
    r = width * 0.5
    for q in pts:
        draw.ellipse([q[0] - r, q[1] - r, q[0] + r, q[1] + r], fill=fill)


def spray(mask, rng, blur=5.0, halo=0.28, speckle=0.5):
    """A hard mask to spray paint: soft overspray halo round it and loose dots in the halo."""
    m = mask.astype(np.float32) / 255.0
    soft = ndimage.gaussian_filter(m, blur)
    wide = ndimage.gaussian_filter(m, blur * 3.0)
    dots = (rng.random(m.shape) < wide * speckle * 0.35).astype(np.float32) * 0.7
    out = np.maximum(m, np.maximum(soft * 0.9, wide * halo))
    out = np.maximum(out, dots * (wide > 0.02))
    return np.clip(out, 0.0, 1.0)


def drips(draw, pts, rng, width, count, cell_h, lo=0.15, hi=0.55):
    # Drips run from the lowest places of the line.
    cand = sorted(pts, key=lambda q: -q[1])[: max(8, len(pts) // 5)]
    for _ in range(count):
        x, y = cand[rng.randrange(len(cand))]
        length = cell_h * rng.uniform(lo, hi) * rng.uniform(0.3, 1.0)
        w = max(2.0, width * rng.uniform(0.25, 0.5))
        end = min(cell_h * 0.97, y + length)
        draw.line([(x, y), (x + rng.uniform(-2, 2), end)], fill=255, width=int(w))
        r = w * 0.8
        draw.ellipse([x - r, end - r, x + r, end + r * 1.3], fill=255)


def letter_run(glyphs, rng, w, h, count, lh, slant, x0, base, spacing):
    strokes = []
    x = x0
    for i in range(count):
        g = glyphs[rng.randrange(len(glyphs))]
        gw = lh * rng.uniform(0.5, 0.8)
        gh = lh * rng.uniform(0.85, 1.15)
        mirror = rng.random() < 0.3
        dy = rng.uniform(-0.08, 0.08) * lh
        for s in g:
            pts = []
            for (gx, gy) in s:
                gx = 1.0 - gx if mirror else gx
                px = x + gx * gw + slant * gy * gh + rng.uniform(-0.03, 0.03) * lh
                py = base - gy * gh + dy + rng.uniform(-0.03, 0.03) * lh
                pts.append((px, py))
            strokes.append(pts)
        x += gw * spacing
    return strokes, x


def handstyle(rng, W, H):
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)
    count = rng.randint(3, 6)
    lh = H * rng.uniform(0.42, 0.58)
    slant = rng.uniform(0.15, 0.5)
    width = H * rng.uniform(0.028, 0.06)
    base = H * rng.uniform(0.66, 0.74)
    spacing = rng.uniform(0.8, 1.05)
    x0 = W * 0.07
    strokes, x_end = letter_run(GLYPHS, rng, W, H, count, lh, slant, x0, base, spacing)
    # Fit to the cell.
    xs = [p[0] for s in strokes for p in s]
    ys = [p[1] for s in strokes for p in s]
    sx = (W * 0.86) / max(1.0, max(xs) - min(xs))
    sy = (H * 0.7) / max(1.0, max(ys) - min(ys))
    k = min(sx, sy, 1.3)
    cx, cy = (max(xs) + min(xs)) * 0.5, (max(ys) + min(ys)) * 0.5
    strokes = [[((p[0] - cx) * k + W * 0.5, (p[1] - cy) * k + H * 0.46) for p in s] for s in strokes]
    connected = rng.random() < 0.6
    all_pts = []
    if connected:
        chain = [p for s in strokes for p in s]
        pts = catmull(chain, 8)
        draw_poly(d, pts, width)
        all_pts += pts
    else:
        for s in strokes:
            pts = catmull(s, 8)
            draw_poly(d, pts, width)
            all_pts += pts
    # The flourish: an underline swooping back under the word, or a pair of dots, or both.
    if rng.random() < 0.7:
        x1 = max(p[0] for p in all_pts)
        x0 = min(p[0] for p in all_pts)
        y1 = max(p[1] for p in all_pts) + H * 0.04
        sw = [(x1 - W * 0.02, y1 - H * 0.15), (x1, y1), (x0 + (x1 - x0) * 0.5, y1 + H * 0.05), (x0 - W * 0.02, y1 + H * 0.01)]
        pts = catmull(sw, 12)
        draw_poly(d, pts, width * 0.9)
        all_pts += pts
    if rng.random() < 0.4:
        top = min(p[1] for p in all_pts)
        xx = rng.uniform(W * 0.3, W * 0.7)
        for j in range(2):
            r = width * 0.9
            d.ellipse([xx + j * width * 2.5 - r, top - H * 0.06 - r, xx + j * width * 2.5 + r, top - H * 0.06 + r], fill=255)
    if rng.random() < 0.65:
        drips(d, all_pts, rng, width, rng.randint(2, 6), H)
    return spray(np.asarray(img), np.random.default_rng(rng.randrange(1 << 30)), blur=width * 0.2, halo=0.12, speckle=0.35)


def throwup(rng, W, H):
    count = rng.randint(2, 4)
    lh = H * rng.uniform(0.5, 0.62)
    fat = lh * rng.uniform(0.3, 0.4)
    slant = rng.uniform(0.0, 0.25)
    strokes_per = []
    x = 0.0
    for i in range(count):
        g = BUBBLES[rng.randrange(len(BUBBLES))]
        gw = lh * rng.uniform(0.55, 0.8)
        gh = lh * rng.uniform(0.9, 1.1)
        dy = rng.uniform(-0.1, 0.1) * lh
        rot = rng.uniform(-0.15, 0.15)
        letter = []
        for s in g:
            pts = []
            for (gx, gy) in s:
                ux, uy = gx - 0.5, gy - 0.5
                ux, uy = ux * math.cos(rot) - uy * math.sin(rot), ux * math.sin(rot) + uy * math.cos(rot)
                pts.append((x + (ux + 0.5) * gw + slant * uy * gh, -(uy + 0.5) * gh + dy))
            letter.append(pts)
        strokes_per.append(letter)
        x += gw * rng.uniform(0.72, 0.9)
    xs = [p[0] for L in strokes_per for s in L for p in s]
    ys = [p[1] for L in strokes_per for s in L for p in s]
    k = min((W * 0.8 - fat) / max(1.0, max(xs) - min(xs)), (H * 0.78 - fat) / max(1.0, max(ys) - min(ys)), 1.2)
    fat *= k
    cx, cy = (max(xs) + min(xs)) * 0.5, (max(ys) + min(ys)) * 0.5
    fill = np.zeros((H, W), np.float32)
    outline = np.zeros((H, W), np.float32)
    shine = np.zeros((H, W), np.float32)
    ring = max(3, int(fat * rng.uniform(0.16, 0.24)))
    struct = ndimage.generate_binary_structure(2, 1)
    # Later letters sit over earlier ones: each cuts its outline into what is under it.
    for L in strokes_per:
        img = Image.new("L", (W, H), 0)
        d = ImageDraw.Draw(img)
        inner = Image.new("L", (W, H), 0)
        di = ImageDraw.Draw(inner)
        hi = Image.new("L", (W, H), 0)
        dh = ImageDraw.Draw(hi)
        for s in L:
            pts = [((p[0] - cx) * k + W * 0.5, (p[1] - cy) * k + H * 0.5) for p in s]
            sm = catmull(pts, 10)
            draw_poly(d, sm, fat)
            # A thin line down the skeleton, in the outline colour: the letter's counters.
            if rng.random() < 0.6:
                draw_poly(di, sm[len(sm) // 5: len(sm) - len(sm) // 5], max(2, fat * 0.12))
            # Shine: a short white tick near the top-left of each stroke.
            q = sm[max(0, len(sm) // 6)]
            dh.arc([q[0] - fat * 0.3, q[1] - fat * 0.3, q[0] + fat * 0.3, q[1] + fat * 0.3], 190, 260, fill=255, width=max(2, int(fat * 0.09)))
        m = np.asarray(img) > 127
        grown = ndimage.binary_dilation(m, struct, iterations=ring)
        outline = np.maximum(outline, grown.astype(np.float32))
        fill = fill * (1.0 - grown) + m.astype(np.float32)
        fill = np.minimum(fill, 1.0 - (np.asarray(inner) > 127))
        shine = shine * (1.0 - grown) + (np.asarray(hi) > 127) * m
    # A sloppy fill: streaks where the can was moving fast.
    nrng = np.random.default_rng(rng.randrange(1 << 30))
    streak = ndimage.gaussian_filter(nrng.random((H, W)).astype(np.float32), (1.5, 18.0))
    streak = (streak - streak.mean()) / (streak.std() + 1e-6)
    fill = fill * np.clip(0.95 + 0.05 * streak, 0.8, 1.0)
    if rng.random() < 0.5:
        img = Image.new("L", (W, H), 0)
        d = ImageDraw.Draw(img)
        pts = list(zip(*np.nonzero(outline > 0.5)))
        low = [(int(p[1]), int(p[0])) for p in pts if p[0] > H * 0.55]
        if low:
            drips(d, [low[rng.randrange(len(low))] for _ in range(60)], rng, ring * 1.4, rng.randint(2, 5), H, 0.08, 0.3)
        outline = np.maximum(outline, np.asarray(img) / 255.0)
    g = spray((outline * 255).astype(np.uint8), nrng, blur=ring * 0.35, halo=0.1, speckle=0.25)
    r = np.clip(ndimage.gaussian_filter(fill, 1.2), 0, 1)
    b = np.clip(ndimage.gaussian_filter(shine.astype(np.float32), 1.5), 0, 1)
    return np.stack([r, g, b], -1)


def roller(rng, W, H):
    """Big straight block letters, the way a roller or a wide cap does them on a freeway wall."""
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)
    count = rng.randint(3, 5)
    lw = W * 0.86 / count
    stroke = lw * rng.uniform(0.2, 0.28)
    top, bot = H * 0.14, H * 0.84
    for i in range(count):
        x0 = W * 0.07 + i * lw + lw * 0.08
        x1 = x0 + lw * 0.78
        kind = rng.randrange(5)
        if kind == 0:  # a slab with a notch
            d.rectangle([x0, top, x1, bot], fill=255)
            d.rectangle([x0 + stroke, top + (bot - top) * 0.35, x1 + 2, top + (bot - top) * 0.55], fill=0)
        elif kind == 1:  # two posts and a bar
            d.rectangle([x0, top, x0 + stroke, bot], fill=255)
            d.rectangle([x1 - stroke, top, x1, bot], fill=255)
            d.rectangle([x0, top + (bot - top) * 0.42, x1, top + (bot - top) * 0.42 + stroke], fill=255)
        elif kind == 2:  # a frame
            d.rectangle([x0, top, x1, bot], fill=255)
            d.rectangle([x0 + stroke, top + stroke, x1 - stroke, bot - stroke], fill=0)
        elif kind == 3:  # a zig
            d.polygon([(x0, top), (x1, top), (x0 + stroke * 1.2, bot - stroke), (x1, bot - stroke), (x1, bot), (x0, bot), (x1 - stroke * 1.2, top + stroke), (x0, top + stroke)], fill=255)
        else:  # a step
            d.rectangle([x0, top, x0 + stroke, bot], fill=255)
            d.rectangle([x0, bot - stroke, x1, bot], fill=255)
            d.rectangle([x0, top, x1, top + stroke], fill=255)
    m = np.asarray(img).astype(np.float32) / 255.0
    nrng = np.random.default_rng(rng.randrange(1 << 30))
    # Ragged edges and roller streaks.
    edge = ndimage.gaussian_filter(nrng.random((H, W)).astype(np.float32), 3.0)
    m = ndimage.gaussian_filter(m, 2.0)
    m = np.clip((m - 0.5 + (edge - 0.5) * 0.5) * 6.0 + 0.5, 0, 1)
    streak = ndimage.gaussian_filter(nrng.random((H, W)).astype(np.float32), (0.8, 30.0))
    streak = (streak - streak.mean()) / (streak.std() + 1e-6)
    m = m * np.clip(0.88 + 0.1 * streak, 0.6, 1.0)
    z = np.zeros_like(m)
    return np.stack([m, z, z], -1)


def make_tags(rng):
    CW, CH = 1024, 512  # 2x
    atlas = np.zeros((CH * 4, CW * 4, 4), np.float32)
    for cell in range(16):
        if cell < 8:
            m = handstyle(rng, CW, CH)
            rgb = np.stack([m, np.zeros_like(m), np.zeros_like(m)], -1)
        elif cell < 14:
            rgb = throwup(rng, CW, CH)
        else:
            rgb = roller(rng, CW, CH)
        # Keep a clear margin round the cell (mips).
        pad = 24
        rgb[:pad] = 0
        rgb[-pad:] = 0
        rgb[:, :pad] = 0
        rgb[:, -pad:] = 0
        row, col = divmod(cell, 4)
        atlas[row * CH:(row + 1) * CH, col * CW:(col + 1) * CW, :3] = rgb
    atlas[..., 3] = np.max(atlas[..., :3], -1)
    img = Image.fromarray((np.clip(atlas, 0, 1) * 255).astype(np.uint8), "RGBA")
    return img.resize((2048, 1024), Image.LANCZOS)


# --- Paper -------------------------------------------------------------------------------------
BANDS = ["NIGHT MOTH", "TIN COYOTE", "NEON MARROW", "DUSKHOUND", "SODIUM", "VELVET GRAVEL",
         "PALE ORCHARD", "SLOW COMET", "MOTH PARADE", "GLORP", "HOLLOW PIER", "KOVALI"]
VENUES = ["THE ORCHID ROOM", "BASEMENT NINE", "LAMPLIGHT HALL", "THE LOW DOOR", "CASA TEMBLOR"]
WORDS = ["LIVE", "ALL AGES", "TONIGHT", "DOORS", "SAT", "FRI", "THU", "PLUS GUESTS", "FREE", "LATE"]


def text_lines(d, box, rng, color, rows, gap=None, h=None, ragged=True):
    """Illegible lines of small type: word blocks of varying length."""
    x0, y0, x1, y1 = box
    h = h or (y1 - y0) / (rows * 1.8)
    gap = gap or h * 1.8
    y = y0
    for r in range(rows):
        x = x0
        end = x1 - (rng.uniform(0, (x1 - x0) * 0.35) if ragged else 0)
        while x < end:
            w = rng.uniform(1.5, 6.5) * h
            w = min(w, end - x)
            if w > h:
                d.rounded_rectangle([x, y, x + w, y + h], radius=h * 0.3, fill=color)
            x += w + h * 0.7
        y += gap
        if y > y1:
            break


def centered(d, text, y, fnt, W, color, stretch_img=None):
    b = d.textbbox((0, 0), text, font=fnt)
    d.text(((W - (b[2] - b[0])) / 2 - b[0], y - b[1]), text, font=fnt, fill=color)
    return y + (b[3] - b[1])


def fit_font(name, text, max_w, start):
    size = start
    while size > 10:
        f = font(name, size)
        b = f.getbbox(text)
        if b[2] - b[0] <= max_w:
            return f
        size -= 4
    return font(name, 10)


def paper_noise(img, rng, amount=10):
    a = np.asarray(img).astype(np.float32)
    nrng = np.random.default_rng(rng.randrange(1 << 30))
    n = ndimage.gaussian_filter(nrng.normal(0, 1, a.shape[:2]).astype(np.float32), 1.2) * amount
    big = ndimage.gaussian_filter(nrng.normal(0, 1, a.shape[:2]).astype(np.float32), 40) * amount * 4
    a[..., :3] += (n + big)[..., None]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), img.mode)


def poster_gig(rng, W, H):
    palette = [((236, 214, 60), (22, 22, 26)), ((230, 90, 60), (250, 240, 220)), ((40, 60, 140), (240, 200, 70)),
               ((240, 236, 226), (200, 30, 40)), ((20, 20, 24), (240, 110, 170)), ((90, 170, 120), (20, 30, 25))]
    bg, fg = palette[rng.randrange(len(palette))]
    img = Image.new("RGBA", (W, H), bg + (255,))
    d = ImageDraw.Draw(img)
    # A graphic: a big circle, halftone dots, or stripes.
    g = rng.randrange(3)
    if g == 0:
        r = W * rng.uniform(0.3, 0.42)
        cx, cy = W * rng.uniform(0.35, 0.65), H * 0.42
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fg)
        d.ellipse([cx - r * 0.55, cy - r * 0.8, cx + r * 0.75, cy + r * 0.35], fill=bg)
    elif g == 1:
        step = W / 16
        for iy in range(int(H * 0.55 / step)):
            for ix in range(17):
                t = 1.0 - abs(iy * step - H * 0.3) / (H * 0.3)
                r = step * 0.48 * max(0.0, t) * (0.6 + 0.4 * math.sin(ix * 0.7 + iy * 0.3))
                x, y = ix * step, H * 0.05 + iy * step
                d.ellipse([x - r, y - r, x + r, y + r], fill=fg)
    else:
        for k in range(9):
            y = H * 0.1 + k * H * 0.055
            d.rectangle([0, y, W, y + H * 0.025], fill=fg)
    name = BANDS[rng.randrange(len(BANDS))]
    f = fit_font(LIB_B if rng.random() < 0.5 else SANS_B, name, W * 0.9, int(H * 0.16))
    y = centered(d, name, H * 0.68, f, W, fg)
    f2 = font(LIB_B, int(H * 0.045))
    centered(d, WORDS[rng.randrange(len(WORDS))] + "  ·  " + VENUES[rng.randrange(len(VENUES))], y + H * 0.04, f2, W, fg)
    text_lines(d, (W * 0.15, H * 0.9, W * 0.85, H * 0.97), rng, fg, 2, h=H * 0.012)
    return paper_noise(img, rng, 6)


def poster_club(rng, W, H):
    img = Image.new("RGBA", (W, H), (14, 12, 22, 255))
    a = np.zeros((H, W, 3), np.float32)
    yy, xx = np.mgrid[0:H, 0:W]
    for _ in range(3):
        c = np.array([rng.uniform(0.3, 1), rng.uniform(0, 0.6), rng.uniform(0.3, 1)]) * 255
        cx, cy, r = rng.uniform(0, W), rng.uniform(0, H * 0.7), rng.uniform(W * 0.3, W * 0.8)
        a += c * np.exp(-((xx - cx) ** 2 + (yy - cy) ** 2) / (r * r))[..., None] * 0.8
    img = Image.fromarray(np.clip(a + 14, 0, 255).astype(np.uint8)).convert("RGBA")
    d = ImageDraw.Draw(img)
    day = ["SATURDAY", "FRIDAY", "SUNDAY", "THURSDAY"][rng.randrange(4)]
    f = fit_font(SANS_B, day, W * 0.9, int(H * 0.12))
    centered(d, day, H * 0.12, f, W, (255, 255, 255))
    name = BANDS[rng.randrange(len(BANDS))]
    f = fit_font(SERIF_B, name, W * 0.85, int(H * 0.09))
    centered(d, name, H * 0.55, f, W, (255, 230, 120))
    text_lines(d, (W * 0.12, H * 0.72, W * 0.88, H * 0.93), rng, (220, 220, 230), 6, h=H * 0.012)
    return paper_noise(img, rng, 5)


def poster_lost(rng, W, H):
    img = Image.new("RGBA", (W, H), (244, 242, 234, 255))
    d = ImageDraw.Draw(img)
    what = "LOST CAT" if rng.random() < 0.5 else "LOST DOG"
    f = fit_font(LIB_B, what, W * 0.86, int(H * 0.13))
    centered(d, what, H * 0.04, f, W, (200, 20, 20) if rng.random() < 0.5 else (15, 15, 15))
    # The photo: a grey snapshot with a soft pale animal-ish shape in it.
    px0, py0, px1, py1 = W * 0.14, H * 0.2, W * 0.86, H * 0.55
    ph = np.zeros((int(py1 - py0), int(px1 - px0), 3), np.float32)
    nrng = np.random.default_rng(rng.randrange(1 << 30))
    ph += 90 + ndimage.gaussian_filter(nrng.normal(0, 30, ph.shape[:2]), 6)[..., None]
    yy, xx = np.mgrid[0:ph.shape[0], 0:ph.shape[1]]
    body = np.exp(-(((xx - ph.shape[1] * 0.5) / (ph.shape[1] * 0.28)) ** 2 + ((yy - ph.shape[0] * 0.62) / (ph.shape[0] * 0.28)) ** 2))
    head = np.exp(-(((xx - ph.shape[1] * 0.62) / (ph.shape[1] * 0.14)) ** 2 + ((yy - ph.shape[0] * 0.33) / (ph.shape[0] * 0.16)) ** 2))
    tone = rng.choice([(170, 140, 100), (60, 55, 50), (200, 190, 175), (130, 110, 90)])
    m = np.clip(body + head, 0, 1)[..., None]
    ph = ph * (1 - m) + np.array(tone) * m
    if rng.random() < 0.6:  # a photocopy: grey
        ph = ph.mean(-1, keepdims=True).repeat(3, -1)
    img.paste(Image.fromarray(np.clip(ph, 0, 255).astype(np.uint8)).convert("RGBA"), (int(px0), int(py0)))
    text_lines(d, (W * 0.1, H * 0.6, W * 0.9, H * 0.8), rng, (30, 30, 30), 5, h=H * 0.014)
    # Tear-off tabs along the bottom, some already taken.
    n = 9
    tw = W / n
    d.line([(0, H * 0.83), (W, H * 0.83)], fill=(120, 120, 120), width=2)
    for i in range(n):
        x = i * tw
        if rng.random() < 0.35:
            d.rectangle([x + 1, H * 0.835, x + tw - 1, H], fill=(0, 0, 0, 0))
            continue
        d.line([(x, H * 0.83), (x, H)], fill=(150, 150, 150), width=2)
        for k in range(3):
            d.rectangle([x + tw * 0.3 + k * tw * 0.15, H * 0.85, x + tw * 0.38 + k * tw * 0.15, H * 0.97], fill=(40, 40, 40))
    return paper_noise(img, rng, 4)


def poster_bill(rng, W, H):
    papers = [(250, 230, 70), (250, 140, 170), (140, 220, 240), (245, 245, 240), (250, 170, 60), (170, 240, 140)]
    img = Image.new("RGBA", (W, H), papers[rng.randrange(len(papers))] + (255,))
    d = ImageDraw.Draw(img)
    heads = [["ROOM", "FOR RENT"], ["GUITAR", "LESSONS"], ["MOVING", "SALE"], ["HELP", "WANTED"], ["YARD", "SALE"],
             ["PIANO", "FOR FREE"], ["BAND", "NEEDS DRUMMER"]]
    lines = heads[rng.randrange(len(heads))]
    y = H * 0.06
    for ln in lines:
        f = fit_font(LIB_B, ln, W * 0.88, int(H * 0.14))
        y = centered(d, ln, y, f, W, (15, 15, 20)) + H * 0.03
    text_lines(d, (W * 0.1, y + H * 0.04, W * 0.9, H * 0.78), rng, (30, 30, 30), 7, h=H * 0.018)
    n = 8
    tw = W / n
    for i in range(n):
        x = i * tw
        if rng.random() < 0.3:
            d.rectangle([x + 1, H * 0.84, x + tw - 1, H], fill=(0, 0, 0, 0))
            continue
        d.line([(x, H * 0.84), (x, H)], fill=(80, 80, 80), width=2)
        d.rectangle([x + tw * 0.4, H * 0.86, x + tw * 0.6, H * 0.97], fill=(40, 40, 40))
    return paper_noise(img, rng, 5)


def poster_art(rng, W, H):
    """A screen-printed art print: two or three inks, overlapping shapes, a small name."""
    inks = [(230, 70, 50), (30, 90, 170), (245, 200, 40), (20, 20, 20), (240, 140, 170), (40, 150, 110)]
    rng.shuffle(inks)
    img = Image.new("RGBA", (W, H), (238, 232, 216, 255))
    d = ImageDraw.Draw(img, "RGBA")
    for k in range(rng.randint(3, 6)):
        c = inks[k % 3] + (200,)
        s = rng.randrange(3)
        x, y, r = rng.uniform(0, W), rng.uniform(0, H * 0.8), rng.uniform(W * 0.15, W * 0.45)
        if s == 0:
            d.ellipse([x - r, y - r, x + r, y + r], fill=c)
        elif s == 1:
            d.polygon([(x, y - r), (x + r, y + r), (x - r, y + r)], fill=c)
        else:
            d.rectangle([x - r, y - r * 0.4, x + r, y + r * 0.4], fill=c)
    name = BANDS[rng.randrange(len(BANDS))]
    f = fit_font(SANS_B, name, W * 0.6, int(H * 0.05))
    d.text((W * 0.08, H * 0.9), name, font=f, fill=(20, 20, 20))
    return paper_noise(img, rng, 7)


def poster_text(rng, W, H):
    """A wall of type: an event bill in columns, the kind nobody reads."""
    bg = [(240, 238, 230), (250, 220, 60), (30, 30, 34)][rng.randrange(3)]
    fg = (20, 20, 20) if sum(bg) > 300 else (240, 240, 235)
    acc = [(210, 30, 40), (30, 70, 170), (20, 130, 80)][rng.randrange(3)]
    img = Image.new("RGBA", (W, H), bg + (255,))
    d = ImageDraw.Draw(img)
    word = ["WEEKEND", "SEASON", "BLOCK PARTY", "SHOWCASE", "OPEN MIC"][rng.randrange(5)]
    f = fit_font(LIB_B, word, W * 0.9, int(H * 0.11))
    y = centered(d, word, H * 0.05, f, W, acc) + H * 0.04
    for col in range(2):
        text_lines(d, (W * (0.07 + col * 0.46), y, W * (0.47 + col * 0.46), H * 0.93), rng, fg, 12, h=H * 0.014, gap=H * 0.03)
    return paper_noise(img, rng, 5)


POSTERS = [poster_gig, poster_gig, poster_club, poster_lost, poster_bill, poster_art, poster_gig, poster_text,
           poster_club, poster_lost, poster_bill, poster_art, poster_gig, poster_text, poster_bill, poster_gig]


def sticker(rng, S, i):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    words = ["GLORP", "WIMBLE", "ZUNDA", "FROBAK", "QUAXX", "MOOP", "TENDER", "BLOOMRAT", "OKAY?", "HI!"]
    colors = [(230, 50, 50), (40, 90, 200), (250, 210, 40), (30, 30, 30), (250, 250, 245), (60, 180, 110), (250, 120, 180), (250, 140, 40)]
    kind = i % 8
    m = S * 0.08
    border = S * 0.05
    white = (250, 250, 246, 255)
    if kind == 0:  # slap label: coloured header band, white body with a scribble
        c = colors[rng.randrange(3)]
        d.rounded_rectangle([m, S * 0.2, S - m, S * 0.8], radius=S * 0.05, fill=white)
        d.rounded_rectangle([m, S * 0.2, S - m, S * 0.4], radius=S * 0.05, fill=c + (255,))
        d.rectangle([m, S * 0.33, S - m, S * 0.4], fill=c + (255,))
        text_lines(d, (S * 0.2, S * 0.26, S * 0.8, S * 0.34), rng, (255, 255, 255), 1, h=S * 0.03)
        pts = [(S * rng.uniform(0.15, 0.25), S * 0.68)]
        for k in range(6):
            pts.append((S * (0.2 + k * 0.11), S * rng.uniform(0.47, 0.72)))
        draw_poly(d, catmull(pts, 8), S * 0.025, fill=(20, 20, 20, 255))
    elif kind == 1:  # round emblem: ring, dotted "text", a simple face
        c1, c2 = rng.sample(colors, 2)
        r = S * 0.42
        d.ellipse([S / 2 - r, S / 2 - r, S / 2 + r, S / 2 + r], fill=white)
        r -= border
        d.ellipse([S / 2 - r, S / 2 - r, S / 2 + r, S / 2 + r], fill=c1 + (255,))
        r2 = r * 0.62
        d.ellipse([S / 2 - r2, S / 2 - r2, S / 2 + r2, S / 2 + r2], fill=c2 + (255,))
        for k in range(18):
            a = k / 18 * math.tau
            q = (S / 2 + math.cos(a) * r * 0.82, S / 2 + math.sin(a) * r * 0.82)
            d.ellipse([q[0] - S * 0.012, q[1] - S * 0.012, q[0] + S * 0.012, q[1] + S * 0.012], fill=(255, 255, 255, 255))
        e = S * 0.05
        for sx in (-1, 1):
            d.ellipse([S / 2 + sx * r2 * 0.35 - e, S * 0.45 - e, S / 2 + sx * r2 * 0.35 + e, S * 0.45 + e], fill=(20, 20, 20, 255))
        d.arc([S / 2 - r2 * 0.45, S * 0.45, S / 2 + r2 * 0.45, S * 0.62], 20, 160, fill=(20, 20, 20, 255), width=int(S * 0.02))
    elif kind == 2:  # a word on a band
        c = colors[rng.randrange(len(colors))]
        fg = (20, 20, 20) if sum(c) > 450 else (255, 255, 255)
        word = words[rng.randrange(len(words))]
        d.rounded_rectangle([m, S * 0.32, S - m, S * 0.68], radius=S * 0.06, fill=white)
        d.rounded_rectangle([m + border, S * 0.32 + border, S - m - border, S * 0.68 - border], radius=S * 0.04, fill=c + (255,))
        f = fit_font(SANS_B, word, S * 0.7, int(S * 0.2))
        centered(d, word, S * 0.4, f, S, fg)
    elif kind == 3:  # an eyeball character
        r = S * 0.4
        d.ellipse([S / 2 - r, S / 2 - r, S / 2 + r, S / 2 + r], fill=white)
        r -= border
        d.ellipse([S / 2 - r, S / 2 - r, S / 2 + r, S / 2 + r], fill=(240, 240, 235, 255), outline=(20, 20, 20, 255), width=int(S * 0.02))
        c = colors[rng.randrange(len(colors))]
        ir = r * 0.5
        ox = rng.uniform(-0.2, 0.2) * r
        d.ellipse([S / 2 - ir + ox, S / 2 - ir, S / 2 + ir + ox, S / 2 + ir], fill=c + (255,))
        pr = ir * 0.45
        d.ellipse([S / 2 - pr + ox, S / 2 - pr, S / 2 + pr + ox, S / 2 + pr], fill=(10, 10, 10, 255))
        d.ellipse([S / 2 - pr * 0.9 + ox, S / 2 - pr * 0.9, S / 2 - pr * 0.3 + ox, S / 2 - pr * 0.3], fill=(255, 255, 255, 255))
    elif kind == 4:  # hazard stripes
        d.rounded_rectangle([m, S * 0.3, S - m, S * 0.7], radius=S * 0.03, fill=white)
        box = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        bd = ImageDraw.Draw(box)
        c = colors[rng.randrange(2) + 2]
        for k in range(-4, 12):
            x = k * S * 0.12
            bd.polygon([(x, S * 0.3), (x + S * 0.06, S * 0.3), (x - S * 0.02, S * 0.7), (x - S * 0.08, S * 0.7)], fill=(20, 20, 20, 255))
        mask = Image.new("L", (S, S), 0)
        ImageDraw.Draw(mask).rectangle([m + border, S * 0.3 + border, S - m - border, S * 0.7 - border], fill=255)
        fillc = Image.new("RGBA", (S, S), c + (255,))
        img.paste(fillc, (0, 0), mask)
        img.paste(box, (0, 0), Image.fromarray(np.minimum(np.asarray(box)[..., 3], np.asarray(mask))))
    elif kind == 5:  # a little ghost / blob creature
        c = colors[rng.randrange(len(colors))]
        pts = []
        for k in range(24):
            a = k / 24 * math.tau
            rr = S * (0.36 + 0.05 * math.sin(a * 3 + i))
            pts.append((S / 2 + math.cos(a) * rr, S / 2 + math.sin(a) * rr * 1.05))
        d.polygon(pts, fill=white)
        pts2 = [(S / 2 + (p[0] - S / 2) * 0.86, S / 2 + (p[1] - S / 2) * 0.86) for p in pts]
        d.polygon(pts2, fill=c + (255,))
        for sx in (-1, 1):
            d.ellipse([S / 2 + sx * S * 0.1 - S * 0.04, S * 0.42 - S * 0.06, S / 2 + sx * S * 0.1 + S * 0.04, S * 0.42 + S * 0.06], fill=(20, 20, 20, 255))
        d.line([(S * 0.42, S * 0.6), (S * 0.5, S * 0.64), (S * 0.58, S * 0.6)], fill=(20, 20, 20, 255), width=int(S * 0.02))
    elif kind == 6:  # a white label with black handstyle
        d.rounded_rectangle([m, S * 0.25, S - m, S * 0.75], radius=S * 0.02, fill=white)
        pts = []
        for k in range(8):
            pts.append((S * (0.16 + k * 0.095), S * rng.uniform(0.35, 0.62)))
        draw_poly(d, catmull(pts, 8), S * 0.03, fill=[(20, 20, 20, 255), (200, 30, 30, 255), (30, 60, 180, 255)][rng.randrange(3)])
    else:  # a moon / sun disc
        c1, c2 = rng.sample(colors, 2)
        r = S * 0.38
        d.ellipse([S / 2 - r, S / 2 - r, S / 2 + r, S / 2 + r], fill=white)
        r -= border
        d.ellipse([S / 2 - r, S / 2 - r, S / 2 + r, S / 2 + r], fill=c1 + (255,))
        d.ellipse([S / 2 - r * 0.6, S / 2 - r * 0.8, S / 2 + r * 0.9, S / 2 + r * 0.6], fill=c2 + (255,))
    return img


def make_paper(rng):
    PW, PH = 512, 768  # posters at 2x
    SS = 256  # stickers at 2x
    atlas = Image.new("RGBA", (4096, 2048), (0, 0, 0, 0))
    for i, fn in enumerate(POSTERS):
        p = fn(rng, PW - 32, PH - 32)
        # Slightly irregular paper edge.
        a = np.asarray(p).copy()
        nrng = np.random.default_rng(rng.randrange(1 << 30))
        edge = ndimage.gaussian_filter(nrng.random(a.shape[:2]).astype(np.float32), 2.0)
        h, w = a.shape[:2]
        yy, xx = np.mgrid[0:h, 0:w]
        dist = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy)).astype(np.float32)
        cut = dist > (edge - 0.5) * 12.0 + 3.0
        a[..., 3] = (a[..., 3] * cut).astype(np.uint8)
        p = Image.fromarray(a)
        row, col = divmod(i, 8)
        atlas.paste(p, (col * PW + 16, row * PH + 16))
    for i in range(32):
        s = sticker(rng, SS - 16, i + rng.randrange(8) * 0)
        row, col = divmod(i, 16)
        atlas.paste(s, (col * SS + 8, 2 * PH + row * SS + 8))
    return atlas.resize((2048, 1024), Image.LANCZOS)


def main():
    rng = random.Random(SEED)
    os.makedirs(OUT_DIR, exist_ok=True)
    tags = make_tags(rng)
    paper = make_paper(rng)
    tags.save(os.path.join(OUT_DIR, "street_wear_tags.png"), optimize=True)
    paper.save(os.path.join(OUT_DIR, "street_wear_paper.png"), optimize=True)
    if "--preview" in sys.argv:
        pass
        prev = Image.new("RGB", (2048, 2048), (128, 124, 118))
        t = np.asarray(tags).astype(np.float32) / 255.0
        col = np.full(t.shape[:2] + (3,), (128, 124, 118), np.float32)
        col = col * (1 - t[..., 1:2]) + np.array([20, 20, 30]) * t[..., 1:2]
        col = col * (1 - t[..., 0:1]) + np.array([220, 60, 160]) * t[..., 0:1]
        col = col * (1 - t[..., 2:3]) + 255 * t[..., 2:3]
        prev.paste(Image.fromarray(col.astype(np.uint8)), (0, 0))
        prev.paste(paper, (0, 1024), paper)
        prev.save(os.path.join(OUT_DIR, "street_wear_preview.png"))
    print("wrote", OUT_DIR)


if __name__ == "__main__":
    main()
