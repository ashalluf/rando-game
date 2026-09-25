#!/usr/bin/env python3
"""High-fidelity everyday four-door sedan body, built in Blender's Python API (bpy as a module,
no Blender binary needed):

    python3 tools/make_hifi_sedan.py

Writes assets/models/hifi_sedan.glb. Then `godot --headless --path . --import` (Godot serves a
cached import of a .glb otherwise, CLAUDE.md).

WHY THIS FILE EXISTS
--------------------
The sedan is the most common car in the city (Vehicle.BODY_ODDS, and the police cruiser), and
it used to be an ~8k-triangle Meshy remesh: a polygonal silhouette at the arch lips and bumper
corners and a mottled baked texture on the nose, parked beside the hi-fi exotics. This body is
built the way tools/make_hifi_gt.py builds the grand tourer - read that file's header, the
method is the same and is not repeated here:

    a quad control cage lofted from cross sections (Section, KEYS), subdivision at level 2,
    creases and holding loops for the shutlines, booleans for the arches, the mouths and the
    daylight openings, a small bevel, recessed glass in a rubber frame, proud arch lips.

WHAT IS DIFFERENT, AND WHY
--------------------------
BUDGET. An exotic is one car in eight and a hero object; the sedan is the bulk of ~150 traffic
cars and every other parked car. So the subdivided shell (about 120k triangles) is DECIMATED to
SHELL_TRIS with Blender's quadric collapse, symmetric about the centre line, then shaded by angle.
Quadric collapse spends triangles where the surface bends and on the sharp shutline and bevel
edges, so the silhouette and the panel gaps survive. Everything bolted on is built at a resolution chosen for a car
seen from a pavement, not a showroom. Total ~27k triangles at LOD0; Godot's importer builds the
LOD chain and the shadow mesh from that.

ONE SURFACE, NOT SIX. The exotics carry six material slots, which is six draw calls a car and
six more in each shadow pass. For the most common car in traffic that is several hundred draws
a street. So every part is built in a slot as usual, and at export the slots are folded into ONE
material ("paint") with the slot written into the vertex attributes:

    COLOR_0.rgb   the part's own linear albedo (glass, rubber, trim, lens, rim)
    COLOR_0.a     1 where the car's paint goes, 0 elsewhere
    TEXCOORD_0    x = roughness, y = metallic (+2.0 on a lamp lens, which glows at night)

and car_paint.gdshader reads them when `vertex_slots` is on (Vehicle.VERTEX_SLOT_BODIES). One
draw per car, the same as the Meshy body it replaces, and the glass is real glass by construction
instead of a guess from a texel's brightness or the body's shape (the GEO_GLASS_BELTLINE test).

WHEELS. The game draws a generated wheel in the arch up close (Vehicle._add_generated_wheels) and
hands over past wheel_draw_distance to a wheel baked into the body, which Vehicle shrinks into the
hub up close (PropFactory.tuck_body_wheels, WHEEL_POSE "cut"). So a plain low tyre and rim are
baked into each arch, about 300 triangles a wheel, and the arch itself is a blind pocket in black
behind them.

ORIGINAL DESIGN. A generic 2020s mid-size family sedan - a class, not a copy of any car. No
manufacturer's badge, grille shape or light signature: the grille is a plain slatted mouth, the
lamps are tapered blades, the badge recesses are empty.

THE STANCE
----------
    length 4.85   width 1.85 (without mirrors)   height 1.44   wheelbase 2.82

Styled as a 2020s car, not a 1990s one (that was the first pass's review): a low bonnet that
falls to a crisp leading edge 0.72 m up, slim headlamps joined by a dark slot, a wide low grille
with corner intakes, a windscreen raked ~24 degrees off horizontal, a fastback roof running into
a short high deck, and a character line rising toward the tail.
    front overhang 0.97   rear overhang 1.08   tyre 0.66 diameter (225/50 R17 class)

Geometry conventions are the GT's: authored X lateral, Y longitudinal with the nose at +Y (`f`),
Z up, ground at Z = 0; the glTF exporter turns that into Godot's X right, Y up, nose at -Z. The
section is addressed by the ring coordinate j (see ANCHOR_J). The run prints the WHEEL_POSE row
for Vehicle in body space.
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree

OUT_PATH = "assets/models/hifi_sedan.glb"

# --- material slots ----------------------------------------------------------------------------
# Built as slots (each part keeps its own), folded into vertex attributes at export (see header).
#   name, linear albedo, roughness, metallic, glows at night
SLOTS = [
    ("paint",       (1.0, 1.0, 1.0),       0.30, 0.30, False),
    ("glass",       (0.016, 0.018, 0.021), 0.04, 0.00, False),
    ("trim",        (0.030, 0.030, 0.032), 0.48, 0.00, False),
    ("tyre",        (0.026, 0.026, 0.028), 0.88, 0.00, False),
    ("light_front", (0.30, 0.31, 0.33),    0.08, 0.60, True),
    ("light_rear",  (0.42, 0.018, 0.022),  0.08, 0.10, True),
    ("rim",         (0.50, 0.51, 0.53),    0.30, 0.85, False),
    ("gloss",       (0.012, 0.012, 0.013), 0.10, 0.00, False),
]
PAINT, GLASS, TRIM, TYRE, LIGHT_F, LIGHT_R, RIM, GLOSS = range(8)

SUBSURF_LEVELS = 2
## Triangles the decimated shell is allowed. The rest of the budget is the glass, lamps, mirrors,
## trim and baked wheels, about 7k.
SHELL_TRIS = int(os.environ.get("SEDAN_SHELL_TRIS", "20500"))
## Final length along the car, metres. The model is scaled to exactly this at the end.
TARGET_LENGTH = 4.85

# --- the section: nine anchors, addressed by ring coordinate j --------------------------------
#   j = 0   underbody centreline        j = 13  beltline (bottom of the side glass)
#   j = 2   underbody outer edge        j = 16  mid glass / tumblehome
#   j = 4   sill (rocker) outer         j = 19  roof rail
#   j = 7   lower side (arch height)    j = 22  roof centreline
#   j = 10  shoulder / character line
# Forward of the cowl and aft of the backlight the top four anchors are the bonnet and the boot
# lid, crowned across the car.
ANCHOR_J = [0.0, 2.0, 4.0, 7.0, 10.0, 13.0, 16.0, 19.0, 22.0]

# Keyframed section scalars along the length (see make_hifi_gt.py for the column meanings), in
# two tables: the lower body and the upper body are keyed at different stations, because the
# glasshouse is placed on its own (the cowl, the header, the backlight) and the lower body follows
# the wheels. Each column is a monotone cubic along f.
KEYS_LOWER = [
    # f        zb     ub     us     zs     uh     zh     uw     zw
    (2.380, 0.215, 0.450, 0.660, 0.235, 0.775, 0.360, 0.795, 0.540),
    (2.250, 0.185, 0.505, 0.740, 0.212, 0.868, 0.365, 0.882, 0.575),
    (2.100, 0.165, 0.525, 0.760, 0.200, 0.908, 0.372, 0.918, 0.615),
    (1.850, 0.155, 0.540, 0.782, 0.200, 0.920, 0.380, 0.925, 0.660),
    (1.450, 0.150, 0.555, 0.800, 0.200, 0.922, 0.385, 0.926, 0.695),
    (1.100, 0.150, 0.560, 0.808, 0.205, 0.920, 0.392, 0.925, 0.712),
    (0.700, 0.150, 0.562, 0.815, 0.210, 0.918, 0.400, 0.924, 0.728),
    (0.000, 0.150, 0.562, 0.818, 0.210, 0.918, 0.400, 0.924, 0.752),
    (-0.800, 0.150, 0.562, 0.818, 0.210, 0.918, 0.400, 0.924, 0.778),
    (-1.350, 0.152, 0.558, 0.814, 0.210, 0.920, 0.400, 0.925, 0.795),
    (-1.600, 0.160, 0.552, 0.803, 0.212, 0.918, 0.400, 0.923, 0.802),
    (-1.850, 0.170, 0.532, 0.788, 0.220, 0.908, 0.400, 0.918, 0.808),
    (-2.050, 0.190, 0.508, 0.762, 0.240, 0.893, 0.410, 0.907, 0.810),
    (-2.220, 0.220, 0.482, 0.735, 0.268, 0.875, 0.420, 0.892, 0.808),
    (-2.370, 0.250, 0.452, 0.695, 0.295, 0.845, 0.430, 0.862, 0.800),
]
KEYS_UPPER = [
    # f        ubl    zbl     um     zm     ur     zr     zt
    (2.380, 0.775, 0.672, 0.630, 0.708, 0.385, 0.721, 0.726),
    (2.250, 0.862, 0.703, 0.718, 0.735, 0.415, 0.747, 0.751),
    (2.100, 0.898, 0.735, 0.745, 0.766, 0.425, 0.779, 0.783),
    (1.850, 0.903, 0.775, 0.755, 0.806, 0.432, 0.820, 0.824),
    (1.450, 0.902, 0.820, 0.760, 0.848, 0.435, 0.862, 0.866),
    (1.200, 0.900, 0.846, 0.760, 0.873, 0.435, 0.887, 0.891),
    (1.000, 0.897, 0.870, 0.765, 0.898, 0.448, 0.912, 0.917),
    (0.880, 0.894, 0.884, 0.780, 0.922, 0.495, 0.938, 0.944),
    (0.600, 0.889, 0.902, 0.805, 1.012, 0.588, 1.075, 1.092),
    (0.300, 0.885, 0.914, 0.795, 1.105, 0.642, 1.228, 1.255),
    (0.000, 0.882, 0.924, 0.785, 1.158, 0.662, 1.338, 1.375),
    (-0.300, 0.881, 0.934, 0.780, 1.180, 0.667, 1.392, 1.438),
    (-0.700, 0.880, 0.946, 0.776, 1.176, 0.662, 1.378, 1.418),
    (-1.050, 0.878, 0.960, 0.765, 1.155, 0.642, 1.328, 1.362),
    (-1.350, 0.875, 0.976, 0.748, 1.130, 0.612, 1.262, 1.288),
    (-1.650, 0.869, 0.998, 0.725, 1.102, 0.562, 1.182, 1.198),
    (-1.950, 0.862, 1.030, 0.703, 1.082, 0.502, 1.103, 1.108),
    (-2.150, 0.857, 1.050, 0.692, 1.082, 0.462, 1.093, 1.098),
    (-2.260, 0.855, 1.054, 0.682, 1.080, 0.432, 1.088, 1.093),
    (-2.370, 0.845, 1.042, 0.668, 1.068, 0.407, 1.076, 1.080),
]

F_NOSE = 2.380
F_TAIL = -2.370
ROLL_R = 0.024        # radius of the fillet that rolls the nose and tail rims into the fascias
ROLL_STEPS = 2

FRONT_AXLE = 1.450
REAR_AXLE = -1.370
AXLE_Z = 0.330
ARCH_R_F = 0.372
ARCH_R_R = 0.372
WHEEL_X = 0.800
TYRE_R = 0.330
TYRE_W = 0.225

# --- shutlines (as make_hifi_gt.py: a 7 mm x 5 mm recess held by loops either side) -----------
GAP_HALF_F = 0.0035
GAP_HOLD_F = 0.0065
GAP_HALF_J = 0.039
GAP_HOLD_J = 0.072
GAP_DEPTH = 0.005

# (f0, j_lo, j_hi): a gap running across the car at station f0, over that ring span.
TRANS_GAPS = [
    (2.290, 14.5, 22.0),    # bonnet front edge, over the headlamps
    (0.915, 14.5, 22.0),    # bonnet rear edge, at the cowl
    (0.985, 4.60, 13.05),   # front door front cut, behind the front arch
    (-0.140, 4.60, 13.05),  # front / rear door split, under the B-pillar
    (-1.050, 4.60, 13.05),  # rear door rear cut, down into the rear arch
    (-1.975, 14.5, 22.0),   # boot lid front edge, at the foot of the backlight
    (-2.290, 14.5, 22.0),   # boot lid rear edge, where the deck turns down
]
# (j0, f_lo, f_hi): a gap running along the car at ring j0, over that station span.
LONG_GAPS = [
    (14.5, 0.915, 2.290),    # bonnet side, where the wing top turns over
    (14.5, -2.290, -1.975),  # boot lid side
    (13.05, -1.050, 0.985),  # door tops (the belt line)
    (4.60, -1.050, 0.985),   # door bottoms, at the sill step
]

SHOULDER_J = 10.0
SHOULDER_CREASE = 1.0
SHOULDER_RIDGE = 0.014
SHOULDER_FADE = (2.08, 2.33)

# --- the glasshouse -----------------------------------------------------------------------------
A_PILLAR = [(13.30, 0.730), (14.60, 0.665), (15.60, 0.585), (16.60, 0.480),
            (17.60, 0.345), (18.60, 0.175), (19.60, 0.030), (20.60, -0.030), (22.00, -0.050)]
COWL = [(14.00, 0.770), (16.00, 0.832), (19.00, 0.868), (22.00, 0.880)]
C_PILLAR = [(13.30, -1.470), (15.00, -1.390), (16.60, -1.270), (18.50, -1.080)]
BACKLIGHT_FRONT = [(16.80, -1.290), (18.50, -1.170), (20.00, -1.100), (22.00, -1.070)]
BACKLIGHT_REAR = [(16.80, -1.860), (19.00, -1.900), (22.00, -1.920)]
PILLAR_HALF = 0.050
## The B-pillar applique (piano black over the glass) and the quarter-light divider in line
## with the rear door cut: (f centre, half width).
B_PILLAR = (-0.140, 0.052)
QUARTER_BAR = (-1.062, 0.016)

# --- the cage's own resolution ------------------------------------------------------------------
BASE_RINGS = [0.0, 1.8, 2.7, 3.6, 4.35, 5.1, 6.8, 8.6, 9.3, 9.65, 10.0, 10.35, 10.9,
              11.9, 12.95, 13.7, 14.6, 15.6, 16.6, 17.6, 18.6, 19.6, 20.6, 21.4, 22.0]
BASE_STATIONS = [2.380, 2.33, 2.20, 2.10, 1.98, 1.85, 1.70, 1.56, 1.450, 1.30, 1.16, 1.08,
                 0.94, 0.82, 0.68, 0.52, 0.36, 0.20, 0.05, -0.05, -0.26, -0.40, -0.56, -0.72,
                 -0.88, -0.98, -1.14, -1.26, -1.370, -1.50, -1.62, -1.74, -1.86, -2.06,
                 -2.16, -2.23, -2.32, -2.370]


# --- small numeric helpers ----------------------------------------------------------------------

def table(pts, x):
    """Piecewise-linear lookup over (x, y) pairs sorted ascending in x, clamped at both ends."""
    if x <= pts[0][0]:
        return pts[0][1]
    if x >= pts[-1][0]:
        return pts[-1][1]
    for k in range(len(pts) - 1):
        x0, y0 = pts[k]
        x1, y1 = pts[k + 1]
        if x0 <= x <= x1:
            t = (x - x0) / (x1 - x0)
            return y0 + t * (y1 - y0)
    return pts[-1][1]


class Mono:
    """Fritsch-Carlson monotone cubic (see make_hifi_gt.py: a plain spline overshoots)."""

    def __init__(self, xs, ys):
        order = sorted(range(len(xs)), key=lambda i: xs[i])
        self.x = [xs[i] for i in order]
        self.y = [ys[i] for i in order]
        n = len(self.x)
        d = [(self.y[i + 1] - self.y[i]) / (self.x[i + 1] - self.x[i]) for i in range(n - 1)]
        m = [0.0] * n
        m[0] = d[0]
        m[-1] = d[-1]
        for i in range(1, n - 1):
            m[i] = 0.0 if d[i - 1] * d[i] <= 0.0 else (d[i - 1] + d[i]) * 0.5
        for i in range(n - 1):
            if d[i] == 0.0:
                m[i] = m[i + 1] = 0.0
                continue
            a = m[i] / d[i]
            b = m[i + 1] / d[i]
            s = a * a + b * b
            if s > 9.0:
                t = 3.0 / math.sqrt(s)
                m[i] = t * a * d[i]
                m[i + 1] = t * b * d[i]
        self.m = m

    def __call__(self, x):
        xs = self.x
        if x <= xs[0]:
            return self.y[0] + (x - xs[0]) * self.m[0]
        if x >= xs[-1]:
            return self.y[-1] + (x - xs[-1]) * self.m[-1]
        lo, hi = 0, len(xs) - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if xs[mid] <= x:
                lo = mid
            else:
                hi = mid
        h = xs[hi] - xs[lo]
        t = (x - xs[lo]) / h
        t2 = t * t
        t3 = t2 * t
        return ((2 * t3 - 3 * t2 + 1) * self.y[lo] + (t3 - 2 * t2 + t) * h * self.m[lo]
                + (-2 * t3 + 3 * t2) * self.y[hi] + (t3 - t2) * h * self.m[hi])


class Section:
    """The body's cross section as a function of the station f, evaluated at any ring j (see
    make_hifi_gt.py; end tangents pinned horizontal so the mirrored halves meet smoothly)."""

    def __init__(self, lower, upper):
        fl = [k[0] for k in lower]
        fu = [k[0] for k in upper]
        self.curves = ([Mono(fl, [k[1 + i] for k in lower]) for i in range(8)]
                       + [Mono(fu, [k[1 + i] for k in upper]) for i in range(7)])

    def anchors(self, f):
        (zb, ub, us, zs, uh, zh, uw, zw, ubl, zbl, um, zm, ur, zr,
         zt) = [c(f) for c in self.curves]
        return [(0.0, zb), (ub, zb + 0.02), (us, zs), (uh, zh), (uw, zw),
                (ubl, zbl), (um, zm), (ur, zr), (0.0, zt)]

    @staticmethod
    def _tangents(P):
        T = ANCHOR_J
        n = len(P)
        m = [(0.0, 0.0)] * n
        d0 = math.hypot(P[1][0] - P[0][0], P[1][1] - P[0][1]) / (T[1] - T[0])
        m[0] = (d0, 0.0)
        dl = math.hypot(P[n - 1][0] - P[n - 2][0], P[n - 1][1] - P[n - 2][1]) / (T[n - 1] - T[n - 2])
        m[n - 1] = (-dl, 0.0)
        for k in range(1, n - 1):
            span = T[k + 1] - T[k - 1]
            m[k] = ((P[k + 1][0] - P[k - 1][0]) / span, (P[k + 1][1] - P[k - 1][1]) / span)
        return m

    def outline(self, f, rings):
        """Returns [(u, z, nu, nz)] per ring: the 2D point and its outward 2D normal."""
        P = self.anchors(f)
        m = self._tangents(P)
        T = ANCHOR_J
        out = []
        for j in rings:
            jv = min(max(j, T[0]), T[-1])
            k = 0
            while k < len(T) - 2 and jv > T[k + 1]:
                k += 1
            h = T[k + 1] - T[k]
            s = (jv - T[k]) / h
            s2 = s * s
            s3 = s2 * s
            h00, h10, h01, h11 = 2 * s3 - 3 * s2 + 1, s3 - 2 * s2 + s, -2 * s3 + 3 * s2, s3 - s2
            g00, g10, g01, g11 = 6 * s2 - 6 * s, 3 * s2 - 4 * s + 1, -6 * s2 + 6 * s, 3 * s2 - 2 * s
            u = h00 * P[k][0] + h10 * h * m[k][0] + h01 * P[k + 1][0] + h11 * h * m[k + 1][0]
            z = h00 * P[k][1] + h10 * h * m[k][1] + h01 * P[k + 1][1] + h11 * h * m[k + 1][1]
            du = (g00 * P[k][0] + g10 * h * m[k][0] + g01 * P[k + 1][0] + g11 * h * m[k + 1][0]) / h
            dz = (g00 * P[k][1] + g10 * h * m[k][1] + g01 * P[k + 1][1] + g11 * h * m[k + 1][1]) / h
            nl = math.hypot(du, dz) or 1.0
            out.append((u, z, dz / nl, -du / nl))
        return out

    def point(self, f, j, side=1.0):
        u, z, _nu, _nz = self.outline(f, [j])[0]
        return Vector((side * u, f, z))

    def normal(self, f, j, side=1.0):
        d = 0.01
        a = self.point(f - d, j, side)
        b = self.point(f + d, j, side)
        tf = (b - a).normalized()
        _u0, _z0, nu, nz = self.outline(f, [j])[0]
        nsec = Vector((side * nu, 0.0, nz))
        n = nsec - tf * nsec.dot(tf)
        return n.normalized() if n.length > 1e-6 else nsec


SEC = Section(KEYS_LOWER, KEYS_UPPER)


# --- blender plumbing ---------------------------------------------------------------------------

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_materials():
    mats = []
    for name, col, rough, metal, _glow in SLOTS:
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


def subsurf(ob, levels=SUBSURF_LEVELS):
    mod = ob.modifiers.new("subsurf", 'SUBSURF')
    mod.levels = levels
    mod.render_levels = levels
    if hasattr(mod, "use_creases"):
        mod.use_creases = True
    if hasattr(mod, "use_limit_surface"):
        mod.use_limit_surface = True
    apply_modifiers(ob)


def bevel(ob, width, segments=2, angle=40.0):
    mod = ob.modifiers.new("bev", 'BEVEL')
    mod.width = width
    mod.segments = segments
    mod.limit_method = 'ANGLE'
    mod.angle_limit = math.radians(angle)
    mod.miter_outer = 'MITER_ARC'
    mod.harden_normals = False
    if hasattr(mod, "use_clamp_overlap"):
        mod.use_clamp_overlap = True
    apply_modifiers(ob)


def boolean(ob, cutter, op='DIFFERENCE'):
    mod = ob.modifiers.new("bool", 'BOOLEAN')
    mod.object = cutter
    mod.operation = op
    mod.solver = 'EXACT'
    mod.material_mode = 'INDEX'
    apply_modifiers(ob)
    bpy.data.objects.remove(cutter, do_unlink=True)


def shade(ob, sharp_deg=33.0):
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


def join(objects):
    objects = [o for o in objects if o is not None]
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    return objects[0]


def crease_layer(bm):
    try:
        lay = bm.edges.layers.crease
        return lay.verify() if hasattr(lay, "verify") else lay
    except (AttributeError, TypeError):
        pass
    lay = bm.edges.layers.float.get("crease_edge")
    if lay is None:
        lay = bm.edges.layers.float.new("crease_edge")
    return lay


def tri_count(ob):
    ob.data.calc_loop_triangles()
    return len(ob.data.loop_triangles)


def decimate(ob, target, sharp_deg=33.0):
    """Collapse `ob` down to about `target` triangles, symmetric about the centre line, and shade
    it by angle. Its own normals, NOT the full-resolution surface's: transferring those back
    (DATA_TRANSFER, custom normals) was tried and smeared dark bands across every door - a
    decimated vertex on a shutline's edge took the groove wall's normal and spread it over a
    triangle half a door long. At this density the plain smooth normals are already clean."""
    n = tri_count(ob)
    if n > target:
        mod = ob.modifiers.new("dec", 'DECIMATE')
        mod.decimate_type = 'COLLAPSE'
        mod.ratio = target / float(n)
        mod.use_symmetry = True
        mod.symmetry_axis = 'X'
        mod.use_collapse_triangulate = True
        apply_modifiers(ob)
    shade(ob, sharp_deg)
    return n


# --- generic mesh builders -----------------------------------------------------------------------

def quad(bm, a, b, c, d, mat):
    try:
        f = bm.faces.new((a, b, c, d))
    except ValueError:
        return None
    f.material_index = mat
    return f


def grid_patch(bm, pts, nu, nv, mat, verts=None):
    if verts is None:
        verts = [bm.verts.new(p) for p in pts]
    for i in range(nu - 1):
        for j in range(nv - 1):
            quad(bm, verts[i * nv + j], verts[(i + 1) * nv + j],
                 verts[(i + 1) * nv + j + 1], verts[i * nv + j + 1], mat)
    return verts


def frames(path):
    n = len(path)
    tans = []
    for i in range(n):
        if i == 0:
            t = path[1] - path[0]
        elif i == n - 1:
            t = path[-1] - path[-2]
        else:
            t = path[i + 1] - path[i - 1]
        tans.append(t.normalized())
    ref = Vector((0, 0, 1))
    if abs(tans[0].dot(ref)) > 0.9:
        ref = Vector((1, 0, 0))
    up = (ref - tans[0] * ref.dot(tans[0])).normalized()
    out = []
    for i in range(n):
        up = (up - tans[i] * up.dot(tans[i]))
        up = up.normalized() if up.length > 1e-6 else Vector((0, 0, 1))
        out.append((tans[i], up, tans[i].cross(up).normalized()))
    return out


def sweep_tube(bm, path, radius, mat, segs=8, caps=False):
    fr = frames(path)
    rings = []
    for i, p in enumerate(path):
        _t, up, side = fr[i]
        r = radius(i) if callable(radius) else radius
        rings.append([bm.verts.new(p + up * (r * math.cos(a)) + side * (r * math.sin(a)))
                      for a in [2 * math.pi * k / segs for k in range(segs)]])
    for i in range(len(rings) - 1):
        for k in range(segs):
            k2 = (k + 1) % segs
            quad(bm, rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k], mat)
    if caps:
        for ring in (rings[0], rings[-1]):
            f = bm.faces.new(ring)
            f.material_index = mat
    return rings


def add_box(bm, size, loc, mat=TRIM):
    sx, sy, sz = (s * 0.5 for s in size)
    cx, cy, cz = loc
    co = [(-sx, -sy, -sz), (sx, -sy, -sz), (sx, sy, -sz), (-sx, sy, -sz),
          (-sx, -sy, sz), (sx, -sy, sz), (sx, sy, sz), (-sx, sy, sz)]
    v = [bm.verts.new((cx + x, cy + y, cz + z)) for x, y, z in co]
    for a, b, c, d in [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
                       (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]:
        quad(bm, v[a], v[b], v[c], v[d], mat)
    return v


# --- the control cage ---------------------------------------------------------------------------

def build_ring_list():
    rings = list(BASE_RINGS)
    gap_rings = {}
    for j0, _f0, _f1 in LONG_GAPS:
        if j0 in gap_rings:
            continue
        vals = [j0 - GAP_HOLD_J, j0 - GAP_HALF_J, j0 + GAP_HALF_J, j0 + GAP_HOLD_J]
        gap_rings[j0] = vals
        rings = [r for r in rings if abs(r - j0) > GAP_HOLD_J * 1.8]
        rings.extend(vals)
    rings = sorted(set(round(r, 6) for r in rings))
    # The nose and tail caps are Coons patches, which needs an odd ring count (make_hifi_gt.py).
    if len(rings) % 2 == 0:
        rings.append(round((rings[-2] + rings[-1]) * 0.5, 6))
        rings = sorted(set(rings))
    return rings, gap_rings


def build_station_list():
    st = list(BASE_STATIONS)
    gap_st = {}
    for f0, _j0, _j1 in TRANS_GAPS:
        vals = [f0 - GAP_HOLD_F, f0 - GAP_HALF_F, f0 + GAP_HALF_F, f0 + GAP_HOLD_F]
        gap_st[f0] = vals
        st = [f for f in st if abs(f - f0) > 0.03]
        st.extend(vals)
    st = sorted(set(round(f, 6) for f in st), reverse=True)
    return st, gap_st


def coons_cap(bm, loop, mat, dome, axis_sign):
    """Close a section loop with a quad grid instead of an n-gon (make_hifi_gt.py)."""
    K = len(loop)
    a = K // 4
    if a * 4 != K:
        f = bm.faces.new(loop)
        f.material_index = mat
        return
    corner = [loop[0], loop[a], loop[2 * a], loop[3 * a]]
    grid = [[None] * (a + 1) for _ in range(a + 1)]
    for p in range(a + 1):
        grid[p][0] = loop[p]
        grid[p][a] = loop[(3 * a - p) % K]
    for q in range(a + 1):
        grid[a][q] = loop[a + q]
        grid[0][q] = loop[(4 * a - q) % K]
    for p in range(1, a):
        for q in range(1, a):
            u = p / a
            v = q / a
            co = ((1 - v) * grid[p][0].co + v * grid[p][a].co
                  + (1 - u) * grid[0][q].co + u * grid[a][q].co
                  - ((1 - u) * (1 - v) * corner[0].co + u * (1 - v) * corner[1].co
                     + u * v * corner[2].co + (1 - u) * v * corner[3].co))
            co = co.copy()
            co.y += axis_sign * dome * math.sin(math.pi * u) * math.sin(math.pi * v)
            grid[p][q] = bm.verts.new(co)
    for p in range(a):
        for q in range(a):
            quad(bm, grid[p][q], grid[p + 1][q], grid[p + 1][q + 1], grid[p][q + 1], mat)


def build_body(mats):
    rings, gap_rings = build_ring_list()
    stations, gap_st = build_station_list()
    M = len(rings)
    K = 2 * M - 2
    loop_ring = list(range(M)) + list(range(M - 2, 0, -1))
    loop_side = [1.0] * M + [-1.0] * (M - 2)

    bm = bmesh.new()
    cre = crease_layer(bm)

    outlines = [SEC.outline(f, rings) for f in stations]
    verts = []
    for i, f in enumerate(stations):
        row = []
        for k in range(K):
            u, z, _nu, _nz = outlines[i][loop_ring[k]]
            row.append(bm.verts.new((loop_side[k] * u, f, z)))
        verts.append(row)

    def normal_at(i, k):
        s = loop_side[k]
        _u, _z, nu, nz = outlines[i][loop_ring[k]]
        nsec = Vector((s * nu, 0.0, nz))
        i0 = max(i - 1, 0)
        i1 = min(i + 1, len(stations) - 1)
        tf = (verts[i1][k].co - verts[i0][k].co)
        tf = tf.normalized() if tf.length > 1e-9 else Vector((0, 1, 0))
        n = nsec - tf * nsec.dot(tf)
        return n.normalized() if n.length > 1e-6 else nsec

    st_index = {round(f, 6): i for i, f in enumerate(stations)}
    ring_index = {round(r, 6): i for i, r in enumerate(rings)}
    pushed = set()
    crease_along_k = []
    crease_along_i = []
    groove_faces = set()

    for f0, j_lo, j_hi in TRANS_GAPS:
        idx = [st_index[round(v, 6)] for v in sorted(gap_st[f0], reverse=True)]
        for i in idx:
            crease_along_k.append((i, j_lo, j_hi))
        for i in idx[1:3]:
            for k in range(K):
                if j_lo - 1e-6 <= rings[loop_ring[k]] <= j_hi + 1e-6:
                    pushed.add((i, k))
        groove_faces.add(("f", idx[1], j_lo, j_hi))

    for j0, f_lo, f_hi in LONG_GAPS:
        vals = sorted(gap_rings[j0])
        ridx = [ring_index[round(v, 6)] for v in vals]
        for r in ridx:
            crease_along_i.append((r, f_lo, f_hi))
        for r in ridx[1:3]:
            for i, f in enumerate(stations):
                if f_lo - 1e-6 <= f <= f_hi + 1e-6:
                    for k in (r, K - r if 0 < r < M - 1 else r):
                        pushed.add((i, k))
        groove_faces.add(("j", ridx[1], f_lo, f_hi))

    for (i, k) in pushed:
        verts[i][k].co -= normal_at(i, k) * GAP_DEPTH

    sh_rings = {}
    for want, amount in ((SHOULDER_J, 1.0), (SHOULDER_J - 0.35, -0.30), (SHOULDER_J + 0.35, 0.55)):
        key = round(want, 6)
        if key in ring_index:
            sh_rings[ring_index[key]] = amount
    for r, amount in sh_rings.items():
        for k in (r, K - r):
            for i, f in enumerate(stations):
                t = (SHOULDER_FADE[1] - abs(f)) / (SHOULDER_FADE[1] - SHOULDER_FADE[0])
                t = min(max(t, 0.0), 1.0)
                t = t * t * (3.0 - 2.0 * t)
                if t > 0.0:
                    verts[i][k].co += normal_at(i, k) * (SHOULDER_RIDGE * amount * t)

    def face_mat(i, k):
        f = (stations[i] + stations[i + 1]) * 0.5
        j = (rings[loop_ring[k]] + rings[loop_ring[(k + 1) % K]]) * 0.5
        for tag, a, b, c in groove_faces:
            if tag == "f" and i == a and b - 1e-6 <= j <= c + 1e-6:
                return TRIM
            if tag == "j" and loop_ring[k] == a and b - 1e-6 <= f <= c + 1e-6:
                return TRIM
        return PAINT

    for i in range(len(stations) - 1):
        for k in range(K):
            k2 = (k + 1) % K
            if verts[i][k] is verts[i][k2]:
                continue
            quad(bm, verts[i][k], verts[i][k2], verts[i + 1][k2], verts[i + 1][k], face_mat(i, k))

    for end, sign, dome in ((0, 1.0, 0.015), (len(stations) - 1, -1.0, 0.012)):
        rim = verts[end]
        prev = rim
        out = outlines[end]
        for step in range(1, ROLL_STEPS + 1):
            ang = (math.pi * 0.5) * step / ROLL_STEPS
            inset = ROLL_R * (1.0 - math.cos(ang))
            dz = ROLL_R * math.sin(ang)
            row = []
            made = {}
            for k in range(K):
                if rim[k] in made:
                    row.append(made[rim[k]])
                    continue
                u, z, nu, nz = out[loop_ring[k]]
                s = loop_side[k]
                base = Vector((s * u, stations[end], z))
                nv = Vector((s * nu, 0.0, nz))
                v = bm.verts.new(base - nv * inset + Vector((0.0, sign * dz, 0.0)))
                made[rim[k]] = v
                row.append(v)
            for k in range(K):
                k2 = (k + 1) % K
                if prev[k] is prev[k2] or row[k] is row[k2]:
                    continue
                if sign > 0:
                    quad(bm, prev[k], prev[k2], row[k2], row[k], PAINT)
                else:
                    quad(bm, prev[k2], prev[k], row[k], row[k2], PAINT)
            prev = row
        loop = []
        for k in range(K):
            if not loop or prev[k] is not loop[-1]:
                loop.append(prev[k])
        while len(loop) > 1 and loop[0] is loop[-1]:
            loop.pop()
        coons_cap(bm, loop, PAINT, dome, sign)

    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    def set_crease(v1, v2, value):
        if v1 is v2:
            return
        e = bm.edges.get((v1, v2))
        if e is not None:
            e[cre] = max(e[cre], value)

    for i, j_lo, j_hi in crease_along_k:
        for k in range(K):
            k2 = (k + 1) % K
            j = (rings[loop_ring[k]] + rings[loop_ring[k2]]) * 0.5
            if j_lo - 1e-6 <= j <= j_hi + 1e-6:
                set_crease(verts[i][k], verts[i][k2], 1.0)
    for r, f_lo, f_hi in crease_along_i:
        ks = [r] + ([K - r] if 0 < r < M - 1 else [])
        for k in ks:
            for i in range(len(stations) - 1):
                fm = (stations[i] + stations[i + 1]) * 0.5
                if f_lo - 1e-6 <= fm <= f_hi + 1e-6:
                    set_crease(verts[i][k], verts[i + 1][k], 1.0)
    if round(SHOULDER_J, 6) in ring_index:
        r = ring_index[round(SHOULDER_J, 6)]
        for k in (r, K - r):
            for i in range(len(stations) - 1):
                set_crease(verts[i][k], verts[i + 1][k], SHOULDER_CREASE)

    ob = new_object("hifi_sedan_body", bm, mats)
    subsurf(ob)
    return ob


# --- cutters ------------------------------------------------------------------------------------

def arch_shell(bm, f_c, radius, x_in, x_out):
    prof = [(f_c + radius, -0.35)]
    n = 26
    for k in range(n + 1):
        a = math.pi * k / n
        prof.append((f_c + radius * math.cos(a), AXLE_Z + radius * math.sin(a)))
    prof.append((f_c - radius, -0.35))
    ring_a = [bm.verts.new((x_in, f, z)) for f, z in prof]
    ring_b = [bm.verts.new((x_out, f, z)) for f, z in prof]
    for k in range(len(prof) - 1):
        quad(bm, ring_a[k], ring_a[k + 1], ring_b[k + 1], ring_b[k], TRIM)
    quad(bm, ring_a[-1], ring_a[0], ring_b[0], ring_b[-1], TRIM)
    bm.faces.new(ring_a).material_index = TRIM
    bm.faces.new(list(reversed(ring_b))).material_index = TRIM


def arch_cutter(mats):
    """All four arches in one operand: a blind pocket that stops inboard of the tyre."""
    bm = bmesh.new()
    for f_c, r in ((FRONT_AXLE, ARCH_R_F), (REAR_AXLE, ARCH_R_R)):
        arch_shell(bm, f_c, r, 0.615, 1.30)
        arch_shell(bm, f_c, r, -1.30, -0.615)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object("cut_arch", bm, mats)


def box_cutter(size, loc, mats, round_r=0.016):
    bm = bmesh.new()
    add_box(bm, size, loc, TRIM)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = new_object("cut_box", bm, mats)
    if round_r > 0.0:
        bevel(ob, round_r, segments=2, angle=30.0)
    for p in ob.data.polygons:
        p.material_index = TRIM
    return ob


# --- surface probing ----------------------------------------------------------------------------

class Surface:
    """Raycasts the finished body so every bolted-on detail sits on the real surface."""

    def __init__(self, ob):
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bm.transform(ob.matrix_world)
        self.bvh = BVHTree.FromBMesh(bm)
        bm.free()

    def hit(self, origin, direction, back=0.30):
        d = Vector(direction).normalized()
        o = Vector(origin) - d * back
        loc, nor, _idx, _dist = self.bvh.ray_cast(o, d, back + 8.0)
        if loc is None:
            return None, None
        return loc, nor

    def on_body(self, f, j, side=1.0):
        p = SEC.point(f, j, side)
        n = SEC.normal(f, j, side)
        loc, nor = self.hit(p, -n)
        if loc is None:
            return p, n
        if nor is not None and nor.dot(n) < 0.0:
            nor = -nor
        return loc, (nor or n)


# --- the glasshouse -----------------------------------------------------------------------------

def dlo_regions():
    """(name, j_outer, centre, f_lo(j), f_hi(j), rows, cols) - see make_hifi_gt.py."""
    return [
        ("windscreen", 14.20, True,
         lambda j: table(A_PILLAR, j) + PILLAR_HALF, lambda j: table(COWL, j), 12, 10),
        ("side", 13.35, False,
         lambda j: table(C_PILLAR, j), lambda j: table(A_PILLAR, j) - PILLAR_HALF, 6, 20),
        ("backlight", 16.85, True,
         lambda j: table(BACKLIGHT_REAR, j), lambda j: table(BACKLIGHT_FRONT, j), 12, 8),
    ]


DLO_SHRINK_F = 0.013
DLO_SHRINK_J = 0.10
GLASS_INSET = 0.014
J_TOP = 22.0
SIDE_GLASS_TOP = 18.45


def dlo_span(flo, fhi, j):
    a, b = flo(j), fhi(j)
    if b < a:
        a = b = (a + b) * 0.5
    return a, b


def dlo_rows(j_outer, centre, rows, shrink_j=0.0):
    out = []
    if centre:
        w = (J_TOP - j_outer) - shrink_j
        for k in range(rows + 1):
            t = -1.0 + 2.0 * k / rows
            out.append((J_TOP - w * abs(t), 1.0 if t >= 0.0 else -1.0))
    else:
        j0 = j_outer + shrink_j
        j1 = SIDE_GLASS_TOP - shrink_j
        for k in range(rows + 1):
            out.append((j0 + (j1 - j0) * k / rows, None))
    return out


def build_glass(bm, surf, j_outer, centre, flo, fhi, rows, cols, side):
    pts = []
    for j, rside in dlo_rows(j_outer, centre, rows):
        sd = side if rside is None else rside * side
        f_a, f_b = dlo_span(flo, fhi, j)
        for b in range(cols + 1):
            f = f_a + (f_b - f_a) * b / cols
            p, n = surf.on_body(f, j, sd)
            pts.append(p - n * GLASS_INSET)
    grid_patch(bm, pts, rows + 1, cols + 1, GLASS)


def grid_solid(bm, top, bot, nr, nc, mat):
    vt = [bm.verts.new(p) for p in top]
    vb = [bm.verts.new(p) for p in bot]
    for i in range(nr - 1):
        for c in range(nc - 1):
            quad(bm, vt[i * nc + c], vt[(i + 1) * nc + c],
                 vt[(i + 1) * nc + c + 1], vt[i * nc + c + 1], mat)
            quad(bm, vb[i * nc + c + 1], vb[(i + 1) * nc + c + 1],
                 vb[(i + 1) * nc + c], vb[i * nc + c], mat)

    def wall(a, b):
        quad(bm, vt[a], vt[b], vb[b], vb[a], mat)

    for c in range(nc - 1):
        wall(c, c + 1)
        wall((nr - 1) * nc + c + 1, (nr - 1) * nc + c)
    for i in range(nr - 1):
        wall(i * nc + nc - 1, (i + 1) * nc + nc - 1)
        wall((i + 1) * nc, i * nc)


def region_solid(bm, surf, j_outer, centre, flo, fhi, rows, cols, side, out, inn, mat):
    """The opening's cutter: the body surface offset out and in, stitched round the edge."""
    ring = dlo_rows(j_outer, centre, rows, DLO_SHRINK_J)
    top, bot = [], []
    for j, rside in ring:
        sd = side if rside is None else rside * side
        f_a, f_b = dlo_span(flo, fhi, j)
        f_a += DLO_SHRINK_F
        f_b -= DLO_SHRINK_F
        if f_b < f_a:
            f_a = f_b = (f_a + f_b) * 0.5
        for c in range(cols + 1):
            f = f_a + (f_b - f_a) * c / cols
            p, n = surf.on_body(f, j, sd)
            top.append(p + n * out)
            bot.append(p - n * inn)
    grid_solid(bm, top, bot, len(ring), cols + 1, mat)


