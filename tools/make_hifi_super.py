#!/usr/bin/env python3
"""High-fidelity mid-engine supercar body, built as a SUBDIVISION SURFACE in Blender's bpy module.

    python3 tools/make_hifi_super.py                 # build + export + verify
    python3 tools/make_hifi_super.py --no-verify     # skip re-reading the .glb

Writes assets/models/hifi_super_coupe.glb.

WHY THIS EXISTS
---------------
The previous generated bodies were ~32 k-triangle low-poly cages with a 3 mm bevel. At that
density every curved panel is a fan of flat facets, which is exactly what "looks like an N64 car"
means, and no amount of clearcoat in the paint shader can hide it: faceting is a *shading normal*
problem and the normals are wrong because the surface is wrong. This file does the only thing
that actually fixes it - it builds a coarse, all-quad CONTROL CAGE with edge flow that follows the
form, and puts a CATMULL-CLARK SUBDIVISION SURFACE on it. Sharpness comes from HOLDING LOOPS
(pairs of edge loops a few millimetres apart), never from leaving an edge unsubdivided.

THE ONE IDEA THE WHOLE FILE RESTS ON
------------------------------------
The body is one structured quad grid, indexed by (f, g):

    f   longitudinal station, in metres, tail (-2.21) to nose (+2.21)
    g   position round the cross-section, 0 = floor centreline, 16 = right shoulder (widest),
        32 = roof centreline, 48 = left shoulder, wrapping at 64.

Because the grid is structured and I choose where its lines fall, EVERY feature is the same
operation on index ranges:

  * a SHUT LINE is three grid lines 3.2 mm apart with the middle one pushed 4.5 mm into the body.
    Under subdivision, tight loop spacing = tight radius, so that is a real 7 mm panel gap with a
    crisp edge, not a painted stripe.
  * an OPENING (side intakes, grille, lamps, glass) is "delete the faces in this (f, g) rectangle,
    then extrude the border inward twice and cap it". That gives a real mouth with visible inner
    walls. A holding loop goes in just outside each opening in f, and the cut loop itself carries
    an edge CREASE, which is what keeps the rim from melting under subdivision.
  * a WHEEL ARCH is the same delete-and-extrude, with the cut boundary snapped onto the arch
    circle afterwards so it is round and not stair-stepped, and with the surface just outside the
    cut pushed proud to make the arch lip.

So the feature tables below (OPENINGS, GROOVES) are the design, and the grid lines they need are
derived from them automatically. Nothing is placed by eye in 3-space.

CONVENTIONS THE GAME DEPENDS ON
-------------------------------
Authored X = lateral, Y = longitudinal with the NOSE AT +Y, Z = up, ground at Z = 0. glTF's Y-up
conversion turns that into Godot's X right, Y up, nose at -Z, which is the game's forward.
Vehicle._add_body_model() scales the model so its longest horizontal axis equals the chassis
length and centres it on its own bounding box, and Vehicle._wheel_slots uses ONE wheel_z for both
axles - so the arches MUST be symmetric about the bbox centre or the wheels sit off-centre in
their own wings. That is why the overhangs here are 0.955 m each instead of the 0.90 / 1.00 the
brief asked for: the wheelbase (2.64, target 2.65) and the arch centres are the numbers the game
can actually honour, and a 5 cm overhang difference is invisible where a 5.5 cm wheel offset is
not. The lowest vertex (the splitter blade) is 0.050 m above the ground plane and the wheel
centres are at Z = 0.350.

Material slots are a contract: index 0 is "paint" and the game tints ONLY that slot. Nothing that
is not bodywork may be merged into it.

ORIGINALITY
-----------
A CLASS study, not a copy. The proportions that make a shape read as a mid-engine supercar - cab
forward, low wide nose, a hard shoulder over the rear arches, big side intakes, a dished engine
deck between buttresses - belong to nobody. No badge, no manufacturer's grille or lamp signature.
Name: "Vantorre Sabre GTX". Invented.
"""

import math
import os
import sys

import bpy  # noqa: E402  (bpy must come before bmesh/mathutils)
import bmesh
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO, "assets", "models")
PREFIX = "hifi_super_"

# --- the contract with the game -------------------------------------------------------------
# name, base colour, metallic, roughness. Index 0 is the tinted paint.
SLOTS = [
    ("paint",       (0.78, 0.79, 0.81), 0.85, 0.26),
    ("glass",       (0.035, 0.042, 0.055), 0.00, 0.04),
    ("trim",        (0.030, 0.030, 0.034), 0.00, 0.56),
    ("tyre",        (0.024, 0.024, 0.026), 0.00, 0.90),
    ("light_front", (0.34, 0.37, 0.42), 0.00, 0.05),
    ("light_rear",  (0.46, 0.028, 0.026), 0.00, 0.09),
]
PAINT, GLASS, TRIM, TYRE, LIGHT_F, LIGHT_R = range(6)

# --- stance ---------------------------------------------------------------------------------
HUB_Z = 0.350            # wheel centre height = half of the 0.70 m wheel
AXLE = 1.320             # arch centres, symmetric about the bbox centre (wheelbase 2.64)
ARCH_R = 0.385           # arch opening radius: 3.5 cm over the 0.35 m tyre
NOSE_F = 2.210           # front-most loft station
TAIL_F = -2.210          # rear-most loft station
BBOX_F = 2.275           # splitter tip / rear valance: the actual 4.55 m length

# --- cage density ---------------------------------------------------------------------------
# The feature lines below already put a lot of loops in; these only fill the gaps between them.
# They are the two knobs for the triangle budget - see the count printed at the end.
BASE_F_STEP = 0.900      # metres between filler stations (every KEYS station is
                         # already a grid line, so these only fill the long gaps)
BASE_H_STEP = 14.0        # section-parameter units between filler ring samples
SUBDIV = 2               # Catmull-Clark levels on the shell. This is the whole point of the file.

GROOVE_EPS_F = 0.0032    # half-width of a shut line, in metres
GROOVE_EPS_G = 0.105     # half-width of a shut line, in section-parameter units
GROOVE_DEPTH = 0.0045    # how deep a panel gap cuts
HOLD_F = 0.0             # openings are held by their crease, not by a holding loop
HOLD_G = 0.0             # no ring holding loop: opening rims are held by an edge CREASE
RIM_CREASE = 0.85        # crease on an opening's cut loop. A holding loop round every opening in
                         # the ring direction doubled the cage for edges a crease holds just as
                         # crisply, and the triangles are better spent on the panels.


# =============================================================================================
# Section shape
# =============================================================================================
# Twelve control points per half-section, sampled at these h values. h is the ring parameter on
# one side: 0 floor centre, 16 shoulder (max width), 32 roof centre. The named indices are what
# the feature tables are written in, so moving a control point moves every feature with it.
CUM = [0.0, 2.0, 4.0, 7.0, 10.0, 13.0, 16.0, 19.0, 23.0, 26.0, 29.0, 32.0]
H_MAX = 32.0

# Section parameters, in the order the key table uses them.
#   z0    underbody height on the centreline
#   wb    floor-pan half width
#   z1    shoulder height          w1  max half width (at the shoulder)
#   z2    roof-rail / deck-edge height
#   w2    roof-rail half width
#   crown height added on the roof centreline (NEGATIVE dishes it - that is the engine deck
#         sunk between the buttresses, and it is what stops the tail reading as a box)
#   tuck  how far the flank pulls back in below the shoulder (< 1 = undercut = hard shoulder line)
#   low   fullness of the lower flank
NPARAM = 9

