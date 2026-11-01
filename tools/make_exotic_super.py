#!/usr/bin/env python3
"""Original mid-engine supercar bodies, lofted in Blender's Python API (bpy as a module).

    python3 tools/make_exotic_super.py              # both
    python3 tools/make_exotic_super.py coupe        # just one

Writes assets/models/exo_super_coupe.glb and assets/models/exo_super_spider.glb.

ORIGINALITY
-----------
These are CLASS studies, not copies. No badge, no model name, no grille or lamp signature is
taken from any manufacturer's car. What makes a shape read as exotic is proportion and stance -
low, wide, big wheels hard up in the arches, short overhangs, a cabin pushed forward, a hard
shoulder line - and none of that belongs to anybody. Names: "Vantorre Sabre" (coupe) and
"Vantorre Sabre Aperta" (open roof). Invented.

STANCE (the whole brief, in numbers)
------------------------------------
length 4.55, width 2.00 (over the rear arches), height 1.20, wheelbase 2.65, wheel diameter 0.70,
track 1.70, arch radius 0.385 front / 0.395 rear so the tyre clears the wing by ~3.5 cm.
Overhangs are drawn symmetric at 0.95 m each: Vehicle._wheel_slots uses ONE wheel_z for both
axles, so asymmetric arches would sit the wheels 5 cm off-centre in their own wings, which is the
loudest amateur tell there is. Wheelbase and overall length are exactly on target.

GEOMETRY CONVENTIONS
--------------------
Authored X = lateral, Y = longitudinal with the NOSE AT +Y, Z = up, ground at Z = 0. The glTF
Y-up conversion turns that into Godot's X right, Y up, nose at -Z, which is the game's forward.
The lowest body vertex (the splitter blade) is 0.050 m above that ground plane and the wheel
centres are at Z = 0.350, i.e. 0.300 above the model's AABB bottom - see the report the script
prints, the game has to seat it with those two numbers.

SURFACING
---------
A loft: each body is a table of cross-sections given as eight scalars, splined along the length
(monotone, so unevenly spaced stations cannot overshoot and fold the shell) and skinned. The
section itself is a Catmull-Rom through twelve control points, which is what buys the two things
a box cannot have: a hard shoulder line with the flank tucked under it, and a greenhouse that is
visibly a separate volume sitting on the body. Intakes, the cockpit and the diffuser are boolean
cuts; everything is bevelled so no edge is perfectly sharp.
"""

import math
import os
import sys

import bpy  # noqa: E402  (bpy must be imported before bmesh/mathutils)
import bmesh
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO, "assets", "models")
PREFIX = "exo_super_"

# Slot order is a contract with the game: index 0 is the tinted paint, nothing else may be
# merged into it. name, base colour, metallic, roughness.
SLOTS = [
    ("paint",       (0.80, 0.81, 0.83), 0.85, 0.28),
    ("glass",       (0.040, 0.048, 0.060), 0.00, 0.05),
    ("trim",        (0.034, 0.034, 0.038), 0.00, 0.58),
    ("tyre",        (0.028, 0.028, 0.030), 0.00, 0.88),
    ("light_front", (0.30, 0.33, 0.38), 0.00, 0.06),
    ("light_rear",  (0.44, 0.030, 0.030), 0.00, 0.10),
]
PAINT, GLASS, TRIM, TYRE, LIGHT_F, LIGHT_R = range(6)

# One half section is a spline through twelve control points, sampled with a fixed number of
# steps per span so the ring index `h` means the same thing at every station: that is what lets
# glass, sills and shut lines be selected by parameter instead of by guesswork.
SEG_STEPS = [2, 2, 3, 3, 3, 3, 3, 4, 3, 3, 4]
H_PAN, H_SILL, H_WAIST, H_BELT, H_RAIL, H_TOP = 4, 10, 13, 16, 26, 33
HALF_N = 1 + sum(SEG_STEPS)          # 34 points, index 0..33
RING_N = HALF_N * 2 - 2              # 66 points round the closed loop


# --- maths ---------------------------------------------------------------------------------

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
    """The twelve control points of one half section, from the floor centre up to the roof centre.

    p = (u0 floor height, wb floor half width, u1 shoulder height, w1 max half width,
         u2 top height, w2 top half width, crown roof dome at the centreline, tuck waist factor)

    `tuck` is the one that matters for this class. Below the shoulder the flank pulls back in
    (tuck < 1), so the shoulder overhangs the side of the car instead of being the top of a
    barrel. That undercut plus the tight radius above it is the hard shoulder line.
    """
    u0, wb, u1, w1, u2, w2, crown, tuck = p
    du = u1 - u0
    dt = max(u2 - u1, 1e-4)
    ctrl = [
        (0.0,                      u0),                    # floor centre
        (wb * 0.62,                u0 + 0.002),            # flat underbody
        (wb,                       u0 + 0.014),            # edge of the floor pan
        (wb + (w1 - wb) * 0.66,    u0 + du * 0.18),        # rocker, tucked under
        (w1 * 0.972,               u0 + du * 0.52),        # lower flank, near full width
        (w1 * tuck,                u0 + du * 0.76),        # waist: the undercut
        (w1,                       u1),                    # HARD SHOULDER, max width
        (w1 * 0.958,               u1 + dt * 0.10),        # shoulder radius, tight
        (w2 + (w1 - w2) * 0.52,    u1 + dt * 0.46),        # tumblehome
        (w2,                       u2 - dt * 0.10),        # roof rail / deck edge
        (w2 * 0.80,                u2),                    # roof crest
        (0.0,                      u2 + crown),            # roof centre (crown < 0 dishes it)
    ]
    return spline_points(ctrl, SEG_STEPS)