def tidy_cutter(bm):
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=2e-5)
    bmesh.ops.dissolve_degenerate(bm, dist=2e-5, edges=bm.edges)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)


def dlo_cutters(surf, mats):
    out = []
    for name, j_outer, centre, flo, fhi, rows, cols in dlo_regions():
        for side in ([1.0] if centre else [1.0, -1.0]):
            bm = bmesh.new()
            region_solid(bm, surf, j_outer, centre, flo, fhi, rows * 2, cols * 2,
                         side, 0.060, 0.055, TYRE)
            tidy_cutter(bm)
            out.append(new_object("cut_" + name, bm, mats))
    return out


def build_glasshouse(surf, mats):
    bm = bmesh.new()
    for _name, j_outer, centre, flo, fhi, rows, cols in dlo_regions():
        for side in ([1.0] if centre else [1.0, -1.0]):
            build_glass(bm, surf, j_outer, centre, flo, fhi, rows, cols, side)
    # The B-pillar is piano black over the glass line, the way nearly every modern sedan does
    # it, and a thin divider stands in line with the rear door cut where the fixed quarter light
    # starts. Both sit between the glass and the body surface, inside the opening.
    for (fc, hw), mat, inset in ((B_PILLAR, GLOSS, 0.006), (QUARTER_BAR, TRIM, 0.008)):
        for side in (1.0, -1.0):
            pts = []
            rows, cols = 6, 2
            for r in range(rows + 1):
                j = 13.30 + (SIDE_GLASS_TOP + 0.05 - 13.30) * r / rows
                for c in range(cols + 1):
                    f = fc - hw + 2.0 * hw * c / cols
                    p, n = surf.on_body(f, j, side)
                    pts.append(p - n * inset)
            grid_patch(bm, pts, rows + 1, cols + 1, mat)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object("hifi_sedan_glass", bm, mats)