KEYS = [
    # The vertical layout is the thing the first pass got wrong. A 0.70 m wheel means the top of
    # the arch cut is at 0.735, so the shoulder (z1) over an arch has to be well ABOVE that or the
    # cut eats the whole wing and the tyre stands proud of the bodywork. Hence z1 ~0.81 over the
    # front arch and ~0.84 over the rear, dipping to 0.76 at the door: that dip and rise IS the
    # haunch, and it is most of what makes the car look planted.
    # f        z0     wb    z1     w1     z2     w2     crown   tuck   low
    (-2.210, (0.300, 0.400, 0.700, 0.780, 0.878, 0.590, -0.004, 0.955, 0.985)),
    (-2.150, (0.248, 0.480, 0.738, 0.880, 0.915, 0.680, -0.010, 0.950, 0.985)),
    (-2.080, (0.190, 0.540, 0.768, 0.940, 0.950, 0.742, -0.016, 0.945, 0.985)),
    (-2.000, (0.140, 0.570, 0.788, 0.962, 0.972, 0.760, -0.030, 0.942, 0.986)),  # ducktail crest
    (-1.900, (0.112, 0.590, 0.798, 0.972, 0.924, 0.764, -0.038, 0.938, 0.987)),
    (-1.700, (0.092, 0.610, 0.812, 1.000, 0.928, 0.756, -0.064, 0.930, 0.990)),
    (-1.450, (0.086, 0.620, 0.830, 1.012, 0.940, 0.722, -0.100, 0.925, 0.992)),
    (-1.320, (0.085, 0.620, 0.838, 1.016, 0.952, 0.702, -0.118, 0.922, 0.992)),
    (-1.100, (0.084, 0.620, 0.828, 1.008, 0.982, 0.654, -0.126, 0.918, 0.992)),
    (-0.850, (0.083, 0.620, 0.806, 0.994, 1.042, 0.588, -0.098, 0.915, 0.991)),
    (-0.600, (0.082, 0.620, 0.784, 0.980, 1.114, 0.522, -0.028, 0.912, 0.990)),
    (-0.320, (0.082, 0.620, 0.768, 0.974, 1.158, 0.489,  0.030, 0.910, 0.990)),
    (-0.050, (0.082, 0.620, 0.760, 0.970, 1.164, 0.484,  0.036, 0.910, 0.990)),
    (0.250,  (0.082, 0.620, 0.757, 0.966, 1.142, 0.499,  0.034, 0.910, 0.990)),
    (0.560,  (0.082, 0.620, 0.756, 0.962, 1.032, 0.547,  0.024, 0.912, 0.990)),
    (0.800,  (0.082, 0.620, 0.757, 0.960, 0.902, 0.602,  0.010, 0.914, 0.990)),
    (0.980,  (0.083, 0.620, 0.764, 0.960, 0.826, 0.642,  0.000, 0.916, 0.990)),
    (1.150,  (0.084, 0.620, 0.782, 0.982, 0.806, 0.666, -0.006, 0.918, 0.990)),
    (1.320,  (0.085, 0.620, 0.806, 1.000, 0.818, 0.680, -0.010, 0.920, 0.990)),
    (1.560,  (0.086, 0.610, 0.790, 0.988, 0.806, 0.678, -0.016, 0.922, 0.990)),
    (1.800,  (0.090, 0.600, 0.742, 0.964, 0.812, 0.664, -0.020, 0.925, 0.989)),
    # The last 25 cm is a hard taper on purpose. A loft along Y turns whatever the final station
    # is into a flat end cap, and a car's front fascia is where the grille, the lamps and the
    # corner intakes all live - so the nose has to pull in enough that those surfaces are real
    # lofted faces with forward-facing normals, and the cap is only the prow between them.
    (1.960,  (0.098, 0.570, 0.690, 0.936, 0.784, 0.642, -0.022, 0.928, 0.988)),
    (2.040,  (0.104, 0.545, 0.660, 0.922, 0.758, 0.622, -0.022, 0.930, 0.988)),
    (2.100,  (0.116, 0.500, 0.632, 0.890, 0.732, 0.582, -0.018, 0.934, 0.987)),
    (2.150,  (0.140, 0.430, 0.598, 0.820, 0.696, 0.512, -0.014, 0.940, 0.986)),
    (2.185,  (0.180, 0.330, 0.558, 0.700, 0.652, 0.402, -0.008, 0.946, 0.985)),
    (2.210,  (0.240, 0.190, 0.508, 0.480, 0.596, 0.252, -0.004, 0.952, 0.985)),
]


def control_points(p):
    """The twelve (half-width, height) control points of one half-section."""
    z0, wb, z1, w1, z2, w2, crown, tuck, low = p
    dz = z1 - z0
    dt = max(z2 - z1, 1e-4)
    return [
        (0.0,                       z0),                 # 0  floor centre
        (wb * 0.60,                 z0 + 0.004),         # 2  flat floor
        (wb,                        z0 + 0.020),         # 4  floor-pan edge
        (wb + (w1 - wb) * 0.62,     z0 + dz * 0.16),     # 7  rocker, tucked under
        (w1 * low,                  z0 + dz * 0.50),     # 10 lower flank
        (w1 * tuck,                 z0 + dz * 0.78),     # 13 waist: the undercut
        (w1,                        z1),                 # 16 HARD SHOULDER, max width
        (w1 * 0.955,                z1 + dt * 0.11),     # 19 shoulder radius, tight
        (w2 + (w1 - w2) * 0.50,     z1 + dt * 0.48),     # 23 tumblehome
        (w2,                        z2 - dt * 0.09),     # 26 roof rail / deck edge
        (w2 * 0.78,                 z2),                 # 29 roof crest / buttress top
        (0.0,                       z2 + crown),         # 32 roof centre
    ]


def catmull(p0, p1, p2, p3, t):
    t2 = t * t
    return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
                  + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t2 * t)


def section_xz(cp, h):
    """Catmull-Rom through the twelve control points, evaluated at continuous h in [0, 32]."""
    h = min(max(h, 0.0), H_MAX)
    i = 0
    while i < len(CUM) - 2 and h > CUM[i + 1]:
        i += 1
    t = (h - CUM[i]) / (CUM[i + 1] - CUM[i])
    def g(k):
        return cp[min(max(k, 0), len(cp) - 1)]
    p0, p1, p2, p3 = g(i - 1), g(i), g(i + 1), g(i + 2)
    return (catmull(p0[0], p1[0], p2[0], p3[0], t),
            catmull(p0[1], p1[1], p2[1], p3[1], t))


class Mono:
    """Fritsch-Carlson monotone cubic. Stations are 15 mm apart at the nose and half a metre apart
    at the cabin; a uniform spline through that OVERSHOOTS, sections cross, and the shell folds."""

    def __init__(self, xs, ys):
        self.xs, self.ys = xs, ys
        n = len(xs)
        h = [xs[i + 1] - xs[i] for i in range(n - 1)]
        d = [(ys[i + 1] - ys[i]) / h[i] for i in range(n - 1)]
        m = [0.0] * n
        m[0], m[-1] = d[0], d[-1]
        for i in range(1, n - 1):
            if d[i - 1] * d[i] <= 0.0:
                m[i] = 0.0
            else:
                w1 = 2.0 * h[i] + h[i - 1]
                w2 = h[i] + 2.0 * h[i - 1]
                m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
        self.m, self.h = m, h

    def __call__(self, x):
        xs = self.xs
        if x <= xs[0]:
            return self.ys[0]
        if x >= xs[-1]:
            return self.ys[-1]
        lo, hi = 0, len(xs) - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if xs[mid] <= x:
                lo = mid
            else:
                hi = mid
        hh = self.h[lo]
        t = (x - xs[lo]) / hh
        t2, t3 = t * t, t * t * t
        return ((2 * t3 - 3 * t2 + 1) * self.ys[lo] + (t3 - 2 * t2 + t) * hh * self.m[lo]
                + (-2 * t3 + 3 * t2) * self.ys[hi] + (t3 - t2) * hh * self.m[hi])


