#!/usr/bin/env python3
"""Paints the city birds' plumage atlases (original procedural art, no source photos).

    python3 tools/birds/make_bird_textures.py [pigeon gull crow sparrow]

Writes, per species, into assets/textures/birds/:
  <species>_albedo.png  RGBA: plumage colour, alpha = the feathers' cut-out
  <species>_normal.png  RGB:  OpenGL-convention normal map (rachis, barbs, contour-feather scallops)
  <species>_mask.png    RGB:  R iridescence (pigeon neck, crow gloss), G morph region (the grey a
                              pigeon's colour morph replaces), B roughness
Then run `godot --headless --path . --import` and `python3 tools/fix_texture_imports.py
assets/textures/birds` and commit the PNGs and their .import files.

The atlas layout is a contract with scripts/world/bird_mesh.gd (BirdMesh.SLOTS and the body /
eye / leg / far-wing regions); change one, change both. 1024 px square:
  body      x 0..512,   y 0..1024  u = round the body from the dorsal midline (0) to the ventral
                                   (512), mirrored left / right; v = along the spine, beak tip at
                                   the top (y 0), tail base at the bottom. Landmarks along the
                                   spine are fixed fractions (S_* below), so every species' loft
                                   maps its own neck, head and beak onto the same rows.
  feathers  x 512..1024 one 64 px column per feather kind, drawn base down, tip up:
            row A y 0..448: P_OUT P_MID P_IN S_OUT S_IN TERT TAIL_OUT TAIL_IN
            row B y 448..704: COV_G COV_M P_COV ALULA
  far wing  x 512..1024, y 704..960: a whole left wing seen from above in (span, chord)
            coordinates (span 0 at the shoulder on the left, chord 0 the leading edge at the top);
            the far LOD's wing quads and the near wing's covert sheet both read it
  eye       x 512..576, y 960..1024; legs x 576..640, y 960..1024
"""
import os
import sys

import numpy as np
from PIL import Image

N = 1024
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "textures", "birds")

# Spine landmarks (0 tail base .. 1 beak tip), shared with BirdMesh.S_*.
S_NECK = 0.58
S_HEAD = 0.74
S_EYE = 0.84
S_BEAK = 0.915

# Feather slots: name -> (x0, y0, w, h) in pixels. Mirrored by BirdMesh.SLOTS.
SLOTS = {
    "P_OUT": (512, 0, 64, 448), "P_MID": (576, 0, 64, 448), "P_IN": (640, 0, 64, 448),
    "S_OUT": (704, 0, 64, 448), "S_IN": (768, 0, 64, 448), "TERT": (832, 0, 64, 448),
    "TAIL_OUT": (896, 0, 64, 448), "TAIL_IN": (960, 0, 64, 448),
    "COV_G": (512, 448, 64, 256), "COV_M": (576, 448, 64, 256), "P_COV": (640, 448, 64, 256),
    "ALULA": (704, 448, 64, 256),
}
# The covert sheet over the near wing's flight feathers: (span, chord) like the far wing, its
# trailing edge cut into the rounded tips of the greater coverts.
COV_SHEET = (768, 448, 256, 256)
FAR_WING = (512, 704, 512, 256)
EYE = (512, 960, 64, 64)
LEG = (576, 960, 64, 64)


def srgb(*c):
    return np.array(c, dtype=np.float32)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def band(x, a, b, soft=0.02):
    return smooth(a - soft, a + soft, x) * (1.0 - smooth(b - soft, b + soft, x))


class Noise:
    """Value noise on a lattice, numpy vectorised, seeded."""

    def __init__(self, seed):
        self.rng = np.random.default_rng(seed)
        self.table = self.rng.random((256, 256)).astype(np.float32)

    def __call__(self, x, y):
        xi = np.floor(x).astype(np.int64)
        yi = np.floor(y).astype(np.int64)
        fx = x - xi
        fy = y - yi
        fx = fx * fx * (3 - 2 * fx)
        fy = fy * fy * (3 - 2 * fy)
        t = self.table
        a = t[yi % 256, xi % 256]
        b = t[yi % 256, (xi + 1) % 256]
        c = t[(yi + 1) % 256, xi % 256]
        d = t[(yi + 1) % 256, (xi + 1) % 256]
        return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy

    def fbm(self, x, y, octaves=4):
        v = 0.0
        amp = 0.5
        for i in range(octaves):
            v = v + amp * self(x * (2 ** i) + 17.3 * i, y * (2 ** i) + 5.1 * i)
            amp *= 0.5
        return v


