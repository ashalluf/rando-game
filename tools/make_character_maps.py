#!/usr/bin/env python3
"""Bake the character surface maps (mask + normal) for the rigged pedestrian models.

    python3 tools/make_character_maps.py                  # both rigs, writes assets/models/
    python3 tools/make_character_maps.py --debug out/     # plus classification previews

WHY THIS EXISTS
---------------
The generated rigs ship ONE 1K colour photo and nothing else: no normal map, no roughness map,
one material.  Under Forward+ with AgX and SSIL a whole crowd therefore renders as smooth
plastic mannequins - a flat painting stretched over a smooth mesh reflects light like a
billiard ball, whatever the picture on it shows.

shaders/character.gdshader used to make up for the missing masks by classifying every pixel at
runtime as skin / cloth / hair from its hue, saturation and brightness.  That produced two
shipped defects, both invisible for weeks:

  * Forward+ hands a `source_color` texture back LINEARISED and the Compatibility renderer hands
    back raw sRGB, so every threshold was in the wrong colour space on desktop and no garment
    was ever recoloured in the Mac build.
  * Hair reached 0.8 % of head pixels, so the whole hair palette was dead code.

Both are the same bug: a per-pixel guess, made a million times a frame, that nobody can look at.
This tool makes the guess ONCE, offline, where it can use information the shader simply does not
have - the skeleton, the bind pose, per-vertex bone weights, and the rig's own measured skin
colour - and where the result can be rendered out and inspected.

WHAT IT WRITES  (per rig, next to the .glb)
-------------------------------------------
pedestrian_X_mask.png   RGBA.  R = skin, G = garment, B = hair coverage.  The fourth class,
                        shoes and leather, is the implicit remainder 1-R-G-B, so four materials
                        fit in three channels.  A = SHADE: the source texel's sRGB value
                        (max of r,g,b) baked in a known colour space.  The shader rebuilds the
                        garment and the hair colour from A instead of from the albedo texture,
                        which is what removes the renderer-dependent colour-space plumbing
                        altogether - the number the shader compares against no longer depends on
                        how this renderer happens to sample a colour texture.

pedestrian_X_nrm.png    Tangent-space normal map, OpenGL convention (green = +Y), synthesised
                        per material in OBJECT space and projected into the rig's own tangent
                        frame.  Object space matters: the UV atlas is thousands of tiny
                        per-triangle islands, so anything drawn in UV space would change
                        direction every few texels and read as noise.  Evaluating the detail at
                        the bind-pose position instead makes a fold run across a sleeve.

There is deliberately NO separate roughness image.  Everything one would hold is recoverable
from these two: the per-material level from the mask, the sheen on a forehead or a nose from the
shade channel (the source photo's own highlights sit exactly there), and the weave/crease
variation from the slope of the baked normal.  A third 1 MB sampler on the most-instanced
material in the game is not worth 0.1 of roughness difference between denim and knit.

HOW A TEXEL IS CLASSIFIED
-------------------------
Not by "pixels that happen to look pinkish".  Each texel belongs to exactly one triangle, and
each triangle has bone weights, so every texel knows which body part it is on:

  hands                          -> skin, always.  This is the calibration sample.
  feet                           -> shoe, always.
  torso / hips / thighs / shins  -> garment, unless the colour matches this rig's own measured
                                    skin to within SKIN_DELTA_E (shorts, a midriff, bare feet)
  arms and forearms              -> garment or skin by the same colour test, which is where a
                                    sleeve actually ends
  head                           -> skin everywhere except the scalp zone (above the brow line
                                    and not facing forward), where a dark texel is hair.  Gating
                                    hair on scalp GEOMETRY is what fixes it: hair is warm and
                                    saturated, so a colour-only test either misses it entirely
                                    (the old 0.8 %) or paints the eyes and lips with it.

The colour test is a CIE76 distance in Lab to THIS RIG's own skin, sampled from its hands.  That
is why pedestrian_c works: its jacket and trousers are the same warm brown as its skin, so hue
cannot separate them, but in Lab the garment sits 35 units away - mostly in lightness, which is
a channel the old HSV test had to use as a global threshold and could only ever get half right.

Run tools/fix_texture_imports.py assets/models afterwards and commit the .import files.
"""

import argparse
import json
import os
import struct
import sys

import numpy as np
from PIL import Image

# ---------------------------------------------------------------------------------------------
# Tunables.  Everything a future pass is likely to want to change lives here.
# ---------------------------------------------------------------------------------------------