class Loft:
    """The nine section scalars splined along the length, sampled at (f, g)."""

    def __init__(self, keys):
        xs = [k[0] for k in keys]
        self.curves = [Mono(xs, [k[1][i] for k in keys]) for i in range(NPARAM)]
        self._cp = {}

    def cp(self, f):
        key = round(f, 5)
        c = self._cp.get(key)
        if c is None:
            c = control_points(tuple(cu(f) for cu in self.curves))
            self._cp[key] = c
        return c

    def raw(self, f, g):
        """Undisplaced surface point. g wraps at 64; g > 32 is the -X side."""
        g = g % 64.0
        h = g if g <= 32.0 else 64.0 - g
        x, z = section_xz(self.cp(f), h)
        return Vector(((x if g <= 32.0 else -x), f, z))

    def normal(self, f, g):
        df, dg = 0.0025, 0.06
        tf = self.raw(f + df, g) - self.raw(f - df, g)
        tg = self.raw(f, g + dg) - self.raw(f, g - dg)
        n = tf.cross(tg)
        if n.length < 1e-9:
            # Degenerate only on the centrelines, where the section tangent is parallel to X.
            return Vector((0.0, 0.0, 1.0)) if 8.0 < g < 56.0 else Vector((0.0, 0.0, -1.0))
        return n.normalized()


# =============================================================================================
# Feature tables. Everything the car has that is not a smooth panel lives here.
# =============================================================================================
def gmir(a, b):
    """The mirror image of a g-range on the other flank."""
    return ((64.0 - b) % 64.0, (64.0 - a) % 64.0)


# Openings: faces inside (f range, g range) are deleted and the border extruded inward, so the
# mouth has real inner walls. steps = [(depth, tangential shrink), ...] from the skin inward.
# The first step is a short one: it is the rim radius, and a rim is what tells the eye that the
# opening has a thickness rather than being a hole cut in paper.
# An opening's `g` is its ring range at the FIRST station and `g2`, when present, the range at
# the last: the aperture is then a tapered quad, not a rectangle. A side window cut as a plain
# rectangle is one of the loudest "this is a game asset" tells there is, and the same trick turns
# the side intake from a letterbox into a scoop that opens toward the wheel.
OPENINGS = [
    # --- front. The lamps straddle the shoulder, because at the nose the section has almost no
    #     height above it: anything placed up there comes out a 2 cm sliver on top of the wing.
    dict(name="grille_low",  f=(2.060, 2.205), g=(55.0, 9.0),
         steps=[(0.013, 0.995), (0.130, 0.82)], mat=TRIM),
    dict(name="intake_fnt",  f=(2.075, 2.200), g=(10.5, 14.5), mirror=True,
         steps=[(0.012, 0.995), (0.105, 0.80)], mat=TRIM),
    dict(name="lamp_front",  f=(1.820, 2.020), g=(13.0, 18.0), mirror=True,
         steps=[(0.010, 0.995), (0.062, 0.94)], mat=TRIM),
    # --- flanks ---
    dict(name="intake_side", f=(-0.880, -0.500), g=(9.0, 14.5), g2=(10.5, 13.0), mirror=True,
         steps=[(0.014, 0.995), (0.245, 0.78)], mat=TRIM),
    dict(name="glass_side",  f=(-0.360, 0.180), g=(21.8, 24.3), g2=(20.6, 25.5), mirror=True,
         steps=[(0.008, 0.996), (0.095, 0.88)], mat=TRIM),
    # --- greenhouse ---
    dict(name="windscreen",  f=(0.320, 0.920), g=(26.5, 37.5),
         steps=[(0.009, 0.996), (0.120, 0.86)], mat=TRIM),
    dict(name="glass_rear",  f=(-1.000, -0.600), g=(29.2, 34.8),
         steps=[(0.009, 0.996), (0.110, 0.86)], mat=TRIM),
    # --- rear ---
    dict(name="deck_vent",   f=(-1.500, -1.080), g=(29.2, 34.8),
         steps=[(0.010, 0.996), (0.072, 0.88)], mat=TRIM),
    dict(name="lamp_rear",   f=(-2.185, -2.055), g=(13.0, 18.0), mirror=True,
         steps=[(0.010, 0.995), (0.058, 0.94)], mat=TRIM),
    dict(name="vent_rear",   f=(-2.185, -2.055), g=(55.0, 9.0),
         steps=[(0.013, 0.995), (0.110, 0.84)], mat=TRIM),
]
OPEN_BY_NAME = {o["name"]: o for o in OPENINGS}

# Shut lines. axis 'f' is a seam across the car at a station; axis 'g' is a seam running along it.
# rng is the extent on the other axis; the depth fades out over the last `fade` of each end so a
# seam never stops in a step.
GROOVES = [
    # frunk lid: two cross seams and the two seams down the tops of the wings
    dict(axis='f', at=1.900,  rng=(21.5, 42.5)),
    dict(axis='f', at=0.980,  rng=(21.5, 42.5)),
    dict(axis='g', at=21.5,   rng=(0.980, 1.900), mirror=True),
    # front and rear bumper seams, round the lower body only
    dict(axis='f', at=1.600,  rng=(42.5, 21.5)),
    dict(axis='f', at=-1.920, rng=(42.5, 21.5)),
    # doors
    dict(axis='f', at=0.615,  rng=(6.5, 19.6), mirror=True),
    dict(axis='f', at=-0.400, rng=(6.5, 19.6), mirror=True),
    dict(axis='g', at=6.5,    rng=(-0.400, 0.615), mirror=True),
    dict(axis='g', at=19.6,   rng=(-0.400, 0.615), mirror=True),
    # engine lid
    dict(axis='f', at=-0.520, rng=(24.0, 40.0)),
    dict(axis='f', at=-1.660, rng=(24.0, 40.0)),
    dict(axis='g', at=24.0,   rng=(-1.660, -0.520), mirror=True),
]

# The rocker step under the doors: a wider, shallower groove, so it reads as a change of plane
# rather than a panel gap.
SILL = dict(axis='g', at=5.0, rng=(-1.050, 1.050), mirror=True,
            depth=0.013, eps_g=0.30, fade=0.10)

# Flush door pulls: a soft dish in the flank with a trim tab in it (built in the detail pass).
HANDLES = [(-0.290, 18.0), (-0.290, 46.0)]
HANDLE_R = (0.072, 1.40)     # metres in f, parameter units in g
HANDLE_DEPTH = 0.011

# The fuel flap, on the left rear quarter.
FLAP = dict(f=-0.700, g=46.0, r=0.058)   # rear quarter, clear of the side intake


# =============================================================================================
# Grid construction
# =============================================================================================
def wrap_in(v, a, b):
    """Is v inside the g-range [a, b], which may wrap through 64?"""
    v %= 64.0
    a %= 64.0
    b %= 64.0
    return (a <= v <= b) if a <= b else (v >= a or v <= b)


def fold(g):
    """g -> the half-section parameter h in [0, 32]."""
    g %= 64.0
    return g if g <= 32.0 else 64.0 - g