# --- Species ------------------------------------------------------------------------------
# Body colour: f(a, s, n) -> (rgb[h, w, 3], irid[h, w], morph[h, w], rough[h, w]).
# a 0 dorsal .. 1 ventral midline, s 0 tail base .. 1 beak tip, n noise in 0..1.

def pigeon_body(a, s, n):
    grey = srgb(0.54, 0.56, 0.61)
    belly = srgb(0.44, 0.46, 0.52)
    rump = srgb(0.72, 0.73, 0.76)
    neck = srgb(0.30, 0.32, 0.38)
    head = srgb(0.40, 0.42, 0.48)
    beak = srgb(0.16, 0.15, 0.16)
    cere = srgb(0.90, 0.89, 0.86)
    col = grey + (belly - grey) * smooth(0.45, 0.9, a)[..., None]
    col = col + (rump - col) * (band(s, 0.02, 0.2, 0.05) * (1 - smooth(0.25, 0.5, a)))[..., None]
    nk = band(s, S_NECK - 0.06, S_HEAD + 0.01, 0.035)
    col = col + (neck - col) * nk[..., None]
    hd = smooth(S_HEAD - 0.01, S_HEAD + 0.03, s)
    col = col + (head - col) * hd[..., None]
    bk = smooth(S_BEAK - 0.004, S_BEAK + 0.004, s)
    col = col + (beak - col) * bk[..., None]
    cr = band(s, S_BEAK, S_BEAK + 0.03, 0.006) * (1 - smooth(0.3, 0.45, a))
    col = col + (cere - col) * cr[..., None]
    col = col * (0.94 + 0.12 * n)[..., None]
    # The sheen is on the sides and front of the neck, little on the nape.
    irid = nk * (1 - bk) * (0.35 + 0.65 * smooth(0.15, 0.55, a)) * (1 - smooth(0.85, 1.0, a) * 0.5)
    morph = (1 - bk) * (1 - cr)
    rough = 0.72 - 0.3 * bk
    return col, irid, morph, rough


def gull_body(a, s, n):
    white = srgb(0.93, 0.93, 0.91)
    mantle = srgb(0.34, 0.36, 0.40)
    beak = srgb(0.93, 0.78, 0.26)
    red = srgb(0.80, 0.18, 0.12)
    col = np.broadcast_to(white, a.shape + (3,)).copy()
    mt = band(s, 0.12, S_NECK - 0.02, 0.05) * (1 - smooth(0.22, 0.40, a))
    col = col + (mantle - col) * mt[..., None]
    bk = smooth(S_BEAK - 0.004, S_BEAK + 0.004, s)
    col = col + (beak - col) * bk[..., None]
    spot = band(s, 0.955, 0.985, 0.006) * smooth(0.62, 0.75, a)
    col = col + (red - col) * spot[..., None]
    col = col * (0.95 + 0.08 * n)[..., None]
    return col, np.zeros_like(a), np.zeros_like(a), 0.74 - 0.35 * bk


def crow_body(a, s, n):
    black = srgb(0.075, 0.075, 0.085)
    beak = srgb(0.05, 0.05, 0.055)
    bk = smooth(S_BEAK - 0.004, S_BEAK + 0.004, s)
    col = black + (beak - black) * bk[..., None]
    col = col * (0.85 + 0.3 * n)[..., None]
    irid = (0.55 - 0.2 * smooth(0.5, 1.0, a)) * (1 - bk)
    return col, irid, np.zeros_like(a), 0.5 - 0.1 * bk


