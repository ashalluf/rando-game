#!/usr/bin/env python3
"""Paints the dogs' coat atlases (DogMesh, scripts/npc/dog_mesh.gd): one 1024 x 1024 JPG per
breed colourway in assets/textures/dogs/<look>.jpg, all on the same chart, so every pattern is a
function of (piece, u, v) - anatomy, not pixels. The chart (mirrored from DogMesh):

  TORSO   (0, 0, .5, .5)     u 0 the dorsal midline .. 1 the ventral, both sides mirrored;
                             v the control row / 13: 0 rump, 1 buttock, 2 croup, 3 loin, 4 last
                             rib, 5 ribs, 6 withers, 7 shoulder, 8 forechest, 9 neck base, 10-13
                             up the neck to the poll
  HEAD    (.5, 0, .5, .25)   u 0 the top midline .. 1 the throat; v row / 8: 0 neck join,
                             1 occiput, 2 skull, 3 brow, 4 stop, 5 muzzle, 6 mid muzzle, 7 nose,
                             8 tip. The eye sits at row 3.3, 62 degrees from the top.
  EAR_OUT (.5, .25, .125, .25), EAR_IN (.625, .25, .125, .25): u across, v base .. tip
  TAIL    (.75, .25, .25, .25): u 0 top .. 1 under, v base .. tip
  FRONT   (0, .5, .25, .5), HIND (.25, .5, .25, .5): u around (0 front, .25 lateral, .5 back,
                             .75 medial), v down the leg (front: shoulder .25, elbow .5, carpus
                             .75; hind: hip .2, stifle .4, gaskin .6, hock .8)
  PAW     (.5, .5, .25, .125): u 0 top .. 1 sole, v heel .. toe

Every look is original: the colours and markings of the breed, nothing copied. Run:

  python3 tools/dogs/make_dog_coats.py [look ...]

then `godot --headless --path . --import` and `python3 tools/fix_texture_imports.py
assets/textures/dogs`, and commit the JPGs and their .import files.
"""
import os
import sys

import numpy as np
from PIL import Image

SIZE = 1024
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "textures", "dogs")

R_TORSO = (0.0, 0.0, 0.5, 0.5)
R_HEAD = (0.5, 0.0, 0.5, 0.25)
R_EAR_OUT = (0.5, 0.25, 0.125, 0.25)
R_EAR_IN = (0.625, 0.25, 0.125, 0.25)
R_TAIL = (0.75, 0.25, 0.25, 0.25)
R_FRONT = (0.0, 0.5, 0.25, 0.5)
R_HIND = (0.25, 0.5, 0.25, 0.5)
R_PAW = (0.5, 0.5, 0.25, 0.125)
R_EYE = (0.75, 0.5, 0.0625, 0.0625)
PIECES = {"torso": R_TORSO, "head": R_HEAD, "ear_out": R_EAR_OUT, "ear_in": R_EAR_IN, "tail": R_TAIL,
          "front": R_FRONT, "hind": R_HIND, "paw": R_PAW}

T_ROWS = 13.0
H_ROWS = 8.0
EYE_V = 3.3 / H_ROWS
EYE_U = 62.0 / 180.0
NOSE_V = (8.0 - 0.62) / H_ROWS


def srgb(*c):
    return np.array(c, dtype=np.float32) / 255.0


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


class Noise:
    """Value noise on a periodic lattice, sampled at any (x, y) arrays."""

    def __init__(self, seed):
        self.rng = np.random.default_rng(seed)
        self.grid = self.rng.random((64, 64)).astype(np.float32)

    def __call__(self, x, y, freq=8.0):
        x = np.asarray(x) * freq
        y = np.asarray(y) * freq
        xi = np.floor(x).astype(int)
        yi = np.floor(y).astype(int)
        fx = x - xi
        fy = y - yi
        fx = fx * fx * (3 - 2 * fx)
        fy = fy * fy * (3 - 2 * fy)
        g = self.grid
        a = g[yi % 64, xi % 64]
        b = g[yi % 64, (xi + 1) % 64]
        c = g[(yi + 1) % 64, xi % 64]
        d = g[(yi + 1) % 64, (xi + 1) % 64]
        return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy

    def fbm(self, x, y, freq=4.0, octaves=4):
        s = 0.0
        amp = 0.5
        for _ in range(octaves):
            s = s + amp * self(x, y, freq)
            freq *= 2.03
            amp *= 0.5
        return s