def opening_ranges(op):
    """Every g-range the opening occupies anywhere, for placing grid lines."""
    out = [op["g"]]
    if "g2" in op:
        out.append(op["g2"])
    if op.get("mirror"):
        out += [gmir(*r) for r in list(out)]
    return out


def op_range_at(op, t, mirror=False):
    """The opening's g-range a fraction t of the way along its f extent."""
    a0, b0 = op["g"]
    if "g2" in op:
        a1, b1 = op["g2"]
        a0, b0 = a0 + (a1 - a0) * t, b0 + (b1 - b0) * t
    return gmir(a0, b0) if mirror else (a0, b0)


def groove_ranges(gr):
    if gr["axis"] == 'f':
        return [gr["rng"]] if not gr.get("mirror") else [gr["rng"], gmir(*gr["rng"])]
    return [gr["at"]] if not gr.get("mirror") else [gr["at"], (64.0 - gr["at"]) % 64.0]


def merge(values, base_lo, base_hi, base_step, tol):
    """Feature lines first; filler lines only where they are not crowding one."""
    vals = sorted(set(round(v, 6) for v in values))
    out = list(vals)
    n = max(1, int(math.ceil((base_hi - base_lo) / base_step)))
    for i in range(n + 1):
        v = base_lo + (base_hi - base_lo) * i / n
        if all(abs(v - u) > tol for u in vals):
            out.append(round(v, 6))
    out = sorted(set(out))
    # Never let two lines end up closer than a third of a groove half-width: a pair that tight is
    # an accidental crease, and it shows up as a scratch down the paint.
    keep = [out[0]]
    for v in out[1:]:
        if v - keep[-1] > tol * 0.22:
            keep.append(v)
    return keep


def build_stations():
    # Every section key is a grid line. Without that the loft is only sampled at the filler
    # spacing and a 3 cm feature like the ducktail crest lands between two stations and vanishes.
    feats = [NOSE_F, TAIL_F] + [k[0] for k in KEYS]
    for gr in GROOVES + [SILL]:
        if gr["axis"] == 'f':
            e = gr.get("eps_f", GROOVE_EPS_F)
            feats += [gr["at"] - e, gr["at"], gr["at"] + e]
        else:
            a, b = gr["rng"]
            feats += [a, b]
    for op in OPENINGS:
        a, b = op["f"]
        feats += [a, b, a - HOLD_F, b + HOLD_F]
        if "g2" in op:
            # A tapered aperture needs stations along its length or the slope comes out as two
            # or three steps instead of an edge.
            feats += [a + (b - a) * k / 5.0 for k in range(1, 5)]
    feats += [HANDLES[0][0] - HANDLE_R[0], HANDLES[0][0] + HANDLE_R[0]]
    feats = [min(max(v, TAIL_F), NOSE_F) for v in feats]
    return merge(feats, TAIL_F, NOSE_F, BASE_F_STEP, GROOVE_EPS_F * 2.2)


def build_ring():
    """Half-section samples in [0, 32], padded so the two halves have equal counts (the nose and
    tail caps are Coons patches and need four sides of matching length), then mirrored."""
    feats = [0.0, 16.0, 32.0]
    for gr in GROOVES + [SILL]:
        e = gr.get("eps_g", GROOVE_EPS_G)
        if gr["axis"] == 'g':
            for at in groove_ranges(gr):
                feats += [fold(at - e), fold(at), fold(at + e)]
        else:
            for (a, b) in groove_ranges(gr):
                feats += [fold(a), fold(b)]
    for op in OPENINGS:
        for (a, b) in opening_ranges(op):
            feats += [fold(a), fold(b), fold(a - HOLD_G), fold(b + HOLD_G)]
    # The door pull is a soft dish, not a cut, so it does not get grid lines of its own.
    feats = [min(max(v, 0.0), 32.0) for v in feats]
    half = merge(feats, 0.0, 32.0, BASE_H_STEP, GROOVE_EPS_G * 2.2)
    # Pad the sparser half until the two have the same number of spans.
    while True:
        lo = [v for v in half if v <= 16.0]
        hi = [v for v in half if v >= 16.0]
        if len(lo) == len(hi):
            break
        side = lo if len(lo) < len(hi) else hi
        gaps = [(side[i + 1] - side[i], i) for i in range(len(side) - 1)]
        gaps.sort(reverse=True)
        _, i = gaps[0]
        half = sorted(half + [0.5 * (side[i] + side[i + 1])])
    ring = list(half) + [64.0 - v for v in reversed(half[1:-1])]
    return ring


# =============================================================================================
# Displacement: shut lines, the rocker step, arch lips, door pulls
# =============================================================================================
def smoothstep(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def band(v, a, b, fade):
    """1 inside [a, b], fading to 0 over `fade` at each end."""
    if b < a:
        a, b = b, a
    if v <= a or v >= b:
        return 0.0
    return min(smoothstep((v - a) / fade), smoothstep((b - v) / fade))


def band_g(v, a, b, fade):
    if not wrap_in(v, a, b):
        return 0.0
    da = (v - a) % 64.0
    db = (b - v) % 64.0
    return min(smoothstep(da / fade), smoothstep(db / fade))


def groove_depth(f, g):
    d = 0.0
    for gr in GROOVES + [SILL]:
        dep = gr.get("depth", GROOVE_DEPTH)
        if gr["axis"] == 'f':
            if abs(f - gr["at"]) > gr.get("eps_f", GROOVE_EPS_F) * 0.42:
                continue
            for (a, b) in groove_ranges(gr):
                d = max(d, dep * band_g(g, a, b, gr.get("fade", 1.2)))
        else:
            ats = groove_ranges(gr)
            e = gr.get("eps_g", GROOVE_EPS_G)
            hit = any(abs(((g - at + 32.0) % 64.0) - 32.0) < e * 0.42 for at in ats)
            if not hit:
                continue
            a, b = gr["rng"]
            d = max(d, dep * band(f, a, b, gr.get("fade", 0.055)))
    return d


def handle_depth(f, g):
    d = 0.0
    for (hf, hg) in HANDLES:
        du = (f - hf) / HANDLE_R[0]
        dv = (((g - hg + 32.0) % 64.0) - 32.0) / HANDLE_R[1]
        r = math.hypot(du, dv)
        if r < 1.0:
            d = max(d, HANDLE_DEPTH * smoothstep(1.0 - r))
    return d


def arch_lip(f, g, z):
    """Push the skin just outside an arch cut proud, so the arch has a blistered lip."""
    if fold(g) < 4.2 or fold(g) > 19.0:
        return 0.0
    best = 0.0
    for fa in (AXLE, -AXLE):
        d = math.hypot(f - fa, z - HUB_Z)
        if ARCH_R < d < ARCH_R + 0.095:
            t = (d - ARCH_R) / 0.095
            best = max(best, 0.014 * (1.0 - t) ** 1.6)
    return best


def surface(loft, f, g):
    p = loft.raw(f, g)
    n = loft.normal(f, g)
    off = arch_lip(f, g, p.z) - groove_depth(f, g) - handle_depth(f, g)
    return p + n * off, n


# =============================================================================================
# Blender plumbing
# =============================================================================================
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_materials():
    mats = []
    for name, col, metal, rough in SLOTS:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (col[0], col[1], col[2], 1.0)
        bsdf.inputs["Metallic"].default_value = metal
        bsdf.inputs["Roughness"].default_value = rough
        mats.append(m)
    return mats


def new_object(name, bm, mats):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    for m in mats:
        ob.data.materials.append(m)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def apply_modifiers(ob):
    bpy.context.view_layer.objects.active = ob
    for mod in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)


