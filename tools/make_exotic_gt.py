#!/usr/bin/env python3
"""Front-engine grand tourer bodies, built procedurally in Blender's Python API (bpy as a module,
no Blender binary needed):

    python3 tools/make_exotic_gt.py                 # both
    python3 tools/make_exotic_gt.py coupe           # just one

Writes assets/models/exo_gt_coupe.glb and assets/models/exo_gt_convertible.glb.

ORIGINAL DESIGNS. These are the "Calvara GT" and "Calvara GT Aperta": a class of car, not a copy
of one. No badge, no real model name, no grille or lamp signature lifted from a particular
manufacturer. What makes them read as exotic is proportion and stance, which is what this file
is really about.

WHAT THE STANCE IS AND WHY EVERY NUMBER IS WHERE IT IS
------------------------------------------------------
    length 4.70   width 1.97   height 1.30   wheelbase 2.67
    front overhang 0.93   rear overhang 1.10   wheel diameter 0.71   track 1.68

  * DASH TO AXLE. The front axle is at f = +1.420 and the base of the windscreen at f = +0.720,
    so 0.70 m of bonnet sits between the front wheel centre and the scuttle. That one
    relationship is the entire signature of a front-engine GT and is what makes it look
    expensive. Everything else on the car can be mediocre and it will still read right.
  * THE GROUND IS THE CONTACT PATCH. z = 0 is where the tyres touch the road, the hubs are at
    z = 0.355 = the tyre radius, and NOTHING on the car is allowed below z = 0. Vehicle's
    _add_body_model() plants the bottom of the model's AABB at the body type's ride height, so
    if the splitter were the lowest vertex the splitter would sit on the tarmac and the wheels
    would hover. The first pass did exactly that.
  * THE ARCH IS BIGGER THAN THE WHEEL, AND IT HAS A LIP. Arch opening radius 0.430 front /
    0.438 rear against a 0.355 tyre: 7.5 to 8.3 cm of daylight over the tyre crown, carried
    right round from -22 to 202 degrees, not just over the top. The opening edge then wears a
    flare (`arch_lip`) that stands 28 mm proud of the flank and is the widest part of the car.
    An arch cut at the tyre radius is not an arch, it is a hole, and the side view then has no
    curve in its lower silhouette at all - the sill runs dead straight past a black disc.
  * THE WHEELS ARE REAL. Vehicle hides its own wheel meshes when a body model is present
    (`_has_model`), so the model has to carry them: a full round tyre with a bulged sidewall, a
    rim with five turbine spokes cut through to a visible hub, a rim flange standing proud of
    the bead, and a brake disc and caliper behind the spokes. A flat dark disc at any colour
    still reads as a flat dark disc.
  * The arch lips are the widest points of the body; the flank tucks in 5 cm at the waist
    between them. The tyre's outer face lands just inside the lip crest, so the wheel fills the
    arch out to the edge. Small wheels rattling around inside big arches is the single loudest
    amateur tell.
  * Windscreen rake: base (0.720, 0.945) to header (0.045, 1.262) is 25.4 degrees from
    horizontal.
  * A hard shoulder line runs unbroken from over the front arch to the tail lamp (`crease`,
    22 mm proud and bevelled at 4.5 mm so it catches a real highlight), with a second lower line
    along the sill so the flank is not one featureless slab.

GEOMETRY CONVENTIONS
--------------------
Authored X = lateral, Y = longitudinal with the NOSE AT +Y, Z = up, ground at Z = 0. The glTF
exporter's Y-up conversion turns that into Godot's X right, Y up, nose at -Z, which is the
engine's forward.

Vehicle._add_body_model() scales the model so its longest horizontal axis equals the body type's
`length` and drops the bottom of the AABB on the type's ride height, centred on X and Z. So only
the model's PROPORTIONS matter, never its absolute size. The numbers the game needs, printed by
the build:

    arch centre        front f = +1.420   rear f = -1.250      (wheelbase 2.670)
    hub height         z = 0.355          tyre radius 0.355    (contact patch on z = 0)
    hub x              +- 0.840           (track 1.680)

The shell is a loft: a handful of 2D cross-sections given as seven scalars each, splined along
the length with a monotone cubic and skinned. That is how real body surfacing works, and it is
what gives a continuous flank and a greenhouse that tapers. Wheel arches and intakes are cut
afterwards with exact booleans; everything is bevelled, because a perfectly sharp edge catches
no light and the bevel highlight is what makes it read as sheet metal.

The export is patched after the fact (`patch_glb`) rather than trusting Blender's material
settings to survive the exporter: every material is forced doubleSided:false (Godot imports
doubleSided as cull_mode=DISABLED, which doubles the fragment cost of a prop that exists 150
times in traffic), the lamps get an emissiveFactor, and the roadster's screen gets alphaMode
BLEND so you can see through the one piece of glass on an open car.
"""

import json
import math
import os
import struct
import sys

import bpy  # noqa: E402  (bpy must be imported before bmesh/mathutils)
import bmesh
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO, "assets", "models")
PREFIX = "exo_gt_"

# Slot order is a contract with the game: the tinted paint is the slot named "paint" and nothing
# else may be merged into it. name, base colour, metallic, roughness. No textures anywhere - the
# game does paint in shaders/car_paint.gdshader.
#
# `trim` is deliberately an anthracite METAL, not the near-black matte it used to be: it is the
# only slot the rims can use, and a 0.046 matte rim is indistinguishable from a 0.028 matte tyre,
# so every wheel read as one featureless dark disc. Anthracite metal is also right for the sills,
# splitter, diffuser, vent liners and mirror arms that share the slot.
SLOTS = [
    ("paint",       (0.80, 0.81, 0.83), 0.85, 0.28),
    ("glass",       (0.040, 0.050, 0.062), 0.00, 0.05),
    ("trim",        (0.168, 0.172, 0.182), 0.38, 0.34),
    ("tyre",        (0.028, 0.028, 0.030), 0.00, 0.88),
    ("light_front", (0.50, 0.53, 0.60), 0.00, 0.09),
    ("light_rear",  (0.54, 0.035, 0.038), 0.00, 0.13),
]
PAINT, GLASS, TRIM, TYRE, LIGHT_F, LIGHT_R = range(6)

# The half cross-section is a spline through eleven control points, sampled with a fixed number
# of steps per span so the ring index `h` means the same thing at every station: that is what
# lets regions (glass, shut lines, creases, lamps) be selected by parameter instead of guesswork.
SEG_STEPS = [2, 3, 3, 4, 3, 3, 4, 3, 3, 4]
H_UNDER, H_SILL, H_BELT, H_RAIL, H_TOP = 0, 5, 15, 25, 32
HALF_N = 1 + sum(SEG_STEPS)          # 33 points, index 0..32
RING_N = HALF_N * 2 - 2              # 64 points round the closed loop

WHEEL_R = 0.355                      # tyre radius: contact patch on z = 0, hub at z = 0.355
HUB_U = 0.355
HUB_X = 0.840                        # track 1.680


# --- maths -----------------------------------------------------------------------------------

def catmull(p0, p1, p2, p3, t):
    t2 = t * t
    return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
                  + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t2 * t)


def spline_points(pts, steps):
    """Catmull-Rom through 2D control points, `steps[i]` samples across span i, endpoints kept."""
    ext = [pts[0]] + list(pts) + [pts[-1]]
    out = [pts[0]]
    for i in range(len(pts) - 1):
        p0, p1, p2, p3 = ext[i], ext[i + 1], ext[i + 2], ext[i + 3]
        n = steps[i]
        for s in range(1, n + 1):
            t = s / n
            out.append((catmull(p0[0], p1[0], p2[0], p3[0], t),
                        catmull(p0[1], p1[1], p2[1], p3[1], t)))
    return out


def half_outline(p):
    """The eleven control points of one half section, floor centre first, roof centre last.

    p = (u0 floor height, wb floor half width, u1 belt height, w1 max half width,
         u2 top height, w2 top half width, crown roof dome at the centreline)

    The shoulder inset has to be a fraction of the taper actually available: a fixed 2 % is fine
    where the greenhouse is much narrower than the body, but where w2 approaches w1 it lands
    INSIDE the tumblehome point, the outline doubles back, the shell self-intersects and the
    booleans then delete the whole car. The convertible's flat tonneau deck is exactly that case.

    The flank control at 0.58 of the way up used to be 0.968 of the full width, which rounded the
    whole side. It is 0.988 now: the side is close to dead flat from the sill to the shoulder and
    then breaks hard, which is what gives the car a shoulder rather than a bulge.
    """
    u0, wb, u1, w1, u2, w2, crown = p
    du = u1 - u0
    dt = u2 - u1
    shoulder = min(w1 * 0.018, max(0.0, w1 - w2) * 0.26 + 0.002)
    w_sh = w1 - shoulder
    w_tumble = w2 + (w_sh - w2) * 0.56
    ctrl = [
        (0.0, u0),                                        # floor centre (flat underbody)
        (wb * 0.58, u0 + 0.003),                          # floor
        (wb, u0 + 0.030),                                 # outer edge of the floor pan
        (wb + (w1 - wb) * 0.64, u0 + du * 0.20),          # rocker, tucked hard under
        (w1 * 0.988, u0 + du * 0.58),                     # flank, deliberately flat
        (w1, u1),                                         # shoulder / belt line
        (w_sh, u1 + dt * 0.10),                           # shoulder radius, tight
        (w_tumble, u1 + dt * 0.48),                       # tumblehome
        (w2, u2 - dt * 0.085),                            # roof rail
        (w2 * 0.86, u2),                                  # roof edge
        (0.0, u2 + crown),                                # roof centre
    ]
    return spline_points(ctrl, SEG_STEPS)


