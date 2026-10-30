#!/usr/bin/env python3
"""High-fidelity front-engine grand tourer body, built in Blender's Python API (bpy as a module,
no Blender binary needed):

    python3 tools/make_hifi_gt.py

Writes assets/models/hifi_gt_coupe.glb.

WHY THIS FILE EXISTS
--------------------
The previous generated cars were low-poly cages with a small bevel, about 32k triangles. The
owner's verdict was "they look like N64 cars ... everything overall still looks blocky", while
liking the paint. That is a GEOMETRY problem: at that density a curved body panel is a fan of
flat facets, and no clearcoat shader hides a facet. So this body is built the way a real car
model is built:

    1. a COARSE QUAD CONTROL CAGE with edge flow that follows the form (a loft: cross sections
       splined along the length, every ring a quad loop, no triangles anywhere in the body),
    2. a SUBDIVISION SURFACE at level 2 - this is the step that turns facets into a continuous
       surface and is the whole difference between an N64 car and a modern one,
    3. sharpness from EDGE CREASES and tight HOLDING LOOPS, never from leaving edges unsubdivided,
    4. booleans only for the wheel arches and the intake mouths, after the subdivision,
    5. a small bevel last, so every hard edge catches a highlight.

Budget is deliberately large: ~180k triangles. Exotics are about 12% of traffic and are hero
objects the player drives; a modern GPU does not notice a few hundred thousand static triangles.
Coming in under 100k is the mistake this pass exists to correct.

WHAT MAKES IT READ AS A REAL CAR RATHER THAN A TOY
--------------------------------------------------
  * SHUTLINES. The bonnet, doors and boot are cut in as real 7 mm x 5 mm recesses with holding
    loops and creases either side, so the body reads as separate panels. Their absence is most
    of why the old cars read as bars of soap.
  * RECESSED GLASS. The windscreen, side glass and backlight sit 14 mm inside the body in a
    rubber-sealed frame, not flush with it.
  * Wheel arch LIPS that stand proud of the body side, a sill that steps in under the doors,
    door handles, mirrors on stalks, a fuel flap, a badging recess with NO badge.
  * Grille and intake MESHES: real egg-crate fins with depth inside the mouths, not a black face.
  * Exhausts as real tubes with visible inner walls.

ORIGINAL DESIGN. This is the "Calvara Corsara" - a CLASS of car (front-engine GT), not a copy of
one. No manufacturer's badge, grille shape or light signature. The owner asked for Ferraris and
Bugattis; those are trademarked and this ships commercially, so we build the class.

THE STANCE, AND WHY EVERY NUMBER IS WHERE IT IS
-----------------------------------------------
    length 4.70   width 1.97   height 1.30   wheelbase 2.67
    front overhang 0.93   rear overhang 1.10   wheel diameter 0.70

  * DASH TO AXLE is the whole signature of the class. The front axle is at f = +1.42 and the
    base of the windscreen at f = +0.74, so 0.68 m of bonnet sits between the front wheel centre
    and the scuttle. That one relationship is what makes it look expensive.
  * Width 1.97 against height 1.30: a car half again wider than it is tall reads as exotic from
    any angle.
  * The arches are the widest points of the body (half width 0.985 at both axles, tucking to
    0.935 at the waist). The tyre's outer face lands at 0.985, so the wheel fills the arch.
  * A hard shoulder line (ring 10, held by loops at 9.65 and 10.35 and creased at 0.5) runs the
    full length, and the greenhouse is ~0.3 m narrower per side than the body. That separation
    is what stops it reading as a rounded blob.

GEOMETRY CONVENTIONS
--------------------
Authored X = lateral, Y = longitudinal with the NOSE AT +Y (called `f` throughout), Z = up,
ground at Z = 0. The glTF exporter's Y-up conversion turns that into Godot's X right, Y up, nose
at -Z, which is the engine's forward.

The section is parameterised by a ring coordinate `j` running 0 (underbody centreline) to 22
(roof centreline) through nine named anchors; every shutline, glass opening and crease is
addressed in (f, j), which is why they land exactly on the cage's own loops.

Vehicle._add_body_model() scales the model so its longest horizontal axis equals the body type's
`length`, drops the bottom of its AABB on `model_bottom_y`, and applies the paint shader PER
SURFACE, only to the slot named "paint". The numbers the game needs are printed by the run:

    arch centre        front f = +1.420   rear f = -1.250      (wheelbase 2.670)
    arch centre height z = 0.350          arch radius 0.405 / 0.415 (front / rear)
    wheel centre x     +- 0.835           (track 1.670, tyre outer face 0.985)
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree

OUT_DIR = "assets/models"
PREFIX = "hifi_gt_"

# --- material slots ------------------------------------------------------------------------
# Exactly these six names, in this order. The game tints ONLY "paint"; nothing that is not
# bodywork may end up in that slot. "tyre" is the rubber weather seal round every piece of glass.
SLOTS = [
    ("paint",       (0.78, 0.78, 0.80), 0.85, 0.22),
    ("glass",       (0.022, 0.028, 0.038), 0.25, 0.045),
    ("trim",        (0.032, 0.032, 0.036), 0.10, 0.52),
    ("tyre",        (0.028, 0.028, 0.030), 0.0, 0.88),
    ("light_front", (0.34, 0.37, 0.43), 0.20, 0.07),
    ("light_rear",  (0.62, 0.045, 0.050), 0.15, 0.08),
]
PAINT, GLASS, TRIM, TYRE, LIGHT_F, LIGHT_R = range(6)

SUBSURF_LEVELS = 2

# --- the section: nine anchors, addressed by ring coordinate j -------------------------------
#   j = 0   underbody centreline        j = 13  beltline (top of the body side)
#   j = 2   underbody outer edge        j = 16  mid glass / tumblehome
#   j = 4   sill (rocker) outer         j = 19  roof rail
#   j = 7   lower side / arch bulge     j = 22  roof centreline
#   j = 10  shoulder line (widest)
ANCHOR_J = [0.0, 2.0, 4.0, 7.0, 10.0, 13.0, 16.0, 19.0, 22.0]

# Keyframed section scalars along the length. Order:
#   zb   underbody height at the centreline
#   ub   underbody half width
#   us,zs   sill outer point
#   uh,zh   lower side / arch bulge
#   uw,zw   shoulder line (the widest point of the body)
#   ubl,zbl beltline
#   um,zm   mid glass
#   ur,zr   roof rail
#   zt   roof centreline height
KEYS = [
    # f        zb     ub     us     zs     uh     zh     uw     zw    ubl    zbl     um     zm     ur     zr     zt
    (2.295, 0.100, 0.360, 0.520, 0.145, 0.700, 0.250, 0.790, 0.360, 0.772, 0.452, 0.690, 0.532, 0.440, 0.596, 0.620),
    (2.100, 0.095, 0.420, 0.600, 0.140, 0.810, 0.278, 0.885, 0.424, 0.858, 0.545, 0.756, 0.638, 0.464, 0.702, 0.730),
    (1.850, 0.100, 0.480, 0.665, 0.150, 0.895, 0.310, 0.950, 0.500, 0.925, 0.640, 0.810, 0.740, 0.490, 0.810, 0.845),
    (1.600, 0.105, 0.520, 0.700, 0.158, 0.960, 0.340, 0.978, 0.560, 0.950, 0.700, 0.835, 0.790, 0.500, 0.860, 0.895),
    (1.420, 0.110, 0.540, 0.715, 0.163, 0.982, 0.360, 0.985, 0.600, 0.958, 0.730, 0.845, 0.820, 0.505, 0.890, 0.925),
    (1.150, 0.115, 0.550, 0.700, 0.168, 0.962, 0.375, 0.972, 0.640, 0.948, 0.760, 0.845, 0.850, 0.505, 0.920, 0.955),
    (0.860, 0.115, 0.550, 0.672, 0.172, 0.920, 0.385, 0.955, 0.690, 0.935, 0.800, 0.840, 0.885, 0.505, 0.945, 0.978),
    (0.720, 0.115, 0.550, 0.662, 0.174, 0.910, 0.390, 0.948, 0.715, 0.930, 0.830, 0.850, 0.905, 0.560, 0.960, 0.990),
    (0.450, 0.115, 0.550, 0.650, 0.176, 0.900, 0.398, 0.942, 0.760, 0.925, 0.900, 0.855, 1.010, 0.620, 1.120, 1.140),
    (0.100, 0.115, 0.550, 0.645, 0.178, 0.895, 0.402, 0.938, 0.790, 0.920, 0.945, 0.870, 1.090, 0.650, 1.235, 1.265),
    (-0.050, 0.115, 0.550, 0.643, 0.178, 0.893, 0.403, 0.936, 0.798, 0.918, 0.955, 0.872, 1.110, 0.655, 1.272, 1.300),
    (-0.300, 0.115, 0.545, 0.640, 0.178, 0.892, 0.405, 0.934, 0.802, 0.915, 0.960, 0.868, 1.115, 0.648, 1.272, 1.298),
    (-0.700, 0.115, 0.540, 0.635, 0.177, 0.890, 0.406, 0.932, 0.805, 0.908, 0.958, 0.850, 1.098, 0.620, 1.255, 1.288),
    (-1.000, 0.115, 0.530, 0.632, 0.176, 0.930, 0.405, 0.955, 0.802, 0.900, 0.950, 0.808, 1.050, 0.545, 1.195, 1.230),
    (-1.250, 0.115, 0.520, 0.638, 0.175, 0.982, 0.400, 0.985, 0.795, 0.945, 0.935, 0.775, 0.995, 0.470, 1.115, 1.150),
    (-1.550, 0.115, 0.500, 0.628, 0.172, 0.935, 0.392, 0.975, 0.788, 0.935, 0.918, 0.725, 0.935, 0.408, 1.010, 1.042),
    (-1.850, 0.110, 0.470, 0.608, 0.166, 0.878, 0.380, 0.945, 0.775, 0.905, 0.886, 0.690, 0.906, 0.368, 0.945, 0.968),
    (-2.100, 0.105, 0.440, 0.578, 0.158, 0.826, 0.362, 0.880, 0.750, 0.845, 0.852, 0.660, 0.882, 0.350, 0.913, 0.938),
    (-2.295, 0.100, 0.400, 0.535, 0.150, 0.760, 0.345, 0.815, 0.720, 0.778, 0.828, 0.608, 0.862, 0.326, 0.892, 0.908),
]

F_NOSE = 2.295
F_TAIL = -2.295
ROLL_R = 0.055        # radius of the fillet that rolls the nose and tail rims into the fascias
ROLL_STEPS = 2

FRONT_AXLE = 1.420
REAR_AXLE = -1.250
AXLE_Z = 0.350
ARCH_R_F = 0.405
ARCH_R_R = 0.415
WHEEL_X = 0.835

# --- shutlines ---------------------------------------------------------------------------
# A panel gap is a 7 mm wide, 5 mm deep recess held by loops 6.5 mm out from its centre and
# creased hard on all four loops, so subdivision cannot round it away. Ring offsets are in
# ring units; the section runs about 0.09 m per ring unit, hence 0.039 / 0.072.
GAP_HALF_F = 0.0035
GAP_HOLD_F = 0.0065
GAP_HALF_J = 0.039
GAP_HOLD_J = 0.072
GAP_DEPTH = 0.005

# (f0, j_lo, j_hi): a gap running across the car at station f0, over that ring span.
TRANS_GAPS = [
    (2.120, 14.5, 22.0),    # bonnet front edge
    (0.740, 14.5, 22.0),    # bonnet rear edge, at the base of the windscreen
    (0.560, 4.60, 13.05),   # door front cut
    (-0.860, 4.60, 13.05),  # door rear cut
    (-1.585, 14.5, 22.0),   # boot lid front edge
    (-2.180, 14.5, 22.0),   # boot lid rear edge
]
# (j0, f_lo, f_hi): a gap running along the car at ring j0, over that station span.
LONG_GAPS = [
    (14.5, 0.740, 2.120),    # bonnet side, where the wing top turns over
    (14.5, -2.185, -1.585),  # boot lid side
    (13.05, -0.860, 0.560),  # door top (the beltline)
    (4.60, -0.860, 0.560),   # door bottom, at the sill step
]

SHOULDER_J = 10.0
SHOULDER_CREASE = 1.0
## How far the shoulder loop stands proud of the flank. A crease alone is invisible on a body
## this smooth: what reads as a character line is a real change of plane, so the loop is pushed
## out and its two holding loops come part of the way with it.
SHOULDER_RIDGE = 0.009
SHOULDER_FADE = (1.95, 2.25)

# --- the glasshouse ------------------------------------------------------------------------
# Each daylight opening is defined as: for a ring j, the glass runs between f_lo(j) and f_hi(j).
# The A-pillar and C-pillar are the gaps between neighbouring openings, so they come out as real
# structure instead of being drawn on.
A_PILLAR = [(13.30, 0.520), (14.60, 0.455), (15.60, 0.390), (16.60, 0.300),
            (17.60, 0.195), (18.60, 0.065), (19.60, -0.045), (20.60, -0.085), (22.00, -0.095)]
COWL = [(14.00, 0.530), (16.00, 0.630), (19.00, 0.700), (22.00, 0.720)]
C_PILLAR = [(13.30, -0.810), (15.00, -0.760), (16.60, -0.700), (18.50, -0.620)]
BACKLIGHT_FRONT = [(16.80, -1.280), (18.50, -1.080), (20.00, -0.880), (22.00, -0.745)]
BACKLIGHT_REAR = [(16.80, -1.410), (19.00, -1.490), (22.00, -1.535)]
PILLAR_HALF = 0.055

# --- the cage's own resolution --------------------------------------------------------------
BASE_RINGS = [0.0, 1.8, 2.7, 3.6, 4.35, 5.1, 6.8, 8.6, 9.3, 9.65, 10.0, 10.35, 10.9,
              11.9, 12.95, 13.7, 14.6, 15.6, 16.6, 17.6, 18.6, 19.6, 20.6, 21.4, 22.0]
BASE_STATIONS = [2.295, 2.18, 2.10, 1.95, 1.84, 1.70, 1.55, 1.42, 1.28, 1.12, 0.95, 0.82,
                 0.68, 0.62, 0.44, 0.26, 0.06, -0.16, -0.38, -0.60, -0.78, -0.96, -1.10,
                 -1.25, -1.40, -1.66, -1.78, -1.90, -2.02, -2.12, -2.295]


# --- small numeric helpers --------------------------------------------------------------------

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
    """Fritsch-Carlson monotone cubic. A plain spline overshoots between keyframes, which on a
    car body shows up as a bulge in the middle of a panel that is not in any of the numbers."""

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
            if d[i - 1] * d[i] <= 0.0:
                m[i] = 0.0
            else:
                m[i] = (d[i - 1] + d[i]) * 0.5
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
    """The body's cross section as a function of the station f, evaluated at any ring j.

    Nine anchors are splined along the length with monotone cubics, then a Hermite runs through
    those anchors round the section. The end tangents are pinned horizontal, so the mirrored
    half meets the centreline with a continuous normal - otherwise there is a crease down the
    middle of the roof and along the floor that no amount of smoothing removes."""

    def __init__(self, keys):
        fs = [k[0] for k in keys]
        self.curves = [Mono(fs, [k[1 + i] for k in keys]) for i in range(15)]

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
        h0 = T[1] - T[0]
        d0 = math.hypot(P[1][0] - P[0][0], P[1][1] - P[0][1]) / h0
        m[0] = (d0, 0.0)
        hl = T[n - 1] - T[n - 2]
        dl = math.hypot(P[n - 1][0] - P[n - 2][0], P[n - 1][1] - P[n - 2][1]) / hl
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
        u, z, nu, nz = self.outline(f, [j])[0]
        return Vector((side * u, f, z))

    def normal(self, f, j, side=1.0):
        """Outward 3D normal, including the change of the section along the length."""
        d = 0.01
        a = self.point(f - d, j, side)
        b = self.point(f + d, j, side)
        tf = (b - a).normalized()
        u0, z0, nu, nz = self.outline(f, [j])[0]
        nsec = Vector((side * nu, 0.0, nz))
        # Remove any component along the length tangent, then renormalise.
        n = nsec - tf * nsec.dot(tf)
        return n.normalized() if n.length > 1e-6 else nsec


SEC = Section(KEYS)


# --- blender plumbing --------------------------------------------------------------------------

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
    """Blender moved edge creases to a generic float attribute; support both spellings."""
    try:
        lay = bm.edges.layers.crease
        return lay.verify() if hasattr(lay, "verify") else lay
    except (AttributeError, TypeError):
        pass
    lay = bm.edges.layers.float.get("crease_edge")
    if lay is None:
        lay = bm.edges.layers.float.new("crease_edge")
    return lay


# --- generic mesh builders ---------------------------------------------------------------------

def quad(bm, a, b, c, d, mat):
    try:
        f = bm.faces.new((a, b, c, d))
    except ValueError:
        return None
    f.material_index = mat
    return f


def grid_patch(bm, pts, nu, nv, mat, verts=None):
    """pts[i*nv + j] laid out as an (nu x nv) grid of Vectors; returns the BMVert grid."""
    if verts is None:
        verts = [bm.verts.new(p) for p in pts]
    for i in range(nu - 1):
        for j in range(nv - 1):
            quad(bm, verts[i * nv + j], verts[(i + 1) * nv + j],
                 verts[(i + 1) * nv + j + 1], verts[i * nv + j + 1], mat)
    return verts


def frames(path):
    """Parallel-transport frames along a polyline, so a swept tube does not spin."""
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
        t, up, side = fr[i]
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


def rounded_box_mesh(size, loc, mat, radius=0.02):
    """A box as its own object with a bevel applied - used for cutters that need soft corners."""
    bm = bmesh.new()
    add_box(bm, size, loc, mat)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


# --- the control cage --------------------------------------------------------------------------

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
    # The nose and tail caps are Coons patches over the section loop, which needs the loop split
    # into four equal arcs: that only works when the ring count is odd.
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
        st = [f for f in st if abs(f - f0) > GAP_HOLD_F * 1.8]
        st.extend(vals)
    st = sorted(set(round(f, 6) for f in st), reverse=True)
    return st, gap_st


def coons_cap(bm, loop, mat, dome, axis_sign):
    """Close a section loop with a quad grid instead of an n-gon. An n-gon cap subdivides into a
    very high-valence pole and ripples across the whole fascia, which is exactly the panel the
    eye lands on first."""
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


def in_windscreen(f, j):
    return j >= 13.5 and table(A_PILLAR, j) + PILLAR_HALF <= f <= table(COWL, j)


def in_side_glass(f, j):
    return 13.45 <= j <= 18.5 and table(C_PILLAR, j) <= f <= table(A_PILLAR, j) - PILLAR_HALF


def in_backlight(f, j):
    return j >= 16.9 and table(BACKLIGHT_REAR, j) <= f <= table(BACKLIGHT_FRONT, j)


def build_body(mats):
    rings, gap_rings = build_ring_list()
    stations, gap_st = build_station_list()
    M = len(rings)
    K = 2 * M - 2
    # loop index -> (ring index, side)
    loop_ring = list(range(M)) + list(range(M - 2, 0, -1))
    loop_side = [1.0] * M + [-1.0] * (M - 2)

    bm = bmesh.new()
    cre = crease_layer(bm)

    outlines = [SEC.outline(f, rings) for f in stations]
    verts = []
    for i, f in enumerate(stations):
        row = []
        for k in range(K):
            r = loop_ring[k]
            s = loop_side[k]
            u, z, _nu, _nz = outlines[i][r]
            row.append(bm.verts.new((s * u, f, z)))
        verts.append(row)

    def normal_at(i, k):
        r = loop_ring[k]
        s = loop_side[k]
        _u, _z, nu, nz = outlines[i][r]
        nsec = Vector((s * nu, 0.0, nz))
        i0 = max(i - 1, 0)
        i1 = min(i + 1, len(stations) - 1)
        tf = (verts[i1][k].co - verts[i0][k].co)
        tf = tf.normalized() if tf.length > 1e-9 else Vector((0, 1, 0))
        n = nsec - tf * nsec.dot(tf)
        return n.normalized() if n.length > 1e-6 else nsec

    # --- shutline grooves: push the two inner loops in, crease all four ---------------------
    st_index = {round(f, 6): i for i, f in enumerate(stations)}
    ring_index = {round(r, 6): i for i, r in enumerate(rings)}
    pushed = set()
    crease_along_k = []   # (station index, ring lo, ring hi)
    crease_along_i = []   # (ring index, f lo, f hi)
    groove_faces = set()  # (station index pair) or (ring index pair) marked dark

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
    for want, amount in ((SHOULDER_J, 1.0), (SHOULDER_J - 0.35, 0.38), (SHOULDER_J + 0.35, 0.30)):
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

    # --- faces -------------------------------------------------------------------------------
    def face_mat(i, k):
        f = (stations[i] + stations[i + 1]) * 0.5
        j = (rings[loop_ring[k]] + rings[loop_ring[(k + 1) % K]]) * 0.5
        for tag, a, b, c in groove_faces:
            if tag == "f" and i == a and b - 1e-6 <= j <= c + 1e-6:
                return TRIM
            if tag == "j" and loop_ring[k] == a and b - 1e-6 <= f <= c + 1e-6:
                return TRIM
        # NOTE: the body under a daylight opening stays PAINT. Classifying it dark by face
        # centre stair-steps along the diagonal pillar lines, and the steps stick out past the
        # glass as a chequerboard - far worse than the sliver it was meant to hide.
        return PAINT

    for i in range(len(stations) - 1):
        for k in range(K):
            k2 = (k + 1) % K
            if verts[i][k] is verts[i][k2]:
                continue
            quad(bm, verts[i][k], verts[i][k2], verts[i + 1][k2], verts[i + 1][k], face_mat(i, k))

    # --- nose and tail: a fillet roll, then a Coons cap ---------------------------------------
    for end, sign, dome in ((0, 1.0, 0.030), (len(stations) - 1, -1.0, 0.020)):
        rim = verts[end]
        prev = rim
        out = outlines[end]
        for step in range(1, ROLL_STEPS + 1):
            # Measured from the RIM every time, never from the previous ring: accumulating the
            # offsets rolls the nose twice as far as ROLL_R says and pushes the fascia out past
            # the length the stance is built on.
            ang = (math.pi * 0.5) * step / ROLL_STEPS
            inset = ROLL_R * (1.0 - math.cos(ang))
            dz = ROLL_R * math.sin(ang)
            row = []
            made = {}
            for k in range(K):
                r = loop_ring[k]
                s = loop_side[k]
                if rim[k] in made:
                    row.append(made[rim[k]])
                    continue
                u, z, nu, nz = out[r]
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

    # --- creases -------------------------------------------------------------------------------
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
    # The shoulder line: a light crease between two holding loops, not a knife edge.
    if round(SHOULDER_J, 6) in ring_index:
        r = ring_index[round(SHOULDER_J, 6)]
        for k in (r, K - r):
            for i in range(len(stations) - 1):
                set_crease(verts[i][k], verts[i + 1][k], SHOULDER_CREASE)

    ob = new_object("hifi_gt_body", bm, mats)
    subsurf(ob)
    return ob


# --- cutters -----------------------------------------------------------------------------------

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
    fa = bm.faces.new(ring_a)
    fa.material_index = TRIM
    fb = bm.faces.new(list(reversed(ring_b)))
    fb.material_index = TRIM


def arch_cutter(mats):
    """All four arches in one operand. An EXACT boolean is the slowest step in the build and it
    copes perfectly well with several disjoint shells in one mesh."""
    bm = bmesh.new()
    arch_shell(bm, FRONT_AXLE, ARCH_R_F, 0.600, 1.30)
    arch_shell(bm, FRONT_AXLE, ARCH_R_F, -1.30, -0.600)
    arch_shell(bm, REAR_AXLE, ARCH_R_R, 0.580, 1.30)
    arch_shell(bm, REAR_AXLE, ARCH_R_R, -1.30, -0.580)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object("cut_arch", bm, mats)


def box_cutter(size, loc, mats, round_r=0.018):
    bm = rounded_box_mesh(size, loc, TRIM)
    ob = new_object("cut_box", bm, mats)
    for p in ob.data.polygons:
        p.material_index = TRIM
    if round_r > 0.0:
        bevel(ob, round_r, segments=3, angle=30.0)
        for p in ob.data.polygons:
            p.material_index = TRIM
    return ob


# --- surface probing ---------------------------------------------------------------------------

class Surface:
    """Raycasts the finished body so every bolted-on detail sits exactly on the real surface
    rather than on the control cage, which subdivision has already pulled inwards."""

    def __init__(self, ob):
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bm.transform(ob.matrix_world)
        self.bvh = BVHTree.FromBMesh(bm)
        bm.free()

    def hit(self, origin, direction, back=0.30):
        # The ray length is a fixed generous span, NOT a multiple of `back`: with back = 0 the
        # old form asked the BVH for a zero-length ray, so every lamp, arch lip and exhaust
        # placed this way silently fell back to a guessed position.
        d = Vector(direction).normalized()
        o = Vector(origin) - d * back
        loc, nor, idx, dist = self.bvh.ray_cast(o, d, back + 8.0)
        if loc is None:
            return None, None
        return loc, nor

    def on_body(self, f, j, side=1.0):
        """The point and normal of the finished surface at the cage's (f, j)."""
        p = SEC.point(f, j, side)
        n = SEC.normal(f, j, side)
        loc, nor = self.hit(p, -n)
        if loc is None:
            return p, n
        if nor is not None and nor.dot(n) < 0.0:
            nor = -nor
        return loc, (nor or n)