def subsurf(ob, levels):
    mod = ob.modifiers.new("sub", 'SUBSURF')
    mod.levels = levels
    mod.render_levels = levels
    mod.quality = 3
    mod.use_limit_surface = True
    mod.boundary_smooth = 'PRESERVE_CORNERS'
    apply_modifiers(ob)


def bevel(ob, width, segments=2, angle=36.0):
    mod = ob.modifiers.new("bev", 'BEVEL')
    mod.width = width
    mod.segments = segments
    mod.limit_method = 'ANGLE'
    mod.angle_limit = math.radians(angle)
    mod.miter_outer = 'MITER_ARC'
    apply_modifiers(ob)


def solidify(ob, thickness):
    mod = ob.modifiers.new("sol", 'SOLIDIFY')
    mod.thickness = thickness
    mod.offset = -1.0
    apply_modifiers(ob)


def shade(ob, sharp_deg=52.0):
    """Smooth everywhere; sharp only where two faces really do meet at an angle. If a body panel
    still shows facets after this, the surface is wrong, not the shading."""
    me = ob.data
    for poly in me.polygons:
        poly.use_smooth = True
    lim = math.cos(math.radians(sharp_deg))
    faces = {}
    for poly in me.polygons:
        for ek in poly.edge_keys:
            faces.setdefault(ek, []).append(poly.index)
    for e in me.edges:
        fl = faces.get(e.key, [])
        if len(fl) != 2:
            e.use_edge_sharp = True
            continue
        if me.polygons[fl[0]].normal.dot(me.polygons[fl[1]].normal) < lim:
            e.use_edge_sharp = True


def join(parts):
    bpy.ops.object.select_all(action='DESELECT')
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    return parts[0]


# =============================================================================================
# The shell
# =============================================================================================
def coons_cap(bm, ring_verts, mats_idx, bulge, outward):
    """Fill an end ring with a quad grid (a Coons patch between its four sides), so the nose and
    tail panels are quads like everything else. An n-gon cap would put a 60-valence pole in the
    middle of the front of the car and subdivision would pinch it into a dimple."""
    n = len(ring_verts)
    q = n // 4
    corner = [0, q, 2 * q, 3 * q]
    bottom = [ring_verts[i] for i in range(corner[0], corner[1] + 1)]
    right = [ring_verts[i] for i in range(corner[1], corner[2] + 1)]
    top = [ring_verts[(corner[3] - i) % n] for i in range(q + 1)]
    left = [ring_verts[(n - i) % n] for i in range(q + 1)]
    Q00, Q10, Q11, Q01 = bottom[0].co, bottom[-1].co, right[-1].co, left[-1].co
    grid = []
    for iu in range(q + 1):
        u = iu / q
        row = []
        for iv in range(q + 1):
            v = iv / q
            if iv == 0:
                vert = bottom[iu]
            elif iv == q:
                vert = top[iu]
            elif iu == 0:
                vert = left[iv]
            elif iu == q:
                vert = right[iv]
            else:
                p = ((1 - v) * bottom[iu].co + v * top[iu].co
                     + (1 - u) * left[iv].co + u * right[iv].co
                     - ((1 - u) * (1 - v) * Q00 + u * (1 - v) * Q10
                        + u * v * Q11 + (1 - u) * v * Q01))
                p = p + outward * (bulge * math.sin(math.pi * u) * math.sin(math.pi * v))
                vert = bm.verts.new(p)
            row.append(vert)
        grid.append(row)
    for iu in range(q):
        for iv in range(q):
            f = bm.faces.new((grid[iu][iv], grid[iu + 1][iv],
                              grid[iu + 1][iv + 1], grid[iu][iv + 1]))
            f.material_index = mats_idx
    return grid


def build_cage(loft, stations, ring):
    """The control cage. Every face remembers the (f, g) cell it came from, which is how the
    feature tables can select faces exactly instead of by a nearest-point search over the skin."""
    bm = bmesh.new()
    nS, nR = len(stations), len(ring)
    verts = [[None] * nR for _ in range(nS)]
    nrm = {}
    vfg = {}
    for i, f in enumerate(stations):
        for j, g in enumerate(ring):
            p, n = surface(loft, f, g)
            v = bm.verts.new(p)
            verts[i][j] = v
            nrm[v] = n
            vfg[v] = (f, g)
    bm.verts.index_update()
    fg = {}
    for i in range(nS - 1):
        fc = 0.5 * (stations[i] + stations[i + 1])
        for j in range(nR):
            j2 = (j + 1) % nR
            a, b, c, d = verts[i][j], verts[i + 1][j], verts[i + 1][j2], verts[i][j2]
            if len({a, b, c, d}) < 4:
                continue
            face = bm.faces.new((a, b, c, d))
            face.material_index = PAINT
            g2 = ring[j2] if j2 > j else ring[j2] + 64.0
            fg[face] = (fc, (0.5 * (ring[j] + g2)) % 64.0)
    # Nose and tail caps. They get no (f, g), so no opening can ever select them.
    coons_cap(bm, verts[-1], PAINT, 0.055, Vector((0.0, 1.0, 0.0)))
    coons_cap(bm, verts[0], PAINT, 0.055, Vector((0.0, -1.0, 0.0)))
    bm.faces.ensure_lookup_table()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    crease = bm.edges.layers.float.get("crease_edge") or bm.edges.layers.float.new("crease_edge")
    return bm, verts, nrm, fg, vfg, crease


# --- carving ---------------------------------------------------------------------------------
def carve(bm, faces, nrm, steps, mat, crease=None, crease_val=0.0):
    """Delete a patch of skin and push its border inward, twice, then cap it. That second ring is
    the inner wall you can see down the intake; the first is only a rim radius."""
    fset = set(faces)
    if not fset:
        return []
    bedges = set()
    for f in fset:
        for e in f.edges:
            if len(e.link_faces) != 2 or any(lf not in fset for lf in e.link_faces):
                bedges.add(e)
    ring_verts = set()
    for e in bedges:
        ring_verts.update(e.verts)
    cen = Vector((0.0, 0.0, 0.0))
    for v in ring_verts:
        cen += v.co
    cen /= max(len(ring_verts), 1)
    axis = Vector((0.0, 0.0, 0.0))
    for v in ring_verts:
        axis += nrm.get(v, Vector((0.0, 0.0, 1.0)))
    axis = axis.normalized() if axis.length > 1e-6 else Vector((0.0, 0.0, 1.0))

    bmesh.ops.delete(bm, geom=list(fset), context='FACES')
    cur_edges = [e for e in bedges if e.is_valid]
    if crease is not None and crease_val > 0.0:
        for e in cur_edges:
            e[crease] = crease_val
    cur_n = {v: nrm.get(v, axis) for v in ring_verts if v.is_valid}
    made = []
    for (depth, shrink) in steps:
        ret = bmesh.ops.extrude_edge_only(bm, edges=cur_edges)
        geom = ret["geom"]
        new_verts = [g for g in geom if isinstance(g, bmesh.types.BMVert)]
        new_faces = [g for g in geom if isinstance(g, bmesh.types.BMFace)]
        made += new_faces
        nxt_n = {}
        old_set = set(cur_n)
        for nv in new_verts:
            src = None
            for e in nv.link_edges:
                o = e.other_vert(nv)
                if o in old_set:
                    src = o
                    break
            n = cur_n.get(src, axis) if src else axis
            base = (src.co if src else nv.co) - n * depth
            t = base - cen
            along = axis * t.dot(axis)
            nv.co = cen + along + (t - along) * shrink
            nxt_n[nv] = n
        cur_n = nxt_n
        cur_edges = [g for g in geom
                     if isinstance(g, bmesh.types.BMEdge) and all(v in nxt_n for v in g.verts)]
    if cur_edges:
        res = bmesh.ops.contextual_create(bm, geom=cur_edges)
        made += res.get("faces", [])
    for f in made:
        f.material_index = mat
    return made