def sparrow_body(a, s, n, streak):
    back = srgb(0.52, 0.36, 0.22)
    streakc = srgb(0.13, 0.09, 0.06)
    belly = srgb(0.70, 0.70, 0.68)
    crown = srgb(0.48, 0.48, 0.48)
    nape = srgb(0.50, 0.28, 0.14)
    cheek = srgb(0.82, 0.82, 0.80)
    bib = srgb(0.08, 0.07, 0.07)
    beak = srgb(0.18, 0.16, 0.16)
    col = back + (belly - back) * smooth(0.35, 0.6, a)[..., None]
    st = streak * (1 - smooth(0.25, 0.4, a)) * band(s, 0.1, S_NECK, 0.04)
    col = col + (streakc - col) * st[..., None]
    nk = band(s, S_NECK - 0.03, S_HEAD + 0.06, 0.03) * (1 - smooth(0.3, 0.5, a))
    col = col + (nape - col) * nk[..., None]
    cr = smooth(S_HEAD + 0.02, S_HEAD + 0.06, s) * (1 - smooth(0.25, 0.4, a))
    col = col + (crown - col) * cr[..., None]
    ch = band(s, S_HEAD - 0.02, S_BEAK, 0.02) * band(a, 0.4, 0.62, 0.05)
    col = col + (cheek - col) * ch[..., None]
    bb = band(s, S_NECK - 0.05, S_BEAK, 0.03) * smooth(0.62, 0.72, a)
    col = col + (bib - col) * bb[..., None]
    bk = smooth(S_BEAK - 0.004, S_BEAK + 0.004, s)
    col = col + (beak - col) * bk[..., None]
    col = col * (0.92 + 0.14 * n)[..., None]
    return col, np.zeros_like(a), np.zeros_like(a), 0.78 - 0.35 * bk


# Feather colours: f(t, dn, n) -> rgb; t 0 base .. 1 tip, dn signed distance from the shaft over
# the vane's width (-1 outer edge .. +1 inner edge), n noise.

def lerp_c(c0, c1, k):
    return c0 + (c1 - c0) * k[..., None]


def pigeon_feather(kind):
    grey = srgb(0.56, 0.58, 0.63)
    dark = srgb(0.17, 0.17, 0.19)
    black = srgb(0.07, 0.07, 0.08)

    def f(t, dn, n):
        c = np.broadcast_to(grey, t.shape + (3,)).copy()
        if kind == "P_OUT":
            c = lerp_c(c, dark, smooth(0.35, 0.6, t))
        elif kind == "P_MID":
            c = lerp_c(c, dark, smooth(0.55, 0.75, t))
        elif kind == "P_IN":
            c = lerp_c(c, dark, smooth(0.72, 0.9, t) * 0.8)
        elif kind in ("S_OUT", "S_IN"):
            c = lerp_c(c, black, band(t, 0.6, 0.8, 0.03))
            c = lerp_c(c, dark, smooth(0.9, 1.0, t) * 0.6)
        elif kind == "TERT":
            c = lerp_c(c, black, band(t, 0.52, 0.74, 0.03))
        elif kind in ("TAIL_OUT", "TAIL_IN"):
            c = lerp_c(c, srgb(0.5, 0.52, 0.58), smooth(0.2, 0.6, t))
            c = lerp_c(c, black, band(t, 0.76, 0.95, 0.02))
            if kind == "TAIL_OUT":
                c = lerp_c(c, srgb(0.9, 0.9, 0.9), (1 - smooth(-0.75, -0.55, dn)) * (1 - smooth(0.55, 0.7, t)))
        elif kind == "COV_G":
            c = lerp_c(c, black, band(t, 0.62, 0.9, 0.03))
        elif kind == "P_COV" or kind == "ALULA":
            c = lerp_c(c, srgb(0.4, 0.41, 0.46), smooth(0.3, 0.8, t))
        return c
    return f


def gull_feather(kind):
    slate = srgb(0.34, 0.36, 0.40)
    black = srgb(0.06, 0.06, 0.065)
    white = srgb(0.93, 0.93, 0.91)

    def f(t, dn, n):
        c = np.broadcast_to(slate, t.shape + (3,)).copy()
        if kind == "P_OUT":
            c = lerp_c(c, black, smooth(0.4, 0.5, t))
            mirror = np.clip(1 - ((t - 0.84) / 0.06) ** 2 - ((dn - 0.25) / 0.6) ** 2, 0, 1)
            c = lerp_c(c, white, smooth(0.0, 0.25, mirror))
            c = lerp_c(c, white, smooth(0.965, 0.985, t))
        elif kind == "P_MID":
            c = lerp_c(c, black, smooth(0.58, 0.66, t))
            c = lerp_c(c, white, smooth(0.94, 0.97, t))
        elif kind == "P_IN":
            c = lerp_c(c, black, band(t, 0.78, 0.9, 0.02) * 0.9)
            c = lerp_c(c, white, smooth(0.9, 0.93, t))
        elif kind in ("S_OUT", "S_IN", "TERT"):
            c = lerp_c(c, white, smooth(0.8 if kind == "TERT" else 0.84, 0.88, t))
        elif kind in ("TAIL_OUT", "TAIL_IN"):
            c = np.broadcast_to(white, t.shape + (3,)).copy()
        elif kind == "ALULA":
            c = lerp_c(c, black, smooth(0.6, 0.8, t) * 0.5)
        return c
    return f