def mix(a, b, t):
    t = np.asarray(t)[..., None]
    return a * (1 - t) + b * t


class Look:
    """A coat: colour(piece, u, v) -> (h, w, 3) floats, sRGB 0..1."""

    def __init__(self, seed):
        self.n = Noise(seed)

    def var(self, u, v, amount=0.08, freq=5.0):
        return 1.0 + (self.n.fbm(u * 1.7 + 3.1, v * 1.3 + 0.7, freq) - 0.5) * 2.0 * amount

    def nose(self, u, v, base):
        """Nose leather with its nostrils (u 0 top .. ~0.6, v NOSE_V .. 1)."""
        col = np.broadcast_to(base, u.shape + (3,)).copy()
        # The nostrils: a comma each side, low on the front of the nose.
        t = (v - NOSE_V) / (1.0 - NOSE_V)
        d = np.hypot((u - 0.42) / 0.11, (t - 0.86) / 0.12)
        col *= (1.0 - 0.7 * smooth(1.0, 0.55, d))[..., None]
        # The philtrum: a groove down the middle front.
        col *= (1.0 - 0.25 * smooth(0.06, 0.0, np.abs(u - 0.62)) * smooth(0.7, 1.0, t))[..., None]
        return col

    def paint(self, piece, u, v):
        raise NotImplementedError


def blank(u, c):
    return np.broadcast_to(c, u.shape + (3,)).copy()


class Solid(Look):
    """One colour all over (a lab, a chihuahua), lighter underneath and on the legs, darker
    along the back and on the ears, a black or liver nose and dark pads."""

    def __init__(self, seed, base, under, ear, nose, back_dark=0.12, light_legs=0.25):
        super().__init__(seed)
        self.base, self.under, self.ear, self.nose_c = base, under, ear, nose
        self.back_dark, self.light_legs = back_dark, light_legs

    def paint(self, piece, u, v):
        b, un = self.base, self.under
        if piece == "torso":
            c = mix(b, un, smooth(0.45, 0.95, u))
            c *= (1.0 - self.back_dark * smooth(0.35, 0.0, u))[..., None]
        elif piece == "head":
            c = mix(b, un, smooth(0.6, 1.0, u) * 0.7)
            c *= (1.0 - 0.15 * smooth(0.6, 0.95, v) * smooth(0.6, 0.2, u))[..., None]
            nose = (v > NOSE_V) & (u < 0.62)
            c = np.where(nose[..., None], self.nose(u, v, self.nose_c), c)
        elif piece in ("ear_out", "ear_in"):
            c = blank(u, self.ear)
            if piece == "ear_in":
                c = mix(c, un, 0.4)
        elif piece == "tail":
            c = mix(b, un, smooth(0.5, 1.0, u) * 0.5)
        elif piece in ("front", "hind"):
            c = mix(b, un, self.light_legs * smooth(0.3, 0.9, v) + 0.2 * smooth(0.6, 0.8, u) * smooth(0.85, 0.65, u))
        else:
            c = mix(b, un, 0.3)
        return c * self.var(u, v)[..., None]