class Mono:
    """Fritsch-Carlson monotone cubic. A uniform spline through stations 15 mm apart at the nose
    and half a metre apart at the cabin OVERSHOOTS; the overshoot makes sections cross, the shell
    self-intersects, and the exact boolean solver then deletes the whole car."""

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


NPARAM = 8


class Loft:
    """Analytic skin: the eight section scalars interpolated along the length, sampled at (f, h)."""

    def __init__(self, keys):
        self.keys = keys                       # nose first, tail last
        self.fs = [k[0] for k in keys]
        xs = [k[0] for k in reversed(keys)]
        self.curves = [Mono(xs, [k[1 + i] for k in reversed(keys)]) for i in range(NPARAM)]
        self._cache = {}

    def params(self, f):
        key = round(f, 5)
        p = self._cache.get(key)
        if p is None:
            p = tuple(c(f) for c in self.curves)
            self._cache[key] = p
        return p

    def half(self, f):
        return half_outline(self.params(f))

    def ring(self, f):
        """One closed cross-section: RING_N points, index 0 at the floor centre going up the +X side."""
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
        # normal points INTO the body: every shut line, lamp and mirror would sink out of sight.
        return -n if side < 0.0 else n

    def off(self, f, h, side, d):
        return self.point(f, h, side) + self.normal(f, h, side) * d


# --- blender plumbing ----------------------------------------------------------------------

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
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    return objects[0]


# --- primitive builders ---------------------------------------------------------------------

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


def ribbon(bm, loft, f_list, h_list, offsets, mat, side):
    """An open strip laid on the skin; offsets[i] is the normal offset of f_list[i]."""
    hl = h_list if side > 0 else list(reversed(h_list))
    pts = []
    for i, f in enumerate(f_list):
        for h in hl:
            pts.append(loft.off(f, h, side, offsets[i]))
    add_grid(bm, pts, len(f_list), len(h_list), mat)


def slab(bm, loft, f_list, h_list, out, thick, mat_out, mat_side, side):
    """A closed panel lying on the skin: an outer shell at `out` and an inner one `thick` under."""
    hs = h_list if side > 0 else list(reversed(h_list))
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


def _xform(loc, rot):
    return (Matrix.Translation(Vector(loc))
            @ Matrix.Rotation(rot[2], 4, 'Z')
            @ Matrix.Rotation(rot[1], 4, 'Y')
            @ Matrix.Rotation(rot[0], 4, 'X'))


def cube_bmesh(size, loc, rot=(0, 0, 0), bev=0.0, segs=2):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    if bev > 0.0:
        bmesh.ops.bevel(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
                        offset=bev, segments=segs, affect='EDGES', profile=0.6, clamp_overlap=True)
    bmesh.ops.transform(bm, matrix=_xform(loc, rot), verts=bm.verts)
    return bm


def merge_bmesh(dst, src, mat):
    vmap = {v: dst.verts.new(v.co) for v in src.verts}
    for f in src.faces:
        try:
            nf = dst.faces.new([vmap[v] for v in f.verts])
            nf.material_index = mat
        except ValueError:
            pass
    src.free()


def add_box(bm, size, loc, rot=(0, 0, 0), mat=TRIM, bev=0.02, segs=2):
    merge_bmesh(bm, cube_bmesh(size, loc, rot, bev, segs), mat)


def plate(bm, loft, f_list, h, out, thick, mat, cols=7):
    """A flat lip welded to the body's own underside: at each station it takes the loft's point at
    section index `h`, pushes it `out` metres further outboard and hangs `thick` below it. Because
    both its width and its height come from the loft, a splitter built this way follows the
    fascia instead of hovering under it like a sheet of plywood."""
    nf = len(f_list)
    top, bot = [], []
    for f in f_list:
        pt = loft.point(f, h, 1.0)
        xh, z = pt.x + out, pt.z
        for j in range(cols):
            x = -xh + 2.0 * xh * j / (cols - 1)
            top.append(Vector((x, f, z)))
            bot.append(Vector((x, f, z - thick)))
    vt = [bm.verts.new(q) for q in top]
    vb = [bm.verts.new(q) for q in bot]

    def face(vs):
        try:
            fc = bm.faces.new(vs)
            fc.material_index = mat
        except ValueError:
            pass
    for i in range(nf - 1):
        for j in range(cols - 1):
            a, b = i * cols + j, i * cols + j + 1
            c, d = (i + 1) * cols + j + 1, (i + 1) * cols + j
            face((vt[a], vt[d], vt[c], vt[b]))
            face((vb[a], vb[b], vb[c], vb[d]))

    def wall(a, b):
        face((vt[a], vt[b], vb[b], vb[a]))
    for j in range(cols - 1):
        wall(j, j + 1)
        wall((nf - 1) * cols + j + 1, (nf - 1) * cols + j)
    for i in range(nf - 1):
        wall((i + 1) * cols, i * cols)
        wall(i * cols + cols - 1, (i + 1) * cols + cols - 1)