# --- details -------------------------------------------------------------------------------------

## Each daylight opening. The body is a closed solid, so glass laid on the inside of it is
## simply buried: the openings have to be cut. The cutter's faces carry the "tyre" slot, so the
## boolean hands back a rubber-black recess wall for free and the glass sits 14 mm down inside
## it, in a frame, the way it does on a real car.
##   (name, j_outer, centre, f_lo(j), f_hi(j), rows, cols)
## `centre` regions reach the centreline: they are built as ONE patch spanning both sides,
## parameterised across the car, because two mirrored halves that stop at j = 21.9 leave a
## painted stripe down the middle of the windscreen.
def dlo_regions():
    return [
        ("windscreen", 14.20, True,
         lambda j: table(A_PILLAR, j) + PILLAR_HALF, lambda j: table(COWL, j), 20, 18),
        ("side", 13.35, False,
         lambda j: table(C_PILLAR, j), lambda j: table(A_PILLAR, j) - PILLAR_HALF, 12, 18),
        ("backlight", 16.85, True,
         lambda j: table(BACKLIGHT_REAR, j), lambda j: table(BACKLIGHT_FRONT, j), 18, 18),
    ]


DLO_SHRINK_F = 0.013   # the hole is this much smaller than the glass, so the glass tucks under
DLO_SHRINK_J = 0.10    # the rim on every side and no seam can open up
GLASS_INSET = 0.014
J_TOP = 22.0
## The roof rail: where the side glass stops. The only non-centre opening, so this is its
## inner bound rather than another column in the region table.
SIDE_GLASS_TOP = 18.45