def crow_feather(kind):
    black = srgb(0.07, 0.07, 0.08)

    def f(t, dn, n):
        c = np.broadcast_to(black, t.shape + (3,)).copy()
        return c * (0.9 + 0.2 * smooth(0.0, 1.0, t))[..., None]
    return f


def sparrow_feather(kind):
    brown = srgb(0.36, 0.26, 0.17)
    dark = srgb(0.14, 0.10, 0.07)
    rufous = srgb(0.62, 0.40, 0.20)
    buff = srgb(0.76, 0.64, 0.46)
    white = srgb(0.88, 0.87, 0.82)

    def f(t, dn, n):
        c = np.broadcast_to(brown, t.shape + (3,)).copy()
        edge = smooth(0.45, 0.75, np.abs(dn))
        if kind in ("P_OUT", "P_MID", "P_IN"):
            c = lerp_c(c, dark, 1 - smooth(-0.3, 0.0, dn) * 0.0 - 0.3)
            c = lerp_c(c, buff, (1 - smooth(-0.55, -0.35, dn)) * 0.8)
        elif kind in ("S_OUT", "S_IN"):
            c = lerp_c(c, dark, 0.5 * np.ones_like(t))
            c = lerp_c(c, rufous, (1 - smooth(-0.6, -0.3, dn)))
        elif kind == "TERT" or kind == "COV_G":
            c = lerp_c(dark * np.ones_like(c), rufous, edge)
            c = lerp_c(c, buff, smooth(0.85, 0.95, t) * edge)
        elif kind == "COV_M":
            c = lerp_c(c, dark, 0.4 * np.ones_like(t))
            c = lerp_c(c, white, smooth(0.7, 0.78, t))
        elif kind in ("TAIL_OUT", "TAIL_IN"):
            c = lerp_c(c, buff, edge * 0.5)
        return c
    return f


SPECIES = {
    "pigeon": {
        "body": pigeon_body, "feather": pigeon_feather, "seed": 11,
        "eye": (srgb(0.92, 0.42, 0.10), srgb(0.62, 0.64, 0.66), 0.62),  # iris, orbital ring, pupil share
        "leg": srgb(0.78, 0.30, 0.28), "far_rough": 0.68, "feather_rough": 0.66,
        "irid_feather": 0.0, "morph_feather": 1.0,
    },
    "gull": {
        "body": gull_body, "feather": gull_feather, "seed": 23,
        "eye": (srgb(0.93, 0.86, 0.55), srgb(0.88, 0.62, 0.22), 0.35),
        "leg": srgb(0.86, 0.62, 0.58), "far_rough": 0.7, "feather_rough": 0.7,
        "irid_feather": 0.0, "morph_feather": 0.0,
    },
    "crow": {
        "body": crow_body, "feather": crow_feather, "seed": 37,
        "eye": (srgb(0.12, 0.09, 0.07), srgb(0.07, 0.07, 0.08), 0.55),
        "leg": srgb(0.07, 0.07, 0.075), "far_rough": 0.48, "feather_rough": 0.42,
        "irid_feather": 0.75, "morph_feather": 0.0,
    },
    "sparrow": {
        "body": None, "feather": sparrow_feather, "seed": 53,
        "eye": (srgb(0.10, 0.08, 0.06), srgb(0.30, 0.25, 0.22), 0.6),
        "leg": srgb(0.64, 0.50, 0.42), "far_rough": 0.75, "feather_rough": 0.72,
        "irid_feather": 0.0, "morph_feather": 0.0,
    },
}