class Mono:
    """Fritsch-Carlson monotone cubic. A uniform spline through the very uneven station spacing
    used here (15 mm apart at the nose, half a metre across the cabin) OVERSHOOTS, the sections
    then cross each other, the shell self-intersects and every boolean wipes the car."""

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
        h = self.h[lo]
        t = (x - xs[lo]) / h
        t2, t3 = t * t, t * t * t
        return ((2 * t3 - 3 * t2 + 1) * self.ys[lo] + (t3 - 2 * t2 + t) * h * self.m[lo]
                + (-2 * t3 + 3 * t2) * self.ys[hi] + (t3 - t2) * h * self.m[hi])


class Loft:
    """Analytic skin: the seven section scalars interpolated along the length, sampled at (f, h)."""

    def __init__(self, keys):
        self.keys = keys                       # nose first, tail last
        self.fs = [k[0] for k in keys]
        xs = [k[0] for k in reversed(keys)]
        self.curves = [Mono(xs, [k[1 + i] for k in reversed(keys)]) for i in range(7)]
        self._cache = {}
        self._half = {}

    def params(self, f):
        key = round(f, 5)
        p = self._cache.get(key)
        if p is None:
            p = tuple(c(f) for c in self.curves)
            self._cache[key] = p
        return p

    def half(self, f):
        key = round(f, 5)
        h = self._half.get(key)
        if h is None:
            h = half_outline(self.params(key))
            self._half[key] = h
        return h

    def ring(self, f):
        """One closed cross-section: 64 points, index 0 at the floor centre going up the +X side."""
        h = self.half(f)
        pts = [Vector((x, f, u)) for (x, u) in h]
        pts += [Vector((-x, f, u)) for (x, u) in reversed(h[1:-1])]
        return pts

    def point(self, f, h, side=1.0):
        half = self.half(round(f, 5))
        h = max(0.0, min(float(HALF_N - 1) - 1e-6, h))
        i = int(h)
        t = h - i
        x = half[i][0] + (half[i + 1][0] - half[i][0]) * t
        u = half[i][1] + (half[i + 1][1] - half[i][1]) * t
        return Vector((x * side, f, u))

    def normal(self, f, h, side=1.0):
        d = 0.02
        df = self.point(f + d, h, side) - self.point(f - d, h, side)
        dh = self.point(f, h + 0.25, side) - self.point(f, h - 0.25, side)
        n = dh.cross(-df)
        if n.length < 1e-9:
            return Vector((side, 0.0, 0.0))
        n.normalize()
        # Mirroring X flips the handedness of the cross product, so on the port side the raw
        # normal points INTO the body: every crease, lamp and mirror would sink out of sight.
        return -n if side < 0.0 else n

    def off(self, f, h, side, d):
        return self.point(f, h, side) + self.normal(f, h, side) * d

    # -- inverses. The arch lip, the lamp bars and the mirror mounts are all authored in real
    # world terms ("this height above the road", "this far out from the centreline") and have to
    # be put back onto the skin, which is parameterised by the ring index h instead.

    def h_at_u(self, f, u, hmax=H_BELT + 8):
        """Ring index whose height is `u`, searching the monotone stretch from floor to shoulder."""
        half = self.half(round(f, 5))
        if u <= half[0][1]:
            return 0.0
        for i in range(min(hmax, HALF_N - 1)):
            a, b = half[i][1], half[i + 1][1]
            if b >= u >= a and b > a:
                return i + (u - a) / (b - a)
        return float(hmax)

    def x_at_u(self, f, u):
        return abs(self.point(f, self.h_at_u(f, u)).x)

    def f_at_xu(self, u, x, f_end, f_in):
        """Where on the nose (or tail) cap the surface is `x` off the centreline at height `u`.

        `f_end` is the extreme station (the tip), `f_in` one well inside it. The half width grows
        monotonically going inboard, so a bisection lands on the wrap of the nose - which is what
        makes a lamp bar follow the bumper instead of floating in front of it.
        """
        if self.x_at_u(f_end, u) >= x:
            return f_end
        lo, hi = f_in, f_end
        for _ in range(26):
            mid = 0.5 * (lo + hi)
            if self.x_at_u(mid, u) > x:
                lo = mid
            else:
                hi = mid
        return 0.5 * (lo + hi)


# --- blender plumbing --------------------------------------------------------------------------

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_materials():
    mats = []
    for name, col, metal, rough in SLOTS:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        m.use_backface_culling = True
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


def cleanup(ob, dist=0.0002, drop_slivers=True):
    """Weld coincident vertices and throw away zero-area faces.

    Booleans and bevels both leave slivers - triangles with two vertices in the same place. They
    carry undefined normals, they are pure waste, and they were 2.7 % of the last pass's paint.
    Welding first is what turns them into degenerate faces that can then simply be deleted.
    """
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=dist)
    if drop_slivers:
        bad = [f for f in bm.faces if f.calc_area() < 2.0e-9]
        if bad:
            bmesh.ops.delete(bm, geom=bad, context='FACES_ONLY')
        loose = [v for v in bm.verts if not v.link_faces]
        if loose:
            bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bm.to_mesh(ob.data)
    bm.free()
    return ob


def bevel(ob, width, segments=2, angle=30.0):
    mod = ob.modifiers.new("bev", 'BEVEL')
    mod.width = width
    mod.segments = segments
    mod.limit_method = 'ANGLE'
    mod.angle_limit = math.radians(angle)
    mod.miter_outer = 'MITER_ARC'
    mod.harden_normals = False
    apply_modifiers(ob)


def boolean(ob, cutter):
    mod = ob.modifiers.new("bool", 'BOOLEAN')
    mod.object = cutter
    mod.operation = 'DIFFERENCE'
    mod.solver = 'EXACT'
    mod.material_mode = 'INDEX'
    apply_modifiers(ob)
    bpy.data.objects.remove(cutter, do_unlink=True)


def shade(ob, sharp_deg=40.0):
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
        n0 = me.polygons[fl[0]].normal
        n1 = me.polygons[fl[1]].normal
        if n0.dot(n1) < lim:
            e.use_edge_sharp = True


def join(objects):
    objects = [o for o in objects if o is not None]
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    return objects[0]


# --- primitive builders -------------------------------------------------------------------------

def grid_faces(bm, verts, nf, nh, mat, closed_h=False):
    """verts[i*nh + j], i along the length (nose first), j round the section going up."""
    out = []
    for i in range(nf - 1):
        span = nh if closed_h else nh - 1
        for j in range(span):
            j2 = (j + 1) % nh
            try:
                fc = bm.faces.new((verts[i * nh + j], verts[i * nh + j2],
                                   verts[(i + 1) * nh + j2], verts[(i + 1) * nh + j]))
            except ValueError:
                continue
            fc.material_index = mat
            out.append(fc)
    return out


def add_grid(bm, pts, nf, nh, mat, closed_h=False):
    verts = [bm.verts.new(p) for p in pts]
    return verts, grid_faces(bm, verts, nf, nh, mat, closed_h)


def in_arch(wheels, p, margin=0.006):
    """Is this point inside a wheel opening? Creases are drawn on the analytic loft, which still
    exists where the boolean cut the shell away, so without this check a character line carries
    straight on across the wheel arch as a painted blade floating over the tyre. That is exactly
    what put paint 5 cm inside the front tyre last time."""
    for w in wheels or ():
        if abs(p.x) <= w["x_in"]:
            continue
        if math.hypot(p.y - w["f"], p.z - w["u"]) < w["r"] + margin:
            return True
    return False


def crease(bm, loft, flo, fhi, h0, half_h, out, mat, side, wheels=None, steps=None):
    """A rolled character line laid proud of the skin: five rows, the middle one pushed out by
    `out`, the edges nearly flush. Bevelled afterwards it catches a hard highlight along its
    length, which is what a shoulder line actually is. A perfectly smooth flank has none and
    reads as a bar of soap. It is drawn in runs, breaking wherever it would cross an arch."""
    n = steps or max(10, int(abs(fhi - flo) / 0.065))
    fs = [fhi - (fhi - flo) * s / n for s in range(n + 1)]
    # h0 is either one ring index or a list of (f, h) keys the line follows along the car. Held
    # at a single index the shoulder line is either inside the wheel arch or up on the belt,
    # where a pure side view cannot see it at all - it has to ride up over each arch and drop
    # along the doors, which is what a real one does.
    if isinstance(h0, list):
        ks = list(reversed(h0))
        height = Mono([k[0] for k in ks], [k[1] for k in ks])
    else:
        height = lambda f: h0                                    # noqa: E731
    offs = [0.0004, out * 0.52, out, out * 0.88, 0.0008]
    if side < 0.0:
        offs = list(reversed(offs))
    run = []
    nh = 5

    def flush():
        if len(run) > 1:
            add_grid(bm, [p for row in run for p in row], len(run), nh, mat)
        run.clear()
    span = abs(fhi - flo)
    for f in fs:
        c = height(f)
        hs = [c - half_h, c - half_h * 0.34, c, c + half_h * 0.34, c + half_h]
        if side < 0.0:
            hs = list(reversed(hs))
        e = min(abs(f - flo), abs(f - fhi)) / max(1e-6, min(0.24, span * 0.45))
        fade = min(1.0, e) ** 2 * (3.0 - 2.0 * min(1.0, e)) / 1.0
        row = [loft.off(f, h, side, offs[k] * fade) for k, h in enumerate(hs)]
        if any(in_arch(wheels, q) for q in row):
            flush()
            continue
        run.append(row)
    flush()


