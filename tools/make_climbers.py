#!/usr/bin/env python3
"""Climbing plants and garden accents: the leaf / flower atlas ClimbingPlants wears.

Everything is ORIGINAL procedural art drawn by this script from a fixed seed: leaf outlines are
parametric (lobed ivy, heart-shaped creeping fig, ovate bougainvillea, star jasmine, pinnate
wisteria and trumpet vine, toothed grape), shaded leaf by leaf (a dome across the blade, the
midrib and veins, a darker edge, a lighter underside where a leaf turns), with the flowers drawn
the same way (papery bougainvillea bracts in threes, jasmine pinwheels, wisteria racemes, grape
bunches, orange trumpets) and the accent plants' blades (an agave leaf with its teeth, terminal
spine and the bud prints of the leaf it grew against, an aloe leaf with its spots, a red-hot
poker spike, lavender, lantana heads).

Writes, in assets/textures/climbers/:

* climbers_albedo.png (2048 x 1536, sRGB colour + alpha cut-out): 8 x 6 cells of 256 px. Every
  cell keeps an 8 px transparent margin so the mip chain never bleeds one cell into the next;
  scripts/world/climbing_plants.gd holds the same grid (CELL_* constants, ATLAS_COLS / _ROWS).
* climbers_normal.png (same grid, OpenGL tangent-space normal from the painted height).

Cells (index = row * 8 + column):
   0-3  ivy sprigs              4-5  ivy mat              6-7  creeping fig mat
   8-9  bougainvillea leaves    10-11 bracts magenta      12-13 bracts orange   14-15 bracts white
  16-17 star jasmine leaves     18-19 jasmine in flower   20-21 wisteria leaves 22-23 wisteria racemes
  24-25 grape leaves            26 grape bunch            27-28 trumpet vine leaves
  29-30 trumpet vine in flower  31 woody stems
  32 agave blade  33 agave blade (variegated)  34 aloe blade  35 red-hot poker spike
  36 lavender clump  37-38 lantana in flower  39 strappy blades (the poker's leaves)
  40 bougainvillea leaf mass  41-43 bougainvillea mass in bloom (magenta, orange, white)
  44 star jasmine mass in flower  45 wisteria leaf mass  46 grape leaf mass  47 trumpet vine mass

Drawn at twice the size and filtered down (premultiplied), so edges are anti-aliased.

    python3 tools/make_climbers.py              # writes both PNGs
    python3 tools/make_climbers.py --preview    # also writes build/climbers_preview.png

Then `godot --headless --path . --import` and `python3 tools/fix_texture_imports.py` on the two
new .import files, and commit the PNGs and their .import files.
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw

COLS, ROWS = 8, 6
CELL = 256
SS = 2  # supersampling
C2 = CELL * SS
MARGIN = 8 * SS
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "textures", "climbers")


def srgb(r, g, b):
    return np.array([r, g, b], dtype=np.float32) / 255.0


class Cell:
    """One cell being painted: premultiplied colour, coverage and height, at C2 x C2."""

    def __init__(self):
        self.rgb = np.zeros((C2, C2, 3), np.float32)
        self.a = np.zeros((C2, C2), np.float32)
        self.h = np.zeros((C2, C2), np.float32)

    def put(self, mask, color, height, x0, y0):
        """Composites a patch (mask, colour HxWx3, height HxW) at x0, y0, over what is there."""
        hgt, wid = mask.shape
        xa, ya = max(0, x0), max(0, y0)
        xb, yb = min(C2, x0 + wid), min(C2, y0 + hgt)
        if xa >= xb or ya >= yb:
            return
        m = mask[ya - y0:yb - y0, xa - x0:xb - x0]
        c = color[ya - y0:yb - y0, xa - x0:xb - x0]
        hh = height[ya - y0:yb - y0, xa - x0:xb - x0]
        dst_rgb = self.rgb[ya:yb, xa:xb]
        dst_a = self.a[ya:yb, xa:xb]
        dst_h = self.h[ya:yb, xa:xb]
        self.rgb[ya:yb, xa:xb] = c * m[..., None] + dst_rgb * (1.0 - m[..., None])
        self.a[ya:yb, xa:xb] = m + dst_a * (1.0 - m)
        # A leaf lying on another stands a little proud of it.
        self.h[ya:yb, xa:xb] = np.where(m > 0.5, np.maximum(hh, dst_h * 0.6 + hh), dst_h)


def poly_mask(points, size):
    """Coverage of a polygon (list of (x, y) in patch px) in a size x size patch."""
    im = Image.new("L", (size[0], size[1]), 0)
    ImageDraw.Draw(im).polygon([(float(x), float(y)) for x, y in points], fill=255)
    return np.asarray(im, np.float32) / 255.0


def blade(cell, rng, outline, base, tip, color, vein=0.8, veins=6, height=1.0, edge_dark=0.25,
          curl=0.0, side_light=0.12, hue_jit=0.06, vein_light=False, spots=None):
    """One leaf blade from `base` to `tip` (cell px). `outline(t)` is the half width at t in 0..1
    as a fraction of the length (negative t is allowed for lobes behind the base). Shaded across
    (a dome), along (lighter toward the tip), with a midrib and `veins` pairs of side veins."""
    bx, by = base
    tx, ty = tip
    length = math.hypot(tx - bx, ty - by)
    if length < 2:
        return
    ux, uy = (tx - bx) / length, (ty - by) / length
    vx, vy = -uy, ux
    ts = np.linspace(-0.25, 1.0, 140)
    left, right = [], []
    for t in ts:
        w = outline(t)
        if w <= 0 and t > 0.02:
            continue
        w = max(w, 0.0)
        bend = curl * t * t * length
        px, py = bx + ux * t * length + vx * bend, by + uy * t * length + vy * bend
        left.append((px + vx * w * length, py + vy * w * length))
        right.append((px - vx * w * length, py - vy * w * length))
    pts = left + right[::-1]
    if len(pts) < 3:
        return
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    x0, y0 = int(math.floor(min(xs))) - 2, int(math.floor(min(ys))) - 2
    x1, y1 = int(math.ceil(max(xs))) + 2, int(math.ceil(max(ys))) + 2
    wid, hgt = x1 - x0, y1 - y0
    if wid <= 0 or hgt <= 0:
        return
    mask = poly_mask([(x - x0, y - y0) for x, y in pts], (wid, hgt))
    yy, xx = np.mgrid[0:hgt, 0:wid].astype(np.float32)
    rx, ry = xx + x0 - bx, yy + y0 - by
    t = (rx * ux + ry * uy) / length
    s = (rx * vx + ry * vy) / length
    t_c = np.clip(t, 0.0, 1.0)
    bend = curl * t_c * t_c
    s = s - bend
    half = np.maximum(np.vectorize(outline)(np.clip(t, -0.25, 1.0)), 1e-3)
    across = np.clip(np.abs(s) / half, 0.0, 1.0)
    col = np.array(color, np.float32) * (1.0 + rng.uniform(-hue_jit, hue_jit, 3).astype(np.float32))
    dome = 1.0 - across ** 2
    shade = 0.78 + 0.22 * dome + 0.10 * (t_c - 0.5)
    shade *= 1.0 + side_light * np.sign(s) * 0.5
    shade *= 1.0 - edge_dark * np.clip((across - 0.78) / 0.22, 0.0, 1.0)
    c = col[None, None, :] * shade[..., None]
    # Midrib and side veins: thin lines, lighter or darker than the blade.
    rib = np.exp(-(s / (0.012 + 0.006 * (1 - t_c))) ** 2) * (t > 0.0) * (t < 0.97)
    vein_v = np.zeros_like(t)
    for k in range(veins):
        tk = (k + 0.6) / (veins + 0.5) * 0.9
        # Each side vein runs out and forward from the midrib.
        d = (t - tk) - np.abs(s) * 0.9
        vein_v += np.exp(-(d / 0.012) ** 2) * (np.abs(s) > 0.01) * (across < 0.9)
    vein_v = np.clip(vein_v, 0, 1) * vein
    vk = 1.25 if vein_light else 0.7
    c = c * (1.0 + (vk - 1.0) * np.clip(rib * 1.2 + vein_v * 0.6, 0, 1))[..., None]
    if spots is not None:
        # Pale flecks (an aloe's spots): random little ellipses inside the blade.
        sp = np.zeros_like(t)
        for _ in range(spots):
            st, ss_ = rng.uniform(0.05, 0.9), rng.uniform(-0.6, 0.6)
            r = rng.uniform(0.012, 0.03)
            sp = np.maximum(sp, np.clip(1.0 - (((t - st) / (r * 2.2)) ** 2 + ((s / half - ss_) / 1.6 / (r * 20)) ** 2), 0, 1))
        c = c * (1.0 - sp[..., None]) + np.array([0.78, 0.82, 0.70], np.float32) * sp[..., None]
    h = height * (0.55 + 0.45 * dome) - 0.25 * rib * height - 0.12 * vein_v * height
    cell.put(mask, np.clip(c, 0, 1), h.astype(np.float32), x0, y0)


def stem(cell, pts, width, color, height=0.6):
    """A stem / twig along pts (cell px), as a run of round-capped segments."""
    for (ax, ay), (bx, by) in zip(pts[:-1], pts[1:]):
        x0, y0 = int(min(ax, bx) - width - 2), int(min(ay, by) - width - 2)
        x1, y1 = int(max(ax, bx) + width + 2), int(max(ay, by) + width + 2)
        yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
        dx, dy = bx - ax, by - ay
        ll = max(dx * dx + dy * dy, 1e-6)
        t = np.clip(((xx - ax) * dx + (yy - ay) * dy) / ll, 0, 1)
        d = np.hypot(xx - (ax + dx * t), yy - (ay + dy * t))
        m = np.clip(width - d + 0.5, 0, 1)
        r = np.clip(d / max(width, 0.5), 0, 1)
        c = np.array(color, np.float32)[None, None, :] * (0.75 + 0.35 * (1 - r ** 2))[..., None]
        cell.put(m, c, (height * (1 - r ** 2)).astype(np.float32), x0, y0)


def curve(p0, p1, bow, n=12):
    (ax, ay), (bx, by) = p0, p1
    mx, my = (ax + bx) / 2 - (by - ay) * bow, (ay + by) / 2 + (bx - ax) * bow
    out = []
    for i in range(n + 1):
        t = i / n
        out.append(((1 - t) ** 2 * ax + 2 * (1 - t) * t * mx + t * t * bx, (1 - t) ** 2 * ay + 2 * (1 - t) * t * my + t * t * by))
    return out


def disc(cell, cx, cy, r, color, height=0.8, ring=0.0):
    x0, y0 = int(cx - r - 2), int(cy - r - 2)
    size = int(2 * r + 5)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    d = np.hypot(xx + x0 - cx, yy + y0 - cy) / max(r, 0.5)
    m = np.clip((1 - d) * r + 0.5, 0, 1)
    lit = np.clip(1 - np.hypot(xx + x0 - (cx - r * 0.35), yy + y0 - (cy - r * 0.35)) / (r * 1.6), 0, 1)
    c = np.array(color, np.float32)[None, None, :] * (0.62 + 0.55 * lit)[..., None]
    if ring > 0:
        c = c * (1 - ring * np.clip((d - 0.75) / 0.25, 0, 1))[..., None]
    cell.put(m, np.clip(c, 0, 1), (height * np.sqrt(np.clip(1 - d * d, 0, 1))).astype(np.float32), x0, y0)


# --- Leaf outlines (half width as a fraction of the length, t from base 0 to tip 1) ----------------

def ovate(w, power=0.85, back=0.25):
    return lambda t: w * max(math.sin(math.pi * min(max(t, 0.0), 1.0)), 0.0) ** power * (1.0 - back * t) if t >= 0 else 0.0


def lance(w):
    return lambda t: w * (max(math.sin(math.pi * min(max(t, 0.0), 1.0) ** 0.8), 0.0) ** 1.1) if t >= 0 else 0.0


def heart(w):
    # Rounded lobes either side of the stalk, a short point.
    def f(t):
        if t < -0.18:
            return 0.0
        if t < 0.0:
            return w * 0.85 * math.sqrt(max(0.0, 1.0 - (t / 0.18) ** 2)) * (0.4 + 0.6 * (1 + t / 0.18))
        return w * (math.sin(math.pi * (0.5 + 0.5 * t)) ** 0.7 if t < 1.0 else 0.0) * (1.05 - 0.25 * t)
    return f


def lobed(w, lobes=5, depth=0.35, teeth=0.0, seed=0.0):
    # A palmate leaf (ivy, grape) drawn as a width that rises and falls along the blade: the lobes.
    def f(t):
        if t < -0.12:
            return 0.0
        tt = max(t, 0.0)
        env = math.sin(math.pi * min(0.15 + tt * 0.85, 1.0)) ** 0.6 * (1.0 - 0.45 * tt)
        if t < 0:
            env = 0.6 * (1 + t / 0.12)
        lob = 1.0 - depth * (0.5 - 0.5 * math.cos(tt * math.pi * (lobes - 1) * 0.5 + seed)) ** 2
        tooth = 1.0 - teeth * (0.5 + 0.5 * math.sin(tt * 70.0 + seed))
        return w * env * lob * tooth
    return f


def palmate(cell, rng, base, tip, color, lobes=5, depth=0.45, vein_light=True, height=0.9, teeth=0.0):
    """A palmate leaf (ivy, grape) round the point where the stalk meets it: lobes pointing out
    from it, the middle one along base->tip, a notch at the stalk, veins running to each lobe."""
    bx, by = base
    tx, ty = tip
    R = math.hypot(tx - bx, ty - by)
    if R < 3:
        return
    a0 = math.atan2(ty - by, tx - bx)
    spread = 0.78 if lobes == 5 else 1.0
    lobe_angles = [(k - (lobes - 1) / 2) * spread for k in range(lobes)]
    lobe_len = [1.0 - 0.22 * abs(k - (lobes - 1) / 2) ** 1.2 for k in range(lobes)]
    def radius(th):
        # th relative to the tip direction, -pi..pi
        best = 0.0
        for la, ll in zip(lobe_angles, lobe_len):
            d = (th - la + math.pi) % math.tau - math.pi
            best = max(best, ll * max(0.0, 1.0 - abs(d) / (spread * 0.62)) ** 0.9)
        r = (1.0 - depth) + depth * best
        # The stalk's notch behind the blade.
        back = abs((th + math.pi) % math.tau - math.pi)
        r *= 1.0 - 0.75 * max(0.0, 1.0 - (math.pi - back) / 0.45) ** 2
        r *= 1.0 - teeth * (0.5 + 0.5 * math.sin(th * 41.0))
        return r
    for _ in range(8):
        cen = (bx + math.cos(a0) * R * 0.28, by + math.sin(a0) * R * 0.28)
        pts = []
        for i in range(220):
            th = -math.pi + math.tau * i / 220
            r = radius(th) * R * 0.75
            pts.append((cen[0] + math.cos(a0 + th) * r, cen[1] + math.sin(a0 + th) * r))
        lo = min(min(p[0] for p in pts), min(p[1] for p in pts))
        hi = max(max(p[0] for p in pts), max(p[1] for p in pts))
        if lo >= MARGIN and hi <= C2 - MARGIN:
            break
        R *= 0.85
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    x0, y0 = int(min(xs)) - 2, int(min(ys)) - 2
    x1, y1 = int(max(xs)) + 3, int(max(ys)) + 3
    mask = poly_mask([(x - x0, y - y0) for x, y in pts], (x1 - x0, y1 - y0))
    yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
    dx, dy = xx - cen[0], yy - cen[1]
    dist = np.hypot(dx, dy) / (R * 0.75)
    th = (np.arctan2(dy, dx) - a0 + math.pi) % math.tau - math.pi
    rad = np.vectorize(radius)(th)
    rel = np.clip(dist / np.maximum(rad, 1e-3), 0, 1)
    vein = np.zeros_like(dist)
    for la in lobe_angles:
        d = np.abs((th - la + math.pi) % math.tau - math.pi) * dist
        vein = np.maximum(vein, np.exp(-(d / 0.025) ** 2) * (rel < 0.95))
    col = np.array(color, np.float32) * (1.0 + rng.uniform(-0.06, 0.06, 3).astype(np.float32))
    dome = 1.0 - rel ** 2
    shade = (0.8 + 0.22 * dome) * (1.0 - 0.25 * np.clip((rel - 0.82) / 0.18, 0, 1))
    shade *= 1.0 + 0.08 * np.cos(th * 2.0 + 0.7)
    c = col[None, None, :] * shade[..., None]
    vk = 1.45 if vein_light else 0.7
    c = c * (1.0 + (vk - 1.0) * vein)[..., None]
    h = height * (0.55 + 0.45 * dome) - 0.2 * vein * height
    stem(cell, [base, cen], 1.5 * SS, color * 0.8)
    cell.put(mask, np.clip(c, 0, 1), h.astype(np.float32), x0, y0)


def strap(w, taper=0.85):
    return lambda t: w * (1.0 - taper * max(t, 0.0) ** 1.4) if 0.0 <= t <= 1.0 else 0.0


# --- Palette (sRGB) -----------------------------------------------------------------------------------

IVY = [srgb(38, 62, 28), srgb(46, 72, 30), srgb(30, 52, 24), srgb(52, 76, 36)]
FIG = [srgb(54, 86, 34), srgb(64, 96, 38), srgb(44, 74, 30)]
BOUG_LEAF = [srgb(58, 92, 36), srgb(66, 100, 40), srgb(50, 84, 32)]
MAGENTA = [srgb(208, 34, 132), srgb(192, 24, 118), srgb(224, 56, 150)]
ORANGE = [srgb(236, 120, 46), srgb(226, 96, 40), srgb(244, 146, 66)]
WHITE = [srgb(242, 236, 232), srgb(234, 226, 226), srgb(246, 242, 236)]
JASMINE = [srgb(34, 60, 26), srgb(40, 68, 30)]
WIST_LEAF = [srgb(76, 108, 44), srgb(84, 116, 50)]
WIST_FLOWER = [srgb(156, 132, 206), srgb(140, 116, 196), srgb(176, 156, 220)]
GRAPE_LEAF = [srgb(78, 112, 46), srgb(88, 120, 50)]
TRUMPET_LEAF = [srgb(62, 96, 36), srgb(70, 104, 40)]
TRUMPET = [srgb(232, 92, 34), srgb(220, 70, 30), srgb(240, 120, 44)]
STEM = srgb(92, 70, 52)


def sprig(cell, rng, n_leaves, outline, colors, size=(0.28, 0.42), veins=5, vein_light=False, curl=0.15,
          start=None, end=None, stem_w=3.0, flowers=None, height=1.0):
    """A stem across the cell with leaves on alternating sides, newest (smallest) toward the tip."""
    m = MARGIN + 6
    start = start or (rng.uniform(m, C2 * 0.3), C2 - m - rng.uniform(0, C2 * 0.15))
    end = end or (C2 - m - rng.uniform(0, C2 * 0.25), m + rng.uniform(0, C2 * 0.25))
    path = curve(start, end, rng.uniform(-0.25, 0.25), 24)
    stem(cell, path, stem_w * SS, STEM * 0.9 + colors[0] * 0.4)
    for i in range(n_leaves):
        f = (i + 0.5) / n_leaves
        k = int(f * (len(path) - 1))
        px, py = path[k]
        qx, qy = path[min(k + 1, len(path) - 1)]
        ang = math.atan2(qy - py, qx - px) + (1 if i % 2 else -1) * rng.uniform(0.6, 1.3)
        ln = C2 * rng.uniform(*size) * (1.0 - 0.35 * f)
        tip = (px + math.cos(ang) * ln, py + math.sin(ang) * ln)
        # Keep the blade inside the cell's margin.
        tip = (min(max(tip[0], m), C2 - m), min(max(tip[1], m), C2 - m))
        if callable(outline) and getattr(outline, "palmate", False):
            outline(cell, rng, (px, py), tip, colors[rng.integers(len(colors))])
        else:
            blade(cell, rng, outline, (px, py), tip, colors[rng.integers(len(colors))], veins=veins, vein_light=vein_light,
                  curl=rng.uniform(-curl, curl), height=height)
    if flowers:
        flowers(cell, rng, path)
    return path


def mat(cell, rng, n, outline, colors, size, veins=3, vein_light=False):
    """A dense mat of small leaves all over the cell (creeping fig, ivy on a wall), with the vine
    showing between them."""
    m = MARGIN + 4
    for _ in range(5):
        a = (rng.uniform(m, C2 - m), rng.uniform(m, C2 - m))
        b = (rng.uniform(m, C2 - m), rng.uniform(m, C2 - m))
        stem(cell, curve(a, b, rng.uniform(-0.3, 0.3), 16), 1.6 * SS, STEM)
    for _ in range(n):
        cx, cy = rng.uniform(m + 10, C2 - m - 10), rng.uniform(m + 10, C2 - m - 10)
        ang = rng.uniform(0, math.tau)
        ln = C2 * rng.uniform(*size)
        tipx = min(max(cx + math.cos(ang) * ln, m), C2 - m)
        tipy = min(max(cy + math.sin(ang) * ln, m), C2 - m)
        if getattr(outline, "palmate", False):
            outline(cell, rng, (cx, cy), (tipx, tipy), colors[rng.integers(len(colors))])
        else:
            blade(cell, rng, outline, (cx, cy), (tipx, tipy), colors[rng.integers(len(colors))], veins=veins,
                  vein_light=vein_light, curl=rng.uniform(-0.1, 0.1), height=0.8)


def bracts(cell, rng, cx, cy, size, colors):
    """A bougainvillea bract cluster: three papery heart-ish bracts round a pale flower."""
    base_ang = rng.uniform(0, math.tau)
    for k in range(3):
        a = base_ang + k * math.tau / 3 + rng.uniform(-0.25, 0.25)
        tip = (cx + math.cos(a) * size, cy + math.sin(a) * size)
        blade(cell, rng, ovate(0.48, 0.6, 0.1), (cx, cy), tip, colors[rng.integers(len(colors))], veins=4, vein=1.0,
              vein_light=False, edge_dark=0.1, height=0.6, side_light=0.2, hue_jit=0.05)
    disc(cell, cx, cy, size * 0.12, srgb(246, 236, 200), 0.9)


def boug_flowers(colors):
    def f(cell, rng, path):
        m = MARGIN + 30
        for _ in range(rng.integers(5, 8)):
            # Clusters toward the tips, a few along the stem.
            k = int(rng.uniform(0.35, 1.0) * (len(path) - 1))
            px, py = path[k]
            cx = min(max(px + rng.normal(0, C2 * 0.12), m), C2 - m)
            cy = min(max(py + rng.normal(0, C2 * 0.12), m), C2 - m)
            for _ in range(rng.integers(2, 5)):
                bracts(cell, rng, cx + rng.normal(0, 16 * SS), cy + rng.normal(0, 16 * SS), rng.uniform(20, 30) * SS, colors)
    return f


def jasmine_flower(cell, rng, cx, cy, r):
    """Star jasmine: five pinwheel petals twisted the same way round a cream throat."""
    a0 = rng.uniform(0, math.tau)
    for k in range(5):
        a = a0 + k * math.tau / 5
        tip = (cx + math.cos(a + 0.35) * r, cy + math.sin(a + 0.35) * r)
        blade(cell, rng, ovate(0.34, 0.7, 0.0), (cx + math.cos(a) * r * 0.12, cy + math.sin(a) * r * 0.12), tip,
              srgb(246, 244, 236), veins=0, vein=0.0, edge_dark=0.08, curl=0.25, height=0.5, hue_jit=0.02)
    disc(cell, cx, cy, r * 0.16, srgb(236, 222, 170), 0.7)


def jasmine_flowers(cell, rng, path):
    m = MARGIN + 20
    for _ in range(rng.integers(5, 9)):
        k = int(rng.uniform(0.2, 1.0) * (len(path) - 1))
        px, py = path[k]
        for _ in range(rng.integers(2, 4)):
            jasmine_flower(cell, rng, min(max(px + rng.normal(0, 26 * SS), m), C2 - m),
                           min(max(py + rng.normal(0, 26 * SS), m), C2 - m), rng.uniform(11, 15) * SS)


def pinnate(cell, rng, colors, n_pairs, leaflet, size, start, end):
    """A pinnate leaf: a rachis with leaflets in pairs and one at the tip."""
    path = curve(start, end, rng.uniform(-0.12, 0.12), 20)
    stem(cell, path, 1.8 * SS, colors[0] * 0.9)
    for i in range(n_pairs):
        k = int((i + 0.7) / (n_pairs + 0.5) * (len(path) - 1))
        px, py = path[k]
        qx, qy = path[min(k + 1, len(path) - 1)]
        d = math.atan2(qy - py, qx - px)
        for sgn in (-1, 1):
            a = d + sgn * rng.uniform(0.9, 1.2)
            ln = size * rng.uniform(0.85, 1.1)
            blade(cell, rng, leaflet, (px, py), (px + math.cos(a) * ln, py + math.sin(a) * ln), colors[rng.integers(len(colors))],
                  veins=4, curl=rng.uniform(-0.1, 0.1), height=0.7)
    ex, ey = path[-1]
    px, py = path[-3]
    d = math.atan2(ey - py, ex - px)
    blade(cell, rng, leaflet, (ex, ey), (ex + math.cos(d) * size, ey + math.sin(d) * size), colors[0], veins=4, height=0.7)


def raceme(cell, rng, top, length, colors):
    """A wisteria raceme hanging from `top`: pea flowers along a drooping axis, buds at the tip."""
    tx, ty = top
    path = curve((tx, ty), (tx + rng.normal(0, 12 * SS), ty + length), rng.uniform(-0.08, 0.08), 30)
    stem(cell, path, 1.5 * SS, srgb(110, 120, 70))
    n = 46
    for i in range(n):
        f = i / n
        k = int(f * (len(path) - 1))
        px, py = path[k]
        w = (1.0 - f * 0.75) * 30 * SS
        for _ in range(2):
            cx = px + rng.uniform(-w, w)
            cy = py + rng.uniform(-6, 6) * SS
            c = colors[rng.integers(len(colors))] * (1.0 + 0.35 * f)
            r = (9 - 4 * f) * SS
            # A pea flower: a round standard petal with a darker keel under it.
            disc(cell, cx, cy, r, np.clip(c, 0, 1), 0.7, ring=0.25)
            disc(cell, cx, cy + r * 0.5, r * 0.45, np.clip(c * 0.75, 0, 1), 0.8)


def grape_bunch(cell, rng):
    cx = C2 * 0.5
    top = MARGIN + 30
    stem(cell, curve((cx, MARGIN + 6), (cx + 10, top + 20), 0.1, 6), 2.5 * SS, srgb(110, 96, 60))
    for i in range(150):
        f = rng.uniform(0, 1) ** 0.8
        y = top + f * (C2 - top - MARGIN - 40)
        half = (1.0 - f) ** 0.7 * C2 * 0.3 + 12 * SS
        x = cx + rng.uniform(-half, half)
        c = srgb(62, 40, 74) * rng.uniform(0.8, 1.2)
        if rng.uniform() < 0.25:
            c = srgb(96, 118, 60) * rng.uniform(0.85, 1.1)
        disc(cell, x, y, rng.uniform(13, 17) * SS, np.clip(c, 0, 1), 1.0, ring=0.15)
        # The bloom on a grape: a pale highlight dot.
    for _ in range(40):
        disc(cell, rng.uniform(C2 * 0.25, C2 * 0.75), rng.uniform(top, C2 * 0.8), 2.5 * SS, srgb(170, 160, 180), 0.2)


def trumpet(cell, rng, base, ang, ln):
    """A trumpet vine flower: a tube that flares to a five-lobed mouth, orange shading to red."""
    bx, by = base
    tip = (bx + math.cos(ang) * ln, by + math.sin(ang) * ln)
    tube = lambda t: (0.09 + 0.05 * t + 0.22 * max(0.0, (t - 0.72) / 0.28) ** 1.5) if 0 <= t <= 1 else 0.0
    blade(cell, rng, tube, base, tip, TRUMPET[rng.integers(len(TRUMPET))], veins=0, vein=0.0, edge_dark=0.35,
          height=0.9, side_light=0.25)
    disc(cell, tip[0], tip[1], ln * 0.13, srgb(250, 170, 60), 0.6)
    disc(cell, tip[0], tip[1], ln * 0.05, srgb(190, 60, 30), 0.3)


def agave_blade(cell, rng, variegated=False):
    """An agave leaf filling the cell top (tip) to bottom (base): glaucous blue-grey, the teeth
    along its edge, the black terminal spine and the pale bud prints of the leaf it grew against."""
    cx = C2 * 0.5
    base = (cx, C2 - MARGIN)
    tip = (cx, MARGIN + 4)
    out = lambda t: 0.30 * (1.0 - max(t, 0.0) ** 1.6) * (1.0 + 0.08 * math.sin(t * 9.0)) if 0.0 <= t <= 1.0 else 0.0
    col = srgb(118, 146, 150)
    blade(cell, rng, out, base, tip, col, veins=0, vein=0.0, edge_dark=0.18, height=1.0, side_light=0.15, hue_jit=0.02)
    # Bud prints: faint ghost outlines of the next leaf's teeth, in rows across the blade.
    yy, xx = np.mgrid[0:C2, 0:C2].astype(np.float32)
    t = (C2 - MARGIN - yy) / (C2 - 2 * MARGIN)
    half = np.vectorize(out)(np.clip(t, 0, 1)) * (C2 - 2 * MARGIN)
    inside = (np.abs(xx - cx) < half * 0.92) & (t > 0) & (t < 1)
    prints = np.zeros_like(t)
    for k in range(3):
        tk = 0.35 + 0.2 * k
        wk = np.vectorize(out)(tk) * (C2 - 2 * MARGIN) * 0.75
        d = np.abs(np.hypot((xx - cx) / max(wk, 1), (t - tk) * 6.0) - 1.0)
        prints += np.exp(-(d / 0.03) ** 2) * 0.35
    sel = inside & (cell.a > 0.5)
    cell.rgb[sel] = cell.rgb[sel] * (1.0 + prints[sel, None] * 0.6)
    if variegated:
        band = np.clip(1.0 - np.abs(np.abs(xx - cx) / np.maximum(half, 1) - 0.8) / 0.12, 0, 1)
        sel2 = inside & (cell.a > 0.5)
        cell.rgb[sel2] = cell.rgb[sel2] * (1 - band[sel2, None]) + srgb(214, 200, 120) * band[sel2, None]
    # Teeth: little dark hooked thorns along both edges, and the terminal spine.
    for k in range(18):
        tt = 0.08 + k * 0.05
        w = out(tt) * (C2 - 2 * MARGIN)
        y = C2 - MARGIN - tt * (C2 - 2 * MARGIN)
        for sgn in (-1, 1):
            x = cx + sgn * w
            blade(cell, rng, ovate(0.35, 0.5, 0.6), (x - sgn * 3 * SS, y), (x + sgn * 10 * SS, y - 6 * SS),
                  srgb(70, 46, 34), veins=0, vein=0.0, height=0.4, edge_dark=0.0)
    blade(cell, rng, lance(0.12), (cx, MARGIN + 40 * SS), (cx, MARGIN + 2), srgb(40, 28, 22), veins=0, vein=0.0, height=0.5)


def aloe_blade(cell, rng):
    cx = C2 * 0.5
    out = lambda t: 0.26 * (1.0 - max(t, 0.0) ** 1.3) if 0.0 <= t <= 1.0 else 0.0
    blade(cell, rng, out, (cx, C2 - MARGIN), (cx, MARGIN + 4), srgb(96, 126, 82), veins=0, vein=0.0, edge_dark=0.3,
          height=1.0, spots=60, side_light=0.15)
    for k in range(22):
        tt = 0.05 + k * 0.042
        w = out(tt) * (C2 - 2 * MARGIN)
        y = C2 - MARGIN - tt * (C2 - 2 * MARGIN)
        for sgn in (-1, 1):
            x = cx + sgn * w
            blade(cell, rng, ovate(0.4, 0.5, 0.6), (x - sgn * 2 * SS, y), (x + sgn * 7 * SS, y - 4 * SS),
                  srgb(196, 150, 120), veins=0, vein=0.0, height=0.3, edge_dark=0.0)


def poker_spike(cell, rng):
    """Red-hot poker: a stalk and a dense spike of drooping tubes, coral-red buds at the top fading
    through orange to yellow open flowers below."""
    cx = C2 * 0.5
    stem(cell, [(cx, C2 - MARGIN), (cx, C2 * 0.45)], 4 * SS, srgb(92, 120, 58))
    top, bottom = MARGIN + 10, C2 * 0.58
    for i in range(150):
        f = rng.uniform(0, 1)
        y = top + f * (bottom - top)
        half = (0.55 + 0.45 * math.sin(math.pi * min(f * 1.3, 1.0))) * 34 * SS
        x = cx + rng.uniform(-half, half)
        c = np.array([0.86, 0.22 + 0.55 * f, 0.10 + 0.12 * f], np.float32)
        ang = math.pi * 0.5 + (x - cx) / (half + 1) * 0.5
        ln = (26 - 6 * f) * SS
        blade(cell, rng, lance(0.16), (x, y), (x + math.cos(ang) * ln * 0.4, y + math.sin(ang) * ln), c,
              veins=0, vein=0.0, height=0.7, edge_dark=0.3, hue_jit=0.04)


def lavender(cell, rng):
    m = MARGIN + 6
    for _ in range(30):
        bx = C2 * 0.5 + rng.normal(0, C2 * 0.08)
        tx = bx + rng.normal(0, C2 * 0.22)
        ty = m + rng.uniform(0, C2 * 0.35)
        path = curve((bx, C2 - m), (tx, ty), rng.uniform(-0.1, 0.1), 10)
        stem(cell, path, 1.4 * SS, srgb(120, 134, 104))
        # The spike: whorls of tiny violet flowers on the stem's last fifth.
        for k in range(10):
            px, py = path[max(0, len(path) - 1 - k // 4)]
            disc(cell, px + rng.normal(0, 3 * SS), py + k * 4 * SS * 0.6 + rng.normal(0, 2 * SS), rng.uniform(4, 6) * SS,
                 np.clip(srgb(122, 96, 170) * rng.uniform(0.85, 1.15), 0, 1), 0.6)
    for _ in range(40):
        bx = C2 * 0.5 + rng.normal(0, C2 * 0.15)
        a = -math.pi * 0.5 + rng.normal(0, 0.6)
        ln = rng.uniform(40, 80) * SS
        y0 = C2 - m - rng.uniform(0, 40) * SS
        blade(cell, rng, lance(0.06), (bx, y0), (bx + math.cos(a) * ln, y0 + math.sin(a) * ln), srgb(132, 148, 120),
              veins=0, vein=0.0, height=0.4)


def lantana(cell, rng, palette):
    m = MARGIN + 6
    for _ in range(26):
        cx, cy = rng.uniform(m + 20, C2 - m - 20), rng.uniform(m + 40, C2 - m - 10)
        a = rng.uniform(0, math.tau)
        ln = rng.uniform(0.12, 0.17) * C2
        blade(cell, rng, ovate(0.36, 0.8, 0.3), (cx, cy), (min(max(cx + math.cos(a) * ln, m), C2 - m), min(max(cy + math.sin(a) * ln, m), C2 - m)),
              srgb(58, 88, 40), veins=5, height=0.7)
    for _ in range(9):
        hx, hy = rng.uniform(m + 40, C2 - m - 40), rng.uniform(m + 40, C2 * 0.75)
        r = rng.uniform(26, 34) * SS
        # A head: florets, the outer ring one colour, the inner another.
        for k in range(26):
            rr = math.sqrt(rng.uniform(0, 1)) * r
            a = rng.uniform(0, math.tau)
            c = palette[0] if rr > r * 0.55 else palette[1]
            disc(cell, hx + math.cos(a) * rr, hy + math.sin(a) * rr, rng.uniform(6, 8) * SS, np.clip(c * rng.uniform(0.9, 1.1), 0, 1), 0.6)


def straps(cell, rng):
    m = MARGIN + 4
    for _ in range(14):
        bx = C2 * 0.5 + rng.normal(0, C2 * 0.06)
        a = -math.pi * 0.5 + rng.normal(0, 0.5)
        ln = rng.uniform(0.6, 0.85) * (C2 - 2 * m)
        tip = (min(max(bx + math.cos(a) * ln, m), C2 - m), max(C2 - m + math.sin(a) * ln, m))
        blade(cell, rng, strap(0.035, 0.9), (bx, C2 - m), tip, srgb(76, 104, 62) * rng.uniform(0.85, 1.1), veins=0,
              vein=0.4, curl=rng.uniform(-0.25, 0.25), height=0.6)


def woody(cell, rng):
    """A few old stems twisting up together (a vine's trunk), with side shoots."""
    m = MARGIN + 4
    for k in range(3):
        x0 = C2 * (0.4 + 0.1 * k) + rng.uniform(-10, 10) * SS
        pts = []
        for i in range(25):
            t = i / 24
            pts.append((x0 + math.sin(t * 7.0 + k * 2.0) * 14 * SS, C2 - m - t * (C2 - 2 * m)))
        stem(cell, pts, rng.uniform(5, 8) * SS, srgb(104, 84, 64) * rng.uniform(0.8, 1.05), height=1.0)
    for _ in range(4):
        y = rng.uniform(C2 * 0.2, C2 * 0.8)
        x = C2 * 0.5
        stem(cell, curve((x, y), (x + rng.choice([-1, 1]) * rng.uniform(40, 90) * SS, y - rng.uniform(30, 70) * SS), 0.2, 8),
             2.2 * SS, srgb(110, 92, 70))


def palm_leaf(lobes, depth, teeth=0.0):
    f = lambda cell, rng, base, tip, color: palmate(cell, rng, base, tip, color, lobes, depth, True, 0.9, teeth)
    f.palmate = True
    return f


def mass(cell, rng, outline, colors, size, n, flowers=None, palm=False, nflowers=(10, 16)):
    """A dense mass of foliage filling the cell (the inside of a plant), leaves every way, with
    `flowers(cell, rng, cx, cy)` dropped over it."""
    m = MARGIN + 4
    for _ in range(4):
        a = (rng.uniform(m, C2 - m), rng.uniform(m, C2 - m))
        b = (rng.uniform(m, C2 - m), rng.uniform(m, C2 - m))
        stem(cell, curve(a, b, rng.uniform(-0.3, 0.3), 16), 2.0 * SS, STEM)
    for _ in range(n):
        cx, cy = rng.uniform(m + 6, C2 - m - 6), rng.uniform(m + 6, C2 - m - 6)
        # Fewer near the corners: a mass card is round-ish, so its edge is not a square.
        if math.hypot(cx - C2 / 2, cy - C2 / 2) > C2 * 0.5 * rng.uniform(0.82, 1.05):
            continue
        ang = rng.uniform(0, math.tau)
        ln = C2 * rng.uniform(*size)
        tip = (min(max(cx + math.cos(ang) * ln, m), C2 - m), min(max(cy + math.sin(ang) * ln, m), C2 - m))
        col = colors[rng.integers(len(colors))] * rng.uniform(0.8, 1.12)
        if palm:
            palmate(cell, rng, (cx, cy), tip, np.clip(col, 0, 1), 5, 0.45, True, 0.9, 0.05)
        else:
            blade(cell, rng, outline, (cx, cy), tip, np.clip(col, 0, 1), veins=4, curl=rng.uniform(-0.15, 0.15), height=0.8)
    if flowers:
        for _ in range(rng.integers(*nflowers)):
            cx, cy = rng.uniform(m + 30, C2 - m - 30), rng.uniform(m + 30, C2 - m - 30)
            if math.hypot(cx - C2 / 2, cy - C2 / 2) < C2 * 0.42:
                flowers(cell, rng, cx, cy)


def paint(index, rng):
    c = Cell()
    if index < 4:
        sprig(c, rng, rng.integers(7, 10), palm_leaf(5 if index % 2 else 3, 0.62), IVY, (0.2, 0.28), veins=4, vein_light=True)
    elif index < 6:
        mat(c, rng, 95, palm_leaf(5 if index % 2 else 3, 0.62), IVY, (0.10, 0.15), veins=3, vein_light=True)
    elif index < 8:
        mat(c, rng, 330, heart(0.42), FIG, (0.05, 0.075), veins=2)
    elif index < 10:
        sprig(c, rng, rng.integers(8, 11), ovate(0.36), BOUG_LEAF, (0.18, 0.26), veins=5)
    elif index < 16:
        colors = MAGENTA if index < 12 else ORANGE if index < 14 else WHITE
        sprig(c, rng, rng.integers(6, 9), ovate(0.36), BOUG_LEAF, (0.15, 0.22), veins=5, flowers=boug_flowers(colors))
    elif index < 18:
        sprig(c, rng, rng.integers(10, 14), ovate(0.30, 0.8, 0.2), JASMINE, (0.16, 0.22), veins=4)
    elif index < 20:
        sprig(c, rng, rng.integers(9, 12), ovate(0.30, 0.8, 0.2), JASMINE, (0.15, 0.2), veins=4, flowers=jasmine_flowers)
    elif index < 22:
        m = MARGIN + 6
        for k in range(2):
            pinnate(c, rng, WIST_LEAF, 5, ovate(0.36, 0.8, 0.3), C2 * 0.12, (m + k * C2 * 0.3, C2 - m), (C2 * 0.6 + k * C2 * 0.15, m + 10))
    elif index < 24:
        for k in range(2):
            raceme(c, rng, (C2 * (0.32 + 0.36 * k), MARGIN + 6), C2 - 2 * MARGIN - 20 - k * 30 * SS, WIST_FLOWER)
    elif index < 26:
        sprig(c, rng, 3, palm_leaf(5, 0.42, 0.05), GRAPE_LEAF, (0.4, 0.48), veins=5, vein_light=True)
    elif index == 26:
        grape_bunch(c, rng)
    elif index < 29:
        m = MARGIN + 6
        for k in range(3):
            pinnate(c, rng, TRUMPET_LEAF, 5, lance(0.3), C2 * 0.15, (m + 20 + k * C2 * 0.25, C2 - m), (C2 * 0.4 + k * C2 * 0.2, m + 10))
    elif index < 31:
        path = sprig(c, rng, 6, lance(0.22), TRUMPET_LEAF, (0.15, 0.2), veins=4)
        for _ in range(rng.integers(5, 8)):
            k = int(rng.uniform(0.4, 1.0) * (len(path) - 1))
            px, py = path[k]
            trumpet(c, rng, (px, py), rng.uniform(-math.pi, 0), C2 * rng.uniform(0.2, 0.26))
    elif index == 31:
        woody(c, rng)
    elif index == 32:
        agave_blade(c, rng, False)
    elif index == 33:
        agave_blade(c, rng, True)
    elif index == 34:
        aloe_blade(c, rng)
    elif index == 35:
        poker_spike(c, rng)
    elif index == 36:
        lavender(c, rng)
    elif index == 37:
        lantana(c, rng, [srgb(240, 150, 40), srgb(250, 220, 70)])
    elif index == 38:
        lantana(c, rng, [srgb(226, 90, 140), srgb(250, 210, 90)])
    elif index == 39:
        straps(c, rng)
    elif index == 40:
        mass(c, rng, ovate(0.36), BOUG_LEAF, (0.08, 0.13), 260)
    elif index < 44:
        colors = [MAGENTA, ORANGE, WHITE][index - 41]
        def fl(cell, rng, cx, cy, colors=colors):
            for _ in range(rng.integers(2, 5)):
                bracts(cell, rng, cx + rng.normal(0, 12 * SS), cy + rng.normal(0, 12 * SS), rng.uniform(16, 24) * SS, colors)
        mass(c, rng, ovate(0.36), BOUG_LEAF, (0.08, 0.13), 200, fl, nflowers=(20, 28))
    elif index == 44:
        def fl(cell, rng, cx, cy):
            for _ in range(rng.integers(1, 3)):
                jasmine_flower(cell, rng, cx + rng.normal(0, 10 * SS), cy + rng.normal(0, 10 * SS), rng.uniform(10, 13) * SS)
        mass(c, rng, ovate(0.30, 0.8, 0.2), JASMINE, (0.07, 0.1), 300, fl)
    elif index == 45:
        mass(c, rng, ovate(0.36, 0.8, 0.3), WIST_LEAF, (0.06, 0.1), 300)
    elif index == 46:
        mass(c, rng, None, GRAPE_LEAF, (0.14, 0.2), 60, palm=True)
    elif index == 47:
        def fl(cell, rng, cx, cy):
            if rng.uniform() < 0.5:
                trumpet(cell, rng, (cx, cy), rng.uniform(-math.pi, 0), C2 * rng.uniform(0.14, 0.18))
        mass(c, rng, lance(0.24), TRUMPET_LEAF, (0.07, 0.11), 280, fl)
    return c


def finish(c):
    """Downsamples a painted cell to CELL px (premultiplied) and works out its normal."""
    a = c.a.reshape(CELL, SS, CELL, SS).mean(axis=(1, 3))
    rgb_p = (c.rgb * c.a[..., None]).reshape(CELL, SS, CELL, SS, 3).mean(axis=(1, 3))
    rgb = np.where(a[..., None] > 1e-4, rgb_p / np.maximum(a[..., None], 1e-4), 0.0)
    h = c.h.reshape(CELL, SS, CELL, SS).mean(axis=(1, 3))
    # Soften the height a touch so the normal is not aliased.
    hp = np.pad(h, 1, mode="edge")
    h = (hp[:-2, 1:-1] + hp[2:, 1:-1] + hp[1:-1, :-2] + hp[1:-1, 2:] + 4 * h) / 8
    gy, gx = np.gradient(h)
    k = 3.0
    n = np.stack([-gx * k, gy * k, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    # Outside the leaves the normal is flat, so the mips do not tilt a leaf's edge.
    n = np.where(a[..., None] > 0.02, n, np.array([0.0, 0.0, 1.0]))
    return rgb, a, n


def bleed(rgb, a):
    """Spreads each cell's leaf colour into its transparent texels, so mips have no dark fringe."""
    out = rgb.copy()
    known = a > 0.02
    for _ in range(24):
        if known.all():
            break
        acc = np.zeros_like(out)
        cnt = np.zeros(a.shape, np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            sh = np.roll(np.roll(out * known[..., None], dy, 0), dx, 1)
            kn = np.roll(np.roll(known, dy, 0), dx, 1)
            acc += sh
            cnt += kn
        new = (~known) & (cnt > 0)
        out[new] = acc[new] / cnt[new, None]
        known = known | new
    return out


def main():
    rng0 = np.random.default_rng(20261005)
    alb = np.zeros((ROWS * CELL, COLS * CELL, 4), np.float32)
    nrm = np.zeros((ROWS * CELL, COLS * CELL, 3), np.float32)
    nrm[..., 2] = 1.0
    for index in range(COLS * ROWS):
        rng = np.random.default_rng(int(rng0.integers(1 << 30)))
        rgb, a, n = finish(paint(index, rng))
        rgb = bleed(rgb, a)
        r, col = divmod(index, COLS)
        alb[r * CELL:(r + 1) * CELL, col * CELL:(col + 1) * CELL, :3] = rgb
        alb[r * CELL:(r + 1) * CELL, col * CELL:(col + 1) * CELL, 3] = a
        nrm[r * CELL:(r + 1) * CELL, col * CELL:(col + 1) * CELL] = n
        print("cell %2d  cover %.2f" % (index, float(a.mean())))
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray((np.clip(alb, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, "climbers_albedo.png"), optimize=True)
    Image.fromarray((np.clip(nrm * 0.5 + 0.5, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(os.path.join(OUT, "climbers_normal.png"), optimize=True)
    if "--preview" in sys.argv:
        bg = np.ones_like(alb[..., :3]) * np.array([0.82, 0.78, 0.70])
        pv = alb[..., :3] * alb[..., 3:] + bg * (1 - alb[..., 3:])
        os.makedirs(os.path.join(os.path.dirname(__file__), "..", "build"), exist_ok=True)
        Image.fromarray((pv * 255).astype(np.uint8)).save(os.path.join(os.path.dirname(__file__), "..", "build", "climbers_preview.png"))


if __name__ == "__main__":
    main()