def carve_openings(bm, loft, nrm, fg, vfg, crease):
    """Every opening in one pass. Face selection is by (f, g) rectangle, and because the grid
    lines were placed at exactly those bounds the cut lands ON them and not near them.

    A TAPERED aperture is the exception: its edge runs diagonally across the cells, so selecting
    whole faces stair-steps it. The fix is to cut first and then slide the boundary vertices back
    onto the exact edge - the same trick the wheel arches use, and without it a side window comes
    out with a staircase down its top edge."""
    for op in OPENINGS:
        fa, fb = op["f"]
        tapered = "g2" in op
        for m in ([False, True] if op.get("mirror") else [False]):
            sel = []
            for f in bm.faces:
                cell = fg.get(f)
                if cell is None or not (fa < cell[0] < fb):
                    continue
                t = (cell[0] - fa) / (fb - fa)
                if wrap_in(cell[1], *op_range_at(op, t, m)):
                    sel.append(f)
            if not sel:
                continue
            if tapered:
                snap_taper(loft, set(sel), op, m, vfg)
            carve(bm, sel, nrm, op["steps"], op["mat"], crease, RIM_CREASE)


def snap_taper(loft, fset, op, mirror, vfg):
    """Slide the cut boundary onto the aperture's true edge, for the long sides only: the two end
    edges already sit on stations and must stay there."""
    fa, fb = op["f"]
    border = set()
    for f in fset:
        for e in f.edges:
            if len(e.link_faces) != 2 or any(lf not in fset for lf in e.link_faces):
                border.update(e.verts)
    for v in border:
        cell = vfg.get(v)
        if cell is None:
            continue
        vf, vg = cell
        if vf < fa + 1e-4 or vf > fb - 1e-4:
            continue
        t = min(max((vf - fa) / (fb - fa), 0.0), 1.0)
        a, b = op_range_at(op, t, mirror)
        da = abs(((vg - a + 32.0) % 64.0) - 32.0)
        db = abs(((vg - b + 32.0) % 64.0) - 32.0)
        if min(da, db) > 1.4:
            continue
        v.co = surface(loft, vf, a if da < db else b)[0]


def carve_arches(bm, nrm, fg, crease):
    """The wheel arches. Selection is the arch circle in the (Y, Z) plane; the cut boundary is
    snapped onto that circle BEFORE the extrusion, so the well inherits a round mouth instead of
    a stair-stepped one - and only above the hub line, because below it a real arch runs straight
    down into the sill rather than curling back under the car."""
    for fa in (AXLE, -AXLE):
        sel = []
        for f in bm.faces:
            cell = fg.get(f)
            if cell is None or fold(cell[1]) < 3.2:
                continue
            c = f.calc_center_median()
            if abs(c.x) > 0.42 and math.hypot(c.y - fa, c.z - HUB_Z) < ARCH_R:
                sel.append(f)
        if not sel:
            continue
        fset = set(sel)
        border = set()
        for f in fset:
            for e in f.edges:
                if len(e.link_faces) != 2 or any(lf not in fset for lf in e.link_faces):
                    border.update(e.verts)
        for v in border:
            if v.co.z < HUB_Z - 0.165:
                continue
            d = Vector((0.0, v.co.y - fa, v.co.z - HUB_Z))
            # Only snap what is already near the rim. A vertex at a third of the radius that
            # happened to touch the cut gets catapulted outward into a spike otherwise, which is
            # exactly what the first render grew above the front wheel.
            if not (ARCH_R * 0.72 < d.length < ARCH_R * 1.40):
                continue
            k = ARCH_R / d.length
            v.co.y = fa + d.y * k
            v.co.z = HUB_Z + d.z * k
        carve(bm, sel, nrm, [(0.018, 0.995), (0.215, 0.90)], TYRE, crease, RIM_CREASE)


def build_shell(loft, mats):
    stations = build_stations()
    ring = build_ring()
    bm, verts, nrm, fg, vfg, crease = build_cage(loft, stations, ring)
    carve_arches(bm, nrm, fg, crease)
    carve_openings(bm, loft, nrm, fg, vfg, crease)
    bm.faces.ensure_lookup_table()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    ob = new_object(PREFIX + "shell", bm, mats)
    cage = len(ob.data.polygons)
    subsurf(ob, SUBDIV)
    return ob, len(stations), len(ring), cage


# =============================================================================================
# Glass, lenses and the rest of the detail
# =============================================================================================
def panel(loft, bm, f_rng, g_rng, inset, mat, nu=26, nv=18, shrink=0.012, g_end=None):
    """A pane conformed to the skin and set `inset` below it, so glass sits in a frame instead of
    lying flush on the body. `g_end` gives it the same taper as its aperture."""
    fa, fb = f_rng
    f0, f1 = fa, fb
    fa, fb = fa + (fb - fa) * shrink, fb - (fb - fa) * shrink
    grid = []
    for i in range(nu + 1):
        f = fa + (fb - fa) * i / nu
        ga, gb = g_rng
        if g_end is not None:
            t = (f - f0) / (f1 - f0)
            ga = ga + (g_end[0] - ga) * t
            gb = gb + (g_end[1] - gb) * t
        span = (gb - ga) % 64.0
        ga2 = ga + span * shrink
        span2 = span * (1.0 - 2.0 * shrink)
        row = []
        for j in range(nv + 1):
            g = ga2 + span2 * j / nv
            p = loft.raw(f, g)
            n = loft.normal(f, g)
            row.append(bm.verts.new(p - n * inset))
        grid.append(row)
    for i in range(nu):
        for j in range(nv):
            f = bm.faces.new((grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]))
            f.material_index = mat
    return grid


def build_glass(loft, mats):
    """Glass, taken straight from the aperture table so a pane can never drift away from the hole
    it belongs in - which is exactly what happened when the lamp openings moved and the lenses
    stayed behind, leaving two black slots in the nose."""
    bm = bmesh.new()
    for name, inset, nu, nv in (("windscreen", 0.024, 30, 22), ("glass_rear", 0.024, 22, 16),
                                ("glass_side", 0.022, 22, 12)):
        op = OPEN_BY_NAME[name]
        for m in ([False, True] if op.get("mirror") else [False]):
            # Negative shrink: the pane overhangs its hole. A pane cut to the exact aperture
            # leaves a sliver of the dark frame showing at every edge, which reads as a gap.
            panel(loft, bm, op["f"], op_range_at(op, 0.0, m), inset, GLASS, nu, nv,
                  shrink=-0.010, g_end=op_range_at(op, 1.0, m) if "g2" in op else None)
    ob = new_object(PREFIX + "glass", bm, mats)
    bpy.context.view_layer.objects.active = ob
    solidify(ob, 0.006)
    return ob