# Feather shapes: (outer vane width, inner vane width, tip start, tip shape: 0 round .. 1 pointed,
# shaft curve, emargination) as fractions of the slot's half width / length.
SHAPES = {
    "P_OUT": (0.22, 0.62, 0.72, 0.75, 0.10, 0.55),
    "P_MID": (0.30, 0.68, 0.78, 0.5, 0.07, 0.35),
    "P_IN": (0.40, 0.74, 0.84, 0.25, 0.05, 0.0),
    "S_OUT": (0.55, 0.80, 0.88, 0.05, 0.03, 0.0),
    "S_IN": (0.62, 0.82, 0.86, 0.0, 0.02, 0.0),
    "TERT": (0.66, 0.82, 0.80, 0.0, 0.02, 0.0),
    "TAIL_OUT": (0.42, 0.80, 0.86, 0.1, 0.04, 0.0),
    "TAIL_IN": (0.74, 0.80, 0.86, 0.05, 0.0, 0.0),
    "COV_G": (0.66, 0.82, 0.66, 0.0, 0.02, 0.0),
    "COV_M": (0.74, 0.80, 0.55, 0.0, 0.0, 0.0),
    "P_COV": (0.50, 0.75, 0.70, 0.25, 0.04, 0.0),
    "ALULA": (0.40, 0.70, 0.70, 0.4, 0.06, 0.0),
}


def paint_feather(kind, spec, alb, hgt, msk, noise):
    x0, y0, w, h = SLOTS[kind]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    t = 1.0 - (yy + 0.5) / h
    xc = (xx + 0.5) / w * 2.0 - 1.0
    wo, wi, tip0, pointed, curve, emarg = SHAPES[kind]
    shaft = -0.05 + curve * t * t
    d = xc - shaft
    # Vane half widths along the feather: in from the base, out to the tip.
    rise = smooth(0.0, 0.14, t)
    tt = np.clip((t - tip0) / (1.0 - tip0), 0.0, 1.0)
    round_tip = np.sqrt(np.clip(1.0 - tt * tt, 0.0, 1.0))
    point_tip = 1.0 - tt
    tipf = round_tip * (1 - pointed) + point_tip * pointed
    outer = wo * rise * tipf * (1.0 - emarg * smooth(0.55, 0.75, t) * 0.6)
    inner = wi * rise * tipf
    vane = np.where(d < 0, outer, inner)
    dn = np.where(d < 0, d / np.maximum(outer, 1e-4), d / np.maximum(inner, 1e-4))
    px = 2.0 / w  # one pixel in xc units
    alpha = np.clip((vane - np.abs(d)) / px, 0.0, 1.0)
    alpha *= (t > 0.012) * (t < 0.995)
    # Barbs: lines leaning toward the tip, a few vane splits where they part.
    length_px = h
    barb = (t * length_px - np.abs(d) * (w * 0.5) * 1.6) / 3.1
    stripes = 0.5 + 0.5 * np.sin(barb * 2.0 * np.pi)
    split_n = noise(barb * 0.12, np.sign(d) * 3.0 + SLOTS[kind][0] * 0.01)
    split = (np.abs(dn) > 0.35 + 0.65 * smooth(0.55, 0.9, split_n)) & (split_n > 0.72)
    alpha = alpha * np.where(split & (np.abs(barb - np.round(barb)) < 0.35), 0.0, 1.0)
    # Fluffy down at the base: thin, fading.
    down = 1.0 - smooth(0.04, 0.16, t)
    alpha = alpha * (1.0 - down * 0.65 * (np.abs(dn) > 0.3))
    n = noise.fbm(xx * 0.08 + x0, yy * 0.04 + y0, 3)
    col = spec["feather"](kind)(t, np.clip(dn, -1, 1), n)
    col = col * (0.9 + 0.1 * stripes)[..., None] * (0.95 + 0.1 * n)[..., None]
    # The shaft: a pale stripe in a grey or dark feather.
    shaft_w = (0.035 - 0.02 * t) * (t < 0.98)
    on_shaft = 1.0 - smooth(shaft_w * 0.6, shaft_w, np.abs(d))
    col = col + (np.clip(col * 1.4 + 0.08, 0, 1) - col) * (on_shaft * 0.6)[..., None]
    alpha = np.maximum(alpha, on_shaft * (t > 0.012) * (t < 0.985))
    height = 0.35 * stripes * (np.abs(dn) < 1) + 1.2 * on_shaft + 0.4 * (1 - np.abs(np.clip(dn, -1, 1)))
    alb[y0:y0 + h, x0:x0 + w, :3] = col
    alb[y0:y0 + h, x0:x0 + w, 3] = alpha
    hgt[y0:y0 + h, x0:x0 + w] = height
    msk[y0:y0 + h, x0:x0 + w, 0] = spec["irid_feather"]
    msk[y0:y0 + h, x0:x0 + w, 1] = spec["morph_feather"]
    msk[y0:y0 + h, x0:x0 + w, 2] = spec["feather_rough"]