SIZE = 1024
## Lab (CIE76) distance from the rig's own measured skin colour inside which a texel is skin.
## Used where bare skin is plausible: hands, neck, arms - that is, where a sleeve ends.
SKIN_DELTA_E = 20.0
## The same test on the torso and legs, where bare skin is rare and a pale shirt sitting near
## the skin colour would otherwise speckle a jacket with flesh.  Tighter on purpose.
TORSO_SKIN_DELTA_E = 11.0
## The same test on the scalp, where the decision is hair vs forehead.  Looser, because hair
## lying over skin is darker than the hair further up the head.
HAIR_DELTA_E = 15.0
## Scalp zone: fraction of the head's height above which hair may appear at all, and the fraction
## above which it appears even on the forward-facing side (the top of the head).
SCALP_LOW = 0.42
SCALP_TOP = 0.74
## How far forward a surface normal has to point, inside the scalp band, to be called face.
FACE_FACING = 0.35

## Detail amplitudes, in metres of relief on a 1.75 m body.  Slope, not height, is what a normal
## map carries, so these are paired with the wavelengths below: amplitude / wavelength is the
## tangent of the bump angle.  Crank `*_FOLD_A` to make a material read harder.
KNIT_FOLD_A, KNIT_FOLD_L = 0.0150, 0.075
KNIT_WEAVE_A, KNIT_WEAVE_L = 0.00046, 0.0065
DENIM_FOLD_A, DENIM_FOLD_L = 0.0130, 0.095
DENIM_TWILL_A, DENIM_TWILL_L = 0.00042, 0.0055
SHIRT_FOLD_A, SHIRT_FOLD_L = 0.0092, 0.050
SHIRT_WEAVE_A, SHIRT_WEAVE_L = 0.00026, 0.0050
SKIN_CREASE_A, SKIN_CREASE_L = 0.0024, 0.035
SKIN_PORE_A, SKIN_PORE_L = 0.00017, 0.0055
HAIR_CLUMP_A, HAIR_CLUMP_L = 0.0052, 0.030
HAIR_STRAND_A, HAIR_STRAND_L = 0.00135, 0.0070
## How far the hair strand noise is stretched along the flow direction.  1 is isotropic.
HAIR_SQUASH = 0.18
SHOE_CREASE_A, SHOE_CREASE_L = 0.0038, 0.040
SHOE_GRAIN_A, SHOE_GRAIN_L = 0.00040, 0.0060
## Cloth gathers where a garment ends.  Within this distance of a cuff, a collar, a hem or a
## waistband the fold amplitude is multiplied by up to (1 + EDGE_GATHER).  Noise alone gives an
## even scatter of creases over a whole sleeve, which is exactly how cloth does not behave.
EDGE_GATHER, EDGE_GATHER_L = 1.6, 0.035

## Texels of gutter painted outside every UV island, so bilinear filtering and the mip chain
## never pull the empty background into a face.
DILATE = 14

SKIN, CLOTH, HAIR, SHOE = 0, 1, 2, 3

# Bone name -> body region.  The rigs share one skeleton, so this is the same for all of them.
GROUPS = {
    "head_end": "HEAD", "headfront": "HEAD", "Head": "HEAD", "neck": "NECK",
    "Spine": "TORSO", "Spine01": "TORSO", "Spine02": "TORSO", "Hips": "HIPS",
    "LeftShoulder": "TORSO", "RightShoulder": "TORSO",
    "LeftArm": "UPPERARM", "RightArm": "UPPERARM",
    "LeftForeArm": "FOREARM", "RightForeArm": "FOREARM",
    "LeftHand": "HAND", "RightHand": "HAND",
    "LeftUpLeg": "THIGH", "RightUpLeg": "THIGH", "LeftLeg": "SHIN", "RightLeg": "SHIN",
    "LeftFoot": "FOOT", "RightFoot": "FOOT", "LeftToeBase": "FOOT", "RightToeBase": "FOOT",
}
GSET = ["HEAD", "NECK", "TORSO", "HIPS", "UPPERARM", "FOREARM", "HAND", "THIGH", "SHIN", "FOOT"]


# ---------------------------------------------------------------------------------------------
# glTF binary reading.  Small and self-contained so the tool has no dependency beyond numpy/PIL.
# ---------------------------------------------------------------------------------------------

_COMP = {5120: (np.int8, 1), 5121: (np.uint8, 1), 5122: (np.int16, 2),
         5123: (np.uint16, 2), 5125: (np.uint32, 4), 5126: (np.float32, 4)}
_NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load_glb(path):
    data = open(path, "rb").read()
    if data[:4] != b"glTF":
        raise ValueError("%s is not a binary glTF" % path)
    off, js, bin_ = 12, None, None
    while off < len(data):
        length, kind = struct.unpack_from("<II", data, off)
        off += 8
        chunk = data[off:off + length]
        off += length
        if kind == 0x4E4F534A:
            js = json.loads(chunk.decode("utf-8"))
        elif kind == 0x004E4942:
            bin_ = chunk
    return js, bin_


