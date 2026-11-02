#!/usr/bin/env python3
"""Everyday road car bodies (the sedan, the compact crossover, the full-size pickup), built in
Blender from code:

    tools/road_cars_setup.sh                     # once: Blender 4.2 LTS into build/car_src/
    build/car_src/blender/blender-4.2.23-linux-x64/blender -b --factory-startup \\
        -P tools/make_road_cars.py -- sedan crossover pickup [--render] [--nodetail]

Writes assets/models/road_<name>.glb. Then `godot --headless --path . --import` - Godot serves a
cached import of a .glb otherwise (CLAUDE.md, measurement trap 1). `--render` also writes Cycles
previews (front 3/4, rear 3/4, side, top) to $RENDER_DIR (default build/car_src/renders).

WHY THIS FILE EXISTS
--------------------
The cars on the street were the weakest assets in the game: ~8k-triangle Meshy remeshes with
crumpled panels. A first Blender sedan (wt/sedan-body, never merged) had clean surfaces but read
as a boxy 1980s car: flat vertical sides, an upright nose, a small greenhouse set far back, a long
flat deck. Proportions and surfacing are most of what makes a car read as modern, so this file is
organised around them rather than around the parts:

  * THE SHAPE IS PROFILE CURVES, the way a car is drawn: a side view (the roofline with a fast
    screen and a fastback rear, the bonnet and deck, the beltline, the shoulder, the sill, the
    floor), a plan view (the width at every station: the nose and the tail tapering, the hips
    over the rear wheels) and a few inset curves that make the cross section (the shoulder shelf,
    the tumblehome of the glasshouse, the tuck of the sill). Every curve is a list of (station,
    value) keys through a monotone cubic, so a change to one number moves one line on the car.
  * A CONTROL CAGE LOFTED THROUGH CROSS SECTIONS. Each station's section is a smooth curve
    through eight anchors (floor, floor edge, sill, lower door, shoulder, belt, rail, roof) taken
    from the curves above. The cage is those sections sampled on fixed rings, capped at the nose
    and the tail by a rolled rim and a domed quad patch, with the shoulder held crisp by a crease
    and two holding loops. Subdivision (Catmull-Clark, level 2) turns it into the surface.
  * The rail anchor is the glasshouse's own line: over the roof it is the side of the roof, down
    the windscreen it is the A-pillar and down the backlight the C-pillar, so the windows are
    regions between rings (belt..rail for the side glass, rail..centreline for the screens) and
    never fight the cage.
  * Everything else is cut or added AFTER subdivision, so it costs triangles only where it is:
    the wheel arches, the windows and the lamp pockets are booleans (their cutters' walls give the
    black liners and rubber seals for free), the panel gaps are 4 mm grooves cut by thin strip
    solids laid along lines drawn in side, plan or front view, and the glass, lamps, grille,
    mirrors, handles, lips and trims are separate pieces placed on the surface by raycast.

Material slots, bound by name in Vehicle._add_body_model(): `paint` (bodywork only: the car's
colour and the clearcoat shader go on this slot), `glass`, `trim` (black plastic, liners, groove
walls), `chrome`, `tyre`, `light_front`, `light_rear`. No wheels in the full model: the game
draws its generated wheels (spokes, tread, disc and caliper; they steer and spin) in the arches.

THE FAR TWIN. Each .glb holds two meshes: the full model (~50k triangles, seven surfaces, LODs
from the importer) and `<name>_far`, the same car collapsed to ~8k triangles in TWO surfaces -
`paint_far` and `parts`, every other slot folded into one with its albedo in the vertex colour
and its roughness in the alpha (Vehicle.PARTS_SHADER). Vehicle draws the twin past
`body_far_distance` (30 m): seven surfaces are seven draws and seven depth pre-pass draws a car,
and most cars on a street are further away than that. Only the twin carries a baked tyre and
rim, a little inside the generated one, for past the distance the generated wheels stop
(WHEEL_POSE "baked"), so the full model needs no runtime wheel tuck. The run prints the
WHEEL_POSE row and the numbers `Vehicle._dims()` needs; `ride` is where the physics wheels meet
the road in body space, which `tools/glshot/car_shot.gd` prints (CONTACT) for a parked car.

ORIGINAL DESIGNS. Generic 2020s classes, not copies: no manufacturer's badge, grille shape or
light signature. Geometry conventions: X lateral, Y along the car with the NOSE AT +Y (called `f`
in the section code), Z up, ground at Z = 0. The glTF exporter's Y-up conversion turns that into
Godot's X right, Y up, nose at -Z (the engine's forward).
"""

import math
import os
import sys
import time

import bpy
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
OUT_DIR = os.path.join(REPO, "assets", "models")
RENDER_DIR = os.environ.get("RENDER_DIR", os.path.join(REPO, "build", "car_src", "renders"))

# --- material slots ------------------------------------------------------------------------------
#   name, linear albedo, metallic, roughness, emission strength
SLOTS = [
    ("paint",       (0.80, 0.80, 0.80),    0.30, 0.30, 0.0),
    ("glass",       (0.018, 0.021, 0.026), 0.00, 0.05, 0.0),
    ("trim",        (0.030, 0.030, 0.033), 0.00, 0.55, 0.0),
    ("chrome",      (0.86, 0.87, 0.89),    1.00, 0.14, 0.0),
    ("tyre",        (0.024, 0.024, 0.026), 0.00, 0.90, 0.0),
    ("light_front", (0.88, 0.90, 0.94),    0.00, 0.10, 1.4),
    ("light_rear",  (0.50, 0.025, 0.030),  0.00, 0.12, 0.25),
]
PAINT, GLASS, TRIM, CHROME, TYRE, LIGHT_F, LIGHT_R = range(len(SLOTS))

SUBSURF_LEVELS = 2

# --- small numeric helpers ------------------------------------------------------------------------


def smooth01(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def ramp(x, a, b):
    """0 at a, 1 at b, smoothstepped; a > b works too."""
    if abs(b - a) < 1e-9:
        return 1.0 if x >= b else 0.0
    return smooth01((x - a) / (b - a))


class Mono:
    """Fritsch-Carlson monotone cubic through (x, y) keys. A plain spline overshoots between keys,
    which on a car body is a bulge in the middle of a panel that is not in any of the numbers."""

    def __init__(self, pts):
        pts = sorted(pts)
        self.x = [p[0] for p in pts]
        self.y = [p[1] for p in pts]
        n = len(self.x)
        if n == 1:
            self.m = [0.0]
            return
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
        if len(xs) == 1:
            return self.y[0]
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


def curve(v):
    """A profile entry is a number (constant) or a list of (station, value) keys."""
    if isinstance(v, (int, float)):
        c = float(v)
        return lambda f: c
    return Mono(v)


# --- the section ----------------------------------------------------------------------------------
#   j = 0 floor centreline   j = 1 floor edge   j = 2 sill corner   j = 3 lower door
#   j = 4 shoulder (widest)  j = 5 belt         j = 6 rail          j = 7 roof centreline
# Forward of the cowl and aft of the deck the rail anchor lies on the bonnet / boot lid crown.
N_ANCHORS = 8
## Where a flat-roofed body's ninth anchor (the roof edge, profile `roof_w` / `roof_z`) sits in
## ring coordinates, between the rail (6) and the roof centreline (7).
ROOF_J = 6.5


class Section:
    def __init__(self, spec):
        self.s = spec
        p = spec["profile"]
        self.c = {k: curve(v) for k, v in p.items()}
        self.cowl = spec["cowl"]
        self.deck = spec["deck"]

    def gh_weight(self, f):
        """1 inside the glasshouse (between the deck and the cowl), 0 on the bonnet and boot."""
        s = self.s
        return (ramp(f, self.cowl + s["gh_blend_front"], self.cowl)
                * ramp(f, self.deck - s["gh_blend_rear"], self.deck))

    def rail(self, f, w5, z5, z7):
        """The rail anchor: the glasshouse line inside the glasshouse, a point on the crown of the
        bonnet or the boot lid outside it."""
        c = self.c
        g = self.gh_weight(f)
        crown_w = w5 * self.s["crown_at"]
        crown_z = z7 - (z7 - z5) * self.s["crown_at"] ** 2
        if g <= 0.0:
            return crown_w, crown_z
        # The rail is drawn as its own side-view line: the A-pillar rising from the cowl, the side
        # of the roof, the C-pillar falling to the deck. It runs below the centreline by the
        # screens' curvature in plan and the roof's crown across the car.
        gz = c["rail_z"](f)
        gw = c["rail_w"](f)
        return crown_w + (gw - crown_w) * g, crown_z + (gz - crown_z) * g

    def anchors(self, f):
        c = self.c
        w4 = c["width"](f)
        z4 = c["shoulder_z"](f)
        z5 = c["belt_z"](f)
        w5 = w4 - c["belt_in"](f)
        z7 = c["top"](f)
        w6, z6 = self.rail(f, w5, z5, z7)
        z3 = c["low_z"](f)
        w3 = w4 - c["low_in"](f)
        z2 = c["sill_z"](f)
        w2 = w4 - c["sill_in"](f)
        z0 = c["floor_z"](f)
        w1 = w2 - c["floor_in"](f)
        P = [(0.0, z0), (w1, z0 + 0.012), (w2, z2), (w3, z3), (w4, z4), (w5, z5), (w6, z6)]
        if "roof_z" in c:
            # A ninth anchor at j = ROOF_J: the edge of a flat roof (a van). Inside the glasshouse
            # it is its own line; on the bonnet it sits between the rail and the crown.
            g = self.gh_weight(f)
            ow, oz = w6 * 0.5, z6 + (z7 - z6) * 0.75
            rw, rz = c["roof_w"](f), c["roof_z"](f)
            P.append((ow + (rw - ow) * g, oz + (rz - oz) * g))
        P.append((0.0, z7))
        return P

    def params(self):
        """The ring coordinate of each anchor."""
        if "roof_z" in self.c:
            return [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, ROOF_J, 7.0]
        return [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0]

    def tangents_at(self, f, P):
        """tangents(), with the spec's per-anchor overrides blended in by the glasshouse weight
        (a van's flat side runs straight up into its roof edge, and its roof is flat)."""
        T = self.tangents(P)
        over = self.s.get("tangent_over", {})
        if not over:
            return T
        g = self.c["over_w"](f) if "over_w" in self.c else self.gh_weight(f)
        g = min(max(g, 0.0), 1.0)
        for k, (ox, oz) in over.items():
            tx = T[k][0] + (ox - T[k][0]) * g
            tz = T[k][1] + (oz - T[k][1]) * g
            lt = math.hypot(tx, tz) or 1.0
            T[k] = (tx / lt, tz / lt)
        return T

    def j_at_z(self, f, z, j_lo=5.0, j_hi=6.9):
        """The ring coordinate where the section reaches height z, between j_lo and j_hi."""
        a, b = j_lo, j_hi
        for _ in range(28):
            m = (a + b) * 0.5
            if self.eval(f, m)[1] < z:
                a = m
            else:
                b = m
        return (a + b) * 0.5

    @staticmethod
    def tangents(P):
        """Unit tangents: the bisector of the two neighbouring chords, pinned horizontal at the
        centreline ends (so the mirrored halves meet without a crease) and vertical at the
        shoulder (so the shoulder is the widest point of the section)."""
        n = len(P)
        T = []
        for k in range(n):
            if k == 0:
                T.append((1.0, 0.0))
                continue
            if k == n - 1:
                T.append((-1.0, 0.0))
                continue
            if k == 4:
                T.append((0.0, 1.0))
                continue
            ax, az = P[k][0] - P[k - 1][0], P[k][1] - P[k - 1][1]
            bx, bz = P[k + 1][0] - P[k][0], P[k + 1][1] - P[k][1]
            la = math.hypot(ax, az) or 1.0
            lb = math.hypot(bx, bz) or 1.0
            tx, tz = ax / la + bx / lb, az / la + bz / lb
            lt = math.hypot(tx, tz) or 1.0
            T.append((tx / lt, tz / lt))
        return T

    def eval(self, f, j):
        """(u, z, nu, nz): the point on the section at ring j and its outward 2D normal."""
        P = self.anchors(f)
        T = self.tangents_at(f, P)
        J = self.params()
        jv = min(max(j, 0.0), N_ANCHORS - 1.0)
        k = 0
        while k < len(J) - 2 and jv > J[k + 1]:
            k += 1
        s = (jv - J[k]) / (J[k + 1] - J[k])
        d = math.hypot(P[k + 1][0] - P[k][0], P[k + 1][1] - P[k][1])
        ten = self.s.get("tension", 1.0) * d
        s2, s3 = s * s, s * s * s
        h00, h10, h01, h11 = 2 * s3 - 3 * s2 + 1, s3 - 2 * s2 + s, -2 * s3 + 3 * s2, s3 - s2
        g00, g10, g01, g11 = 6 * s2 - 6 * s, 3 * s2 - 4 * s + 1, -6 * s2 + 6 * s, 3 * s2 - 2 * s
        u = h00 * P[k][0] + h10 * ten * T[k][0] + h01 * P[k + 1][0] + h11 * ten * T[k + 1][0]
        z = h00 * P[k][1] + h10 * ten * T[k][1] + h01 * P[k + 1][1] + h11 * ten * T[k + 1][1]
        du = g00 * P[k][0] + g10 * ten * T[k][0] + g01 * P[k + 1][0] + g11 * ten * T[k + 1][0]
        dz = g00 * P[k][1] + g10 * ten * T[k][1] + g01 * P[k + 1][1] + g11 * ten * T[k + 1][1]
        nl = math.hypot(du, dz) or 1.0
        return u, z, dz / nl, -du / nl

    def point(self, f, j, side=1.0):
        u, z, _nu, _nz = self.eval(f, j)
        return Vector((side * u, f, z))

    def normal(self, f, j, side=1.0):
        d = 0.01
        a = self.point(f - d, j, side)
        b = self.point(f + d, j, side)
        tf = (b - a).normalized()
        _u, _z, nu, nz = self.eval(f, j)
        n = Vector((side * nu, 0.0, nz))
        n = n - tf * n.dot(tf)
        return n.normalized() if n.length > 1e-6 else Vector((side * nu, 0.0, nz))

    def j_along(self, f, j0, metres, direction=1.0):
        """The ring coordinate `metres` of arc length from j0 round the section."""
        step = 0.02 * direction
        j = j0
        u0, z0, _a, _b = self.eval(f, j)
        acc = 0.0
        while acc < metres and 0.0 <= j <= N_ANCHORS - 1.0:
            j += step
            u1, z1, _a, _b = self.eval(f, j)
            seg = math.hypot(u1 - u0, z1 - z0)
            if acc + seg >= metres:
                return j - step + step * (metres - acc) / max(seg, 1e-9)
            acc += seg
            u0, z0 = u1, z1
        return j


# --- blender plumbing -------------------------------------------------------------------------------

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_materials():
    mats = []
    for name, col, metal, rough, emit in SLOTS:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (col[0], col[1], col[2], 1.0)
        bsdf.inputs["Metallic"].default_value = metal
        bsdf.inputs["Roughness"].default_value = rough
        if emit > 0.0:
            bsdf.inputs["Emission Color"].default_value = (col[0], col[1], col[2], 1.0)
            bsdf.inputs["Emission Strength"].default_value = emit
        mats.append(m)
    return mats


MATS = []


def new_object(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    for m in MATS:
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


T0 = time.time()


def log(msg):
    print("[%6.1fs] %s" % (time.time() - T0, msg), flush=True)


def boolean(ob, cutter, op='DIFFERENCE', self_intersect=False, quiet=False, guard=True,
            tolerant=False):
    """An EXACT boolean. With `guard`, a result that lost most of the mesh (the solver read the
    body as inside a bad cutter and deleted the car) is rolled back and the cutter dropped."""
    if not quiet:
        log("boolean %s (%d faces) into %d faces" % (cutter.name, len(cutter.data.polygons),
                                                     len(ob.data.polygons)))
    before = ob.data.copy() if guard else None
    n0 = len(ob.data.polygons)
    mod = ob.modifiers.new("bool", 'BOOLEAN')
    mod.object = cutter
    mod.operation = op
    mod.solver = 'EXACT'
    mod.material_mode = 'INDEX'
    if self_intersect:
        mod.use_self = True
    if tolerant:
        mod.use_hole_tolerant = True
    apply_modifiers(ob)
    bpy.data.objects.remove(cutter, do_unlink=True)
    if guard:
        n1 = len(ob.data.polygons)
        if n1 < n0 * 0.8:
            log("  WARNING: boolean left %d of %d faces - rolled back" % (n1, n0))
            old = ob.data
            ob.data = before
            bpy.data.meshes.remove(old)
            return False
        bpy.data.meshes.remove(before)
    return True


def shade(ob, sharp_deg=35.0):
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
        p0, p1 = me.polygons[fl[0]], me.polygons[fl[1]]
        if p0.material_index != p1.material_index or p0.normal.dot(p1.normal) < lim:
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


def quad(bm, a, b, c, d, mat):
    try:
        f = bm.faces.new((a, b, c, d))
    except ValueError:
        return None
    f.material_index = mat
    return f


def grid_patch(bm, pts, nu, nv, mat, mats=None):
    """pts[i * nv + j] as an (nu x nv) grid; `mats(i, j)` may pick a slot per face."""
    verts = [bm.verts.new(p) for p in pts]
    for i in range(nu - 1):
        for j in range(nv - 1):
            m = mats(i, j) if mats else mat
            quad(bm, verts[i * nv + j], verts[(i + 1) * nv + j],
                 verts[(i + 1) * nv + j + 1], verts[i * nv + j + 1], m)
    return verts


def grid_solid(bm, top, bot, nr, nc, mat):
    """A closed solid between two (nr x nc) grids and a wall round the edge."""
    vt = [bm.verts.new(p) for p in top]
    vb = [bm.verts.new(p) for p in bot]
    for i in range(nr - 1):
        for c in range(nc - 1):
            quad(bm, vt[i * nc + c], vt[(i + 1) * nc + c], vt[(i + 1) * nc + c + 1],
                 vt[i * nc + c + 1], mat)
            quad(bm, vb[i * nc + c + 1], vb[(i + 1) * nc + c + 1], vb[(i + 1) * nc + c],
                 vb[i * nc + c], mat)

    def wall(a, b):
        quad(bm, vt[a], vt[b], vb[b], vb[a], mat)

    for c in range(nc - 1):
        wall(c, c + 1)
        wall((nr - 1) * nc + c + 1, (nr - 1) * nc + c)
    for i in range(nr - 1):
        wall(i * nc + nc - 1, (i + 1) * nc + nc - 1)
        wall((i + 1) * nc, i * nc)


def frames(path):
    """Parallel-transport frames along a polyline, so a swept profile does not spin."""
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
        up = up - tans[i] * up.dot(tans[i])
        up = up.normalized() if up.length > 1e-6 else Vector((0, 0, 1))
        out.append((tans[i], up, tans[i].cross(up).normalized()))
    return out


def sweep(bm, path, profile, mat, closed_profile=True, caps=True, normals=None):
    """Sweeps a 2D profile [(a, b)] along a path. With `normals` (one per path point) the profile's
    b axis is that normal and its a axis lies in the surface across the path, so a profile swept
    along a line on the body stands up off the body; otherwise parallel-transport frames."""
    rings = []
    fr = frames(path)
    for i, p in enumerate(path):
        t = fr[i][0]
        if normals is not None:
            nb = normals[i] - t * normals[i].dot(t)
            nb = nb.normalized() if nb.length > 1e-6 else fr[i][1]
            na = t.cross(nb).normalized()
        else:
            nb, na = fr[i][1], fr[i][2]
        pr = profile(i) if callable(profile) else profile
        rings.append([bm.verts.new(p + na * a + nb * b) for a, b in pr])
    m = len(rings[0])
    seg = m if closed_profile else m - 1
    made = []
    for i in range(len(rings) - 1):
        for k in range(seg):
            k2 = (k + 1) % m
            f = quad(bm, rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k], mat)
            if f is not None:
                made.append(f)
    if caps and closed_profile:
        for ring in (rings[0], rings[-1]):
            try:
                f = bm.faces.new(ring)
                f.material_index = mat
                made.append(f)
            except ValueError:
                pass
    # A closed swept shell is oriented outward on its own, whatever the profile's winding; the
    # shared trims mesh is never recalculated as a whole (its open panels are wound by hand).
    if closed_profile and made:
        bmesh.ops.recalc_face_normals(bm, faces=made)
    return rings


def add_box(bm, size, loc, mat):
    sx, sy, sz = (s * 0.5 for s in size)
    cx, cy, cz = loc
    co = [(-sx, -sy, -sz), (sx, -sy, -sz), (sx, sy, -sz), (-sx, sy, -sz),
          (-sx, -sy, sz), (sx, -sy, sz), (sx, sy, sz), (-sx, sy, sz)]
    v = [bm.verts.new((cx + x, cy + y, cz + z)) for x, y, z in co]
    for a, b, c, d in [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
                       (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]:
        quad(bm, v[a], v[b], v[c], v[d], mat)
    return v


def tidy(bm):
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=2e-5)
    bmesh.ops.dissolve_degenerate(bm, dist=2e-5, edges=bm.edges)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)