def paint_body(name, spec, alb, hgt, msk, noise):
    w, h = 512, N
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    a = (xx + 0.5) / w
    s = 1.0 - (yy + 0.5) / h
    n = noise.fbm(xx * 0.03, yy * 0.03, 4)
    if name == "sparrow":
        streak = smooth(0.55, 0.7, noise(xx * 0.09, yy * 0.012))
        col, irid, morph, rough = sparrow_body(a, s, n, streak)
    else:
        col, irid, morph, rough = spec["body"](a, s, n)
    # Contour feathers: rows of overlapping scallops whose free edges point to the tail.
    size = 30.0 * (1.0 - 0.55 * smooth(S_NECK, S_HEAD + 0.05, s)) * (1.0 - 0.6 * smooth(S_BEAK - 0.02, S_BEAK, s))
    row = np.floor(yy / size)
    uu = xx / size + 0.5 * (row % 2)
    vv = yy / size
    jitter = noise(np.floor(uu) * 3.1, row * 1.7) * 0.25
    phase = vv - 0.32 * np.cos(2.0 * np.pi * (uu - jitter)) + jitter
    edge = phase - np.floor(phase)
    scallop = edge ** 1.6
    fine = 0.5 + 0.5 * np.sin((yy / 2.2 + xx * 0.6) * 2.0 * np.pi * 0.5)
    on_beak = smooth(S_BEAK - 0.006, S_BEAK + 0.006, s)
    height = (0.3 * scallop + 0.08 * fine + 0.25 * n) * (1 - on_beak) + on_beak * (0.2 * n)
    col = col * (0.95 + 0.07 * scallop * (1 - on_beak))[..., None]
    alb[0:h, 0:w, :3] = col
    alb[0:h, 0:w, 3] = 1.0
    hgt[0:h, 0:w] = height
    msk[0:h, 0:w, 0] = irid
    msk[0:h, 0:w, 1] = morph
    msk[0:h, 0:w, 2] = rough