def accessor(js, bin_, index):
    a = js["accessors"][index]
    n = _NCOMP[a["type"]]
    dt, sz = _COMP[a["componentType"]]
    bv = js["bufferViews"][a["bufferView"]]
    base = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", n * sz)
    count = a["count"]
    if stride == n * sz:
        return np.frombuffer(bin_, dtype=dt, count=count * n, offset=base).reshape(count, n)
    raw = np.frombuffer(bin_, dtype=np.uint8, count=stride * count, offset=base).reshape(count, stride)
    return raw[:, :n * sz].copy().view(dt).reshape(count, n)


def read_rig(path):
    js, bin_ = load_glb(path)
    prim = js["meshes"][0]["primitives"][0]
    at = prim["attributes"]
    P = accessor(js, bin_, at["POSITION"]).astype(np.float64)
    N = accessor(js, bin_, at["NORMAL"]).astype(np.float64)
    UV = accessor(js, bin_, at["TEXCOORD_0"]).astype(np.float64)
    J = accessor(js, bin_, at["JOINTS_0"]).astype(np.int32)
    W = accessor(js, bin_, at["WEIGHTS_0"]).astype(np.float64)
    tris = accessor(js, bin_, prim["indices"]).reshape(-1, 3).astype(np.int64)
    names = [js["nodes"][n].get("name", "?") for n in js["skins"][0]["joints"]]
    gi = np.array([GSET.index(GROUPS.get(n, "TORSO")) for n in names])
    vg = np.zeros((len(P), len(GSET)))
    for k in range(4):
        np.add.at(vg, (np.arange(len(P)), gi[J[:, k]]), W[:, k])
    total = vg.sum(1, keepdims=True)
    total[total <= 0] = 1.0
    nl = np.linalg.norm(N, axis=1, keepdims=True)
    nl[nl < 1e-9] = 1.0
    return dict(P=P, N=N / nl, UV=UV, tris=tris, vg=vg / total)


def vertex_frames(P, N, UV, tris):
    """Per-vertex tangent and bitangent from the UV derivatives, averaged over the adjacent
    triangles and Gram-Schmidt orthogonalised - the construction Godot's generate_tangents()
    runs on these rigs at import time, so the baked map lands in the frame the shader reads."""
    T = np.zeros_like(P)
    B = np.zeros_like(P)
    p0, p1, p2 = P[tris[:, 0]], P[tris[:, 1]], P[tris[:, 2]]
    u0, u1, u2 = UV[tris[:, 0]], UV[tris[:, 1]], UV[tris[:, 2]]
    e1, e2 = p1 - p0, p2 - p0
    d1, d2 = u1 - u0, u2 - u0
    det = d1[:, 0] * d2[:, 1] - d2[:, 0] * d1[:, 1]
    safe = np.where(np.abs(det) < 1e-12, 1.0, det)
    r = np.where(np.abs(det) < 1e-12, 0.0, 1.0 / safe)[:, None]
    tan = (e1 * d2[:, 1:2] - e2 * d1[:, 1:2]) * r
    bit = (e2 * d1[:, 0:1] - e1 * d2[:, 0:1]) * r
    for k in range(3):
        np.add.at(T, tris[:, k], tan)
        np.add.at(B, tris[:, k], bit)
    T = T - N * np.sum(N * T, 1, keepdims=True)
    tl = np.linalg.norm(T, axis=1, keepdims=True)
    # A vertex with no usable UV derivative still needs some frame; any tangent will do.
    bad = (tl[:, 0] < 1e-9)
    if bad.any():
        fallback = np.cross(N[bad], np.array([0.0, 1.0, 0.0]))
        fl = np.linalg.norm(fallback, axis=1, keepdims=True)
        fl[fl < 1e-9] = 1.0
        T[bad] = fallback / fl
        tl[bad] = 1.0
    T = T / tl
    w = np.sign(np.sum(np.cross(N, T) * B, 1, keepdims=True))
    w[w == 0] = 1.0
    return T, np.cross(N, T) * w


def rasterize(UV, tris, size):
    """Per-texel triangle id and barycentric weights.  Slightly conservative: a texel counts if
    its centre is within half a texel of the triangle, so the thin slivers this atlas is full of
    still write their island instead of dropping out."""
    tid = np.full((size, size), -1, np.int32)
    bary = np.zeros((size, size, 3), np.float32)
    best = np.full((size, size), -1e9, np.float32)
    uvp = UV * size
    for t in range(len(tris)):
        a, b, c = uvp[tris[t, 0]], uvp[tris[t, 1]], uvp[tris[t, 2]]
        x0 = max(int(np.floor(min(a[0], b[0], c[0]))) - 1, 0)
        x1 = min(int(np.ceil(max(a[0], b[0], c[0]))) + 1, size - 1)
        y0 = max(int(np.floor(min(a[1], b[1], c[1]))) - 1, 0)
        y1 = min(int(np.ceil(max(a[1], b[1], c[1]))) + 1, size - 1)
        if x1 < x0 or y1 < y0:
            continue
        d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(d) < 1e-12:
            continue
        X, Y = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        l0 = ((b[1] - c[1]) * (X - c[0]) + (c[0] - b[0]) * (Y - c[1])) / d
        l1 = ((c[1] - a[1]) * (X - c[0]) + (a[0] - c[0]) * (Y - c[1])) / d
        l2 = 1.0 - l0 - l1
        m = np.minimum(np.minimum(l0, l1), l2) * np.sqrt(abs(d))
        hit = m > -0.5
        if not hit.any():
            continue
        sy, sx = np.where(hit)
        gy, gx = sy + y0, sx + x0
        score = m[sy, sx].astype(np.float32)
        take = score > best[gy, gx]
        gy, gx, sy, sx = gy[take], gx[take], sy[take], sx[take]
        best[gy, gx] = score[take]
        tid[gy, gx] = t
        bary[gy, gx, 0] = np.clip(l0[sy, sx], 0, 1)
        bary[gy, gx, 1] = np.clip(l1[sy, sx], 0, 1)
        bary[gy, gx, 2] = np.clip(l2[sy, sx], 0, 1)
    s = bary.sum(2, keepdims=True)
    s[s <= 0] = 1.0
    return tid, bary / s


