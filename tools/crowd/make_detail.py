#!/usr/bin/env python3
"""The crowd's tiling surface detail: assets/textures/crowd/crowd_detail.png (numpy + PIL).

    python3 tools/crowd/make_detail.py

One 1024 x 1024 RGBA texture, four 512 px tiles, each tiling on its own:

    +--------+--------+
    |  skin  | jersey |      skin    5 cm a tile: pores, the crosshatch of fine lines, mottle
    +--------+--------+      jersey  6 cm: knit stitches in rows, heather, a little pilling
    | denim  | woven  |      denim   8 cm: the 3/1 twill on the diagonal, slub streaks down it
    +--------+--------+      woven   5 cm: a plain weave (shirting, suiting, canvas), slubs

RG is a tangent-space normal (0.5 = flat), B an offset to the roughness (0.5 = none), A a
multiplier on the albedo (0.5 = 1). shaders/character.gdshader samples it on the crowd rigs'
metric UV2 (tools/crowd/build_character.py: 1 unit = 1 m of surface), so the weave is the same
size on every island. At street distance the mips average the threads away and what is left is
what cloth and skin look like from a few metres: a broken-up highlight, a heathered tone and,
on denim, the vertical streaks. Our own procedural work, no source images.
"""
import math
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(REPO, "assets", "textures", "crowd", "crowd_detail.png")
N = 512
rng = np.random.default_rng(42)
yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)


def blur(a, sigma):
    """Periodic Gaussian blur (FFT), so every tile wraps."""
    fy = np.fft.fftfreq(N)[:, None]
    fx = np.fft.fftfreq(N)[None, :]
    g = np.exp(-2 * (np.pi * sigma) ** 2 * (fx ** 2 + fy ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g)).astype(np.float32)


def noise(sigma):
    n = blur(rng.random((N, N)).astype(np.float32) - 0.5, sigma)
    return n / (np.abs(n).max() + 1e-9)


def blur_x(a, sigma):
    fx = np.fft.fftfreq(N)[None, :]
    g = np.exp(-2 * (np.pi * sigma) ** 2 * fx ** 2)
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g)).astype(np.float32)


def blur_y(a, sigma):
    fy = np.fft.fftfreq(N)[:, None]
    g = np.exp(-2 * (np.pi * sigma) ** 2 * fy ** 2)
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g)).astype(np.float32)


def normal(h, strength):
    """Tangent-space normal from a periodic height map; rows run down the image, +Y up it."""
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
    gy = (np.roll(h, 1, 0) - np.roll(h, -1, 0)) * 0.5 * strength
    n = np.stack([-gx, -gy, np.ones_like(gx)], -1)
    return n / np.linalg.norm(n, axis=-1, keepdims=True)


def tile(h, strength, rough, tone):
    n = normal(h, strength)
    return np.concatenate([n[..., :2] * 0.5 + 0.5, (0.5 + rough)[..., None], (0.5 + tone)[..., None]], -1)


def splats(period, radius, depth, jitter=1.0, keep=0.85):
    """Periodic field of Gaussian dimples on a jittered grid."""
    h = np.zeros((N, N), np.float32)
    k = int(math.ceil(radius * 3))
    for gy in range(0, N, period):
        for gx in range(0, N, period):
            if rng.random() > keep:
                continue
            cx = gx + rng.random() * period * jitter
            cy = gy + rng.random() * period * jitter
            r = radius * (0.7 + 0.6 * rng.random())
            d = depth * (0.6 + 0.8 * rng.random())
            ix0, iy0 = int(cx) - k, int(cy) - k
            sy, sx = np.mgrid[iy0:iy0 + 2 * k + 1, ix0:ix0 + 2 * k + 1]
            v = -d * np.exp(-((sx - cx) ** 2 + (sy - cy) ** 2) / (r * r))
            np.add.at(h, (sy % N, sx % N), v.astype(np.float32))
    return h