# --- lamps --------------------------------------------------------------------------------------
## (x_inboard, x_outboard, z_centre in, z_centre out, height in, height out, end, material,
## mirrored). Tapered blades, as on the GT: a lamp that narrows toward one end reads as designed.
LAMP_SPECS = [
    (0.330, 0.790, 0.660, 0.684, 0.056, 0.034, 1.0, LIGHT_F, True),
    (0.250, 0.870, 0.905, 0.890, 0.045, 0.125, -1.0, LIGHT_R, True),
    (-0.260, 0.260, 0.905, 0.905, 0.030, 0.030, -1.0, LIGHT_R, False),
]
LAMP_INSET_X = 0.016
LAMP_INSET_Z = 0.010
LAMP_DEPTH = 0.008
FASCIA_LIMIT = 2.0


def fascia_hit(surf, x, z, end, limit=FASCIA_LIMIT):
    """Where the nose (end=+1) or tail (end=-1) fascia is at (x, z), or None if the ray lands
    on the flank instead (make_hifi_gt.py)."""
    loc, _ = surf.hit(Vector((x, end * 3.0, z)), Vector((0, -end, 0)), back=0.0)
    if loc is None or abs(loc.y) < limit or loc.y * end < 0:
        return None
    return loc


def lamp_grid(surf, spec, side, cols, rows, sx=0.0, sz=0.0):
    xi, xo, zi, zo, hi, ho, end, _mat, _mirror = spec
    span = xo - xi
    shr = sx / span if abs(span) > 1e-6 else 0.0
    pts = []
    for r in range(rows + 1):
        v = r / rows
        for c in range(cols + 1):
            t = shr + (1.0 - 2.0 * shr) * (c / cols)
            x = xi + span * t
            zc = zi + (zo - zi) * t
            h = (hi + (ho - hi) * t) * 0.5 - sz
            loc = fascia_hit(surf, side * x, zc - h + 2.0 * h * v, end)
            if loc is None:
                return None
            pts.append(loc)
    return pts


