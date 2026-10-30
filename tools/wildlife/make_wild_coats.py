#!/usr/bin/env python3
"""Paints the urban wildlife's coats (WildSpecies, scripts/npc/wild_species.gd) on the dogs' chart
(tools/dogs/make_dog_coats.py: the same pieces, rows and landmarks, since the animals are built by
DogMesh from their own proportions), into assets/textures/dogs/wild_<look>.jpg beside the dogs'.

  coyote     grizzled tawny-grey, a darker saddle of black-tipped guard hairs, cream throat and
             belly, rufous backs of the ears and outside of the legs, a black tail tip and a dark
             stripe down the front of each foreleg
  deer       a mule deer's winter grey-brown, the white rump patch round a white tail with a black
             tip, a white throat bib and muzzle band, a dark forehead "V", dark hooves
  raccoon    grizzled grey, the black mask through the eyes under white brows, a white muzzle, black
             rings round the tail, dark hands and feet
  squirrel   a fox squirrel's rusty grizzled grey back, orange belly, cheeks and feet, the tail's
             hairs banded and orange at the fringe
  rabbit     a cottontail's grizzled grey-brown, buff nape, pale belly, the tail white underneath,
             dark rims on the ears

Everything is original procedural paint. Run:

  python3 tools/wildlife/make_wild_coats.py [look ...]

then `godot --headless --path . --import` and `python3 tools/fix_texture_imports.py
assets/textures/dogs`, and commit the JPGs and their .import files.
"""
import importlib.util
import os
import sys

import numpy as np

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("dog_coats", os.path.join(_here, "..", "dogs", "make_dog_coats.py"))
dc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(dc)

srgb, smooth, mix, blank = dc.srgb, dc.smooth, dc.mix, dc.blank
EYE_U, EYE_V, NOSE_V = dc.EYE_U, dc.EYE_V, dc.NOSE_V


class Wild(dc.Look):
    """Shared helpers: agouti grizzle (banded guard hairs as fine noise), a body gradient."""

    def grizzle(self, u, v, base, dark, light, amount=0.5, freq=60.0):
        g = self.n(u * 3.1 + 0.3, v * 2.7 + 0.9, freq)
        g2 = self.n(u * 5.3 + 1.7, v * 4.1 + 0.2, freq * 1.9)
        t = np.clip((g * 0.6 + g2 * 0.4 - 0.5) * 2.2, -1.0, 1.0)
        c = mix(base, dark, np.clip(-t, 0, 1) * amount)
        return mix(c, light, np.clip(t, 0, 1) * amount * 0.8)


class Coyote(Wild):
    def __init__(self, seed, pale=False):
        super().__init__(seed)
        self.tawny = srgb(150, 122, 88) * (1.12 if pale else 1.0)
        self.grey = srgb(118, 108, 96) * (1.1 if pale else 1.0)
        self.dark = srgb(48, 40, 34)
        self.cream = srgb(214, 200, 176)
        self.rufous = srgb(160, 98, 54)

    def paint(self, piece, u, v):
        n = self.n
        edge = (n.fbm(u * 2.0, v * 2.0, 6.0) - 0.5) * 0.18
        if piece == "torso":
            c = mix(self.grey, self.tawny, smooth(0.08, 0.4, u + edge))
            c = mix(c, self.cream, smooth(0.62 + edge, 0.8 + edge, u))
            c = self.grizzle(u, v, c, self.dark, self.cream, 0.55 * (1.0 - smooth(0.4, 0.7, u)))
            # The saddle of black-tipped hairs over the shoulders and back.
            sad = smooth(0.3, 0.05, u + edge) * smooth(0.15, 0.4, v) * smooth(0.85, 0.6, v)
            c = mix(c, self.dark, sad * 0.45)
            # The throat and the cheeks of the neck are cream.
            c = mix(c, self.cream, smooth(0.5, 0.68, u) * smooth(0.6, 0.8, v))
        elif piece == "head":
            c = mix(self.grey, self.tawny, smooth(0.1, 0.4, u))
            c = mix(c, self.rufous, smooth(0.42, 0.6, v) * smooth(0.0, 0.3, u) * 0.5)
            c = mix(c, self.cream, smooth(0.5, 0.62, u + edge * 0.5))
            # Pale round the eyes, a dark lip line.
            ring = smooth(0.07, 0.03, np.hypot(u - EYE_U, (v - EYE_V) * 1.3))
            c = mix(c, self.cream, ring * 0.6)
            c = self.grizzle(u, v, c, self.dark, self.cream, 0.35)
            nose = (v > NOSE_V) & (u < 0.62)
            c = np.where(nose[..., None], self.nose(u, v, srgb(28, 24, 22)), c)
        elif piece == "ear_out":
            c = mix(self.rufous, self.dark, smooth(0.7, 0.95, v) * 0.7)
        elif piece == "ear_in":
            c = blank(u, self.cream * 0.95)
        elif piece == "tail":
            c = mix(self.grey, self.cream, smooth(0.3, 0.8, u))
            c = self.grizzle(u, v, c, self.dark, self.cream, 0.6)
            # The dark gland spot near the base on top, the black tip.
            c = mix(c, self.dark, smooth(0.25, 0.0, u) * smooth(0.12, 0.2, v) * smooth(0.32, 0.24, v) * 0.7)
            c = mix(c, self.dark, smooth(0.78, 0.9, v))
        elif piece in ("front", "hind"):
            c = mix(self.rufous, self.tawny, smooth(0.0, 0.4, v))
            c = mix(c, self.cream, smooth(0.6, 0.8, np.abs(u - 0.75) < 0.2) * 0.5)
            if piece == "front":
                # The dark stripe down the front of the foreleg.
                c = mix(c, self.dark, smooth(0.06, 0.0, np.abs(u - 0.0) + 0.0) * smooth(0.3, 0.5, v) * 0.7)
            c = mix(c, self.cream, smooth(0.85, 1.0, v) * 0.4)
            c = self.grizzle(u, v, c, self.dark, self.cream, 0.25)
        else:
            c = blank(u, srgb(70, 58, 48))
        return c * self.var(u, v, 0.06)[..., None]