def add_cyl(bm, radius, depth, loc, rot=(0, 0, 0), mat=TRIM, segs=12, cap=True):
    tmp = bmesh.new()
    bmesh.ops.create_cone(tmp, cap_ends=cap, cap_tris=False, segments=segs,
                          radius1=radius, radius2=radius, depth=depth)
    bmesh.ops.transform(tmp, matrix=_xform(loc, rot), verts=tmp.verts)
    merge_bmesh(bm, tmp, mat)


# --- the shell -------------------------------------------------------------------------------

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


def region_hit(spec, f, h):
    """Which surface region (f, h) falls in: (key, material, inset) or None.

    Regions are (key, f_lo, f_hi, h_lo, h_hi, material, inset). The dark ones are the whole point
    of doing it this way: a supercar's valance, sills and rear diffuser are black composite, not
    paint, and painting them in the SURFACE costs nothing and can never float off the body. The
    first pass hung them on as separate plates and they read as planks bolted to a car."""
    for key, flo, fhi, hlo, hhi, mat, inset in spec["regions"]:
        if not (flo <= f <= fhi):
            continue
        # hhi may be a pair: the top edge then ramps across the f range, so a valance climbs
        # toward the nose instead of stepping up it like a staircase.
        top = hhi
        if isinstance(hhi, tuple):
            t = (f - flo) / max(fhi - flo, 1e-6)
            top = hhi[0] + (hhi[1] - hhi[0]) * t
        if hlo <= h <= top:
            return key, mat, inset
    return None


def build_shell(spec, mats):
    loft = spec["loft"]
    fs = stations(loft, spec.get("step", 0.062))
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
            hit = region_hit(spec, fm, hm)
            fc.material_index = hit[1] if hit else PAINT
            if hit and hit[2]:
                region.setdefault(hit[0], []).append(fc)
    for ring in (rings[0], rings[-1]):
        try:
            fc = bm.faces.new(ring)
            fc.material_index = PAINT
        except ValueError:
            pass
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))

    # Window reveals: inset each pane as ONE region so the frame is a single band round it, then
    # push the pane in. Face-by-face insetting would give every quad in the screen its own frame.
    for key, faces in region.items():
        faces = [f for f in faces if f.is_valid]
        if not faces:
            continue
        res = bmesh.ops.inset_region(bm, faces=faces, use_boundary=True, use_even_offset=True,
                                     use_interpolate=True, thickness=0.020, depth=0.0)
        for f in res["faces"]:
            f.material_index = PAINT
        bm.normal_update()
        moved = set()
        for f in faces:
            for v in f.verts:
                moved.add(v)
        for v in moved:
            v.co -= v.normal * 0.014
    bm.normal_update()
    return new_object(spec["name"] + "_shell", bm, mats)


def cut_arches(ob, spec, mats):
    """Wheel wells. The cutter flares outward, so the arch mouth is wider than its back: with the
    bevel on the cut edge that is what gives the opening a lip instead of a knife edge."""
    for w in spec["wheels"]:
        depth = w["x_out"] - w["x_in"]
        for side in (1.0, -1.0):
            bm = bmesh.new()
            bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=28,
                                  radius1=w["r"] * 0.965, radius2=w["r"], depth=depth)
            bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0),
                             matrix=Matrix.Rotation(math.pi / 2 * side, 3, 'Y'))
            x = side * (w["x_in"] + depth * 0.5)
            bmesh.ops.translate(bm, verts=bm.verts, vec=Vector((x, w["f"], w["u"])))
            for fc in bm.faces:
                fc.material_index = TYRE
            boolean(ob, new_object("arch_cut", bm, mats))
    return ob


def cut_shapes(ob, spec, mats):
    """Intakes, the diffuser cavity and (on the spider) the cockpit: boolean boxes that may be
    rotated and rounded, so an intake mouth is a scoop rather than a rectangular hole."""
    for c in spec.get("cuts", []):
        size, loc, rot, mat = c[0], c[1], c[2], c[3]
        bev = c[4] if len(c) > 4 else 0.0
        mirror = c[5] if len(c) > 5 else False
        xs = (1.0, -1.0) if mirror else (1.0,)
        for s in xs:
            bm = cube_bmesh((size[0], size[1], size[2]),
                            (loc[0] * s, loc[1], loc[2]),
                            (rot[0], rot[1] * s, rot[2] * s), bev, 3)
            for fc in bm.faces:
                fc.material_index = mat
            boolean(ob, new_object("cut", bm, mats))
    return ob


# --- details ----------------------------------------------------------------------------------