# ---------------------------------------------------------------------------------------------
# Colour.
# ---------------------------------------------------------------------------------------------

def srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_lab(rgb):
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = rgb @ m.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(np.maximum(xyz, 1e-9)), 7.787 * xyz + 16.0 / 116.0)
    return np.stack([116.0 * f[..., 1] - 16.0,
                     500.0 * (f[..., 0] - f[..., 1]),
                     200.0 * (f[..., 1] - f[..., 2])], -1)


# ---------------------------------------------------------------------------------------------
# Noise.  Hash-based value noise, evaluated on flat arrays of object-space points.
# ---------------------------------------------------------------------------------------------

def _hash(ix, iy, iz, seed):
    h = (ix.astype(np.uint64) * np.uint64(0x9E3779B1)
         ^ iy.astype(np.uint64) * np.uint64(0x85EBCA6B)
         ^ iz.astype(np.uint64) * np.uint64(0xC2B2AE35)
         ^ np.uint64(seed) * np.uint64(0x27D4EB2F))
    h ^= h >> np.uint64(15)
    h *= np.uint64(0x2545F4914F6CDD1D)
    h ^= h >> np.uint64(29)
    return (h >> np.uint64(40)).astype(np.float64) / float(1 << 24)


def value_noise(q, seed):
    """Trilinear value noise in [0,1] at the points q (N,3)."""
    i = np.floor(q)
    f = q - i
    f = f * f * (3.0 - 2.0 * f)
    ix, iy, iz = i[:, 0].astype(np.int64), i[:, 1].astype(np.int64), i[:, 2].astype(np.int64)
    out = 0.0
    for dz in (0, 1):
        wz = f[:, 2] if dz else 1.0 - f[:, 2]
        for dy in (0, 1):
            wy = f[:, 1] if dy else 1.0 - f[:, 1]
            for dx in (0, 1):
                wx = f[:, 0] if dx else 1.0 - f[:, 0]
                out = out + _hash(ix + dx, iy + dy, iz + dz, seed) * (wx * wy * wz)
    return out


def fbm(q, seed, octaves=3, gain=0.5, lac=2.03):
    total, amp, norm, scale = 0.0, 1.0, 0.0, 1.0
    for o in range(octaves):
        total = total + amp * value_noise(q * scale, seed + o * 37)
        norm += amp
        amp *= gain
        scale *= lac
    return total / norm


def ridged(q, seed, octaves=3):
    """Folds want creases, not blobs: fold the noise about its midpoint so it has sharp valleys."""
    total, amp, norm, scale = 0.0, 1.0, 0.0, 1.0
    for o in range(octaves):
        n = 1.0 - np.abs(value_noise(q * scale, seed + o * 91) * 2.0 - 1.0)
        total = total + amp * n * n
        norm += amp
        amp *= 0.5
        scale *= 2.07
    return total / norm


def _plain_weave(u, v):
    """One over-under grid: the warp reads on top where it dominates, the weft where it does."""
    a = np.sin(u * 2.0 * np.pi)
    b = np.sin(v * 2.0 * np.pi)
    return np.maximum(np.abs(a), np.abs(b)) - 0.6


def triplanar(fn, P, N, lam):
    """Evaluate a 2D pattern on the three axis planes and blend by the surface normal, so a
    directional weave keeps one direction across a whole garment instead of turning over at
    every UV island edge."""
    w = np.abs(N) ** 4.0
    w = w / np.maximum(w.sum(1, keepdims=True), 1e-9)
    q = P / lam
    return (fn(q[:, 1], q[:, 2]) * w[:, 0]
            + fn(q[:, 0], q[:, 2]) * w[:, 1]
            + fn(q[:, 0], q[:, 1]) * w[:, 2])