class Deer(Wild):
    def __init__(self, seed):
        super().__init__(seed)
        self.body = srgb(122, 110, 98)
        self.dark = srgb(54, 46, 40)
        self.white = srgb(226, 222, 212)
        self.fawn = srgb(150, 124, 96)

    def paint(self, piece, u, v):
        n = self.n
        edge = (n.fbm(u * 2.0, v * 2.0, 6.0) - 0.5) * 0.12
        if piece == "torso":
            c = mix(self.body * 0.92, self.body, smooth(0.0, 0.3, u))
            c = mix(c, self.fawn, smooth(0.45, 0.62, u) * 0.6)
            c = mix(c, self.white * 0.9, smooth(0.7 + edge, 0.85 + edge, u))
            # The white rump patch round the tail.
            rump = smooth(0.2 + edge, 0.1, v) * smooth(0.6, 0.15, u)
            c = mix(c, self.white, rump)
            # The throat bib.
            c = mix(c, self.white, smooth(0.62, 0.75, u) * smooth(0.82, 0.9, v))
            c = self.grizzle(u, v, c, self.dark, self.white, 0.25, 80.0)
        elif piece == "head":
            c = mix(self.body, self.fawn, smooth(0.2, 0.5, u) * 0.6)
            # The dark forehead "V" and crown, the white muzzle band and chin.
            vee = smooth(0.12, 0.0, np.abs(u - 0.02)) * smooth(0.15, 0.3, v) * smooth(0.6, 0.45, v)
            c = mix(c, self.dark, vee * 0.8)
            band = smooth(0.62, 0.68, v) * smooth(0.74, 0.7, v) * smooth(0.25, 0.4, u)
            c = mix(c, self.white, band)
            c = mix(c, self.white, smooth(0.55, 0.65, u) * smooth(0.5, 0.65, v))
            ring = smooth(0.08, 0.04, np.hypot(u - EYE_U, (v - EYE_V) * 1.3))
            c = mix(c, self.white, ring * 0.7)
            c = self.grizzle(u, v, c, self.dark, self.white, 0.18, 80.0)
            nose = (v > NOSE_V) & (u < 0.62)
            c = np.where(nose[..., None], self.nose(u, v, srgb(26, 22, 21)), c)
        elif piece == "ear_out":
            c = mix(self.body, self.dark, smooth(0.0, 0.25, np.minimum(u, 1.0 - u)) * 0.0 + smooth(0.85, 1.0, v) * 0.6)
            c = mix(c, self.dark, smooth(0.08, 0.0, np.minimum(u, 1.0 - u)) * 0.6)
        elif piece == "ear_in":
            c = mix(blank(u, self.white * 0.92), srgb(170, 130, 120), smooth(0.3, 0.0, np.abs(u - 0.5)) * 0.25)
        elif piece == "tail":
            c = blank(u, self.white)
            c = mix(c, srgb(20, 18, 17), smooth(0.6, 0.75, v))
        elif piece in ("front", "hind"):
            c = mix(self.body, self.fawn, smooth(0.3, 0.7, v))
            c = mix(c, self.white * 0.85, smooth(0.5, 0.8, 1.0 - np.abs(u - 0.75) * 4.0) * 0.6)
            if piece == "hind":
                # The metatarsal gland: a dark tuft outside each hock.
                c = mix(c, self.dark, smooth(0.08, 0.0, np.abs(u - 0.25)) * smooth(0.82, 0.86, v) * smooth(0.92, 0.88, v))
            c = mix(c, self.dark, smooth(0.92, 0.98, v))
        else:
            c = blank(u, srgb(34, 30, 28))
        return c * self.var(u, v, 0.05)[..., None]