def lamp_instances():
    for spec in LAMP_SPECS:
        for side in ((1.0, -1.0) if spec[8] else (1.0,)):
            yield spec, side


def lamp_cutter(surf, mats):
    bm = bmesh.new()
    for spec, side in lamp_instances():
        end = spec[6]
        cols, rows = 16, 3
        pts = lamp_grid(surf, spec, side, cols, rows, LAMP_INSET_X, LAMP_INSET_Z)
        if pts is None:
            print("  lamp cutter missed the fascia:", spec[:2], side)
            continue
        nv = Vector((0.0, end, 0.0))
        grid_solid(bm, [p + nv * 0.050 for p in pts], [p - nv * 0.050 for p in pts],
                   rows + 1, cols + 1, TRIM)
    tidy_cutter(bm)
    return new_object("cut_lamps", bm, mats)


def build_lamps(surf, mats):
    bm = bmesh.new()
    for spec, side in lamp_instances():
        end = spec[6]
        cols, rows = 10, 2
        pts = lamp_grid(surf, spec, side, cols, rows)
        if pts is None:
            print("  lamp missed the fascia:", spec[:2], side)
            continue
        nv = Vector((0.0, end, 0.0))
        grid_patch(bm, [p - nv * LAMP_DEPTH for p in pts], rows + 1, cols + 1, spec[7])
    # Two projector cups behind each headlamp lens, and a dark bezel strip under them: the lamp
    # needs something in it or the lens reads as a painted shape.
    for side in (1.0, -1.0):
        for x0 in (0.430, 0.540, 0.650):
            x = side * x0
            z0 = 0.660 + (0.684 - 0.660) * (x0 - 0.330) / (0.790 - 0.330)
            loc = fascia_hit(surf, x, z0, 1.0)
            if loc is None:
                continue
            fy = loc.y - LAMP_DEPTH - 0.004
            n_seg = 12
            ring = [bm.verts.new((x + 0.016 * math.cos(a), fy, z0 + 0.012 * math.sin(a)))
                    for a in [2 * math.pi * q / n_seg for q in range(n_seg)]]
            deep = [bm.verts.new((x + 0.011 * math.cos(a), fy - 0.018, z0 + 0.008 * math.sin(a)))
                    for a in [2 * math.pi * q / n_seg for q in range(n_seg)]]
            for q in range(n_seg):
                q2 = (q + 1) % n_seg
                quad(bm, ring[q], ring[q2], deep[q2], deep[q], RIM)
            bm.faces.new(deep).material_index = LIGHT_F
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object("hifi_sedan_lamps", bm, mats)