def paint_far_wing(name, spec, alb, hgt, msk, noise):
    """A whole left wing from above in (span f, chord c) coordinates for the far LOD and the near
    wing's covert sheet: coverts in rows on the front half, flight feathers behind, primaries
    fanned out to the tip with gaps between their tips."""
    x0, y0, w, h = FAR_WING
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    f = (xx + 0.5) / w
    c = (yy + 0.5) / h
    feather = spec["feather"]
    # Which feather kind covers each point: coverts on the front, secondaries / primaries behind.
    cov_line = 0.42 + 0.08 * f
    is_cov = c < cov_line
    # Rows of covert scallops.
    rows = np.floor(c / 0.09)
    uu = f * 34.0 + 0.5 * (rows % 2)
    ph = c / 0.09 - 0.3 * np.cos(2 * np.pi * uu)
    sc = (ph - np.floor(ph)) ** 1.5
    col = np.zeros((h, w, 3), np.float32)
    tvec = np.clip((c - cov_line) / np.maximum(1.0 - cov_line, 1e-3), 0, 1)
    # Out on the hand the primaries are seen along their length: their tips ARE the wingtip.
    tvec = np.where(f > 0.48, np.maximum(tvec, np.clip((f - 0.5) / 0.45, 0, 1)), tvec)
    # Flight feathers: count across the span, one stripe each, coloured as their slot.
    count = np.where(f < 0.48, 11.0, 10.0)
    local = np.where(f < 0.48, f / 0.48, (f - 0.48) / 0.52) * count
    idx = np.floor(local)
    dn = (local - idx) * 2.0 - 1.0
    kinds_s = np.where(idx < 3, "TERT", np.where(idx < 7, "S_IN", "S_OUT"))
    kinds_p = np.where(idx < 4, "P_IN", np.where(idx < 7, "P_MID", "P_OUT"))
    kind = np.where(f < 0.48, kinds_s, kinds_p)
    for k in ("TERT", "S_IN", "S_OUT", "P_IN", "P_MID", "P_OUT"):
        m = (kind == k)
        if not m.any():
            continue
        ck = feather(k)(tvec[m], dn[m], np.zeros_like(tvec[m]))
        col[m] = ck
    cov_kind_col = np.where((c > cov_line - 0.14)[..., None], feather("COV_G")(np.clip((c - (cov_line - 0.14)) / 0.14, 0, 1), np.zeros_like(c), c),
                            feather("COV_M")(np.clip(c / np.maximum(cov_line - 0.14, 0.05), 0, 1) * 0.6, np.zeros_like(c), c))
    col = np.where(is_cov[..., None], cov_kind_col * (0.9 + 0.12 * sc)[..., None], col)
    # Trailing edge: serrated by the feather tips; the hand's outer primaries part at their tips.
    tip_shape = 1.0 - 0.08 * np.abs(dn) ** 2
    trail = np.where(f < 0.48, 0.97 * tip_shape, (0.97 - 0.55 * smooth(0.7, 1.0, f) ** 1.3) * tip_shape)
    gaps = (f > 0.8) & (np.abs(dn) > 0.62) & (c > 0.45)
    lead_cut = 0.02 + 0.10 * smooth(0.8, 1.0, f) ** 2
    alpha = np.clip((trail - c) * h / 2.0, 0, 1) * np.clip((c - lead_cut) * h / 2.0 + 1.0, 0, 1)
    alpha = np.where(gaps, 0.0, alpha) * np.clip((1.0 - f) * w / 2.0, 0, 1)
    n = noise.fbm(xx * 0.05, yy * 0.05, 3)
    col = col * (0.93 + 0.12 * n)[..., None]
    stripes = 0.5 + 0.5 * np.cos(dn * np.pi)
    height = np.where(is_cov, 0.7 * sc, 0.5 * stripes)
    alb[y0:y0 + h, x0:x0 + w, :3] = col
    alb[y0:y0 + h, x0:x0 + w, 3] = alpha
    hgt[y0:y0 + h, x0:x0 + w] = height
    msk[y0:y0 + h, x0:x0 + w, 0] = spec["irid_feather"]
    msk[y0:y0 + h, x0:x0 + w, 1] = spec["morph_feather"]
    msk[y0:y0 + h, x0:x0 + w, 2] = spec["far_rough"]


def paint_cov_sheet(name, spec, alb, hgt, msk, noise):
    """The coverts as one sheet: rows of small rounded feathers, the greater coverts' row last,
    their tips cut out along the trailing edge so the sheet ends in a scalloped line."""
    x0, y0, w, h = COV_SHEET
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    f = (xx + 0.5) / w
    c = (yy + 0.5) / h
    feather = spec["feather"]
    rows = 5.0
    r = np.floor(c * rows)
    per = 26.0 - 6.0 * (r / rows)
    uu = f * per + 0.5 * (r % 2)
    ph = c * rows - 0.38 * np.cos(2 * np.pi * uu)
    sc = (ph - np.floor(ph)) ** 1.4
    greater = smooth(0.62, 0.66, c)
    tg = np.clip((c - 0.6) / 0.4, 0, 1)
    col_g = feather("COV_G")(0.35 + 0.6 * tg, np.zeros_like(c), c)
    col_m = feather("COV_M")(0.3 + 0.5 * c, np.zeros_like(c), c)
    col = col_m + (col_g - col_m) * greater[..., None]
    if name == "sparrow":
        col = col + (srgb(0.88, 0.87, 0.82) - col) * (band(c, 0.5, 0.58, 0.02))[..., None]
    col = col * (0.9 + 0.12 * sc)[..., None] * (0.95 + 0.1 * noise.fbm(xx * 0.06, yy * 0.06, 3))[..., None]
    # The greater coverts' rounded tips along the trailing edge.
    gu = f * 16.0
    tip = 0.93 - 0.06 * (2.0 * np.abs(gu - np.floor(gu) - 0.5)) ** 2
    alpha = np.clip((tip - c) * h / 1.5, 0, 1) * np.clip(c * h / 1.5 + 0.5, 0, 1)
    alb[y0:y0 + h, x0:x0 + w, :3] = col
    alb[y0:y0 + h, x0:x0 + w, 3] = alpha
    hgt[y0:y0 + h, x0:x0 + w] = 0.6 * sc
    msk[y0:y0 + h, x0:x0 + w, 0] = spec["irid_feather"]
    msk[y0:y0 + h, x0:x0 + w, 1] = spec["morph_feather"]
    msk[y0:y0 + h, x0:x0 + w, 2] = spec["feather_rough"]


