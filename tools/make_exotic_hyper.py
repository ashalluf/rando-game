#!/usr/bin/env python3
"""Original hypercar bodies, built procedurally in Blender's Python API (bpy as a module).

    python3 tools/make_exotic_hyper.py          # both cars
    python3 tools/make_exotic_hyper.py a        # just exo_hyper_a

Writes assets/models/exo_hyper_<v>.glb.

ORIGINALITY
-----------
These are invented cars in the hypercar CLASS. No badge, no model name, no grille or lamp
signature copied from any manufacturer. What makes them read as exotic is stance - very low,
very wide, big wheels hard against the arch lips, short overhangs on a long wheelbase - not a
logo. Names: "Vallory Tempest" (a) and "Kessin Wraithe GT" (b).

WHY IT IS BUILT THIS WAY
------------------------
The earlier procedural pass splined its cross-sections, which rounds every control point away
and is exactly what makes a body read as a 1930s streamliner. Here the CROSS-SECTION is a
polyline - straight runs between named control points, so the sill, the shoulder, the belt and
the roof rail are genuine creases - and only the LENGTHWISE run of each control point is
smoothed (monotone PCHIP, so it never overshoots into a bulge). Creases across, flow along:
that is how a real body is surfaced, and it is what makes the 1.5 mm bevel on each crease catch
a highlight and read as folded sheet.

Geometry conventions
--------------------
Blender is authored X = lateral, Y = longitudinal with the NOSE AT +Y, Z = up, and the lowest
body vertex at Z = 0. The glTF exporter's Y-up conversion gives Godot X right, Y up, nose at -Z,
so Vehicle._add_body_model() needs no extra yaw (it only rotates when the model's longest axis
is X, and ours is Z).

Vehicle._add_body_model() scales the model so its longest horizontal axis equals the body type's
length, then drops the model's AABB floor onto model_bottom_y (-0.27) while the wheel contact
patch sits at -0.32 and the wheel centre at +0.10. So the WHEEL CENTRE always lands 0.37 m above
the lowest body vertex, whatever the car was drawn with: every arch here is centred on
ARCH_Z = 0.37 for that reason. The game's VehicleWheel3D radius is 0.42, so ARCH_R is 0.455 -
3.5 cm of lip over the tyre, which is what "big wheels filling the arches" means in practice.

Material slots are the six the game expects, in this order: paint, glass, trim, tyre,
light_front, light_rear. Flat colours, no textures - shaders/car_paint.gdshader does the paint.
Only "paint" may be tinted, so nothing else is merged into it. "tyre" is the black rubbery
lining inside the wheel wells and the cut intakes (same use as the earlier pass).
"""

import math
import os
import sys

import bpy  # noqa: E402  (bpy first)
import bmesh
from mathutils import Matrix, Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO, "assets", "models")
PREFIX = "exo_hyper_"

# name, base colour, metallic, roughness. Order is a contract with the game: 0 is the paint.
SLOTS = [
    ("paint",       (0.80, 0.81, 0.84), 0.85, 0.28),
    ("glass",       (0.035, 0.042, 0.055), 0.00, 0.05),
    ("trim",        (0.052, 0.052, 0.058), 0.25, 0.42),
    ("tyre",        (0.026, 0.026, 0.028), 0.00, 0.88),
    ("light_front", (0.88, 0.90, 0.95), 0.00, 0.07),
    ("light_rear",  (0.45, 0.028, 0.030), 0.00, 0.10),
]
PAINT, GLASS, TRIM, TYRE, LIGHT_F, LIGHT_R = range(6)

# --- the package the whole car is dimensioned from -------------------------------------------
WHEELBASE = 2.70
FRONT_AXLE = 1.45          # nose at +Y, so the front axle is at +1.45
REAR_AXLE = FRONT_AXLE - WHEELBASE
ARCH_Z = 0.37              # wheel centre above the lowest body vertex - fixed by the game
ARCH_R = 0.455             # arch lip radius: the game wheel is 0.42, so a 3.5 cm gap
ARCH_INNER_X = 0.60        # inboard wall of the wheel house
NOSE_Y = 2.24              # bodywork; the splitter reaches +2.30
TAIL_Y = -2.18             # bodywork; the diffuser and wing reach -2.30

# The half section is a polyline through ten control points. SEG_STEPS says how many samples
# each span gets: they are straight lines, so the extra points cost nothing but give the bevel
# and the arch boolean something to bite on, and they keep the ring index meaning the same on
# every station, which is what lets regions be chosen by index instead of by guesswork.
SEG_STEPS = [2, 2, 3, 3, 3, 3, 3, 3, 4]
H_FLOOR, H_SILL, H_SHOULDER, H_BELT, H_RAIL = 2, 4, 10, 16, 22
HALF_N = 1 + sum(SEG_STEPS)      # 27 points, index 0..26
RING_N = HALF_N * 2 - 2          # 52 round the closed loop


# --- maths -----------------------------------------------------------------------------------

def smoothstep(a, b, t):
    if a == b:
        return 1.0 if t >= b else 0.0
    if b < a:
        return 1.0 - smoothstep(b, a, t)
    x = min(1.0, max(0.0, (t - a) / (b - a)))
    return x * x * (3.0 - 2.0 * x)


def window(t, t0, t1, fade):
    """1 well inside [t0, t1], 0 outside it, smoothly faded over `fade` at each end."""
    if t <= t0 or t >= t1:
        return 0.0
    return min(smoothstep(t0, t0 + fade, t), smoothstep(t1, t1 - fade, t))


class Curve:
    """Monotone cubic (PCHIP) through (y, value) keys. Monotone matters: a Catmull-Rom through
    the same keys overshoots between a low nose and a high fender and puts a blister there."""

    def __init__(self, keys):
        ks = sorted(keys, key=lambda k: k[0])
        self.x = [k[0] for k in ks]
        self.y = [k[1] for k in ks]
        n = len(self.x)
        self.h = [self.x[i + 1] - self.x[i] for i in range(n - 1)]
        self.d = [(self.y[i + 1] - self.y[i]) / self.h[i] for i in range(n - 1)]
        m = [0.0] * n
        m[0] = self.d[0]
        m[-1] = self.d[-1]
        for i in range(1, n - 1):
            if self.d[i - 1] * self.d[i] <= 0.0:
                m[i] = 0.0
            else:
                w1 = 2.0 * self.h[i] + self.h[i - 1]
                w2 = self.h[i] + 2.0 * self.h[i - 1]
                m[i] = (w1 + w2) / (w1 / self.d[i - 1] + w2 / self.d[i])
        self.m = m

    def __call__(self, t):
        x = self.x
        if t <= x[0]:
            return self.y[0]
        if t >= x[-1]:
            return self.y[-1]
        i = 0
        while i < len(x) - 2 and t > x[i + 1]:
            i += 1
        hh = self.h[i]
        s = (t - x[i]) / hh
        s2, s3 = s * s, s * s * s
        return ((2 * s3 - 3 * s2 + 1) * self.y[i] + (s3 - 2 * s2 + s) * hh * self.m[i]
                + (-2 * s3 + 3 * s2) * self.y[i + 1] + (s3 - s2) * hh * self.m[i + 1])