def build_details(spec, mats):
    loft = spec["loft"]
    bm = bmesh.new()
    d = spec["detail"]

    # Shut lines. A perfectly smooth flank reads as a bar of soap; these thin proud strips are
    # what say "doors" and "engine cover". Constant-f strips run round the section, constant-h
    # ones run along the car.
    for f0, hlo, hhi in d.get("shut_v", []):
        hs = [hlo + (hhi - hlo) * s / 10.0 for s in range(11)]
        for side in (1.0, -1.0):
            ribbon(bm, loft, [f0 + 0.007, f0, f0 - 0.007], hs,
                   [0.0020, 0.0006, 0.0020], TRIM, side)
    # Character line. A hard crease running the length of the flank is what a rounded shell
    # cannot give you, and its highlight is most of what says "sheet metal" at a distance.
    for (h0, flo, fhi, rise) in d.get("creases", []):
        n = max(8, int((fhi - flo) / 0.07))
        fs = [fhi - (fhi - flo) * s / n for s in range(n + 1)]
        for side in (1.0, -1.0):
            pts = []
            hl = [h0 - 0.75, h0, h0 + 0.75] if side > 0 else [h0 + 0.75, h0, h0 - 0.75]
            for f in fs:
                for k, hh in enumerate(hl):
                    pts.append(loft.off(f, hh, side, 0.0004 if k != 1 else rise))
            add_grid(bm, pts, len(fs), 3, PAINT)
    for h0, flo, fhi in d.get("shut_h", []):
        n = max(6, int((fhi - flo) / 0.09))
        fs = [fhi - (fhi - flo) * s / n for s in range(n + 1)]
        for side in (1.0, -1.0):
            hs = [h0 + 0.28, h0, h0 - 0.28]
            ribbon(bm, loft, fs, hs, [0.0020] * len(fs), TRIM, side)

    # Splitter and skirt lips, welded to the body's own underside.
    for (flo, fhi, h, out, thick, mat) in d.get("lips", []):
        n = max(4, int((fhi - flo) / 0.055))
        fs = [fhi - (fhi - flo) * s / n for s in range(n + 1)]
        plate(bm, loft, fs, h, out, thick, mat)

    # Lamps: slabs that sit 7 mm proud of the skin and sink into it, so the lens is the only
    # thing you see and it follows the bodywork instead of floating on it. Thin and wide on
    # purpose - a horizontal light signature is most of what reads as "modern exotic".
    for (flo, fhi, hlo, hhi, mat) in d.get("lamps", []):
        n = max(5, int((fhi - flo) / 0.022))
        fs = [fhi - (fhi - flo) * s / n for s in range(n + 1)]
        hs = [hlo + (hhi - hlo) * s / 4.0 for s in range(5)]
        for side in (1.0, -1.0):
            slab(bm, loft, fs, hs, 0.0025, 0.040, mat, TRIM, side)

    # Grille slats inside a boolean recess.
    for (x, u0, u1, f0, count, mat) in d.get("slats", []):
        for i in range(count):
            u = u0 + (u1 - u0) * (i + 0.5) / count
            add_box(bm, (x * 2.0, 0.050, (u1 - u0) / count * 0.50), (0.0, f0, u),
                    mat=mat, bev=0.005, segs=1)

    # Mirrors: a pod on a stalk. Cheap, and the single silhouette detail people read as "car".
    for (f0, h0, up, out, size) in d.get("mirrors", []):
        for side in (1.0, -1.0):
            base = loft.off(f0, h0, side, 0.008)
            pod = base + Vector((side * out, 0.0, up))
            add_box(bm, (0.040, 0.075, 0.032),
                    (base.x + side * out * 0.40, base.y, base.z + up * 0.55),
                    rot=(0.0, side * 0.35, 0.0), mat=TRIM, bev=0.008, segs=1)
            add_box(bm, size, (pod.x, pod.y, pod.z), mat=PAINT, bev=0.022, segs=2)
            add_box(bm, (size[0] * 0.50, 0.014, size[2] * 0.60),
                    (pod.x + side * size[0] * 0.28, pod.y - size[1] * 0.47, pod.z),
                    mat=GLASS, bev=0.005, segs=1)

    # Flush door pulls.
    for (f0, h0, size) in d.get("handles", []):
        for side in (1.0, -1.0):
            p = loft.off(f0, h0, side, 0.012)
            add_box(bm, size, (p.x, p.y, p.z), mat=TRIM, bev=0.008, segs=1)

    # Wiper at the base of the screen.
    for (f0, u0, length, tilt) in d.get("wipers", []):
        add_box(bm, (length, 0.024, 0.014), (-length * 0.12, f0, u0),
                rot=(0.0, tilt, 0.0), mat=TRIM, bev=0.004, segs=1)

    # Exhaust tips.
    for (x, f0, u0, r) in d.get("exhaust", []):
        for side in (1.0, -1.0):
            add_cyl(bm, r, 0.14, (side * x, f0, u0), rot=(math.pi / 2, 0, 0), mat=TRIM, segs=14)
            add_cyl(bm, r * 0.72, 0.12, (side * x, f0 - 0.012, u0),
                    rot=(math.pi / 2, 0, 0), mat=TYRE, segs=14)

    # Vertical fins: diffuser strakes, intake dividers, roll hoops, anything box shaped.
    for (size, loc, rot, mat, bev, mirror) in d.get("boxes", []):
        xs = (1.0, -1.0) if mirror else (1.0,)
        for s in xs:
            add_box(bm, size, (loc[0] * s, loc[1], loc[2]),
                    rot=(rot[0], rot[1] * s, rot[2] * s), mat=mat, bev=bev, segs=2)

    if not bm.faces:
        bm.free()
        return None
    return new_object(spec["name"] + "_detail", bm, mats)