def coons_cap(bm, loop, mat, dome, axis_sign, lean=None):
    """Closes a section loop with a quad grid (an n-gon cap subdivides into a high-valence pole
    that ripples across the fascia). `dome` bows it out along the car; `lean(u, v)` adds a shaped
    offset so a face can be fuller low down than at the top."""
    K = len(loop)
    a = K // 4
    if a * 4 != K:
        f = bm.faces.new(loop)
        f.material_index = mat
        return []
    corner = [loop[0], loop[a], loop[2 * a], loop[3 * a]]
    grid = [[None] * (a + 1) for _ in range(a + 1)]
    for p in range(a + 1):
        grid[p][0] = loop[p]
        grid[p][a] = loop[(3 * a - p) % K]
    for q in range(a + 1):
        grid[a][q] = loop[a + q]
        grid[0][q] = loop[(4 * a - q) % K]
    made = []
    for p in range(1, a):
        for q in range(1, a):
            u = p / a
            v = q / a
            co = ((1 - v) * grid[p][0].co + v * grid[p][a].co
                  + (1 - u) * grid[0][q].co + u * grid[a][q].co
                  - ((1 - u) * (1 - v) * corner[0].co + u * (1 - v) * corner[1].co
                     + u * v * corner[2].co + (1 - u) * v * corner[3].co))
            co = co.copy()
            bow = math.sin(math.pi * u) * math.sin(math.pi * v)
            co.y += axis_sign * dome * bow
            if lean is not None:
                co.y += axis_sign * lean(co) * bow
            grid[p][q] = bm.verts.new(co)
            made.append(grid[p][q])
    for p in range(a):
        for q in range(a):
            quad(bm, grid[p][q], grid[p + 1][q], grid[p + 1][q + 1], grid[p][q + 1], mat)
    return made


# --- the cage ----------------------------------------------------------------------------------------

def ring_list(spec):
    rings = list(spec["rings"])
    if len(rings) % 2 == 0:
        raise ValueError("the ring count must be odd (the caps are Coons patches)")
    return rings


def station_list(spec):
    nose, tail = spec["nose"], spec["tail"]
    st = set()
    for d in spec["end_steps"]:
        st.add(round(nose - d, 5))
        st.add(round(tail + d, 5))
    lo = tail + spec["end_steps"][-1]
    hi = nose - spec["end_steps"][-1]
    n = max(2, int(round((hi - lo) / spec["mid_step"])))
    for i in range(1, n):
        st.add(round(lo + (hi - lo) * i / n, 5))
    # Extra stations push out the evenly spaced ones near them, but never each other: they come
    # in clusters round a corner, and when each one cleared its neighbours only the last of a
    # cluster survived - the first pickup's cab back was a long roll for exactly that reason.
    extras = [round(f, 5) for f in spec.get("extra_stations", [])]
    for f in extras:
        st = {s for s in st if abs(s - f) > spec["mid_step"] * 0.3}
    st.update(extras)
    return sorted(st, reverse=True)


def bump(x, a, b, feather):
    """1 between a and b, easing to 0 over `feather` outside them."""
    lo, hi = min(a, b), max(a, b)
    if x < lo:
        return smooth01(1.0 - (lo - x) / feather) if feather > 0 else 0.0
    if x > hi:
        return smooth01(1.0 - (x - hi) / feather) if feather > 0 else 0.0
    return 1.0


def build_body(spec, sec):
    rings = ring_list(spec)
    stations = station_list(spec)
    M = len(rings)
    K = 2 * M - 2
    loop_ring = list(range(M)) + list(range(M - 2, 0, -1))
    loop_side = [1.0] * M + [-1.0] * (M - 2)

    bm = bmesh.new()
    cre = crease_layer(bm)
    evals = [[sec.eval(f, j) for j in rings] for f in stations]

    # Sculpt: smooth bumps along the section normal, (f0, f1, f_feather, j0, j1, j_feather, amount)
    sculpt = spec.get("sculpt", [])

    def disp(f, j):
        d = 0.0
        for f0, f1, ff, j0, j1, jf, amt in sculpt:
            d += amt * bump(f, f0, f1, ff) * bump(j, j0, j1, jf)
        return d

    verts = []
    for i, f in enumerate(stations):
        row = []
        for k in range(K):
            r = loop_ring[k]
            s = loop_side[k]
            u, z, nu, nz = evals[i][r]
            dd = disp(f, rings[r])
            row.append(bm.verts.new((s * (u + nu * dd), f, z + nz * dd)))
        verts.append(row)

    under = spec.get("under_j", 1.0)

    def face_mat(i, k):
        j = (rings[loop_ring[k]] + rings[loop_ring[(k + 1) % K]]) * 0.5
        return TRIM if j < under else PAINT

    for i in range(len(stations) - 1):
        for k in range(K):
            k2 = (k + 1) % K
            quad(bm, verts[i][k], verts[i][k2], verts[i + 1][k2], verts[i + 1][k], face_mat(i, k))

    # Nose and tail: a rolled rim, then a Coons cap.
    for end, sign, key in ((0, 1.0, "nose_cap"), (len(stations) - 1, -1.0, "tail_cap")):
        cap = spec[key]
        rim = verts[end]
        prev = rim
        out = evals[end]
        steps = cap["steps"]
        for step in range(1, steps + 1):
            ang = (math.pi * 0.5) * step / steps
            row = []
            for k in range(K):
                r = loop_ring[k]
                s = loop_side[k]
                R = cap["roll"](rings[r])
                u, z, nu, nz = out[r]
                base = Vector((s * u, stations[end], z))
                nv = Vector((s * nu, 0.0, nz))
                row.append(bm.verts.new(base - nv * (R * (1.0 - math.cos(ang)))
                                        + Vector((0.0, sign * R * math.sin(ang), 0.0))))
            for k in range(K):
                k2 = (k + 1) % K
                m = TRIM if (rings[loop_ring[k]] + rings[loop_ring[k2]]) * 0.5 < under else PAINT
                if sign > 0:
                    quad(bm, prev[k], prev[k2], row[k2], row[k], m)
                else:
                    quad(bm, prev[k2], prev[k], row[k], row[k2], m)
            prev = row
        coons_cap(bm, list(prev), PAINT, cap["dome"], sign, cap.get("lean"))

    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    def set_crease(v1, v2, value):
        if v1 is v2 or not v1.is_valid or not v2.is_valid:
            return
        e = bm.edges.get((v1, v2))
        if e is not None:
            e[cre] = max(e[cre], value)

    # Creases along rings: (j, value, f_lo, f_hi)
    for j0, value, f_lo, f_hi in spec.get("creases", []):
        if j0 not in rings:
            continue
        r = rings.index(j0)
        for k in (r, K - r):
            for i in range(len(stations) - 1):
                fm = (stations[i] + stations[i + 1]) * 0.5
                if f_lo <= fm <= f_hi:
                    set_crease(verts[i][k % K], verts[i + 1][k % K], value)

    # Creases across the car along a station loop: (f, value, j_lo, j_hi), f one of the
    # stations. Subdivision pulls the surface inside the cage, so a sharp corner in the side
    # profile (a truck's roof edge over a near-vertical back) comes out as a long roll unless the
    # loop at the corner is creased (and held by close stations either side).
    for f0, value, j_lo, j_hi in spec.get("station_creases", []):
        near = min(range(len(stations)), key=lambda i: abs(stations[i] - f0))
        if abs(stations[near] - f0) > 1e-4:
            continue
        for k in range(K):
            k2 = (k + 1) % K
            j = (rings[loop_ring[k]] + rings[loop_ring[k2]]) * 0.5
            if j_lo <= j <= j_hi:
                set_crease(verts[near][k], verts[near][k2], value)

    ob = new_object("body", bm)
    subsurf(ob)
    return ob


# --- surface probing -------------------------------------------------------------------------------

class Surface:
    """Raycasts the finished (subdivided) body, so every detail sits on the real surface rather
    than on the cage, which subdivision has pulled inwards."""

    def __init__(self, ob, sec):
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bm.transform(ob.matrix_world)
        self.bvh = BVHTree.FromBMesh(bm)
        bm.free()
        self.sec = sec

    def ray(self, origin, direction, length=8.0):
        d = Vector(direction).normalized()
        loc, nor, _idx, _dist = self.bvh.ray_cast(Vector(origin), d, length)
        if loc is None:
            return None, None
        if nor.dot(d) > 0.0:
            nor = -nor
        return loc, nor

    def on_body(self, f, j, side=1.0):
        p = self.sec.point(f, j, side)
        n = self.sec.normal(f, j, side)
        loc, nor = self.ray(p + n * 0.25, -n, 0.6)
        if loc is None:
            return p, n
        return loc, nor

    def side_hit(self, y, z, side=1.0):
        return self.ray((side * 3.0, y, z), (-side, 0.0, 0.0), 6.0)

    def top_hit(self, x, y):
        return self.ray((x, y, 4.0), (0.0, 0.0, -1.0), 6.0)

    def end_hit(self, x, z, end):
        """The nose (end=+1) or tail (end=-1) seen head on."""
        return self.ray((x, end * 5.0, z), (0.0, -end, 0.0), 8.0)


def densify(pts, step):
    """Resamples a 2D polyline so no segment is longer than `step`."""
    out = [pts[0]]
    for a, b in zip(pts[:-1], pts[1:]):
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        n = max(1, int(math.ceil(L / step)))
        for k in range(1, n + 1):
            t = k / n
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def surface_path(surf, view, pts, side=1.0, step=0.02):
    """3D points and normals on the body along a polyline drawn in one orthographic view:
    'side' (y, z), 'top' (x, y), 'front' / 'rear' (x, z)."""
    out = []
    for a, b in densify(pts, step):
        if view == "side":
            loc, nor = surf.side_hit(a, b, side)
        elif view == "top":
            loc, nor = surf.top_hit(a, b)
        elif view == "front":
            loc, nor = surf.end_hit(a, b, 1.0)
        else:
            loc, nor = surf.end_hit(a, b, -1.0)
        if loc is not None:
            out.append((loc, nor))
    return out


def fj_path(surf, pts, side=1.0, step=0.02):
    """The same along a polyline drawn in the section's own (f, j) coordinates."""
    out = []
    dense = []
    for a, b in zip(pts[:-1], pts[1:]):
        pa, pb = surf.sec.point(a[0], a[1], side), surf.sec.point(b[0], b[1], side)
        n = max(1, int(math.ceil((pb - pa).length / step)))
        for k in range(n):
            t = k / n
            dense.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    dense.append(pts[-1])
    for f, j in dense:
        out.append(surf.on_body(f, j, side))
    return out


# --- cutters -----------------------------------------------------------------------------------------

def arch_cutter(spec):
    """All four arches in one operand: a blind pocket from inside the wheel to past the body."""
    bm = bmesh.new()
    for f_c, R, x_in in ((spec["front_axle"], spec["arch_r"], spec["arch_in"]),
                         (spec["rear_axle"], spec["arch_r_rear"], spec["arch_in"])):
        az = spec["axle_z"]
        for side in (1.0, -1.0):
            prof = [(f_c + R, -0.3)]
            n = 32
            for k in range(n + 1):
                a = math.pi * k / n
                prof.append((f_c + R * math.cos(a), az + R * math.sin(a)))
            prof.append((f_c - R, -0.3))
            xa, xb = (x_in, 1.4) if side > 0 else (-1.4, -x_in)
            ra = [bm.verts.new((xa, f, z)) for f, z in prof]
            rb = [bm.verts.new((xb, f, z)) for f, z in prof]
            for k in range(len(prof) - 1):
                quad(bm, ra[k], ra[k + 1], rb[k + 1], rb[k], TRIM)
            quad(bm, ra[-1], ra[0], rb[0], rb[-1], TRIM)
            bm.faces.new(ra).material_index = TRIM
            bm.faces.new(list(reversed(rb))).material_index = TRIM
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object("cut_arch", bm)


def region_grid(surf, f_span, j_span, rows, cols, side, centre, shrink_f=0.0, shrink_j=0.0):
    """Surface points and normals over a window region in (f, j). `j_span(f)` gives (j_lo, j_hi)
    for a station, `f_span(j)` gives (f_lo, f_hi) for a ring. A centre region runs from the far
    side's j_lo over the centreline (j = 7) to the near side's j_lo in one sweep, so a screen is
    one piece of glass."""
    pts = []
    for r in range(rows + 1):
        t = r / rows
        if centre:
            tt = -1.0 + 2.0 * t
            sd = 1.0 if tt >= 0.0 else -1.0
            jj = None
        else:
            sd = side
            tt = t
        for c in range(cols + 1):
            s = c / cols
            # Iterate once: the f span depends on j and the j span on f.
            f_lo, f_hi = f_span(None)
            f = f_lo + shrink_f + (f_hi - f_lo - 2 * shrink_f) * s
            j_lo, j_hi = j_span(f)
            if centre:
                j = N_ANCHORS - 1.0 - (N_ANCHORS - 1.0 - j_lo - shrink_j) * abs(tt)
            else:
                j = j_lo + shrink_j + (j_hi - j_lo - 2 * shrink_j) * tt
            f_lo, f_hi = f_span(j)
            f = f_lo + shrink_f + (f_hi - f_lo - 2 * shrink_f) * s
            j_lo, j_hi = j_span(f)
            if centre:
                j = N_ANCHORS - 1.0 - (N_ANCHORS - 1.0 - j_lo - shrink_j) * abs(tt)
            else:
                j = j_lo + shrink_j + (j_hi - j_lo - 2 * shrink_j) * tt
            pts.append(surf.on_body(f, j, sd))
    return pts


def cut_windows(body, surf, wins):
    """Every daylight opening, one shell per boolean: a shell that self-intersects where the
    surface curves tighter than its offsets is then dropped on its own (and logged) instead of
    taking every window with it."""
    for win in wins:
        off = win.get("cut_depth", 0.05)
        for side in ((1.0,) if win["centre"] else (1.0, -1.0)):
            bm = bmesh.new()
            pts = region_grid(surf, win["f"], win["j"], win["rows"], win["cols"], side,
                              win["centre"], 0.012, win["cut_shrink_j"])
            grid_solid(bm, [p + n * off for p, n in pts], [p - n * off for p, n in pts],
                       win["rows"] + 1, win["cols"] + 1, TYRE)
            tidy(bm)
            if not boolean(body, new_object("cut_" + win["name"], bm), quiet=True):
                log("  window %s (side %+d) dropped" % (win["name"], side))


def build_glass(surf, windows, inset):
    bm = bmesh.new()
    for win in windows:
        for side in ((1.0,) if win["centre"] else (1.0, -1.0)):
            pts = region_grid(surf, win["f"], win["j"], win["rows"], win["cols"], side,
                              win["centre"])
            grid_patch(bm, [p - n * inset for p, n in pts], win["rows"] + 1, win["cols"] + 1,
                       GLASS)
    tidy(bm)
    return new_object("glass", bm)