def airfoil(chord, thickness, camber, n=18):
    """Closed loop of an inverted (downforce) aerofoil in (u, v), u along the chord from the
    leading edge. Camber is negative-down, i.e. the pressure side is on top."""
    pts_up, pts_dn = [], []
    for i in range(n + 1):
        b = math.pi * i / n
        x = 0.5 * (1.0 - math.cos(b))                     # cosine spacing, dense at the edges
        t = 5.0 * thickness * (0.2969 * math.sqrt(max(x, 1e-6)) - 0.1260 * x
                               - 0.3516 * x * x + 0.2843 * x ** 3 - 0.1036 * x ** 4)
        yc = camber * (1.0 - (2.0 * x - 1.0) ** 2)
        pts_up.append((x * chord, (yc + t) * chord))
        pts_dn.append((x * chord, (yc - t) * chord))
    return pts_up + list(reversed(pts_dn[1:-1]))


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


def bevel(ob, width, segments=2, angle=30.0):
    mod = ob.modifiers.new("bev", 'BEVEL')
    mod.width = width
    mod.segments = segments
    mod.limit_method = 'ANGLE'
    mod.angle_limit = math.radians(angle)
    mod.miter_outer = 'MITER_ARC'
    mod.harden_normals = False
    apply_modifiers(ob)


def boolean_cut(ob, cutter):
    mod = ob.modifiers.new("bool", 'BOOLEAN')
    mod.object = cutter
    mod.operation = 'DIFFERENCE'
    mod.solver = 'EXACT'
    apply_modifiers(ob)
    bpy.data.objects.remove(cutter, do_unlink=True)


def shade(ob, sharp_deg=21.0):
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
        elif me.polygons[fl[0]].normal.dot(me.polygons[fl[1]].normal) < lim:
            e.use_edge_sharp = True


def join(objects):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    return objects[0]


# --- primitive builders -------------------------------------------------------------------------

def add_box(bm, size, loc, rot=(0, 0, 0), mat=TRIM, bev=0.006, segs=2):
    tmp = bmesh.new()
    bmesh.ops.create_cube(tmp, size=1.0)
    bmesh.ops.scale(tmp, vec=Vector(size), verts=tmp.verts)
    if bev > 0.0:
        bmesh.ops.bevel(tmp, geom=list(tmp.verts) + list(tmp.edges) + list(tmp.faces),
                        offset=bev, segments=segs, affect='EDGES', profile=0.6, clamp_overlap=True)
    m = (Matrix.Translation(Vector(loc)) @ Matrix.Rotation(rot[2], 4, 'Z')
         @ Matrix.Rotation(rot[1], 4, 'Y') @ Matrix.Rotation(rot[0], 4, 'X'))
    bmesh.ops.transform(tmp, matrix=m, verts=tmp.verts)
    _absorb(bm, tmp, mat)


def add_cyl(bm, radius, depth, loc, rot=(0, 0, 0), mat=TRIM, segs=14, r2=None):
    tmp = bmesh.new()
    bmesh.ops.create_cone(tmp, cap_ends=True, cap_tris=False, segments=segs,
                          radius1=radius, radius2=(radius if r2 is None else r2), depth=depth)
    m = (Matrix.Translation(Vector(loc)) @ Matrix.Rotation(rot[2], 4, 'Z')
         @ Matrix.Rotation(rot[1], 4, 'Y') @ Matrix.Rotation(rot[0], 4, 'X'))
    bmesh.ops.transform(tmp, matrix=m, verts=tmp.verts)
    _absorb(bm, tmp, mat)


def add_prism(bm, pts, a, b, axis='X', mat=TRIM, bev=0.004, rot=None, loc=(0, 0, 0)):
    """Extrude a 2D polygon between two planes. axis='X' means the polygon lives in (Y, Z)."""
    tmp = bmesh.new()
    lo, hi = [], []
    for (u, v) in pts:
        if axis == 'X':
            lo.append(tmp.verts.new((a, u, v)))
            hi.append(tmp.verts.new((b, u, v)))
        elif axis == 'Y':
            lo.append(tmp.verts.new((u, a, v)))
            hi.append(tmp.verts.new((u, b, v)))
        else:
            lo.append(tmp.verts.new((u, v, a)))
            hi.append(tmp.verts.new((u, v, b)))
    tmp.verts.ensure_lookup_table()
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        try:
            tmp.faces.new((lo[i], lo[j], hi[j], hi[i]))
        except ValueError:
            pass
    try:
        tmp.faces.new(lo)
    except ValueError:
        pass
    try:
        tmp.faces.new(list(reversed(hi)))
    except ValueError:
        pass
    bmesh.ops.recalc_face_normals(tmp, faces=tmp.faces[:])
    if bev > 0.0:
        bmesh.ops.bevel(tmp, geom=list(tmp.verts) + list(tmp.edges) + list(tmp.faces),
                        offset=bev, segments=2, affect='EDGES', profile=0.6, clamp_overlap=True)
    if rot is not None:
        m = (Matrix.Translation(Vector(loc)) @ Matrix.Rotation(rot[2], 4, 'Z')
             @ Matrix.Rotation(rot[1], 4, 'Y') @ Matrix.Rotation(rot[0], 4, 'X'))
        bmesh.ops.transform(tmp, matrix=m, verts=tmp.verts)
    elif loc != (0, 0, 0):
        bmesh.ops.transform(tmp, matrix=Matrix.Translation(Vector(loc)), verts=tmp.verts)
    _absorb(bm, tmp, mat)


def _absorb(bm, tmp, mat):
    vmap = {v: bm.verts.new(v.co) for v in tmp.verts}
    for f in tmp.faces:
        try:
            nf = bm.faces.new([vmap[v] for v in f.verts])
            nf.material_index = mat
        except ValueError:
            pass
    tmp.free()


# --- the cross section ---------------------------------------------------------------------------

def channel_inset(spec, y):
    """The deep side channel ahead of the rear wheels: a scoop that fades in gently from the
    door and stops dead at the arch, so the end of it reads as an intake mouth."""
    ch = spec["channel"]
    rise = smoothstep(ch["from"], ch["from"] - 0.34, y) if y < ch["from"] else 0.0
    fall = 1.0 - smoothstep(ch["to"], ch["to"] - 0.07, y)
    return ch["depth"] * rise * fall