# --- the cars -----------------------------------------------------------------------------------
# A key is (f, u0 floor, wb floor half width, u1 shoulder, w1 max half width, u2 top,
# w2 top half width, crown, tuck). f runs along the car with the NOSE AT +f; every height is
# metres above the ground it is drawn on. Stations crowd together at the nose, the cowl and the
# tail on purpose: those are where the surface changes direction, and spreading a change of
# direction over half a metre is what turns a car into a bar of soap.

NOSE, TAIL = 2.275, -2.275
AXLE = 1.325          # wheelbase 2.65, overhangs 0.95 each
WHEEL_R = 0.35        # 0.70 m diameter
HUB_Z = 0.35          # wheel centre height = wheel radius, contact patch on z = 0

# Front half: nose, fascia, front arch, bonnet, cowl. Shared by both bodies.
FRONT_KEYS = [
    (2.275, 0.115, 0.30, 0.345, 0.520, 0.560, 0.380, -0.005, 0.980),
    (2.262, 0.092, 0.38, 0.348, 0.690, 0.578, 0.520, -0.014, 0.970),
    (2.240, 0.074, 0.46, 0.356, 0.810, 0.604, 0.620, -0.024, 0.955),
    (2.205, 0.062, 0.52, 0.376, 0.870, 0.634, 0.664, -0.042, 0.940),
    (2.150, 0.054, 0.56, 0.404, 0.904, 0.664, 0.686, -0.058, 0.930),
    (2.040, 0.050, 0.58, 0.452, 0.926, 0.700, 0.700, -0.080, 0.920),
    (1.860, 0.054, 0.59, 0.512, 0.944, 0.744, 0.700, -0.112, 0.910),
    (1.620, 0.062, 0.60, 0.578, 0.962, 0.784, 0.698, -0.136, 0.900),
    (1.325, 0.072, 0.60, 0.636, 0.985, 0.812, 0.692, -0.146, 0.895),  # front axle, fender peak
    (1.210, 0.077, 0.60, 0.668, 0.960, 0.806, 0.694, -0.110, 0.895),
    (1.100, 0.082, 0.60, 0.700, 0.938, 0.794, 0.694, -0.064, 0.895),  # cowl / base of screen
]

# Rear quarter: engine deck shoulder, tail taper, chopped tail panel. Shared by both bodies.
TAIL_KEYS = [
    (-1.620, 0.118, 0.585, 0.884, 0.994, 1.024, 0.836, -0.112, 0.900),
    (-1.880, 0.152, 0.555, 0.874, 0.962, 0.992, 0.842, -0.062, 0.910),
    (-2.060, 0.216, 0.510, 0.860, 0.918, 0.966, 0.822, -0.030, 0.920),
    (-2.180, 0.292, 0.455, 0.842, 0.868, 0.940, 0.780, -0.014, 0.935),
    (-2.250, 0.372, 0.385, 0.816, 0.812, 0.906, 0.720, -0.008, 0.955),
    (-2.275, 0.442, 0.305, 0.790, 0.735, 0.868, 0.640, -0.004, 0.975),
]

COUPE_MID = [
    (1.055, 0.084, 0.60, 0.712, 0.932, 0.845, 0.672, -0.022, 0.895),   # screen break
    (0.920, 0.087, 0.60, 0.742, 0.928, 0.935, 0.600, 0.004, 0.895),
    (0.760, 0.090, 0.60, 0.778, 0.924, 1.032, 0.524, 0.010, 0.895),
    (0.580, 0.092, 0.60, 0.812, 0.922, 1.122, 0.456, 0.012, 0.895),
    (0.420, 0.094, 0.60, 0.836, 0.922, 1.180, 0.418, 0.012, 0.895),   # header / roof leading edge
    (0.180, 0.095, 0.60, 0.856, 0.924, 1.196, 0.400, 0.008, 0.895),
    (-0.120, 0.096, 0.60, 0.866, 0.930, 1.198, 0.396, 0.006, 0.895),
    (-0.420, 0.098, 0.60, 0.870, 0.940, 1.182, 0.414, 0.004, 0.895),  # back of the roof
    (-0.560, 0.099, 0.60, 0.872, 0.950, 1.162, 0.468, -0.036, 0.895),
    (-0.760, 0.101, 0.60, 0.876, 0.966, 1.126, 0.562, -0.094, 0.895),
    (-0.980, 0.103, 0.60, 0.880, 0.978, 1.088, 0.664, -0.132, 0.895),
    (-1.325, 0.107, 0.60, 0.886, 1.000, 1.052, 0.784, -0.138, 0.895),  # rear axle, widest point
]