class Shepherd(Look):
    """Black and tan: a black saddle over the back and down the croup, a black mask, black ears
    and the top of the tail; rich tan below, paler cream on the chest and the inner legs."""

    def __init__(self, seed, dark=False):
        super().__init__(seed)
        self.tan = srgb(158, 112, 70)
        self.cream = srgb(196, 164, 124)
        self.black = srgb(36, 31, 28)
        self.dark = dark

    def paint(self, piece, u, v):
        n = self.n
        tan, cream, blk = self.tan, self.cream, self.black
        edge = (n.fbm(u * 2.0, v * 2.0, 6.0) - 0.5) * 0.18
        if piece == "torso":
            reach = 0.5 + (0.18 if self.dark else 0.0) + edge
            # The saddle: from the croup to the withers, reaching down the ribs.
            along = smooth(0.06, 0.16, v) * smooth(0.82, 0.62, v)
            neck = smooth(0.62, 0.8, v) * 0.75
            saddle = smooth(reach + 0.06, reach - 0.06, u) * np.maximum(along, neck * smooth(0.35 + edge, 0.2 + edge, u))
            c = mix(tan, cream, smooth(0.6, 1.0, u) * 0.7)
            c = mix(c, blk, saddle)
        elif piece == "head":
            c = mix(tan, cream, smooth(0.65, 1.0, u) * 0.5)
            mask = smooth(0.5, 0.68, v) * smooth(0.9, 0.55, u) * 0.85
            cap = smooth(0.32, 0.12, u) * smooth(0.15, 0.3, v) * smooth(0.6, 0.45, v) * 0.6
            c = mix(c, blk, np.maximum(mask, cap) * (1.0 if not self.dark else 1.0))
            if self.dark:
                c = mix(c, blk, smooth(0.5, 0.2, u) * 0.85)
            nose = (v > NOSE_V) & (u < 0.62)
            c = np.where(nose[..., None], self.nose(u, v, srgb(20, 18, 17)), c)
        elif piece == "ear_out":
            c = mix(blk, tan, smooth(0.0, 0.15, v) * 0.15)
        elif piece == "ear_in":
            c = mix(cream, blk, 0.35)
        elif piece == "tail":
            c = mix(blk, tan, smooth(0.35, 0.75, u) * smooth(0.95, 0.7, v))
        elif piece in ("front", "hind"):
            c = mix(tan, cream, smooth(0.5, 0.8, u) * smooth(0.95, 0.7, u) * 0.6)
            if piece == "hind":
                # The dark runs down the back of the thigh a little.
                c = mix(c, blk, smooth(0.3, 0.12, v) * smooth(0.3, 0.5, u) * smooth(0.7, 0.5, u) * 0.7)
            if self.dark:
                c = mix(c, blk, smooth(0.35, 0.15, v) * 0.8)
        else:
            c = blank(u, tan)
        return c * self.var(u, v, 0.07)[..., None]


class Patched(Look):
    """A white dog with coloured patches: a terrier's tan or tricolour head, a pit bull's patch
    over one eye. `head` / `saddle` are colours or None."""

    def __init__(self, seed, white, head, saddle=None, nose=srgb(26, 23, 22), saddle_black=None):
        super().__init__(seed)
        self.white, self.head, self.saddle, self.nose_c = white, head, saddle, nose
        self.saddle_black = saddle_black

    def paint(self, piece, u, v):
        n = self.n
        w = self.white
        c = blank(u, w)
        edge = (n.fbm(u * 2.0, v * 2.0, 5.0) - 0.5) * 0.25
        if piece == "torso" and self.saddle is not None:
            spot = smooth(0.42 + edge, 0.3 + edge, u) * smooth(0.12, 0.2, v) * smooth(0.55, 0.45, v)
            c = mix(c, self.saddle, spot)
            if self.saddle_black is not None:
                c = mix(c, self.saddle_black, spot * smooth(0.3 + edge, 0.15 + edge, u))
        if piece == "head" and self.head is not None:
            # Over the ears and round the eyes, the blaze down the middle left white.
            patch = smooth(0.62 + edge * 0.5, 0.48 + edge * 0.5, v) * smooth(0.0, 0.12, v)
            blaze = smooth(0.1, 0.03, u) * smooth(0.25, 0.4, v)
            c = mix(c, self.head, patch * (1.0 - blaze))
        if piece == "head":
            nose = (v > NOSE_V) & (u < 0.62)
            c = np.where(nose[..., None], self.nose(u, v, self.nose_c), c)
        if piece in ("ear_out", "ear_in") and self.head is not None:
            c = blank(u, self.head)
            if piece == "ear_in":
                c = mix(c, w, 0.4)
        if piece == "tail" and self.saddle is not None:
            c = mix(c, self.saddle, smooth(0.25, 0.1, v) * 0.8)
        return c * self.var(u, v, 0.05)[..., None]