def resample(path, step):
    """Keeps every point at least `step` from the last one kept (and always the last)."""
    if len(path) < 3:
        return path
    out = [path[0]]
    for p, n in path[1:-1]:
        if (p - out[-1][0]).length >= step:
            out.append((p, n))
    out.append(path[-1])
    return out


def clean_path(path, step=0.02):
    """Drops near-duplicate points and splits a path where a ray jumped to another surface."""
    out, cur = [], []
    for p, n in path:
        if cur and (p - cur[-1][0]).length < 0.001:
            continue
        if cur and (p - cur[-1][0]).length > step * 4.0:
            if len(cur) > 1:
                out.append(cur)
            cur = []
        cur.append((p, n))
    if len(cur) > 1:
        out.append(cur)
    return out


def cut_grooves(body, paths, width=0.0042, depth=0.0055):
    """Panel gaps: a thin solid swept along each path on the surface, cut one at a time. The
    boolean leaves a 4 mm groove whose walls and floor take the cutter's slot (trim), so the gap
    reads dark. One strip per boolean: strips cross at the corners, and a union of them - or one
    self-intersecting operand - was what once deleted a whole body."""
    hw = width * 0.5
    # A narrow trapezoid: walls rolling in to a 2 mm floor, the way two panel edges roll away
    # from each other. (A V was tried: where two of them cross, their floor edges meet edge on
    # edge and the solver left the body open, after which every later cut failed.)
    prof = [(-hw * 1.4, 0.03), (hw * 1.4, 0.03), (hw * 0.5, -depth), (-hw * 0.5, -depth)]
    for raw in paths:
        # The EXACT solver occasionally reads a strip as inside-out on a coplanar coincidence;
        # the same strip resampled a few millimetres differently goes through.
        for step in (0.04, 0.033, 0.047):
            ok = True
            for path in clean_path(resample(raw, step), step):
                bm = bmesh.new()
                sweep(bm, [p for p, _n in path], prof, TRIM, normals=[n for _p, n in path])
                tidy(bm)
                ok = boolean(body, new_object("groove", bm), quiet=True, tolerant=True) and ok
            if ok:
                break
            a, b = raw[0][0], raw[-1][0]
            log("  groove %d retried: (%.2f %.2f %.2f) -> (%.2f %.2f %.2f)"
                % (paths.index(raw), a.x, a.y, a.z, b.x, b.y, b.z))
    log("grooves cut (%d paths)" % len(paths))


def extrude_cutter(outline, axis, near, far, mat=TRIM, bevel=0.0):
    """A prism: a closed 2D outline swept along an axis ('x', 'y' or 'z') from `near` to `far`."""
    bm = bmesh.new()

    def co(a, b, w):
        if axis == "y":
            return Vector((a, w, b))
        if axis == "x":
            return Vector((w, a, b))
        return Vector((a, b, w))

    ra = [bm.verts.new(co(a, b, near)) for a, b in outline]
    rb = [bm.verts.new(co(a, b, far)) for a, b in outline]
    n = len(outline)
    for k in range(n):
        k2 = (k + 1) % n
        quad(bm, ra[k], ra[k2], rb[k2], rb[k], mat)
    bm.faces.new(ra).material_index = mat
    bm.faces.new(list(reversed(rb))).material_index = mat
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object("cut_prism", bm)


def rounded_outline(pts, radius, n=4):
    """A closed polygon with every corner rounded by `radius` (clamped to half each edge)."""
    out = []
    m = len(pts)
    for i in range(m):
        p0 = Vector(pts[i - 1])
        p1 = Vector(pts[i])
        p2 = Vector(pts[(i + 1) % m])
        a = (p0 - p1)
        b = (p2 - p1)
        la, lb = a.length, b.length
        r = min(radius, la * 0.45, lb * 0.45)
        a.normalize()
        b.normalize()
        s = p1 + a * r
        e = p1 + b * r
        for k in range(n + 1):
            t = k / n
            # quadratic Bezier with the corner as control point
            q = s * (1 - t) ** 2 + p1 * 2 * t * (1 - t) + e * t * t
            out.append((q.x, q.y))
    return out


def blade_grid(xi, xo, zi, zo, hi, ho, rows, cols, taper=None):
    """A tapered lamp blade in a front/rear view: from x_inboard to x_outboard, centre height and
    height interpolated, as an (rows+1) x (cols+1) grid of (x, z)."""
    g = []
    for r in range(rows + 1):
        v = r / rows
        row = []
        for c in range(cols + 1):
            t = c / cols
            x = xi + (xo - xi) * t
            zc = zi + (zo - zi) * t
            h = hi + (ho - hi) * t
            if taper is not None:
                h *= taper(t)
            row.append((x, zc - h * 0.5 + h * v))
        g.append(row)
    return g


def poly_grid(bottom, top, rows):
    """A grid between two polylines with the same number of points."""
    g = []
    for r in range(rows + 1):
        v = r / rows
        g.append([(b[0] + (t[0] - b[0]) * v, b[1] + (t[1] - b[1]) * v) for b, t in zip(bottom, top)])
    return g


def far_wheel(bm, cx, cy, cz, r, w, side, segs=20):
    """A plain tyre and rim face, ~250 triangles. The game draws its generated wheel over it up
    close and shrinks this one into the hub (PropFactory.tuck_body_wheels)."""
    rim_r = r * 0.72
    hw = w * 0.5
    # Tyre section, outboard to inboard, in (radius, axial) with axial positive outboard.
    prof = [(rim_r, hw * 0.86), (r * 0.93, hw), (r, hw * 0.70), (r, -hw * 0.70), (r * 0.93, -hw),
            (rim_r, -hw * 0.86)]
    rings = []
    for k in range(segs):
        a = 2 * math.pi * k / segs
        ca, sa = math.cos(a), math.sin(a)
        rings.append([bm.verts.new((cx + side * ax, cy + rr * ca, cz + rr * sa)) for rr, ax in prof])
    for k in range(segs):
        k2 = (k + 1) % segs
        for q in range(len(prof) - 1):
            quad(bm, rings[k][q], rings[k2][q], rings[k2][q + 1], rings[k][q + 1], TYRE)
    # Rim face: a dished disc, lighter than the tyre so the wheel reads at distance.
    face_x = cx + side * hw * 0.62
    hub_x = cx + side * hw * 0.30
    outer = [rings[k][0] for k in range(segs)]
    mid = []
    for k in range(segs):
        a = 2 * math.pi * k / segs
        mid.append(bm.verts.new((hub_x, cy + rim_r * 0.35 * math.cos(a), cz + rim_r * 0.35 * math.sin(a))))
    lip = []
    for k in range(segs):
        a = 2 * math.pi * k / segs
        lip.append(bm.verts.new((face_x, cy + rim_r * 0.97 * math.cos(a), cz + rim_r * 0.97 * math.sin(a))))
    for k in range(segs):
        k2 = (k + 1) % segs
        quad(bm, outer[k], outer[k2], lip[k2], lip[k], CHROME)
        quad(bm, lip[k], lip[k2], mid[k2], mid[k], CHROME)
    c = bm.verts.new((hub_x, cy, cz))
    for k in range(segs):
        k2 = (k + 1) % segs
        try:
            bm.faces.new((mid[k], mid[k2], c)).material_index = CHROME
        except ValueError:
            pass
    inner = [rings[k][-1] for k in range(segs)]
    ci = bm.verts.new((cx - side * hw * 0.5, cy, cz))
    for k in range(segs):
        k2 = (k + 1) % segs
        try:
            bm.faces.new((inner[k2], inner[k], ci)).material_index = TYRE
        except ValueError:
            pass


# --- assembly ----------------------------------------------------------------------------------------