# --- bolted-on details --------------------------------------------------------------------------

def cap_rim(j, side, end):
    f_end = F_NOSE if end > 0 else F_TAIL
    u, z, nu, nz = SEC.outline(f_end, [j])[0]
    return Vector((side * (u - ROLL_R * nu), f_end + end * ROLL_R, z - ROLL_R * nz))


def build_lip(bm, j0, j1, end, reach, drop, thick, mat=TRIM, n=14):
    """A blade along the bottom rim of the fascia: the chin spoiler and the rear valance."""
    path = [cap_rim(j1 - (j1 - j0) * k / n, -1.0, end) for k in range(n + 1)]
    path += [cap_rim(j0 + (j1 - j0) * k / n, 1.0, end) for k in range(n + 1)]
    prev = None
    for p in path:
        a = bm.verts.new(p)
        b = bm.verts.new(p + Vector((0.0, end * reach, -drop)))
        c = bm.verts.new(p + Vector((0.0, 0.0, -thick)))
        d = bm.verts.new(p + Vector((0.0, end * reach, -drop - thick)))
        if prev is not None:
            pa, pb, pc, pd = prev
            quad(bm, pa, a, b, pb, mat)
            quad(bm, pc, pd, d, c, mat)
            quad(bm, pb, b, d, pd, mat)
            quad(bm, pa, pc, c, a, mat)
        prev = (a, b, c, d)