def bmesh_recalc(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(ob.data)
    bm.free()


def build_lenses(loft, mats):
    """Lamp lenses down inside their recesses, with brighter blades in front of them. No
    manufacturer's light signature: three plain elements front, one bar rear."""
    bm = bmesh.new()
    for name, mat, inset, blades in (("lamp_front", LIGHT_F, 0.030, 3),
                                     ("lamp_rear", LIGHT_R, 0.028, 1)):
        op = OPEN_BY_NAME[name]
        fa, fb = op["f"]
        for m in (False, True):
            g0 = op_range_at(op, 0.0, m)
            g1 = op_range_at(op, 1.0, m) if "g2" in op else g0
            panel(loft, bm, op["f"], g0, inset, mat, 16, 10, shrink=0.05, g_end=g1)
            for k in range(blades):
                c = (k + 0.5) / blades
                w = 0.30 / blades
                def lerp(r, u):
                    return r[0] + ((r[1] - r[0]) % 64.0) * u
                sub0 = (lerp(g0, c - w), lerp(g0, c + w))
                sub1 = (lerp(g1, c - w), lerp(g1, c + w))
                panel(loft, bm, (fa + (fb - fa) * 0.10, fb - (fb - fa) * 0.10), sub0,
                      inset - 0.014, mat, 8, 4, shrink=0.02, g_end=sub1)
    ob = new_object(PREFIX + "lens", bm, mats)
    return ob


# --- primitive helpers for the hard details ---------------------------------------------------
def bm_box(bm, centre, size, mat, rot_x=0.0, rot_z=0.0, taper=1.0):
    hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
    pts = []
    for sz in (-1, 1):
        k = taper if sz > 0 else 1.0
        for sy in (-1, 1):
            for sx in (-1, 1):
                pts.append(Vector((sx * hx * k, sy * hy, sz * hz)))
    cx, sx_ = math.cos(rot_x), math.sin(rot_x)
    cz, sz_ = math.cos(rot_z), math.sin(rot_z)
    vs = []
    for p in pts:
        y, z = p.y * cx - p.z * sx_, p.y * sx_ + p.z * cx
        x, y = p.x * cz - y * sz_, p.x * sz_ + y * cz
        vs.append(bm.verts.new(Vector((x, y, z)) + Vector(centre)))
    quads = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6),
             (0, 2, 6, 4), (1, 5, 7, 3)]
    for q in quads:
        f = bm.faces.new([vs[i] for i in q])
        f.material_index = mat
    return vs


def bm_tube(bm, centre, r_out, r_in, depth, mat, segs=24, axis='y'):
    """A real tube with an inner wall you can see down. An exhaust drawn as a black disc is the
    single most obvious tell of a cheap car model."""
    rings = []
    for (r, y) in ((r_out, -depth * 0.5), (r_out, depth * 0.5),
                   (r_in, depth * 0.5), (r_in, -depth * 0.5)):
        ring = []
        for k in range(segs):
            a = 2.0 * math.pi * k / segs
            p = Vector((math.cos(a) * r, y, math.sin(a) * r * 0.82))
            if axis == 'z':
                p = Vector((p.x, p.z, p.y))
            ring.append(bm.verts.new(p + Vector(centre)))
        rings.append(ring)
    for ri in range(3):
        a, b = rings[ri], rings[ri + 1]
        for k in range(segs):
            k2 = (k + 1) % segs
            f = bm.faces.new((a[k], a[k2], b[k2], b[k]))
            f.material_index = mat
    a, b = rings[3], rings[0]
    for k in range(segs):
        k2 = (k + 1) % segs
        f = bm.faces.new((a[k], a[k2], b[k2], b[k]))
        f.material_index = mat


def bm_sphere(bm, centre, radius, mat, su=26, sv=16, scale=(1.0, 1.0, 1.0)):
    grid = []
    for i in range(sv + 1):
        th = math.pi * i / sv
        row = []
        for j in range(su):
            ph = 2.0 * math.pi * j / su
            p = Vector((math.sin(th) * math.cos(ph) * scale[0],
                        math.sin(th) * math.sin(ph) * scale[1],
                        math.cos(th) * scale[2])) * radius
            row.append(bm.verts.new(p + Vector(centre)))
        grid.append(row)
    for i in range(sv):
        for j in range(su):
            j2 = (j + 1) % su
            f = bm.faces.new((grid[i][j], grid[i][j2], grid[i + 1][j2], grid[i + 1][j]))
            f.material_index = mat


def bm_disc(bm, centre, normal, radius, depth, mat, segs=28, scale_u=1.0):
    """A flat disc lying ON the skin, oriented by the surface normal. A sphere sunk into the body
    reads as a blister, not a recess - which is what the first pass got for every badge panel."""
    n = Vector(normal).normalized()
    up = Vector((0.0, 0.0, 1.0))
    if abs(n.z) > 0.9:
        up = Vector((0.0, 1.0, 0.0))
    u = n.cross(up).normalized() * scale_u
    v = n.cross(u).normalized()
    c = Vector(centre)
    front, back = [], []
    for k in range(segs):
        a = 2.0 * math.pi * k / segs
        r = u * (math.cos(a) * radius) + v * (math.sin(a) * radius)
        front.append(bm.verts.new(c + r))
        back.append(bm.verts.new(c + r - n * depth))
    f = bm.faces.new(front)
    f.material_index = mat
    for k in range(segs):
        k2 = (k + 1) % segs
        f = bm.faces.new((front[k], front[k2], back[k2], back[k]))
        f.material_index = mat