def dlo_span(flo, fhi, j):
    a, b = flo(j), fhi(j)
    if b < a:
        a = b = (a + b) * 0.5
    return a, b


def dlo_rows(j_outer, centre, rows, shrink_j=0.0):
    """The rows of an opening as (j, side). A centre region runs from the far side, over the
    centreline, to the near side in one sweep."""
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
    """A closed solid between two (nr x nc) grids: the two surfaces plus a wall round the edge.
    No fan caps anywhere, which is the point - see region_solid."""
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
    """The opening's cutter, built as the body surface offset out and in and stitched round the
    edge - NOT as a loop swept along its own normals. A swept loop is manifold but it
    self-intersects wherever the surface curves, and two of them that reach into the cabin
    overlap each other; either one makes the EXACT solver read the whole body as inside the
    cutter and a difference then deletes the car."""
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


def panel_solid(bm, surf, f0, f1, j0, j1, side, out, inn, mat, nf=12, nj=6):
    """A rectangular patch of the body in (f, j), offset out and in - the flank equivalent of
    region_solid, used for the wing gill."""
    top, bot = [], []
    for a in range(nj + 1):
        j = j0 + (j1 - j0) * a / nj
        for c in range(nf + 1):
            f = f0 + (f1 - f0) * c / nf
            p, n = surf.on_body(f, j, side)
            top.append(p + n * out)
            bot.append(p - n * inn)
    grid_solid(bm, top, bot, nj + 1, nf + 1, mat)