def build_sill(surf, mats):
    """A black rocker moulding under the doors, as the GT's satin blade: without it the body
    side is one slab from the shoulder to the ground and the car sits high."""
    bm = bmesh.new()
    fs = [1.00 - 2.02 * k / 16 for k in range(17)]
    for side in (1.0, -1.0):
        top, bot, out = [], [], []
        for f in fs:
            p_t, n_t = surf.on_body(f, 4.30, side)
            p_b, n_b = surf.on_body(f, 2.90, side)
            top.append(p_t)
            bot.append(p_b)
            mid = (p_t + p_b) * 0.5
            nn = (n_t + n_b).normalized()
            out.append(mid + nn * 0.012 + Vector((0, 0, -0.006)))
        vt = [bm.verts.new(p) for p in top]
        vo = [bm.verts.new(p) for p in out]
        vb = [bm.verts.new(p) for p in bot]
        for k in range(len(fs) - 1):
            if side > 0:
                quad(bm, vt[k], vt[k + 1], vo[k + 1], vo[k], TRIM)
                quad(bm, vo[k], vo[k + 1], vb[k + 1], vb[k], TRIM)
            else:
                quad(bm, vt[k + 1], vt[k], vo[k], vo[k + 1], TRIM)
                quad(bm, vo[k + 1], vo[k], vb[k], vb[k + 1], TRIM)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object("hifi_sedan_sill", bm, mats)


def build_arch_lips(surf, mats):
    """A rolled lip standing a little proud round each arch - a flush opening reads as a hole
    cut in a shell. Smaller than the GT's: a family car's arch is barely flared."""
    bm = bmesh.new()
    for f_c, radius in ((FRONT_AXLE, ARCH_R_F), (REAR_AXLE, ARCH_R_R)):
        for side in (1.0, -1.0):
            path = []
            n = 22
            for k in range(n + 1):
                a = math.radians(-6.0 + 192.0 * k / n)
                rr = radius + 0.007
                f = f_c + rr * math.cos(a)
                z = AXLE_Z + rr * math.sin(a)
                loc, _nor = surf.hit(Vector((side * 1.6, f, z)), Vector((-side, 0, 0)), back=0.0)
                if loc is None:
                    continue
                path.append(Vector((loc.x, f, z)))
            if len(path) > 3:
                sweep_tube(bm, path,
                           lambda i, n=len(path): 0.0105 * (0.45 + 0.55 * math.sin(math.pi * i / (n - 1))),
                           PAINT, segs=6, caps=True)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object("hifi_sedan_archlips", bm, mats)