def build_details(loft, mats):
    """Everything that is not skin. Positions come from the loft surface wherever a part has to
    sit on or in the body, so moving a section key moves the parts with it instead of leaving
    slats floating in the middle of an intake."""
    bm = bmesh.new()

    def on(f, g, depth):
        """A point `depth` below the skin at (f, g), and the surface normal there."""
        pnt = loft.raw(f, g)
        n = loft.normal(f, g)
        return pnt - n * depth, n

    # --- front splitter. Tucked right under the nose and barely proud of it. The first pass
    #     had a 1.6 x 0.45 m plate reaching forward and it read as a skateboard. -------------
    bm_box(bm, (0.0, 2.090, 0.0600), (1.14, 0.205, 0.020), TRIM, taper=0.74)
    for sgn in (-1.0, 1.0):
        bm_box(bm, (sgn * 0.470, 2.088, 0.086), (0.020, 0.185, 0.060), TRIM, rot_z=sgn * 0.05)
        bm_box(bm, (sgn * 0.838, 1.955, 0.430), (0.120, 0.215, 0.015), TRIM, rot_x=-0.16)

    # --- slats in the low front mouth and vanes in the corner intakes ------------------------
    for k in range(4):
        g = 60.4 + k * 1.9
        pa, _ = on(2.150, g % 64.0, 0.075)
        pb, _ = on(2.150, (128.0 - g) % 64.0, 0.075)
        bm_box(bm, (0.0, 0.5 * (pa.y + pb.y), 0.5 * (pa.z + pb.z)),
               (abs(pa.x - pb.x) + 0.10, 0.026, 0.016), TRIM, rot_x=0.34)
    for sgn in (-1.0, 1.0):
        for k in range(3):
            g = 11.8 + k * 1.1
            pt, _ = on(2.145, g if sgn > 0 else (64.0 - g), 0.055)
            bm_box(bm, (pt.x, pt.y, pt.z), (0.016, 0.068, 0.120), TRIM, rot_z=sgn * 0.20)

    # --- side intake vanes, hung off the surface the intake was cut from ----------------------
    for sgn in (-1.0, 1.0):
        for k in range(3):
            f = -0.590 - k * 0.100
            pt, _ = on(f, 11.8 if sgn > 0 else 52.2, 0.105)
            bm_box(bm, (pt.x, pt.y, pt.z), (0.075, 0.026, 0.175), TRIM, rot_z=sgn * 0.10)

    # --- engine deck louvres, lying in the dish between the buttresses ------------------------
    for k in range(8):
        f = -1.125 - k * 0.050
        pt, _ = on(f, 32.0, 0.026)
        pe, _ = on(f, 29.6, 0.026)
        bm_box(bm, (0.0, pt.y, pt.z - 0.003), (abs(pe.x) * 2.0 - 0.02, 0.024, 0.017),
               TRIM, rot_x=0.48)

    # --- side skirts: the blade under the rocker step -----------------------------------------
    for sgn in (-1.0, 1.0):
        pt, _ = on(0.030, 6.0 if sgn > 0 else 58.0, -0.012)
        bm_box(bm, (pt.x, pt.y, pt.z), (0.055, 1.94, 0.030), TRIM, rot_z=sgn * 0.02)

    # --- mirrors on proper stalks. Anchored on the skin at the door top, not floating -------
    for sgn in (-1.0, 1.0):
        root, rn = on(0.700, 18.4 if sgn > 0 else 45.6, -0.004)
        tip = Vector((sgn * 1.048, root.y - 0.030, root.z + 0.058))
        mid = (root + tip) * 0.5
        bm_box(bm, tuple(mid), (abs(tip.x - root.x) + 0.02, 0.036, 0.028), TRIM, rot_x=-0.26)
        bm_sphere(bm, tuple(tip), 0.072, PAINT, 22, 14, scale=(0.95, 1.40, 0.60))
        bm_box(bm, (tip.x + sgn * 0.022, tip.y - 0.064, tip.z), (0.014, 0.104, 0.064),
               GLASS, rot_z=sgn * 0.22)

    # --- door pulls: a trim tab lying in the dish the skin already has -----------------------
    for (hf, hg) in HANDLES:
        pt, _ = on(hf, hg, 0.005)
        bm_box(bm, (pt.x, pt.y, pt.z), (0.024, 0.126, 0.026), TRIM,
               rot_z=(0.03 if pt.x > 0 else -0.03))

    # --- fuel flap: a paint disc inside a dark ring, which is all a flap ever is --------------
    pt, nf = on(FLAP["f"], FLAP["g"], 0.004)
    bm_disc(bm, pt, nf, FLAP["r"], 0.012, TRIM, 28)
    bm_disc(bm, pt - nf * 0.0035, nf, FLAP["r"] - 0.007, 0.010, PAINT, 28)

    # --- badge recesses. A recess, never a badge: badges are somebody's trademark -------------
    for (bf, bg) in ((1.700, 32.0), (-2.060, 32.0)):
        pt, nb = on(bf, bg, 0.010)
        bm_disc(bm, pt, nb, 0.046, 0.016, TRIM, 26, scale_u=1.7)

    # --- rear diffuser and exhausts. One tilted ramp with fins, tucked up under the valance ---
    bm_box(bm, (0.0, -2.060, 0.208), (1.46, 0.290, 0.024), TRIM, rot_x=-0.36)
    for k in range(7):
        bm_box(bm, ((k - 3) * 0.196, -2.060, 0.248), (0.022, 0.280, 0.098), TRIM, rot_x=-0.36)
    for sgn in (-1.0, 1.0):
        bm_tube(bm, (sgn * 0.230, -2.135, 0.340), 0.075, 0.059, 0.200, TRIM, 26)

    # --- windscreen wiper, parked on the cowl -------------------------------------------------
    bm_box(bm, (-0.17, 0.930, 0.800), (0.030, 0.140, 0.016), TRIM, rot_z=0.5)
    bm_box(bm, (0.10, 0.888, 0.842), (0.520, 0.020, 0.012), TRIM, rot_z=0.28)

    # --- a suggestion of an interior, seen through the screen ---------------------------------
    bm_box(bm, (0.0, 0.560, 0.870), (1.30, 0.30, 0.10), TRIM, rot_x=-0.26)       # dash top
    for sgn in (-1.0, 1.0):
        bm_box(bm, (sgn * 0.320, 0.070, 0.610), (0.44, 0.44, 0.10), TRIM)        # cushion
        bm_box(bm, (sgn * 0.320, -0.180, 0.840), (0.42, 0.10, 0.44), TRIM, rot_x=0.22)
    bm_sphere(bm, (-0.36, 0.450, 0.880), 0.140, TRIM, 24, 10, scale=(1.0, 0.16, 1.0))

    ob = new_object(PREFIX + "detail", bm, mats)
    bmesh_recalc(ob)
    bevel(ob, 0.0045, segments=2, angle=34.0)
    return ob


# =============================================================================================
# Build / export / verify
# =============================================================================================
def build():
    reset_scene()
    mats = make_materials()
    loft = Loft(KEYS)
    shell, nS, nR, cage = build_shell(loft, mats)
    glass = build_glass(loft, mats)
    lens = build_lenses(loft, mats)
    det = build_details(loft, mats)
    ob = join([shell, glass, lens, det])
    ob.name = PREFIX + "coupe"
    ob.data.name = ob.name
    shade(ob)
    print("  cage %d quads, %d stations x %d ring, subdiv %d" % (cage, nS, nR, SUBDIV))
    return ob


def export(ob, name):
    path = os.path.join(OUT_DIR, PREFIX + name + ".glb")
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', use_selection=True,
        export_apply=True, export_materials='EXPORT', export_yup=True,
        export_normals=True, export_texcoords=False, export_tangents=False,
        export_skins=False, export_animations=False, export_cameras=False,
        export_lights=False,
    )
    return path


def verify(path):
    """Read the numbers back out of the file that was actually written, not out of the scene."""
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=path)
    tris = 0
    per = {}
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    names = []
    for ob in list(bpy.context.scene.objects):
        if ob.type != 'MESH':
            continue
        me = ob.data
        me.calc_loop_triangles()
        slots = [ms.material.name if ms.material else "<none>" for ms in ob.material_slots]
        for n in slots:
            if n not in names:
                names.append(n)
        for t in me.loop_triangles:
            tris += 1
            si = me.polygons[t.polygon_index].material_index
            k = slots[si] if si < len(slots) else "<none>"
            per[k] = per.get(k, 0) + 1
        for v in me.vertices:
            w = ob.matrix_world @ v.co
            mn = Vector((min(mn.x, w.x), min(mn.y, w.y), min(mn.z, w.z)))
            mx = Vector((max(mx.x, w.x), max(mx.y, w.y), max(mx.z, w.z)))
    return tris, mn, mx, per, names


def main(argv):
    os.makedirs(OUT_DIR, exist_ok=True)
    ob = build()
    path = export(ob, "coupe")
    if "--no-verify" in argv:
        print("  -> " + path)
        return
    tris, mn, mx, per, names = verify(path)
    # The importer converts glTF's Y-up back to Blender's Z-up, so this is the authored frame:
    # X lateral, Y longitudinal, Z up - the same numbers the KEYS table is written in.
    print("READ BACK FROM %s" % os.path.basename(path))
    print("  triangles : %d" % tris)
    print("  bbox      : width %.3f  length %.3f  height %.3f"
          % (mx.x - mn.x, mx.y - mn.y, mx.z - mn.z))
    print("  extents   : y %+.3f .. %+.3f (centre %+.4f)  z %.4f .. %.4f"
          % (mn.y, mx.y, 0.5 * (mn.y + mx.y), mn.z, mx.z))
    print("  stance    : wheel centres %.3f above the lowest vertex, arches at y %+.3f/%+.3f"
          % (HUB_Z - mn.z, AXLE, -AXLE))
    print("  slots     : " + ", ".join(names))
    print("  per slot  : " + ", ".join("%s=%d" % (k, v) for k, v in sorted(per.items())))
    print("  -> " + path)


if __name__ == "__main__":
    main(sys.argv[1:])
