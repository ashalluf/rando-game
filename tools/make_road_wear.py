#!/usr/bin/env python3
"""Road wear stamps (RoadWear, scripts/world/road_wear.gd): the library of 25 base stamps every
street in the city is worn from, written into ONE atlas of three textures.

    python3 tools/make_road_wear.py            (needs pillow and numpy; ~1 minute)

Writes, all 2048 x 2048, 5 x 5 cells of 409.6 px with each stamp drawn at 400 px in the middle:
  assets/textures/road_wear/road_wear_color.png  RGB albedo (sRGB, as the road's own texture is
                                                 read: what the feature looks like under a road
                                                 tint of 1), A coverage
  assets/textures/road_wear/road_wear_nrm.png    R / G the surface slope along the stamp's +u /
                                                 +v (0.5 flat, our own convention, NOT a GL normal
                                                 map), B ambient occlusion (cavity)
  assets/textures/road_wear/road_wear_data.png   R height (0.5 the road; +-HEIGHT_RANGE metres),
                                                 G roughness, B water the texel holds (1.0 = holds
                                                 it even dry), A erosion order (a texel is drawn
                                                 while its order is above the instance's wear
                                                 threshold, so one stamp erodes into many shapes)
  scripts/world/road_wear_table.gd               the stamps' names, real sizes and depths, which
                                                 RoadWear and the shader read (the contract)

A stamp's u runs across the road and v along it (row = v). Sources: the CC0 scans already in
the repo (docs/ASSETS.md) - Asphalt033 and AerialAsphalt01 (asphalt and patch asphalt),
GravelConcrete03 (gravel and exposed aggregate), DryGroundRocks (the dirt under a pothole),
Concrete034 (concrete panels) - cut, recoloured and re-lit by this script; the shapes (cracks,
holes, ruts, ripples, stains, tyre marks, paint ghosts) are procedural. Nothing here is a brand,
a logo or lettering. Reproducible: every random stream is seeded per stamp.
"""
import math
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
TEX = os.path.join(ROOT, "assets", "textures")
OUT = os.path.join(TEX, "road_wear")
ATLAS = 2048
GRID = 5
CELL = ATLAS / GRID
S = 400  # stamp size in px
HEIGHT_RANGE = 0.12  # metres either way of the road in data.R
# The road's own texture sets and how many metres one tile covers on a road (CityChunk._road_look).
ASPHALT_TILE = 7.0
AERIAL_TILE = 9.0
GRAVEL_TILE = 2.5
DIRT_TILE = 2.0
CONCRETE_TILE = 3.0


# --- colour --------------------------------------------------------------------------------------

