#!/usr/bin/env python3
"""The street HDRI the sky's cubemap pass mirrors under (and just over) its horizon.

Source: Poly Haven's "San Giuseppe Bridge" (CC0, 2K .hdr; polyhaven.com/a/san_giuseppe_bridge,
mirrored in three.js's examples/textures/equirectangular/). A canal street in daylight: facades
both sides, paving, a bridge, water. Its own sky is cut out (the game's sky stays the game's).

Writes assets/textures/sky/street_hdri.png, 1024 x 512 RGBA, equirectangular like the source
(u 0..1 = longitude, v 0 = straight up):
  rgb  the scene's colour relative to the mean of its street band (sRGB-encoded x 0.5, so 0.5
       is the mean): sky.gdshader multiplies it by the drawn horizon's brightness, so the street
       keeps the brightness the flat grey had and gains its structure;
  a    1 where something stands (facades, paving, water), 0 where its sky is.

  python3 tools/reflections/make_street_hdri.py build/hdri/san_giuseppe_bridge_2k.hdr
"""
import sys
import numpy as np
from PIL import Image, ImageFilter


def read_hdr(path):
    data = open(path, 'rb').read()
    i = data.index(b'\n\n')
    rest = data[i + 2:]
    j = rest.index(b'\n')
    _, h, _, w = rest[:j].decode().split()
    h, w = int(h), int(w)
    rest = rest[j + 1:]
    out = np.zeros((h, w, 4), np.uint8)
    p = 0
    for y in range(h):
        assert rest[p] == 2 and rest[p + 1] == 2, "only new-style RLE"
        p += 4
        for c in range(4):
            x = 0
            while x < w:
                n = rest[p]
                p += 1
                if n > 128:
                    n -= 128
                    out[y, x:x + n, c] = rest[p]
                    p += 1
                else:
                    out[y, x:x + n, c] = np.frombuffer(rest[p:p + n], np.uint8)
                    p += n
                x += n
    e = out[..., 3].astype(np.int32)
    f = np.where(e > 0, np.ldexp(1.0, e - 136), 0.0)
    return out[..., :3].astype(np.float32) * f[..., None]


def main():
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else 'assets/textures/sky/street_hdri.png'
    a = read_hdr(src)
    # Down to 1024 x 512 by box filter (the source is 2048 x 1024).
    h, w = a.shape[:2]
    a = a.reshape(512, h // 512, 1024, w // 1024, 3).mean(axis=(1, 3))
    h, w = 512, 1024
    lum = a @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    v = (np.arange(h) + 0.5) / h
    up = np.cos(v * np.pi)[:, None] * np.ones((1, w))
    # Its sky: over the horizon, bright, bluer than red (the facades are warm stone and render).
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    sky = (up > 0.02) & (b > r * 1.08) & (lum > 0.25)
    sky |= up > 0.75
    stand = (~sky).astype(np.float32)
    m = Image.fromarray((stand * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3))
    m = m.filter(ImageFilter.GaussianBlur(1.2))
    stand = np.asarray(m).astype(np.float32) / 255.0
    stand[up < 0.0] = 1.0
    # Relative to the street band's mean (below the horizon, the paving and the water), with the
    # sun's highlights rolled off so a glint does not become a white blotch on every car door.
    band = (up < -0.05) & (up > -0.9)
    mean = float(lum[band].mean())
    rel = a / mean
    rl = rel @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    roll = np.where(rl > 1.4, (1.4 + np.log1p(np.maximum(rl - 1.4, 0.0))) / np.maximum(rl, 1e-6), 1.0)
    rel = rel * roll[..., None]
    enc = np.clip(rel * 0.5, 0.0, 1.0)
    srgb = np.where(enc <= 0.0031308, enc * 12.92, 1.055 * np.power(enc, 1 / 2.4) - 0.055)
    rgba = np.dstack([srgb, stand])
    Image.fromarray((np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGBA').save(dst, optimize=True)
    print('wrote %s, street mean %.3f, standing share over the horizon %.2f' % (dst, mean, float(stand[(up > 0) & (up < 0.5)].mean())))


main()
