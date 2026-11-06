#!/usr/bin/env python3
"""The sky's cloud noise: two small tileable textures the cumulus march samples.

    python3 tools/sky/make_cloud_noise.py      (needs numpy and Pillow; a few seconds)

Writes, both imported as Images (lossless) and turned into textures by DayNight:

  assets/textures/sky/cloud_shape3d.png   64 x 64 x 64 volume, the slices stacked down the image
      (64 x 4096 RGB). R: Perlin-Worley at 4 cells a tile - billows, which is what makes a cumulus
      top a cauliflower rather than a lump of fog. G: Worley fbm at 8 / 16 / 32 cells (the
      erosion of the edges). B: Worley fbm at 16 / 32 / 64 (the finest wisps).
  assets/textures/sky/cloud_weather.png   256 x 256 RGB, tiling. R: where cumulus stand (Perlin
      fbm sharpened by Worley clusters, so they come in fields and streets with blue between).
      G: how tall each one grows. B: a slow Perlin for the mid deck.

Everything is original procedural noise (no source images), seeded, so a rebuild is identical.
"""
import os
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "assets", "textures", "sky")
RNG = np.random.default_rng(20261005)


def perlin(shape, cells):
	"""Tileable gradient noise in [-1, 1] on a grid of `shape`, `cells` lattice cells a tile."""
	dim = len(shape)
	grads = RNG.normal(size=(cells,) * dim + (dim,))
	grads /= np.linalg.norm(grads, axis=-1, keepdims=True)
	coords = np.meshgrid(*[np.arange(n) * cells / n for n in shape], indexing="ij")
	i0 = [np.floor(c).astype(int) for c in coords]
	f = [c - i for c, i in zip(coords, i0)]
	fade = [t * t * t * (t * (t * 6 - 15) + 10) for t in f]
	out = np.zeros(shape)
	for corner in range(1 << dim):
		off = [(corner >> d) & 1 for d in range(dim)]
		idx = tuple((i0[d] + off[d]) % cells for d in range(dim))
		g = grads[idx]
		dot = sum(g[..., d] * (f[d] - off[d]) for d in range(dim))
		w = np.ones(shape)
		for d in range(dim):
			w = w * (fade[d] if off[d] else 1 - fade[d])
		out += w * dot
	return out * (1.6 if dim == 3 else 1.4)


def worley(shape, cells):
	"""Tileable inverted Worley (1 at a feature point, 0 far from it), F1 distance."""
	dim = len(shape)
	pts = RNG.random((cells,) * dim + (dim,))
	coords = np.meshgrid(*[np.arange(n) * cells / n for n in shape], indexing="ij")
	i0 = [np.floor(c).astype(int) for c in coords]
	best = np.full(shape, 9.0)
	import itertools
	for off in itertools.product((-1, 0, 1), repeat=dim):
		idx = tuple((i0[d] + off[d]) % cells for d in range(dim))
		p = pts[idx]
		d2 = sum((i0[d] + off[d] + p[..., d] - coords[d]) ** 2 for d in range(dim))
		best = np.minimum(best, d2)
	return 1.0 - np.clip(np.sqrt(best), 0.0, 1.0)


def fbm(fn, shape, cells, octaves, gain=0.5):
	v = np.zeros(shape)
	amp = 1.0
	tot = 0.0
	for o in range(octaves):
		v += fn(shape, cells * (2 ** o)) * amp
		tot += amp
		amp *= gain
	return v / tot


def remap(v, lo, hi, nlo, nhi):
	return nlo + (v - lo) * (nhi - nlo) / (hi - lo)


def norm01(v):
	lo, hi = np.percentile(v, 0.5), np.percentile(v, 99.5)
	return np.clip((v - lo) / (hi - lo), 0.0, 1.0)


def volume():
	s = (64, 64, 64)
	p = fbm(perlin, s, 4, 3) * 0.5 + 0.5
	w = fbm(worley, s, 4, 3, 0.55)
	# Perlin-Worley (Schneider, "The Real-time Volumetric Cloudscapes of Horizon Zero Dawn"):
	# the Perlin's connectedness with the Worley's billows.
	pw = np.clip(remap(p, w - 1.0, 1.0, 0.0, 1.0), 0.0, 1.0)
	r = norm01(pw)
	g = norm01(fbm(worley, s, 8, 3, 0.6))
	b = norm01(fbm(worley, s, 16, 3, 0.6))
	vol = np.stack([r, g, b], axis=-1)  # z, y, x? indexed [x, y, z]
	# Slices along z, stacked down the image: image row = z * 64 + y, column = x.
	img = np.transpose(vol, (2, 1, 0, 3)).reshape(64 * 64, 64, 3)
	return (img * 255.0 + 0.5).astype(np.uint8)


def weather():
	s = (256, 256)
	base = fbm(perlin, s, 6, 4) * 0.5 + 0.5
	clusters = fbm(worley, s, 10, 2, 0.5)
	cov = norm01(base * 0.65 + clusters * 0.55)
	height = norm01(fbm(perlin, s, 4, 3) * 0.6 + fbm(worley, s, 12, 2) * 0.4)
	mid = norm01(fbm(perlin, s, 8, 4))
	img = np.stack([cov, height, mid], axis=-1)
	# Image rows are y; the arrays are [x, y].
	img = np.transpose(img, (1, 0, 2))
	return (img * 255.0 + 0.5).astype(np.uint8)


def main():
	os.makedirs(OUT, exist_ok=True)
	Image.fromarray(volume(), "RGB").save(os.path.join(OUT, "cloud_shape3d.png"), optimize=True)
	Image.fromarray(weather(), "RGB").save(os.path.join(OUT, "cloud_weather.png"), optimize=True)
	print("wrote", OUT)


if __name__ == "__main__":
	main()