def paint_eye_leg(spec, alb, hgt, msk):
    x0, y0, w, h = EYE
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    r = np.hypot((xx + 0.5) / w * 2 - 1, (yy + 0.5) / h * 2 - 1)
    iris, ring, pupil = spec["eye"]
    col = np.broadcast_to(ring, (h, w, 3)).copy()
    col = lerp_c(col, iris, 1 - smooth(0.66, 0.72, r))
    col = lerp_c(col, srgb(0.02, 0.02, 0.02), 1 - smooth(pupil * 0.6 - 0.03, pupil * 0.6 + 0.03, r))
    alb[y0:y0 + h, x0:x0 + w, :3] = col
    alb[y0:y0 + h, x0:x0 + w, 3] = 1.0
    hgt[y0:y0 + h, x0:x0 + w] = 0.0
    msk[y0:y0 + h, x0:x0 + w, 2] = np.where(r < 0.72, 0.06, 0.5)
    x0, y0, w, h = LEG
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    scutes = (yy / 6.0) % 1.0
    col = spec["leg"] * (0.85 + 0.2 * scutes)[..., None]
    alb[y0:y0 + h, x0:x0 + w, :3] = col
    alb[y0:y0 + h, x0:x0 + w, 3] = 1.0
    hgt[y0:y0 + h, x0:x0 + w] = scutes * 0.5
    msk[y0:y0 + h, x0:x0 + w, 2] = 0.5


def normal_from_height(hgt, strength):
    gx = (np.roll(hgt, -1, axis=1) - np.roll(hgt, 1, axis=1)) * 0.5
    gy = (np.roll(hgt, -1, axis=0) - np.roll(hgt, 1, axis=0)) * 0.5
    nx = -gx * strength
    ny = gy * strength  # image y runs down, OpenGL green runs up
    nz = np.ones_like(hgt)
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / l, ny / l, nz / l], axis=-1) * 0.5 + 0.5


def dilate_colour(alb):
    """Bleeds every opaque texel's colour into the transparent ones round it, so the mips of a
    cut-out feather do not pull its edge toward black."""
    rgb = alb[..., :3].copy()
    a = alb[..., 3] > 0.02
    filled = a.copy()
    for _ in range(12):
        acc = np.zeros_like(rgb)
        cnt = np.zeros(filled.shape, np.float32)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            sh = np.roll(np.roll(filled, dy, 0), dx, 1)
            acc += np.roll(np.roll(rgb, dy, 0), dx, 1) * sh[..., None]
            cnt += sh
        grow = (~filled) & (cnt > 0)
        rgb[grow] = acc[grow] / cnt[grow][..., None]
        filled |= grow
    alb[..., :3] = rgb


def build(name):
    spec = SPECIES[name]
    noise = Noise(spec["seed"])
    alb = np.zeros((N, N, 4), np.float32)
    hgt = np.zeros((N, N), np.float32)
    msk = np.zeros((N, N, 3), np.float32)
    msk[..., 2] = 0.7
    paint_body(name, spec, alb, hgt, msk, noise)
    for kind in SLOTS:
        paint_feather(kind, spec, alb, hgt, msk, noise)
    paint_far_wing(name, spec, alb, hgt, msk, noise)
    paint_cov_sheet(name, spec, alb, hgt, msk, noise)
    paint_eye_leg(spec, alb, hgt, msk)
    dilate_colour(alb)
    nrm = normal_from_height(hgt, 2.2)
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray((np.clip(alb, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, name + "_albedo.png"), optimize=True)
    Image.fromarray((np.clip(nrm, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(os.path.join(OUT, name + "_normal.png"), optimize=True)
    Image.fromarray((np.clip(msk, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(os.path.join(OUT, name + "_mask.png"), optimize=True)
    print("wrote", name)


if __name__ == "__main__":
    names = sys.argv[1:] or list(SPECIES)
    for nm in names:
        build(nm)
