#!/usr/bin/env python3
"""Original ultra-luxury saloon and its SUV sibling, built in Blender's Python API (bpy module).

    python3 tools/make_exotic_luxury.py            # both
    python3 tools/make_exotic_luxury.py saloon     # just one

Writes assets/models/exo_lux_saloon.glb and assets/models/exo_lux_suv.glb.

ORIGINALITY
-----------
CLASS studies, never copies. No badge, no model name, no grille outline, no lamp graphic and no
surfacing cue is taken from any manufacturer's car. What makes a car read as ultra-luxury is
proportion and restraint - a very long bonnet, a cabin pushed a long way back, flat unbroken
body sides, one crisp horizontal shoulder from headlamp to tail lamp, big wheels filling squared
arches, and a formal upright roof - and none of that belongs to anybody.  The grille here is an
invented shape: a clipped keystone, wider at the top than the bottom, with a flat lid and cut
lower corners.  Names: "Halvorsen Solenne" (saloon) and "Halvorsen Altus" (SUV).  Invented.

THE BRIEF, IN NUMBERS
---------------------
saloon  length 5.75  width 2.00  height 1.57  wheelbase 3.55  wheel dia 0.72
suv     length 5.55  width 2.05  height 1.84  wheelbase 3.30  wheel dia 0.78
Overhangs are drawn symmetric (Vehicle._wheel_slots uses ONE wheel_z for both axles, so an
asymmetric car would sit its wheels off-centre in their own arches).  Arches clear the tyre by
40-45 mm all round and are SQUARED - straight sides, a flat lid, 0.12 m corners - which is what
this class does and what a supercar never does.

WHY IT IS NOT A SUPERCAR
------------------------
This class is flat surfaces and straight lines.  Every cross-section is a POLYLINE WITH FILLETED
CORNERS, not a spline: long dead-straight runs with 12-50 mm radii at the corners.  That is the
whole difference.  A Catmull-Rom section gives a barrel; a filleted polyline gives a flat door
skin with a hard crease at the top of it, which is the thing that reads as a big formal car.

GEOMETRY CONVENTIONS
--------------------
Authored X lateral, Y longitudinal with the NOSE AT +Y, Z up, ground at Z = 0.  The glTF Y-up
conversion turns that into Godot's X right, Y up, nose at -Z, which is the game's forward, and
Vehicle._add_body_model() then needs no MODEL_YAW entry.  The script prints the wheel centre
height and the axle positions the arches were drawn around; the game has to seat it with those.

STRUCTURE
---------
Two closed lofts.  The LOWER BODY runs the full length (floor pan -> rocker -> character line ->
shoulder -> deck) and the GREENHOUSE is a second loft that sits on it, so the body side and the
glasshouse are visibly separate volumes rather than one melted lump.  Wheel arches and the lamp
recesses are exact booleans; everything else is boxes and surface ribbons, and every edge gets a
1-3 mm bevel because the bevel highlight is what makes a flat panel read as sheet metal.
"""

import math
import os
import sys

import bpy  # noqa: E402  (bpy first)
import bmesh
from mathutils import Euler, Matrix, Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO, "assets", "models")
PREFIX = "exo_lux_"

# Slot order is a contract with the game: index 0 is the tinted paint and nothing else may be
# merged into it.  name, base colour, metallic, roughness.
SLOTS = [
    ("paint",       (0.78, 0.79, 0.81), 0.85, 0.26),
    ("glass",       (0.045, 0.052, 0.062), 0.00, 0.05),
    ("trim",        (0.046, 0.047, 0.051), 0.15, 0.40),
    ("tyre",        (0.028, 0.028, 0.030), 0.00, 0.90),
    ("light_front", (0.32, 0.35, 0.40), 0.00, 0.06),
    ("light_rear",  (0.42, 0.030, 0.030), 0.00, 0.10),
]
PAINT, GLASS, TRIM, TYRE, LIGHT_F, LIGHT_R = range(6)
CHROME = 6  # a seventh material that still exports as "trim"; see make_materials()


# --- maths ----------------------------------------------------------------------------------

class Mono:
    """Fritsch-Carlson monotone cubic.  A plain uniform spline through stations 30 mm apart at
    the nose and half a metre apart at the doors OVERSHOOTS, the overshoot makes neighbouring
    sections cross, and the exact boolean solver then deletes the whole car."""

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


def fillet(corners, radii, s_steps, r_steps):
    """A polyline with rounded corners, sampled to a FIXED number of points.

    corners: n points (x, z).  radii: n-2 corner radii.  s_steps: n-1 samples per straight run.
    r_steps: n-2 samples per corner arc.  Returns (points, marks) where marks[k] is the
    (first, last) output index of corner k+1's arc, so glass, sills and creases can be selected
    by index instead of by guesswork.  Straight runs stay dead straight: that is the point.
    """
    n = len(corners)
    P = [Vector(c) for c in corners]
    t = [0.0] * n
    for i in range(1, n - 1):
        a, b = P[i - 1] - P[i], P[i + 1] - P[i]
        la, lb = a.length, b.length
        if la < 1e-9 or lb < 1e-9:
            continue
        ang = math.acos(max(-1.0, min(1.0, (a / la).dot(b / lb))))
        r = radii[i - 1]
        if ang > math.pi - 2e-3 or ang < 2e-3 or r <= 1e-6:
            t[i] = 0.0
        else:
            t[i] = min(r / math.tan(ang * 0.5), la * 0.47, lb * 0.47)
    pts = [P[0]]
    marks = []
    cursor = P[0]
    for i in range(1, n - 1):
        a, b = P[i - 1] - P[i], P[i + 1] - P[i]
        la, lb = max(a.length, 1e-9), max(b.length, 1e-9)
        da, db = a / la, b / lb
        T1, T2 = P[i] + da * t[i], P[i] + db * t[i]
        ns = s_steps[i - 1]
        for k in range(1, ns + 1):
            pts.append(cursor.lerp(T1, k / ns))
        first = len(pts) - 1
        nr = r_steps[i - 1]
        if t[i] <= 1e-7:
            for k in range(1, nr + 1):
                pts.append(T1.lerp(T2, k / nr))
        else:
            ang = math.acos(max(-1.0, min(1.0, da.dot(db))))
            bis = (da + db)
            bis = bis.normalized() if bis.length > 1e-9 else Vector((0.0, 1.0))
            cen = P[i] + bis * (t[i] / max(math.cos(ang * 0.5), 1e-6))
            v1, v2 = T1 - cen, T2 - cen
            rr = v1.length
            a1 = math.atan2(v1.y, v1.x)
            a2 = math.atan2(v2.y, v2.x)
            d = a2 - a1
            while d > math.pi:
                d -= 2.0 * math.pi
            while d < -math.pi:
                d += 2.0 * math.pi
            for k in range(1, nr + 1):
                aa = a1 + d * k / nr
                pts.append(cen + Vector((math.cos(aa), math.sin(aa))) * rr)
        marks.append((first, len(pts) - 1))
        cursor = T2
    ns = s_steps[-1]
    for k in range(1, ns + 1):
        pts.append(cursor.lerp(P[-1], k / ns))
    return [(p.x, p.y) for p in pts], marks