def build_handles_and_flap(surf, mats):
    bm = bmesh.new()
    for side in (1.0, -1.0):
        for fc in (0.085, -0.885):
            c, n = surf.on_body(fc, 12.05, side)
            tan_f = (surf.on_body(fc + 0.09, 12.05, side)[0]
                     - surf.on_body(fc - 0.09, 12.05, side)[0]).normalized()
            up = n.cross(tan_f).normalized()
            if up.z < 0:
                up = -up
            hw, hh = 0.095, 0.030
            rim = [c + tan_f * sx * hw + up * sz * hh for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
            vr = [bm.verts.new(p + n * 0.001) for p in rim]
            vd = [bm.verts.new(p - n * 0.020) for p in rim]
            for k in range(4):
                k2 = (k + 1) % 4
                quad(bm, vr[k], vr[k2], vd[k2], vd[k], TRIM)
            bm.faces.new(vd).material_index = TRIM
            # A body-coloured pull bar standing off the dark pocket, the ordinary sedan handle.
            bar = [c + tan_f * t * 0.080 + up * 0.006 + n * 0.006 for t in (-1.0, -0.5, 0.0, 0.5, 1.0)]
            sweep_tube(bm, bar, 0.0115, PAINT, segs=6, caps=True)
        if side > 0:
            # Fuel flap on the right rear quarter: a rounded-square groove, nothing in it.
            fc, fn = surf.on_body(-1.690, 11.55, side)
            tf = (surf.on_body(-1.60, 11.55, side)[0] - surf.on_body(-1.78, 11.55, side)[0]).normalized()
            fu = fn.cross(tf).normalized()
            if fu.z < 0:
                fu = -fu
            n_seg = 16
            outer, inner = [], []
            for k in range(n_seg):
                a = 2 * math.pi * k / n_seg
                ca, sa = math.cos(a), math.sin(a)
                # superellipse: a squircle flap, not a round one
                e = 0.5
                d = tf * (math.copysign(abs(ca) ** e, ca)) + fu * (math.copysign(abs(sa) ** e, sa))
                outer.append(bm.verts.new(fc + d * 0.062 + fn * 0.0015))
                inner.append(bm.verts.new(fc + d * 0.056 - fn * 0.0035))
            for k in range(n_seg):
                k2 = (k + 1) % n_seg
                quad(bm, outer[k], outer[k2], inner[k2], inner[k], TRIM)
            bm.faces.new(inner).material_index = PAINT
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object("hifi_sedan_handles", bm, mats)


def build_mirrors(surf, mats, extra):
    bm = bmesh.new()
    for side in (1.0, -1.0):
        root, n = surf.on_body(0.715, 13.25, side)
        head = Vector((side * 0.995, 0.655, 1.000))
        path = [root + n * 0.004,
                root.lerp(head, 0.5) + Vector((0, 0, 0.012)),
                head]
        sweep_tube(bm, path, lambda i: (0.032, 0.024, 0.020)[i], TRIM, segs=8, caps=True)
        hb = bmesh.new()
        add_box(hb, (0.095, 0.105, 0.115), (side * 1.040, 0.645, 1.012), PAINT)
        bmesh.ops.recalc_face_normals(hb, faces=hb.faces)
        hob = new_object("mirror_head", hb, mats)
        bevel(hob, 0.026, segments=2, angle=40.0)
        subsurf(hob, 1)
        gb = bmesh.new()
        add_box(gb, (0.080, 0.010, 0.095), (side * 1.044, 0.5935, 1.010), GLASS)
        bmesh.ops.recalc_face_normals(gb, faces=gb.faces)
        gob = new_object("mirror_glass", gb, mats)
        for poly in gob.data.polygons:
            poly.material_index = GLASS
        extra.extend([hob, gob])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object("hifi_sedan_mirrorstalk", bm, mats)


def slats(bm, x0, x1, z0, z1, f_front, depth, n, mat=TRIM, thick=0.010, uprights=0):
    """Horizontal slats with depth inside a mouth, plus a few uprights holding them."""
    fc = f_front - depth * 0.5
    for k in range(n):
        z = z0 + (z1 - z0) * (k + 0.5) / n
        add_box(bm, (x1 - x0, depth, thick), ((x0 + x1) * 0.5, fc, z), mat)
    for k in range(uprights):
        x = x0 + (x1 - x0) * (k + 1) / (uprights + 1)
        add_box(bm, (thick, depth * 0.8, z1 - z0), (x, fc - depth * 0.1, (z0 + z1) * 0.5), mat)


## The mouths, as (half width, z bottom, z top, x centre, mirrored): a slim dark slot joining
## the headlamps under the bonnet's leading edge, a wide low grille, and a small vertical
## intake at each corner of the bumper. Pockets POCKET deep behind the fascia, each placed off
## the fascia where it is (a box placed off a guessed station missed the nose entirely).
MOUTHS = [
    (0.305, 0.652, 0.676, 0.0, False),
    (0.560, 0.330, 0.495, 0.0, False),
    (0.050, 0.300, 0.390, 0.650, True),
]
POCKET = 0.045


def mouth_cutters(surf, mats):
    out = []
    for hw, z0, z1, xc, mirror in MOUTHS:
        for side in ((1.0, -1.0) if mirror else (1.0,)):
            loc = fascia_hit(surf, side * xc, (z0 + z1) * 0.5, 1.0)
            if loc is None:
                print("  mouth missed the fascia:", hw, z0, z1, xc)
                continue
            back = loc.y - POCKET
            out.append(box_cutter((hw * 2.0, 0.40, z1 - z0), (side * xc, back + 0.20, (z0 + z1) * 0.5),
                                  mats, 0.008))
    return out


def build_front_end(surf, mats):
    bm = bmesh.new()
    # A fine mesh in the low grille (horizontal bars and uprights, set back in the pocket).
    hw, z0, z1, _xc, _m = MOUTHS[1]
    loc = fascia_hit(surf, 0.0, (z0 + z1) * 0.5, 1.0)
    if loc:
        slats(bm, -hw + 0.01, hw - 0.01, z0 + 0.008, z1 - 0.008, loc.y - 0.012, 0.022, 5, TRIM,
              thick=0.008, uprights=15)
    # Chin spoiler along the bottom rim of the nose.
    build_lip(bm, 0.40, 5.0, 1.0, 0.030, 0.010, 0.016)
    # Badge recess on the nose between the slot and the grille: a recess, and nothing in it.
    loc = fascia_hit(surf, 0.0, 0.590, 1.0)
    if loc:
        n_seg = 16
        outer, inner = [], []
        for k in range(n_seg):
            a = 2 * math.pi * k / n_seg
            d = Vector((0.046 * math.cos(a), 0.0, 0.024 * math.sin(a)))
            outer.append(bm.verts.new(loc + d + Vector((0, 0.001, 0))))
            inner.append(bm.verts.new(loc + d * 0.86 - Vector((0, 0.006, 0))))
        for k in range(n_seg):
            k2 = (k + 1) % n_seg
            quad(bm, outer[k], outer[k2], inner[k2], inner[k], GLOSS)
        bm.faces.new(inner).material_index = GLOSS
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object("hifi_sedan_front", bm, mats)


def build_rear_end(surf, mats):
    bm = bmesh.new()
    build_lip(bm, 0.40, 4.3, -1.0, 0.020, 0.008, 0.016)
    # Two small tail pipes tucked under the valance, visible only from behind.
    for side in (1.0, -1.0):
        cx = side * 0.52
        loc = fascia_hit(surf, cx, 0.290, -1.0, limit=1.9)
        tip = (loc.y if loc else -2.36) + 0.030
        n_seg = 10
        outer, inner, deep = [], [], []
        for k in range(n_seg):
            a = 2 * math.pi * k / n_seg
            ca, sa = math.cos(a), math.sin(a)
            outer.append(bm.verts.new((cx + 0.034 * ca, tip, 0.225 + 0.030 * sa)))
            inner.append(bm.verts.new((cx + 0.028 * ca, tip, 0.225 + 0.024 * sa)))
            deep.append(bm.verts.new((cx + 0.028 * ca, tip + 0.080, 0.225 + 0.024 * sa)))
        for k in range(n_seg):
            k2 = (k + 1) % n_seg
            quad(bm, outer[k], outer[k2], inner[k2], inner[k], RIM)
            quad(bm, inner[k], inner[k2], deep[k2], deep[k], TRIM)
        bm.faces.new(deep).material_index = TRIM
    loc = fascia_hit(surf, 0.0, 0.985, -1.0, limit=1.9)
    if loc:
        n_seg = 16
        outer, inner = [], []
        for k in range(n_seg):
            a = 2 * math.pi * k / n_seg
            d = Vector((0.048 * math.cos(a), 0.0, 0.026 * math.sin(a)))
            outer.append(bm.verts.new(loc + d - Vector((0, 0.001, 0))))
            inner.append(bm.verts.new(loc + d * 0.86 + Vector((0, 0.006, 0))))
        for k in range(n_seg):
            k2 = (k + 1) % n_seg
            quad(bm, outer[k2], outer[k], inner[k], inner[k2], GLOSS)
        bm.faces.new(list(reversed(inner))).material_index = GLOSS
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object("hifi_sedan_rear", bm, mats)


def build_wheels(mats):
    """The far wheel: a plain tyre with a rim face, about 300 triangles. Vehicle draws its
    generated wheel over it up close and shrinks this one into the hub (see the header)."""
    bm = bmesh.new()
    segs = 20
    # Tyre section as (radius, lateral offset from the centre plane, outboard positive).
    hw = TYRE_W * 0.5
    rim_r = TYRE_R * 0.66
    prof = [(rim_r + 0.010, -hw * 0.88), (TYRE_R - 0.030, -hw), (TYRE_R - 0.004, -hw * 0.80),
            (TYRE_R, -hw * 0.30), (TYRE_R, hw * 0.30), (TYRE_R - 0.004, hw * 0.80),
            (TYRE_R - 0.030, hw), (rim_r + 0.010, hw * 0.88)]
    for f_c in (FRONT_AXLE, REAR_AXLE):
        for side in (1.0, -1.0):
            cx = side * WHEEL_X
            rings = []
            for k in range(segs):
                a = 2 * math.pi * k / segs
                ca, sa = math.cos(a), math.sin(a)
                rings.append([bm.verts.new((cx + side * dx, f_c + r * ca, AXLE_Z + r * sa))
                              for r, dx in prof])
            for k in range(segs):
                k2 = (k + 1) % segs
                for p in range(len(prof) - 1):
                    quad(bm, rings[k][p], rings[k2][p], rings[k2][p + 1], rings[k][p + 1], TYRE)
            # Rim face: a dished disc, outer lip to a hub.
            lip = [rings[k][-1] for k in range(segs)]
            face = []
            hub = []
            for k in range(segs):
                a = 2 * math.pi * k / segs
                ca, sa = math.cos(a), math.sin(a)
                face.append(bm.verts.new((cx + side * hw * 0.60, f_c + rim_r * 0.96 * ca, AXLE_Z + rim_r * 0.96 * sa)))
                hub.append(bm.verts.new((cx + side * hw * 0.72, f_c + rim_r * 0.28 * ca, AXLE_Z + rim_r * 0.28 * sa)))
            for k in range(segs):
                k2 = (k + 1) % segs
                quad(bm, lip[k], lip[k2], face[k2], face[k], RIM)
                quad(bm, face[k], face[k2], hub[k2], hub[k], RIM)
            bm.faces.new(hub).material_index = RIM
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object("hifi_sedan_wheels", bm, mats)


# --- assembly ------------------------------------------------------------------------------------

def build():
    reset_scene()
    mats = make_materials()
    body = build_body(mats)

    boolean(body, arch_cutter(mats))
    # The front mouths, the black lower valance band across the tail and the number-plate
    # recess between the tail lamps, each a pocket placed off the fascia where it really is.
    surf0 = Surface(body)
    for cutter in mouth_cutters(surf0, mats):
        boolean(body, cutter)
    for w, h, z, r in ((1.380, 0.125, 0.320, 0.012), (0.540, 0.125, 0.745, 0.010)):
        loc = fascia_hit(surf0, 0.0, z, -1.0, limit=1.9)
        if loc is not None:
            boolean(body, box_cutter((w, 0.40, h), (0.0, loc.y + 0.030 - 0.20, z), mats, r))
    bevel(body, 0.004, segments=1, angle=42.0)

    surf = Surface(body)
    for cutter in dlo_cutters(surf, mats) + [lamp_cutter(surf, mats)]:
        boolean(body, cutter)
    full = decimate(body, SHELL_TRIS)
    print("shell: %d triangles subdivided -> %d decimated" % (full, tri_count(body)))

    extra = []
    parts = [body,
             build_glasshouse(surf, mats),
             build_lamps(surf, mats),
             build_sill(surf, mats),
             build_arch_lips(surf, mats),
             build_handles_and_flap(surf, mats),
             build_mirrors(surf, mats, extra),
             build_front_end(surf, mats),
             build_rear_end(surf, mats),
             build_wheels(mats)]
    for p in parts[1:] + extra:
        shade(p)
    parts.extend(extra)
    ob = join(parts)
    ob.name = "hifi_sedan"
    ob.data.name = ob.name
    return ob


def fit_length(ob):
    """Scale to exactly TARGET_LENGTH about the ground centre, so Vehicle's own scale is 1 and the
    printed wheel pose is exact."""
    bb = [Vector(c) for c in ob.bound_box]
    ymin = min(v.y for v in bb)
    ymax = max(v.y for v in bb)
    s = TARGET_LENGTH / (ymax - ymin)
    me = ob.data
    for v in me.vertices:
        v.co = Vector((v.co.x * s, v.co.y * s, v.co.z * s))
    me.update()
    return s


def fold_slots(ob):
    """Write each face's slot into the vertex attributes and leave ONE material (see header)."""
    me = ob.data
    col = me.color_attributes.new("Col", 'FLOAT_COLOR', 'CORNER')
    uv = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        _name, c, rough, metal, glow = SLOTS[poly.material_index]
        paint = 1.0 if poly.material_index == PAINT else 0.0
        mv = metal + (2.0 if glow else 0.0)
        for li in poly.loop_indices:
            col.data[li].color = (c[0], c[1], c[2], paint)
            # The glTF exporter writes V as 1 - v, and Godot reads it back as written.
            uv.data[li].uv = (rough, 1.0 - mv)
    me.color_attributes.active_color = col
    for poly in me.polygons:
        poly.material_index = 0
    while len(me.materials) > 1:
        me.materials.pop(index=len(me.materials) - 1)
    m = me.materials[0]
    m.name = "paint"


def export(ob, path):
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', use_selection=True,
        export_apply=True, export_materials='EXPORT', export_yup=True,
        export_normals=True, export_texcoords=True, export_tangents=False,
        export_vertex_color='ACTIVE', export_all_vertex_colors=False,
        export_skins=False, export_animations=False, export_cameras=False,
        export_lights=False,
    )