def section(spec, y):
    """The half section at station y: HALF_N (x, z) points from the floor centre, out and up the
    flank, over the shoulder and in to the roof centre."""
    c = spec["c"]
    ins = channel_inset(spec, y)
    p = [None] * 10
    zf, wf = c["z_floor"](y), c["w_floor"](y)
    zs, ws = c["z_sill"](y), c["w_sill"](y) - ins * 0.80
    zh, wh = c["z_sh"](y), c["w_sh"](y) - ins * 0.14
    zb, wb = c["z_belt"](y), c["w_belt"](y)
    zr, wr = c["z_rail"](y), c["w_rail"](y)
    zt = c["z_roof"](y)
    p[0] = (0.0, zf)
    p[1] = (wf, zf)
    p[2] = (ws, zs)
    p[4] = (wh, zh)
    p[6] = (wb, zb)
    p[8] = (wr, zr)
    p[9] = (0.0, zt)
    # The three derived points give the flat runs a little crown so the flank is tensioned
    # rather than dead flat, without softening the creases at 2, 4, 6 and 8.
    p[3] = (ws + (wh - ws) * 0.45 + spec["crown_low"] - ins,
            zs + (zh - zs) * 0.45)
    p[5] = (wh + (wb - wh) * 0.52 + spec["crown_up"], zh + (zb - zh) * 0.52)
    p[7] = (wb + (wr - wb) * 0.55 + spec["crown_gl"], zb + (zr - zb) * 0.55)
    # Guardrails so the ring stays a simple polygon whatever the curves do: the lower chain runs
    # outward with rising z, the upper chain runs back inward.
    out = [p[0]]
    for i in range(1, 5):
        x = max(p[i][0], out[-1][0] + 0.004)
        z = max(p[i][1], out[-1][1] + (0.0 if i == 1 else 0.004))
        out.append((x, z))
    for i in range(5, 10):
        x = min(p[i][0], out[-1][0] - 0.004) if i < 9 else 0.0
        out.append((x, max(p[i][1], out[2][1] + 0.02)))
    # Sample the polyline: straight runs, so every control point stays a crease.
    half = [out[0]]
    for i in range(9):
        (x0, z0), (x1, z1) = out[i], out[i + 1]
        n = SEG_STEPS[i]
        for k in range(1, n + 1):
            t = k / n
            half.append((x0 + (x1 - x0) * t, z0 + (z1 - z0) * t))
    return apply_recess(spec, y, half)


def apply_recess(spec, y, half):
    """Ducts, vents and scoops, sunk into the skin along its own outward normal.

    They used to be booleans. A cutter that leaves the body through the TOP of a nose this
    shallow makes the exact solver decide the whole shell is inside it and deletes the car, so
    the openings are sculpted into the section instead: no solver, no failure mode, and the
    lip round the opening comes out as a real bevelled edge for free.
    """
    marks = [None] * len(half)
    n = len(half)
    for r in spec.get("recess", []):
        fy = window(y, r["y0"], r["y1"], r.get("fade_y", 0.13))
        if fy <= 0.0:
            continue
        for i in range(n):
            fh = window(i, r["h0"], r["h1"], r.get("fade_h", 1.3))
            if fh <= 0.0:
                continue
            a = half[max(i - 1, 0)]
            b = half[min(i + 1, n - 1)]
            tx, tz = b[0] - a[0], b[1] - a[1]
            ln = math.hypot(tx, tz) or 1.0
            nx, nz = tz / ln, -tx / ln          # outward for this point order
            f = fy * fh
            d = r["depth"] * f
            half[i] = (half[i][0] - nx * d, half[i][1] - nz * d)
            if f > r.get("mark", 0.62):
                marks[i] = r["mat"]
    return half, marks


def stations(spec):
    ys = set()
    forced = [NOSE_Y, TAIL_Y, FRONT_AXLE, REAR_AXLE, spec["screen_y"], spec["roof_f"],
              spec["roof_r"], spec["deck_y"], spec["channel"]["to"], spec["channel"]["from"]]
    for r in spec.get("recess", []):
        fy = r.get("fade_y", 0.13)
        forced += [r["y0"], r["y0"] + fy, r["y1"] - fy, r["y1"]]
    for f in forced:
        if TAIL_Y <= f <= NOSE_Y:
            ys.add(round(f, 4))
    y = TAIL_Y
    while y < NOSE_Y:
        ys.add(round(y, 4))
        y += spec["step"]
    return sorted(ys, reverse=True)      # nose first


def region_material(spec, y, h0, h1):
    hh = min(h0 if h0 < HALF_N else RING_N - h0, h1 if h1 < HALF_N else RING_N - h1)
    if hh < H_SILL:
        return TRIM                                   # flat floor and the carbon rocker
    if hh < H_BELT:
        if H_SILL + 1 <= hh < H_SHOULDER - 1 \
                and channel_inset(spec, y) > spec["channel"]["depth"] * 0.88 \
                and y < spec["channel"]["to"] + 0.24:
            return TRIM                               # the mouth at the end of the side channel
        return PAINT
    # From the belt up: the canopy. Glass over the screen and the cabin, paint over the rest.
    if spec["roof_f"] <= y <= spec["screen_y"]:
        return PAINT if hh < H_BELT + 3 else GLASS    # screen, with a painted A-pillar
    if spec["roof_r"] <= y < spec["roof_f"]:
        return GLASS if hh < H_RAIL else PAINT        # side glass, painted roof
    if spec["deck_y"] <= y < spec["roof_r"]:
        return spec["backlight"]                      # rear window or a louvred engine cover
    return PAINT


def half_index(h):
    return h if h < HALF_N else RING_N - h


def build_shell(spec, mats):
    bm = bmesh.new()
    ys = stations(spec)
    rings, marks = [], []
    for y in ys:
        half, mk = section(spec, y)
        pts = [(x, y, z) for (x, z) in half]
        pts += [(-x, y, z) for (x, z) in reversed(half[1:-1])]
        rings.append([bm.verts.new(p) for p in pts])
        marks.append(mk)
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        ym = 0.5 * (ys[i] + ys[i + 1])
        for h in range(RING_N):
            h2 = (h + 1) % RING_N
            try:
                f = bm.faces.new((a[h], a[h2], b[h2], b[h]))
            except ValueError:
                continue
            hh = min(half_index(h), half_index(h2))
            ov = marks[i][hh]
            f.material_index = ov if (ov is not None and marks[i + 1][hh] == ov) \
                else region_material(spec, ym, h, h2)
    _cap(bm, rings[0], ys[0], spec, spec["nose_cap"], +1.0)
    _cap(bm, rings[-1], ys[-1], spec, spec["tail_cap"], -1.0)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return new_object("shell", bm, mats)