GILL = (0.805, 0.980, 7.45, 9.55)


def gill_cutter(surf, mats):
    bm = bmesh.new()
    f0, f1, j0, j1 = GILL
    for side in (1.0, -1.0):
        panel_solid(bm, surf, f0, f1, j0, j1, side, 0.050, 0.052, TRIM)
    tidy_cutter(bm)
    return new_object("cut_gill", bm, mats)


def build_gill_fins(surf, mats):
    bm = bmesh.new()
    f0, f1, j0, j1 = GILL
    for side in (1.0, -1.0):
        for k in range(3):
            j = j0 + (j1 - j0) * (k + 0.5) / 3.0
            prev = None
            for c in range(11):
                f = f0 + (f1 - f0) * c / 10.0
                p, n = surf.on_body(f, j, side)
                tj = (surf.on_body(f, j + 0.2, side)[0] - surf.on_body(f, j - 0.2, side)[0])
                tj = tj.normalized() if tj.length > 1e-6 else Vector((0, 0, 1))
                ring = [bm.verts.new(p - n * 0.006 + tj * 0.006),
                        bm.verts.new(p - n * 0.042 + tj * 0.006),
                        bm.verts.new(p - n * 0.042 - tj * 0.006),
                        bm.verts.new(p - n * 0.006 - tj * 0.006)]
                if prev is not None:
                    for q in range(4):
                        quad(bm, prev[q], prev[(q + 1) % 4], ring[(q + 1) % 4], ring[q], TRIM)
                prev = ring
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object("hifi_gt_gill", bm, mats)