class Raccoon(Wild):
    def __init__(self, seed):
        super().__init__(seed)
        self.grey = srgb(122, 116, 108)
        self.dark = srgb(28, 26, 25)
        self.white = srgb(220, 216, 206)
        self.buff = srgb(150, 132, 108)

    def paint(self, piece, u, v):
        n = self.n
        edge = (n.fbm(u * 2.0, v * 2.0, 6.0) - 0.5) * 0.15
        if piece == "torso":
            c = mix(self.grey * 0.85, self.grey, smooth(0.0, 0.3, u))
            c = mix(c, self.buff, smooth(0.55 + edge, 0.8, u) * 0.7)
            c = self.grizzle(u, v, c, self.dark, self.white, 0.7, 70.0)
        elif piece == "head":
            c = self.grizzle(u, v, self.grey, self.dark, self.white, 0.5, 70.0)
            # The mask: a black band through the eyes, down the cheeks.
            mask = smooth(0.13, 0.06, np.abs(v - EYE_V - 0.02 - (u - EYE_U) * 0.25)) * smooth(0.15, 0.3, u) * smooth(0.75, 0.6, u)
            mask = np.maximum(mask, smooth(0.1, 0.05, np.hypot(u - EYE_U, (v - EYE_V) * 0.9)))
            # The white brows over it, the white muzzle and the dark stripe down the nose.
            brow = smooth(0.06, 0.02, np.abs(v - EYE_V + 0.1)) * smooth(0.12, 0.25, u) * smooth(0.55, 0.4, u)
            c = mix(c, self.white, brow)
            c = mix(c, self.white, smooth(0.5, 0.58, v) * smooth(0.2, 0.35, u))
            c = mix(c, self.dark, mask)
            c = mix(c, self.dark, smooth(0.07, 0.0, u) * smooth(0.35, 0.45, v) * 0.8)
            nose = (v > NOSE_V) & (u < 0.62)
            c = np.where(nose[..., None], self.nose(u, v, srgb(22, 20, 19)), c)
        elif piece == "ear_out":
            c = mix(self.dark, self.white, smooth(0.75, 0.95, v))
        elif piece == "ear_in":
            c = blank(u, self.white * 0.9)
        elif piece == "tail":
            # Five black rings and the black tip over the buff-grey.
            ring = 0.5 + 0.5 * np.cos(v * np.pi * 2.0 * 5.0)
            c = mix(self.buff, self.dark, smooth(0.45, 0.65, ring))
            c = mix(c, self.dark, smooth(0.88, 0.95, v))
            c = self.grizzle(u, v, c, self.dark, self.white, 0.3)
        elif piece in ("front", "hind"):
            c = mix(self.grey, self.dark, smooth(0.45, 0.8, v))
            c = self.grizzle(u, v, c, self.dark, self.white, 0.35)
        else:
            c = blank(u, srgb(40, 36, 34))
        return c * self.var(u, v, 0.05)[..., None]