def _twill(u, v):
    """Denim: diagonal ribs, which is what tells denim from knit at arm's length."""
    return np.sin((u + v) * 2.0 * np.pi) * 0.5 + np.sin((u + v) * 6.0 * np.pi) * 0.12


def height(P, N, cls, sub, flow, gather):
    """Object-space relief in metres for a batch of surface points.

    cls    per-point material (SKIN / CLOTH / HAIR / SHOE)
    sub    cloth subtype: 0 knit, 1 denim, 2 shirt
    flow   per-point hair flow direction (unit, tangent to the surface)
    gather per-point fold amplitude multiplier: cloth bunches at a cuff or a hem
    """
    h = np.zeros(len(P))

    m = cls == CLOTH
    if m.any():
        Pm, Nm, sm, gm = P[m], N[m], sub[m], gather[m]
        knit = sm == 0
        denim = sm == 1
        shirt = sm == 2
        hm = np.zeros(len(Pm))
        fold_a = np.where(denim, DENIM_FOLD_A, np.where(shirt, SHIRT_FOLD_A, KNIT_FOLD_A))
        fold_l = np.where(denim, DENIM_FOLD_L, np.where(shirt, SHIRT_FOLD_L, KNIT_FOLD_L))
        hm += fold_a * gm * (ridged(Pm / fold_l[:, None], 11, 3) - 0.45)
        # A second, slower pass so a garment has big soft drape as well as creases.
        hm += fold_a * 0.8 * (fbm(Pm / (fold_l[:, None] * 3.2), 23, 2) - 0.5)
        if knit.any():
            hm[knit] += KNIT_WEAVE_A * triplanar(_plain_weave, Pm[knit], Nm[knit], KNIT_WEAVE_L)
        if denim.any():
            hm[denim] += DENIM_TWILL_A * triplanar(_twill, Pm[denim], Nm[denim], DENIM_TWILL_L)
        if shirt.any():
            hm[shirt] += SHIRT_WEAVE_A * triplanar(_plain_weave, Pm[shirt], Nm[shirt], SHIRT_WEAVE_L)
        h[m] = hm

    m = cls == SKIN
    if m.any():
        Pm = P[m]
        h[m] = (SKIN_CREASE_A * (fbm(Pm / SKIN_CREASE_L, 41, 3) - 0.5)
                + SKIN_PORE_A * (value_noise(Pm / SKIN_PORE_L, 53) - 0.5))

    m = cls == HAIR
    if m.any():
        Pm, fm = P[m], flow[m]
        along = np.sum(Pm * fm, 1, keepdims=True)
        q = (Pm + fm * along * (HAIR_SQUASH - 1.0)) / HAIR_STRAND_L
        h[m] = (HAIR_CLUMP_A * (fbm(Pm / HAIR_CLUMP_L, 61, 2) - 0.5)
                + HAIR_STRAND_A * (ridged(q, 71, 2) - 0.45))

    m = cls == SHOE
    if m.any():
        Pm, Nm = P[m], N[m]
        h[m] = (SHOE_CREASE_A * gather[m] * (ridged(Pm / SHOE_CREASE_L, 83, 2) - 0.45)
                + SHOE_GRAIN_A * triplanar(_plain_weave, Pm, Nm, SHOE_GRAIN_L))
    return h


def edge_distance(P, tris, vcls):
    """Metres from each vertex to the nearest point where the material changes - a cuff, a
    collar, a trouser hem, the top of a shoe.  Relaxed over the mesh's own edge graph, because
    the UV atlas is per-triangle islands and a distance field measured in texture space would
    only ever find island borders."""
    e = np.concatenate([tris[:, [0, 1]], tris[:, [1, 2]], tris[:, [2, 0]]], 0)
    a, b = e[:, 0], e[:, 1]
    # Weld: two vertices at the same place are the same point even when the atlas split them.
    key = np.round(P * 4000.0).astype(np.int64)
    _, weld = np.unique(key, axis=0, return_inverse=True)
    n = weld.max() + 1
    wa, wb = weld[a], weld[b]
    wcls = np.full(n, -1, np.int32)
    wcls[weld] = vcls
    length = np.linalg.norm(P[a] - P[b], axis=1)
    d = np.full(n, 1e9)
    border = wcls[wa] != wcls[wb]
    np.minimum.at(d, wa[border], 0.0)
    np.minimum.at(d, wb[border], 0.0)
    for _ in range(40):
        before = d.sum()
        np.minimum.at(d, wa, d[wb] + length)
        np.minimum.at(d, wb, d[wa] + length)
        if abs(d.sum() - before) < 1e-6:
            break
    return np.minimum(d[weld], 1.0)


# ---------------------------------------------------------------------------------------------
# Baking.
# ---------------------------------------------------------------------------------------------