class Pit(Look):
    """A pit bull mix: a short coat in one colour (blue-grey, or brindle - dark stripes over
    fawn), a white blaze on the chest and throat, white toes."""

    def __init__(self, seed, base, nose, brindle=False):
        super().__init__(seed)
        self.base, self.nose_c, self.brindle = base, nose, brindle
        self.white = srgb(222, 216, 206)

    def paint(self, piece, u, v):
        n = self.n
        b = self.base
        c = blank(u, b)
        if self.brindle and piece in ("torso", "head", "front", "hind", "tail"):
            # Brindle: fine, broken streaks running down the body (round it, so along v on the
            # torso chart they are close together), never a tiger's bold bands.
            warp = n.fbm(u * 1.5, v * 1.5, 3.0) * 2.0
            stripes = np.sin(v * 140.0 + warp * 9.0 + u * 7.0) * 0.5 + 0.5
            broken = n(u * 6.0 + 9.0, v * 25.0, 9.0)
            dark = smooth(0.55, 0.85, stripes * 0.65 + broken * 0.45)
            c = mix(c, srgb(52, 36, 24), dark * 0.7)
        edge = (n.fbm(u * 2.0, v * 2.0, 5.0) - 0.5) * 0.2
        if piece == "torso":
            blaze = smooth(0.78 + edge, 0.9 + edge, u) * smooth(0.5, 0.6, v) * smooth(0.95, 0.8, v)
            c = mix(c, self.white, blaze)
        if piece == "head":
            throat = smooth(0.82 + edge, 0.95, u) * smooth(0.0, 0.3, v)
            stripe = smooth(0.05, 0.0, u) * smooth(0.4, 0.5, v) * smooth(0.75, 0.6, v) * 0.8
            c = mix(c, self.white, np.maximum(throat, stripe))
            nose = (v > NOSE_V) & (u < 0.62)
            c = np.where(nose[..., None], self.nose(u, v, self.nose_c), c)
        if piece == "paw":
            c = mix(c, self.white, smooth(0.25, 0.65, v))
        if piece in ("front", "hind"):
            c = mix(c, self.white, smooth(0.88, 1.0, v) * 0.8)
        return c * self.var(u, v, 0.06)[..., None]


class Husky(Look):
    """A husky: a dark saddle and cap fading through the coat's colour to white on the belly,
    the legs, the face mask and under the tail; the spectacles round the eyes; dark ear backs."""

    def __init__(self, seed, dark, mid):
        super().__init__(seed)
        self.dark, self.mid = dark, mid
        self.white = srgb(226, 224, 220)

    def paint(self, piece, u, v):
        n = self.n
        d, m, w = self.dark, self.mid, self.white
        edge = (n.fbm(u * 2.0, v * 2.0, 6.0) - 0.5) * 0.2
        if piece == "torso":
            c = mix(d, m, smooth(0.12, 0.42, u + edge))
            c = mix(c, w, smooth(0.5 + edge, 0.66 + edge, u))
            # The neck's ruff: a white collar line round the throat.
            c = mix(c, w, smooth(0.7, 0.85, v) * smooth(0.5, 0.3, u + edge) * 0.0)
        elif piece == "head":
            c = mix(d, m, smooth(0.15, 0.4, u))
            mask = smooth(0.38 + edge * 0.4, 0.5, u)
            # Spectacles over the eyes, the white muzzle.
            spec = smooth(0.09, 0.04, np.hypot(u - EYE_U + 0.04, (v - EYE_V + 0.03) * 1.4))
            muzzle = smooth(0.48, 0.56, v) * smooth(0.0, 0.08, u)
            c = mix(c, w, np.maximum(np.maximum(mask, spec), muzzle))
            # The dark line from the stop up the forehead stays.
            c = mix(c, d, smooth(0.06, 0.0, u) * smooth(0.2, 0.3, v) * smooth(0.5, 0.42, v) * 0.6)
            nose = (v > NOSE_V) & (u < 0.62)
            c = np.where(nose[..., None], self.nose(u, v, srgb(24, 22, 21)), c)
        elif piece == "ear_out":
            c = mix(d, m, 0.25)
        elif piece == "ear_in":
            c = blank(u, w)
        elif piece == "tail":
            c = mix(mix(d, m, 0.4), w, smooth(0.35, 0.7, u))
            c = mix(c, d, smooth(0.85, 1.0, v) * smooth(0.6, 0.3, u))
        elif piece in ("front", "hind"):
            c = mix(m, w, smooth(0.12, 0.35, v + edge))
        else:
            c = blank(u, w)
        return c * self.var(u, v, 0.05)[..., None]