def tidy_cutter(bm):
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=2e-5)
    bmesh.ops.dissolve_degenerate(bm, dist=2e-5, edges=bm.edges)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)


def dlo_cutters(surf, mats):
    """One cutter object per opening. Separate booleans cost a little time and mean a single bad
    shell cannot take the whole body with it."""
    out = []
    for name, j_outer, centre, flo, fhi, rows, cols in dlo_regions():
        sides = [1.0] if centre else [1.0, -1.0]
        for side in sides:
            bm = bmesh.new()
            region_solid(bm, surf, j_outer, centre, flo, fhi,
                         rows, cols, side, 0.060, 0.055, TYRE)
            tidy_cutter(bm)
            out.append(new_object("cut_" + name, bm, mats))
    return out


## Lamps. Same problem as the glass: a lens laid on the inside of the fascia cannot be seen, so
## the fascia gets a recess and the lens sits down inside it. Each lamp is a tapered blade:
## (x_inboard, x_outboard, z_centre in, z_centre out, height in, height out, end, material,
## mirrored). A blade that narrows outboard is what makes a light signature look drawn rather
## than stamped out with a rectangle.
LAMP_SPECS = [
    (0.195, 0.660, 0.512, 0.498, 0.086, 0.052, 1.0, LIGHT_F, True),
    (0.145, 0.705, 0.700, 0.692, 0.090, 0.056, -1.0, LIGHT_R, True),
    (-0.145, 0.145, 0.698, 0.698, 0.036, 0.036, -1.0, LIGHT_R, False),
]
LAMP_INSET_X = 0.018
LAMP_INSET_Z = 0.011
LAMP_DEPTH = 0.016