def to_lin(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def to_srgb(a):
    a = np.clip(a, 0.0, 1.0)
    return np.where(a <= 0.0031308, a * 12.92, 1.055 * a ** (1 / 2.4) - 0.055)


_scans = {}


def scan(name, kind):
    key = (name, kind)
    if key not in _scans:
        im = Image.open(os.path.join(TEX, name, "%s_1K-JPG_%s.jpg" % (name, kind)))
        im = im.convert("RGB")
        a = np.asarray(im).astype(np.float32) / 255.0
        _scans[key] = a
    return _scans[key]


def sample(name, kind, w_m, h_m, tile_m, offset=(0.0, 0.0)):
    """The scan `name` as it lies on a stamp w_m x h_m metres (S x S px), at tile_m metres a tile."""
    src = scan(name, kind)
    sh, sw = src.shape[:2]
    px_per_m_x = sw / tile_m
    px_per_m_y = sh / tile_m
    xs = (np.arange(S) + 0.5) / S * w_m * px_per_m_x + offset[0] * sw
    ys = (np.arange(S) + 0.5) / S * h_m * px_per_m_y + offset[1] * sh
    xi = np.floor(xs).astype(int)
    yi = np.floor(ys).astype(int)
    fx = (xs - xi)[None, :, None]
    fy = (ys - yi)[:, None, None]
    x0, x1 = xi % sw, (xi + 1) % sw
    y0, y1 = yi % sh, (yi + 1) % sh
    a = src[y0][:, x0] * (1 - fx) + src[y0][:, x1] * fx
    b = src[y1][:, x0] * (1 - fx) + src[y1][:, x1] * fx
    return a * (1 - fy) + b * fy


def lin_color(name, w, h, tile, off=(0.0, 0.0)):
    return to_lin(sample(name, "Color", w, h, tile, off))


def scan_height(name, w, h, tile, off=(0.0, 0.0), amp=0.004):
    """Fine relief from a scan: its luminance high-passed (stones are lighter than the binder and
    stand proud of it), scaled to +-amp metres. Only ever fine detail on top of a stamp's shape."""
    lum = sample(name, "Color", w, h, tile, off).mean(-1)
    hh = lum - blur(lum, 5)
    return (hh / (np.abs(hh).max() + 1e-6) * amp).astype(np.float32)


# --- noise ---------------------------------------------------------------------------------------

def value_noise(shape, cells, rng):
    """Smooth value noise over `shape` with `cells` lattice cells across."""
    h, w = shape
    gy, gx = int(cells * h / w) + 2, int(cells) + 2
    lat = rng.random((gy + 1, gx + 1)).astype(np.float32)
    ys = np.linspace(0, gy - 1.001, h)
    xs = np.linspace(0, gx - 1.001, w)
    yi = ys.astype(int)
    xi = xs.astype(int)
    fy = ys - yi
    fx = xs - xi
    fy = fy * fy * (3 - 2 * fy)
    fx = fx * fx * (3 - 2 * fx)
    a = lat[yi][:, xi] * (1 - fx) + lat[yi][:, xi + 1] * fx
    b = lat[yi + 1][:, xi] * (1 - fx) + lat[yi + 1][:, xi + 1] * fx
    return a * (1 - fy[:, None]) + b * fy[:, None]


def fbm(shape, cells, rng, octaves=4):
    v = np.zeros(shape, np.float32)
    amp = 0.5
    total = 0.0
    for o in range(octaves):
        v += amp * value_noise(shape, cells * 2 ** o, rng)
        total += amp
        amp *= 0.5
    return v / total


def blur(a, r):
    """Gaussian blur of a 2D float array (sigma r px), edges padded by reflection."""
    if r <= 0:
        return a
    a = np.asarray(a, np.float32)
    p = int(math.ceil(r * 3))
    b = np.pad(a, p, mode="reflect") if min(a.shape) > p else np.pad(a, p, mode="edge")
    fy = np.fft.fftfreq(b.shape[0])[:, None]
    fx = np.fft.rfftfreq(b.shape[1])[None, :]
    g = np.exp(-2.0 * (math.pi * r) ** 2 * (fx * fx + fy * fy))
    out = np.fft.irfft2(np.fft.rfft2(b) * g, s=b.shape)
    return out[p:-p, p:-p].astype(np.float32)


def grid():
    ys, xs = np.mgrid[0:S, 0:S].astype(np.float32)
    return (xs + 0.5) / S, (ys + 0.5) / S


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


# --- strokes -------------------------------------------------------------------------------------

def stroke_layer(paths, ss=2):
    """Rasterises polylines [(points in 0..1, widths in px, value)] into (coverage, value) at S,
    anti-aliased by drawing at `ss` times and averaging. Later paths win where they overlap only
    if their value is higher (np.maximum), so the trunk keeps its order over its branches."""
    size = S * ss
    cov = np.zeros((size, size), np.float32)
    val = np.zeros((size, size), np.float32)
    for pts, widths, value in paths:
        layer = Image.new("L", (size, size), 0)
        d = ImageDraw.Draw(layer)
        for i in range(len(pts) - 1):
            w = max(1, int(round(widths[i] * ss)))
            a = (pts[i][0] * size, pts[i][1] * size)
            b = (pts[i + 1][0] * size, pts[i + 1][1] * size)
            d.line([a, b], fill=255, width=w)
            r = w / 2.0
            d.ellipse([b[0] - r, b[1] - r, b[0] + r, b[1] + r], fill=255)
        m = np.asarray(layer).astype(np.float32) / 255.0
        val = np.where(m > 0.5, np.maximum(val, value), val)
        cov = np.maximum(cov, m)
    cov = cov.reshape(S, ss, S, ss).mean(axis=(1, 3))
    val = val.reshape(S, ss, S, ss).max(axis=(1, 3))
    return cov, val


def walk(rng, start, heading, length, step=0.012, wander=0.35, pull=None):
    """A crack's path: a random walk of `length` (0..1 units) from `start`, heading in radians."""
    pts = [start]
    x, y = start
    h = heading
    n = max(2, int(length / step))
    for i in range(n):
        h += rng.normal(0, wander)
        if pull is not None:
            h = h * 0.75 + pull * 0.25
        x += math.cos(h) * step
        y += math.sin(h) * step
        pts.append((x, y))
    return pts


def crack_tree(rng, start, heading, length, width, order, depth=0, max_depth=3, branch_p=0.18, pull=None, wander=0.3):
    """A crack and its branches as stroke paths: the width tapers to the tips and the order falls
    toward them (the tips erode first)."""
    pts = walk(rng, start, heading, length, wander=wander, pull=pull)
    n = len(pts)
    widths = [width * (1.0 - 0.75 * i / n) * (0.7 + 0.6 * rng.random()) for i in range(n)]
    paths = []
    # The order runs down the crack in pieces, so a threshold cuts it back from the tip.
    seg = 6
    for i in range(0, n - 1, seg):
        part = pts[i:i + seg + 1]
        o = order * (1.0 - 0.55 * i / n)
        paths.append((part, widths[i:i + seg + 1], o))
    if depth < max_depth:
        for i in range(3, n - 3):
            if rng.random() < branch_p / max(1, depth + 1) * (3.0 / max(n, 3)) * 6:
                h = math.atan2(pts[i + 1][1] - pts[i][1], pts[i + 1][0] - pts[i][0]) + rng.choice([-1, 1]) * rng.uniform(0.5, 1.3)
                paths += crack_tree(rng, pts[i], h, length * rng.uniform(0.2, 0.5), widths[i] * 0.7, order * rng.uniform(0.45, 0.85), depth + 1, max_depth, branch_p, None, wander)
    return paths


def voronoi(rng, n, warp=0.0, aspect=1.0, jitter=1.0, seeds=None):
    """F1, F2 and the nearest seed index over the stamp, from n random seeds (or a given set)."""
    u, v = grid()
    if warp > 0:
        u = u + (fbm((S, S), 3, rng) - 0.5) * warp
        v = v + (fbm((S, S), 3, rng) - 0.5) * warp
    if seeds is None:
        seeds = rng.random((n, 2))
    d = np.stack([np.hypot((u - sx) * aspect, v - sy) for sx, sy in seeds], 0)
    idx = np.argsort(d, axis=0)
    f1 = np.take_along_axis(d, idx[0:1], 0)[0]
    f2 = np.take_along_axis(d, idx[1:2], 0)[0]
    return f1, f2, idx[0], seeds


# --- the stamp record ------------------------------------------------------------------------------

class Stamp:
    def __init__(self, name, w, h, depth=0.0):
        self.name = name
        self.w = w  # metres across (u)
        self.h = h  # metres along (v)
        self.depth = depth  # deepest point below the road, metres (POM)
        self.albedo = np.zeros((S, S, 3), np.float32)  # linear
        self.cover = np.zeros((S, S), np.float32)
        self.height = np.zeros((S, S), np.float32)  # metres
        self.rough = np.full((S, S), 0.8, np.float32)
        self.water = np.zeros((S, S), np.float32)
        self.order = np.ones((S, S), np.float32)
        self.ao = np.ones((S, S), np.float32)


def edge_fade(margin=0.06):
    u, v = grid()
    d = np.minimum(np.minimum(u, 1 - u), np.minimum(v, 1 - v))
    return smoothstep(0.0, margin, d)


def asphalt(w, h, rng, dark=1.0, aerial=False):
    name, tile = ("AerialAsphalt01", AERIAL_TILE) if aerial else ("Asphalt033", ASPHALT_TILE)
    off = (rng.random(), rng.random())
    return lin_color(name, w, h, tile, off) * dark, scan_height(name, w, h, tile, off, 0.003), sample(name, "Roughness", w, h, tile, off)[..., 0]


def finish_cracks(st, cov, val, depth, dark=0.25, rough=0.95):
    """Crack strokes onto a stamp: a dark, deep, rough line whose order is its stroke value."""
    st.cover = np.maximum(st.cover, cov)
    st.order = np.where(cov > 0.02, np.maximum(val, 0.02), st.order)
    st.height = st.height - depth * cov * smoothstep(0.0, 0.5, cov)
    st.ao = np.minimum(st.ao, 1.0 - 0.75 * cov)
    st.rough = np.where(cov > 0.05, rough, st.rough)
    st.water = np.maximum(st.water, cov * 0.6)


def crack_albedo(st, rng, base_dark=0.022):
    """The colour inside a crack: dark fines and dust, a touch of weed green now and then."""
    n = fbm((S, S), 12, rng)
    c = np.stack([base_dark * (0.8 + 0.5 * n), base_dark * (0.8 + 0.5 * n), base_dark * (0.72 + 0.45 * n)], -1)
    return c


# --- the 25 stamps -----------------------------------------------------------------------------

def pothole(name, w, depth, rng, kind):
    st = Stamp(name, w, w, depth)
    u, v = grid()
    cx, cy = 0.5 + rng.uniform(-0.04, 0.04), 0.5 + rng.uniform(-0.04, 0.04)
    ang = np.arctan2(v - cy, u - cx)
    rad = np.hypot(u - cx, (v - cy) * rng.uniform(0.85, 1.15))
    # The outline: a lumpy radius in angle, broken into chunks for a deep one.
    k = np.arange(1, 9)
    amps = rng.normal(0, 1, 8) / k ** 1.1
    phases = rng.random(8) * math.tau
    lump = sum(amps[i] * np.cos(k[i] * ang + phases[i]) for i in range(8))
    r_edge = 0.30 * (1.0 + 0.16 * lump)
    if kind in ("deep", "water"):
        # Broken edges: a few angular bites taken out of the rim.
        for b in range(rng.integers(3, 7)):
            a0 = rng.random() * math.tau
            span = rng.uniform(0.25, 0.6)
            da = np.angle(np.exp(1j * (ang - a0)))
            bite = np.clip(1.0 - np.abs(da) / span, 0.0, 1.0)
            r_edge = r_edge + 0.07 * np.minimum(bite * 2.0, 1.0) * rng.uniform(0.5, 1.0)
    r_edge = r_edge + (fbm((S, S), 9, rng) - 0.5) * 0.05
    t = rad / r_edge  # 0 centre, 1 the rim
    inside = smoothstep(1.02, 0.97, t)
    # Depth profile: a steep wall a few centimetres in from the rim, a lumpy floor.
    wall = smoothstep(1.0, 0.82 if kind != "shallow" else 0.6, t)
    floor_n = fbm((S, S), 10, rng)
    floor = 0.75 + 0.25 * floor_n
    if kind == "water":
        floor = 0.85 + 0.15 * (1 - t ** 2)
    hgt = -depth * wall * floor
    # Floor material: dirt and loose aggregate, the base course showing.
    dirt = lin_color("DryGroundRocks", w, w, DIRT_TILE, (rng.random(), rng.random()))
    gravel = lin_color("GravelConcrete03", w, w, GRAVEL_TILE, (rng.random(), rng.random()))
    grey = dirt.mean(-1, keepdims=True)
    dirt = dirt * 0.35 + grey * 0.65  # LA dust is grey-brown, not orange
    mixn = smoothstep(0.4, 0.6, fbm((S, S), 6, rng))[..., None]
    floor_col = (dirt * mixn + gravel * (1 - mixn)) * 0.55
    # The wall: the asphalt's cross-section, dark with aggregate.
    a_col, a_h, a_r = asphalt(w, w, rng, 0.55)
    wall_band = smoothstep(0.55, 0.85, t) * inside
    col = floor_col * (1 - wall_band[..., None]) + a_col * wall_band[..., None]
    # Ravelled, cracked ring round the rim, where the asphalt is breaking up next.
    ring = smoothstep(1.55, 1.0, t) * (1 - inside)
    rn = fbm((S, S), 14, rng)
    loose = ring * smoothstep(0.45, 0.65, rn)
    agg = lin_color("GravelConcrete03", w, w, GRAVEL_TILE * 0.6, (rng.random(), rng.random()))
    col = col * (1 - loose[..., None] * (1 - inside[..., None])) + agg * 0.75 * loose[..., None]
    st.albedo = col.astype(np.float32)
    st.cover = np.clip(np.maximum(inside, loose * 0.85), 0, 1)
    st.height = hgt + a_h * 0.5 - 0.004 * loose
    st.rough = np.where(inside > 0.5, 0.92, 0.85)
    st.ao = 1.0 - 0.55 * wall * (1 - 0.5 * (1 - t).clip(0, 1)) * inside
    # Radial cracks running out of the rim.
    paths = []
    for c in range(rng.integers(3, 8)):
        a0 = rng.random() * math.tau
        r0 = 0.30
        start = (cx + math.cos(a0) * r0, cy + math.sin(a0) * r0)
        paths += crack_tree(rng, start, a0 + rng.normal(0, 0.3), rng.uniform(0.08, 0.2), 3.5, rng.uniform(0.35, 0.7), max_depth=1)
    cov, val = stroke_layer(paths)
    cov *= (1 - inside)
    st.albedo = st.albedo * (1 - cov[..., None]) + crack_albedo(st, rng) * cov[..., None]
    # Erosion order: the core never erodes; the rim, the loose ring and the cracks go first.
    st.order = np.clip(1.15 - t * 0.75 + (rn - 0.5) * 0.25, 0.02, 1.0)
    finish_cracks(st, cov, val, 0.012)
    if kind == "gravel":
        # Filled by a crew with loose gravel and cold patch, a little proud of the floor.
        fill = smoothstep(0.95, 0.75, t)
        g = lin_color("GravelConcrete03", w, w, GRAVEL_TILE * 0.9, (rng.random(), rng.random()))
        g = (g * 0.5 + g.mean(-1, keepdims=True) * 0.5) * (0.55 + 0.35 * fbm((S, S), 9, rng)[..., None])
        cp, cph, _ = asphalt(w, w, rng, 0.45)
        cold = smoothstep(0.45, 0.6, fbm((S, S), 5, rng))[..., None]
        fillc = g * (1 - cold) + cp * cold
        st.albedo = st.albedo * (1 - fill[..., None]) + fillc * fill[..., None]
        gh = scan_height("GravelConcrete03", w, w, GRAVEL_TILE * 0.5, (0.3, 0.1), 0.006)
        st.height = st.height * (1 - fill) + (-0.012 + gh) * fill
        st.rough = np.where(fill > 0.5, 0.9, st.rough)
        st.ao = st.ao * (1 - fill) + (0.9 + 0.1 * fill) * fill
    if kind == "water":
        # A bowl that holds water even on a dry day (a broken main nearby, sprinklers).
        st.water = np.where(t < 0.8, 1.0, np.clip(1.0 - (t - 0.8) / 0.2, 0, 1) * 0.9 + 0.05)
        algae = smoothstep(0.5, 0.95, t) * inside
        st.albedo = st.albedo * (1 - 0.4 * algae[..., None]) + np.array([0.03, 0.035, 0.02]) * 0.4 * algae[..., None]
    else:
        st.water = np.maximum(st.water, np.clip(wall * 0.95, 0, 0.92))
    return st


def pothole_cluster(rng):
    st = Stamp("pothole_cluster", 2.4, 2.4, 0.06)
    st.cover[:] = 0
    st.order[:] = 0.02
    centres = []
    for i in range(rng.integers(4, 7)):
        for tries in range(30):
            c = (rng.uniform(0.18, 0.82), rng.uniform(0.18, 0.82))
            r = rng.uniform(0.06, 0.14)
            if all(math.hypot(c[0] - d[0], c[1] - d[1]) > r + d[2] + 0.03 for d in centres):
                centres.append((c[0], c[1], r))
                break
    u, v = grid()
    a_col, a_h, a_r = asphalt(2.4, 2.4, rng, 0.55)
    dirt = lin_color("GravelConcrete03", 2.4, 2.4, GRAVEL_TILE, (0.2, 0.7)) * 0.5
    ang_n = fbm((S, S), 12, rng)
    for idx, (cx, cy, r) in enumerate(centres):
        ang = np.arctan2(v - cy, u - cx)
        k = rng.normal(0, 1, 6)
        lump = sum(k[i] / (i + 1) * np.cos((i + 1) * ang + rng.random() * 6) for i in range(6))
        t = np.hypot(u - cx, v - cy) / (r * (1 + 0.15 * lump + (ang_n - 0.5) * 0.2))
        inside = smoothstep(1.03, 0.95, t)
        wall = smoothstep(1.0, 0.7, t)
        d = st.depth * rng.uniform(0.5, 1.0)
        st.height = np.minimum(st.height, -d * wall)
        band = smoothstep(0.55, 0.9, t)[..., None]
        col = dirt * (1 - band) + a_col * band
        st.albedo = np.where(inside[..., None] > st.cover[..., None], col, st.albedo)
        st.cover = np.maximum(st.cover, inside)
        # The biggest holes last longest.
        o = 0.35 + 0.65 * (r - 0.06) / 0.08
        st.order = np.where(inside > 0.02, np.maximum(st.order, np.clip(o * (1.1 - 0.4 * t), 0.02, 1)), st.order)
        st.water = np.maximum(st.water, wall * 0.95)
        st.ao = np.minimum(st.ao, 1 - 0.5 * wall * band[..., 0])
    # Fatigue cracks joining them.
    paths = []
    for i in range(len(centres) - 1):
        a, b = centres[i], centres[i + 1]
        h = math.atan2(b[1] - a[1], b[0] - a[0])
        paths += crack_tree(rng, (a[0], a[1]), h, math.hypot(b[0] - a[0], b[1] - a[1]), 3.0, 0.3, max_depth=1, pull=h, wander=0.25)
    cov, val = stroke_layer(paths)
    st.albedo = st.albedo * (1 - cov[..., None]) + crack_albedo(st, rng) * cov[..., None]
    finish_cracks(st, cov * (1 - st.cover), val, 0.01)
    st.rough = np.where(st.cover > 0.5, 0.92, st.rough)
    return st


def alligator(rng):
    st = Stamp("alligator", 2.5, 3.5, 0.015)
    f1, f2, idx, seeds = voronoi(rng, 70, warp=0.03, aspect=2.5 / 3.5)
    edge = f2 - f1
    width = 0.006 + 0.004 * fbm((S, S), 8, rng)
    line = smoothstep(width * 1.6, width * 0.5, edge)
    # The patch it covers: an oval where the wheels ran, ragged.
    u, v = grid()
    blob = np.hypot((u - 0.5) / 0.42, (v - 0.5) / 0.46) + (fbm((S, S), 4, rng) - 0.5) * 0.6
    area = smoothstep(1.0, 0.75, blob)
    cov = line * area
    # Each polygon wears at its own pace: its seed's rank is its order, the middle ones last.
    rank = rng.random(len(seeds))
    o = rank[idx] * 0.6 + 0.4 * smoothstep(1.0, 0.2, blob)
    st.order = np.clip(o, 0.02, 1.0).astype(np.float32)
    # A few of the polygons have lost their surface (the first stage of a pothole).
    lost = (rank[idx] > 0.93) & (area > 0.6)
    lost_m = blur(lost.astype(np.float32), 1.2) * area
    a_col, a_h, _ = asphalt(2.5, 3.5, rng, 0.85)
    agg = lin_color("GravelConcrete03", 2.5, 3.5, GRAVEL_TILE, (0.4, 0.1)) * 0.6
    st.albedo = crack_albedo(st, rng) * (1 - lost_m[..., None]) + agg * lost_m[..., None]
    st.cover = np.clip(np.maximum(cov, lost_m), 0, 1)
    st.height = -0.012 * cov - 0.02 * lost_m
    # Slabs tilt a hair, so the network catches the light.
    tilt = (rng.random(len(seeds)) - 0.5)[idx] * 0.002 * area
    st.height += tilt
    st.rough = np.full((S, S), 0.95, np.float32)
    st.ao = 1 - 0.7 * cov - 0.3 * lost_m
    st.water = np.maximum(cov * 0.5, lost_m * 0.8)
    return st


def block_crack(rng):
    st = Stamp("block_crack", 6.0, 6.0, 0.012)
    # Rectangular blocks 0.3-3 m: a jittered grid, each line wandering.
    paths = []
    nx = rng.integers(3, 5)
    ny = rng.integers(3, 5)
    for i in range(1, nx):
        x = i / nx + rng.uniform(-0.05, 0.05)
        pts = [(x + rng.normal(0, 0.006) + 0.01 * math.sin(j * 0.7), j / 40) for j in range(41)]
        paths.append((pts, [3.0 + rng.random() * 1.5] * 41, rng.uniform(0.4, 1.0)))
    for j in range(1, ny):
        y = j / ny + rng.uniform(-0.05, 0.05)
        # Transverse lines often stop at a longitudinal one.
        x0 = rng.choice([0.0, rng.uniform(0.1, 0.5)])
        x1 = rng.choice([1.0, rng.uniform(0.5, 0.9)])
        pts = [(x0 + (x1 - x0) * i / 40, y + rng.normal(0, 0.006)) for i in range(41)]
        paths.append((pts, [2.5 + rng.random() * 1.5] * 41, rng.uniform(0.25, 0.9)))
    for k in range(6):
        paths += crack_tree(rng, (rng.random(), rng.random()), rng.random() * math.tau, rng.uniform(0.05, 0.15), 2.2, rng.uniform(0.1, 0.4), max_depth=1)
    cov, val = stroke_layer(paths)
    st.albedo = crack_albedo(st, rng)
    st.order[:] = 0.02
    finish_cracks(st, cov, val, 0.012)
    return st


def crack_long(rng, name="crack_long", w=0.8, h=6.0, across=False):
    st = Stamp(name, w, h, 0.015)
    if across:
        start = (0.02, 0.5 + rng.uniform(-0.1, 0.1))
        heading = 0.0
    else:
        start = (0.5 + rng.uniform(-0.1, 0.1), 0.02)
        heading = math.pi / 2
    paths = crack_tree(rng, start, heading, 1.0, 4.5, 1.0, max_depth=2, branch_p=0.35, pull=heading, wander=0.22)
    # A second, finer crack running alongside part of the way (they often double up).
    s2 = (start[0] + (0 if across else 0.08), start[1] + (0.08 if across else 0))
    paths += crack_tree(rng, s2, heading, rng.uniform(0.3, 0.6), 2.5, 0.45, max_depth=1, pull=heading, wander=0.25)
    cov, val = stroke_layer(paths)
    st.albedo = crack_albedo(st, rng)
    st.order[:] = 0.02
    # The edges of an old crack ravel: a lighter frayed band either side.
    fray = np.clip(blur(cov, 3.0) * 3.0 - cov, 0, 1) * 0.5
    agg = lin_color("Asphalt033", w, h, ASPHALT_TILE * 0.6, (0.5, 0.2)) * 1.25
    st.albedo = st.albedo * cov[..., None] / np.maximum(cov[..., None] + fray[..., None], 1e-4) + agg * fray[..., None] / np.maximum(cov[..., None] + fray[..., None], 1e-4)
    finish_cracks(st, cov, val, 0.015)
    st.cover = np.clip(np.maximum(cov, fray * 0.6), 0, 1)
    st.order = np.where(fray > 0.02, np.maximum(st.order, blur(val, 3.0) * 0.8), st.order)
    return st


def tar_snake(rng, name="tar_snake", w=1.0, h=6.0, network=False):
    st = Stamp(name, w, h, 0.0)
    if network:
        f1, f2, idx, seeds = voronoi(rng, 9, warp=0.04)
        edge = f2 - f1
        cov_crack = smoothstep(0.012, 0.004, edge)
        band = smoothstep(0.012, 0.007, edge + (fbm((S, S), 16, rng) - 0.5) * 0.006)
        rank = rng.random(len(seeds))
        st.order = np.clip(0.3 + 0.7 * rank[idx] * 0.6 + 0.4 * (1 - f1 * 3), 0.02, 1).astype(np.float32)
    else:
        paths = crack_tree(rng, (0.5, 0.02), math.pi / 2, 1.0, 2.0, 1.0, max_depth=1, branch_p=0.25, pull=math.pi / 2, wander=0.16)
        # The overband: a squeegeed strip 5-8 cm wide over the crack (stroked at that width),
        # its edges feathered where the rubber thinned.
        wpx = 0.065 / w * S
        wide = [(pts, [wpx * (0.8 + 0.4 * rng.random()) for _ in widths], val) for pts, widths, val in paths]
        cov_crack, val = stroke_layer(wide)
        band = smoothstep(0.15, 0.6, blur(cov_crack, 1.0) + (fbm((S, S), 20, rng) - 0.5) * 0.25)
        st.order = np.clip(val * 1.2, 0.02, 1)
    # Bitumen sealant: near black, glossy when fresh (age dulls it in the shader), a hair proud.
    n = fbm((S, S), 30, rng)
    tar = np.stack([0.012 + 0.006 * n, 0.012 + 0.006 * n, 0.013 + 0.006 * n], -1)
    st.albedo = tar.astype(np.float32)
    st.cover = band
    st.height = 0.0015 * band
    st.rough = (0.38 + 0.2 * n).astype(np.float32)
    st.ao = 1 - 0.05 * band
    st.water = band * 0.0
    return st


def ravelling(rng):
    st = Stamp("ravelling", 2.5, 2.5, 0.01)
    u, v = grid()
    blob = np.hypot(u - 0.5, v - 0.5) * 2.2 + (fbm((S, S), 4, rng) - 0.5) * 0.9
    area = smoothstep(1.0, 0.6, blob)
    # The fines and binder are gone: what is left is the stone, lighter and rougher, pitted.
    stones = lin_color("GravelConcrete03", 2.5, 2.5, GRAVEL_TILE * 0.7, (0.1, 0.9))
    lum = stones.mean(-1, keepdims=True)
    stones = (stones * 0.4 + lum * 0.6) * 0.75
    pits = smoothstep(0.55, 0.75, fbm((S, S), 60, rng))
    col = stones * (1 - 0.6 * pits[..., None])
    st.albedo = col.astype(np.float32)
    n = fbm((S, S), 14, rng)
    st.cover = np.clip(area * (0.55 + 0.45 * smoothstep(0.3, 0.6, n)), 0, 1)
    st.height = -0.006 * area + scan_height("GravelConcrete03", 2.5, 2.5, GRAVEL_TILE * 0.7, (0.1, 0.9), 0.004) * area - 0.004 * pits * area
    st.rough = np.full((S, S), 0.97, np.float32)
    st.ao = 1 - 0.35 * pits * area
    st.order = np.clip(1.2 - blob + (n - 0.5) * 0.4, 0.02, 1)
    st.water = pits * area * 0.3
    return st


def patch(rng, name, w, h, lift, aerial=False, saw=False, strip=False):
    st = Stamp(name, w, h, max(0.0, -lift) + 0.01)
    u, v = grid()
    if saw:
        # Saw-cut: a crisp rectangle with a sealed cut line.
        mx, my = (0.06, 0.03) if strip else (0.08, 0.08)
        d = np.minimum(np.minimum(u - mx, 1 - mx - u) * w, np.minimum(v - my, 1 - my - v) * h)  # metres inside
        inside = smoothstep(-0.004, 0.004, d)
        cut = smoothstep(0.02, 0.008, np.abs(d)) * 1.0
        edge_n = np.zeros((S, S), np.float32)
    else:
        # A hand-raked patch: a rounded rectangle with a lumpy outline.
        q = np.maximum(np.abs(u - 0.5) / 0.42, np.abs(v - 0.5) / 0.42)
        e = (np.abs((u - 0.5) / 0.42) ** 5 + np.abs((v - 0.5) / 0.42) ** 5) ** 0.2
        edge_n = (fbm((S, S), 7, rng) - 0.5) * 0.18
        e = e + edge_n
        d = (1.0 - e) * min(w, h) * 0.42
        inside = smoothstep(-0.01, 0.01, d)
        cut = smoothstep(0.05, 0.0, np.abs(d)) * 0.6
    col, ah, ar = asphalt(w, h, rng, 0.62 if lift >= 0 else 0.7, aerial)
    if aerial:
        # The coarser set is lighter and violet: a utility crew's hot mix is near black, and greys.
        col = (col * 0.35 + col.mean(-1, keepdims=True) * 0.65) * 0.5
    # A patch's surface is denser and finer than the old road: smooth it a little.
    st.albedo = col.astype(np.float32)
    rim = smoothstep(0.08 if not saw else 0.02, 0.0, d) * inside
    slope = smoothstep(0.0, 0.12 if not saw else 0.01, d)
    bowl = smoothstep(0.0, min(w, h) * 0.35, d)
    if lift >= 0:
        st.height = lift * slope + ah * 0.6
    else:
        st.height = lift * (0.5 * slope + 0.5 * bowl) + ah * 0.6
    st.height = st.height * inside
    st.rough = np.clip(ar * 0.9 + 0.05, 0.4, 1.0) * inside + 0.85 * (1 - inside)
    # The seam: black sealant on a saw-cut, a dark rough joint on a raked patch.
    seam_col = np.array([0.013, 0.013, 0.014], np.float32)
    st.albedo = st.albedo * (1 - cut[..., None]) + seam_col * cut[..., None]
    st.rough = np.where(cut > 0.4, 0.45 if saw else 0.95, st.rough)
    st.cover = np.clip(np.maximum(inside, cut), 0, 1)
    st.ao = 1 - 0.25 * rim * (1 if lift < 0 else 0.3) - 0.2 * cut
    if lift < 0:
        st.water = np.clip(bowl * 1.2, 0, 0.9) * inside
        # A sunken patch cracks round its edge.
        paths = []
        for k in range(rng.integers(3, 6)):
            a = rng.random() * math.tau
            sx = 0.5 + 0.42 * math.cos(a)
            sy = 0.5 + 0.42 * math.sin(a)
            paths += crack_tree(rng, (sx, sy), a + math.pi / 2, rng.uniform(0.15, 0.4), 2.5, rng.uniform(0.3, 0.7), max_depth=1)
        cov, val = stroke_layer(paths)
        st.albedo = st.albedo * (1 - cov[..., None]) + crack_albedo(st, rng) * cov[..., None]
        finish_cracks(st, cov, val, 0.01)
    # Erosion: a patch is all or nothing in its body; the threshold only frays its edge (and
    # takes its edge cracks back), so its order is high inside and low out at the seam.
    st.order = np.where(st.order < 0.99, st.order, np.clip(0.55 + d * 3.0 + edge_n, 0.02, 1.0)).astype(np.float32)
    if saw:
        st.order = np.where(inside > 0.5, 1.0, st.order).astype(np.float32)
    return st


def rut(rng):
    st = Stamp("rut_polish", 0.9, 8.0, 0.018)
    u, v = grid()
    wander = (fbm((S, S), 2, rng)[None, :, ] if False else 0)
    centre = 0.5 + 0.05 * np.sin(v * 3.1 + rng.random() * 6) + 0.03 * (value_noise((S, S), 3, rng) - 0.5)
    across = (u - centre) / 0.28
    prof = np.exp(-across ** 2 * 1.6)
    along = smoothstep(0.0, 0.15, v) * smoothstep(1.0, 0.85, v)
    along *= 0.6 + 0.4 * value_noise((S, S), 4, rng)
    k = prof * along
    a_col, ah, ar = asphalt(0.9, 8.0, rng, 1.0)
    # Polished by the tyres: the stone faces smoothed and darkened by rubber, the lane's shine.
    polish = smoothstep(0.35, 0.9, k)
    col = a_col * (1 - 0.35 * polish[..., None])
    # Rubber streaks along the track.
    streak = value_noise((S, S), 40, rng)
    streak = blur(streak, 0) * 0.5 + 0.5 * np.repeat(rng.random((1, S)), S, 0)
    col = col * (1 - 0.15 * polish[..., None] * streak[..., None])
    st.albedo = col.astype(np.float32)
    st.cover = np.clip(k * 0.95, 0, 1)
    # Shoulders: the asphalt pushed up a little either side of the rut.
    shoulder = np.exp(-(np.abs(across) - 1.1) ** 2 * 6) * along
    st.height = -st.depth * k + 0.004 * shoulder
    st.rough = (0.82 - 0.4 * polish).astype(np.float32)
    st.ao = 1 - 0.1 * k
    st.water = smoothstep(0.4, 0.95, k) * 0.95
    st.order = np.clip(k * 1.3, 0.02, 1)
    return st


def edge_break(rng):
    st = Stamp("edge_break", 1.4, 5.0, 0.06)
    u, v = grid()
    # The kerb is at u = 0: the edge of the asphalt crumbles away from it.
    ragged = 0.12 + 0.1 * fbm((S, S), 5, rng)[:, :1] + 0.08 * (value_noise((S, S), 9, rng)[:, :1] - 0.5)
    ragged = np.repeat(ragged.mean(1, keepdims=True), S, 1)
    along = smoothstep(0.0, 0.12, v) * smoothstep(1.0, 0.88, v)
    chunk_gone = smoothstep(ragged + 0.01, ragged - 0.01, u) * along
    # The broken band beyond: cracked into pieces parallel to the edge, settling.
    zone = smoothstep(0.75, 0.2, u) * along
    paths = []
    for k in range(rng.integers(3, 6)):
        x = rng.uniform(0.18, 0.55)
        paths += crack_tree(rng, (x, rng.uniform(0.0, 0.3)), math.pi / 2, rng.uniform(0.4, 0.9), 3.0, rng.uniform(0.4, 1.0), max_depth=2, branch_p=0.4, pull=math.pi / 2)
    for k in range(rng.integers(6, 10)):
        y = rng.uniform(0.1, 0.9)
        paths += crack_tree(rng, (0.05, y), 0.0 + rng.normal(0, 0.3), rng.uniform(0.15, 0.45), 2.6, rng.uniform(0.3, 0.8), max_depth=1)
    cov, val = stroke_layer(paths)
    cov *= zone
    base = lin_color("DryGroundRocks", 1.4, 5.0, DIRT_TILE, (0.6, 0.3))
    base = base * 0.3 + base.mean(-1, keepdims=True) * 0.7
    gravel = lin_color("GravelConcrete03", 1.4, 5.0, GRAVEL_TILE * 0.6, (0.3, 0.3))
    mixn = smoothstep(0.4, 0.6, fbm((S, S), 8, rng))[..., None]
    hole_col = (base * mixn + gravel * (1 - mixn)) * 0.55
    st.albedo = hole_col * chunk_gone[..., None] + crack_albedo(st, rng) * (1 - chunk_gone[..., None])
    # Debris washed into the gutter.
    st.cover = np.clip(np.maximum(chunk_gone, cov), 0, 1)
    st.height = -0.05 * chunk_gone * (0.7 + 0.3 * fbm((S, S), 12, rng)) - 0.008 * zone * smoothstep(0.6, 0.2, u)
    st.rough = np.full((S, S), 0.95, np.float32)
    st.ao = 1 - 0.4 * chunk_gone * smoothstep(ragged - 0.04, ragged, u)
    st.water = chunk_gone * 0.95
    st.order = np.clip(1.0 - u * 1.1 + (fbm((S, S), 6, rng) - 0.5) * 0.4, 0.02, 1.0)
    finish_cracks(st, cov, val, 0.012)
    return st


def shoving(rng):
    st = Stamp("shoving", 3.0, 2.5, 0.012)
    u, v = grid()
    # Washboard ripples across the direction of travel, where traffic brakes at a stop line.
    warp = (fbm((S, S), 3, rng) - 0.5) * 0.08
    phase = (v + warp) * 2.5 / 0.55 * math.tau
    ripple = np.sin(phase)
    area = smoothstep(0.5, 0.15, np.abs(u - 0.5) * (0.9 + 0.3 * fbm((S, S), 3, rng))) * smoothstep(0.0, 0.25, v) * smoothstep(1.0, 0.75, v)
    st.height = (0.009 * ripple * area).astype(np.float32)
    crest = smoothstep(0.5, 1.0, ripple) * area
    trough = smoothstep(-0.5, -1.0, ripple) * area
    a_col, ah, ar = asphalt(3.0, 2.5, rng, 1.0)
    # Bleeding binder on the crests, dust in the troughs, crescent cracks on the crests.
    col = a_col * (1 - 0.45 * crest[..., None]) + np.array([0.11, 0.105, 0.095]) * 0.25 * trough[..., None]
    st.albedo = col.astype(np.float32)
    st.cover = np.clip(area * 0.9, 0, 1)
    st.rough = (0.85 - 0.35 * crest).astype(np.float32)
    st.ao = 1 - 0.25 * trough
    st.water = trough * 0.8
    paths = []
    for k in range(rng.integers(4, 9)):
        y = (round(rng.uniform(0.3, 0.7) * 2.5 / 0.55 - 0.25) + 0.25) * 0.55 / 2.5
        x = rng.uniform(0.25, 0.75)
        paths += crack_tree(rng, (x, y), rng.choice([0.0, math.pi]) + rng.normal(0, 0.2), rng.uniform(0.08, 0.2), 2.4, rng.uniform(0.3, 0.8), max_depth=0)
    cov, val = stroke_layer(paths)
    cov *= area
    st.albedo = st.albedo * (1 - cov[..., None]) + crack_albedo(st, rng) * cov[..., None]
    st.order = np.clip(area * 1.2 + (fbm((S, S), 5, rng) - 0.5) * 0.3, 0.02, 1)
    finish_cracks(st, cov, val, 0.008)
    return st


def oil(rng):
    st = Stamp("oil_drips", 1.8, 3.0, 0.0)
    u, v = grid()
    acc = np.zeros((S, S), np.float32)
    tint = np.zeros((S, S, 3), np.float32)
    kinds = [np.array([0.012, 0.011, 0.010]), np.array([0.016, 0.03, 0.02]), np.array([0.03, 0.018, 0.01])]
    # A parked car's engine and transmission drip in a line under it; some cars leak coolant.
    cx = 0.5 + rng.uniform(-0.1, 0.1)
    order = np.zeros((S, S), np.float32)
    for k in range(rng.integers(9, 16)):
        x = cx + rng.normal(0, 0.12)
        y = rng.uniform(0.15, 0.85)
        r = rng.uniform(0.04, 0.13)
        sq = rng.uniform(0.8, 1.6)
        t = np.hypot((u - x) / r, (v - y) / (r * sq)) + (fbm((S, S), 10, rng) - 0.5) * 0.6
        drop = smoothstep(1.0, 0.3, t)
        kind = 0 if rng.random() < 0.7 else (1 if rng.random() < 0.6 else 2)
        tint = tint * (1 - drop[..., None]) + kinds[kind] * drop[..., None]
        acc = np.maximum(acc, drop * rng.uniform(0.5, 1.0))
        order = np.maximum(order, drop * rng.uniform(0.3, 1.0))
    # The soak: a wide faint halo round the drips.
    halo = blur(acc, 18) * 1.6
    st.albedo = np.where(acc[..., None] > 0.01, tint, np.array([0.03, 0.028, 0.025])).astype(np.float32)
    st.cover = np.clip(np.maximum(acc, halo * 0.45), 0, 1)
    st.rough = (0.82 - 0.5 * acc).astype(np.float32)
    st.order = np.clip(np.maximum(order, halo * 0.5), 0.02, 1)
    st.water = acc * 0.0
    return st


def burnout(rng):
    st = Stamp("burnout", 2.5, 4.0, 0.0)
    u, v = grid()
    acc = np.zeros((S, S), np.float32)
    order = np.zeros((S, S), np.float32)
    # A pair of rubber arcs (a donut or a launch), each streaked along its length.
    cx, cy = rng.uniform(0.45, 0.55), rng.uniform(0.45, 0.55)
    rr = rng.uniform(0.3, 0.38)
    a0 = rng.random() * math.tau
    span = rng.uniform(3.5, 5.5)
    ang = np.arctan2((v - cy) * 4.0 / 2.5, u - cx)
    rad = np.hypot(u - cx, (v - cy) * 4.0 / 2.5)
    da = np.mod(ang - a0, math.tau)
    on_arc = smoothstep(span, span - 0.4, da) * smoothstep(0.0, 0.3, da)
    streak = value_noise((S, S), 60, rng)
    for k, off in enumerate([0.0, 0.1]):
        band = smoothstep(0.05, 0.025, np.abs(rad - rr - off))
        ink = band * on_arc * (0.6 + 0.4 * streak)
        acc = np.maximum(acc, ink)
        order = np.maximum(order, band * on_arc * (0.4 + 0.6 * (1 - da / span)))
    # A straight launch pair too, now and then.
    if rng.random() < 0.6:
        for x in (0.42, 0.58):
            band = smoothstep(0.04, 0.015, np.abs(u - x - 0.02 * np.sin(v * 6)))
            fade = smoothstep(1.0, 0.2, v)
            acc = np.maximum(acc, band * fade * (0.5 + 0.5 * streak))
            order = np.maximum(order, band * fade)
    st.albedo = np.full((S, S, 3), 0.011, np.float32)
    st.cover = np.clip(acc, 0, 1)
    st.rough = (0.8 - 0.3 * acc).astype(np.float32)
    st.order = np.clip(order, 0.02, 1)
    return st


def paint_ghost(rng):
    st = Stamp("paint_ghost", 0.6, 4.0, 0.0)
    u, v = grid()
    # An old lane line ground off when the lanes moved: a grinder scar a little wider than the
    # line, scored across, with what is left of the paint in its texture.
    line_w = 0.1 / 0.6
    scar_w = 0.16 / 0.6
    across = np.abs(u - 0.5)
    dashes = (np.mod(v * 4.0, 3.0) < 1.8) if rng.random() < 0.5 else np.ones((S, S), bool)
    scar = smoothstep(scar_w * 0.5 + 0.01, scar_w * 0.5 - 0.01, across) * smoothstep(0.0, 0.05, v) * smoothstep(1.0, 0.95, v)
    paint = smoothstep(line_w * 0.5 + 0.005, line_w * 0.5 - 0.005, across) * dashes * scar
    n = fbm((S, S), 30, rng)
    left = paint * smoothstep(0.55, 0.9, n + value_noise((S, S), 80, rng) * 0.3) * 0.8
    score = 0.5 + 0.5 * np.sin(v * 4.0 / 0.012)
    a_col, ah, ar = asphalt(0.6, 4.0, rng, 1.0)
    scar_col = a_col * (0.8 + 0.25 * score[..., None]) * 0.85
    white = np.array([0.32, 0.32, 0.3]) if rng.random() < 0.6 else np.array([0.32, 0.25, 0.06])
    st.albedo = (scar_col * (1 - left[..., None]) + white * left[..., None]).astype(np.float32)
    st.cover = np.clip(scar * 0.75 + left * 0.25, 0, 1)
    st.height = -0.002 * scar + 0.0005 * score * scar
    st.rough = (0.88 - 0.1 * left).astype(np.float32)
    st.order = np.clip(scar * (0.5 + 0.5 * n), 0.02, 1)
    return st


def bleeding(rng):
    st = Stamp("bleeding", 0.9, 5.0, 0.0)
    u, v = grid()
    centre = 0.5 + 0.04 * np.sin(v * 5 + rng.random() * 6)
    prof = np.exp(-((u - centre) / 0.22) ** 2)
    n = fbm((S, S), 8, rng)
    k = prof * smoothstep(0.35, 0.6, n * 0.7 + prof * 0.5) * smoothstep(0.0, 0.1, v) * smoothstep(1.0, 0.9, v)
    st.albedo = np.full((S, S, 3), 0.014, np.float32) + (n * 0.006)[..., None]
    st.cover = np.clip(k, 0, 1)
    st.height = 0.0006 * k
    st.rough = (0.6 - 0.32 * k).astype(np.float32)
    st.order = np.clip(k * 1.2 + (n - 0.5) * 0.3, 0.02, 1)
    return st


def concrete_spall(rng):
    st = Stamp("concrete_spall", 2.0, 2.0, 0.03)
    u, v = grid()
    con = lin_color("Concrete034", 2.0, 2.0, CONCRETE_TILE, (0.2, 0.5))
    # A panel corner where the surface has popped off, showing the coarse aggregate.
    cx, cy = rng.uniform(0.3, 0.7), rng.uniform(0.3, 0.7)
    ang = np.arctan2(v - cy, u - cx)
    lump = sum(rng.normal(0, 1) / k * np.cos(k * ang + rng.random() * 6) for k in range(1, 7))
    t = np.hypot(u - cx, v - cy) / (0.26 * (1 + 0.2 * lump) + (fbm((S, S), 8, rng) - 0.5) * 0.06)
    inside = smoothstep(1.02, 0.96, t)
    agg = lin_color("GravelConcrete03", 2.0, 2.0, GRAVEL_TILE * 0.6, (0.6, 0.6))
    wall = smoothstep(1.0, 0.85, t)
    st.albedo = (agg * 0.9 * inside[..., None] + con * 0.85 * (1 - inside[..., None])).astype(np.float32)
    # Hairline map cracks round it in the concrete skin.
    paths = []
    for k in range(rng.integers(4, 8)):
        a = rng.random() * math.tau
        paths += crack_tree(rng, (cx + math.cos(a) * 0.26, cy + math.sin(a) * 0.26), a, rng.uniform(0.1, 0.3), 1.6, rng.uniform(0.3, 0.7), max_depth=1)
    cov, val = stroke_layer(paths)
    cov *= 1 - inside
    st.cover = np.clip(np.maximum(inside, cov), 0, 1)
    st.height = -0.02 * wall * (0.7 + 0.3 * fbm((S, S), 14, rng)) + scan_height("GravelConcrete03", 2, 2, GRAVEL_TILE * 0.6, (0.6, 0.6), 0.005) * inside
    st.rough = np.full((S, S), 0.93, np.float32)
    st.ao = 1 - 0.5 * wall * smoothstep(0.6, 0.95, t)
    st.water = wall * 0.85
    st.order = np.clip(1.15 - t * 0.7, 0.02, 1)
    st.albedo = st.albedo * (1 - cov[..., None]) + np.array([0.06, 0.06, 0.058]) * cov[..., None]
    finish_cracks(st, cov, val, 0.006)
    return st


def concrete_crack(rng):
    st = Stamp("concrete_crack", 2.0, 2.0, 0.01)
    u, v = grid()
    h0 = rng.uniform(0, math.pi)
    start = (0.5 - math.cos(h0) * 0.55, 0.5 - math.sin(h0) * 0.55)
    paths = crack_tree(rng, start, h0, 1.1, 3.5, 1.0, max_depth=2, branch_p=0.3, pull=h0, wander=0.3)
    cov, val = stroke_layer(paths)
    # A fault: one side has settled a few millimetres, with a dark wet line in the step.
    side = np.cos(h0 + math.pi / 2) * (u - 0.5) + math.sin(h0 + math.pi / 2) * (v - 0.5)
    settle = smoothstep(-0.01, 0.01, side + (blur(cov, 2) - 0.1) * 0) * 0.004
    near = blur(cov, 10) * 4.0
    st.albedo = np.full((S, S, 3), 0.045, np.float32) + (fbm((S, S), 10, rng) * 0.02)[..., None]
    stain = np.clip(near, 0, 1) * 0.5
    st.cover = np.clip(np.maximum(cov, stain * 0.35), 0, 1)
    st.order = np.where(cov > 0.02, val, np.clip(near * 0.5, 0.02, 1))
    st.height = -settle * np.clip(near, 0, 1)
    st.rough[:] = 0.9
    finish_cracks(st, cov, val, 0.01)
    return st


# Placement flags the table carries (RoadWear reads them).
DEEP = 1          # real depth: parallax in the shader, a bump for a car
ALIGN = 2         # keeps to the road's axis (cracks along, ruts, tar snakes, edge break-up)
CONCRETE = 4      # lies on concrete (pavements, alleys, car parks)
POOLS = 8         # holds water after rain
SURFACE = 16      # a stain on the surface (fades and greys with age instead of dulling)
KERB = 32         # its u = 0 side goes to the kerb


def build_all():
    stamps = []
    flags = []

    def add(st, f):
        stamps.append(st)
        flags.append(f)

    R = lambda i: np.random.default_rng(1000 + i)
    add(pothole("pothole_shallow", 1.0, 0.04, R(0), "shallow"), DEEP | POOLS)
    add(pothole("pothole_deep", 1.2, 0.11, R(1), "deep"), DEEP | POOLS)
    add(pothole("pothole_gravel", 1.1, 0.03, R(2), "gravel"), DEEP)
    add(pothole("pothole_water", 1.6, 0.09, R(3), "water"), DEEP | POOLS)
    add(pothole_cluster(R(4)), DEEP | POOLS)
    add(alligator(R(5)), ALIGN | POOLS)
    add(block_crack(R(6)), 0)
    add(crack_long(R(7)), ALIGN)
    add(crack_long(R(8), "crack_trans", 3.5, 0.8, across=True), ALIGN)
    add(tar_snake(R(9)), ALIGN)
    add(tar_snake(R(10), "tar_network", 5.0, 5.0, network=True), 0)
    add(ravelling(R(11)), 0)
    add(patch(R(12), "patch_raised", 1.8, 2.4, 0.012), 0)
    add(patch(R(13), "patch_sunken", 1.6, 2.0, -0.018), POOLS)
    add(patch(R(14), "sawcut_patch", 2.4, 3.0, 0.004, aerial=True, saw=True), ALIGN)
    add(patch(R(15), "trench_strip", 1.0, 8.0, -0.006, aerial=True, saw=True, strip=True), ALIGN | POOLS)
    add(rut(R(16)), ALIGN | POOLS)
    add(edge_break(R(17)), ALIGN | KERB | POOLS | DEEP)
    add(shoving(R(18)), ALIGN | POOLS)
    add(oil(R(19)), SURFACE)
    add(burnout(R(20)), SURFACE)
    add(paint_ghost(R(21)), ALIGN | SURFACE)
    add(bleeding(R(22)), ALIGN | SURFACE)
    add(concrete_spall(R(23)), CONCRETE | POOLS)
    add(concrete_crack(R(24)), CONCRETE)
    assert len(stamps) <= 25
    return stamps, flags


def slope_and_ao(st):
    h = st.height.astype(np.float64)
    du = st.w / S
    dv = st.h / S
    hp = np.pad(h, 1, mode="edge")
    sx = (hp[1:-1, 2:] - hp[1:-1, :-2]) / (2 * du)
    sz = (hp[2:, 1:-1] - hp[:-2, 1:-1]) / (2 * dv)
    # Stored as the normal's x and z components (y up), 0.5 + n / 2.
    n = np.stack([-sx, np.ones_like(sx), -sz], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    # Cavity: lower than the neighbourhood is darker.
    cav = h - blur(h.astype(np.float32), 6)
    cavity = np.clip(1.0 + cav / 0.01 * 0.25, 0.4, 1.0)
    ao = np.clip(st.ao * cavity, 0, 1)
    return n, ao


def main():
    os.makedirs(OUT, exist_ok=True)
    stamps, flags = build_all()
    color = np.zeros((ATLAS, ATLAS, 4), np.float32)
    nrm = np.zeros((ATLAS, ATLAS, 3), np.float32)
    nrm[..., 0] = 0.5
    nrm[..., 1] = 0.5
    nrm[..., 2] = 1.0
    data = np.zeros((ATLAS, ATLAS, 4), np.float32)
    data[..., 0] = 0.5
    data[..., 1] = 0.8
    fade = edge_fade(0.04)
    for i, st in enumerate(stamps):
        col, row = i % GRID, i // GRID
        x0 = int(round(col * CELL + (CELL - S) / 2))
        y0 = int(round(row * CELL + (CELL - S) / 2))
        n, ao = slope_and_ao(st)
        st.depth = float(max(st.depth, -st.height.min()))
        cover = np.clip(st.cover * fade, 0, 1)
        color[y0:y0 + S, x0:x0 + S, :3] = to_srgb(np.clip(st.albedo, 0, 1))
        color[y0:y0 + S, x0:x0 + S, 3] = cover
        nrm[y0:y0 + S, x0:x0 + S, 0] = 0.5 + 0.5 * n[..., 0]
        nrm[y0:y0 + S, x0:x0 + S, 1] = 0.5 + 0.5 * n[..., 2]
        nrm[y0:y0 + S, x0:x0 + S, 2] = ao
        data[y0:y0 + S, x0:x0 + S, 0] = np.clip(0.5 + st.height * fade / (2 * HEIGHT_RANGE), 0, 1)
        data[y0:y0 + S, x0:x0 + S, 1] = np.clip(st.rough, 0, 1)
        data[y0:y0 + S, x0:x0 + S, 2] = np.clip(st.water, 0, 1)
        data[y0:y0 + S, x0:x0 + S, 3] = np.clip(st.order, 0, 1)
        print("%2d %-16s %4.1f x %4.1f m  depth %.3f  cover %.2f  height %.3f..%.3f" % (
            i, st.name, st.w, st.h, st.depth, cover.mean(), st.height.min(), st.height.max()))
    # Bleed the stamps' colour out under zero coverage, so mips never pull black into an edge.
    a = color[..., 3:4]
    rgb = color[..., :3] * a
    w = a.copy()
    for r in (2, 6, 16, 40):
        rgb_b = np.stack([blur(rgb[..., c], r) for c in range(3)], -1)
        w_b = blur(w[..., 0], r)[..., None]
        fill = rgb_b / np.maximum(w_b, 1e-5)
        color[..., :3] = np.where(a > 0.02, color[..., :3], np.where(w_b > 1e-4, fill, color[..., :3]))
        rgb = color[..., :3] * np.maximum(a, (w_b > 1e-4).astype(np.float32))
        w = np.maximum(w, (w_b > 1e-4).astype(np.float32))
    save = lambda arr, name, mode: Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), mode).save(os.path.join(OUT, name), optimize=True)
    save(color, "road_wear_color.png", "RGBA")
    save(nrm, "road_wear_nrm.png", "RGB")
    save(data, "road_wear_data.png", "RGBA")
    # A preview of every stamp for the docs.
    prev = Image.fromarray((np.clip(color[..., :3] * color[..., 3:4] + 0.25 * (1 - color[..., 3:4]), 0, 1) * 255).astype(np.uint8)).resize((1024, 1024))
    pdir = os.path.join(ROOT, "build", "road_wear")
    os.makedirs(pdir, exist_ok=True)
    open(os.path.join(pdir, ".gdignore"), "w").close()
    prev.save(os.path.join(pdir, "preview.png"))
    with open(os.path.join(ROOT, "scripts", "world", "road_wear_table.gd"), "w") as f:
        f.write("class_name RoadWearTable\nextends RefCounted\n")
        f.write("## Written by tools/make_road_wear.py: the 25 road wear stamps in its atlas, in cell order\n")
        f.write("## (index = row * GRID + column). [name, size in metres (u across the road, v along it),\n")
        f.write("## deepest point below the road (m), flags]. Do not edit by hand: change the generator.\n\n")
        f.write("const GRID := %d\nconst STAMP_PX := %d\nconst ATLAS_PX := %d\nconst HEIGHT_RANGE := %.3f\n" % (GRID, S, ATLAS, HEIGHT_RANGE))
        f.write("const DEEP := %d\nconst ALIGN := %d\nconst CONCRETE := %d\nconst POOLS := %d\nconst SURFACE := %d\nconst KERB := %d\n\n" % (DEEP, ALIGN, CONCRETE, POOLS, SURFACE, KERB))
        f.write("const STAMPS := [\n")
        for st, fl in zip(stamps, flags):
            f.write('\t["%s", Vector2(%.2f, %.2f), %.3f, %d],\n' % (st.name, st.w, st.h, st.depth, fl))
        f.write("]\n")
    print("wrote", OUT)


if __name__ == "__main__":
    main()