def _cap(bm, ring, y, spec, cap, sign):
    """Close the end of the loft with a lip and a sunken face rather than a flat fan, so the
    mouths in the nose and the vents in the tail are real openings with a rim round them."""
    cen = Vector((0.0, 0.0, 0.0))
    for v in ring:
        cen += v.co
    cen /= len(ring)
    depth = [0.0] * RING_N
    mat = [PAINT] * RING_N
    for h in range(RING_N):
        hh = half_index(h)
        for (h0, h1, d, m) in cap:
            f = window(hh, h0, h1, 1.4)
            if f > 0.0 and d * f > depth[h]:
                depth[h] = d * f
                if f > 0.5:
                    mat[h] = m
    inner = []
    for h in range(RING_N):
        p = ring[h].co
        q = cen + (p - cen) * cap_shrink(spec)
        q.y = y - sign * (0.026 + depth[h])
        inner.append(bm.verts.new(q))
    floor = spec.get("cap_floor", TYRE)
    cv = bm.verts.new(Vector((0.0, y - sign * (0.030 + sum(depth) / len(depth)), cen.z)))
    for h in range(RING_N):
        h2 = (h + 1) % RING_N
        mm = mat[h] if mat[h] == mat[h2] else PAINT
        try:
            bm.faces.new((ring[h], ring[h2], inner[h2], inner[h])).material_index = \
                mm if depth[h] > 0.018 else PAINT
        except ValueError:
            pass
        try:
            bm.faces.new((inner[h], inner[h2], cv)).material_index = floor
        except ValueError:
            pass


def cap_shrink(spec):
    return spec.get("cap_shrink", 0.58)


# --- openings -------------------------------------------------------------------------------------

def skin_top(spec, y, x):
    """Height of the outer skin's UPPER chain at lateral position x, at station y."""
    half, _ = section(spec, y)
    best = None
    for i in range(H_SHOULDER, len(half) - 1):
        (x0, z0), (x1, z1) = half[i], half[i + 1]
        if (x0 - x) * (x1 - x) <= 0.0 and abs(x1 - x0) > 1e-6:
            z = z0 + (z1 - z0) * (x - x0) / (x1 - x0)
            best = z if best is None else max(best, z)
    return half[H_SHOULDER][1] if best is None else best


def skin_x(spec, y, z):
    """Outermost x of the skin at height z, station y. Details that guess at this instead of
    asking end up floating in the air or buried in the flank."""
    half, _ = section(spec, y)
    best = 0.0
    for i in range(len(half) - 1):
        (x0, z0), (x1, z1) = half[i], half[i + 1]
        if (z0 - z) * (z1 - z) <= 0.0 and abs(z1 - z0) > 1e-6:
            best = max(best, x0 + (x1 - x0) * (z - z0) / (z1 - z0))
    return best if best > 0.0 else max(x for (x, _z) in half)


def arch_cutter(spec, y_axle, sign, mats):
    """The wheel house: an arch profile swept outward from the inner wall, and TAPERED DOWN as
    it goes inboard so its roof always stays under the skin.

    A plain cylinder is the obvious thing and it is wrong. A hypercar's bonnet sits lower than
    its front wing crest, so a cutter tall enough to clear the tyre leaves the body through the
    top of the bonnet at the inner wall; the exact solver then decides the shell is inside the
    cutter and deletes the entire car. Keeping the roof of the cutter under the skin costs
    nothing - the inside of a wheel house is never seen - and makes the cut deterministic.
    """
    xs = [ARCH_INNER_X, 0.78, 0.90, 0.985, 1.60]
    kys = []
    for x in xs:
        if x >= 0.985:
            kys.append(1.0)
            continue
        lo = min(skin_top(spec, y_axle + d, x) for d in (-0.42, -0.21, 0.0, 0.21, 0.42))
        top = max(ARCH_Z + 0.07, min(ARCH_Z + ARCH_R, lo - 0.040))
        kys.append((top - ARCH_Z) / ARCH_R)
    n = 26
    z_cut = ARCH_Z - 0.40
    profs = []
    for ky in kys:
        pts = []
        for i in range(n + 1):
            a = math.pi * i / n
            pts.append((y_axle + ARCH_R * math.cos(a), ARCH_Z + ARCH_R * ky * math.sin(a)))
        pts.append((y_axle - ARCH_R, z_cut))
        pts.append((y_axle + ARCH_R, z_cut))
        profs.append(pts)
    bm = bmesh.new()
    rings = [[bm.verts.new((sign * xs[k], u, v)) for (u, v) in profs[k]] for k in range(len(xs))]
    m = len(profs[0])
    for k in range(len(xs) - 1):
        a, b = rings[k], rings[k + 1]
        for i in range(m):
            j2 = (i + 1) % m
            try:
                bm.faces.new((a[i], a[j2], b[j2], b[i]))
            except ValueError:
                pass
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return new_object("archcut", bm, mats)


def cut_arches(ob, spec, mats):
    for y_axle in (FRONT_AXLE, REAR_AXLE):
        for sign in (1.0, -1.0):
            boolean_cut(ob, arch_cutter(spec, y_axle, sign, mats))
    # Everything the cut exposed is wheel-house lining, not paint. The outer skin at the lip is
    # just outside ARCH_R, so the radius separates the two cleanly.
    me = ob.data
    for poly in me.polygons:
        c = poly.center
        if abs(c.x) <= ARCH_INNER_X - 0.005 or c.z < 0.13:
            continue
        for y_axle in (FRONT_AXLE, REAR_AXLE):
            if (c.y - y_axle) ** 2 + (c.z - ARCH_Z) ** 2 < (ARCH_R - 0.003) ** 2:
                poly.material_index = TYRE
                break


# --- details -----------------------------------------------------------------------------------