class Squirrel(Wild):
    def __init__(self, seed):
        super().__init__(seed)
        self.grey = srgb(112, 98, 84)
        self.rust = srgb(150, 104, 70)
        self.orange = srgb(178, 128, 86)
        self.dark = srgb(48, 38, 30)
        self.pale = srgb(206, 180, 150)

    def paint(self, piece, u, v):
        edge = (self.n.fbm(u * 2.0, v * 2.0, 6.0) - 0.5) * 0.15
        if piece == "torso":
            c = mix(self.grey, self.rust, smooth(0.25, 0.5, u))
            c = mix(c, self.orange, smooth(0.55 + edge, 0.7, u))
            c = self.grizzle(u, v, c, self.dark, self.pale, 0.6 * (1.0 - smooth(0.4, 0.6, u)), 90.0)
        elif piece == "head":
            c = mix(self.grey, self.orange, smooth(0.3, 0.55, u))
            ring = smooth(0.07, 0.035, np.hypot(u - EYE_U, (v - EYE_V) * 1.2))
            c = mix(c, self.pale, ring)
            c = self.grizzle(u, v, c, self.dark, self.pale, 0.4, 90.0)
            nose = (v > NOSE_V) & (u < 0.62)
            c = np.where(nose[..., None], self.nose(u, v, srgb(60, 44, 40)), c)
        elif piece in ("ear_out", "ear_in"):
            c = blank(u, self.rust if piece == "ear_out" else self.orange)
        elif piece == "tail":
            # Banded hairs: dark in the middle of the brush, orange at its fringe.
            c = mix(self.grey, self.dark, smooth(0.3, 0.0, np.abs(u - 0.5) * 2.0 - 0.4) * 0.5)
            c = mix(c, self.orange, smooth(0.25, 0.0, np.minimum(u, 1.0 - u)))
            c = self.grizzle(u, v, c, self.dark, self.orange, 0.5, 50.0)
        elif piece in ("front", "hind"):
            c = mix(self.grey, self.orange, smooth(0.2, 0.6, v))
        else:
            c = blank(u, self.orange * 0.8)
        return c * self.var(u, v, 0.06)[..., None]


class Rabbit(Wild):
    def __init__(self, seed):
        super().__init__(seed)
        self.body = srgb(128, 112, 92)
        self.dark = srgb(42, 36, 30)
        self.buff = srgb(176, 142, 100)
        self.white = srgb(228, 224, 214)

    def paint(self, piece, u, v):
        edge = (self.n.fbm(u * 2.0, v * 2.0, 6.0) - 0.5) * 0.15
        if piece == "torso":
            c = mix(self.body, self.buff, smooth(0.3, 0.55, u) * 0.6)
            c = mix(c, self.white, smooth(0.62 + edge, 0.78, u))
            # The rusty-buff nape.
            c = mix(c, self.buff * 1.05, smooth(0.8, 0.92, v) * smooth(0.4, 0.1, u) * 0.8)
            c = self.grizzle(u, v, c, self.dark, self.white, 0.65 * (1.0 - smooth(0.45, 0.65, u)), 90.0)
        elif piece == "head":
            c = mix(self.body, self.buff, smooth(0.25, 0.55, u))
            ring = smooth(0.08, 0.04, np.hypot(u - EYE_U, (v - EYE_V) * 1.2))
            c = mix(c, self.white, ring * 0.8)
            c = self.grizzle(u, v, c, self.dark, self.white, 0.45, 90.0)
            nose = (v > NOSE_V) & (u < 0.62)
            c = np.where(nose[..., None], self.nose(u, v, srgb(150, 110, 104)), c)
        elif piece == "ear_out":
            c = self.grizzle(u, v, self.body, self.dark, self.white, 0.4, 90.0)
            c = mix(c, self.dark, smooth(0.85, 0.97, v) + smooth(0.06, 0.0, np.minimum(u, 1.0 - u)) * 0.6)
        elif piece == "ear_in":
            c = mix(blank(u, self.white * 0.8), srgb(196, 150, 140), smooth(0.3, 0.0, np.abs(u - 0.5)) * 0.5)
        elif piece == "tail":
            c = mix(self.body, self.white, smooth(0.15, 0.4, u))
        elif piece in ("front", "hind"):
            c = mix(self.buff, self.white, smooth(0.6, 0.9, v) * 0.6)
            c = self.grizzle(u, v, c, self.dark, self.white, 0.3, 90.0)
        else:
            c = blank(u, self.buff)
        return c * self.var(u, v, 0.05)[..., None]


LOOKS = {
    "wild_coyote": lambda: Coyote(71),
    "wild_coyote_pale": lambda: Coyote(72, pale=True),
    "wild_deer": lambda: Deer(81),
    "wild_raccoon": lambda: Raccoon(91),
    "wild_squirrel": lambda: Squirrel(101),
    "wild_rabbit": lambda: Rabbit(111),
}


def main():
    dc.LOOKS.update(LOOKS)
    names = sys.argv[1:] or list(LOOKS)
    for name in names:
        dc.paint_look(name)


if __name__ == "__main__":
    main()