def main():
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    ob = build()
    s = fit_length(ob)
    me = ob.data
    counts = {}
    for p in me.polygons:
        counts[SLOTS[p.material_index][0]] = counts.get(SLOTS[p.material_index][0], 0) + 1
    fold_slots(ob)
    tris = tri_count(ob)
    xs = [v.co.x for v in me.vertices]
    ys = [v.co.y for v in me.vertices]
    zs = [v.co.z for v in me.vertices]
    export(ob, OUT_PATH)
    print("tris=%d  L=%.3f W=%.3f H=%.3f  (scale %.4f)" % (
        tris, max(ys) - min(ys), max(xs) - min(xs), max(zs) - min(zs), s))
    body_w = 2.0 * max(abs(v.co.x) for v in me.vertices if v.co.z < 0.95 and abs(v.co.y) < 2.2)
    print("body width without mirrors: %.3f   ground %.4f" % (body_w, min(zs)))
    print("faces per slot: %s" % counts)
    # Vehicle body space: glTF (x, z, -y), centred on the box in x/z, bottom on `ride`.
    ride = -0.24
    cz = -(max(ys) + min(ys)) * 0.5
    front = -FRONT_AXLE * s - cz
    rear = -REAR_AXLE * s - cz
    print('WHEEL_POSE SEDAN: {"x": %.3f, "front": %.3f, "rear": %.3f, "y": %.3f, "r": %.3f, "w": %.3f}'
          % (WHEEL_X * s, front, rear, AXLE_Z * s - min(zs) + ride, TYRE_R * s, TYRE_W * s))
    fmax = max(ys)
    print("police DOOR_BAND (fraction of the length from the nose): Vector2(%.3f, %.3f)"
          % ((fmax - 0.985 * s) / (max(ys) - min(ys)), (fmax + 1.050 * s) / (max(ys) - min(ys))))
    print("wrote %s" % OUT_PATH)
    sys.stdout.flush()


if __name__ == "__main__":
    main()