# --- section shapes -------------------------------------------------------------------------
#
# Lower body: floor centre -> floor edge -> rocker -> character line -> shoulder -> deck edge ->
# deck centre.  The two runs that matter are rocker->character (a near-vertical, dead-straight
# door skin) and character->shoulder (the same, leaning in by 4 mm over 400 mm).  Between them
# sits the widest point of the car, with a 14 mm radius on it: that is the character line.

BODY_RAD = [0.030, 0.050, 0.014, 0.013, 0.032]
BODY_S = [2, 3, 4, 4, 2, 3]
BODY_R = [3, 3, 3, 4, 3]
BODY_NP = 11


def body_half(p):
    zf, wf, zs, ws, zc, wc, zb, wb, zd, wd, crown = p
    return fillet([(0.0, zf), (wf, zf), (ws, zs), (wc, zc), (wb, zb), (wd, zd), (0.0, zd + crown)],
                  BODY_RAD, BODY_S, BODY_R)


# Greenhouse: base centre (buried in the body) -> base edge -> DLO sill -> roof rail -> roof
# crest -> roof centre.  The long straight run is DLO sill -> rail: the tumblehome, kept to
# about 13 degrees so the glasshouse stands up formally instead of tapering like a coupe.
CAB_RAD = [0.030, 0.016, 0.034, 0.075]
CAB_S = [2, 2, 8, 3, 2]
CAB_R = [2, 3, 3, 3]
CAB_NP = 9


def cab_half(p):
    zb, wb, zdl, wdl, zr, wr, zt, wc, crown = p
    return fillet([(0.0, zb), (wb, zb), (wdl, zdl), (wr, zr), (wc, zt), (0.0, zt + crown)],
                  CAB_RAD, CAB_S, CAB_R)