def dilate(channels, valid, rounds):
    """Push island values outwards into the gutter so mips and bilinear taps never sample the
    empty background.  Plain 4-neighbour flood; a dozen rounds covers the padding these islands
    need."""
    out = [c.copy() for c in channels]
    have = valid.copy()
    for _ in range(rounds):
        acc = [np.zeros_like(c) for c in out]
        cnt = np.zeros(have.shape, np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            hs = np.roll(np.roll(have, dy, 0), dx, 1).astype(np.float32)
            cnt += hs
            for i, c in enumerate(out):
                acc[i] += np.roll(np.roll(c, dy, 0), dx, 1) * hs
        grow = (~have) & (cnt > 0)
        if not grow.any():
            break
        for i in range(len(out)):
            out[i][grow] = acc[i][grow] / cnt[grow]
        have |= grow
    return out, have


def blur_masked(a, valid, passes=1):
    """Tiny 3x3 box blur that only mixes covered texels - softens the JPEG speckle at a
    sleeve/skin boundary without dragging the background in."""
    v = valid.astype(np.float32)
    out = a.astype(np.float32)
    for _ in range(passes):
        acc = out * v
        cnt = v.copy()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dy == 0 and dx == 0:
                    continue
                acc += np.roll(np.roll(out * v, dy, 0), dx, 1)
                cnt += np.roll(np.roll(v, dy, 0), dx, 1)
        out = np.where(cnt > 0, acc / np.maximum(cnt, 1e-6), out)
    return out


def classify(rig, tid, bary, img, report=None):
    """Per-texel material, using the skeleton for the regions and this rig's own skin for the
    colour test.  Returns (cls, sub, P, N, T, B, flow, valid) flattened over covered texels."""
    tris, P, N, UV, vg = rig["tris"], rig["P"], rig["N"], rig["UV"], rig["vg"]
    T, B = vertex_frames(P, N, UV, tris)
    valid = tid >= 0
    ys, xs = np.where(valid)
    t = tid[valid]
    w = bary[valid].astype(np.float64)
    corner = tris[t]

    def interp(attr):
        return (attr[corner[:, 0]] * w[:, 0:1] + attr[corner[:, 1]] * w[:, 1:2]
                + attr[corner[:, 2]] * w[:, 2:3])

    pp = interp(P)
    nn = interp(N)
    nn /= np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-9)
    tt = interp(T)
    tt = tt - nn * np.sum(nn * tt, 1, keepdims=True)
    tt /= np.maximum(np.linalg.norm(tt, axis=1, keepdims=True), 1e-9)
    bb = interp(B)
    bb = bb - nn * np.sum(nn * bb, 1, keepdims=True) - tt * np.sum(tt * bb, 1, keepdims=True)
    bb /= np.maximum(np.linalg.norm(bb, axis=1, keepdims=True), 1e-9)

    region = interp(vg).argmax(1)
    rgb = img[ys, xs]
    lab = linear_to_lab(srgb_to_linear(rgb))

    # This rig's own skin, measured off its hands, which are skin on any clothed character.
    hands = region == GSET.index("HAND")
    if hands.sum() < 50:
        hands = region == GSET.index("HEAD")
    skin_ref = np.median(lab[hands], 0)
    d_skin = np.linalg.norm(lab - skin_ref, axis=1)

    cls = np.full(len(pp), CLOTH, np.int32)
    for name in ("HAND", "NECK", "FOREARM", "UPPERARM", "TORSO", "HIPS", "THIGH", "SHIN"):
        m = region == GSET.index(name)
        if name == "HAND":
            cls[m] = SKIN
        else:
            limit = TORSO_SKIN_DELTA_E if name in ("TORSO", "HIPS", "THIGH", "SHIN") else SKIN_DELTA_E
            cls[m] = np.where(d_skin[m] < limit, SKIN, CLOTH)
    cls[region == GSET.index("FOOT")] = SHOE

    # The head: skin unless we are on the scalp, where dark means hair.  Geometry first, colour
    # second - the reverse is what left the hair palette dead and put hair colour on eyelids.
    head = region == GSET.index("HEAD")
    flow = np.tile(np.array([0.0, -1.0, 0.0]), (len(pp), 1))
    if head.any():
        hy = pp[head, 1]
        lo, hi = hy.min(), hy.max()
        span = max(hi - lo, 1e-6)
        hn = (hy - lo) / span
        # Which way the rig faces: the side of the head that is skin-coloured is the face.
        zc = pp[head, 2] - np.median(pp[head, 2])
        front_plus = d_skin[head][zc > 0].mean() if (zc > 0).any() else 1e9
        front_minus = d_skin[head][zc < 0].mean() if (zc < 0).any() else 1e9
        face_dir = 1.0 if front_plus < front_minus else -1.0
        facing = nn[head, 2] * face_dir
        scalp = (hn > SCALP_LOW) & ((facing < FACE_FACING) | (hn > SCALP_TOP))
        sub_cls = np.where(scalp & (d_skin[head] > HAIR_DELTA_E), HAIR, SKIN)
        cls[head] = sub_cls
        # Hair lies down the head: the surface direction closest to "away from the crown".
        crown = np.array([np.median(pp[head, 0]), hi, np.median(pp[head, 2])])
        d = pp[head] - crown
        d = d - nn[head] * np.sum(nn[head] * d, 1, keepdims=True)
        dl = np.linalg.norm(d, axis=1, keepdims=True)
        d = np.where(dl > 1e-6, d / np.maximum(dl, 1e-9), np.array([0.0, -1.0, 0.0]))
        flow[head] = d
        if report is not None:
            report["face_dir"] = face_dir
            report["hair_frac"] = float((sub_cls == HAIR).mean())

    # Cloth subtype from its own colour: blue and dark is denim, light is a shirt, else knit.
    sub = np.zeros(len(pp), np.int32)
    denim = (lab[:, 2] < -1.5) & (lab[:, 0] < 45.0)
    shirt = lab[:, 0] > 55.0
    sub[denim] = 1
    sub[shirt & ~denim] = 2

    # Where does this garment end?  Vote each vertex to a material, then relax the distance to
    # the nearest material change over the mesh, and use it to bunch the cloth at the edges.
    vcount = np.zeros((len(P), 4))
    for k in range(3):
        np.add.at(vcount, (corner[:, k], cls), 1.0)
    vcls = vcount.argmax(1).astype(np.int32)
    vd = edge_distance(P, tris, vcls)
    d_edge = (vd[corner[:, 0]] * w[:, 0] + vd[corner[:, 1]] * w[:, 1] + vd[corner[:, 2]] * w[:, 2])
    gather = 1.0 + EDGE_GATHER * np.exp(-(d_edge / EDGE_GATHER_L) ** 2)

    if report is not None:
        report["skin_ref"] = [round(float(v), 1) for v in skin_ref]
        report["counts"] = {n: int((cls == c).sum()) for n, c in
                            (("skin", SKIN), ("cloth", CLOTH), ("hair", HAIR), ("shoe", SHOE))}
        report["sub"] = {"knit": int((sub[cls == CLOTH] == 0).sum()),
                         "denim": int((sub[cls == CLOTH] == 1).sum()),
                         "shirt": int((sub[cls == CLOTH] == 2).sum())}
    return dict(ys=ys, xs=xs, cls=cls, sub=sub, P=pp, N=nn, T=tt, B=bb, flow=flow,
                gather=gather, rgb=rgb, valid=valid, d_skin=d_skin, region=region)