# ---- skin: 5 cm, ~0.1 mm a texel --------------------------------------------------------------------
h = splats(7, 1.3, 1.0)
warp = noise(24) * 2.0
for kx, ky in ((9, 14), (-12, 10), (16, -5)):
    ph = 2 * math.pi * (kx * xx + ky * yy) / N
    h -= 0.35 * np.abs(np.sin(ph + warp)) ** 10
h += 0.25 * noise(1.0)
mottle = noise(28) * 0.6 + noise(9) * 0.4
skin = tile(h, 1.1, 0.10 * noise(14) - 0.06 * h, 0.035 * mottle + 0.02 * h)

# ---- jersey: 6 cm, ~0.12 mm a texel; a stitch is ~1 mm wide (8 px), rows ~0.8 mm (8 px here) --------
sw, rh = 8.0, 8.0
u = (xx % sw) / sw
v = ((yy + np.where((xx // sw) % 2 == 0, 0.0, rh * 0.5)) % rh) / rh
# each stitch a pair of slanted loops (the knit's V columns)
loop = np.cos((u - 0.5) * math.pi) ** 2 * (0.6 + 0.4 * np.cos(v * 2 * math.pi))
col = np.abs(np.sin(xx / sw * math.pi))
h = 0.8 * loop * col + 0.15 * noise(1.2)
heather = noise(6) * 0.5 + noise(22) * 0.5
pill = np.clip(splats(40, 2.2, -1.0, keep=0.25), 0, None)
h += 0.6 * pill
jersey = tile(h, 0.9, 0.05 * noise(18) - 0.04 * pill, 0.045 * heather + 0.03 * pill)

# ---- denim: 8 cm, ~0.16 mm a texel; the twill ridges run at 63 degrees, ~0.8 mm apart -----------------
per = 5.0
ridge = np.sin(2 * math.pi * (xx * 0.45 + yy * 0.9) / per)
h = 0.5 * np.maximum(ridge, -0.3)
# slubs: thicker, lighter warp threads streaking down the leg for a centimetre or three
slub = blur_y(rng.random((N, N)).astype(np.float32) - 0.5, 60.0)
slub = blur_x(slub, 0.6)
slub /= np.abs(slub).max() + 1e-9
weft = blur_x(rng.random((N, N)).astype(np.float32) - 0.5, 30.0)
weft /= np.abs(weft).max() + 1e-9
h += 0.35 * slub + 0.1 * noise(1.0)
denim = tile(h, 1.0, 0.04 * noise(20), 0.14 * slub + 0.04 * weft + 0.03 * ridge)

# ---- woven: 5 cm, ~0.1 mm a texel; a plain weave ~0.5 mm a thread ---------------------------------------
pw = 5.0
wx = np.sin(2 * math.pi * xx / pw)
wy = np.sin(2 * math.pi * yy / pw)
over = np.sign(np.sin(math.pi * xx / pw) * np.sin(math.pi * yy / pw))
h = 0.35 * (wx * (over > 0) + wy * (over <= 0)) + 0.1 * noise(1.0)
sx_ = blur_x(rng.random((N, N)).astype(np.float32) - 0.5, 45.0)
sy_ = blur_y(rng.random((N, N)).astype(np.float32) - 0.5, 45.0)
sl = (sx_ / (np.abs(sx_).max() + 1e-9) + sy_ / (np.abs(sy_).max() + 1e-9)) * 0.5
h += 0.2 * sl
woven = tile(h, 0.8, 0.04 * noise(16), 0.05 * sl + 0.02 * noise(8))

atlas = np.zeros((2 * N, 2 * N, 4), np.float32)
atlas[:N, :N] = skin
atlas[:N, N:] = jersey
atlas[N:, :N] = denim
atlas[N:, N:] = woven
os.makedirs(os.path.dirname(OUT), exist_ok=True)
Image.fromarray((np.clip(atlas, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(OUT, optimize=True)
print("wrote", OUT)