def build_details(spec, mats):
    bm = bmesh.new()
    c = spec["c"]
    v = spec["variant"]

    # --- front splitter: a tapered plate, drawn in plan -----------------------------------------
    sw = spec["splitter_w"]
    tip = 2.30
    plan = [(-sw, 1.70), (-sw, 2.02), (-sw * 0.90, 2.20), (-sw * 0.56, tip),
            (sw * 0.56, tip), (sw * 0.90, 2.20), (sw, 2.02), (sw, 1.70)]
    add_prism(bm, plan, 0.004, 0.062, axis='Z', mat=TRIM, bev=0.005)
    for s in (-1.0, 1.0):
        add_prism(bm, [(2.22, 0.062), (2.22, 0.235), (1.84, 0.320), (1.84, 0.095)],
                  s * (sw - 0.030), s * sw, axis='X', mat=TRIM, bev=0.004)
    if v == "b":
        # A central tunnel splitter gets a third fence on the centreline.
        add_prism(bm, [(2.26, 0.062), (2.26, 0.205), (1.90, 0.270), (1.90, 0.090)],
                  -0.026, 0.026, axis='X', mat=TRIM, bev=0.004)

    # --- canards on the front corners ------------------------------------------------------------
    for s in (-1.0, 1.0):
        for (yy, zz, ln, span) in spec["canards"]:
            x0 = skin_x(spec, yy, zz) - 0.035
            add_prism(bm, [(yy, zz), (yy - ln, zz + 0.052), (yy - ln - 0.045, zz + 0.038),
                           (yy + 0.028, zz - 0.014)],
                      s * x0, s * (x0 + span), axis='X', mat=TRIM, bev=0.004)

    # --- light blades ------------------------------------------------------------------------
    # Thin, wide, horizontal, and FOLLOWING the top edge of the end panel rather than cutting
    # straight across it: a straight bar on a nose this shallow either floats above the
    # centreline or has to be dropped so low it reads as a bumper.
    for (yy, sgn, bars, mat) in ((NOSE_Y, 1.0, spec["front_lamp"], LIGHT_F),
                                 (TAIL_Y, -1.0, spec["rear_lamp"], LIGHT_R)):
        half, _ = section(spec, yy - sgn * 0.02)
        xmax = max(x for (x, _z) in half)
        for (inset, hgt, frac) in bars:
            xl = xmax * frac
            lo, hi = [], []
            for i in range(15):
                x = -xl + 2.0 * xl * i / 14.0
                t = skin_top(spec, yy - sgn * 0.02, abs(x)) - inset
                lo.append((x, t - hgt))
                hi.append((x, t))
            add_prism(bm, lo + list(reversed(hi)), yy - sgn * 0.105, yy - sgn * 0.010,
                      axis='Y', mat=mat, bev=0.004)

    # --- mirrors ---------------------------------------------------------------------------------
    my = spec["screen_y"] - 0.10
    mx = c["w_sh"](my)
    mz = c["z_sh"](my) - 0.02
    for s in (-1.0, 1.0):
        add_cyl(bm, 0.022, 0.15, (s * (mx + 0.066), my + 0.02, mz + 0.060),
                rot=(0.0, math.radians(72.0) * s, 0.0), mat=TRIM, segs=10)
        add_box(bm, (0.082, 0.185, 0.082), (s * (mx + 0.148), my - 0.01, mz + 0.112),
                rot=(0.0, 0.0, math.radians(-7.0 * s)), mat=PAINT, bev=0.022, segs=3)
        add_box(bm, (0.018, 0.158, 0.068), (s * (mx + 0.112), my - 0.02, mz + 0.112),
                rot=(0.0, 0.0, math.radians(-7.0 * s)), mat=GLASS, bev=0.006, segs=2)

    # --- side channel vanes -----------------------------------------------------------------------
    ch = spec["channel"]
    for s in (-1.0, 1.0):
        for i in range(spec["vanes"]):
            zz = 0.355 + i * 0.100
            yy = ch["to"] + 0.13
            xx = skin_x(spec, yy, zz) - 0.028
            add_box(bm, (0.075, 0.215, 0.020), (s * xx, yy + 0.085, zz),
                    rot=(math.radians(7.0), 0.0, 0.0), mat=TRIM, bev=0.006, segs=1)

    # --- roof intake -------------------------------------------------------------------------------
    if v == "a":
        # A scoop moulded into the roof, opening forward, feeding the engine deck.
        # It has to run out into the deck. Ending it in mid-air leaves a little red tab behind
        # the roof that reads as a broken spoiler.
        prof = [(spec["roof_f"] - 0.10, c["z_roof"](spec["roof_f"] - 0.10) - 0.01),
                (spec["roof_f"] - 0.10, c["z_roof"](spec["roof_f"] - 0.10) + 0.072),
                (spec["roof_r"] - 0.42, c["z_roof"](spec["roof_r"] - 0.42) + 0.040),
                (-1.40, c["z_roof"](-1.40) + 0.006),
                (-1.40, c["z_roof"](-1.40) - 0.030)]
        add_prism(bm, prof, -0.175, 0.175, axis='X', mat=PAINT, bev=0.014)
        add_prism(bm, [(spec["roof_f"] - 0.095, c["z_roof"](spec["roof_f"] - 0.10) + 0.004),
                       (spec["roof_f"] - 0.095, c["z_roof"](spec["roof_f"] - 0.10) + 0.064),
                       (spec["roof_f"] - 0.19, c["z_roof"](spec["roof_f"] - 0.19) + 0.050),
                       (spec["roof_f"] - 0.19, c["z_roof"](spec["roof_f"] - 0.19) + 0.010)],
                  -0.145, 0.145, axis='X', mat=TYRE, bev=0.006)
    else:
        # A snorkel above the roof running back into a shark fin on the engine cover.
        zr = c["z_roof"](spec["roof_f"] - 0.02)
        add_prism(bm, [(spec["roof_f"] + 0.02, zr - 0.01), (spec["roof_f"] + 0.02, zr + 0.115),
                       (spec["roof_r"] - 0.16, c["z_roof"](spec["roof_r"] - 0.16) + 0.085),
                       (spec["roof_r"] - 0.16, c["z_roof"](spec["roof_r"] - 0.16) - 0.02)],
                  -0.135, 0.135, axis='X', mat=TRIM, bev=0.012)
        add_prism(bm, [(spec["roof_f"] + 0.025, zr + 0.012), (spec["roof_f"] + 0.025, zr + 0.105),
                       (spec["roof_f"] - 0.085, zr + 0.098), (spec["roof_f"] - 0.085, zr + 0.020)],
                  -0.105, 0.105, axis='X', mat=TYRE, bev=0.005)
        fin = [(spec["roof_r"] - 0.14, c["z_roof"](spec["roof_r"] - 0.14) + 0.085),
               (-1.62, c["z_roof"](-1.62) + 0.075), (-1.98, c["z_roof"](-1.98) + 0.030),
               (-1.98, c["z_roof"](-1.98) - 0.02),
               (spec["roof_r"] - 0.14, c["z_roof"](spec["roof_r"] - 0.14) - 0.02)]
        add_prism(bm, fin, -0.040, 0.040, axis='X', mat=TRIM, bev=0.010)

    # --- engine deck louvres: thin slats lying in the recessed panel the loft already cut ---------
    for i in range(spec["louvres"]):
        yy = spec["deck_y"] - 0.10 - i * 0.105
        zz = c["z_roof"](yy) - 0.012
        wdt = c["w_rail"](yy) * 0.56
        add_box(bm, (wdt * 2.0, 0.058, 0.010), (0.0, yy, zz),
                rot=(math.radians(10.0), 0.0, 0.0), mat=TRIM, bev=0.003, segs=1)

    # --- diffuser: ramp, strakes, and a closing fence -------------------------------------------------
    d = spec["diffuser"]
    dw = d["half_w"]
    ramp = [(d["y0"], c["z_floor"](d["y0"]) - 0.004), (-2.30, d["z1"]), (-2.30, d["z1"] + 0.052),
            (d["y0"], c["z_floor"](d["y0"]) + 0.050)]
    add_prism(bm, ramp, -dw, dw, axis='X', mat=TRIM, bev=0.006)
    for i in range(d["strakes"]):
        f = (i / (d["strakes"] - 1.0)) * 2.0 - 1.0
        xx = f * (dw - 0.045)
        add_prism(bm, [(d["y0"] + 0.02, c["z_floor"](d["y0"]) + 0.050),
                       (-2.29, d["z1"] + 0.052), (-2.29, d["z1"] + 0.052 + d["strake_h"]),
                       (d["y0"] + 0.02, c["z_floor"](d["y0"]) + 0.050 + d["strake_h"] * 0.35)],
                  xx - 0.016, xx + 0.016, axis='X', mat=TRIM, bev=0.005)

    # --- exhausts ---------------------------------------------------------------------------------
    for (ex, ez, er) in spec["exhausts"]:
        add_cyl(bm, er, 0.16, (ex, -2.245, ez), rot=(math.radians(90.0), 0.0, 0.0),
                mat=TRIM, segs=14)
        add_cyl(bm, er * 0.74, 0.10, (ex, -2.275, ez), rot=(math.radians(90.0), 0.0, 0.0),
                mat=TYRE, segs=14)

    # --- rear wing ----------------------------------------------------------------------------------
    w = spec["wing"]
    half = w["span"] * 0.5
    foil = airfoil(w["chord"], w["thick"], w["camber"], n=16)
    aoa = math.radians(w["aoa"])
    ca, sa = math.cos(aoa), math.sin(aoa)
    main = [(w["y"] - (u * ca - vv * sa), w["z"] + (u * sa + vv * ca)) for (u, vv) in foil]
    add_prism(bm, main, -half, half, axis='X', mat=TRIM, bev=0.003)
    if w.get("flap"):
        f = w["flap"]
        foil2 = airfoil(f["chord"], f["thick"], f["camber"], n=12)
        a2 = math.radians(f["aoa"])
        c2, s2 = math.cos(a2), math.sin(a2)
        flap = [(f["y"] - (u * c2 - vv * s2), f["z"] + (u * s2 + vv * c2)) for (u, vv) in foil2]
        add_prism(bm, flap, -half * 0.97, half * 0.97, axis='X', mat=TRIM, bev=0.003)
    for s in (-1.0, 1.0):
        add_prism(bm, w["endplate"], s * (half - 0.022), s * (half + 0.012), axis='X',
                  mat=TRIM, bev=0.006)
    for s in (-1.0, 1.0):
        for st in w["struts"]:
            add_prism(bm, st, s * (w["strut_x"] - 0.026), s * (w["strut_x"] + 0.026),
                      axis='X', mat=TRIM, bev=0.006)

    ob = new_object("details", bm, mats)
    return ob