def bake(glb, tex, out_mask, out_nrm, debug=None, report=None):
    rig = read_rig(glb)
    img = np.asarray(Image.open(tex).convert("RGB"), np.float32) / 255.0
    if img.shape[0] != SIZE or img.shape[1] != SIZE:
        img = np.asarray(Image.open(tex).convert("RGB").resize((SIZE, SIZE)), np.float32) / 255.0
    tid, bary = rasterize(rig["UV"], rig["tris"], SIZE)
    c = classify(rig, tid, bary, img, report)
    ys, xs, cls = c["ys"], c["xs"], c["cls"]

    # --- normal map -------------------------------------------------------------------------
    # Finite differences of the object-space relief along the texel's own tangent and bitangent.
    # Taking the derivative in the frame the shader will reconstruct means the result is correct
    # whatever convention the tangent generator chose.
    step = 0.0012
    n_ts = np.zeros((len(ys), 3))
    block = 60000
    for i in range(0, len(ys), block):
        s = slice(i, min(i + block, len(ys)))
        P, N, T, B = c["P"][s], c["N"][s], c["T"][s], c["B"][s]
        cl, sb, fl, ga = cls[s], c["sub"][s], c["flow"][s], c["gather"][s]
        hu = height(P + T * step, N, cl, sb, fl, ga) - height(P - T * step, N, cl, sb, fl, ga)
        hv = height(P + B * step, N, cl, sb, fl, ga) - height(P - B * step, N, cl, sb, fl, ga)
        n_ts[s, 0] = -hu / (2.0 * step)
        n_ts[s, 1] = -hv / (2.0 * step)
        n_ts[s, 2] = 1.0
    n_ts /= np.maximum(np.linalg.norm(n_ts, axis=1, keepdims=True), 1e-9)

    nrm = np.zeros((SIZE, SIZE, 3), np.float32)
    nrm[:, :, 2] = 1.0
    nrm[ys, xs] = n_ts.astype(np.float32)

    # --- mask -------------------------------------------------------------------------------
    mask = np.zeros((SIZE, SIZE, 4), np.float32)
    for i, k in ((SKIN, 0), (CLOTH, 1), (HAIR, 2)):
        m = cls == i
        mask[ys[m], xs[m], k] = 1.0
    # A = the source texel's sRGB value, baked once in a known colour space.  The shader rebuilds
    # the garment and the hair from this instead of from the albedo texture, which is what makes
    # the result identical on Forward+ and on the Compatibility renderer.
    mask[ys, xs, 3] = c["rgb"].max(1)

    valid = c["valid"]
    for k in range(3):
        mask[:, :, k] = blur_masked(mask[:, :, k], valid, 1)
    ch, filled = dilate([mask[:, :, 0], mask[:, :, 1], mask[:, :, 2], mask[:, :, 3],
                         nrm[:, :, 0], nrm[:, :, 1], nrm[:, :, 2]], valid, DILATE)
    mask[:, :, 0], mask[:, :, 1], mask[:, :, 2], mask[:, :, 3] = ch[0], ch[1], ch[2], ch[3]
    nrm[:, :, 0], nrm[:, :, 1], nrm[:, :, 2] = ch[4], ch[5], ch[6]
    nrm[~filled] = np.array([0.0, 0.0, 1.0], np.float32)
    nrm /= np.maximum(np.linalg.norm(nrm, axis=2, keepdims=True), 1e-9)

    Image.fromarray(np.clip(mask * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGBA").save(out_mask)
    Image.fromarray(np.clip((nrm * 0.5 + 0.5) * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGB").save(out_nrm)
    if report is not None:
        report["slope_deg_p90"] = round(float(np.degrees(np.arctan(
            np.percentile(np.linalg.norm(n_ts[:, :2], axis=1) / np.maximum(n_ts[:, 2], 1e-6), 90)))), 1)
        report["coverage"] = round(float(valid.mean()), 3)

    if debug:
        os.makedirs(debug, exist_ok=True)
        base = os.path.splitext(os.path.basename(out_mask))[0]
        colours = np.array([[1.0, 0.72, 0.58], [0.25, 0.45, 0.85], [0.95, 0.85, 0.2], [0.15, 0.85, 0.35]])
        preview(rig, c, colours[cls], os.path.join(debug, base + "_classes.png"))
        shade = np.clip(c["rgb"].max(1), 0, 1)[:, None] * np.ones(3)
        preview(rig, c, shade, os.path.join(debug, base + "_shade.png"))
        lit = np.clip(0.25 + 0.75 * np.clip(n_ts @ np.array([0.45, 0.55, 0.70]), 0, 1), 0, 1)
        preview(rig, c, lit[:, None] * np.ones(3), os.path.join(debug, base + "_relief.png"), lit_by_normal=False)
    return report


def preview(rig, c, colour, path, lit_by_normal=False):
    """Paint the classification straight onto an orthographic view of the rig, front and side.
    A UV atlas of 8000 per-triangle islands tells you nothing by eye; a picture of the body does."""
    W, H = 300, 620
    out = np.ones((H, W * 2, 3), np.float32)
    P, N = c["P"], c["N"]
    lo, hi = P.min(0), P.max(0)
    for view, (ax, flip) in enumerate(((0, 1.0), (2, -1.0))):
        span = max(hi[ax] - lo[ax], hi[1] - lo[1]) * 1.1
        u = ((P[:, ax] * flip - (lo[ax] + hi[ax]) * 0.5 * flip) / span + 0.5) * W
        v = (1.0 - (P[:, 1] - lo[1]) / span) * H + H * 0.03
        depth = P[:, 2] * (1.0 if view == 0 else 1.0)
        order = np.argsort(depth if view == 0 else P[:, 0])
        col = colour
        if lit_by_normal:
            col = col * np.clip(0.3 + 0.7 * N[:, 2:3], 0, 1)
        ui = np.clip(u[order].astype(int), 0, W - 1) + view * W
        vi = np.clip(v[order].astype(int), 0, H - 1)
        out[vi, ui] = np.clip(col[order], 0, 1)
    Image.fromarray((out * 255).astype(np.uint8)).save(path)


RIGS = [
    ("a", "assets/models/pedestrian_a_anim.glb", "assets/models/pedestrian_a_anim_texture_0.jpg"),
    ("c", "assets/models/pedestrian_c_anim.glb", "assets/models/pedestrian_c_anim_texture_0.jpg"),
] + [
    (n, "assets/models/pedestrian_%s_anim.glb" % n, "assets/models/pedestrian_%s_anim_texture_0.jpg" % n)
    for n in "defghijkl"
]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--debug", default="", help="directory for classification previews")
    ap.add_argument("--only", default="", help="bake one rig (a, c, d .. l)")
    args = ap.parse_args()
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    for name, glb, tex in RIGS:
        if args.only and args.only != name:
            continue
        g, t = os.path.join(root, glb), os.path.join(root, tex)
        if not os.path.exists(g):
            print("missing %s - skipped" % glb)
            continue
        mask = os.path.join(root, "assets/models/pedestrian_%s_mask.png" % name)
        nrm = os.path.join(root, "assets/models/pedestrian_%s_nrm.png" % name)
        report = {}
        bake(g, t, mask, nrm, args.debug, report)
        print("pedestrian_%s: %s" % (name, json.dumps(report, sort_keys=True)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