def lamp_grid(surf, spec, side, cols, rows, sx=0.0, sz=0.0):
    """The lamp's outline sampled onto the fascia. Returns None if any sample misses, so a lamp
    that has drifted off the panel is dropped rather than drawn across the wing."""
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
            continue
        nv = Vector((0.0, end, 0.0))
        grid_solid(bm, [p + nv * 0.050 for p in pts], [p - nv * 0.058 for p in pts],
                   rows + 1, cols + 1, TRIM)
    tidy_cutter(bm)
    return new_object("cut_lamps", bm, mats)


def detail_cutters(surf, mats):
    return dlo_cutters(surf, mats) + [lamp_cutter(surf, mats), gill_cutter(surf, mats)]


def build_glasshouse(surf, mats):
    bm = bmesh.new()
    for _name, j_outer, centre, flo, fhi, rows, cols in dlo_regions():
        if centre:
            build_glass(bm, surf, j_outer, centre, flo, fhi, rows, cols, 1.0)
        else:
            for side in (1.0, -1.0):
                build_glass(bm, surf, j_outer, centre, flo, fhi, rows, cols, side)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object("hifi_gt_glass", bm, mats)


def build_lamps(surf, mats):
    bm = bmesh.new()
    for spec, side in lamp_instances():
        end = spec[6]
        mat = spec[7]
        cols, rows = 20, 3
        pts = lamp_grid(surf, spec, side, cols, rows)
        if pts is None:
            continue
        nv = Vector((0.0, end, 0.0))
        grid_patch(bm, [p - nv * LAMP_DEPTH for p in pts], rows + 1, cols + 1, mat)
    # Projectors behind the front lens: real tubes, so the lamp has something in it.
    for side in (1.0, -1.0):
        for k in range(3):
            x = side * (0.265 + 0.150 * k)
            loc = fascia_hit(surf, x, 0.507, 1.0)
            if loc is None:
                continue
            fy = loc.y - 0.036
            ring = [bm.verts.new((x + 0.026 * math.cos(a), fy, 0.507 + 0.026 * math.sin(a)))
                    for a in [2 * math.pi * q / 14 for q in range(14)]]
            deep = [bm.verts.new((x + 0.019 * math.cos(a), fy - 0.026, 0.507 + 0.019 * math.sin(a)))
                    for a in [2 * math.pi * q / 14 for q in range(14)]]
            for q in range(14):
                q2 = (q + 1) % 14
                quad(bm, ring[q], ring[q2], deep[q2], deep[q], TRIM)
            bm.faces.new(deep).material_index = LIGHT_F
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object("hifi_gt_lamps", bm, mats)


def cap_rim(j, side, end):
    """A point on the rim of the nose or tail fascia, where the fillet roll ends and the cap
    begins. Anything that has to sit on that edge is placed from this rather than from a
    raycast: at a rim a ray can land on either surface and the part jumps."""
    f_end = F_NOSE if end > 0 else F_TAIL
    u, z, nu, nz = SEC.outline(f_end, [j])[0]
    return Vector((side * (u - ROLL_R * nu), f_end + end * ROLL_R, z - ROLL_R * nz))


def build_lip(bm, j0, j1, end, reach, drop, thick, mat=TRIM, n=20):
    """The splitter at the nose and the valance at the tail: a blade along the bottom rim of the
    fascia. Built off cap_rim so it follows the fascia's own outline instead of being a plank."""
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
    """The rocker steps in under the doors and wears a satin blade. Without it the body side is
    one uninterrupted slab from the shoulder to the ground and the car sits high."""
    bm = bmesh.new()
    fs = [1.15 - 2.30 * k / 28 for k in range(29)]
    for side in (1.0, -1.0):
        top, bot, out = [], [], []
        for f in fs:
            p_t, n_t = surf.on_body(f, 5.60, side)
            p_b, n_b = surf.on_body(f, 3.60, side)
            top.append(p_t)
            bot.append(p_b)
            mid = (p_t + p_b) * 0.5
            nn = (n_t + n_b).normalized()
            out.append(mid + nn * 0.018 + Vector((0, 0, -0.010)))
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
    return new_object("hifi_gt_sill", bm, mats)


def build_arch_lips(surf, mats):
    """A lip standing proud of the body side round each arch. Cars have them; a flush opening
    reads as a hole cut in a shell."""
    bm = bmesh.new()
    for f_c, radius in ((FRONT_AXLE, ARCH_R_F), (REAR_AXLE, ARCH_R_R)):
        for side in (1.0, -1.0):
            path = []
            n = 36
            for k in range(n + 1):
                a = math.radians(-7.0 + 194.0 * k / n)
                rr = radius + 0.009
                f = f_c + rr * math.cos(a)
                z = AXLE_Z + rr * math.sin(a)
                loc, nor = surf.hit(Vector((side * 1.6, f, z)), Vector((-side, 0, 0)), back=0.0)
                if loc is None:
                    continue
                path.append(Vector((loc.x, f, z)))
            if len(path) > 3:
                sweep_tube(bm, path,
                           lambda i, n=len(path): 0.0145 * (0.5 + 0.5 * math.sin(math.pi * i / (n - 1))),
                           PAINT, segs=8, caps=True)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object("hifi_gt_archlips", bm, mats)