# --- the two cars ----------------------------------------------------------------------------------

def curves(keys):
    return {k: Curve(v) for k, v in keys.items()}


# "Vallory Tempest": mid-engine, tensioned curved surfaces over a hard shoulder line, a single
# swan-neck wing hung from above, a roof scoop feeding the deck.
CAR_A = {
    "variant": "a",
    "title": "Vallory Tempest",
    "step": 0.058,
    "crown_low": 0.030, "crown_up": 0.022, "crown_gl": 0.012,
    "screen_y": 0.72, "roof_f": 0.05, "roof_r": -0.78, "deck_y": -1.58,
    "backlight": GLASS,
    "cap_shrink": 0.60, "cap_floor": TYRE,
    # (drop below the panel's top edge, height, share of the half width) - one blade each end
    "front_lamp": [(0.038, 0.052, 0.86)],
    "rear_lamp": [(0.085, 0.058, 0.90)],
    # (h0, h1, depth, material): what the end cap sinks in and how deep. The lower band is the
    # mouth under the nose / the valance under the tail; the upper band is the corner ducts.
    "nose_cap": [(-1.2, 9.8, 0.150, TYRE), (11.2, 14.8, 0.030, LIGHT_F)],
    "tail_cap": [(-1.2, 9.2, 0.125, TYRE), (12.4, 16.8, 0.032, LIGHT_R),
                 (19.5, 24.5, 0.038, TRIM)],
    "recess": [
        # exit vent in the top of the front wing. It has to sit clear of the arch's own y range
        # (the axle +/- ARCH_R): a recess inside it deforms the skin the arch cutter is about to
        # meet, and the boolean then eats the car.
        {"y0": 0.56, "y1": 0.95, "h0": 9.0, "h1": 14.0, "depth": 0.055, "mat": TRIM,
         "fade_y": 0.07, "fade_h": 1.0, "mark": 0.45},
        # bonnet outlet on the centreline
        {"y0": 1.12, "y1": 1.48, "h0": 21.5, "h1": 26.0, "depth": 0.030, "mat": TRIM,
         "fade_y": 0.07, "fade_h": 0.9, "mark": 0.45},
        # the ducts that run back from the mouths in the nose face
        {"y0": 1.86, "y1": 2.25, "h0": 4.0, "h1": 9.0, "depth": 0.058, "mat": TYRE,
         "fade_y": 0.12, "fade_h": 1.4},
        # One thin blade of light all the way across each end, wrapped round the corner. Round
        # lamps are what make a modelled car look like a toy.
        {"y0": 2.02, "y1": 2.26, "h0": 11.2, "h1": 14.8, "depth": 0.020, "mat": LIGHT_F,
         "fade_y": 0.08, "fade_h": 0.8},
        {"y0": -2.19, "y1": -2.03, "h0": 12.4, "h1": 16.8, "depth": 0.018, "mat": LIGHT_R,
         "fade_y": 0.06, "fade_h": 0.8},
        # the sunken louvre panel over the engine
        {"y0": -2.22, "y1": -1.58, "h0": 20.0, "h1": 26.0, "depth": 0.030, "mat": TRIM,
         "fade_y": 0.10, "fade_h": 1.6},
    ],
    "channel": {"from": -0.12, "to": -0.98, "depth": 0.150},
    "vanes": 3,
    "louvres": 5,
    "splitter_w": 0.94,
    # (y at the trailing edge, height, chord, span outboard of the skin)
    "canards": [(2.06, 0.285, 0.26, 0.165), (1.99, 0.420, 0.22, 0.150)],
    "exhausts": [(-0.20, 0.435, 0.058), (0.20, 0.435, 0.058)],
    "diffuser": {"y0": -1.70, "z1": 0.395, "half_w": 0.80, "strakes": 5, "strake_h": 0.145},
    "wing": {
        "y": -1.90, "z": 1.250, "chord": 0.40, "thick": 0.085, "camber": -0.035,
        "aoa": 9.0, "span": 1.92, "strut_x": 0.60,
        "endplate": [(-1.64, 1.045), (-2.29, 1.175), (-2.30, 1.395), (-1.68, 1.300)],
        "struts": [[(-1.72, 0.905), (-1.83, 0.905), (-2.00, 1.295), (-1.915, 1.318)]],
    },
    "keys": {
        "z_floor": [(2.30, 0.118), (1.90, 0.072), (1.45, 0.050), (0.60, 0.046), (-0.40, 0.046),
                    (-1.25, 0.056), (-1.70, 0.078), (-2.05, 0.240), (-2.30, 0.400)],
        "w_floor": [(2.30, 0.40), (1.90, 0.70), (1.45, 0.80), (0.00, 0.86), (-1.25, 0.82),
                    (-2.30, 0.64)],
        "z_sill": [(2.30, 0.140), (1.90, 0.108), (1.45, 0.100), (0.00, 0.098), (-1.25, 0.106),
                   (-1.90, 0.165), (-2.30, 0.420)],
        "w_sill": [(2.30, 0.50), (2.10, 0.72), (1.80, 0.93), (1.45, 1.022), (1.10, 0.958),
                   (0.30, 0.940), (-0.30, 0.946), (-0.90, 0.988), (-1.25, 1.026),
                   (-1.80, 0.950), (-2.30, 0.740)],
        "z_sh": [(2.30, 0.395), (2.10, 0.500), (1.85, 0.720), (1.45, 0.865), (1.15, 0.845),
                 (0.75, 0.818), (0.30, 0.822), (-0.30, 0.848), (-0.85, 0.886), (-1.25, 0.905),
                 (-1.70, 0.895), (-2.10, 0.868), (-2.30, 0.830)],
        # The peaks at the two axles are the arch flares. They have to stand a good centimetre
        # proud of the tyre's outer face or the arch has no lip and the wheel reads as buried.
        "w_sh": [(2.30, 0.56), (2.10, 0.77), (1.80, 0.980), (1.45, 1.042), (1.05, 0.978),
                 (0.40, 0.956), (-0.20, 0.966), (-0.80, 1.008), (-1.25, 1.042), (-1.75, 1.000),
                 (-2.10, 0.930), (-2.30, 0.800)],
        "z_belt": [(2.30, 0.360), (2.10, 0.450), (1.80, 0.620), (1.45, 0.746), (1.05, 0.775),
                   (0.72, 0.800), (0.40, 0.890), (0.05, 1.022), (-0.30, 1.040), (-0.78, 1.024),
                   (-1.05, 0.980), (-1.45, 0.932), (-1.90, 0.900), (-2.30, 0.838)],
        "w_belt": [(2.30, 0.40), (2.10, 0.60), (1.80, 0.795), (1.45, 0.860), (1.05, 0.832),
                   (0.72, 0.812), (0.30, 0.800), (0.05, 0.780), (-0.30, 0.766), (-0.78, 0.752),
                   (-1.05, 0.800), (-1.45, 0.842), (-1.90, 0.800), (-2.30, 0.615)],
        "z_rail": [(2.30, 0.330), (1.80, 0.580), (1.45, 0.702), (1.05, 0.736), (0.72, 0.775),
                   (0.40, 0.912), (0.05, 1.068), (-0.30, 1.088), (-0.78, 1.062), (-1.05, 1.002),
                   (-1.45, 0.948), (-1.90, 0.902), (-2.30, 0.840)],
        "w_rail": [(2.30, 0.22), (1.80, 0.52), (1.45, 0.580), (0.72, 0.565), (0.05, 0.505),
                   (-0.30, 0.492), (-0.78, 0.482), (-1.05, 0.552), (-1.45, 0.620),
                   (-1.90, 0.580), (-2.30, 0.420)],
        "z_roof": [(2.30, 0.300), (2.10, 0.400), (1.80, 0.556), (1.45, 0.668), (1.05, 0.706),
                   (0.72, 0.762), (0.40, 0.904), (0.05, 1.094), (-0.30, 1.110), (-0.78, 1.080),
                   (-1.05, 1.016), (-1.45, 0.958), (-1.90, 0.906), (-2.30, 0.845)],
    },
}