SPIDER_MID = [
    (1.055, 0.084, 0.60, 0.712, 0.932, 0.845, 0.672, -0.022, 0.895),
    (0.920, 0.087, 0.60, 0.742, 0.928, 0.936, 0.608, 0.004, 0.895),
    (0.790, 0.089, 0.60, 0.768, 0.926, 1.020, 0.536, 0.008, 0.895),
    (0.640, 0.091, 0.60, 0.796, 0.924, 1.086, 0.482, 0.010, 0.895),   # top of the header rail
    (0.580, 0.092, 0.60, 0.808, 0.923, 1.036, 0.502, -0.014, 0.895),
    (0.500, 0.093, 0.60, 0.820, 0.922, 0.976, 0.548, -0.032, 0.895),
    (0.400, 0.094, 0.60, 0.834, 0.922, 0.936, 0.608, -0.040, 0.895),
    (0.180, 0.095, 0.60, 0.852, 0.924, 0.920, 0.664, -0.040, 0.895),
    (-0.120, 0.096, 0.60, 0.862, 0.930, 0.918, 0.700, -0.036, 0.895),
    (-0.420, 0.098, 0.60, 0.868, 0.940, 0.930, 0.734, -0.038, 0.895),
    (-0.560, 0.099, 0.60, 0.870, 0.950, 0.942, 0.754, -0.044, 0.895),
    (-0.760, 0.101, 0.60, 0.874, 0.966, 0.962, 0.784, -0.056, 0.895),
    (-0.980, 0.103, 0.60, 0.878, 0.978, 0.988, 0.814, -0.068, 0.895),
    (-1.325, 0.107, 0.60, 0.884, 1.000, 1.016, 0.850, -0.086, 0.895),  # rear axle, widest point
]

WHEELS = [
    dict(f=AXLE,  x_in=0.575, x_out=1.070, u=HUB_Z, r=0.385),
    dict(f=-AXLE, x_in=0.585, x_out=1.110, u=HUB_Z, r=0.395),
]

# Shared bodywork: splitter, dive planes, diffuser strakes, gills, lamps. Every one of these is
# placed against the loft's own numbers, not eyeballed: a splitter wider than the body at that
# height, or a light bar buried a centimetre inside the tail panel, is what the first pass did.
def aero_boxes(wing):
    return [
        # dive planes on the fascia corners
        ((0.165, 0.125, 0.014), (0.868, 2.090, 0.290), (0.22, 0.0, 0.14), TRIM, 0.005, True),
        # diffuser strakes, tucked up inside the rear valance recess
        ((0.022, 0.300, 0.075), (0.150, -2.150, 0.470), (-0.30, 0.0, 0.0), TRIM, 0.005, True),
        ((0.022, 0.300, 0.075), (0.380, -2.150, 0.470), (-0.30, 0.0, 0.0), TRIM, 0.005, True),
        ((0.022, 0.300, 0.075), (0.560, -2.150, 0.470), (-0.30, 0.0, 0.0), TRIM, 0.005, True),
        # rear lamp lens, sunk in the slot cut for it so the lens finishes flush with the tail
        ((1.340, 0.085, 0.058), (0.000, -2.238, 0.752), (0.0, 0.0, 0.0), LIGHT_R, 0.012, False),
        # gills behind the front arches
        ((0.026, 0.175, 0.016), (0.940, 1.030, 0.545), (0.0, 0.0, 0.0), TRIM, 0.004, True),
        ((0.026, 0.175, 0.016), (0.937, 1.030, 0.600), (0.0, 0.0, 0.0), TRIM, 0.004, True),
        ((0.026, 0.175, 0.016), (0.931, 1.030, 0.655), (0.0, 0.0, 0.0), TRIM, 0.004, True),
        # divider standing in each side intake
        ((0.016, 0.420, 0.150), (0.840, -0.700, 0.618), (0.16, 0.0, 0.0), TRIM, 0.004, True),
        ((0.070, 0.430, 0.030), (0.905, -0.690, 0.760), (0.16, 0.0, 0.0), PAINT, 0.010, True),
        # bonnet vent slats, sunk in the recess cut out of the bonnet centre
        ((0.580, 0.030, 0.022), (0.000, 1.655, 0.622), (-0.22, 0.0, 0.0), TRIM, 0.004, False),
        ((0.580, 0.030, 0.022), (0.000, 1.745, 0.628), (-0.22, 0.0, 0.0), TRIM, 0.004, False),
        ((0.570, 0.030, 0.022), (0.000, 1.835, 0.634), (-0.22, 0.0, 0.0), TRIM, 0.004, False),
        # ducktail lip: body colour, because a black shelf on a painted deck reads as a bolt-on
        (wing, (0.000, -2.090, 0.972), (-0.10, 0.0, 0.0), PAINT, 0.014, False),
    ]