def build_handles_and_flap(surf, mats):
    bm = bmesh.new()
    for side in (1.0, -1.0):
        # Door handle: a dark recess plate with a pull bar standing off it.
        c, n = surf.on_body(-0.115, 12.00, side)
        tan_f = (surf.on_body(-0.02, 12.00, side)[0] - surf.on_body(-0.21, 12.00, side)[0]).normalized()
        up = n.cross(tan_f).normalized()
        if up.z < 0:
            up = -up
        hw, hh = 0.100, 0.033
        rim = [c + tan_f * sx * hw + up * sz * hh for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        deep = [p - n * 0.022 for p in rim]
        vr = [bm.verts.new(p + n * 0.001) for p in rim]
        vd = [bm.verts.new(p) for p in deep]
        for k in range(4):
            k2 = (k + 1) % 4
            quad(bm, vr[k], vr[k2], vd[k2], vd[k], TRIM)
        f = bm.faces.new(vd)
        f.material_index = TRIM
        bar = [c + tan_f * t * 0.085 + up * 0.008 + n * 0.005 for t in (-1.0, -0.5, 0.0, 0.5, 1.0)]
        sweep_tube(bm, bar, 0.0125, TRIM, segs=8, caps=True)
        # Fuel flap on the rear quarter: a circular groove, no badge, no cap.
        if side > 0:
            fc, fn = surf.on_body(-1.020, 11.60, side)
            tf = (surf.on_body(-0.92, 11.60, side)[0] - surf.on_body(-1.12, 11.60, side)[0]).normalized()
            fu = fn.cross(tf).normalized()
            if fu.z < 0:
                fu = -fu
            n_seg = 22
            outer, inner = [], []
            for k in range(n_seg):
                a = 2 * math.pi * k / n_seg
                d = tf * math.cos(a) + fu * math.sin(a)
                outer.append(bm.verts.new(fc + d * 0.078 + fn * 0.0015))
                inner.append(bm.verts.new(fc + d * 0.070 - fn * 0.0035))
            for k in range(n_seg):
                k2 = (k + 1) % n_seg
                quad(bm, outer[k], outer[k2], inner[k2], inner[k], TRIM)
            cap = bm.faces.new(inner)
            cap.material_index = PAINT
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object("hifi_gt_handles", bm, mats)


def build_mirrors(surf, mats, extra):
    bm = bmesh.new()
    for side in (1.0, -1.0):
        root, n = surf.on_body(0.460, 12.60, side)
        head = Vector((side * 0.995, 0.380, 0.985))
        path = [root + n * 0.004,
                root.lerp(head, 0.45) + Vector((0, 0, 0.016)),
                root.lerp(head, 0.80) + Vector((0, 0, 0.026)),
                head]
        sweep_tube(bm, path, lambda i: (0.036, 0.029, 0.024, 0.021)[i], TRIM, segs=10, caps=True)
        # Mirror head: a bevelled cage under one level of subdivision. Two levels on a plain
        # box converge on a sphere, and a red ball on a stick is not a wing mirror.
        hb = bmesh.new()
        add_box(hb, (0.072, 0.200, 0.108), (side * 1.040, 0.372, 0.998), PAINT)
        bmesh.ops.recalc_face_normals(hb, faces=hb.faces)
        hob = new_object("mirror_head", hb, mats)
        bevel(hob, 0.024, segments=2, angle=40.0)
        subsurf(hob, 1)
        # The glass faces BACKWARDS, on the rear face of the head, not inboard.
        gb = bmesh.new()
        add_box(gb, (0.062, 0.014, 0.094), (side * 1.040, 0.2755, 0.998), GLASS)
        bmesh.ops.recalc_face_normals(gb, faces=gb.faces)
        gob = new_object("mirror_glass", gb, mats)
        for poly in gob.data.polygons:
            poly.material_index = GLASS
        extra.extend([hob, gob])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object("hifi_gt_mirrorstalk", bm, mats)


def eggcrate(bm, x0, x1, z0, z1, f_front, f_back, mat=TRIM, nv=None, nh=3, thick=0.008):
    """Real fins with depth inside an intake mouth. A black-painted flat face is the single
    cheapest-looking thing a car model can have."""
    if nv is None:
        nv = max(4, int((x1 - x0) / 0.058))
    depth = abs(f_front - f_back)
    fc = (f_front + f_back) * 0.5
    for k in range(nv + 1):
        x = x0 + (x1 - x0) * k / nv
        add_box(bm, (thick, depth * 0.80, z1 - z0), (x, fc, (z0 + z1) * 0.5), mat)
    for k in range(nh + 1):
        z = z0 + (z1 - z0) * k / nh
        add_box(bm, (x1 - x0, depth * 0.55, thick), ((x0 + x1) * 0.5, fc, z), mat)


def fascia_hit(surf, x, z, end, limit=1.9):
    """Where the nose (end=+1) or tail (end=-1) fascia is at (x, z). Guards against a ray that
    misses the fascia and lands halfway down the flank, which is what drags a headlight into
    the middle of the wing."""
    d = Vector((0, -end, 0))
    loc, _ = surf.hit(Vector((x, end * 3.0, z)), d, back=0.0)
    if loc is None or abs(loc.y) < limit or loc.y * end < 0:
        return None
    return loc


def build_front_end(surf, mats):
    bm = bmesh.new()
    # Egg-crate behind each mouth. The mouths themselves are boolean pockets in the fascia.
    eggcrate(bm, -0.520, 0.520, 0.185, 0.280, 2.315, 2.125, TRIM, nh=3)
    eggcrate(bm, -0.385, 0.385, 0.360, 0.420, 2.335, 2.185, TRIM, nh=1)
    # Splitter along the bottom rim of the nose fascia.
    build_lip(bm, 0.35, 5.20, 1.0, 0.052, 0.012, 0.020)
    # Badging recess on the nose: a recess, and nothing in it.
    loc = fascia_hit(surf, 0.0, 0.482, 1.0)
    if loc:
        n_seg = 20
        outer, inner = [], []
        for k in range(n_seg):
            a = 2 * math.pi * k / n_seg
            d = Vector((0.054 * math.cos(a), 0.0, 0.031 * math.sin(a)))
            outer.append(bm.verts.new(loc + d))
            inner.append(bm.verts.new(loc + d * 0.86 - Vector((0, 0.007, 0))))
        for k in range(n_seg):
            k2 = (k + 1) % n_seg
            quad(bm, outer[k], outer[k2], inner[k2], inner[k], TRIM)
        cap = bm.faces.new(inner)
        cap.material_index = TRIM
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object("hifi_gt_front", bm, mats)


def build_rear_end(surf, mats):
    bm = bmesh.new()
    # Diffuser fins inside the rear pocket, and the valance blade along the bottom rim.
    for k in range(9):
        x = -0.46 + 0.92 * k / 8
        add_box(bm, (0.011, 0.150, 0.115), (x, -2.185, 0.225), TRIM)
    add_box(bm, (0.98, 0.022, 0.120), (0.0, -2.130, 0.225), TRIM)
    build_lip(bm, 0.35, 4.60, -1.0, 0.040, 0.010, 0.018)
    # Exhausts: real tubes with an inner wall and a dark plug at the back.
    for side in (1.0, -1.0):
        for dx in (0.0, 0.112):
            cx = side * (0.280 + dx)
            loc = fascia_hit(surf, cx, 0.375, -1.0)
            tip = (loc.y if loc else -2.34) - 0.014
            n_seg = 16
            outer, inner, deep, back, skirt = [], [], [], [], []
            for k in range(n_seg):
                a = 2 * math.pi * k / n_seg
                ca, sa = math.cos(a), math.sin(a)
                outer.append(bm.verts.new((cx + 0.049 * ca, tip, 0.375 + 0.049 * sa)))
                inner.append(bm.verts.new((cx + 0.039 * ca, tip, 0.375 + 0.039 * sa)))
                deep.append(bm.verts.new((cx + 0.039 * ca, tip + 0.100, 0.375 + 0.039 * sa)))
                back.append(bm.verts.new((cx + 0.028 * ca, tip + 0.100, 0.375 + 0.028 * sa)))
                skirt.append(bm.verts.new((cx + 0.058 * ca, tip + 0.055, 0.375 + 0.058 * sa)))
            for k in range(n_seg):
                k2 = (k + 1) % n_seg
                quad(bm, outer[k], outer[k2], inner[k2], inner[k], TRIM)
                quad(bm, inner[k], inner[k2], deep[k2], deep[k], TRIM)
                quad(bm, deep[k], deep[k2], back[k2], back[k], TRIM)
                quad(bm, skirt[k], skirt[k2], outer[k2], outer[k], TRIM)
            plug = bm.faces.new(back)
            plug.material_index = TRIM
    # Badging recess on the tail.
    loc = fascia_hit(surf, 0.0, 0.790, -1.0)
    if loc:
        n_seg = 20
        outer, inner = [], []
        for k in range(n_seg):
            a = 2 * math.pi * k / n_seg
            d = Vector((0.052 * math.cos(a), 0.0, 0.030 * math.sin(a)))
            outer.append(bm.verts.new(loc + d))
            inner.append(bm.verts.new(loc + d * 0.86 + Vector((0, 0.007, 0))))
        for k in range(n_seg):
            k2 = (k + 1) % n_seg
            quad(bm, outer[k2], outer[k], inner[k], inner[k2], TRIM)
        cap = bm.faces.new(list(reversed(inner)))
        cap.material_index = TRIM
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object("hifi_gt_rear", bm, mats)


# --- assembly --------------------------------------------------------------------------------

def build():
    reset_scene()
    mats = make_materials()
    body = build_body(mats)

    # Wheel arches: a blind pocket, not a tunnel - the cutter stops inboard of the wheel.
    boolean(body, arch_cutter(mats))
    # Intake mouths and the rear diffuser pocket.
    boolean(body, box_cutter((1.08, 0.36, 0.125), (0.0, 2.26, 0.2325), mats))
    boolean(body, box_cutter((0.82, 0.30, 0.085), (0.0, 2.30, 0.390), mats))
    boolean(body, box_cutter((1.14, 0.30, 0.150), (0.0, -2.255, 0.240), mats))
    bevel(body, 0.0045, segments=2, angle=42.0)

    # Probe the body while it is still SOLID: every bolted-on part is placed by raycast, and
    # once the daylight openings are cut those rays fly straight through the greenhouse.
    surf = Surface(body)
    for cutter in detail_cutters(surf, mats):
        boolean(body, cutter)
    extra = []
    parts = [body]
    parts.append(build_glasshouse(surf, mats))
    parts.append(build_lamps(surf, mats))
    parts.append(build_gill_fins(surf, mats))
    parts.append(build_sill(surf, mats))
    parts.append(build_arch_lips(surf, mats))
    parts.append(build_handles_and_flap(surf, mats))
    parts.append(build_mirrors(surf, mats, extra))
    parts.extend(extra)
    parts.append(build_front_end(surf, mats))
    parts.append(build_rear_end(surf, mats))

    ob = join(parts)
    ob.name = PREFIX + "coupe"
    ob.data.name = ob.name
    shade(ob)
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


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    ob = build()
    me = ob.data
    me.calc_loop_triangles()
    tris = len(me.loop_triangles)
    bb = [Vector(c) for c in ob.bound_box]
    mn = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
    mx = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
    counts = {}
    for p in me.polygons:
        counts[me.materials[p.material_index].name] = counts.get(me.materials[p.material_index].name, 0) + 1
    path = export(ob, "coupe")
    print("tris=%d  L=%.3f W=%.3f H=%.3f  x %.3f..%.3f  y %.3f..%.3f  z %.3f..%.3f"
          % (tris, mx.y - mn.y, mx.x - mn.x, mx.z - mn.z, mn.x, mx.x, mn.y, mx.y, mn.z, mx.z))
    print("faces per slot: %s" % counts)
    body_w = 2.0 * max(abs(v.co.x) for v in me.vertices if v.co.z < 0.85)
    print("body width without mirrors: %.3f" % body_w)
    print("subdiv levels: %d   arches: front f=%.3f r=%.3f  rear f=%.3f r=%.3f  axle z=%.3f"
          % (SUBSURF_LEVELS, FRONT_AXLE, ARCH_R_F, REAR_AXLE, ARCH_R_R, AXLE_Z))
    print("wrote %s" % path)


if __name__ == "__main__":
    main()
