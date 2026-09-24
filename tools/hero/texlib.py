"""Texture helpers for prep_textures.py (numpy + PIL, no Blender)."""
import os

import numpy as np
from PIL import Image


def srgb_to_lin(c):
    c = np.asarray(c, np.float32)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def to8(a):
    return (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)


def save(a, path, size=None, quality=92):
    """RGB(A) or grey float array -> jpg/png, resized with Lanczos when size is given."""
    a = np.asarray(a)
    if a.ndim == 2:
        a = np.repeat(a[..., None], 3, 2)
    im = Image.fromarray(to8(a))
    if size and im.size[0] != size:
        h = int(round(size * im.size[1] / im.size[0]))
        # channel by channel: PIL resizes RGBA premultiplied, which zeroes the colour of every
        # texel whose alpha is 0 - and in a data mask alpha is just a fourth channel
        im = Image.merge(im.mode, [c.resize((size, h), Image.LANCZOS) for c in im.split()])
    if path.endswith(".jpg"):
        im.convert("RGB").save(path, quality=quality)
    else:
        im.save(path, optimize=True)
    return os.path.basename(path)


def blur(a, sigma):
    """Gaussian blur of a 2D array via FFT (wraps round - fine for tiling noise)."""
    if sigma <= 0:
        return a
    h, w = a.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-2 * (np.pi * sigma) ** 2 * (fx ** 2 + fy ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g)).astype(np.float32)


def tile_noise(rng, size, sigma):
    """Tileable band-limited noise, zero mean, unit peak."""
    n = blur(rng.random((size, size)).astype(np.float32) - 0.5, sigma)
    return n / (np.abs(n).max() + 1e-9)


def height_to_normal(h, strength):
    """Tangent-space normal (OpenGL, +Y up the image) from a tiling height map (pixels)."""
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
    gy = (np.roll(h, 1, 0) - np.roll(h, -1, 0)) * 0.5 * strength  # rows run down, +Y runs up
    n = np.stack([-gx, -gy, np.ones_like(gx)], -1)
    return n / np.linalg.norm(n, axis=-1, keepdims=True)


def encode_normal(n):
    return n * 0.5 + 0.5


def dilate(img, cov, iters=10):
    """Push colours out of covered texels into empty ones, so mips and bilinear filtering never
    pull in the background at a UV seam."""
    img = img.copy()
    cov = cov.copy()
    for _ in range(iters):
        acc = np.zeros_like(img, dtype=np.float32)
        cnt = np.zeros(cov.shape, np.float32)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (-1, -1), (1, -1), (-1, 1)):
            c = np.roll(np.roll(cov, dy, 0), dx, 1)
            v = np.roll(np.roll(img, dy, 0), dx, 1)
            if img.ndim == 3:
                acc += v * c[..., None]
            else:
                acc += v * c
            cnt += c
        new = (~cov) & (cnt > 0)
        if img.ndim == 3:
            img[new] = acc[new] / cnt[new][:, None]
        else:
            img[new] = acc[new] / cnt[new]
        cov = cov | new
    return img


def surface_normal_map(height_fn, P, N, T, B, cov, eps=0.0004, chunk=400000):
    """Tangent-space normal map of a height field defined on the 3D surface. height_fn(points,
    sl) -> heights (metres, along the normal) or a dict of several; sl slices the covered texels
    in np.nonzero(cov) order, for per-texel attributes. T and B are dP/du and dP/dv per texel (Blender UV, v
    up), which is the frame a baked OpenGL normal map is measured in."""
    idx = np.nonzero(cov)
    p = P[idx].astype(np.float64)
    n = N[idx].astype(np.float64)
    t = T[idx].astype(np.float64)
    b = B[idx].astype(np.float64)
    t = t - n * np.sum(t * n, 1, keepdims=True)
    t /= np.maximum(np.linalg.norm(t, axis=1, keepdims=True), 1e-12)
    b = b - n * np.sum(b * n, 1, keepdims=True) - t * np.sum(b * t, 1, keepdims=True)
    bl = np.linalg.norm(b, axis=1, keepdims=True)
    b = np.where(bl > 1e-12, b / np.maximum(bl, 1e-12), np.cross(n, t))
    outs = {}
    for s in range(0, len(p), chunk):
        e = slice(s, s + chunk)
        h0 = height_fn(p[e], e)
        ht = height_fn(p[e] + t[e] * eps, e)
        hb = height_fn(p[e] + b[e] * eps, e)
        single = not isinstance(h0, dict)
        if single:
            h0, ht, hb = {"": h0}, {"": ht}, {"": hb}
        for k in h0:
            dt = (ht[k] - h0[k]) / eps
            db = (hb[k] - h0[k]) / eps
            v = np.stack([-dt, -db, np.ones_like(dt)], 1)
            outs.setdefault(k, np.zeros((len(p), 3)))[e] = v / np.linalg.norm(v, axis=1, keepdims=True)
    imgs = {}
    for k, out in outs.items():
        img = np.zeros(P.shape, np.float32)
        img[..., 2] = 1.0
        img[idx] = out
        imgs[k] = img
    return imgs[""] if list(imgs) == [""] else imgs


def raster_values(values, cov, fill=0.0):
    img = np.full(cov.shape + np.shape(values)[1:], fill, np.float32)
    img[np.nonzero(cov)] = values
    return img


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)