# The dark lower body. A supercar is two colours: painted upper, black composite valance, sills
# and diffuser. Doing it in the surface rather than as bolted-on plates is what stops the splitter
# reading as a plank, and it costs no geometry at all.
LOWER = [
    ("valance", 1.880, 2.300, 0.0, (7.0, 12.4), TRIM, False),
    ("skirt",  -0.620, 1.880, 0.0, 6.8, TRIM, False),
    ("rear",   -2.300, -1.900, 0.0, 9.4, TRIM, False),
]


COMMON_CUTS = [
    # front centre intake
    ((0.780, 0.320, 0.155), (0.000, 2.185, 0.205), (0.0, 0.0, 0.0), TRIM, 0.030, False),
    # front corner intakes
    ((0.270, 0.270, 0.205), (0.650, 2.170, 0.305), (0.0, 0.0, 0.10), TRIM, 0.065, True),
    # the big side intakes ahead of the rear wheels, tilted so the top edge rises to the rear
    ((0.640, 0.500, 0.330), (1.050, -0.700, 0.618), (0.18, 0.0, -0.05), TRIM, 0.085, True),
    # bonnet vent: kills the highlight blob a smooth bonnet dome always gives
    ((0.640, 0.340, 0.110), (0.000, 1.750, 0.652), (-0.10, 0.0, 0.0), TRIM, 0.030, False),
    # slot in the tail panel for the light bar
    ((1.380, 0.120, 0.080), (0.000, -2.235, 0.752), (0.0, 0.0, 0.0), TRIM, 0.015, False),
    # rear valance recess: the exhausts and the diffuser live in here, and the shadow it casts
    # is what visually shortens a tail that is otherwise one tall slab of bodywork
    ((1.220, 0.400, 0.230), (0.000, -2.150, 0.540), (0.0, 0.0, 0.0), TRIM, 0.040, False),
    # engine-cover recess in the valley between the buttresses
    ((0.700, 0.520, 0.110), (0.000, -1.660, 0.952), (0.0, 0.0, 0.0), TRIM, 0.025, False),
]

COUPE = dict(
    name="coupe",
    step=0.066,
    keys=FRONT_KEYS + COUPE_MID + TAIL_KEYS,
    wheels=WHEELS,
    regions=LOWER + [
        ("wind", 0.435, 1.085, 19.5, 34.0, GLASS, True),
        ("side", -0.400, 0.410, 20.0, 26.0, GLASS, True),
        ("back", -1.290, -0.470, 28.0, 34.0, GLASS, True),
    ],
    cuts=COMMON_CUTS,
    detail=dict(
        shut_v=[(0.940, 7.5, 19.0), (-0.460, 7.5, 19.0), (1.180, 20.0, 33.0),
                (-1.335, 24.0, 33.0), (1.880, 7.5, 21.0), (-1.900, 7.5, 21.0)],
        shut_h=[],
        creases=[(13.2, -0.980, 1.050, 0.0075)],
        lips=[(1.880, 2.278, 5.0, 0.080, 0.026, TRIM),
              (-0.560, 0.960, 5.6, 0.038, 0.020, TRIM)],
        lamps=[(2.150, 2.260, 18.5, 22.0, LIGHT_F)],
        slats=[(0.320, 0.150, 0.258, 2.170, 3, TRIM)],
        mirrors=[(0.980, 17.5, 0.045, 0.100, (0.046, 0.132, 0.066))],
        handles=[(0.200, 17.4, (0.026, 0.140, 0.026))],
        wipers=[(1.075, 0.744, 0.580, 0.20)],
        exhaust=[(0.340, -2.180, 0.585, 0.054)],
        boxes=aero_boxes((1.360, 0.220, 0.040)) + [
            # louvres inside the engine-cover recess
            ((0.560, 0.030, 0.024), (0.000, -1.480, 0.918), (0.20, 0.0, 0.0), TRIM, 0.004, False),
            ((0.580, 0.030, 0.024), (0.000, -1.570, 0.920), (0.20, 0.0, 0.0), TRIM, 0.004, False),
            ((0.590, 0.030, 0.024), (0.000, -1.660, 0.924), (0.20, 0.0, 0.0), TRIM, 0.004, False),
            ((0.580, 0.030, 0.024), (0.000, -1.750, 0.930), (0.20, 0.0, 0.0), TRIM, 0.004, False),
            ((0.560, 0.030, 0.024), (0.000, -1.840, 0.938), (0.20, 0.0, 0.0), TRIM, 0.004, False),
        ],
    ),
)