# "Kessin Wraithe GT": a harder wedge. Flatter planes, a chisel nose, a squarer Kamm tail, a
# snorkel and shark fin down the spine, and a dual-element wing on straight uprights.
CAR_B = {
    "variant": "b",
    "title": "Kessin Wraithe GT",
    "step": 0.079,
    "crown_low": 0.006, "crown_up": 0.005, "crown_gl": 0.003,
    "screen_y": 0.78, "roof_f": 0.10, "roof_r": -0.70, "deck_y": -1.50,
    "backlight": TRIM,
    "cap_shrink": 0.62, "cap_floor": TYRE,
    # two stacked blades each end: the wedge's own signature, nothing like car a's single bar
    "front_lamp": [(0.030, 0.034, 0.90), (0.092, 0.030, 0.76)],
    "rear_lamp": [(0.070, 0.038, 0.92), (0.140, 0.034, 0.80)],
    "nose_cap": [(-1.2, 10.0, 0.145, TYRE), (11.4, 15.4, 0.028, LIGHT_F)],
    "tail_cap": [(-1.2, 9.8, 0.118, TYRE), (11.6, 14.8, 0.030, LIGHT_R),
                 (16.6, 19.8, 0.030, LIGHT_R), (21.5, 25.2, 0.036, TRIM)],
    "recess": [
        # clear of the arch, same reason as car a
        {"y0": 0.54, "y1": 0.94, "h0": 8.5, "h1": 14.5, "depth": 0.062, "mat": TRIM,
         "fade_y": 0.07, "fade_h": 1.0, "mark": 0.45},
        {"y0": 1.08, "y1": 1.52, "h0": 21.0, "h1": 26.0, "depth": 0.038, "mat": TRIM,
         "fade_y": 0.07, "fade_h": 0.9, "mark": 0.45},
        {"y0": 1.82, "y1": 2.26, "h0": 3.5, "h1": 9.5, "depth": 0.070, "mat": TYRE,
         "fade_y": 0.12, "fade_h": 1.4},
        # a groove struck down the whole flank - the wedge's one long line
        {"y0": -0.34, "y1": 1.00, "h0": 5.6, "h1": 8.6, "depth": 0.024, "mat": PAINT,
         "fade_y": 0.22, "fade_h": 1.0},
        # twin light bars at each end instead of car a's single blade
        {"y0": 2.00, "y1": 2.26, "h0": 11.4, "h1": 15.4, "depth": 0.018, "mat": LIGHT_F,
         "fade_y": 0.08, "fade_h": 0.8},
        {"y0": -2.19, "y1": -2.04, "h0": 11.6, "h1": 14.8, "depth": 0.016, "mat": LIGHT_R,
         "fade_y": 0.06, "fade_h": 0.8},
        {"y0": -2.19, "y1": -2.04, "h0": 16.6, "h1": 19.8, "depth": 0.016, "mat": LIGHT_R,
         "fade_y": 0.06, "fade_h": 0.8},
        {"y0": -2.22, "y1": -1.50, "h0": 19.5, "h1": 26.0, "depth": 0.034, "mat": TRIM,
         "fade_y": 0.10, "fade_h": 1.6},
    ],
    "channel": {"from": -0.05, "to": -0.96, "depth": 0.178},
    "vanes": 4,
    "louvres": 6,
    "splitter_w": 0.99,
    "canards": [(2.10, 0.200, 0.24, 0.160), (2.04, 0.310, 0.24, 0.150),
                (1.98, 0.420, 0.20, 0.140)],
    "exhausts": [(-0.36, 0.400, 0.052), (0.36, 0.400, 0.052)],
    "diffuser": {"y0": -1.66, "z1": 0.330, "half_w": 0.845, "strakes": 7, "strake_h": 0.185},
    "wing": {
        "y": -1.80, "z": 1.300, "chord": 0.36, "thick": 0.080, "camber": -0.030,
        "aoa": 8.0, "span": 1.98, "strut_x": 0.92,
        "flap": {"y": -2.125, "z": 1.378, "chord": 0.175, "thick": 0.070, "camber": -0.040,
                 "aoa": 22.0},
        "endplate": [(-1.58, 1.020), (-2.30, 1.210), (-2.31, 1.500), (-1.62, 1.330)],
        "struts": [[(-1.80, 0.900), (-1.895, 0.900), (-1.925, 1.305), (-1.830, 1.305)],
                   [(-2.07, 0.885), (-2.155, 0.885), (-2.185, 1.275), (-2.100, 1.275)]],
    },
    "keys": {
        "z_floor": [(2.30, 0.100), (1.90, 0.066), (1.45, 0.046), (0.60, 0.042), (-0.40, 0.042),
                    (-1.25, 0.052), (-1.66, 0.070), (-2.05, 0.200), (-2.30, 0.335)],
        "w_floor": [(2.30, 0.46), (1.90, 0.74), (1.45, 0.84), (0.00, 0.89), (-1.25, 0.86),
                    (-2.30, 0.72)],
        "z_sill": [(2.30, 0.125), (1.90, 0.098), (1.45, 0.092), (0.00, 0.090), (-1.25, 0.098),
                   (-1.90, 0.150), (-2.30, 0.360)],
        "w_sill": [(2.30, 0.58), (2.10, 0.82), (1.80, 0.98), (1.45, 1.028), (1.10, 0.970),
                   (0.30, 0.952), (-0.30, 0.958), (-0.90, 1.002), (-1.25, 1.030),
                   (-1.80, 0.985), (-2.30, 0.860)],
        "z_sh": [(2.30, 0.292), (2.10, 0.418), (1.85, 0.680), (1.45, 0.845), (1.15, 0.828),
                 (0.78, 0.805), (0.30, 0.812), (-0.30, 0.842), (-0.85, 0.884), (-1.25, 0.902),
                 (-1.70, 0.900), (-2.10, 0.902), (-2.30, 0.908)],
        "w_sh": [(2.30, 0.66), (2.10, 0.86), (1.80, 1.002), (1.45, 1.045), (1.05, 0.982),
                 (0.40, 0.964), (-0.20, 0.972), (-0.80, 1.010), (-1.25, 1.045), (-1.75, 1.012),
                 (-2.10, 0.978), (-2.30, 0.930)],
        "z_belt": [(2.30, 0.295), (2.10, 0.382), (1.80, 0.585), (1.45, 0.726), (1.05, 0.752),
                   (0.78, 0.778), (0.44, 0.884), (0.10, 1.004), (-0.30, 1.028), (-0.70, 1.014),
                   (-1.05, 0.972), (-1.45, 0.930), (-1.90, 0.906), (-2.30, 0.916)],
        "w_belt": [(2.30, 0.48), (2.10, 0.68), (1.80, 0.830), (1.45, 0.876), (1.05, 0.848),
                   (0.78, 0.828), (0.30, 0.818), (0.10, 0.800), (-0.30, 0.788), (-0.70, 0.774),
                   (-1.05, 0.822), (-1.45, 0.860), (-1.90, 0.836), (-2.30, 0.700)],
        "z_rail": [(2.30, 0.268), (1.80, 0.545), (1.45, 0.686), (1.05, 0.716), (0.78, 0.756),
                   (0.44, 0.908), (0.10, 1.050), (-0.30, 1.078), (-0.70, 1.060), (-1.05, 1.000),
                   (-1.45, 0.948), (-1.90, 0.918), (-2.30, 0.922)],
        "w_rail": [(2.30, 0.26), (1.80, 0.56), (1.45, 0.610), (0.78, 0.592), (0.10, 0.530),
                   (-0.30, 0.518), (-0.70, 0.510), (-1.05, 0.580), (-1.45, 0.645),
                   (-1.90, 0.620), (-2.30, 0.500)],
        "z_roof": [(2.30, 0.196), (2.10, 0.310), (1.80, 0.520), (1.45, 0.650), (1.05, 0.682),
                   (0.78, 0.742), (0.44, 0.900), (0.10, 1.088), (-0.30, 1.110), (-0.70, 1.090),
                   (-1.05, 1.018), (-1.45, 0.958), (-1.90, 0.930), (-2.30, 0.936)],
    },
}