LOOKS = {
    "lab_yellow": lambda: Solid(11, srgb(212, 166, 100), srgb(228, 196, 142), srgb(190, 138, 76), srgb(30, 26, 25)),
    "lab_black": lambda: Solid(12, srgb(34, 31, 30), srgb(42, 37, 34), srgb(28, 26, 25), srgb(20, 19, 19), 0.05, 0.05),
    "lab_chocolate": lambda: Solid(13, srgb(84, 52, 33), srgb(102, 66, 44), srgb(70, 42, 27), srgb(74, 48, 40), 0.1, 0.1),
    "shepherd": lambda: Shepherd(21),
    "shepherd_dark": lambda: Shepherd(22, dark=True),
    "terrier_tan": lambda: Patched(31, srgb(232, 228, 220), srgb(176, 108, 52)),
    "terrier_tricolor": lambda: Patched(32, srgb(232, 228, 220), srgb(170, 102, 48), srgb(170, 102, 48), saddle_black=srgb(22, 20, 19)),
    "chihuahua_fawn": lambda: Solid(41, srgb(214, 168, 112), srgb(236, 210, 170), srgb(196, 146, 92), srgb(44, 34, 31), 0.1, 0.3),
    "chihuahua_blacktan": lambda: Shepherd(42, dark=True),
    "pitbull_blue": lambda: Pit(51, srgb(98, 98, 104), srgb(62, 60, 63)),
    "pitbull_brindle": lambda: Pit(52, srgb(128, 90, 58), srgb(30, 26, 25), brindle=True),
    "pitbull_white": lambda: Patched(53, srgb(226, 220, 210), srgb(190, 140, 92), None, nose=srgb(120, 82, 76)),
    "husky_grey": lambda: Husky(61, srgb(52, 52, 55), srgb(128, 128, 132)),
    "husky_red": lambda: Husky(62, srgb(122, 66, 34), srgb(176, 110, 66)),
}


def paint_look(name):
    look = LOOKS[name]()
    img = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    img[:] = 0.5
    for piece, (rx, ry, rw, rh) in PIECES.items():
        x0, y0 = int(rx * SIZE), int(ry * SIZE)
        w, h = int(rw * SIZE), int(rh * SIZE)
        uu, vv = np.meshgrid((np.arange(w) + 0.5) / w, (np.arange(h) + 0.5) / h)
        img[y0:y0 + h, x0:x0 + w] = np.clip(look.paint(piece, uu, vv), 0.0, 1.0)
    # The eye's rect is never sampled for colour (the shader draws the eye); fill it dark.
    ex, ey = int(R_EYE[0] * SIZE), int(R_EYE[1] * SIZE)
    img[ey:ey + int(R_EYE[3] * SIZE), ex:ex + int(R_EYE[2] * SIZE)] = 0.05
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".jpg")
    Image.fromarray((img * 255.0 + 0.5).astype(np.uint8)).save(path, quality=90)
    print(path)


def main():
    names = sys.argv[1:] or list(LOOKS)
    for name in names:
        paint_look(name)


if __name__ == "__main__":
    main()