SPIDER = dict(
    name="spider",
    step=0.066,
    keys=FRONT_KEYS + SPIDER_MID + TAIL_KEYS,
    wheels=WHEELS,
    regions=LOWER + [
        ("wind", 0.655, 1.085, 19.5, 34.0, GLASS, True),
    ],
    cuts=COMMON_CUTS + [
        # the cockpit, hollowed straight out of the loft
        ((1.080, 1.000, 0.800), (0.000, 0.060, 0.920), (0.0, 0.0, 0.0), TRIM, 0.150, False),
    ],
    detail=dict(
        shut_v=[(0.940, 7.5, 18.0), (-0.460, 7.5, 18.0), (1.180, 20.0, 33.0),
                (-1.335, 24.0, 33.0), (1.880, 7.5, 21.0), (-1.900, 7.5, 21.0)],
        shut_h=[],
        creases=[(13.2, -0.980, 1.050, 0.0075)],
        lips=[(1.880, 2.278, 5.0, 0.080, 0.026, TRIM),
              (-0.560, 0.960, 5.6, 0.038, 0.020, TRIM)],
        lamps=[(2.150, 2.260, 18.5, 22.0, LIGHT_F)],
        slats=[(0.320, 0.150, 0.258, 2.170, 3, TRIM)],
        mirrors=[(0.980, 17.5, 0.045, 0.100, (0.046, 0.132, 0.066))],
        handles=[(0.200, 17.0, (0.026, 0.140, 0.026))],
        wipers=[(1.075, 0.744, 0.580, 0.20)],
        exhaust=[(0.340, -2.180, 0.585, 0.054)],
        boxes=aero_boxes((1.360, 0.210, 0.038)) + [
            # roll hoops behind the seats and the deck they grow out of
            ((0.120, 0.140, 0.240), (0.325, -0.430, 0.960), (0.10, 0.0, 0.0), PAINT, 0.028, True),
            ((0.740, 0.220, 0.060), (0.000, -0.440, 0.902), (0.0, 0.0, 0.0), PAINT, 0.018, False),
            # wind deflector between the hoops
            ((0.540, 0.018, 0.100), (0.000, -0.355, 0.980), (0.22, 0.0, 0.0), GLASS, 0.005, False),
            # seats, tunnel and dash inside the cockpit
            ((0.400, 0.440, 0.100), (0.295, 0.140, 0.585), (0.0, 0.0, 0.0), TRIM, 0.038, True),
            ((0.360, 0.115, 0.400), (0.295, -0.130, 0.770), (0.20, 0.0, 0.0), TRIM, 0.038, True),
            ((0.190, 0.860, 0.125), (0.000, 0.060, 0.595), (0.0, 0.0, 0.0), TRIM, 0.028, False),
            ((0.880, 0.230, 0.140), (0.000, 0.470, 0.735), (0.30, 0.0, 0.0), TRIM, 0.028, False),
            # louvres inside the engine-cover recess
            ((0.560, 0.030, 0.024), (0.000, -1.480, 0.912), (0.20, 0.0, 0.0), TRIM, 0.004, False),
            ((0.580, 0.030, 0.024), (0.000, -1.570, 0.914), (0.20, 0.0, 0.0), TRIM, 0.004, False),
            ((0.590, 0.030, 0.024), (0.000, -1.660, 0.918), (0.20, 0.0, 0.0), TRIM, 0.004, False),
            ((0.580, 0.030, 0.024), (0.000, -1.750, 0.926), (0.20, 0.0, 0.0), TRIM, 0.004, False),
            ((0.560, 0.030, 0.024), (0.000, -1.840, 0.936), (0.20, 0.0, 0.0), TRIM, 0.004, False),
        ],
    ),
)

CARS = {c["name"]: c for c in (COUPE, SPIDER)}


# --- build / export --------------------------------------------------------------------------

def build(spec):
    reset_scene()
    mats = make_materials()
    spec["loft"] = Loft(spec["keys"])
    shell = build_shell(spec, mats)
    bad = self_intersections(shell)
    if bad:
        print("  WARNING %s: %d self-intersecting face pairs in the shell" % (spec["name"], bad))
    cut_shapes(shell, spec, mats)
    cut_arches(shell, spec, mats)
    bevel(shell, 0.0030, segments=2, angle=28.0)
    parts = [shell]
    det = build_details(spec, mats)
    if det is not None:
        bevel(det, 0.0020, segments=1, angle=40.0)
        parts.append(det)
    ob = join(parts)
    ob.name = PREFIX + spec["name"]
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


def main(argv):
    names = [a for a in argv if a in CARS] or list(CARS)
    os.makedirs(OUT_DIR, exist_ok=True)
    for n in names:
        ob = build(CARS[n])
        me = ob.data
        me.calc_loop_triangles()
        tris = len(me.loop_triangles)
        bb = [Vector(c) for c in ob.bound_box]
        mn = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
        mx = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
        per = {}
        for t in me.loop_triangles:
            slot = me.polygons[t.polygon_index].material_index
            per[SLOTS[slot][0]] = per.get(SLOTS[slot][0], 0) + 1
        path = export(ob, n)
        print("%-7s tris=%6d  width %.3f  length %.3f  height %.3f  lowest body z %.3f"
              % (n, tris, mx.x - mn.x, mx.y - mn.y, mx.z - mn.z, mn.z))
        print("        arch centres z=%.3f (%.3f above the lowest vertex), axles y=%+.3f/%+.3f"
              % (HUB_Z, HUB_Z - mn.z, AXLE, -AXLE))
        print("        slots: " + ", ".join("%s=%d" % (k, v) for k, v in per.items()))
        print("        -> " + os.path.basename(path))


if __name__ == "__main__":
    main(sys.argv[1:])