CARS = {"a": CAR_A, "b": CAR_B}


# --- build / export ---------------------------------------------------------------------------------

def build(spec):
    reset_scene()
    mats = make_materials()
    spec["c"] = curves(spec["keys"])
    shell = build_shell(spec, mats)
    shell.data.calc_loop_triangles()
    before = len(shell.data.loop_triangles)
    cut_arches(shell, spec, mats)
    shell.data.calc_loop_triangles()
    if len(shell.data.loop_triangles) < before * 0.7:
        raise SystemExit("arch boolean collapsed the shell of car %s" % spec["variant"])
    bevel(shell, 0.0016, segments=2, angle=15.0)
    det = build_details(spec, mats)
    bevel(det, 0.0012, segments=1, angle=40.0)
    ob = join([shell, det])
    ob.name = PREFIX + spec["variant"]
    ob.data.name = ob.name
    # The model must sit with its lowest body vertex at Z = 0: the arches are drawn against
    # ARCH_Z measured from there, and the game seats that vertex 5 cm above the road.
    zmin = min((ob.matrix_world @ v.co).z for v in ob.data.vertices)
    for v in ob.data.vertices:
        v.co.z -= zmin
    shade(ob)
    return ob


def export(ob, variant):
    path = os.path.join(OUT_DIR, PREFIX + variant + ".glb")
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
        used = sorted({p.material_index for p in me.polygons})
        vs = [v.co for v in me.vertices]
        mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
        mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
        path = export(ob, n)
        print("%s  %-18s tris=%6d  L=%.3f W=%.3f H=%.3f  (x %.3f..%.3f  y %.3f..%.3f  z %.3f..%.3f)"
              % (n, CARS[n]["title"], tris, mx.y - mn.y, mx.x - mn.x, mx.z - mn.z,
                 mn.x, mx.x, mn.y, mx.y, mn.z, mx.z))
        print("   slots used: %s -> %s" % (used, os.path.basename(path)))


if __name__ == "__main__":
    main(sys.argv[1:])