def build(spec, detail=True):
    reset_scene()
    MATS.clear()
    MATS.extend(make_materials())
    sec = Section(spec)
    body = build_body(spec, sec)
    boolean(body, arch_cutter(spec))
    surf = Surface(body, sec)
    parts = [body]
    if detail:
        spec["details"](spec, sec, surf, body, parts)
    decimate_underbody(body)
    for o in parts:
        o.data.calc_loop_triangles()
        log("part %-14s %6d triangles" % (o.name, len(o.data.loop_triangles)))
        if os.environ.get("PROBE_PROFILE") and o.name == "body":
            prof = {}
            for v in o.data.vertices:
                k = round(v.co.y * 10.0) / 10.0
                prof[k] = max(prof.get(k, -9.0), v.co.z)
            log("  PROFILE " + " ".join("%.1f:%.2f" % (k, prof[k]) for k in sorted(prof)))
        if os.environ.get("PROBE_SLOT"):
            want = int(os.environ["PROBE_SLOT"])
            cs = []
            for poly in o.data.polygons:
                if poly.material_index == want:
                    cs.append(poly.center.copy())
            if cs:
                ys = sorted(c.y for c in cs)
                log("  SLOT %d in %s: %d faces, y %.2f..%.2f, e.g. %s" % (
                    want, o.name, len(cs), ys[0], ys[-1],
                    [tuple(round(v, 2) for v in c) for c in cs[:: max(1, len(cs) // 6)]]))
        if os.environ.get("PROBE_BOX"):
            x0, y0, z0, x1, y1, z1 = [float(v) for v in os.environ["PROBE_BOX"].split(",")]
            hits = [v.co for v in o.data.vertices
                    if x0 <= v.co.x <= x1 and y0 <= v.co.y <= y1 and z0 <= v.co.z <= z1]
            if hits:
                log("  PROBE %s: %d verts in box, e.g. %s" % (o.name, len(hits),
                                                          [tuple(round(c, 3) for c in h) for h in hits[:4]]))
    ob = join(parts)
    ob.name = "road_" + spec["name"]
    ob.data.name = ob.name
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.dissolve_degenerate(bm, dist=1e-6, edges=bm.edges)
    loose = [e for e in bm.edges if not e.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='EDGES')
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.validate(clean_customdata=False)
    shade(ob)
    return ob


FAR_TRIS = 7000


def far_wheels(spec, segs=14):
    """The far twin's wheels: a plain tyre and dished rim in each arch, drawn only past the
    distance the game stops drawing its generated wheels. Kept a little inside the generated
    tyre (radius and width), so between the far twin's hand-over and that distance - where both
    draw - it is hidden inside the real wheel instead of fighting it."""
    bm = bmesh.new()
    for f_c in (spec["front_axle"], spec["rear_axle"]):
        for side in (1.0, -1.0):
            far_wheel(bm, side * spec["wheel_x"], f_c, spec["axle_z"], spec["wheel_r"] * 0.97,
                      spec["wheel_w"] * 0.88, side, segs)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object("far_wheels", bm)


def build_far(ob, spec, target=FAR_TRIS):
    """The distance twin: the same car with every part but the paint folded into ONE surface
    ("parts", its albedo in the vertex colour's rgb and its roughness in the alpha, read by
    Vehicle's parts shader), collapsed to ~`target` triangles. Two draws where the full body
    takes seven - most cars on a street are past the distance Vehicle hands over at, and each
    surface is also a depth pre-pass draw."""
    far = ob.copy()
    far.data = ob.data.copy()
    far.name = ob.name + "_far"
    far.data.name = far.name
    bpy.context.scene.collection.objects.link(far)
    me = far.data
    col = me.color_attributes.new("Col", 'FLOAT_COLOR', 'CORNER')
    slot_col = {}
    for i, (name, c, _metal, rough, _emit) in enumerate(SLOTS):
        r = rough if name != "chrome" else 0.22
        # A metal cannot live in a non-metal surface: chrome becomes a bright satin grey there.
        cc = c if name != "chrome" else (0.62, 0.63, 0.65)
        slot_col[i] = (cc[0], cc[1], cc[2], r)
    for poly in me.polygons:
        v = slot_col[poly.material_index]
        for li in poly.loop_indices:
            col.data[li].color = v
    parts_mat = bpy.data.materials.new("parts")
    parts_mat.use_nodes = True
    nt = parts_mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    # Its own paint slot ("paint_far": Vehicle paints any slot named paint*): one material used by
    # a primitive with vertex colours and one without is a case glTF does not allow.
    paint_far = MATS[PAINT].copy()
    paint_far.name = "paint_far"
    me.materials.clear()
    me.materials.append(paint_far)
    me.materials.append(parts_mat)
    # Material index: 0 paint, 1 everything else. (The loop colours were written above, while
    # the faces still carried their own slot.)
    idx = [0 if slot == PAINT else 1 for slot in
           [p.material_index for p in ob.data.polygons]]
    for poly, k in zip(me.polygons, idx):
        poly.material_index = k
    me.calc_loop_triangles()
    n = len(me.loop_triangles)
    mod = far.modifiers.new("dec", 'DECIMATE')
    mod.decimate_type = 'COLLAPSE'
    mod.ratio = min(1.0, target / max(n, 1))
    mod.use_collapse_triangulate = True
    apply_modifiers(far)
    # The wheels go in after the collapse, already as coarse as they need to be; their faces
    # take the parts slot with the tyre's and the rim's colours.
    wh = far_wheels(spec)
    wme = wh.data
    wcol = wme.color_attributes.new("Col", 'FLOAT_COLOR', 'CORNER')
    for poly in wme.polygons:
        v = slot_col[poly.material_index]
        for li in poly.loop_indices:
            wcol.data[li].color = v
    wme.materials.clear()
    wme.materials.append(paint_far)
    wme.materials.append(parts_mat)
    for poly in wme.polygons:
        poly.material_index = 1
    far = join([far, wh])
    far.name = ob.name + "_far"
    far.data.name = far.name
    bm = bmesh.new()
    bm.from_mesh(far.data)
    bmesh.ops.dissolve_degenerate(bm, dist=1e-5, edges=bm.edges)
    loose = [e for e in bm.edges if not e.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='EDGES')
    bm.to_mesh(far.data)
    bm.free()
    far.data.validate(clean_customdata=False)
    shade(far, 40.0)
    return far


def decimate_underbody(ob, ratio=0.12):
    """The floor is a full share of the level-2 surface and nobody sees it but a car flying
    overhead, where it is a black silhouette: collapse it to a fraction, leaving everything that
    faces sideways or up untouched."""
    me = ob.data
    vg = ob.vertex_groups.new(name="under")
    idx = set()
    for p in me.polygons:
        if p.normal.z < -0.80:
            idx.update(p.vertices)
    # Keep the rim of the floor where it meets the sills and the arches: a vertex shared with any
    # face that is not floor stays put, so the silhouette does not move.
    keep = set()
    for p in me.polygons:
        if p.normal.z >= -0.80:
            keep.update(p.vertices)
    vg.add(list(idx - keep), 1.0, 'REPLACE')
    mod = ob.modifiers.new("dec", 'DECIMATE')
    mod.decimate_type = 'COLLAPSE'
    mod.ratio = ratio
    mod.vertex_group = "under"
    apply_modifiers(ob)
    g = ob.vertex_groups.get("under")
    if g is not None:
        ob.vertex_groups.remove(g)


def export(objs, path):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    kw = dict(
        filepath=path, export_format='GLB', use_selection=True,
        export_apply=True, export_materials='EXPORT', export_yup=True,
        export_normals=True, export_texcoords=False, export_tangents=False,
        export_skins=False, export_animations=False, export_cameras=False,
        export_lights=False,
    )
    try:
        bpy.ops.export_scene.gltf(export_vertex_color='ACTIVE', **kw)
    except TypeError:
        bpy.ops.export_scene.gltf(export_colors=True, **kw)


def report(ob, spec, far=None):
    me = ob.data
    me.calc_loop_triangles()
    tris = len(me.loop_triangles)
    xs = [v.co.x for v in me.vertices]
    ys = [v.co.y for v in me.vertices]
    zs = [v.co.z for v in me.vertices]
    counts = {}
    for t in me.loop_triangles:
        nm = me.materials[t.material_index].name
        counts[nm] = counts.get(nm, 0) + 1
    L = max(ys) - min(ys)
    body_w = 2.0 * max(abs(v.co.x) for v in me.vertices if v.co.z < spec["belt_probe_z"])
    print("== %s: %d triangles  L=%.3f  W(body)=%.3f  W(mirrors)=%.3f  H=%.3f  y %.3f..%.3f"
          % (spec["name"], tris, L, body_w, max(xs) - min(xs), max(zs) - min(zs), min(ys), max(ys)))
    print("   triangles per slot: %s" % counts)
    # Vehicle body space: the model is centred on the bounding box of EVERY mesh in the file (the
    # far twin's wheels included, whose tyres are the lowest thing) and that box's bottom sits at
    # `ride`.
    bottom = min(zs)
    if far is not None:
        fz = [v.co.z for v in far.data.vertices]
        fy = [v.co.y for v in far.data.vertices]
        bottom = min(bottom, min(fz))
        ys = ys + fy
    cy = (max(ys) + min(ys)) * 0.5
    road = spec["road"]
    front = -(spec["front_axle"] - cy)
    rear = -(spec["rear_axle"] - cy)
    print('   WHEEL_POSE: {"x": %.3f, "front": %.3f, "rear": %.3f, "y": %.3f, "r": %.3f, "w": %.3f, '
          '"baked": true}'
          % (spec["wheel_x"], front, rear, road + spec["axle_z"], spec["wheel_r"],
             spec["wheel_w"]))
    print('   _dims: "ride": %.3f, "road": %.3f (model bottom z %.3f; body y = model z + road)'
          % (road + bottom, road, bottom))
    print("   lamps: _dims lamp_y / tail_y = the lamp centres' model z + road")
    print("   _dims: length %.3f width %.3f height %.3f" % (L, body_w, max(zs) - min(zs)))
    return tris


# --- Cycles previews -----------------------------------------------------------------------------------

PREVIEW_PAINT = (0.16, 0.20, 0.27)


def preview_materials(ob, paint):
    for m in ob.data.materials:
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        if m.name == "paint":
            bsdf.inputs["Base Color"].default_value = (paint[0], paint[1], paint[2], 1.0)
            bsdf.inputs["Metallic"].default_value = 0.35
            bsdf.inputs["Roughness"].default_value = 0.32
            if "Coat Weight" in bsdf.inputs:
                bsdf.inputs["Coat Weight"].default_value = 1.0
                bsdf.inputs["Coat Roughness"].default_value = 0.03


def render_previews(ob, name, views, paint=PREVIEW_PAINT, samples=24, res=(960, 540)):
    os.makedirs(RENDER_DIR, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.film_transparent = False
    scene.view_settings.view_transform = 'AgX'
    preview_materials(ob, paint)
    world = bpy.data.worlds.new("w")
    scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    bg = nt.nodes.get("Background")
    # A studio gradient: dark ground, bright horizon band, blue-grey zenith. Horizon lines in the
    # paint are what show whether a surface is fair.
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp_n = nt.nodes.new("ShaderNodeValToRGB")
    cr = ramp_n.color_ramp
    cr.elements[0].position = 0.40
    cr.elements[0].color = (0.035, 0.035, 0.038, 1.0)
    cr.elements[1].position = 0.52
    cr.elements[1].color = (0.85, 0.86, 0.88, 1.0)
    e = cr.elements.new(0.62)
    e.color = (0.30, 0.34, 0.40, 1.0)
    e2 = cr.elements.new(1.0)
    e2.color = (0.16, 0.19, 0.25, 1.0)
    mapr = nt.nodes.new("ShaderNodeMapRange")
    mapr.inputs["From Min"].default_value = -1.0
    mapr.inputs["From Max"].default_value = 1.0
    nt.links.new(tc.outputs["Generated"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["Z"], mapr.inputs["Value"])
    nt.links.new(mapr.outputs["Result"], ramp_n.inputs["Fac"])
    nt.links.new(ramp_n.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 1.0
    sun_d = bpy.data.lights.new("sun", 'SUN')
    sun_d.energy = 2.2
    sun_d.angle = math.radians(3.0)
    sun = bpy.data.objects.new("sun", sun_d)
    sun.rotation_euler = (math.radians(50.0), 0.0, math.radians(140.0))
    scene.collection.objects.link(sun)
    # Ground.
    bpy.ops.mesh.primitive_plane_add(size=60.0, location=(0, 0, 0))
    ground = bpy.context.active_object
    gm = bpy.data.materials.new("ground")
    gm.use_nodes = True
    gb = gm.node_tree.nodes.get("Principled BSDF")
    gb.inputs["Base Color"].default_value = (0.20, 0.20, 0.21, 1.0)
    gb.inputs["Roughness"].default_value = 0.8
    ground.data.materials.append(gm)
    # A softbox strip overhead so the paint shows its surfacing in the reflections.
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0.0, 0.0, 6.0))
    strip = bpy.context.active_object
    strip.scale = (1.2, 9.0, 1.0)
    em = bpy.data.materials.new("softbox")
    em.use_nodes = True
    eb = em.node_tree.nodes.get("Principled BSDF")
    eb.inputs["Emission Color"].default_value = (1, 1, 1, 1)
    eb.inputs["Emission Strength"].default_value = 6.0
    eb.inputs["Base Color"].default_value = (0, 0, 0, 1)
    strip.data.materials.append(em)
    strip.visible_camera = False
    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    out = []
    for view in views:
        vname, loc, look, lens = view
        cam.location = Vector(loc)
        d = Vector(look) - Vector(loc)
        cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
        cam_data.lens = lens
        path = os.path.join(RENDER_DIR, "%s_%s.png" % (name, vname))
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        out.append(path)
        print("rendered", path)
    return out


def default_views(spec):
    L = spec["length"]
    # Framed for a 4.9 m, 1.45 m car; anything bigger (the van) pulls the camera back to fit.
    k = max(1.0, L / 4.9, spec.get("height", 1.45) / 1.45 * 0.85)
    zc = 0.62 * max(1.0, spec.get("height", 1.45) / 1.45)
    return [
        ("front3", (5.2 * k, L * 0.5 + 4.6 * k, 1.55 * k), (0.0, 0.25, zc), 50),
        ("rear3", (-5.0 * k, -L * 0.5 - 4.4 * k, 1.75 * k), (0.0, -0.25, zc * 1.1), 50),
        ("side", (9.5 * k, 0.0, 0.85 * k), (0.0, 0.0, zc * 1.15), 55),
        ("front", (0.0, L * 0.5 + 7.5 * k, 1.05 * k), (0.0, 0.0, zc), 60),
        ("rear", (0.0, -L * 0.5 - 7.5 * k, 1.15 * k), (0.0, 0.0, zc * 1.1), 60),
        ("top", (4.5 * k, 3.0 * k, 5.5 * k), (0.0, 0.0, 0.5 * k), 45),
    ]


# --- the bodies --------------------------------------------------------------------------------------

# --- detail helpers ---------------------------------------------------------------------------------

def oface(bm, verts, mat, want):
    """A face wound so its normal agrees with `want` (the surface normal it sits on)."""
    try:
        f = bm.faces.new(verts)
    except ValueError:
        return None
    f.material_index = mat
    f.normal_update()
    if f.normal.dot(want) < 0.0:
        f.normal_flip()
    return f


def oriented_grid(bm, pts, nrm, nr, nc, mat, mats=None):
    """An (nr x nc) grid of points with their outward normals; every face faces outward."""
    v = [bm.verts.new(p) for p in pts]
    for i in range(nr - 1):
        for j in range(nc - 1):
            a, b, c, d = i * nc + j, (i + 1) * nc + j, (i + 1) * nc + j + 1, i * nc + j + 1
            want = nrm[a] + nrm[b] + nrm[c] + nrm[d]
            oface(bm, (v[a], v[b], v[c], v[d]), mats(i, j) if mats else mat, want)
    return v


def rim_walls(bm, top, bottom, nrm, nr, nc, mat):
    """Walls from a panel's edge (`top` verts) down to `bottom` points, facing out of the panel."""
    vb = [bm.verts.new(p) for p in bottom]
    ring = ([(0, c) for c in range(nc)] + [(r, nc - 1) for r in range(1, nr)]
            + [(nr - 1, c) for c in range(nc - 2, -1, -1)] + [(r, 0) for r in range(nr - 2, 0, -1)])
    centre = Vector((0, 0, 0))
    for p in top:
        centre += p.co
    centre /= max(len(top), 1)
    for k in range(len(ring)):
        a = ring[k][0] * nc + ring[k][1]
        b = ring[(k + 1) % len(ring)][0] * nc + ring[(k + 1) % len(ring)][1]
        mid = (top[a].co + top[b].co) * 0.5
        oface(bm, (top[a], top[b], vb[b], vb[a]), mat, mid - centre)


def hits_2d(surf, view, grid2d, side=1.0):
    """Surface points and normals for a grid of 2D points in a view, or None if any ray misses -
    or if the hits spread more than half a metre in depth: a ray just past a rounded corner goes
    on down the flank, and a part laid over hits like that is a streak along the car."""
    pts, nrm = [], []
    for row in grid2d:
        for a, b in row:
            hit = surface_path(surf, view, [(a, b), (a, b)], side)
            if not hit:
                log("  part dropped: a %s-view ray at (%.2f, %.2f) missed the body" % (view, a, b))
                return None
            pts.append(hit[0][0])
            nrm.append(hit[0][1])
    axis = {"front": 1, "rear": 1, "side": 0, "top": 2}[view]
    depth = [p[axis] for p in pts]
    if max(depth) - min(depth) > 0.5:
        log("  part dropped: its %s-view hits spread %.2f m deep (from %s)"
            % (view, max(depth) - min(depth), tuple(round(v, 2) for v in grid2d[0][0])))
        return None
    return pts, nrm


def applied(bm, surf, view, grid2d, proud, mat, side=1.0, thickness=0.0, rim=None, mats=None):
    """A part laid on the body over a 2D grid in a view: its face `proud` off the skin and, with
    a thickness, a wall down under the skin so it reads as a part and not a decal."""
    res = hits_2d(surf, view, grid2d, side)
    if res is None:
        return False
    pts, nrm = res
    nr, nc = len(grid2d), len(grid2d[0])
    top = oriented_grid(bm, [p + n * proud for p, n in zip(pts, nrm)], nrm, nr, nc, mat, mats)
    if thickness > 0.0:
        rim_walls(bm, top, [p - n * thickness for p, n in zip(pts, nrm)], nrm, nr, nc,
                  rim if rim is not None else mat)
    return True


def fj_applied(bm, surf, f_lo, f_hi, j_lo, j_hi, rows, cols, proud, mat, side=1.0,
               thickness=0.0, rim=None, centre=False, mats=None):
    """The same over an (f, j) region; the bounds may be functions (f_lo(j), j_lo(f), ...)."""
    fl = f_lo if callable(f_lo) else (lambda j, v=f_lo: v)
    fh = f_hi if callable(f_hi) else (lambda j, v=f_hi: v)
    jl = j_lo if callable(j_lo) else (lambda f, v=j_lo: v)
    jh = j_hi if callable(j_hi) else (lambda f, v=j_hi: v)

    def fsp(j):
        jj = 6.0 if j is None else j
        return fl(jj), fh(jj)

    def jsp(f):
        return jl(f), jh(f)

    pn = region_grid(surf, fsp, jsp, rows, cols, side, centre)
    pts = [p for p, _n in pn]
    nrm = [n for _p, n in pn]
    top = oriented_grid(bm, [p + n * proud for p, n in zip(pts, nrm)], nrm, rows + 1, cols + 1,
                        mat, mats)
    if thickness > 0.0:
        rim_walls(bm, top, [p - n * thickness for p, n in zip(pts, nrm)], nrm, rows + 1,
                  cols + 1, rim if rim is not None else mat)
    return True


def wrap_band(bm, surf, end, z0, z1, proud, mat, reach=0.30, corner_r=0.20, thickness=0.05,
              rows=3, n_front=10, n_corner=6, n_side=5):
    """A bumper that wraps round the corners: one grid from the end of one flank, round its
    corner, across the face and round to the other flank. Each column is a horizontal ray -
    along the car across the face, radiating from a corner centre round the corner, across the
    car along the flank - so the band follows the plan outline instead of being a flat plate
    whose outer rays miss the corner. `end` +1 the nose, -1 the tail."""
    zm = (z0 + z1) * 0.5
    face, _n = surf.ray((0.0, end * 8.0, zm), (0.0, -end, 0.0), 16.0)
    if face is None:
        log("  bumper dropped: no face at z %.2f" % zm)
        return False
    flank, _n = surf.ray((4.0, face.y - end * (corner_r + reach + 0.1), zm), (-1.0, 0.0, 0.0), 8.0)
    if flank is None:
        log("  bumper dropped: no flank at z %.2f" % zm)
        return False
    xc = flank.x - corner_r
    fc = face.y - end * corner_r
    rays = []
    for k in range(n_front + 1):
        x = xc * k / n_front
        rays.append(((x, face.y + end * 3.0), (0.0, -end)))
    for k in range(1, n_corner):
        a = math.pi * 0.5 * k / n_corner
        d = (math.sin(a), end * math.cos(a))
        rays.append(((xc + d[0] * 3.0, fc + d[1] * 3.0), (-d[0], -d[1])))
    for k in range(n_side + 1):
        f = fc - end * reach * k / n_side
        rays.append(((xc + 3.0, f), (-1.0, 0.0)))
    grid = []
    for r in range(rows + 1):
        z = z0 + (z1 - z0) * r / rows
        row = []
        for (ox, oy), (dx, dy) in rays:
            loc, nor = surf.ray((ox, oy, z), (dx, dy, 0.0), 6.0)
            if loc is None:
                log("  bumper dropped: a ray at z %.2f missed" % z)
                return False
            row.append((loc, nor))
        # Mirror onto the other side: columns run from its flank round to the centre.
        left = [(Vector((-p.x, p.y, p.z)), Vector((-n.x, n.y, n.z))) for p, n in reversed(row[1:])]
        grid.append(left + row)
    nr, nc = len(grid), len(grid[0])
    pts = [p for row in grid for p, _n in row]
    nrm = [n for row in grid for _p, n in row]
    top = oriented_grid(bm, [p + n * proud for p, n in zip(pts, nrm)], nrm, nr, nc, mat)
    rim_walls(bm, top, [p - n * thickness for p, n in zip(pts, nrm)], nrm, nr, nc, mat)
    return True


def mirror2(grid2d):
    return [[(-a, b) for a, b in row] for row in grid2d]


def rect_grid(x0, x1, z0, z1, rows, cols):
    return [[(x0 + (x1 - x0) * c / cols, z0 + (z1 - z0) * r / rows) for c in range(cols + 1)]
            for r in range(rows + 1)]


def circle_path(cy, cz, r, a0, a1, n):
    return [(cy + r * math.cos(math.radians(a0 + (a1 - a0) * k / n)),
             cz + r * math.sin(math.radians(a0 + (a1 - a0) * k / n))) for k in range(n + 1)]


def eggcrate(bm, x0, x1, z0, z1, y_front, y_back, nv, nh, thick=0.006, mat=TRIM):
    """Fins with depth inside a mouth: a flat black face is the cheapest-looking thing a car can
    have, a mesh with depth is what a grille is."""
    depth = abs(y_front - y_back)
    yc = (y_front + y_back) * 0.5
    for k in range(nv + 1):
        x = x0 + (x1 - x0) * k / nv
        add_box(bm, (thick, depth, z1 - z0), (x, yc, (z0 + z1) * 0.5), mat)
    for k in range(nh + 1):
        z = z0 + (z1 - z0) * k / nh
        add_box(bm, (x1 - x0, depth * 0.8, thick), ((x0 + x1) * 0.5, yc - depth * 0.1, z), mat)


def arch_lips(bm, surf, s, width=0.026, height=0.009, mat=PAINT, a0=-10.0, a1=190.0, grow=0.004):
    """A rolled lip round each arch, standing proud of the side: a flush opening reads as a hole
    cut in a shell."""
    for f_c, R in ((s["front_axle"], s["arch_r"]), (s["rear_axle"], s["arch_r_rear"])):
        for side in (1.0, -1.0):
            path = []
            for yz in circle_path(f_c, s["axle_z"], R + grow, a0, a1, 44):
                loc, nor = surf.side_hit(yz[0], yz[1], side)
                if loc is not None and abs(loc.x) > s["arch_in"] + 0.1:
                    path.append((loc, nor))
            if len(path) < 4:
                continue
            n = len(path)

            def prof(i, n=n):
                t = math.sin(math.pi * min(max(i / (n - 1), 0.0), 1.0))
                k = 0.35 + 0.65 * min(1.0, t * 2.2)
                w, h = width * 0.5, height * k
                return [(-w, -0.004), (-w * 0.55, h * 0.8), (0.0, h), (w * 0.55, h * 0.8),
                        (w, -0.004)]
            pts = [p for p, _n in path]
            nrm = [nn for _p, nn in path]
            rings = sweep(bm, pts, prof, mat, closed_profile=True, caps=True, normals=nrm)


def mirror(parts, surf, s, side, root_f, root_j, head, size, glass_mat=CHROME, head_mat=PAINT):
    """A wing mirror on a stalk: a painted head (a bevelled box under one subdivision level, which
    stays a mirror and does not melt into a ball), a black stalk and a glass on its rear face."""
    bm = bmesh.new()
    root, n = surf.on_body(root_f, root_j, side)
    hx, hy, hz = head
    hc = Vector((side * hx, hy, hz))
    inner = hc + Vector((-side * size[0] * 0.42, 0.0, -size[2] * 0.12))
    path = [root - n * 0.01, root + n * 0.012, root.lerp(inner, 0.6) + Vector((0, 0, 0.01)), inner]
    prof = [(math.cos(a) * 0.022, math.sin(a) * 0.012) for a in
            [2 * math.pi * k / 10 for k in range(10)]]
    sweep(bm, path, prof, TRIM)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    parts.append(new_object("mirror_stalk", bm))
    hb = bmesh.new()
    add_box(hb, size, hc, head_mat)
    bmesh.ops.recalc_face_normals(hb, faces=hb.faces)
    hob = new_object("mirror_head", hb)
    mod = hob.modifiers.new("bev", 'BEVEL')
    mod.width = min(size) * 0.3
    mod.segments = 2
    apply_modifiers(hob)
    subsurf(hob, 1)
    parts.append(hob)
    gb = bmesh.new()
    gy = hy - size[1] * 0.5 - 0.0015
    v = [gb.verts.new((side * hx + side * sx * size[0] * 0.40, gy, hz + sz * size[2] * 0.36))
         for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    oface(gb, v, glass_mat, Vector((0, -1, 0)))
    parts.append(new_object("mirror_glass", gb))


def flush_handle(bm_cut, bm, surf, y, z, side, length=0.15, height=0.034, mat=CHROME):
    """A flush door handle: a shallow pocket with the handle lying flat in it."""
    g = [[(y - length * 0.5 + length * c / 6, z - height * 0.5 + height * r / 2) for c in range(7)]
         for r in range(3)]
    res = hits_2d(surf, "side", g, side)
    if res is None:
        return
    pts, nrm = res
    grid_solid(bm_cut, [p + n * 0.02 for p, n in zip(pts, nrm)],
               [p - n * 0.009 for p, n in zip(pts, nrm)], 3, 7, TRIM)
    gi = [[(y - length * 0.42 + length * 0.84 * c / 6, z - height * 0.28 + height * 0.56 * r / 2)
           for c in range(7)] for r in range(3)]
    res = hits_2d(surf, "side", gi, side)
    if res:
        pts, nrm = res
        oriented_grid(bm, [p - nn * 0.0015 for p, nn in zip(pts, nrm)], nrm, 3, 7, mat)


# --- the sedan --------------------------------------------------------------------------------------

def sedan():
    s = {"name": "sedan", "length": 4.90}
    s.update({
        "nose": 2.345, "tail": -2.36,
        "front_axle": 1.50, "rear_axle": -1.33, "axle_z": 0.345,
        "wheel_r": 0.345, "wheel_w": 0.235, "wheel_x": 0.797,
        "arch_r": 0.388, "arch_r_rear": 0.388, "arch_in": 0.56,
        "road": -0.177, "belt_probe_z": 0.9,
        "cowl": 1.02, "deck": -1.96, "gh_blend_front": 0.14, "gh_blend_rear": 0.12,
        "crown_at": 0.60, "tension": 1.0, "under_j": 1.0,
        "rings": [0.0, 1.0, 1.6, 2.0, 2.4, 2.85, 3.35, 3.8, 3.92, 4.0, 4.08, 4.5, 5.0, 5.5,
                  6.1, 6.6, 7.0],
        "end_steps": [0.0, 0.012, 0.03, 0.055, 0.09, 0.135, 0.19, 0.26, 0.34],
        "mid_step": 0.27,
        "extra_stations": [1.02, -1.96],
        "creases": [(4.0, 0.8, -3.0, 3.0)],
        "nose_cap": {"steps": 3, "roll": lambda j: 0.045, "dome": 0.068,
                     "lean": lambda co: 0.045 * ramp(co.z, 0.70, 0.38)},
        "tail_cap": {"steps": 3, "roll": lambda j: 0.045, "dome": 0.068,
                     "lean": lambda co: -0.035 * ramp(co.z, 0.62, 0.32)},
        "sculpt": [
            # rear haunch over the rear wheel, a lighter one over the front
            (-1.10, -1.55, 0.45, 3.6, 4.3, 0.55, 0.011),
            (1.25, 1.75, 0.35, 3.6, 4.4, 0.5, 0.006),
            # the lower door scoop between the wheels
            (0.95, -0.85, 0.35, 2.55, 3.1, 0.35, -0.012),
            # the shoulder line stands proud of the flank, its holding loops part of the way
            (3.0, -3.0, 0.0, 3.97, 4.03, 0.10, 0.005),
            # a raised centre panel on the bonnet
            (1.15, 2.10, 0.25, 6.45, 7.0, 0.30, 0.010),
        ],
        "profile": {
            "top": [(2.345, 0.706), (2.31, 0.730), (2.25, 0.756), (2.14, 0.788), (1.95, 0.826),
                    (1.70, 0.866), (1.45, 0.902), (1.25, 0.930), (1.12, 0.948), (1.06, 0.958),
                    (1.02, 0.968), (0.95, 1.004), (0.80, 1.080), (0.60, 1.182), (0.42, 1.270),
                    (0.28, 1.335), (0.18, 1.378), (0.08, 1.410), (-0.05, 1.432), (-0.20, 1.443),
                    (-0.35, 1.445), (-0.50, 1.439), (-0.65, 1.424), (-0.80, 1.400),
                    (-0.95, 1.368), (-1.15, 1.314), (-1.35, 1.250), (-1.55, 1.180),
                    (-1.72, 1.120), (-1.85, 1.082), (-1.95, 1.062), (-2.04, 1.053),
                    (-2.16, 1.053), (-2.27, 1.058), (-2.33, 1.059), (-2.36, 1.051)],
            "rail_z": [(1.15, 0.945), (1.02, 0.962), (0.92, 0.992), (0.80, 1.035), (0.65, 1.100),
                       (0.50, 1.172), (0.35, 1.240), (0.20, 1.300), (0.05, 1.346), (-0.10, 1.370),
                       (-0.30, 1.380), (-0.50, 1.376), (-0.70, 1.357), (-0.85, 1.332),
                       (-1.00, 1.300), (-1.20, 1.250), (-1.40, 1.188), (-1.60, 1.120),
                       (-1.78, 1.070), (-1.90, 1.050), (-2.00, 1.042)],
            "rail_w": [(1.15, 0.825), (1.02, 0.812), (0.85, 0.797), (0.65, 0.772), (0.45, 0.750),
                       (0.25, 0.732), (0.05, 0.720), (-0.30, 0.712), (-0.70, 0.713), (-1.00, 0.722),
                       (-1.30, 0.738), (-1.55, 0.757), (-1.80, 0.778), (-1.96, 0.788),
                       (-2.05, 0.792)],
            "belt_z": [(2.345, 0.690), (2.30, 0.728), (2.20, 0.765), (2.00, 0.815), (1.70, 0.862),
                       (1.40, 0.900), (1.15, 0.932), (1.00, 0.948), (0.80, 0.962), (0.40, 0.978),
                       (-0.20, 0.990), (-0.80, 1.004), (-1.30, 1.016), (-1.72, 1.028),
                       (-2.00, 1.033), (-2.22, 1.031), (-2.36, 1.018)],
            "belt_in": [(2.345, 0.050), (2.0, 0.060), (1.2, 0.066), (0.0, 0.068), (-1.2, 0.074),
                        (-1.8, 0.078), (-2.2, 0.072), (-2.36, 0.062)],
            "shoulder_z": [(2.345, 0.612), (2.25, 0.680), (2.05, 0.738), (1.75, 0.774),
                           (1.40, 0.792), (0.80, 0.805), (0.00, 0.815), (-0.80, 0.830),
                           (-1.40, 0.848), (-1.90, 0.862), (-2.22, 0.866), (-2.36, 0.858)],
            "width": [(2.345, 0.680), (2.325, 0.748), (2.29, 0.802), (2.23, 0.845),
                      (2.14, 0.876), (2.00, 0.900), (1.80, 0.913), (1.50, 0.918), (1.20, 0.914),
                      (0.80, 0.906), (0.30, 0.903), (-0.30, 0.905), (-0.90, 0.913),
                      (-1.33, 0.919), (-1.65, 0.915), (-1.90, 0.902), (-2.05, 0.886),
                      (-2.17, 0.862), (-2.26, 0.830), (-2.31, 0.795), (-2.34, 0.752),
                      (-2.36, 0.680)],
            "low_z": [(2.345, 0.40), (1.5, 0.40), (0.0, 0.42), (-1.33, 0.44), (-2.36, 0.46)],
            "low_in": 0.045,
            "sill_z": [(2.345, 0.262), (2.2, 0.248), (1.9, 0.232), (1.5, 0.225), (0.0, 0.215),
                       (-1.33, 0.225), (-1.9, 0.258), (-2.2, 0.292), (-2.36, 0.308)],
            "sill_in": [(2.345, 0.065), (2.0, 0.065), (1.0, 0.085), (-1.5, 0.085), (-2.36, 0.065)],
            "floor_z": [(2.345, 0.248), (2.2, 0.200), (1.9, 0.165), (1.5, 0.150), (0.0, 0.145),
                        (-1.33, 0.150), (-1.9, 0.200), (-2.2, 0.262), (-2.36, 0.290)],
            "floor_in": 0.10,
        },
    })
    s["details"] = sedan_details
    return s


def sedan_windows(s, sec):
    belt_gap, top_gap = 0.022, 0.020

    def side_j(f):
        lo = sec.j_along(f, 5.0, belt_gap)
        hi = sec.j_along(f, 6.0, top_gap, -1.0)
        if hi < lo:
            lo = hi = (lo + hi) * 0.5
        return lo, hi

    def screen_j(pillar):
        return lambda f: (sec.j_along(f, 6.0, pillar), 7.0)

    return [
        {"name": "windscreen", "centre": True, "rows": 16, "cols": 14,
         "f": lambda j: (0.140, 0.990), "j": screen_j(0.058), "cut_shrink_j": 0.02},
        {"name": "front", "centre": False, "rows": 8, "cols": 16,
         "f": lambda j: (-0.055, 0.950), "j": side_j, "cut_shrink_j": 0.035},
        {"name": "rear", "centre": False, "rows": 8, "cols": 16,
         "f": lambda j: (-1.24 + 0.20 * min(max(0.0 if j is None else (j - 5.0), 0.0), 1.0), -0.140),
         "j": side_j, "cut_shrink_j": 0.035},
        {"name": "backlight", "centre": True, "rows": 16, "cols": 12,
         "f": lambda j: (-1.930, -0.860), "j": screen_j(0.050), "cut_shrink_j": 0.02},
    ]


def sedan_details(s, sec, surf, body, parts):
    wins = sedan_windows(s, sec)
    # Windows: every opening in one operand.
    cut_windows(body, surf, wins)

    # Pockets: headlamps, grille mouth, corner intakes, plate recess, door handles.
    bmc = bmesh.new()
    bmp = bmesh.new()  # parts that sit in the pockets
    lamp = blade_grid(0.34, 0.815, 0.642, 0.626, 0.060, 0.080, 3, 18)
    for side in (1.0, -1.0):
        g = lamp if side > 0 else mirror2(lamp)
        res = hits_2d(surf, "front", g, 1.0)
        if res:
            pts, nrm = res
            grid_solid(bmc, [p + n * 0.03 for p, n in zip(pts, nrm)],
                       [p - n * 0.018 for p, n in zip(pts, nrm)], len(g), len(g[0]), TRIM)
            # Housing: gloss black; LED line along its top; two projector eyes.
            oriented_grid(bmp, [p - n * 0.015 for p, n in zip(pts, nrm)], nrm, len(g), len(g[0]),
                          GLASS)
        drl = blade_grid(0.35, 0.805, 0.665, 0.656, 0.010, 0.012, 1, 18)
        applied(bmp, surf, "front", drl if side > 0 else mirror2(drl), -0.011, LIGHT_F)
        drop = blade_grid(0.780, 0.800, 0.630, 0.630, 0.056, 0.064, 2, 1)
        applied(bmp, surf, "front", drop if side > 0 else mirror2(drop), -0.011, LIGHT_F)
        for xc in (0.50, 0.605):
            eye = rect_grid(xc - 0.032, xc + 0.032, 0.622, 0.648, 1, 3)
            applied(bmp, surf, "front", eye if side > 0 else mirror2(eye), -0.013, CHROME)
            lens = rect_grid(xc - 0.022, xc + 0.022, 0.627, 0.644, 1, 3)
            applied(bmp, surf, "front", lens if side > 0 else mirror2(lens), -0.0115, LIGHT_F)
    # The black band that joins the lamps across the nose.
    band = blade_grid(-0.345, 0.345, 0.648, 0.648, 0.036, 0.036, 2, 16)
    applied(bmp, surf, "front", band, 0.0025, GLASS, thickness=0.004)
    # Grille mouth: a wide trapezoid, fuller at the bottom, cut as a boolean prism, then an
    # egg-crate set back inside it.
    mouth = rounded_outline([(-0.47, 0.500), (0.47, 0.500), (0.61, 0.272), (-0.61, 0.272)], 0.06)
    boolean(body, extrude_cutter(mouth, "y", 2.30, 3.2))
    eggcrate(bmp, -0.64, 0.64, 0.272, 0.500, 2.40, 2.33, 40, 8, thick=0.0045)
    # Corner intakes (air curtains) with a vertical lamp strip in each.
    for side in (1.0, -1.0):
        o = [(side * 0.675, 0.305), (side * 0.745, 0.315), (side * 0.762, 0.490), (side * 0.702, 0.500)]
        boolean(body, extrude_cutter(rounded_outline(o, 0.018), "y", 2.20, 3.2))
        strip = [[(side * (0.690 + 0.012 * c), 0.33 + 0.145 * r) for c in range(2)] for r in range(2)]
        applied(bmp, surf, "front", strip, -0.035, LIGHT_F)
    # Splitter lip along the bottom of the fascia.
    lip = rect_grid(-0.66, 0.66, 0.255, 0.278, 1, 24)
    applied(bmp, surf, "front", lip, 0.008, TRIM, thickness=0.01)
    # Plate recess on the rear bumper.
    plate = rect_grid(-0.265, 0.265, 0.505, 0.645, 2, 8)
    res = hits_2d(surf, "rear", plate, 1.0)
    if res:
        pts, nrm = res
        grid_solid(bmc, [p + n * 0.02 for p, n in zip(pts, nrm)],
                   [p - n * 0.010 for p, n in zip(pts, nrm)], 3, 9, TRIM)
    # Door handles.
    for side in (1.0, -1.0):
        flush_handle(bmc, bmp, surf, 0.30, 0.880, side)
        flush_handle(bmc, bmp, surf, -0.66, 0.892, side)
    tidy(bmc)
    boolean(body, new_object("cut_pockets", bmc))

    # Panel gaps.
    paths = []
    fa, ra, R = s["front_axle"], s["rear_axle"], s["arch_r"]
    for side in (1.0, -1.0):
        paths.append(surface_path(surf, "side", [(1.00, 0.945), (0.995, 0.80), (0.985, 0.55),
                                                  (0.98, 0.30)], side))
        paths.append(surface_path(surf, "side", [(-0.098, 0.99), (-0.098, 0.30)], side))
        arc = circle_path(ra, s["axle_z"], R + 0.045, 44.3, -12.0, 14)
        rear_cut = [(-1.02, 1.012), (-1.02, arc[0][1])] + arc[1:]
        paths.append(surface_path(surf, "side", rear_cut, side))
        paths.append(surface_path(surf, "side", [(0.98, 0.30), (arc[-1][0], 0.30)], side))
        # Bonnet sides, front bumper split, rear bumper split.
        paths.append(fj_path(surf, [(1.07, 5.40), (2.325, 5.40)], side))
        paths.append(surface_path(surf, "side", [(2.215, 0.665), (2.13, 0.610), (2.03, 0.575),
                                                  (fa + R + 0.03, 0.56)], side))
        paths.append(surface_path(surf, "side", [(-2.255, 0.905), (-2.20, 0.78), (-2.05, 0.66),
                                                  (ra - R - 0.03, 0.60)], side))
        # Boot lid sides.
        paths.append(fj_path(surf, [(-1.985, 5.40), (-2.335, 5.40)], side))
        # Bonnet front edge, across the nose just before it rolls into the fascia.
        paths.append(fj_path(surf, [(2.325, 5.40), (2.325, 7.0)], side))
    paths.append(surface_path(surf, "rear", [(0.715, 1.008), (0.705, 0.902), (0.0, 0.895),
                                              (-0.705, 0.902), (-0.715, 1.008)], 1.0))
    # The rear bumper cover's top edge, right across the tail and up round each corner.
    paths.append(surface_path(surf, "rear", [(0.835, 0.83), (0.80, 0.70), (0.72, 0.655),
                                              (0.0, 0.648), (-0.72, 0.655), (-0.80, 0.70),
                                              (-0.835, 0.83)], 1.0))
    # Fuel flap, right rear quarter.
    flap = circle_path(-1.56, 0.905, 0.078, 5.0, 352.0, 24)
    paths.append(surface_path(surf, "side", flap, 1.0, step=0.015))
    cut_grooves(body, paths)

    # Glass, and what sits round it.
    parts.append(build_glass(surf, wins, 0.007))
    bmt = bmesh.new()
    belt_gap = 0.022
    for side in (1.0, -1.0):
        # B-pillar applique in gloss black, between the two side windows.
        fj_applied(bmt, surf, -0.147, -0.048, lambda f: sec.j_along(f, 5.0, belt_gap - 0.004),
                   lambda f: sec.j_along(f, 6.0, 0.016, -1.0), 6, 3, 0.002, GLASS, side,
                   thickness=0.006)
        # Chrome belt strip under the side glass.
        fj_applied(bmt, surf, lambda j: -1.23, lambda j: 0.94, lambda f: sec.j_along(f, 5.0, 0.004),
                   lambda f: sec.j_along(f, 5.0, 0.017), 1, 40, 0.0025, CHROME, side,
                   thickness=0.005)
        # Quarter-light divider.
        fj_applied(bmt, surf, -1.032, -1.010, lambda f: sec.j_along(f, 5.0, belt_gap),
                   lambda f: sec.j_along(f, 6.0, 0.02, -1.0), 5, 1, -0.004, TRIM, side)
        # Black rocker blade between the arches.
        fj_applied(bmt, surf, ra + R + 0.04, fa - R - 0.04, 1.75, 2.25, 2, 30, 0.004, TRIM, side,
                   thickness=0.008)
    # Cowl panel between the bonnet and the screen.
    fj_applied(bmt, surf, 0.990, 1.062, lambda f: sec.j_along(f, 5.0, 0.03), 7.0, 12, 3, 0.003,
               TRIM, 1.0, thickness=0.006, centre=True)
    # Tail lamps: a thin bar right across, and a lamp at each corner wrapping onto the quarter.
    bar = blade_grid(-0.56, 0.56, 0.952, 0.952, 0.024, 0.024, 1, 24)
    applied(bmt, surf, "rear", bar, 0.003, LIGHT_R, thickness=0.006)
    bar_s = blade_grid(-0.575, 0.575, 0.952, 0.952, 0.042, 0.042, 1, 24)
    applied(bmt, surf, "rear", bar_s, 0.0015, GLASS, thickness=0.004)
    for side in (1.0, -1.0):
        cl = blade_grid(0.50, 0.850, 0.935, 0.925, 0.110, 0.085, 3, 14)
        applied(bmt, surf, "rear", cl if side > 0 else mirror2(cl), 0.002, GLASS, thickness=0.005)
        top = blade_grid(0.515, 0.840, 0.968, 0.952, 0.026, 0.020, 1, 14)
        applied(bmt, surf, "rear", top if side > 0 else mirror2(top), 0.0035, LIGHT_R)
        low = blade_grid(0.60, 0.835, 0.902, 0.898, 0.016, 0.014, 1, 12)
        applied(bmt, surf, "rear", low if side > 0 else mirror2(low), 0.0035, LIGHT_R)
        side_l = blade_grid(0.818, 0.842, 0.930, 0.930, 0.070, 0.062, 2, 1)
        applied(bmt, surf, "rear", side_l if side > 0 else mirror2(side_l), 0.0035, LIGHT_R)
        refl = rect_grid(0.64, 0.74, 0.43, 0.448, 1, 4)
        applied(bmt, surf, "rear", refl if side > 0 else mirror2(refl), 0.002, LIGHT_R,
                thickness=0.004)
    # Rear diffuser.
    dif = rect_grid(-0.62, 0.62, 0.305, 0.425, 2, 20)
    applied(bmt, surf, "rear", dif, 0.006, TRIM, thickness=0.01)
    # Arch lips.
    arch_lips(bmt, surf, s)
    bmesh.ops.remove_doubles(bmt, verts=bmt.verts, dist=1e-6)
    parts.append(new_object("trims", bmt))
    bmesh.ops.remove_doubles(bmp, verts=bmp.verts, dist=1e-6)
    parts.append(new_object("inserts", bmp))
    for side in (1.0, -1.0):
        mirror(parts, surf, s, side, 0.88, 5.05, (0.985, 0.835, 1.005), (0.20, 0.085, 0.115))


SPECS = {"sedan": sedan}


# --- the compact crossover ----------------------------------------------------------------------------

def crossover():
    s = {"name": "crossover", "length": 4.60}
    s.update({
        "nose": 2.215, "tail": -2.225,
        "front_axle": 1.37, "rear_axle": -1.32, "axle_z": 0.360,
        "wheel_r": 0.360, "wheel_w": 0.230, "wheel_x": 0.800,
        "arch_r": 0.412, "arch_r_rear": 0.412, "arch_in": 0.57,
        "road": -0.196, "belt_probe_z": 1.0,
        "cowl": 1.04, "deck": -2.20, "gh_blend_front": 0.14, "gh_blend_rear": 0.05,
        "crown_at": 0.60, "tension": 1.0, "under_j": 1.0,
        "rings": [0.0, 1.0, 1.6, 2.0, 2.4, 2.85, 3.35, 3.8, 3.92, 4.0, 4.08, 4.5, 5.0, 5.5,
                  6.1, 6.6, 7.0],
        "end_steps": [0.0, 0.012, 0.03, 0.055, 0.09, 0.135, 0.19, 0.26, 0.34],
        "mid_step": 0.27,
        "extra_stations": [1.04, -1.97, -2.10],
        "creases": [(4.0, 0.75, -3.0, 3.0)],
        "nose_cap": {"steps": 3, "roll": lambda j: 0.050, "dome": 0.050,
                     "lean": lambda co: 0.035 * ramp(co.z, 0.85, 0.45)},
        "tail_cap": {"steps": 3, "roll": lambda j: 0.040, "dome": 0.035,
                     "lean": lambda co: -0.025 * ramp(co.z, 0.70, 0.40)},
        "sculpt": [
            (-1.05, -1.55, 0.40, 3.55, 4.3, 0.55, 0.010),
            (1.10, 1.65, 0.35, 3.55, 4.4, 0.50, 0.008),
            (0.95, -0.85, 0.35, 2.55, 3.1, 0.35, -0.010),
            (3.0, -3.0, 0.0, 3.97, 4.03, 0.10, 0.005),
            (1.15, 1.95, 0.22, 6.45, 7.0, 0.30, 0.010),
        ],
        "profile": {
            "top": [(2.215, 0.922), (2.18, 0.945), (2.10, 0.966), (1.95, 0.990), (1.70, 1.020),
                    (1.45, 1.046), (1.22, 1.070), (1.10, 1.084), (1.04, 1.096), (0.95, 1.142),
                    (0.80, 1.226), (0.60, 1.336), (0.42, 1.432), (0.30, 1.494), (0.20, 1.538),
                    (0.10, 1.572), (0.0, 1.598), (-0.20, 1.622), (-0.45, 1.632), (-0.80, 1.630),
                    (-1.20, 1.618), (-1.55, 1.600), (-1.80, 1.582), (-1.90, 1.572),
                    (-1.935, 1.545), (-1.98, 1.480), (-2.04, 1.380), (-2.10, 1.270),
                    (-2.15, 1.180), (-2.185, 1.120), (-2.21, 1.085), (-2.225, 1.068)],
            "rail_z": [(1.20, 1.060), (1.04, 1.088), (0.95, 1.120), (0.80, 1.190),
                       (0.60, 1.292), (0.40, 1.382), (0.25, 1.442), (0.10, 1.494), (-0.05, 1.528),
                       (-0.30, 1.552), (-0.70, 1.560), (-1.10, 1.550), (-1.45, 1.528),
                       (-1.70, 1.503), (-1.86, 1.480), (-1.95, 1.428), (-2.02, 1.345),
                       (-2.08, 1.250), (-2.14, 1.160), (-2.19, 1.100), (-2.225, 1.075)],
            "rail_w": [(1.20, 0.838), (1.04, 0.825), (0.80, 0.800), (0.50, 0.778),
                       (0.20, 0.764), (-0.20, 0.758), (-1.00, 0.758), (-1.60, 0.758),
                       (-1.95, 0.752), (-2.10, 0.752), (-2.225, 0.758)],
            "belt_z": [(2.215, 0.900), (2.10, 0.945), (1.90, 0.995), (1.60, 1.035),
                       (1.30, 1.065), (1.04, 1.085), (0.60, 1.100), (0.0, 1.115), (-0.80, 1.132),
                       (-1.20, 1.146), (-1.45, 1.172), (-1.70, 1.200), (-1.95, 1.212),
                       (-2.12, 1.150), (-2.225, 1.080)],
            "belt_in": [(2.215, 0.050), (1.9, 0.058), (0.0, 0.062), (-1.9, 0.066),
                        (-2.225, 0.055)],
            "shoulder_z": [(2.215, 0.800), (2.00, 0.858), (1.70, 0.882), (1.00, 0.892),
                           (0.00, 0.902), (-1.00, 0.916), (-1.80, 0.930), (-2.10, 0.932),
                           (-2.225, 0.922)],
            "width": [(2.215, 0.700), (2.195, 0.765), (2.16, 0.815), (2.10, 0.855),
                      (2.00, 0.885), (1.85, 0.905), (1.60, 0.921), (1.37, 0.926),
                      (1.10, 0.922), (0.50, 0.917), (-0.50, 0.917), (-1.00, 0.922),
                      (-1.32, 0.927), (-1.60, 0.924), (-1.85, 0.913), (-2.00, 0.895),
                      (-2.12, 0.866), (-2.19, 0.830), (-2.225, 0.770)],
            "low_z": [(2.215, 0.52), (0.0, 0.50), (-2.225, 0.54)],
            "low_in": 0.035,
            "sill_z": [(2.215, 0.400), (2.00, 0.370), (1.70, 0.330), (1.37, 0.312),
                       (0.0, 0.300), (-1.32, 0.312), (-1.70, 0.350), (-2.00, 0.400),
                       (-2.225, 0.430)],
            "sill_in": [(2.215, 0.065), (1.8, 0.07), (-1.8, 0.07), (-2.225, 0.065)],
            "floor_z": [(2.215, 0.380), (2.00, 0.330), (1.70, 0.255), (1.37, 0.222),
                        (0.0, 0.215), (-1.32, 0.222), (-1.70, 0.282), (-2.00, 0.360),
                        (-2.225, 0.400)],
            "floor_in": 0.10,
        },
    })
    s["details"] = crossover_details
    return s


def crossover_windows(s, sec):
    belt_gap, top_gap = 0.022, 0.020

    def side_j(f):
        lo = sec.j_along(f, 5.0, belt_gap)
        hi = sec.j_along(f, 6.0, top_gap, -1.0)
        if hi < lo:
            lo = hi = (lo + hi) * 0.5
        return lo, hi

    def screen_j(pillar):
        return lambda f: (sec.j_along(f, 6.0, pillar), 7.0)

    return [
        {"name": "windscreen", "centre": True, "rows": 16, "cols": 14,
         "f": lambda j: (0.050, 1.010), "j": screen_j(0.060), "cut_shrink_j": 0.02},
        {"name": "front", "centre": False, "rows": 8, "cols": 16,
         "f": lambda j: (-0.235, 0.975), "j": side_j, "cut_shrink_j": 0.035},
        {"name": "rear", "centre": False, "rows": 8, "cols": 12,
         "f": lambda j: (-1.130, -0.330), "j": side_j, "cut_shrink_j": 0.035},
        {"name": "quarter", "centre": False, "rows": 8, "cols": 12,
         "f": lambda j: (-2.030, -1.235), "j": side_j, "cut_shrink_j": 0.035},
        {"name": "backlight", "centre": True, "rows": 14, "cols": 8,
         "f": lambda j: (-2.185, -1.990), "j": screen_j(0.055), "cut_shrink_j": 0.02},
    ]


def cladding(bm, surf, s, width=0.070, height=0.014):
    """Black plastic arch flares: a flat band round each arch, standing proud of the side."""
    for f_c, R in ((s["front_axle"], s["arch_r"]), (s["rear_axle"], s["arch_r_rear"])):
        for side in (1.0, -1.0):
            path = []
            for yz in circle_path(f_c, s["axle_z"], R + width * 0.5 - 0.004, -12.0, 192.0, 40):
                loc, nor = surf.side_hit(yz[0], yz[1], side)
                if loc is not None and abs(loc.x) > s["arch_in"] + 0.1:
                    path.append((loc, nor))
            if len(path) < 4:
                continue
            w, h = width * 0.5, height
            prof = [(-w, -0.006), (-w, h * 0.55), (-w * 0.6, h), (w * 0.75, h), (w, h * 0.35),
                    (w, -0.006)]
            sweep(bm, [p for p, _n in path], prof, TRIM, normals=[n for _p, n in path])


def crossover_details(s, sec, surf, body, parts):
    wins = crossover_windows(s, sec)
    cut_windows(body, surf, wins)

    bmc = bmesh.new()
    bmp = bmesh.new()
    # Headlamps: slim, high, under the bonnet edge.
    lamp = blade_grid(0.40, 0.835, 0.845, 0.832, 0.058, 0.078, 3, 18)
    for side in (1.0, -1.0):
        g = lamp if side > 0 else mirror2(lamp)
        res = hits_2d(surf, "front", g, 1.0)
        if res:
            pts, nrm = res
            grid_solid(bmc, [p + n * 0.03 for p, n in zip(pts, nrm)],
                       [p - n * 0.018 for p, n in zip(pts, nrm)], len(g), len(g[0]), TRIM)
            oriented_grid(bmp, [p - n * 0.015 for p, n in zip(pts, nrm)], nrm, len(g), len(g[0]),
                          GLASS)
        drl = blade_grid(0.41, 0.825, 0.868, 0.860, 0.010, 0.012, 1, 18)
        applied(bmp, surf, "front", drl if side > 0 else mirror2(drl), -0.011, LIGHT_F)
        for xc in (0.55, 0.66):
            eye = rect_grid(xc - 0.034, xc + 0.034, 0.822, 0.850, 1, 3)
            applied(bmp, surf, "front", eye if side > 0 else mirror2(eye), -0.013, CHROME)
            lens = rect_grid(xc - 0.024, xc + 0.024, 0.827, 0.845, 1, 3)
            applied(bmp, surf, "front", lens if side > 0 else mirror2(lens), -0.0115, LIGHT_F)
    # Upper grille: a tall trapezoid between the lamps with an egg-crate in it.
    # A shield: narrow under the lamp band, fullest a third of the way down.
    mouth = rounded_outline([(-0.33, 0.785), (0.33, 0.785), (0.48, 0.655), (0.43, 0.530),
                             (-0.43, 0.530), (-0.48, 0.655)], 0.04)
    boolean(body, extrude_cutter(mouth, "y", 2.18, 3.2))
    eggcrate(bmp, -0.50, 0.50, 0.530, 0.785, 2.27, 2.20, 30, 8, thick=0.0045)
    # The gloss black band that joins the lamps across the nose.
    band = blade_grid(-0.405, 0.405, 0.848, 0.848, 0.030, 0.030, 2, 16)
    applied(bmp, surf, "front", band, 0.0025, GLASS, thickness=0.004)
    # Lower intake in the black lower bumper.
    low = rounded_outline([(-0.46, 0.440), (0.46, 0.440), (0.42, 0.370), (-0.42, 0.370)], 0.02)
    boolean(body, extrude_cutter(low, "y", 2.16, 3.2))
    eggcrate(bmp, -0.48, 0.48, 0.370, 0.440, 2.25, 2.19, 16, 1)
    for side in (1.0, -1.0):
        o = [(side * 0.62, 0.43), (side * 0.74, 0.44), (side * 0.75, 0.53), (side * 0.63, 0.52)]
        boolean(body, extrude_cutter(rounded_outline(o, 0.015), "y", 2.08, 3.2))
        fog = [[(side * (0.645 + 0.08 * c), 0.470 + 0.018 * r) for c in range(2)] for r in range(2)]
        applied(bmp, surf, "front", fog, -0.03, LIGHT_F)
    # Black lower bumper band and a satin skid plate.
    band = rect_grid(-0.78, 0.78, 0.36, 0.52, 2, 26)
    applied(bmp, surf, "front", band, 0.004, TRIM, thickness=0.008)
    skid = rect_grid(-0.44, 0.44, 0.405, 0.43, 1, 12)
    applied(bmp, surf, "front", skid, 0.010, CHROME, thickness=0.006)
    # Plate recess on the tailgate.
    plate = rect_grid(-0.265, 0.265, 0.80, 0.94, 2, 8)
    res = hits_2d(surf, "rear", plate, 1.0)
    if res:
        pts, nrm = res
        grid_solid(bmc, [p + n * 0.02 for p, n in zip(pts, nrm)],
                   [p - n * 0.010 for p, n in zip(pts, nrm)], 3, 9, TRIM)
    for side in (1.0, -1.0):
        flush_handle(bmc, bmp, surf, 0.36, 0.975, side, mat=PAINT)
        flush_handle(bmc, bmp, surf, -0.74, 0.988, side, mat=PAINT)
    tidy(bmc)
    boolean(body, new_object("cut_pockets", bmc))

    paths = []
    fa, ra, R = s["front_axle"], s["rear_axle"], s["arch_r"]
    for side in (1.0, -1.0):
        paths.append(surface_path(surf, "side", [(1.00, 1.05), (0.99, 0.80), (0.98, 0.60),
                                                  (0.975, 0.42)], side))
        paths.append(surface_path(surf, "side", [(-0.285, 1.08), (-0.285, 0.42)], side))
        arc = circle_path(ra, s["axle_z"], R + 0.070, 50.0, 8.0, 10)
        rear_cut = [(-1.180, 1.10), (-1.180, arc[0][1])] + arc[1:]
        paths.append(surface_path(surf, "side", rear_cut, side))
        paths.append(surface_path(surf, "side", [(0.975, 0.42), (arc[-1][0], 0.42)], side))
        paths.append(fj_path(surf, [(1.03, 5.40), (2.195, 5.40)], side))
        paths.append(fj_path(surf, [(2.195, 5.40), (2.195, 7.0)], side))
    # The tailgate: up each side of the rear window and across under it at the bumper.
    paths.append(surface_path(surf, "rear", [(0.64, 1.30), (0.66, 0.99), (0.66, 0.66), (0.0, 0.655),
                                              (-0.66, 0.66), (-0.66, 0.99), (-0.64, 1.30)], 1.0))
    flap = circle_path(-1.58, 1.00, 0.075, 5.0, 352.0, 24)
    paths.append(surface_path(surf, "side", flap, 1.0, step=0.015))
    cut_grooves(body, paths)

    parts.append(build_glass(surf, wins, 0.007))
    bmt = bmesh.new()
    for side in (1.0, -1.0):
        # Floating roof: B, C and D pillars in gloss black.
        for f0, f1 in ((-0.330, -0.235), (-1.235, -1.130)):
            fj_applied(bmt, surf, f0, f1, lambda f: sec.j_along(f, 5.0, 0.018),
                       lambda f: sec.j_along(f, 6.0, 0.016, -1.0), 6, 3, 0.002, GLASS, side,
                       thickness=0.006)
        fj_applied(bmt, surf, -2.13, -2.030, lambda f: sec.j_along(f, 5.0, 0.018),
                   lambda f: sec.j_along(f, 6.0, 0.012, -1.0), 6, 4, 0.002, GLASS, side,
                   thickness=0.006)
        # Belt trim.
        fj_applied(bmt, surf, lambda j: -2.04, lambda j: 0.965, lambda f: sec.j_along(f, 5.0, 0.004),
                   lambda f: sec.j_along(f, 5.0, 0.017), 1, 44, 0.0025, CHROME, side,
                   thickness=0.005)
        # Black rocker cladding between the arches.
        fj_applied(bmt, surf, ra + R + 0.03, fa - R - 0.03, 1.6, 2.75, 3, 30, 0.006, TRIM, side,
                   thickness=0.010)
        # Roof rail: a low bar on two feet along each side of the roof.
        rail = fj_path(surf, [(-0.05, 6.30), (-1.85, 6.30)], side, step=0.05)
        if len(rail) > 3:
            pts = [p + n * 0.045 for p, n in rail]
            prof = [(-0.013, -0.012), (0.013, -0.012), (0.011, 0.010), (-0.011, 0.010)]
            sweep(bmt, pts, prof, TRIM, normals=[n for _p, n in rail])
            for k in (1, len(rail) // 2, len(rail) - 2):
                p, n = rail[k]
                add_box(bmt, (0.03, 0.08, 0.05), p + n * 0.02, TRIM)
    fj_applied(bmt, surf, 1.010, 1.080, lambda f: sec.j_along(f, 5.0, 0.03), 7.0, 12, 3, 0.003,
               TRIM, 1.0, thickness=0.006, centre=True)
    # Roof spoiler over the rear window.
    fj_applied(bmt, surf, -1.985, -1.90, lambda f: sec.j_along(f, 6.0, 0.03), 7.0, 12, 2,
               0.012, PAINT, 1.0, thickness=0.02, centre=True)
    # Tail lamps: a bar across the tailgate and a lamp wrapping each corner.
    bar = blade_grid(-0.58, 0.58, 1.045, 1.045, 0.022, 0.022, 1, 24)
    applied(bmt, surf, "rear", bar, 0.003, LIGHT_R, thickness=0.006)
    bar_s = blade_grid(-0.60, 0.60, 1.045, 1.045, 0.040, 0.040, 1, 24)
    applied(bmt, surf, "rear", bar_s, 0.0015, GLASS, thickness=0.004)
    for side in (1.0, -1.0):
        cl = blade_grid(0.54, 0.87, 1.035, 1.025, 0.13, 0.11, 3, 14)
        applied(bmt, surf, "rear", cl if side > 0 else mirror2(cl), 0.002, GLASS, thickness=0.005)
        top = blade_grid(0.555, 0.86, 1.070, 1.058, 0.024, 0.020, 1, 14)
        applied(bmt, surf, "rear", top if side > 0 else mirror2(top), 0.0035, LIGHT_R)
        low = blade_grid(0.62, 0.855, 0.990, 0.985, 0.016, 0.014, 1, 12)
        applied(bmt, surf, "rear", low if side > 0 else mirror2(low), 0.0035, LIGHT_R)
        refl = rect_grid(0.64, 0.76, 0.50, 0.518, 1, 4)
        applied(bmt, surf, "rear", refl if side > 0 else mirror2(refl), 0.009, LIGHT_R,
                thickness=0.004)
    # Black lower bumper with a satin skid plate.
    rb = rect_grid(-0.76, 0.76, 0.42, 0.58, 2, 26)
    applied(bmt, surf, "rear", rb, 0.005, TRIM, thickness=0.01)
    rs = rect_grid(-0.40, 0.40, 0.44, 0.47, 1, 12)
    applied(bmt, surf, "rear", rs, 0.012, CHROME, thickness=0.006)
    cladding(bmt, surf, s)
    bmesh.ops.remove_doubles(bmt, verts=bmt.verts, dist=1e-6)
    parts.append(new_object("trims", bmt))
    bmesh.ops.remove_doubles(bmp, verts=bmp.verts, dist=1e-6)
    parts.append(new_object("inserts", bmp))
    for side in (1.0, -1.0):
        mirror(parts, surf, s, side, 0.90, 5.05, (1.00, 0.855, 1.110), (0.22, 0.090, 0.130))


SPECS["crossover"] = crossover


# --- the full-size pickup -----------------------------------------------------------------------------

def pickup():
    """A crew-cab full-size pickup. The proportions are the class's, not a sedan's (the first
    pass read as a sedan greenhouse on a long body): a TALL square cab (roof 1.98 m, beltline
    1.38 m, a near-vertical back), a long flat bonnet high at the front (1.30 m) over an upright
    face, and one horizontal line from the bonnet edge along the belt to the bed rails."""
    s = {"name": "pickup", "length": 5.90}
    s.update({
        "nose": 2.905, "tail": -2.995,
        "front_axle": 1.95, "rear_axle": -1.66, "axle_z": 0.390,
        "wheel_r": 0.390, "wheel_w": 0.260, "wheel_x": 0.880,
        "arch_r": 0.455, "arch_r_rear": 0.455, "arch_in": 0.62,
        "road": -0.206, "belt_probe_z": 1.30,
        "cowl": 1.12, "deck": -1.105, "gh_blend_front": 0.14, "gh_blend_rear": 0.03,
        "crown_at": 0.60, "tension": 1.0, "under_j": 1.0,
        "rings": [0.0, 1.0, 1.6, 2.1, 2.85, 3.35, 3.8, 3.92, 4.0, 4.08, 4.5, 4.9, 5.0,
                  5.1, 5.6, 6.2, 7.0],
        "end_steps": [0.0, 0.012, 0.03, 0.06, 0.10, 0.16, 0.24],
        "mid_step": 0.50,
        # Holding stations either side of every corner in the side profile (the cowl, the
        # header, the roof edge over the back), each corner loop creased below.
        "extra_stations": [1.16, 1.12, 1.08, 0.88, 0.60, 0.535, 0.48, -0.925, -0.96, -0.995,
                           -1.035, -1.07, -1.095, -1.115, -1.14, -1.18],
        "station_creases": [(1.12, 0.6, 5.2, 7.0), (0.535, 0.6, 5.6, 7.0),
                            (-0.96, 0.75, 5.6, 7.0)],
        # The shoulder, and the belt made crisp along the bonnet's edge and the bed rails, so the
        # truck's one horizontal line is a line and not a roll.
        "creases": [(4.0, 0.6, -3.1, 3.1), (5.0, 0.85, 1.14, 3.1), (5.0, 0.85, -3.1, -1.13)],
        "nose_cap": {"steps": 3, "roll": lambda j: 0.034, "dome": 0.018},
        "tail_cap": {"steps": 3, "roll": lambda j: 0.024, "dome": 0.008},
        "sculpt": [
            (3.0, -3.0, 0.0, 3.97, 4.03, 0.10, 0.004),
            # the power dome on the bonnet, and the lower door feature
            (1.35, 2.60, 0.22, 6.30, 7.0, 0.30, 0.022),
            (1.00, -1.00, 0.30, 2.50, 2.95, 0.30, -0.008),
        ],
        "profile": {
            "top": [(2.905, 1.268), (2.885, 1.288), (2.85, 1.298), (2.70, 1.310), (2.40, 1.326),
                    (2.00, 1.340), (1.60, 1.352), (1.35, 1.360), (1.20, 1.366), (1.12, 1.378),
                    (1.05, 1.440), (0.95, 1.535), (0.85, 1.630), (0.75, 1.725), (0.66, 1.810),
                    (0.60, 1.868), (0.55, 1.908), (0.50, 1.936), (0.42, 1.956), (0.25, 1.970),
                    (-0.20, 1.978), (-0.70, 1.976), (-0.90, 1.968), (-0.96, 1.958),
                    (-1.00, 1.936), (-1.025, 1.895), (-1.045, 1.820), (-1.06, 1.730),
                    (-1.075, 1.620), (-1.09, 1.500), (-1.105, 1.418), (-1.12, 1.390),
                    (-1.15, 1.384), (-2.00, 1.384), (-2.95, 1.384), (-2.995, 1.380)],
            "rail_z": [(1.20, 1.366), (1.12, 1.376), (1.05, 1.432), (0.95, 1.522),
                       (0.85, 1.614), (0.75, 1.704), (0.66, 1.784), (0.60, 1.836), (0.55, 1.870),
                       (0.48, 1.892), (0.30, 1.906), (-0.30, 1.912), (-0.80, 1.908),
                       (-0.93, 1.900), (-0.98, 1.884), (-1.01, 1.850), (-1.035, 1.790),
                       (-1.055, 1.700), (-1.07, 1.600), (-1.085, 1.490), (-1.10, 1.410),
                       (-1.12, 1.386)],
            "rail_w": [(1.20, 0.955), (1.12, 0.950), (0.80, 0.935), (0.50, 0.922),
                       (0.0, 0.918), (-0.70, 0.918), (-1.00, 0.922), (-1.10, 0.950),
                       (-1.20, 0.975)],
            "belt_z": [(2.905, 1.250), (2.88, 1.270), (2.80, 1.280), (2.40, 1.302),
                       (2.00, 1.318), (1.60, 1.332), (1.20, 1.346), (0.60, 1.360),
                       (0.00, 1.368), (-0.60, 1.374), (-1.10, 1.378), (-2.90, 1.380),
                       (-2.995, 1.376)],
            "belt_in": [(2.905, 0.012), (1.20, 0.014), (0.0, 0.022), (-1.10, 0.014),
                        (-2.995, 0.010)],
            "shoulder_z": [(2.905, 1.080), (2.70, 1.150), (2.30, 1.185), (1.50, 1.200),
                           (0.0, 1.205), (-1.50, 1.210), (-2.80, 1.212), (-2.995, 1.205)],
            "width": [(2.905, 0.940), (2.895, 0.972), (2.87, 0.992), (2.80, 1.004),
                      (2.55, 1.010), (2.30, 1.012), (1.95, 1.014), (1.40, 1.010),
                      (0.50, 1.006), (-0.50, 1.006), (-1.20, 1.008), (-1.66, 1.012),
                      (-2.40, 1.010), (-2.85, 1.004), (-2.96, 0.994), (-2.995, 0.975)],
            "low_z": 0.78,
            "low_in": 0.012,
            "sill_z": [(2.905, 0.440), (2.70, 0.450), (2.30, 0.450), (1.95, 0.445),
                       (0.0, 0.435), (-1.66, 0.445), (-2.40, 0.500), (-2.995, 0.490)],
            "sill_in": 0.045,
            "floor_z": [(2.905, 0.420), (2.70, 0.380), (2.30, 0.330), (1.95, 0.290),
                        (0.0, 0.280), (-1.66, 0.290), (-2.40, 0.460), (-2.995, 0.470)],
            "floor_in": 0.12,
        },
    })
    s["details"] = pickup_details
    return s


def pickup_windows(s, sec):
    belt_gap, top_gap = 0.024, 0.022

    def side_j(f):
        lo = sec.j_along(f, 5.0, belt_gap)
        hi = sec.j_along(f, 6.0, top_gap, -1.0)
        if hi < lo:
            lo = hi = (lo + hi) * 0.5
        return lo, hi

    def screen_j(pillar):
        return lambda f: (sec.j_along(f, 6.0, pillar), 7.0)

    return [
        {"name": "windscreen", "centre": True, "rows": 16, "cols": 12,
         "f": lambda j: (0.530, 1.090), "j": screen_j(0.065), "cut_shrink_j": 0.02},
        {"name": "front", "centre": False, "rows": 8, "cols": 14,
         "f": lambda j: (-0.065, 1.075), "j": side_j, "cut_shrink_j": 0.035},
        {"name": "rear", "centre": False, "rows": 8, "cols": 12,
         "f": lambda j: (-0.905, -0.165), "j": side_j, "cut_shrink_j": 0.035},
    ]


def pickup_details(s, sec, surf, body, parts):
    wins = pickup_windows(s, sec)
    cut_windows(body, surf, wins)
    # The bed: hollowed out of the loft (1.71 m inside, rails 10 cm thick), liner-black walls
    # and floor from the cutter; and the gap between the cab and the bed, right through the body
    # above the frame.
    bed = bmesh.new()
    add_box(bed, (1.812, 1.71, 1.6), (0.0, -2.07, 0.86 + 0.8), TRIM)
    boolean(body, new_object("cut_bed", bed))
    gap = bmesh.new()
    add_box(gap, (2.6, 0.024, 1.6), (0.0, -1.130, 0.66 + 0.8), TRIM)
    boolean(body, new_object("cut_cabgap", gap))
    # The rear window: the cab back is near vertical, so a straight pocket through it.
    rw = rounded_outline([(-0.60, 1.855), (0.60, 1.855), (0.63, 1.505), (-0.63, 1.505)], 0.05)
    boolean(body, extrude_cutter(rw, "y", -1.40, -0.995, mat=TYRE))
    rwg = poly_grid([(x * 0.65 / 6.0, 1.488) for x in range(-6, 7)],
                    [(x * 0.62 / 6.0, 1.872) for x in range(-6, 7)], 4)
    bmr = bmesh.new()
    applied(bmr, surf, "rear", rwg, -0.010, GLASS)
    for x in (-0.22, 0.22):
        applied(bmr, surf, "rear", rect_grid(x - 0.012, x + 0.012, 1.505, 1.855, 3, 1), -0.006,
                TRIM)
    parts.append(new_object("rear_window", bmr))

    bmc = bmesh.new()
    bmp = bmesh.new()
    # The face: one big grille opening between the lamps and the bumper, the lamps set into its
    # top corners, a heavy satin surround and a satin crossbar tying the lamps together.
    mouth = rounded_outline([(-0.80, 1.222), (0.80, 1.222), (0.80, 0.655), (-0.80, 0.655)], 0.045)
    boolean(body, extrude_cutter(mouth, "y", 2.80, 3.5))
    eggcrate(bmp, -0.81, 0.81, 0.655, 1.222, 2.905, 2.845, 26, 9, thick=0.010)
    # Two more satin slats across the lower grille.
    for z in (0.760, 0.865):
        add_box(bmp, (1.56, 0.03, 0.028), (0.0, 2.918, z), CHROME)
    frame = [(0.835, 1.250), (0.835, 0.628), (-0.835, 0.628), (-0.835, 1.250), (0.835, 1.250)]
    fp = surface_path(surf, "front", frame, 1.0, step=0.03)
    if len(fp) > 4:
        prof = [(-0.030, -0.004), (-0.022, 0.020), (0.022, 0.020), (0.030, -0.004)]
        sweep(bmp, [p for p, _n in fp], prof, CHROME, normals=[n for _p, n in fp])
    bar = rect_grid(-0.51, 0.51, 0.975, 1.030, 1, 12)
    applied(bmp, surf, "front", bar, 0.006, CHROME, thickness=0.07)
    for side in (1.0, -1.0):
        def sd(g, side=side):
            return g if side > 0 else mirror2(g)
        # The lamp: a gloss black block in the corner of the opening...
        applied(bmp, surf, "front", sd(rect_grid(0.500, 0.800, 0.880, 1.215, 4, 6)), 0.004,
                GLASS, thickness=0.07)
        # ...an L of LED along its top and down its outer edge...
        applied(bmp, surf, "front", sd(rect_grid(0.515, 0.785, 1.186, 1.202, 1, 8)), 0.010,
                LIGHT_F)
        applied(bmp, surf, "front", sd(rect_grid(0.769, 0.785, 0.900, 1.186, 5, 1)), 0.010,
                LIGHT_F)
        # ...two projector eyes, and an amber-less clear bar for the indicator.
        for xc in (0.570, 0.665):
            applied(bmp, surf, "front", sd(rect_grid(xc - 0.042, xc + 0.042, 1.060, 1.165, 2, 3)),
                    0.008, CHROME)
            applied(bmp, surf, "front", sd(rect_grid(xc - 0.031, xc + 0.031, 1.071, 1.154, 2, 3)),
                    0.0095, LIGHT_F)
        # The indicator and a second LED line below the eyes.
        applied(bmp, surf, "front", sd(rect_grid(0.520, 0.750, 0.990, 1.008, 1, 6)), 0.009,
                LIGHT_F)
        applied(bmp, surf, "front", sd(rect_grid(0.520, 0.750, 0.905, 0.945, 1, 6)), 0.008,
                CHROME)
    # Bumper: a massive satin blade right across, proud of the face, a black valance under it.
    wrap_band(bmp, surf, 1.0, 0.470, 0.645, 0.050, CHROME, reach=0.26, corner_r=0.14,
              thickness=0.07)
    wrap_band(bmp, surf, 1.0, 0.440, 0.470, 0.030, TRIM, reach=0.20, corner_r=0.14,
              thickness=0.05, rows=1)
    for side in (1.0, -1.0):
        fog = rect_grid(0.66, 0.80, 0.530, 0.580, 1, 3)
        applied(bmp, surf, "front", fog if side > 0 else mirror2(fog), 0.052, LIGHT_F)
        hook = rect_grid(0.40, 0.48, 0.448, 0.466, 1, 2)
        applied(bmp, surf, "front", hook if side > 0 else mirror2(hook), 0.040, CHROME,
                thickness=0.03)
    # Rear step bumper.
    wrap_band(bmp, surf, -1.0, 0.500, 0.710, 0.055, CHROME, reach=0.16, corner_r=0.10,
              thickness=0.075)
    for side in (1.0, -1.0):
        flush_handle(bmc, bmp, surf, 0.33, 1.245, side, length=0.19, height=0.045)
        flush_handle(bmc, bmp, surf, -0.56, 1.250, side, length=0.19, height=0.045)
    # Tailgate handle recess.
    th = rect_grid(-0.13, 0.13, 1.265, 1.315, 1, 4)
    res = hits_2d(surf, "rear", th, 1.0)
    if res:
        pts, nrm = res
        grid_solid(bmc, [p + n * 0.02 for p, n in zip(pts, nrm)],
                   [p - n * 0.012 for p, n in zip(pts, nrm)], 2, 5, TRIM)
    tidy(bmc)
    boolean(body, new_object("cut_pockets", bmc))

    paths = []
    fa, ra, R = s["front_axle"], s["rear_axle"], s["arch_r"]
    for side in (1.0, -1.0):
        paths.append(surface_path(surf, "side", [(1.080, 1.340), (1.070, 1.00), (1.062, 0.75),
                                                  (1.058, 0.50)], side))
        paths.append(surface_path(surf, "side", [(-0.115, 1.360), (-0.115, 0.50)], side))
        paths.append(surface_path(surf, "side", [(-0.985, 1.370), (-0.985, 0.50)], side))
        paths.append(surface_path(surf, "side", [(1.058, 0.50), (-0.985, 0.50)], side))
        paths.append(fj_path(surf, [(1.14, 5.40), (2.875, 5.40)], side))
        paths.append(fj_path(surf, [(2.875, 5.40), (2.875, 7.0)], side))
    # Tailgate outline on the back.
    paths.append(surface_path(surf, "rear", [(0.87, 1.372), (0.87, 0.74), (0.0, 0.74),
                                              (-0.87, 0.74), (-0.87, 1.372)], 1.0))
    flap = circle_path(-1.50, 1.12, 0.080, 5.0, 352.0, 24)
    paths.append(surface_path(surf, "side", flap, -1.0, step=0.015))
    cut_grooves(body, paths)

    parts.append(build_glass(surf, wins, 0.008))
    bmt = bmesh.new()
    for side in (1.0, -1.0):
        fj_applied(bmt, surf, -0.165, -0.065, lambda f: sec.j_along(f, 5.0, 0.020),
                   lambda f: sec.j_along(f, 6.0, 0.018, -1.0), 12, 3, 0.004, GLASS, side,
                   thickness=0.008)
        # Running board between the arches.
        rb_path = surface_path(surf, "side", [(fa - R - 0.10, 0.47), (ra + R + 0.10, 0.47)], side,
                               step=0.08)
        if len(rb_path) > 2:
            pts = [p + n * 0.10 for p, n in rb_path]
            prof = [(-0.07, -0.030), (0.07, -0.030), (0.07, 0.010), (-0.07, 0.010)]
            sweep(bmt, pts, prof, TRIM, normals=[Vector((0, 0, 1))] * len(pts))
            for k in (1, len(rb_path) - 2):
                p, n = rb_path[k]
                add_box(bmt, (0.12, 0.06, 0.04), p + n * 0.05 + Vector((0, 0, -0.01)), TRIM)
        # Bed rail caps over the whole (squared) rail top.
        fj_applied(bmt, surf, -2.93, -1.22, lambda f: sec.j_along(f, 5.0, 0.004),
                   lambda f: sec.j_along(f, 5.0, 0.092), 1, 24, 0.004, TRIM, side,
                   thickness=0.008)
        # Vertical tail lamps on the bed's rear corners.
        tl = rect_grid(0.845, 0.955, 0.985, 1.345, 4, 3)
        applied(bmt, surf, "rear", tl if side > 0 else mirror2(tl), 0.004, LIGHT_R, thickness=0.008)
        tls = rect_grid(0.875, 0.925, 1.000, 1.055, 1, 2)
        applied(bmt, surf, "rear", tls if side > 0 else mirror2(tls), 0.0055, LIGHT_F)
    fj_applied(bmt, surf, 1.090, 1.160, lambda f: sec.j_along(f, 5.0, 0.03), 7.0, 12, 3, 0.003,
               TRIM, 1.0, thickness=0.006, centre=True)
    cladding(bmt, surf, s, width=0.100, height=0.024)
    bmesh.ops.remove_doubles(bmt, verts=bmt.verts, dist=1e-6)
    parts.append(new_object("trims", bmt))
    bmesh.ops.remove_doubles(bmp, verts=bmp.verts, dist=1e-6)
    parts.append(new_object("inserts", bmp))
    for side in (1.0, -1.0):
        mirror(parts, surf, s, side, 0.99, 5.05, (1.14, 0.96, 1.50), (0.26, 0.10, 0.22))


SPECS["pickup"] = pickup


# --- the high-roof delivery van -----------------------------------------------------------------------

def van():
    """A high-roof panel van: a short sloped bonnet, a steep windscreen that runs on up a raked
    roof fairing into a flat roof, a tall box body with flat sides and tight roof edges (the
    ninth section anchor, `roof_z` / `roof_w`, with the side's and the roof's tangents pinned),
    a sliding door on the kerb side with its track, rear barn doors, glass only at the cab."""
    s = {"name": "van", "length": 5.93, "height": 2.55}
    # (5.70 m between the end stations; the rolled ends and the bumpers make it 5.94.)
    s.update({
        "nose": 2.965, "tail": -2.730,
        "front_axle": 2.10, "rear_axle": -1.56, "axle_z": 0.360,
        "wheel_r": 0.360, "wheel_w": 0.235, "wheel_x": 0.865,
        "arch_r": 0.425, "arch_r_rear": 0.425, "arch_in": 0.60,
        "road": -0.196, "belt_probe_z": 1.2,
        "cowl": 2.28, "deck": -2.730, "gh_blend_front": 0.12, "gh_blend_rear": 0.02,
        "crown_at": 0.60, "tension": 1.0, "under_j": 1.0,
        "rings": [0.0, 1.0, 1.6, 2.1, 2.85, 3.4, 3.92, 4.0, 4.08, 4.6, 5.0, 5.5, 6.0, 6.25,
                  6.5, 6.75, 7.0],
        "end_steps": [0.0, 0.012, 0.03, 0.06, 0.10, 0.16, 0.24],
        "mid_step": 0.52,
        "extra_stations": [2.40, 2.34, 2.28, 2.22, 2.00, 1.80, 1.74, 1.68, 1.55, 1.42, 1.34,
                           1.26],
        "creases": [(4.0, 0.5, -3.0, 3.0), (5.0, 0.45, -2.72, 2.20)],
        "station_creases": [(2.28, 0.5, 5.2, 7.0), (1.74, 0.45, 6.0, 7.0)],
        "tangent_over": {6: (-0.06, 1.0), 7: (-1.0, 0.0)},
        "nose_cap": {"steps": 3, "roll": lambda j: 0.050, "dome": 0.030,
                     "lean": lambda co: 0.025 * ramp(co.z, 0.90, 0.55)},
        "tail_cap": {"steps": 3, "roll": lambda j: 0.055, "dome": 0.010},
        "sculpt": [
            (3.0, -3.0, 0.0, 3.97, 4.03, 0.10, 0.004),
        ],
        "profile": {
            "top": [(2.965, 0.955), (2.94, 0.975), (2.88, 0.995), (2.75, 1.030), (2.60, 1.075),
                    (2.45, 1.130), (2.34, 1.180), (2.28, 1.215), (2.20, 1.343), (2.10, 1.503),
                    (2.00, 1.663), (1.90, 1.823), (1.82, 1.951), (1.76, 2.045), (1.72, 2.098),
                    (1.66, 2.160), (1.58, 2.240), (1.50, 2.320), (1.42, 2.400), (1.36, 2.470),
                    (1.30, 2.520), (1.22, 2.545), (1.00, 2.552), (-2.665, 2.552),
                    (-2.730, 2.540)],
            "rail_z": [(2.36, 1.18), (2.28, 1.205), (2.20, 1.328), (2.10, 1.488), (2.00, 1.648),
                       (1.90, 1.808), (1.80, 1.965), (1.74, 2.050), (1.70, 2.095),
                       (1.62, 2.170), (1.55, 2.240), (1.48, 2.300), (1.40, 2.360),
                       (1.32, 2.398), (1.22, 2.415), (-2.665, 2.415), (-2.730, 2.405)],
            "rail_w": [(2.36, 0.955), (2.28, 0.950), (2.00, 0.935), (1.74, 0.925),
                       (1.60, 0.945), (1.40, 0.965), (1.00, 0.972), (-2.665, 0.972),
                       (-2.730, 0.955)],
            "roof_z": [(2.36, 1.190), (2.28, 1.212), (2.20, 1.337), (2.00, 1.657),
                       (1.80, 1.978), (1.74, 2.060), (1.66, 2.150), (1.55, 2.265),
                       (1.45, 2.380), (1.36, 2.465), (1.28, 2.518), (1.18, 2.538),
                       (1.00, 2.541), (-2.665, 2.541), (-2.730, 2.529)],
            "roof_w": [(2.36, 0.62), (2.00, 0.62), (1.74, 0.64), (1.60, 0.80), (1.45, 0.86),
                       (1.30, 0.885), (-2.665, 0.885), (-2.730, 0.870)],
            "over_w": [(2.965, 0.0), (1.82, 0.0), (1.58, 1.0), (-2.730, 1.0)],
            "belt_z": [(2.965, 0.930), (2.85, 0.985), (2.60, 1.070), (2.40, 1.150),
                       (2.28, 1.195), (2.00, 1.230), (1.30, 1.255), (0.00, 1.265),
                       (-2.665, 1.270), (-2.730, 1.262)],
            "belt_in": 0.020,
            "shoulder_z": [(2.965, 0.780), (2.70, 0.900), (2.30, 0.980), (1.80, 1.020),
                           (-2.730, 1.040)],
            "width": [(2.965, 0.905), (2.95, 0.950), (2.91, 0.985), (2.82, 1.002),
                      (2.60, 1.010), (2.10, 1.015), (-2.565, 1.015), (-2.665, 1.008),
                      (-2.710, 0.990), (-2.730, 0.955)],
            "low_z": 0.70,
            "low_in": 0.012,
            "sill_z": [(2.965, 0.350), (2.75, 0.400), (2.10, 0.415), (0.00, 0.400),
                       (-1.56, 0.410), (-2.40, 0.430), (-2.730, 0.360)],
            "sill_in": 0.045,
            "floor_z": [(2.965, 0.330), (2.60, 0.320), (2.10, 0.285), (0.00, 0.275),
                        (-1.56, 0.285), (-2.40, 0.330), (-2.730, 0.340)],
            "floor_in": 0.12,
        },
    })
    s["details"] = van_details
    return s


def van_windows(s, sec):
    belt_gap = 0.024

    def side_j(f):
        lo = sec.j_along(f, 5.0, belt_gap)
        # The cab's side glass stops at 2.02 m: above it is the high roof's panel.
        hi = min(sec.j_at_z(f, 2.02), sec.j_along(f, 6.0, 0.022, -1.0))
        if hi < lo:
            lo = hi = (lo + hi) * 0.5
        return lo, hi

    def screen_j(pillar):
        return lambda f: (sec.j_along(f, 6.0, pillar), 7.0)

    return [
        {"name": "windscreen", "centre": True, "rows": 16, "cols": 12,
         "f": lambda j: (1.765, 2.262), "j": screen_j(0.060), "cut_shrink_j": 0.02},
        {"name": "cab", "centre": False, "rows": 8, "cols": 12,
         "f": lambda j: (1.300, 2.240), "j": side_j, "cut_shrink_j": 0.035},
    ]


def van_details(s, sec, surf, body, parts):
    wins = van_windows(s, sec)
    cut_windows(body, surf, wins)
    fa, ra, R = s["front_axle"], s["rear_axle"], s["arch_r"]

    bmc = bmesh.new()
    bmp = bmesh.new()
    # Headlamps: swept-up blades flanking the grille under the bonnet's edge.
    lamp = blade_grid(0.52, 0.905, 0.858, 0.890, 0.085, 0.115, 3, 16)
    for side in (1.0, -1.0):
        g = lamp if side > 0 else mirror2(lamp)
        res = hits_2d(surf, "front", g, 1.0)
        if res:
            pts, nrm = res
            grid_solid(bmc, [p + n * 0.03 for p, n in zip(pts, nrm)],
                       [p - n * 0.020 for p, n in zip(pts, nrm)], len(g), len(g[0]), TRIM)
            oriented_grid(bmp, [p - n * 0.017 for p, n in zip(pts, nrm)], nrm, len(g), len(g[0]),
                          GLASS)
        drl = blade_grid(0.535, 0.890, 0.884, 0.928, 0.011, 0.013, 1, 16)
        applied(bmp, surf, "front", drl if side > 0 else mirror2(drl), -0.012, LIGHT_F)
        for xc in (0.62, 0.72):
            eye = rect_grid(xc - 0.034, xc + 0.034, 0.838, 0.872, 1, 3)
            applied(bmp, surf, "front", eye if side > 0 else mirror2(eye), -0.014, CHROME)
            lens = rect_grid(xc - 0.024, xc + 0.024, 0.844, 0.866, 1, 3)
            applied(bmp, surf, "front", lens if side > 0 else mirror2(lens), -0.0125, LIGHT_F)
    # Grille: a wide mouth between the lamps, egg-crate in it, a satin bar across its top.
    mouth = rounded_outline([(-0.50, 0.905), (0.50, 0.905), (0.56, 0.600), (-0.56, 0.600)], 0.045)
    boolean(body, extrude_cutter(mouth, "y", 2.84, 3.4))
    eggcrate(bmp, -0.58, 0.58, 0.600, 0.905, 2.955, 2.895, 26, 6, thick=0.008)
    bar = rect_grid(-0.50, 0.50, 0.870, 0.895, 1, 12)
    applied(bmp, surf, "front", bar, 0.004, CHROME, thickness=0.05)
    # Black bumper right across, fogs and a satin skid strip in it.
    wrap_band(bmp, surf, 1.0, 0.365, 0.600, 0.045, TRIM, reach=0.30, corner_r=0.20,
              thickness=0.06)
    skid = rect_grid(-0.40, 0.40, 0.385, 0.405, 1, 10)
    applied(bmp, surf, "front", skid, 0.048, CHROME, thickness=0.01)
    for side in (1.0, -1.0):
        fog = rect_grid(0.72, 0.86, 0.430, 0.475, 1, 3)
        applied(bmp, surf, "front", fog if side > 0 else mirror2(fog), 0.047, LIGHT_F)
    # Rear: black bumper with a step, the plate recess on the left door, handles, hinges.
    wrap_band(bmp, surf, -1.0, 0.380, 0.600, 0.050, TRIM, reach=0.24, corner_r=0.12,
              thickness=0.065)
    step = rect_grid(-0.36, 0.36, 0.585, 0.600, 1, 8)
    applied(bmp, surf, "rear", step, 0.052, CHROME, thickness=0.01)
    plate = rect_grid(-0.52, -0.22, 0.800, 0.950, 2, 6)
    res = hits_2d(surf, "rear", plate, 1.0)
    if res:
        pts, nrm = res
        grid_solid(bmc, [p + n * 0.02 for p, n in zip(pts, nrm)],
                   [p - n * 0.010 for p, n in zip(pts, nrm)], 3, 7, TRIM)
    for x0, x1 in ((0.05, 0.17), (-0.17, -0.05)):
        applied(bmp, surf, "rear", rect_grid(x0, x1, 1.285, 1.320, 1, 3), 0.006, TRIM,
                thickness=0.012)
    for side in (1.0, -1.0):
        for zc in (0.95, 1.95):
            applied(bmp, surf, "rear", rect_grid(side * 0.735, side * 0.765, zc - 0.05, zc + 0.05,
                                                 1, 1), 0.010, TRIM, thickness=0.02)
    for side in (1.0, -1.0):
        flush_handle(bmc, bmp, surf, 1.44, 1.10, side, length=0.16, height=0.040, mat=TRIM)
    flush_handle(bmc, bmp, surf, 1.06, 1.08, 1.0, length=0.16, height=0.040, mat=TRIM)
    tidy(bmc)
    boolean(body, new_object("cut_pockets", bmc))

    paths = []
    for side in (1.0, -1.0):
        # The cab door: down the front edge and round the arch, along the sill, up the B-pillar,
        # and along the top of its frame to the A-pillar.
        arc = circle_path(fa, s["axle_z"], R + 0.050, 84.0, 172.0, 12)
        front = [(2.225, 1.205), (2.17, 0.95)] + arc + [(1.27, 0.42)]
        paths.append(surface_path(surf, "side", front, side))
        paths.append(surface_path(surf, "side", [(1.27, 0.42), (1.27, 2.065)], side))
        paths.append(surface_path(surf, "side", [(1.27, 2.065), (1.705, 2.065)], side))
        # Bonnet sides and front edge.
        paths.append(fj_path(surf, [(2.30, 5.40), (2.935, 5.40)], side))
        paths.append(fj_path(surf, [(2.935, 5.40), (2.935, 7.0)], side))
    # The sliding door on the kerb side (+x).
    paths.append(surface_path(surf, "side", [(1.18, 0.42), (1.18, 2.10), (-0.32, 2.10),
                                              (-0.32, 0.42), (1.18, 0.42)], 1.0))
    # The barn doors: their outline and the split down the middle.
    paths.append(surface_path(surf, "rear", [(0.775, 0.605), (0.775, 2.300), (-0.775, 2.300),
                                              (-0.775, 0.605)], 1.0))
    paths.append(surface_path(surf, "rear", [(0.0, 0.605), (0.0, 2.300)], 1.0))
    flap = circle_path(1.08, 1.02, 0.070, 5.0, 352.0, 24)
    paths.append(surface_path(surf, "side", flap, -1.0, step=0.015))
    cut_grooves(body, paths)

    parts.append(build_glass(surf, wins, 0.008))
    bmt = bmesh.new()
    for side in (1.0, -1.0):
        # Rubbing strip along the lower flanks, in black plastic.
        for f0, f1 in ((fa - R - 0.05, ra + R + 0.05), (ra - R - 0.05, -2.68)):
            strip = surface_path(surf, "side", [(f0, 0.690), (f1, 0.690)], side, step=0.10)
            if len(strip) > 2:
                prof = [(-0.055, -0.004), (-0.045, 0.010), (0.045, 0.010), (0.055, -0.004)]
                sweep(bmt, [p for p, _n in strip], prof, TRIM, normals=[n for _p, n in strip])
        # Tail lamps: tall pillars in the rear corners, a clear reverse segment in each.
        tl = rect_grid(0.800, 0.895, 0.660, 1.460, 6, 3)
        applied(bmt, surf, "rear", tl if side > 0 else mirror2(tl), 0.004, LIGHT_R, thickness=0.008)
        rev = rect_grid(0.815, 0.880, 0.900, 0.990, 1, 2)
        applied(bmt, surf, "rear", rev if side > 0 else mirror2(rev), 0.0055, LIGHT_F)
    # The sliding door's track along the kerb-side rear quarter.
    track = surface_path(surf, "side", [(-0.30, 1.300), (-1.12, 1.300)], 1.0, step=0.08)
    if len(track) > 2:
        prof = [(-0.010, -0.004), (-0.010, 0.012), (0.010, 0.012), (0.010, -0.004)]
        sweep(bmt, [p for p, _n in track], prof, TRIM, normals=[n for _p, n in track])
    # High-level brake lamp over the barn doors, and the cowl panel.
    applied(bmt, surf, "rear", rect_grid(-0.16, 0.16, 2.420, 2.460, 1, 6), 0.004, LIGHT_R,
            thickness=0.008)
    fj_applied(bmt, surf, 2.245, 2.325, lambda f: sec.j_along(f, 5.0, 0.03), 7.0, 12, 3, 0.003,
               TRIM, 1.0, thickness=0.006, centre=True)
    cladding(bmt, surf, s, width=0.080, height=0.018)
    bmesh.ops.remove_doubles(bmt, verts=bmt.verts, dist=1e-6)
    parts.append(new_object("trims", bmt))
    bmesh.ops.remove_doubles(bmp, verts=bmp.verts, dist=1e-6)
    parts.append(new_object("inserts", bmp))
    for side in (1.0, -1.0):
        mirror(parts, surf, s, side, 2.20, 5.10, (1.19, 2.21, 1.56), (0.20, 0.10, 0.32),
               head_mat=TRIM)


SPECS["van"] = van


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = [a for a in argv if not a.startswith("--")] or ["sedan"]
    do_render = "--render" in argv
    detail = "--nodetail" not in argv
    only_views = os.environ.get("VIEWS", "")
    for name in names:
        spec = SPECS[name]()
        ob = build(spec, detail)
        path = os.path.join(OUT_DIR, "road_%s.glb" % name)
        far = build_far(ob, spec)
        far.data.calc_loop_triangles()
        report(ob, spec, far)
        print("   far twin: %d triangles" % len(far.data.loop_triangles))
        if "--noexport" not in argv:
            export([ob, far], path)
            print("wrote", path)
        # Out of the scene before any preview: it sits exactly over the full model.
        bpy.data.objects.remove(far, do_unlink=True)
        if do_render:
            views = default_views(spec)
            if only_views:
                views = [v for v in views if v[0] in only_views.split(",")]
            # The full model has no wheels (the game draws its own); the preview borrows the far
            # twin's so the stance can be judged.
            wh = far_wheels(spec, 24)
            render_previews(join([ob, wh]), name, views)


if __name__ == "__main__":
    main()