def ribbon(bm, loft, f_list, h_list, offsets, mat, side):
    """An open strip laid on the skin; offsets[i] is the normal offset of f_list[i]."""
    hs = h_list if side > 0.0 else list(reversed(h_list))
    pts = []
    for i, f in enumerate(f_list):
        for h in hs:
            pts.append(loft.off(f, h, side, offsets[i]))
    add_grid(bm, pts, len(f_list), len(hs), mat)


def slab(bm, loft, f_list, h_list, out, thick, mat_out, mat_side, side):
    """A closed panel lying on the skin: an outer shell at `out` and an inner one `thick` under.
    With `out` negative it is a recess (a vent, a lamp sunk into the wing) instead."""
    hs = h_list if side > 0.0 else list(reversed(h_list))
    nf, nh = len(f_list), len(hs)
    outer = [loft.off(f, h, side, out) for f in f_list for h in hs]
    inner = [loft.off(f, h, side, out - thick) for f in f_list for h in hs]
    vo = [bm.verts.new(p) for p in outer]
    vi = [bm.verts.new(p) for p in inner]
    grid_faces(bm, vo, nf, nh, mat_out)
    for i in range(nf - 1):
        for j in range(nh - 1):
            try:
                fc = bm.faces.new((vi[i * nh + j], vi[(i + 1) * nh + j],
                                   vi[(i + 1) * nh + j + 1], vi[i * nh + j + 1]))
                fc.material_index = mat_side
            except ValueError:
                pass

    def wall(a, b):
        try:
            fc = bm.faces.new((vo[a], vo[b], vi[b], vi[a]))
            fc.material_index = mat_side
        except ValueError:
            pass
    for j in range(nh - 1):
        wall(j + 1, j)
        wall((nf - 1) * nh + j, (nf - 1) * nh + j + 1)
    for i in range(nf - 1):
        wall(i * nh, (i + 1) * nh)
        wall((i + 1) * nh + nh - 1, i * nh + nh - 1)


def box_bmesh(size, loc, rot=(0, 0, 0), bev=0.02, segs=2):
    tmp = bmesh.new()
    bmesh.ops.create_cube(tmp, size=1.0)
    bmesh.ops.scale(tmp, vec=Vector(size), verts=tmp.verts)
    if bev > 0.0:
        bmesh.ops.bevel(tmp, geom=list(tmp.verts) + list(tmp.edges) + list(tmp.faces),
                        offset=bev, segments=segs, affect='EDGES', profile=0.62, clamp_overlap=True)
    m = (Matrix.Translation(Vector(loc))
         @ Matrix.Rotation(rot[2], 4, 'Z')
         @ Matrix.Rotation(rot[1], 4, 'Y')
         @ Matrix.Rotation(rot[0], 4, 'X'))
    bmesh.ops.transform(tmp, matrix=m, verts=tmp.verts)
    return tmp


def merge(bm, tmp, mat):
    vmap = {v: bm.verts.new(v.co) for v in tmp.verts}
    for f in tmp.faces:
        try:
            nf = bm.faces.new([vmap[v] for v in f.verts])
            nf.material_index = mat
        except ValueError:
            pass
    tmp.free()


def add_box(bm, size, loc, rot=(0, 0, 0), mat=TRIM, bev=0.02, segs=2):
    merge(bm, box_bmesh(size, loc, rot, bev, segs), mat)


def add_cyl(bm, radius, depth, loc, rot=(0, 0, 0), mat=TRIM, segs=14, cap=True):
    tmp = bmesh.new()
    bmesh.ops.create_cone(tmp, cap_ends=cap, cap_tris=False, segments=segs,
                          radius1=radius, radius2=radius, depth=depth)
    m = (Matrix.Translation(Vector(loc))
         @ Matrix.Rotation(rot[2], 4, 'Z')
         @ Matrix.Rotation(rot[1], 4, 'Y')
         @ Matrix.Rotation(rot[0], 4, 'X'))
    bmesh.ops.transform(tmp, matrix=m, verts=tmp.verts)
    merge(bm, tmp, mat)


def sweep(bm, frames, section, mat, cap=True):
    """Extrude a 2D section along a list of (origin, x_axis, y_axis) frames.

    The one primitive behind the A-pillars, the roll hoops, the arch lips and the steering wheel:
    all four are a closed profile carried along a path, and doing them with boxes is what made the
    last pass's roll hoops "two tins left on the deck".
    """
    nsec = len(section)
    verts = []
    for (o, ax, ay) in frames:
        for (a, b) in section:
            verts.append(bm.verts.new(o + ax * a + ay * b))
    made = []
    for i in range(len(frames) - 1):
        for j in range(nsec):
            j2 = (j + 1) % nsec
            try:
                fc = bm.faces.new((verts[i * nsec + j], verts[i * nsec + j2],
                                   verts[(i + 1) * nsec + j2], verts[(i + 1) * nsec + j]))
                fc.material_index = mat
                made.append((fc, frames[i][0]))
            except ValueError:
                pass
    # Whether that order faces out depends on the handedness of the frame the caller passed, and
    # the callers here use five different frames. A swept tube wraps its own path, so vote on it.
    bm.normal_update()
    if made and sum(1 if fc.normal.dot(fc.calc_center_median() - o) >= 0.0 else -1
                    for (fc, o) in made) < 0:
        bmesh.ops.reverse_faces(bm, faces=[fc for (fc, _) in made])
    if cap:
        for idx, rev in ((0, True), (len(frames) - 1, False)):
            ring = verts[idx * nsec:(idx + 1) * nsec]
            try:
                fc = bm.faces.new(list(reversed(ring)) if rev else ring)
                fc.material_index = mat
            except ValueError:
                pass
    return verts


def revolve(bm, profile, centre, segs, mat, radial=(0.0, 0.0, 1.0), axial=(1.0, 0.0, 0.0),
            closed_profile=False, cap_first=False, cap_last=False):
    """Spin a (radius, axial) profile about an axis. The tyres, rim flanges and brake discs."""
    o = Vector(centre)
    ax = Vector(axial).normalized()
    r0 = Vector(radial).normalized()
    r1 = ax.cross(r0).normalized()
    n = len(profile)
    verts = []
    for k in range(segs):
        ang = 2.0 * math.pi * k / segs
        d = r0 * math.cos(ang) + r1 * math.sin(ang)
        for (r, a) in profile:
            verts.append(bm.verts.new(o + d * r + ax * a))
    # Winding: for a right-handed (axial, radial, axial x radial) frame the quad order
    # (k,j) (k,j+1) (k+1,j+1) (k+1,j) gives a normal of exactly MINUS the radial direction, so
    # every revolved surface comes out inside out. With doubleSided off Godot then culls the
    # outside of the tyre and draws the inside of its far wall, which is lit from within and
    # renders as a pale grey ring - the tyres looked lighter than the rims. Reverse it here.
    span = n if closed_profile else n - 1
    for k in range(segs):
        k2 = (k + 1) % segs
        for j in range(span):
            j2 = (j + 1) % n
            try:
                fc = bm.faces.new((verts[k2 * n + j], verts[k2 * n + j2],
                                   verts[k * n + j2], verts[k * n + j]))
                fc.material_index = mat
            except ValueError:
                pass
    for do_cap, j in ((cap_first, 0), (cap_last, n - 1)):
        if not do_cap:
            continue
        ring = [verts[k * n + j] for k in range(segs)]
        try:
            fc = bm.faces.new(ring if j else list(reversed(ring)))
            fc.material_index = mat
        except ValueError:
            pass
    return verts


# --- the shell ------------------------------------------------------------------------------------