class Loft:
    """Analytic skin: the section scalars interpolated along the length, sampled at (y, h)."""

    def __init__(self, keys, half_fn, nparam):
        self.keys = keys                       # nose first, tail last, y decreasing
        self.half_fn = half_fn
        xs = [k[0] for k in reversed(keys)]
        self.curves = [Mono(xs, [k[1 + i] for k in reversed(keys)]) for i in range(nparam)]
        self.y_front = keys[0][0]
        self.y_rear = keys[-1][0]
        self._cache = {}
        pts, marks = half_fn(tuple(c(keys[len(keys) // 2][0]) for c in self.curves))
        self.marks = marks
        self.half_n = len(pts)
        self.ring_n = self.half_n * 2 - 2

    def half(self, y):
        key = round(y, 5)
        v = self._cache.get(key)
        if v is None:
            v = self.half_fn(tuple(c(key) for c in self.curves))[0]
            self._cache[key] = v
        return v

    def ring(self, y):
        h = self.half(y)
        pts = [Vector((x, y, u)) for (x, u) in h]
        pts += [Vector((-x, y, u)) for (x, u) in reversed(h[1:-1])]
        return pts

    def point(self, y, h, side=1.0):
        half = self.half(round(y, 5))
        h = max(0.0, min(float(self.half_n - 1) - 1e-6, h))
        i = int(h)
        t = h - i
        x = half[i][0] + (half[i + 1][0] - half[i][0]) * t
        u = half[i][1] + (half[i + 1][1] - half[i][1]) * t
        return Vector((x * side, y, u))

    def normal(self, y, h, side=1.0):
        d = 0.02
        df = self.point(y + d, h, side) - self.point(y - d, h, side)
        dh = self.point(y, h + 0.3, side) - self.point(y, h - 0.3, side)
        n = dh.cross(-df)
        if n.length < 1e-9:
            return Vector((side, 0.0, 0.0))
        n.normalize()
        # Mirroring X flips the handedness of the cross product, so on the port side the raw
        # normal points INTO the body and every chrome strip would sink out of sight.
        return -n if side < 0.0 else n

    def x_at(self, y, z):
        """Where the flank is, at a height on the straight part of the side.  Used to lay arch
        cladding and door handles on the surface without guessing a constant x."""
        half = self.half(round(y, 5))
        lo = self.marks[0][1]
        hi = self.marks[3][0]
        best = half[lo][0]
        for i in range(lo, hi):
            z0, z1 = half[i][1], half[i + 1][1]
            if (z0 - z) * (z1 - z) <= 0.0 and abs(z1 - z0) > 1e-9:
                t = (z - z0) / (z1 - z0)
                return half[i][0] + (half[i + 1][0] - half[i][0]) * t
            best = max(best, half[i][0])
        return best


def stations(keys, step):
    ys = []
    for i in range(len(keys) - 1):
        a, b = keys[i][0], keys[i + 1][0]
        n = max(1, int(math.ceil((a - b) / step)))
        for k in range(n):
            ys.append(a - (a - b) * k / n)
    ys.append(keys[-1][0])
    return ys


# --- blender plumbing -----------------------------------------------------------------------

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_materials():
    mats = []
    for name, col, metal, rough in SLOTS:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        b = m.node_tree.nodes.get("Principled BSDF")
        b.inputs["Base Color"].default_value = (col[0], col[1], col[2], 1.0)
        b.inputs["Metallic"].default_value = metal
        b.inputs["Roughness"].default_value = rough
        mats.append(m)
    # Bright chrome shares the "trim" slot on export - the contract is six names, and a seventh
    # material would be a seventh surface the game has to know about.  Index CHROME is remapped
    # to TRIM just before export.
    m = bpy.data.materials.new("chrome_tmp")
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (0.84, 0.85, 0.87, 1.0)
    b.inputs["Metallic"].default_value = 0.72
    b.inputs["Roughness"].default_value = 0.19
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


def shade(ob, sharp_deg=36.0):
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
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    return objects[0]


# --- primitives -----------------------------------------------------------------------------

BOX_FACES = [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)]


def box(bm, size, pos, mat, rot=(0.0, 0.0, 0.0)):
    sx, sy, sz = size
    m = Matrix.Translation(Vector(pos)) @ Euler(rot, 'XYZ').to_matrix().to_4x4()
    vs = []
    for zi in (-0.5, 0.5):
        for yi in (-0.5, 0.5):
            for xi in (-0.5, 0.5):
                vs.append(bm.verts.new(m @ Vector((xi * sx, yi * sy, zi * sz))))
    for f in BOX_FACES:
        try:
            fc = bm.faces.new([vs[i] for i in f])
            fc.material_index = mat
        except ValueError:
            pass
    return vs


def prism(bm, profile, x0, x1, mat):
    """A closed 2D (y, z) loop extruded along x and capped, for boolean cutters."""
    n = len(profile)
    a = [bm.verts.new(Vector((x0, p[0], p[1]))) for p in profile]
    b = [bm.verts.new(Vector((x1, p[0], p[1]))) for p in profile]
    for i in range(n):
        j = (i + 1) % n
        try:
            f = bm.faces.new((a[i], a[j], b[j], b[i]))
            f.material_index = mat
        except ValueError:
            pass
    for ring in (a, b):
        try:
            f = bm.faces.new(ring)
            f.material_index = mat
        except ValueError:
            pass


def arch_profile(y_axle, half, top, r, seg=5, bottom=-0.45):
    pts = [(y_axle - half, bottom)]
    cl = (y_axle - half + r, top - r)
    for k in range(seg + 1):
        a = math.pi - (math.pi * 0.5) * (k / seg)
        pts.append((cl[0] + r * math.cos(a), cl[1] + r * math.sin(a)))
    cr = (y_axle + half - r, top - r)
    for k in range(seg + 1):
        a = (math.pi * 0.5) * (1.0 - k / seg)
        pts.append((cr[0] + r * math.cos(a), cr[1] + r * math.sin(a)))
    pts.append((y_axle + half, bottom))
    return pts


def patch(bm, loft, y0, y1, ny, h0, h1, nh, off, mat, side):
    """A quad grid laid on the skin over a (y, h) rectangle, pushed out along the normal."""
    rows = []
    for i in range(ny + 1):
        y = y0 + (y1 - y0) * i / ny
        row = []
        for j in range(nh + 1):
            h = h0 + (h1 - h0) * j / nh
            row.append(bm.verts.new(loft.point(y, h, side) + loft.normal(y, h, side) * off))
        rows.append(row)
    ref = loft.normal((y0 + y1) * 0.5, (h0 + h1) * 0.5, side)
    for i in range(ny):
        for j in range(nh):
            try:
                f = bm.faces.new((rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j]))
            except ValueError:
                continue
            f.material_index = mat
            f.normal_update()
            if f.normal.dot(ref) < 0.0:
                f.normal_flip()


def half_index(j, loft):
    return j if j < loft.half_n else loft.ring_n - j


def band_mat(bands, h, default=PAINT):
    for lo, hi, m in bands:
        if lo <= h <= hi:
            return m
    return default


def ribbon(bm, loft, samples, off, mat, side):
    """A thin strip laid on the skin.  samples is [(y, h_lo, h_hi)], so the caller can follow a
    constant height, a constant x on the deck, or anything else it can solve for."""
    rows = []
    for (y, h0, h1) in samples:
        rows.append([bm.verts.new(loft.point(y, h, side) + loft.normal(y, h, side) * off)
                     for h in (h0, h1)])
    y_mid, hm0, hm1 = samples[len(samples) // 2]
    ref = loft.normal(y_mid, (hm0 + hm1) * 0.5, side)
    for i in range(len(rows) - 1):
        try:
            f = bm.faces.new((rows[i][0], rows[i][1], rows[i + 1][1], rows[i + 1][0]))
        except ValueError:
            continue
        f.material_index = mat
        f.normal_update()
        if f.normal.dot(ref) < 0.0:
            f.normal_flip()


def h_at_z(loft, y, z):
    """Height on the flank, between the rocker and the shoulder, as a fractional ring index."""
    half = loft.half(round(y, 5))
    lo, hi = loft.marks[0][1], loft.marks[3][1]
    for i in range(lo, hi):
        z0, z1 = half[i][1], half[i + 1][1]
        if (z0 - z) * (z1 - z) <= 0.0 and abs(z1 - z0) > 1e-9:
            return i + (z - z0) / (z1 - z0)
    return float(loft.marks[2][0])


def h_at_x_top(loft, y, x):
    """Position across the deck (bonnet / boot lid) as a fractional ring index."""
    half = loft.half(round(y, 5))
    lo, hi = loft.marks[4][0], loft.half_n - 1
    for i in range(lo, hi):
        x0, x1 = half[i][0], half[i + 1][0]
        if (x0 - x) * (x1 - x) <= 0.0 and abs(x1 - x0) > 1e-9:
            return i + (x - x0) / (x1 - x0)
    return float(lo)


def flank_line(loft, y0, y1, z0, z1, n, w):
    """Samples for a horizontal strip of half-width w rings, running along the flank."""
    out = []
    for i in range(n + 1):
        t = i / n
        y = y0 + (y1 - y0) * t
        h = h_at_z(loft, y, z0 + (z1 - z0) * t)
        out.append((y, h - w, h + w))
    return out


def deck_line(loft, y0, y1, x, n, w):
    out = []
    for i in range(n + 1):
        y = y0 + (y1 - y0) * i / n
        h = h_at_x_top(loft, y, x)
        out.append((y, h - w, h + w))
    return out


def shut_v(bm, loft, y, z0, z1, n, off, mat, side, w=0.55):
    """A vertical panel gap: a thin raised bead rather than a groove, because a 1 mm recess
    z-fights from thirty metres away and a bead never does."""
    rows = []
    for i in range(n + 1):
        h = h_at_z(loft, y, z0 + (z1 - z0) * i / n)
        rows.append((h, y))
    samples_a = [(y - 0.006, h - 0.0, h + 0.0) for (h, y) in rows]
    del samples_a
    verts = []
    for (h, yy) in rows:
        pair = []
        for dy in (-0.007, 0.007):
            p = loft.point(yy + dy, h, side) + loft.normal(yy + dy, h, side) * off
            pair.append(bm.verts.new(p))
        verts.append(pair)
    ref = loft.normal(y, rows[len(rows) // 2][0], side)
    for i in range(len(verts) - 1):
        try:
            f = bm.faces.new((verts[i][0], verts[i][1], verts[i + 1][1], verts[i + 1][0]))
        except ValueError:
            continue
        f.material_index = mat
        f.normal_update()
        if f.normal.dot(ref) < 0.0:
            f.normal_flip()


# --- grille ---------------------------------------------------------------------------------

def grille(bm, g, mats_frame=TRIM):
    """An invented formal grille: a clipped keystone, wider at the lid than at the base, with a
    heavy surround and vertical blades.  Nothing about the outline or the blade spacing is taken
    from a real car - it is a shape that exists because a tall upright radiator once needed one.
    """
    wt, wb = g["w_top"], g["w_bot"]
    zt, zb = g["z_top"], g["z_bot"]
    yf, dep = g["y"], g["depth"]
    fr = g["frame"]
    zc, zh = (zt + zb) * 0.5, zt - zb
    # backing plate
    box(bm, (wt * 1.92, 0.035, zh * 0.98), (0.0, yf - dep, zc), TRIM)
    # lid and base
    box(bm, (wt * 2.0 + fr * 2.0, 0.075, fr), (0.0, yf - dep * 0.42, zt + fr * 0.5), CHROME)
    box(bm, (wb * 2.0 + fr * 2.0, 0.075, fr), (0.0, yf - dep * 0.42, zb - fr * 0.5), CHROME)
    # side posts, leaning so the outline is a keystone (wider at the lid than at the base)
    dx, dz = wt - wb, zt - zb
    ln = math.hypot(dx, dz)
    ry = math.atan2(dx, dz)
    for s in (-1.0, 1.0):
        box(bm, (fr, 0.075, ln), (s * ((wt + wb) * 0.5 + fr * 0.5), yf - dep * 0.42, zc),
            CHROME, rot=(0.0, s * ry, 0.0))
    # blades
    n = g["blades"]
    for i in range(n):
        x = ((i + 0.5) / n - 0.5) * (wt + wb)
        box(bm, (g["blade_w"], g["blade_d"], zh - 0.020), (x, yf - dep * 0.55, zc), CHROME)
    # a single horizontal bar across the middle, the only break in the blades
    box(bm, (wt * 1.92, 0.055, 0.028), (0.0, yf - dep * 0.50, zc + zh * 0.10), CHROME)


# --- shell / cabin --------------------------------------------------------------------------

def build_loft_object(name, loft, keys, step, mats, mat_fn):
    bm = bmesh.new()
    ys = stations(keys, step)
    rings = [[bm.verts.new(p) for p in loft.ring(y)] for y in ys]
    rn = loft.ring_n
    for i in range(len(ys) - 1):
        ym = (ys[i] + ys[i + 1]) * 0.5
        for j in range(rn):
            j2 = (j + 1) % rn
            try:
                f = bm.faces.new((rings[i][j], rings[i][j2], rings[i + 1][j2], rings[i + 1][j]))
            except ValueError:
                continue
            f.material_index = mat_fn(ym, half_index(j, loft) + 0.5)
    for ring in (rings[0], rings[-1]):
        try:
            bm.faces.new(ring).material_index = PAINT
        except ValueError:
            pass
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return new_object(name, bm, mats)


def cabin_mat_fn(spec, loft):
    """Which of paint, glass and chrome each face of the greenhouse is.

    The A-pillar is the one thing that cannot be decided by station alone: it runs diagonally,
    from the glass sill at the base of the screen up to the roof rail at the top of it, so a
    rule that said "this whole station is pillar" gave the car a 40 cm blind panel at the front
    of the front door. It is solved in (station, ring) space instead - the pillar is a band that
    climbs as the stations go back, and everything above it is windscreen wrapping round the
    side. The C-pillar is deliberately NOT done that way: a thick upright C-pillar is most of
    what makes this class formal, so it stays a plain station range.

    The chrome window surround follows the glass rather than a fixed pair of ring rows, because
    a fixed row count is a fixed FRACTION of the DLO and at five rows it ate half the window.
    """
    c = spec["cabin_look"]
    dlo_b = loft.marks[1][1]
    rail_a = loft.marks[2][0]
    span = rail_a - dlo_b
    y_front = loft.y_front
    half_pillar = c.get("pillar", 1.1)

    def fn(y, h):
        if h >= rail_a:
            if y > c["screen_top"] or y < c["light_top"]:
                return GLASS
            return PAINT
        if h < dlo_b:
            return PAINT
        m = PAINT
        if y > c["screen_top"]:
            t = min(1.0, max(0.0, (y_front - y) / max(y_front - c["screen_top"], 1e-6)))
            if h > dlo_b + t * span + half_pillar:
                m = GLASS
        elif y >= c["light_top"]:
            for (y0, y1, mm) in c["bands"]:
                if y0 >= y >= y1:
                    m = mm
                    break
        if m == GLASS and (h < dlo_b + 0.55 or h > rail_a - 0.55):
            return CHROME
        return m
    return fn


def arch_eyebrow(bm, loft, y_axle, half, top, r, grow, off, mat, side, seg=6, base=0.45):
    """A raised band round the arch opening, laid on the flank by solving for x at each (y, z).
    This is the black cladding a luxury SUV wears; a saloon in this class does not have it."""
    inner = arch_profile(y_axle, half, top, r, seg=seg, bottom=base)
    outer = arch_profile(y_axle, half + grow, top + grow, r + grow * 0.5, seg=seg, bottom=base)
    rows = []
    for a, b in zip(inner, outer):
        ra = []
        for (yy, zz) in (a, b):
            x = loft.x_at(yy, max(zz, base)) + off
            ra.append(bm.verts.new(Vector((x * side, yy, zz))))
        rows.append(ra)
    ref = Vector((side, 0.0, 0.0))
    for i in range(len(rows) - 1):
        try:
            f = bm.faces.new((rows[i][0], rows[i][1], rows[i + 1][1], rows[i + 1][0]))
        except ValueError:
            continue
        f.material_index = mat
        f.normal_update()
        if f.normal.dot(ref) < 0.0:
            f.normal_flip()


def on_flank(loft, y, z, side, out):
    p = loft.point(y, h_at_z(loft, y, z), side)
    n = loft.normal(y, h_at_z(loft, y, z), side)
    return p + n * out


# --- the two cars ---------------------------------------------------------------------------
#
# Body params per station: zf wf (floor), zs ws (rocker), zc wc (character line / max width),
# zb wb (shoulder), zd wd (deck), crown.  Cabin params: zbase wbase, zdlo wdlo (glass sill),
# zrail wrail (top of the side), zroof wcrest, crown.

SALOON_BODY = [
    (+2.845, 0.360, 0.44, 0.400, 0.560, 0.690, 0.700, 0.950, 0.660, 0.990, 0.520, 0.000),
    (+2.835, 0.280, 0.50, 0.322, 0.680, 0.616, 0.830, 0.995, 0.790, 1.045, 0.640, 0.001),
    (+2.815, 0.215, 0.58, 0.268, 0.885, 0.580, 0.945, 1.020, 0.930, 1.080, 0.800, 0.003),
    (+2.780, 0.185, 0.62, 0.252, 0.955, 0.572, 0.986, 1.030, 0.972, 1.090, 0.850, 0.004),
    (+2.700, 0.172, 0.64, 0.249, 0.968, 0.592, 0.992, 1.035, 0.980, 1.096, 0.868, 0.005),
    (+2.520, 0.164, 0.66, 0.250, 0.974, 0.618, 0.996, 1.038, 0.985, 1.098, 0.876, 0.006),
    (+2.300, 0.161, 0.67, 0.252, 0.977, 0.634, 0.998, 1.040, 0.987, 1.100, 0.882, 0.006),
    (+1.775, 0.158, 0.68, 0.254, 0.979, 0.652, 1.000, 1.042, 0.989, 1.101, 0.888, 0.006),
    (+1.400, 0.157, 0.68, 0.255, 0.980, 0.657, 1.000, 1.043, 0.991, 1.101, 0.891, 0.006),
    (+1.050, 0.156, 0.68, 0.255, 0.980, 0.659, 1.000, 1.044, 0.992, 1.100, 0.905, 0.005),
    (+0.850, 0.156, 0.68, 0.256, 0.980, 0.660, 1.000, 1.045, 0.992, 1.098, 0.940, 0.003),
    (+0.560, 0.155, 0.68, 0.256, 0.980, 0.660, 1.000, 1.045, 0.992, 1.096, 0.962, 0.000),
    (-0.450, 0.155, 0.68, 0.256, 0.980, 0.659, 1.000, 1.045, 0.992, 1.096, 0.963, 0.000),
    (-1.300, 0.156, 0.68, 0.255, 0.980, 0.656, 0.999, 1.046, 0.991, 1.097, 0.962, 0.000),
    (-1.700, 0.157, 0.68, 0.254, 0.979, 0.654, 0.998, 1.047, 0.990, 1.099, 0.948, 0.002),
    (-2.000, 0.159, 0.68, 0.254, 0.977, 0.650, 0.997, 1.049, 0.989, 1.104, 0.936, 0.004),
    (-2.350, 0.165, 0.67, 0.254, 0.974, 0.642, 0.994, 1.051, 0.985, 1.107, 0.925, 0.004),
    (-2.650, 0.176, 0.65, 0.256, 0.968, 0.628, 0.988, 1.052, 0.978, 1.107, 0.912, 0.004),
    (-2.790, 0.196, 0.62, 0.262, 0.950, 0.612, 0.976, 1.050, 0.962, 1.104, 0.885, 0.003),
    (-2.830, 0.235, 0.57, 0.288, 0.880, 0.596, 0.930, 1.044, 0.908, 1.092, 0.810, 0.002),
    (-2.850, 0.300, 0.50, 0.348, 0.690, 0.640, 0.790, 1.000, 0.760, 1.050, 0.620, 0.000),
]


SALOON_CAB = [
    (+0.730, 1.010, 0.880, 1.040, 0.862, 1.058, 0.830, 1.068, 0.560, 0.000),
    (+0.700, 1.010, 0.918, 1.080, 0.905, 1.118, 0.876, 1.140, 0.600, 0.000),
    (+0.640, 1.010, 0.940, 1.098, 0.924, 1.208, 0.880, 1.248, 0.640, 0.000),
    (+0.560, 1.010, 0.948, 1.106, 0.929, 1.330, 0.868, 1.374, 0.655, 0.000),
    (+0.470, 1.010, 0.952, 1.110, 0.931, 1.442, 0.844, 1.484, 0.650, 0.001),
    (+0.395, 1.010, 0.953, 1.112, 0.932, 1.512, 0.824, 1.546, 0.635, 0.003),
    (+0.310, 1.010, 0.954, 1.113, 0.932, 1.532, 0.814, 1.562, 0.615, 0.005),
    (-0.150, 1.010, 0.955, 1.114, 0.933, 1.537, 0.812, 1.566, 0.605, 0.005),
    (-0.700, 1.010, 0.955, 1.114, 0.933, 1.536, 0.811, 1.565, 0.605, 0.005),
    (-1.150, 1.010, 0.954, 1.113, 0.931, 1.528, 0.804, 1.557, 0.600, 0.005),
    (-1.330, 1.010, 0.952, 1.112, 0.927, 1.508, 0.795, 1.537, 0.592, 0.004),
    (-1.440, 1.010, 0.949, 1.110, 0.921, 1.442, 0.784, 1.470, 0.585, 0.003),
    (-1.560, 1.010, 0.944, 1.107, 0.911, 1.302, 0.770, 1.330, 0.575, 0.002),
    (-1.680, 1.010, 0.928, 1.098, 0.892, 1.160, 0.748, 1.180, 0.560, 0.000),
    (-1.780, 1.010, 0.885, 1.052, 0.850, 1.078, 0.715, 1.086, 0.515, 0.000),
]

SUV_BODY = [
    (+2.745, 0.430, 0.50, 0.480, 0.600, 0.800, 0.820, 1.140, 0.780, 1.200, 0.580, 0.000),
    (+2.718, 0.370, 0.56, 0.412, 0.720, 0.760, 0.950, 1.190, 0.920, 1.252, 0.760, 0.002),
    (+2.680, 0.322, 0.62, 0.372, 0.840, 0.748, 0.992, 1.215, 0.972, 1.278, 0.845, 0.004),
    (+2.600, 0.302, 0.66, 0.360, 0.915, 0.772, 1.012, 1.228, 0.996, 1.290, 0.880, 0.005),
    (+2.400, 0.294, 0.68, 0.358, 0.950, 0.800, 1.021, 1.233, 1.008, 1.294, 0.900, 0.006),
    (+2.100, 0.290, 0.68, 0.360, 0.965, 0.830, 1.025, 1.235, 1.013, 1.296, 0.910, 0.006),
    (+1.650, 0.288, 0.68, 0.362, 0.972, 0.850, 1.025, 1.236, 1.014, 1.296, 0.918, 0.006),
    (+1.200, 0.287, 0.68, 0.363, 0.975, 0.858, 1.025, 1.237, 1.015, 1.296, 0.940, 0.005),
    (+0.950, 0.287, 0.68, 0.364, 0.975, 0.860, 1.025, 1.238, 1.015, 1.294, 0.975, 0.003),
    (+0.700, 0.287, 0.68, 0.364, 0.975, 0.860, 1.025, 1.238, 1.015, 1.292, 0.992, 0.000),
    (-1.000, 0.287, 0.68, 0.364, 0.975, 0.859, 1.025, 1.239, 1.015, 1.292, 0.992, 0.000),
    (-1.650, 0.288, 0.68, 0.363, 0.973, 0.856, 1.024, 1.240, 1.014, 1.293, 0.990, 0.000),
    (-2.200, 0.292, 0.68, 0.362, 0.968, 0.850, 1.021, 1.242, 1.011, 1.296, 0.985, 0.001),
    (-2.560, 0.300, 0.67, 0.364, 0.952, 0.836, 1.012, 1.243, 1.000, 1.298, 0.960, 0.002),
    (-2.700, 0.330, 0.64, 0.380, 0.890, 0.800, 0.975, 1.238, 0.955, 1.290, 0.880, 0.002),
    (-2.745, 0.400, 0.54, 0.450, 0.700, 0.770, 0.850, 1.190, 0.810, 1.240, 0.640, 0.000),
]

SUV_CAB = [
    (+0.830, 1.220, 0.900, 1.248, 0.880, 1.262, 0.845, 1.270, 0.570, 0.000),
    (+0.800, 1.220, 0.935, 1.290, 0.920, 1.326, 0.890, 1.348, 0.610, 0.000),
    (+0.735, 1.220, 0.958, 1.308, 0.942, 1.424, 0.896, 1.462, 0.650, 0.000),
    (+0.660, 1.220, 0.968, 1.316, 0.950, 1.552, 0.884, 1.590, 0.670, 0.000),
    (+0.580, 1.220, 0.974, 1.320, 0.954, 1.676, 0.864, 1.712, 0.670, 0.001),
    (+0.510, 1.220, 0.977, 1.322, 0.956, 1.752, 0.846, 1.782, 0.660, 0.003),
    (+0.455, 1.220, 0.978, 1.323, 0.957, 1.768, 0.838, 1.794, 0.645, 0.004),
    (-0.400, 1.220, 0.979, 1.324, 0.958, 1.770, 0.837, 1.796, 0.640, 0.004),
    (-1.300, 1.220, 0.979, 1.324, 0.958, 1.768, 0.836, 1.794, 0.640, 0.004),
    (-1.900, 1.220, 0.978, 1.323, 0.955, 1.760, 0.831, 1.786, 0.636, 0.004),
    (-2.250, 1.220, 0.974, 1.320, 0.947, 1.730, 0.818, 1.756, 0.626, 0.003),
    (-2.380, 1.220, 0.968, 1.316, 0.936, 1.634, 0.806, 1.660, 0.618, 0.002),
    (-2.500, 1.220, 0.954, 1.308, 0.914, 1.476, 0.790, 1.500, 0.602, 0.001),
    (-2.610, 1.220, 0.924, 1.292, 0.872, 1.318, 0.758, 1.340, 0.578, 0.000),
    (-2.690, 1.220, 0.878, 1.254, 0.824, 1.270, 0.716, 1.276, 0.540, 0.000),
]


def details_saloon(bm, spec):
    b = spec["body"]
    ax = spec["axle"]
    # --- grille: the invented clipped keystone ---
    grille(bm, dict(w_top=0.362, w_bot=0.286, z_top=1.048, z_bot=0.512, y=2.872, depth=0.088,
                    frame=0.038, blades=11, blade_w=0.022, blade_d=0.050))
    for s in (-1.0, 1.0):
        # --- head lamps, set into the recess the boolean cut ---
        box(bm, (0.540, 0.090, 0.064), (s * 0.642, 2.790, 0.982), LIGHT_F)
        box(bm, (0.540, 0.090, 0.048), (s * 0.642, 2.790, 0.904), LIGHT_F)
        box(bm, (0.542, 0.062, 0.014), (s * 0.642, 2.798, 0.943), CHROME)
        box(bm, (0.570, 0.050, 0.020), (s * 0.642, 2.800, 1.024), CHROME)
        # --- tail lamps ---
        box(bm, (0.620, 0.075, 0.104), (s * 0.590, -2.792, 0.958), LIGHT_R)
        box(bm, (0.640, 0.046, 0.020), (s * 0.590, -2.820, 1.022), CHROME)
        # --- door handles: thin chrome pulls, one per door ---
        for hy in (-0.055, -1.150):
            p = on_flank(b, hy, 0.928, s, 0.018)
            box(bm, (0.034, 0.200, 0.036), (p.x, p.y, p.z), CHROME)
            p2 = on_flank(b, hy, 0.928, s, 0.006)
            box(bm, (0.030, 0.240, 0.060), (p2.x, p2.y, p2.z), TRIM)
        # --- door mirror ---
        p = on_flank(b, 0.640, 1.012, s, 0.0)
        box(bm, (0.090, 0.062, 0.044), (p.x + s * 0.045, p.y, p.z + 0.030), TRIM)
        box(bm, (0.070, 0.165, 0.098), (p.x + s * 0.112, p.y - 0.010, p.z + 0.058), PAINT)
        box(bm, (0.030, 0.130, 0.074), (p.x + s * 0.098, p.y - 0.042, p.z + 0.056), GLASS)
        # --- sill blade, low on the door, the only chrome on the flank ---
        ribbon(bm, b, flank_line(b, 1.560, -1.760, 0.336, 0.336, 24, 0.20), 0.007, CHROME, s)
        # --- panel gaps ---
        for gy in (0.700, -0.300, -1.430):
            shut_v(bm, b, gy, 0.300, 1.036, 10, 0.004, TRIM, s)
        # --- bonnet and boot shut lines, following the deck ---
        ribbon(bm, b, deck_line(b, 0.790, 2.700, s * 0.820, 20, 0.11), 0.004, TRIM, 1.0)
        ribbon(bm, b, deck_line(b, -1.880, -2.760, s * 0.855, 12, 0.11), 0.004, TRIM, 1.0)
        # --- bonnet power dome edges ---
        box(bm, (0.050, 1.620, 0.011), (s * 0.330, 1.800, 1.104), PAINT)
        # --- wipers ---
        box(bm, (0.020, 0.300, 0.014), (s * 0.330, 0.860, 1.104), TRIM, rot=(0.0, 0.0, s * 0.18))
        # --- exhaust finishers ---
        box(bm, (0.250, 0.062, 0.084), (s * 0.455, -2.846, 0.300), CHROME)
        # --- rubber arch lip, so the "tyre" slot is a real part and not a promise ---
        for yy in (ax, -ax):
            box(bm, (0.300, 0.020, 0.200), (s * 0.845, yy - 0.380, 0.270), TYRE)
    # --- front air intake blades and lower guard ---
    for z in (0.312, 0.392):
        box(bm, (1.020, 0.055, 0.026), (0.0, 2.800, z), CHROME)
    for s in (-1.0, 1.0):
        # corner vents: the flat outer thirds of a nose this tall need something on them
        for z in (0.408, 0.500):
            box(bm, (0.290, 0.055, 0.028), (s * 0.735, 2.800, z), CHROME)
    box(bm, (1.020, 0.120, 0.052), (0.0, 2.782, 0.258), CHROME)
    # --- the light signature runs the full width: two red bars joined by a chrome centre ---
    box(bm, (0.560, 0.072, 0.104), (0.0, -2.793, 0.958), CHROME)
    box(bm, (1.880, 0.030, 0.014), (0.0, -2.846, 1.020), CHROME)
    # number plate recess frame, so the rear panel is not one blank sheet
    for z in (0.742, 0.558):
        box(bm, (0.610, 0.040, 0.024), (0.0, -2.852, z), CHROME)
    for x in (-0.293, 0.293):
        box(bm, (0.024, 0.040, 0.208), (x, -2.852, 0.650), CHROME)
    box(bm, (1.340, 0.070, 0.058), (0.0, -2.8385, 0.400), CHROME)
    # --- lateral shut lines: front of the bonnet, front of the boot lid ---
    for s in (-1.0, 1.0):
        patch(bm, b, 2.694, 2.706, 1, h_at_x_top(b, 2.694, 0.820), b.half_n - 1.02, 10,
              0.004, TRIM, s)
        patch(bm, b, -1.886, -1.874, 1, h_at_x_top(b, -1.880, 0.855), b.half_n - 1.02, 10,
              0.004, TRIM, s)


def details_suv(bm, spec):
    b = spec["body"]
    ax = spec["axle"]
    grille(bm, dict(w_top=0.452, w_bot=0.372, z_top=1.238, z_bot=0.716, y=2.775, depth=0.094,
                    frame=0.042, blades=13, blade_w=0.024, blade_d=0.054))
    for s in (-1.0, 1.0):
        box(bm, (0.500, 0.095, 0.078), (s * 0.690, 2.690, 1.148), LIGHT_F)
        box(bm, (0.420, 0.095, 0.062), (s * 0.720, 2.690, 0.906), LIGHT_F)
        box(bm, (0.505, 0.062, 0.016), (s * 0.690, 2.700, 1.098), CHROME)
        box(bm, (0.640, 0.075, 0.110), (s * 0.600, -2.690, 1.178), LIGHT_R)
        box(bm, (0.665, 0.046, 0.020), (s * 0.600, -2.716, 1.244), CHROME)
        for hy in (0.330, -1.020):
            p = on_flank(b, hy, 1.120, s, 0.018)
            box(bm, (0.034, 0.210, 0.038), (p.x, p.y, p.z), CHROME)
            p2 = on_flank(b, hy, 1.120, s, 0.006)
            box(bm, (0.030, 0.250, 0.062), (p2.x, p2.y, p2.z), TRIM)
        p = on_flank(b, 0.720, 1.205, s, 0.0)
        box(bm, (0.095, 0.066, 0.046), (p.x + s * 0.048, p.y, p.z + 0.034), TRIM)
        box(bm, (0.074, 0.175, 0.104), (p.x + s * 0.118, p.y - 0.010, p.z + 0.064), PAINT)
        box(bm, (0.032, 0.138, 0.078), (p.x + s * 0.104, p.y - 0.046, p.z + 0.062), GLASS)
        # black arch cladding: the SUV cue the saloon deliberately does not get
        for yy in (ax, -ax):
            arch_eyebrow(bm, b, yy, 0.424, 0.824, 0.115, 0.056, 0.012, TRIM, s, base=0.470)
            box(bm, (0.300, 0.020, 0.220), (s * 0.860, yy - 0.400, 0.330), TYRE)
        # side step
        box(bm, (0.170, 2.560, 0.070), (s * 0.940, -0.060, 0.400), TRIM)
        for yy in (0.900, -1.000):
            box(bm, (0.090, 0.075, 0.130), (s * 0.905, yy, 0.470), TRIM)
        ribbon(bm, b, flank_line(b, 1.560, -1.760, 0.588, 0.588, 22, 0.16), 0.008, CHROME, s)
        for gy in (0.780, -0.470, -1.450):
            shut_v(bm, b, gy, 0.560, 1.226, 10, 0.004, TRIM, s)
        ribbon(bm, b, deck_line(b, 0.880, 2.610, s * 0.800, 18, 0.11), 0.004, TRIM, 1.0)
        # roof rail: tall enough to bury its lower half in the roof, so it needs no feet
        box(bm, (0.052, 2.200, 0.072), (s * 0.700, -0.850, 1.802), TRIM)
    for z in (0.470, 0.570):
        box(bm, (1.100, 0.055, 0.028), (0.0, 2.700, z), CHROME)
    box(bm, (1.300, 0.120, 0.070), (0.0, 2.700, 0.360), CHROME)
    # rear: the light bar runs the full width of the tailgate, with a plate recess under it
    box(bm, (0.560, 0.072, 0.046), (0.0, -2.691, 1.178), CHROME)
    box(bm, (1.860, 0.030, 0.014), (0.0, -2.748, 1.244), CHROME)
    for z in (0.928, 0.734):
        box(bm, (0.620, 0.040, 0.024), (0.0, -2.750, z), CHROME)
    for x in (-0.298, 0.298):
        box(bm, (0.024, 0.040, 0.218), (x, -2.750, 0.830), CHROME)
    box(bm, (1.440, 0.075, 0.082), (0.0, -2.7375, 0.470), TRIM)
    # rear roof spoiler over the tailgate glass
    box(bm, (1.300, 0.200, 0.046), (0.0, -2.252, 1.764), PAINT, rot=(0.22, 0.0, 0.0))
    for s in (-1.0, 1.0):
        patch(bm, b, 2.598, 2.610, 1, h_at_x_top(b, 2.604, 0.800), b.half_n - 1.02, 10,
              0.004, TRIM, s)


SALOON = dict(
    name="saloon", label="Halvorsen Solenne",
    length=5.75, body_keys=SALOON_BODY, cab_keys=SALOON_CAB,
    body_step=0.082, cab_step=0.062,
    axle=1.775, hub=0.360, arch=dict(half=0.396, top=0.752, r=0.100, x_in=0.690, x_out=1.30),
    body_bands=[],
    cabin_look=dict(screen_top=0.400, light_top=-1.335, bands=[
        (+0.400, -0.240, GLASS), (-0.240, -0.335, TRIM), (-0.335, -1.345, GLASS)]),
    lamp_cuts=[((0.500, 0.240, 0.160), (+0.625, 2.920, 0.950)),
               ((0.500, 0.240, 0.160), (-0.625, 2.920, 0.950)),
               ((1.900, 0.240, 0.136), (0.0, -2.930, 0.958)),
               ((0.560, 0.150, 0.170), (0.0, -2.920, 0.650)),
               ((1.080, 0.230, 0.170), (0.0, 2.910, 0.352)),
               ((0.320, 0.230, 0.250), (+0.735, 2.905, 0.470)),
               ((0.320, 0.230, 0.250), (-0.735, 2.905, 0.470)),
               ((1.180, 0.230, 0.130), (0.0, -2.930, 0.330))],
    details=details_saloon,
)

SUV = dict(
    name="suv", label="Halvorsen Altus",
    length=5.55, body_keys=SUV_BODY, cab_keys=SUV_CAB,
    body_step=0.080, cab_step=0.062,
    axle=1.650, hub=0.390, arch=dict(half=0.424, top=0.824, r=0.115, x_in=0.695, x_out=1.35),
    body_bands=[],  # filled in build() once the ring indices are known
    cabin_look=dict(screen_top=0.460, light_top=-2.262, bands=[
        (+0.460, -0.420, GLASS), (-0.420, -0.520, TRIM),
        (-0.520, -1.420, GLASS), (-1.420, -1.520, TRIM), (-1.520, -2.060, GLASS)]),
    lamp_cuts=[((0.530, 0.240, 0.116), (+0.690, 2.800, 1.148)),
               ((0.530, 0.240, 0.116), (-0.690, 2.800, 1.148)),
               ((0.450, 0.240, 0.100), (+0.720, 2.800, 0.906)),
               ((0.450, 0.240, 0.100), (-0.720, 2.800, 0.906)),
               ((1.900, 0.240, 0.150), (0.0, -2.830, 1.178)),
               ((0.620, 0.150, 0.190), (0.0, -2.820, 0.830)),
               ((1.160, 0.230, 0.200), (0.0, 2.820, 0.520))],
    clad_top=1.6,
    details=details_suv,
)

CARS = {c["name"]: c for c in (SALOON, SUV)}


# --- build / export -------------------------------------------------------------------------

def cutter(name, bm, mats):
    ob = new_object(name, bm, mats)
    bmesh_ok = ob
    return bmesh_ok


def build(spec):
    reset_scene()
    mats = make_materials()
    body = Loft(spec["body_keys"], body_half, BODY_NP)
    cab = Loft(spec["cab_keys"], cab_half, CAB_NP)
    spec["body"], spec["cab"] = body, cab
    if "clad_top" in spec:
        spec["body_bands"] = [(0.0, body.marks[1][1] + spec["clad_top"], TRIM)]
    bands = spec["body_bands"]

    shell = build_loft_object(PREFIX + spec["name"] + "_shell", body, spec["body_keys"],
                              spec["body_step"], mats, lambda y, h: band_mat(bands, h))
    # wheel arches
    a = spec["arch"]
    for yy in (spec["axle"], -spec["axle"]):
        for s in (1.0, -1.0):
            bm = bmesh.new()
            prof = arch_profile(yy, a["half"], a["top"], a["r"])
            x0, x1 = a["x_in"], a["x_out"]
            prism(bm, prof, min(s * x0, s * x1), max(s * x0, s * x1), TRIM)
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
            boolean(shell, new_object("cut", bm, mats))
    # lamp and intake recesses
    for size, pos in spec["lamp_cuts"]:
        bm = bmesh.new()
        box(bm, size, pos, TRIM)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        boolean(shell, new_object("cut", bm, mats))
    bevel(shell, 0.0030, segments=2, angle=26.0)

    cabin = build_loft_object(PREFIX + spec["name"] + "_cab", cab, spec["cab_keys"],
                              spec["cab_step"], mats, cabin_mat_fn(spec, cab))
    bevel(cabin, 0.0022, segments=2, angle=30.0)

    bm = bmesh.new()
    spec["details"](bm, spec)
    det = new_object(PREFIX + spec["name"] + "_det", bm, mats)
    bevel(det, 0.0018, segments=1, angle=42.0)

    ob = join([shell, cabin, det])
    ob.name = PREFIX + spec["name"]
    ob.data.name = ob.name
    # Exact length: the game scales the model by its longest horizontal axis anyway, but the
    # report has to be honest about what it is scaling.
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bb = [Vector(c) for c in ob.bound_box]
    ylen = max(v.y for v in bb) - min(v.y for v in bb)
    ob.scale = Vector.Fill(3, spec["length"] / ylen)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    shade(ob)
    # The bright chrome shares the "trim" name on export, so the game still sees exactly the six
    # contracted slots and nothing but the paint slot is ever tinted.
    ob.data.materials[CHROME].name = "trim"
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


def body_widths(spec):
    b = spec["body"]
    out = []
    for k in b.keys:
        half = b.half(k[0])
        out.append((max(x for (x, _z) in half), k[0]))
    return out


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
        per = {}
        for t in me.loop_triangles:
            slot = me.polygons[t.polygon_index].material_index
            nm = me.materials[slot].name
            per[nm] = per.get(nm, 0) + 1
        path = export(ob, n)
        # Body width is measured at the character line, not off the bounding box: the door
        # mirrors legitimately stand proud of the body and would otherwise report the car as
        # 28 cm wider than it is.
        wide = max(abs(v[0]) for v in body_widths(spec)) * 2.0
        print("%-7s %-20s tris=%6d  L %.3f  body W %.3f  roof %.3f above ground   mirrors W %.3f"
              % (n, spec["label"], tris, mx.y - mn.y, wide, mx.z, mx.x - mn.x))
        print("        wheelbase %.3f  hub z %.3f (%.3f above the model floor)  wheel dia %.3f"
              " overhang %.3f" % (spec["axle"] * 2.0, spec["hub"], spec["hub"] - mn.z,
                                  spec["hub"] * 2.0, mx.y - spec["axle"]))
        print("        arch: half %.3f, lid z %.3f (%.3f over the tyre), corner r %.3f,"
              " lowest body z %.3f"
              % (spec["arch"]["half"], spec["arch"]["top"],
                 spec["arch"]["top"] - spec["hub"] * 2.0, spec["arch"]["r"], mn.z))
        print("        slots: " + ", ".join("%s=%d" % (k, v) for k, v in sorted(per.items())))
        print("        -> " + os.path.basename(path))


if __name__ == "__main__":
    main(sys.argv[1:])