def self_intersections(ob):
    """Pairs of faces that pass through each other. Must be zero: the exact boolean solver reads
    a self-intersecting solid as inside-out and quietly deletes everything."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    tree = BVHTree.FromBMesh(bm, epsilon=0.0)
    n = sum(1 for a, b in tree.overlap(tree) if a != b)
    bm.free()
    return n // 2


def stations(loft, step):
    """Sample the key sections densely enough that the loft is smooth, keeping every key f."""
    fs = []
    keys = loft.fs
    for i in range(len(keys) - 1):
        a, b = keys[i], keys[i + 1]
        n = max(1, int(round(abs(a - b) / step)))
        for s in range(n):
            fs.append(a + (b - a) * s / n)
    fs.append(keys[-1])
    return fs


def region_material(spec, f, h):
    """What a face at (length f, section index h) is made of."""
    g = spec["glass"]
    for lo, hi, hlo, hhi in g.get("sides", []):
        if hi >= f >= lo and hlo <= h <= hhi:
            return GLASS
    for lo, hi, hmin in g.get("wind", []) + g.get("back", []):
        if hi >= f >= lo and h >= hmin:
            return GLASS
    return PAINT


def glass_key(spec, f, h):
    g = spec["glass"]
    for i, (lo, hi, hlo, hhi) in enumerate(g.get("sides", [])):
        if hi >= f >= lo and hlo <= h <= hhi:
            return ("s", i)
    for i, (lo, hi, hmin) in enumerate(g.get("wind", [])):
        if hi >= f >= lo and h >= hmin:
            return ("w", i)
    for i, (lo, hi, hmin) in enumerate(g.get("back", [])):
        if hi >= f >= lo and h >= hmin:
            return ("b", i)
    return ("x", 0)


def build_shell(spec, mats):
    loft = spec["loft"]
    fs = stations(loft, spec.get("step", 0.094))
    bm = bmesh.new()
    rings = [[bm.verts.new(p) for p in loft.ring(f)] for f in fs]
    region = {}
    for i in range(len(fs) - 1):
        fm = 0.5 * (fs[i] + fs[i + 1])
        for j in range(RING_N):
            j2 = (j + 1) % RING_N
            hj = j if j <= H_TOP else RING_N - j
            hj2 = j2 if j2 <= H_TOP else RING_N - j2
            hm = 0.5 * (hj + hj2)
            try:
                fc = bm.faces.new((rings[i][j], rings[i][j2],
                                   rings[i + 1][j2], rings[i + 1][j]))
            except ValueError:
                continue
            mat = region_material(spec, fm, hm)
            fc.material_index = mat
            if mat == GLASS:
                region.setdefault(glass_key(spec, fm, hm), []).append(fc)
    for ring in (rings[0], rings[-1]):
        try:
            fc = bm.faces.new(ring)
            fc.material_index = PAINT
        except ValueError:
            pass
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))

    # Window reveals: inset each pane as one region so the frame is a single band round it, then
    # push the pane in. Insetting face by face would give every quad its own frame.
    for key, faces in region.items():
        faces = [f for f in faces if f.is_valid]
        if not faces:
            continue
        res = bmesh.ops.inset_region(bm, faces=faces, use_boundary=True, use_even_offset=True,
                                     use_interpolate=True, thickness=0.018, depth=0.0)
        for f in res["faces"]:
            f.material_index = PAINT
        bm.normal_update()
        moved = set()
        for f in faces:
            f.material_index = GLASS
            for v in f.verts:
                moved.add(v)
        for v in moved:
            v.co -= v.normal * 0.012
    bm.normal_update()
    return new_object(spec["name"] + "_shell", bm, mats)


def cut_arches(ob, spec, mats):
    """Wheel wells, cut a clear 7-8 cm OUTSIDE the tyre and carried right round the opening.

    The liner is lined in the matte black of the `tyre` slot, which is what a real wheel house is.
    It is the gap that makes the arch, not the colour: when the opening sat at exactly the tyre
    radius the "wheel" the eye found was the liner itself, the arch had no opening line at all and
    the side view showed a black disc overlapped on a dead straight sill.
    """
    for w in spec["wheels"]:
        depth = w["x_out"] - w["x_in"]
        for side in (1.0, -1.0):
            bm = bmesh.new()
            bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=30,
                                  radius1=w["r"] * 0.985, radius2=w["r"], depth=depth)
            bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0),
                             matrix=Matrix.Rotation(math.pi / 2 * side, 3, 'Y'))
            x = side * (w["x_in"] + depth * 0.5)
            bmesh.ops.translate(bm, verts=bm.verts, vec=Vector((x, w["f"], w["u"])))
            for fc in bm.faces:
                fc.material_index = TYRE
            boolean(ob, new_object("arch_cut", bm, mats))
    return ob


def cut_shapes(ob, spec, mats):
    """Intakes, ducts and (on the convertible) the cockpit, cut with bevelled boxes so the
    openings have a radius in plan rather than a router-cut corner."""
    for (size, loc, rot, bev, mat) in spec.get("cuts", []):
        tmp = box_bmesh(size, loc, rot, bev, 2)
        bm = bmesh.new()
        merge(bm, tmp, mat)
        boolean(ob, new_object("cut", bm, mats))
    return ob


# --- the arch lip ---------------------------------------------------------------------------------

# Cross-section of the flare, in (radial offset from the opening edge, offset along the surface
# normal). The crest stands 28 mm proud of the flank and is the widest thing on the car; the
# profile then turns UNDER the opening edge, which is what gives the lip a shadow line instead of
# a knife edge. Everything at a negative normal offset is buried in the bodywork: the loop has to
# close somewhere and closing it inside the panel is free.
LIP_PROFILE = [
    (0.132,  0.001),
    (0.082,  0.012),
    (0.042,  0.023),
    (0.012,  0.028),
    (-0.008, 0.026),
    (-0.022, 0.016),
    (-0.025, 0.004),
    (-0.011, -0.005),
    (0.045, -0.007),
    (0.098, -0.004),
]


def arch_lip(bm, loft, hub_f, hub_u, radius, side, mat=PAINT, a0=-22.0, a1=202.0, steps=30):
    """The flare round a wheel opening. Without it the arch is a hole and the car reads flat."""
    frames = []
    for s in range(steps + 1):
        t = s / steps
        ang = math.radians(a0 + (a1 - a0) * t)
        # Fade the flare out at the two ends instead of stopping it dead on the flank.
        e = min(t, 1.0 - t) * steps / 4.0
        fade = 0.34 + 0.66 * min(1.0, max(0.0, e)) ** 0.7
        cf, cu = math.cos(ang), math.sin(ang)
        pts = []
        for (dr, dn) in LIP_PROFILE:
            r = radius + dr
            f = hub_f + r * cf
            u = hub_u + r * cu
            h = loft.h_at_u(f, u)
            p = loft.point(f, h, side) + loft.normal(f, h, side) * (dn * fade)
            pts.append(p)
        frames.append(pts)
    n = len(LIP_PROFILE)
    verts = [bm.verts.new(p) for ring in frames for p in ring]
    for i in range(len(frames) - 1):
        for j in range(n):
            j2 = (j + 1) % n
            quad = (verts[i * n + j], verts[i * n + j2],
                    verts[(i + 1) * n + j2], verts[(i + 1) * n + j])
            if side < 0.0:
                quad = tuple(reversed(quad))
            try:
                fc = bm.faces.new(quad)
                fc.material_index = mat
            except ValueError:
                pass
    for idx, rev in ((0, side > 0.0), (len(frames) - 1, side < 0.0)):
        ring = verts[idx * n:(idx + 1) * n]
        try:
            fc = bm.faces.new(list(reversed(ring)) if rev else ring)
            fc.material_index = mat
        except ValueError:
            pass


# --- the wheels -----------------------------------------------------------------------------------

# (radius as a fraction of the tyre radius, axial position as a fraction of the bead half width).
# The 0.70 bead is a 19.6 inch rim under a 0.71 m tyre, so the sidewall is about 30 % of the
# section - a supercar tyre, not a van one. The sidewall bulges past the bead at 1.02 so the
# widest part of the tyre is rubber, never the rim.
TYRE_PROFILE = [
    (0.700, -0.94), (0.800, -1.00), (0.885, -1.02), (0.950, -0.97),
    (0.988, -0.86), (1.000, -0.72), (1.000, 0.72), (0.988, 0.86),
    (0.950, 0.97), (0.885, 1.02), (0.800, 1.00), (0.700, 0.94),
]


def add_wheel(bm, x, f, u, r, hw, spokes=5, segs=26):
    """One road wheel: tyre, rim flange, turbine spokes cut through to a visible hub, brake disc
    and caliper. Vehicle hides its own wheel meshes once a body model is present, so this is the
    wheel the player sees."""
    side = 1.0 if x >= 0.0 else -1.0
    c = (x, f, u)
    ax = (side, 0.0, 0.0)
    prof = [(a * r, b * hw) for (a, b) in TYRE_PROFILE]
    revolve(bm, prof, c, segs, TYRE, axial=ax)

    # Rim flange: the polished lip that stands proud of the tyre bead and catches the light.
    flange = [(0.688 * r, 0.930 * hw), (0.745 * r, 0.966 * hw),
              (0.752 * r, 1.000 * hw), (0.700 * r, 1.006 * hw)]
    revolve(bm, flange, c, segs, TRIM, axial=ax)
    # Inboard closure, so you do not see through the wheel from the far side.
    back = [(0.0, -0.86 * hw), (0.42 * r, -0.92 * hw), (0.700 * r, -0.94 * hw)]
    revolve(bm, back, c, 16, TRIM, axial=ax)

    # Rim barrel: the wall you see through the spoke gaps. Without it the gaps showed the brake
    # disc at 0.6 r, which filled the wheel and made the whole face read as one flat disc.
    revolve(bm, [(0.680 * r, -0.90 * hw), (0.680 * r, 0.90 * hw)], c, segs, TRIM, axial=ax)
    # Brake disc and a caliper straddling it, set well inboard so the spokes stand in front of it.
    disc = [(0.20 * r, -0.34 * hw), (0.52 * r, -0.34 * hw),
            (0.52 * r, -0.12 * hw), (0.20 * r, -0.12 * hw)]
    revolve(bm, disc, c, 16, TRIM, axial=ax, closed_profile=True)
    a = math.radians(128.0)
    add_box(bm, (0.048, 0.120, 0.080),
            (x - side * 0.22 * hw, f + math.cos(a) * 0.56 * r, u + math.sin(a) * 0.56 * r),
            rot=(-a, 0.0, 0.0), mat=TRIM, bev=0.008, segs=1)

    # Turbine spokes. Each is a tapered prism twisted about its own radial axis, so the five
    # faces meet the light at five different angles - which is the only thing that stops a rim
    # in a dark material reading as a flat disc.
    # Five turbine spokes, dished so the face falls away toward the hub and twisted so no two
    # faces meet the light at the same angle. Depth is what makes a spoke a spoke: the first pass
    # gave them 6 mm and they read as lines painted on a plate.
    for i in range(spokes):
        base = 2.0 * math.pi * i / spokes + 0.22
        ring = []
        for rad, half_a, face, depth, twist in ((0.190 * r, 0.42, 0.50 * hw, 0.34 * hw, 0.00),
                                                (0.440 * r, 0.27, 0.70 * hw, 0.30 * hw, 0.17),
                                                (0.720 * r, 0.16, 0.90 * hw, 0.22 * hw, 0.32)):
            a_mid = base + twist * side
            quad = []
            for (da, dz) in ((-half_a, 0.0), (half_a, 0.0), (half_a, -1.0), (-half_a, -1.0)):
                ang = a_mid + da
                axial = face + dz * depth
                quad.append(Vector((x + side * axial,
                                    f + math.cos(ang) * rad,
                                    u + math.sin(ang) * rad)))
            ring.append([bm.verts.new(p) for p in quad])
        for k in range(len(ring) - 1):
            a, b = ring[k], ring[k + 1]
            for j in range(4):
                j2 = (j + 1) % 4
                quad = (a[j], a[j2], b[j2], b[j])
                if side < 0.0:
                    quad = tuple(reversed(quad))
                try:
                    fc = bm.faces.new(quad)
                    fc.material_index = TRIM
                except ValueError:
                    pass
        for ringv, rev in ((ring[0], side < 0.0), (ring[-1], side > 0.0)):
            try:
                fc = bm.faces.new(list(reversed(ringv)) if rev else ringv)
                fc.material_index = TRIM
            except ValueError:
                pass

    # Hub and centre cap.
    hub = [(0.0, 0.62 * hw), (0.120 * r, 0.64 * hw), (0.200 * r, 0.56 * hw),
           (0.200 * r, 0.40 * hw), (0.0, 0.40 * hw)]
    revolve(bm, hub, c, 14, TRIM, axial=ax)


# --- details ------------------------------------------------------------------------------------

def face_lamp(bm, loft, u_mid, h_out, h_in, xs, f_end, f_in, mat, sink=0.032, proud=0.006):
    """A lamp bar wrapped onto the nose or tail cap, with a recessed dark surround.

    The last pass put a single 26 mm strip across 1.4 m of bumper: no lamp form, no depth, and it
    read as a length of tape that cut the nose in half. A lamp needs height, a taper toward the
    centre and a dark frame it sits inside.
    """
    out = 1.0 if f_end > 0.0 else -1.0       # which way "proud of the bumper" points
    rows = []
    for x in xs:
        t = abs(x) / max(1e-6, abs(xs[-1]))
        # Taper the lens toward the centreline: a bar of constant height is a ruler.
        hi = h_in * (0.44 + 0.56 * t)
        hm = hi * 1.38                       # flat dark border, in the plane of the lens
        ho = h_out * (0.74 + 0.26 * t)
        col = []
        # Six rows: recess wall, dark border, LENS, dark border, recess wall. Without the border
        # rows the surround is edge on from the front and the lamp is a bare strip of white.
        # The bar also sweeps up a little into the wings, so it is a signature rather than a
        # ruler laid across the bumper.
        rise = 0.026 * t * t
        for (du, d) in ((ho, -sink), (hm, proud - 0.007), (hi, proud), (-hi, proud),
                        (-hm, proud - 0.007), (-ho, -sink)):
            u = u_mid + du + rise
            f = loft.f_at_xu(u, abs(x), f_end, f_in)
            col.append(Vector((x, f + out * d, u)))
        rows.append(col)
    nr = 6
    verts = [bm.verts.new(p) for col in rows for p in col]
    for i in range(len(rows) - 1):
        for j in range(nr - 1):
            quad = (verts[i * nr + j], verts[i * nr + j + 1],
                    verts[(i + 1) * nr + j + 1], verts[(i + 1) * nr + j])
            if f_end > 0.0:
                quad = tuple(reversed(quad))
            try:
                fc = bm.faces.new(quad)
                fc.material_index = mat if j == 2 else TRIM
            except ValueError:
                pass
    # Close the outboard ends with a short vertical return so the bar does not just stop.
    for idx, rev in ((0, f_end < 0.0), (len(rows) - 1, f_end > 0.0)):
        ring = verts[idx * nr:(idx + 1) * nr]
        try:
            fc = bm.faces.new(list(reversed(ring)) if rev else ring)
            fc.material_index = TRIM
        except ValueError:
            pass


def plate(bm, loft, f0, f1, rise, widen, thick, mat, steps=9):
    """A splitter or diffuser that follows the body's own outline instead of being a plank.

    Both the width and the HEIGHT come from the floor pan at each station: the half width from
    `wb`, the height from `u0` plus `rise`. A constant height is what made the first splitter
    hang 19 cm below the nose in mid air - the nose floor rises 22 cm over the front overhang for
    approach angle, and a flat plate simply ignores that.
    """
    fs = [f0 + (f1 - f0) * s / steps for s in range(steps + 1)]
    top, bot = [], []
    for s, f in enumerate(fs):
        pr = loft.params(f)
        hwid = pr[1] + widen
        u = pr[0] + rise
        for sx in (-1.0, 1.0):
            top.append(Vector((sx * hwid, f, u)))
            bot.append(Vector((sx * hwid, f, u - thick)))
    vt = [bm.verts.new(p) for p in top]
    vb = [bm.verts.new(p) for p in bot]
    n = len(fs)
    for i in range(n - 1):
        a, b, c, d = i * 2, i * 2 + 1, (i + 1) * 2 + 1, (i + 1) * 2
        try:
            fc = bm.faces.new((vt[a], vt[b], vt[c], vt[d]))
            fc.material_index = mat
        except ValueError:
            pass
        try:
            fc = bm.faces.new((vb[d], vb[c], vb[b], vb[a]))
            fc.material_index = mat
        except ValueError:
            pass
        for (a, b) in ((i * 2, (i + 1) * 2), ((i + 1) * 2 + 1, i * 2 + 1)):
            try:
                fc = bm.faces.new((vt[a], vt[b], vb[b], vb[a]))
                fc.material_index = mat
            except ValueError:
                pass
    for (a, b) in ((1, 0), ((n - 1) * 2, (n - 1) * 2 + 1)):
        try:
            fc = bm.faces.new((vt[a], vt[b], vb[b], vb[a]))
            fc.material_index = mat
        except ValueError:
            pass


def mirror_pod(bm, loft, f0, h0, out, up, mat=PAINT):
    """A teardrop pod on a short swept arm. The last pass used a sphere on a stick and the two
    26 mm glass chips in them were the widest points on the whole car."""
    for side in (1.0, -1.0):
        base = loft.off(f0, h0, side, 0.006)
        n = loft.normal(f0, h0, side)
        pod_c = base + n * out + Vector((0.0, 0.0, up))
        # Arm: a flattened swept section from the shoulder out to the pod.
        frames = []
        for s in range(4):
            t = s / 3.0
            o = base + (pod_c - base) * (t * 0.86) + Vector((0.0, -0.012 * t, 0.0))
            frames.append((o, Vector((side, 0.0, 0.0)), Vector((0.0, 0.0, 1.0))))
        sec = [(-0.010, -0.013), (0.011, -0.019), (0.015, 0.015), (-0.010, 0.018)]
        sweep(bm, frames, sec, TRIM)
        # Pod: a teardrop, widest a third of the way back, tapering to the trailing edge.
        shape = [(0.085, 0.052, 0.040), (0.048, 0.078, 0.052), (-0.010, 0.082, 0.050),
                 (-0.062, 0.062, 0.038), (-0.098, 0.026, 0.017)]
        rings = []
        for (df, hwid, hht) in shape:
            ring = []
            for k in range(8):
                a = 2.0 * math.pi * k / 8.0
                ring.append(pod_c + Vector((side * math.sin(a) * hwid * 0.72,
                                            df, math.cos(a) * hht)))
            rings.append([bm.verts.new(p) for p in ring])
        for i in range(len(rings) - 1):
            for j in range(8):
                j2 = (j + 1) % 8
                quad = (rings[i][j], rings[i][j2], rings[i + 1][j2], rings[i + 1][j])
                if side < 0.0:
                    quad = tuple(reversed(quad))
                try:
                    fc = bm.faces.new(quad)
                    fc.material_index = mat
                except ValueError:
                    pass
        for ring, rev in ((rings[0], side > 0.0), (rings[-1], side < 0.0)):
            try:
                fc = bm.faces.new(list(reversed(ring)) if rev else ring)
                fc.material_index = mat
            except ValueError:
                pass
        # The glass: 150 x 90 mm, sunk into the back of the pod, never the widest thing on the car.
        add_box(bm, (0.018, 0.150, 0.090),
                (pod_c.x - side * 0.006, pod_c.y - 0.040, pod_c.z),
                rot=(0.0, 0.0, side * 0.10), mat=GLASS, bev=0.006, segs=1)


def build_details(spec, mats, bold):
    """`bold` picks the half of the detail that takes the big 4.5 mm bevel (creases, aero, lamps,
    mirrors) from the half that takes a 2 mm one (shut lines, slats, louvres, handles)."""
    loft = spec["loft"]
    d = spec["detail"]
    bm = bmesh.new()

    if bold:
        # THE SHOULDER LINE. The one detail that is not optional on this class of car, and it has
        # to run unbroken from the front arch to the tail lamp or the flank is a slab.
        for (flo, fhi, h0, half_h, out, mat) in d.get("crease", []):
            for side in (1.0, -1.0):
                crease(bm, loft, flo, fhi, h0, half_h, out, mat, side, spec["wheels"])

        for flo, fhi, hlo, hhi in d.get("sill", []):
            n = max(6, int((fhi - flo) / 0.14))
            fs = [fhi - (fhi - flo) * s / n for s in range(n + 1)]
            hs = [hlo + (hhi - hlo) * s / 3.0 for s in range(4)]
            for side in (1.0, -1.0):
                slab(bm, loft, fs, hs, 0.010, 0.034, TRIM, TRIM, side)

        for (flo, fhi, hlo, hhi, mat) in d.get("lamps", []):
            n = max(3, int((fhi - flo) / 0.05))
            fs = [fhi - (fhi - flo) * s / n for s in range(n + 1)]
            hs = [hlo + (hhi - hlo) * s / 4.0 for s in range(5)]
            for side in (1.0, -1.0):
                slab(bm, loft, fs, hs, 0.006, 0.048, mat, TRIM, side)

        for (u_mid, h_out, h_in, xmax, f_end, f_in, mat) in d.get("bars", []):
            xs = [-xmax + 2.0 * xmax * s / 16.0 for s in range(17)]
            face_lamp(bm, loft, u_mid, h_out, h_in, xs, f_end, f_in, mat)

        for (f0, h0, out, up) in d.get("mirrors", []):
            mirror_pod(bm, loft, f0, h0, out, up)

        for (f0, f1, rise, widen, thick, mat) in d.get("plates", []):
            plate(bm, loft, f0, f1, rise, widen, thick, mat)

        for (x, f0, u0, r) in d.get("exhaust", []):
            for side in (1.0, -1.0):
                add_cyl(bm, r, 0.12, (side * x, f0, u0), rot=(math.pi / 2, 0, 0), mat=TRIM, segs=14)

        for (size, loc, rot, mat, bev) in d.get("boxes", []):
            add_box(bm, size, loc, rot=rot, mat=mat, bev=bev, segs=2)
        for (size, loc, rot, mat, bev) in d.get("mirror_boxes", []):
            for side in (1.0, -1.0):
                add_box(bm, size, (side * loc[0], loc[1], loc[2]),
                        rot=(rot[0], side * rot[1], side * rot[2]), mat=mat, bev=bev, segs=2)
    else:
        for f0, hlo, hhi in d.get("shut_v", []):
            hs = [hlo + (hhi - hlo) * s / 10.0 for s in range(11)]
            for side in (1.0, -1.0):
                ribbon(bm, loft, [f0 + 0.008, f0, f0 - 0.008], hs,
                       [0.0020, 0.0007, 0.0020], TRIM, side)
        for h0, flo, fhi in d.get("shut_h", []):
            n = max(6, int((fhi - flo) / 0.10))
            fs = [fhi - (fhi - flo) * s / n for s in range(n + 1)]
            for side in (1.0, -1.0):
                hs = [h0 + 0.28, h0, h0 - 0.28]
                hlist = hs if side > 0.0 else list(reversed(hs))
                pts = []
                for f in fs:
                    for k, h in enumerate(hlist):
                        pts.append(loft.off(f, h, side, [0.0020, 0.0007, 0.0020][k]))
                add_grid(bm, pts, len(fs), 3, TRIM)

        for (flo, fhi, hlo, hhi, depth, fins) in d.get("vents", []):
            n = max(3, int((fhi - flo) / 0.06))
            fs = [fhi - (fhi - flo) * s / n for s in range(n + 1)]
            hs = [hlo + (hhi - hlo) * s / 4.0 for s in range(5)]
            for side in (1.0, -1.0):
                slab(bm, loft, fs, hs, -depth, 0.030, TRIM, TRIM, side)
                for i in range(fins):
                    t = (i + 1.0) / (fins + 1.0)
                    hf = hlo + (hhi - hlo) * t
                    ribbon(bm, loft, fs, [hf - 0.35, hf, hf + 0.35],
                           [0.0015] * len(fs), TRIM, side)

        for (halfx, u0, u1, f0, count) in d.get("slats", []):
            for i in range(count):
                u = u0 + (u1 - u0) * (i + 0.5) / count
                add_box(bm, (halfx * 2.0, 0.055, (u1 - u0) / count * 0.22), (0.0, f0, u),
                        mat=TYRE, bev=0.003, segs=1)

        for (f0, h0) in d.get("handles", []):
            for side in (1.0, -1.0):
                p = loft.off(f0, h0, side, 0.012)
                add_box(bm, (0.026, 0.130, 0.028), (p.x, p.y, p.z), mat=TRIM, bev=0.009, segs=1)

        for (f0, u0, length, tilt) in d.get("wipers", []):
            for side in (1.0, -1.0):
                add_box(bm, (length, 0.024, 0.013), (side * length * 0.52, f0, u0),
                        rot=(0.0, side * tilt, 0.0), mat=TRIM, bev=0.004, segs=1)

        for (size, loc, rot, mat, bev) in d.get("fine_boxes", []):
            add_box(bm, size, loc, rot=rot, mat=mat, bev=bev, segs=1)
        for (size, loc, rot, mat, bev) in d.get("fine_mirror_boxes", []):
            for side in (1.0, -1.0):
                add_box(bm, size, (side * loc[0], loc[1], loc[2]),
                        rot=(rot[0], side * rot[1], side * rot[2]), mat=mat, bev=bev, segs=1)

    if not bm.faces:
        bm.free()
        return None
    return new_object("%s_detail_%s" % (spec["name"], "bold" if bold else "fine"), bm, mats)


def build_rolling(spec, mats):
    """Arch lips and the four road wheels - everything that must not be bevelled again."""
    loft = spec["loft"]
    bm = bmesh.new()
    for w in spec["wheels"]:
        for side in (1.0, -1.0):
            arch_lip(bm, loft, w["f"], w["u"], w["r"], side)
            add_wheel(bm, side * HUB_X, w["f"], HUB_U, WHEEL_R, w["tyre_hw"])
    return new_object(spec["name"] + "_rolling", bm, mats)


def build_cockpit(spec, mats):
    """The roadster's interior and screen. An open car with an empty tray for a cabin is visible
    from every single angle, and the screen is the one thing the player looks through."""
    c = spec.get("cockpit")
    if not c:
        return None
    bm = bmesh.new()

    # --- windscreen. 1.42 m at the base (the last one was 1.02 on a 2.0 m car and looked like a
    # tractor cab), seated ON the cowl with no gap, with A-pillars carrying it into the shoulder.
    base_f, base_u, base_w = c["base"]
    top_f, top_u, top_w = c["top"]
    df, du = top_f - base_f, top_u - base_u
    seg = math.hypot(df, du)
    nrm = Vector((0.0, du / seg, -df / seg))          # outward: forward and up

    def screen_pt(s, t, dn):
        hwid = base_w + (top_w - base_w) * t
        f = base_f + df * t + 0.052 * (1.0 - s * s)   # convex forward in plan
        u = base_u + du * t + 0.014 * (1.0 - s * s) * t
        return Vector((s * hwid, f, u)) + nrm * dn

    ns, nt = 9, 5
    outer, inner = [], []
    for i in range(nt):
        t = i / (nt - 1.0)
        for j in range(ns):
            s = -1.0 + 2.0 * j / (ns - 1.0)
            outer.append(screen_pt(s, t, 0.0))
            inner.append(screen_pt(s, t, -0.013))
    vo = [bm.verts.new(p) for p in outer]
    vi = [bm.verts.new(p) for p in inner]
    grid_faces(bm, vo, nt, ns, GLASS)
    for i in range(nt - 1):
        for j in range(ns - 1):
            try:
                fc = bm.faces.new((vi[i * ns + j], vi[(i + 1) * ns + j],
                                   vi[(i + 1) * ns + j + 1], vi[i * ns + j + 1]))
                fc.material_index = GLASS
            except ValueError:
                pass
    for j in range(ns - 1):                                   # header and cowl edges
        for (a, b) in (((nt - 1) * ns + j, (nt - 1) * ns + j + 1), (j + 1, j)):
            try:
                fc = bm.faces.new((vo[a], vo[b], vi[b], vi[a]))
                fc.material_index = TRIM
            except ValueError:
                pass

    frames = [(screen_pt(-1.0 + 2.0 * j / (ns - 1.0), 1.0, -0.002),
               Vector((0.0, 0.0, 1.0)).cross(nrm).normalized(), nrm) for j in range(ns)]
    sweep(bm, frames, [(-0.012, -0.030), (0.022, -0.034), (0.026, 0.014), (-0.012, 0.018)],
          TRIM, cap=False)

    # A-pillars, swept along the screen's own edges so they actually meet it. The first frame is
    # well under the cowl so the pillar foot is buried in the deck rather than sitting on it.
    for side in (-1.0, 1.0):
        frames = []
        # The first frame sits BELOW the cowl so the pillar is buried in the deck, not floating.
        for i in range(nt + 1):
            tt = -0.17 if i == 0 else (i - 1) / (nt - 1.0)
            o = screen_pt(side, tt, -0.004)
            frames.append((o, Vector((side, 0.0, 0.0)), nrm))
        sec = [(-0.008, -0.030), (0.030, -0.034), (0.036, 0.016), (-0.008, 0.020)]
        sweep(bm, frames, sec, TRIM)

    # --- interior. Two buckets, a dash roll with a binnacle, a tunnel and a wheel: about 2 k
    # triangles, and the difference between a car and a bathtub.
    for sx in (-1.0, 1.0):
        x = sx * c["seat_x"]
        add_box(bm, (0.440, 0.470, 0.085), (x, c["seat_f"], c["floor"] + 0.085),
                rot=(0.05, 0, 0), mat=TRIM, bev=0.045, segs=1)
        add_box(bm, (0.420, 0.110, 0.400), (x, c["seat_f"] - 0.290, c["floor"] + 0.250),
                rot=(0.17, 0, 0), mat=TRIM, bev=0.050, segs=1)
        add_box(bm, (0.250, 0.120, 0.190), (x, c["seat_f"] - 0.352, c["floor"] + 0.462),
                rot=(0.17, 0, 0), mat=TRIM, bev=0.058, segs=1)
        # Roll hoop: two identical arcs of the same section, set symmetrically behind the seats.
        hoop_c = Vector((x, c["hoop_f"], c["hoop_u"]))
        rr = 0.118
        frames = []
        for s in range(13):
            a = math.pi * s / 12.0
            o = hoop_c + Vector((-math.cos(a) * rr, 0.0, math.sin(a) * rr))
            tangent = Vector((math.sin(a), 0.0, math.cos(a)))
            frames.append((o, Vector((0.0, 1.0, 0.0)), tangent))
        sec = [(-0.026, -0.024), (0.026, -0.024), (0.026, 0.024), (-0.026, 0.024)]
        sweep(bm, frames, sec, TRIM)

    add_box(bm, (1.180, 0.300, 0.140), (0.0, c["dash_f"], c["dash_u"]),
            rot=(0.22, 0, 0), mat=TRIM, bev=0.045, segs=1)
    add_box(bm, (0.380, 0.190, 0.115), (-c["seat_x"], c["dash_f"] - 0.100, c["dash_u"] + 0.085),
            rot=(0.40, 0, 0), mat=TRIM, bev=0.038, segs=1)
    add_box(bm, (0.240, 1.000, 0.150), (0.0, c["seat_f"] - 0.100, c["floor"] + 0.090),
            mat=TRIM, bev=0.045, segs=1)

    # Steering wheel: a real rim on three spokes, not a disc.
    wc = Vector((-c["seat_x"], c["dash_f"] - 0.265, c["dash_u"] + 0.060))
    tilt = 0.62
    up = Vector((0.0, -math.sin(tilt), math.cos(tilt)))
    fwd = Vector((0.0, math.cos(tilt), math.sin(tilt)))
    rimr = 0.168
    frames = []
    for s in range(19):
        a = 2.0 * math.pi * s / 18.0
        o = wc + (Vector((1.0, 0.0, 0.0)) * math.cos(a) + up * math.sin(a)) * rimr
        tangent = (Vector((1.0, 0.0, 0.0)) * -math.sin(a) + up * math.cos(a))
        frames.append((o, (tangent.cross(fwd)).normalized(), fwd))
    sec = [(0.019, 0.0), (0.013, 0.013), (0.0, 0.019), (-0.013, 0.013),
           (-0.019, 0.0), (-0.013, -0.013), (0.0, -0.019), (0.013, -0.013)]
    sweep(bm, frames, sec, TRIM, cap=False)
    for a in (0.0, 2.094, 4.189):
        d = Vector((1.0, 0.0, 0.0)) * math.cos(a) + up * math.sin(a)
        mid = wc + d * (rimr * 0.5)
        add_box(bm, (0.036, 0.020, rimr * 0.92),
                (mid.x, mid.y, mid.z),
                rot=(tilt, 0.0, a), mat=TRIM, bev=0.006, segs=1)
    add_cyl(bm, 0.050, 0.055, (wc.x, wc.y, wc.z), rot=(tilt + math.pi / 2, 0, 0), mat=TRIM, segs=12)

    return new_object(spec["name"] + "_cockpit", bm, mats)


# --- the cars ---------------------------------------------------------------------------------
# A key is (f, u0 floor height, wb floor half width, u1 belt height, w1 max half width,
# u2 top height, w2 top half width, crown). f runs along the car with the NOSE AT +f; every
# height is metres above the ROAD (z = 0 is the tyre contact patch). Stations crowd at the nose
# and the tail on purpose: the front of a car is a nearly vertical face carrying a splitter, an
# intake and a lamp, and spreading that taper over half a metre turns a car into a bar of soap.

# Shared front half: everything forward of the cowl is identical on both cars, and it is where
# the class lives (front axle at 1.420, screen base at 0.720 -> 0.70 m of dash to axle).
FRONT_KEYS = [
    # f       u0     wb     u1     w1     u2     w2     crown
    (2.350, 0.308, 0.352, 0.527, 0.742, 0.668, 0.606, -0.006),
    (2.330, 0.252, 0.440, 0.569, 0.820, 0.730, 0.684, -0.014),
    (2.290, 0.196, 0.508, 0.622, 0.874, 0.790, 0.734, -0.026),
    (2.210, 0.151, 0.566, 0.675, 0.908, 0.840, 0.767, -0.038),
    (2.080, 0.121, 0.610, 0.723, 0.926, 0.876, 0.771, -0.056),
    (1.900, 0.105, 0.632, 0.775, 0.936, 0.900, 0.785, -0.056),
    (1.700, 0.098, 0.642, 0.817, 0.938, 0.918, 0.769, -0.072),
    (1.420, 0.094, 0.640, 0.853, 0.952, 0.936, 0.758, -0.080),   # FRONT AXLE, fender peak
    (1.200, 0.091, 0.648, 0.864, 0.926, 0.932, 0.754, -0.070),
    (1.000, 0.089, 0.650, 0.870, 0.921, 0.929, 0.746, -0.056),
    (0.860, 0.088, 0.651, 0.874, 0.918, 0.933, 0.744, -0.034),
    (0.720, 0.087, 0.652, 0.878, 0.916, 0.945, 0.716, -0.020),   # COWL, base of the windscreen
]

# Shared tail. The taper starts at the rear axle and keeps going: the previous pass held full
# width to within 20 cm of the tail and the back of the car read as a blunt square.
TAIL_KEYS = [
    (-1.450, 0.101, 0.648, 0.902, 0.945, 1.006, 0.788, -0.014),
    (-1.700, 0.119, 0.634, 0.896, 0.940, 0.958, 0.800, -0.016),
    (-1.950, 0.146, 0.614, 0.880, 0.912, 0.922, 0.794, -0.016),
    (-2.150, 0.173, 0.588, 0.855, 0.872, 0.893, 0.766, -0.014),
    (-2.280, 0.206, 0.548, 0.808, 0.812, 0.862, 0.712, -0.012),
    (-2.335, 0.246, 0.486, 0.756, 0.722, 0.822, 0.622, -0.008),
    (-2.350, 0.302, 0.406, 0.706, 0.628, 0.772, 0.518, -0.006),
]

# Front and rear wheel wells. `r` is the ARCH OPENING radius, 7.5-8.3 cm bigger than the 0.355
# tyre: that gap is the arch, and cutting it at the tyre radius (which is what the first pass
# did) leaves a hole with no curve in the silhouette and no shadow under the lip.
WHEELS = [
    dict(f=1.420, x_in=0.665, x_out=1.120, u=HUB_U, r=0.416, tyre_hw=0.118),
    dict(f=-1.250, x_in=0.640, x_out=1.130, u=HUB_U, r=0.424, tyre_hw=0.138),
]

# Splitter, light bars and diffuser, shared by both cars. The splitter and diffuser follow the
# floor pan's own plan outline (`plate`) instead of being rectangles: the first pass's flat
# plates stuck out past the body sides and hung in the air at the corners, and read as a plank of
# cardboard slid under the car.
AERO_PLATES = [
    (2.346, 1.960, -0.005, 0.034, 0.018, TRIM),            # front splitter
    (-1.930, -2.350, -0.007, 0.036, 0.020, TRIM),          # rear diffuser
]
LAMP_BARS = [
    (0.622, 0.092, 0.038, 0.700, 2.350, 1.980, LIGHT_F),
    (0.760, 0.098, 0.046, 0.690, -2.350, -2.020, LIGHT_R),
]
AERO_BOXES = [
    # Diffuser strakes, tucked inside the plate they stand on.
    ((0.024, 0.300, 0.080), (0.0, -2.205, 0.268), (-0.36, 0, 0), TRIM, 0.007),
]
AERO_SIDE_BOXES = [
    ((0.024, 0.300, 0.080), (0.205, -2.205, 0.268), (-0.36, 0, 0), TRIM, 0.007),
    ((0.024, 0.300, 0.080), (0.385, -2.205, 0.264), (-0.36, 0, 0), TRIM, 0.007),
]

# The nose intake: a boolean recess, then a trim-lined back panel with the mesh ON it. Hanging a
# silver grille in a body-coloured bumper is what made the last one read as an aftermarket part.
NOSE_CUTS = [
    ((1.080, 0.360, 0.180), (0.0, 2.185, 0.300), (0, 0, 0), 0.045, TYRE),
    ((0.170, 0.300, 0.300), (0.735, 2.215, 0.452), (0, 0, 0), 0.050, TYRE),
    ((0.170, 0.300, 0.300), (-0.735, 2.215, 0.452), (0, 0, 0), 0.050, TYRE),
]
NOSE_LINER = [
    # Back panel of the central intake, 16 cm inside the nose skin, in the matte black of the
    # `tyre` slot: grille mesh is matte black on every car, and a lit grey panel in a red bumper
    # reads as an aftermarket grille rather than as an opening.
    ((1.040, 0.030, 0.150), (0.0, 2.022, 0.300), (0, 0, 0), TYRE, 0.006),
]
NOSE_LINER_SIDES = [
    ((0.150, 0.028, 0.270), (0.735, 2.090, 0.452), (0, 0, 0), TYRE, 0.006),   # duct back face
]

COMMON_DETAIL = dict(
    crease=[(-2.230, 1.460, [(1.460, 16.2), (1.180, 15.2), (0.300, 14.1), (-0.760, 14.3),
                             (-1.250, 15.7), (-1.900, 15.4), (-2.230, 15.0)],
             0.85, 0.0220, PAINT),                          # the shoulder line
            (-0.800, 0.980, 9.5, 0.95, 0.0095, PAINT)],     # second line along the sill
    shut_v=[(0.640, 6.0, 19.5), (-0.900, 6.0, 19.5)],
    shut_h=[(18.8, 0.700, 2.090)],
    sill=[(-1.150, 1.100, 4.2, 7.4)],
    vents=[(0.900, 1.150, 11.5, 15.5, 0.016, 3),             # side gill behind the arch
           (1.720, 1.830, 7.4, 10.0, 0.012, 2),              # brake duct ahead of the arch
           (1.600, 1.860, 26.8, 29.4, 0.010, 2)],            # bonnet extractor louvres
    slats=[(0.430, 0.248, 0.348, 2.070, 5)],
    lamps=[(-2.330, -2.140, 14.4, 16.6, LIGHT_R)],           # tail lamp wrapping the quarter
    handles=[(0.150, 17.0)],
    wipers=[(0.760, 0.958, 0.560, 0.20)],
    exhaust=[(0.230, -2.298, 0.392, 0.045), (0.368, -2.298, 0.392, 0.045)],
    plates=AERO_PLATES,
    bars=LAMP_BARS,
    boxes=list(AERO_BOXES) + list(NOSE_LINER),
    mirror_boxes=list(AERO_SIDE_BOXES) + list(NOSE_LINER_SIDES),
)


def detail(**over):
    d = {k: (list(v) if isinstance(v, list) else v) for k, v in COMMON_DETAIL.items()}
    for k, v in over.items():
        if k in d and isinstance(d[k], list) and isinstance(v, list):
            d[k] = d[k] + v
        else:
            d[k] = v
    return d


COUPE = dict(
    name="coupe",
    step=0.094,
    keys=FRONT_KEYS + [
        (0.400, 0.086, 0.654, 0.879, 0.914, 1.118, 0.680, 0.000),
        (0.100, 0.085, 0.655, 0.883, 0.914, 1.262, 0.658, 0.006),
        (-0.040, 0.085, 0.655, 0.885, 0.915, 1.296, 0.652, 0.008),  # header, top of the screen
        (-0.400, 0.085, 0.655, 0.889, 0.920, 1.300, 0.648, 0.008),  # roof, flat not domed
        (-0.760, 0.086, 0.653, 0.893, 0.930, 1.268, 0.658, 0.006),  # back of the roof
        (-1.020, 0.088, 0.650, 0.897, 0.944, 1.188, 0.700, 0.002),  # fastback
        (-1.160, 0.091, 0.646, 0.900, 0.946, 1.128, 0.736, -0.002),
        (-1.250, 0.094, 0.642, 0.903, 0.952, 1.082, 0.762, -0.006),  # REAR AXLE, haunch peak
    ] + TAIL_KEYS,
    wheels=WHEELS,
    glass=dict(
        wind=[(-0.030, 0.700, 19.0)],
        sides=[(-0.800, -0.060, 18.6, 25.2)],
        back=[(-1.620, -0.760, 26.4)],
    ),
    cuts=list(NOSE_CUTS),
    detail=detail(
        boxes=[
            # Ducktail lip: it has to poke ABOVE the deck or it is just a dark line on it.
            ((1.360, 0.230, 0.034), (0.0, -2.020, 0.918), (0, 0, 0), PAINT, 0.013),
        ],
    ),
)

CONVERTIBLE = dict(
    name="convertible",
    step=0.106,
    keys=FRONT_KEYS + [
        # No roof: the top surface drops to a flat tonneau deck just above the belt, and the
        # cockpit is cut out of it below. w2 has to stay near w1 or the shoulder inset in
        # half_outline folds the section back on itself.
        (0.400, 0.086, 0.654, 0.881, 0.914, 0.974, 0.790, -0.004),
        (0.100, 0.085, 0.655, 0.885, 0.914, 0.977, 0.798, -0.006),
        (-0.040, 0.085, 0.655, 0.887, 0.915, 0.979, 0.802, -0.006),
        (-0.400, 0.085, 0.655, 0.891, 0.920, 0.983, 0.808, -0.007),
        (-0.760, 0.086, 0.653, 0.895, 0.930, 0.988, 0.816, -0.008),
        (-1.020, 0.088, 0.650, 0.899, 0.944, 0.993, 0.822, -0.009),
        (-1.160, 0.091, 0.646, 0.902, 0.946, 0.996, 0.824, -0.010),
        (-1.250, 0.094, 0.642, 0.905, 0.952, 0.998, 0.822, -0.011),  # REAR AXLE, haunch peak
    ] + TAIL_KEYS,
    wheels=WHEELS,
    glass=dict(wind=[], sides=[], back=[]),
    cuts=list(NOSE_CUTS) + [
        # The cockpit, hollowed straight out of the loft.
        ((1.320, 1.640, 0.560), (0.0, -0.160, 1.010), (0, 0, 0), 0.180, TRIM),
    ],
    detail=detail(
        shut_v=[],
        boxes=[
            ((1.360, 0.230, 0.034), (0.0, -2.020, 0.928), (0, 0, 0), PAINT, 0.013),
            # Tonneau fairings behind the cockpit and the scuttle the screen sits on.
            ((1.180, 0.090, 0.055), (0.0, 0.690, 0.950), (0, 0, 0), TRIM, 0.018),
        ],
    ),
    cockpit=dict(
        base=(0.700, 0.945, 0.710),     # f, height, half width at the cowl
        top=(0.045, 1.262, 0.585),      # f, height, half width at the header
        seat_x=0.330, seat_f=-0.240, floor=0.680,
        dash_f=0.470, dash_u=0.885,
        hoop_f=-0.930, hoop_u=0.984,
    ),
)

CARS = {c["name"]: c for c in (COUPE, CONVERTIBLE)}
CONVERTIBLE["glass_alpha"] = 0.30


# --- build / export ------------------------------------------------------------------------------

def build(spec):
    reset_scene()
    mats = make_materials()
    spec["loft"] = Loft(spec["keys"])
    spec["detail"]["mirrors"] = [(0.560, 17.0, 0.062, 0.052)]
    shell = build_shell(spec, mats)
    cleanup(shell, 0.0004, drop_slivers=False)
    bad = self_intersections(shell)
    if bad:
        print("  WARNING %s: %d self-intersecting face pairs in the shell" % (spec["name"], bad))
    cut_shapes(shell, spec, mats)
    cut_arches(shell, spec, mats)
    cleanup(shell, 0.0004)
    bevel(shell, spec.get("bevel", 0.005), segments=2, angle=28.0)
    parts = [shell]
    bold = build_details(spec, mats, True)
    if bold is not None:
        cleanup(bold, 0.0003)
        bevel(bold, 0.0045, segments=2, angle=34.0)
        parts.append(bold)
    fine = build_details(spec, mats, False)
    if fine is not None:
        cleanup(fine, 0.0002)
        bevel(fine, 0.0020, segments=1, angle=40.0)
        parts.append(fine)
    cock = build_cockpit(spec, mats)
    if cock is not None:
        cleanup(cock, 0.0003)
        bevel(cock, 0.0035, segments=1, angle=36.0)
        parts.append(cock)
    parts.append(build_rolling(spec, mats))
    ob = join(parts)
    ob.name = PREFIX + spec["name"]
    ob.data.name = ob.name
    cleanup(ob, 0.00008)
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


def patch_glb(path, glass_alpha=None):
    """Force the material flags the exporter will not reliably give us.

    doubleSided imports into Godot as cull_mode = DISABLED, which doubles the fragment cost of a
    prop that exists 150 times in traffic and buys nothing on a closed body. The lamps get an
    emissiveFactor so they carry at night for free. The roadster's screen gets alphaMode BLEND,
    because on an open car the screen is the one thing the player looks through.
    """
    with open(path, "rb") as fh:
        blob = fh.read()
    magic, ver, total = struct.unpack("<III", blob[:12])
    assert magic == 0x46546C67, path
    off, chunks = 12, []
    while off < total:
        clen, ctype = struct.unpack("<II", blob[off:off + 8])
        chunks.append([ctype, blob[off + 8:off + 8 + clen]])
        off += 8 + clen
    doc = json.loads(chunks[0][1].decode("utf-8"))
    for m in doc.get("materials", []):
        m["doubleSided"] = False
        name = m.get("name", "")
        if name == "light_front":
            m["emissiveFactor"] = [0.22, 0.24, 0.27]
        elif name == "light_rear":
            m["emissiveFactor"] = [0.26, 0.016, 0.018]
        elif name == "glass" and glass_alpha is not None:
            m["alphaMode"] = "BLEND"
            pbr = m.setdefault("pbrMetallicRoughness", {})
            col = pbr.get("baseColorFactor", [0.04, 0.05, 0.062, 1.0])
            pbr["baseColorFactor"] = [col[0], col[1], col[2], glass_alpha]
    raw = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    raw += b" " * ((4 - len(raw) % 4) % 4)
    chunks[0][1] = raw
    out = b""
    for ctype, data in chunks:
        out += struct.pack("<II", len(data), ctype) + data
    with open(path, "wb") as fh:
        fh.write(struct.pack("<III", magic, ver, 12 + len(out)) + out)


def main(argv):
    names = [a for a in argv if a in CARS] or list(CARS)
    os.makedirs(OUT_DIR, exist_ok=True)
    for n in names:
        spec = CARS[n]
        ob = build(spec)
        me = ob.data
        me.calc_loop_triangles()
        tris = len(me.loop_triangles)
        bb = [Vector(c) for c in ob.bound_box]
        mn = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
        mx = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
        used = sorted({me.materials[p.material_index].name for p in me.polygons})
        sliver = sum(1 for t in me.loop_triangles
                     if (me.vertices[t.vertices[1]].co - me.vertices[t.vertices[0]].co).cross(
                         me.vertices[t.vertices[2]].co - me.vertices[t.vertices[0]].co).length < 2e-9)
        path = export(ob, n)
        patch_glb(path, glass_alpha=spec.get("glass_alpha"))
        print("%-12s tris=%6d  L=%.3f W=%.3f H=%.3f   x %.3f..%.3f  y %.3f..%.3f  z %.3f..%.3f"
              % (n, tris, mx.y - mn.y, mx.x - mn.x, mx.z - mn.z,
                 mn.x, mx.x, mn.y, mx.y, mn.z, mx.z))
        print("             slivers=%d  slots: %s  -> %s"
              % (sliver, ", ".join(used), os.path.basename(path)))


if __name__ == "__main__":
    main(sys.argv[1:])
