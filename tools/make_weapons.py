#!/usr/bin/env python3
"""The hero's three guns, modelled, UV-unwrapped and texture-baked in Blender by script.

    blender -b -t 2 --factory-startup -P tools/make_weapons.py -- [ak47] [rocket_launcher] [shotgun] [--nobake]

Writes assets/models/weapon_ak47.glb, weapon_rocket_launcher.glb and weapon_shotgun.glb
(no names = all three). Then run `godot --headless --path . --import` and
`python3 tools/fix_texture_imports.py assets/models`, and commit the .glb, the extracted
`weapon_*_*.jpg` textures and every .import. `--nobake` skips the unwrap and bake and exports
flat colours, which is the fast loop for shape work (a full build is a few minutes a gun).

WHY IT IS BUILT THIS WAY
------------------------
The old guns were a dozen boxes each. What reads as "real" at game distance is mostly three
things, and this script is organised round them:

1. Proportions. Everything is authored in millimetres from real dimensions (an AKM is 880 mm
   with its slant brake, the grip is 335 mm from the butt, the magazine sweeps 90 mm forward).
2. Edges. Nothing real has a knife edge. Every part goes through a Bevel modifier (angle
   limited, so curved lofts stay smooth) and a Weighted Normal modifier, so flat faces shade
   flat and the highlight rolls round a 0.5-1 mm radius. That catch-light on the edges is the
   single biggest difference between a CG box and a machined part.
3. Wear. The finishes are procedural shaders baked to 1K maps per material: a Bevel-node
   edge mask and a local AO mask are baked first, then colour, roughness/metal and normal are
   baked through finishes that use them - parkerised steel with bright steel on the edges,
   oiled wood with grime in the cracks and handled patches, chipped olive paint. The wood
   grain is Poly Haven's CC0 `dark_wood` (fetched into build/weapon_src/ on first run),
   projected along each gun's length so the grain runs down the stock rather than across it.

CONVENTIONS
-----------
Authored in Blender space, millimetres: X right, +Y FORWARD (towards the muzzle), Z up, the
bore on the Y axis. The glTF exporter turns that into Godot's X right, Y up, forward -Z, so a
point (x, y, z) here lands at (x, z, -y) in the game, in metres. Each gun keeps the origin
its old box model had, so the game's hold numbers move a little rather than a lot.

Node names are a contract with the weapon scripts: `Muzzle` (an empty at the muzzle) in every
gun, `Warhead` on the launcher (hidden while it reloads), and on the shotgun `Pump` (the forend
and action bars, which slide back to the `PumpBack` empty), `Shell` (the spent case the script
throws) and `EjectPort`. Every model is original: no maker's marks, logos or text anywhere.
"""

import math
import os
import sys
import time
import urllib.request

import bpy
import bmesh
from mathutils import Matrix, Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO, "assets", "models")
CACHE = os.path.join(REPO, "build", "weapon_src")
S = 0.001  # authored in millimetres
TEX = 1024
# Each object's bake margin is applied without regard to other objects' islands in the same
# image, so the gap between islands (ISLAND_MARGIN, a fraction of the atlas) must be wider
# than two margins or one part's colour bleeds onto its neighbour (the shotgun's rib came out
# with red streaks from the shell's hull at 8 px margins and 4 px gaps).
BAKE_MARGIN = 5
ISLAND_MARGIN = 0.011

# CC0 inputs (Poly Haven, https://polyhaven.com/a/dark_wood): 1K diffuse, height and roughness.
WOOD_SRC = {
    "diff": "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/dark_wood/dark_wood_diff_1k.jpg",
    "disp": "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/dark_wood/dark_wood_disp_1k.jpg",
    "rough": "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/dark_wood/dark_wood_rough_1k.jpg",
}

# Linear mean colour of dark_wood_diff_1k.jpg, what the contrast knob pulls toward.
WOOD_MEAN = (0.114, 0.025, 0.009)

PARTS = []


# ----------------------------------------------------------------------------------------------
# Scene
# ----------------------------------------------------------------------------------------------

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.render.threads_mode = "FIXED"
    sc.render.threads = 2
    sc.cycles.use_denoising = False
    PARTS.clear()


def _link(name, bm):
    bm.normal_update()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = True
    return ob


def _xf(bm, center=(0, 0, 0), axis=None, rot=None):
    """Rotate (local +Y onto `axis`, or by the Euler `rot` in degrees), move to `center` (mm),
    then scale mm -> m."""
    m = Matrix.Identity(4)
    if axis is not None:
        a = Vector(axis).normalized()
        m = Vector((0, 1, 0)).rotation_difference(a).to_matrix().to_4x4()
    if rot is not None:
        from mathutils import Euler
        m = Euler([math.radians(r) for r in rot], "XYZ").to_matrix().to_4x4() @ m
    m = Matrix.Translation(Vector(center)) @ m
    m = Matrix.Scale(S, 4) @ m
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)


# ----------------------------------------------------------------------------------------------
# 2D helpers
# ----------------------------------------------------------------------------------------------

def fillet(pts, radii, seg=3):
    """Round the corners of a closed 2D polygon. `radii` is one number or one per corner."""
    n = len(pts)
    if not isinstance(radii, (list, tuple)):
        radii = [radii] * n
    out = []
    for i in range(n):
        p0, p1, p2 = Vector(pts[i - 1]), Vector(pts[i]), Vector(pts[(i + 1) % n])
        r = radii[i]
        d1, d2 = (p0 - p1), (p2 - p1)
        l1, l2 = d1.length, d2.length
        if r <= 0 or l1 < 1e-6 or l2 < 1e-6:
            out.append(tuple(p1))
            continue
        d1.normalize()
        d2.normalize()
        ang = math.acos(max(-1.0, min(1.0, d1.dot(d2))))
        if ang < 1e-3 or ang > math.pi - 1e-3:
            out.append(tuple(p1))
            continue
        t = r / math.tan(ang / 2)
        t = min(t, 0.45 * l1, 0.45 * l2)
        r = t * math.tan(ang / 2)
        a = p1 + d1 * t
        b = p1 + d2 * t
        c = p1 + (d1 + d2).normalized() * (r / math.sin(ang / 2))
        a0 = math.atan2(a.y - c.y, a.x - c.x)
        a1 = math.atan2(b.y - c.y, b.x - c.x)
        da = a1 - a0
        while da > math.pi:
            da -= 2 * math.pi
        while da < -math.pi:
            da += 2 * math.pi
        for k in range(seg + 1):
            aa = a0 + da * k / seg
            out.append((c.x + r * math.cos(aa), c.y + r * math.sin(aa)))
    return out


def rrect(w, zb, zt, rt, rb, n=4, cx=0.0):
    """Rounded rectangle section in (x, z): width w, from zb to zt, top / bottom corner radii.
    Counter-clockwise from the bottom middle; the same n always gives the same point count."""
    hw = w / 2
    rt = min(rt, hw - 0.01, (zt - zb) / 2 - 0.01)
    rb = min(rb, hw - 0.01, (zt - zb) / 2 - 0.01)
    pts = []
    for cxy, r, a0 in (((hw - rb, zb + rb), rb, -90), ((hw - rt, zt - rt), rt, 0),
                       ((-hw + rt, zt - rt), rt, 90), ((-hw + rb, zb + rb), rb, 180)):
        for k in range(n + 1):
            a = math.radians(a0 + 90 * k / n)
            pts.append((cx + cxy[0] + r * math.cos(a), cxy[1] + r * math.sin(a)))
    return pts


def box_ring(hw, hl, r, n, side_v, bump):
    """CCW rounded-box ring in (x, v): half sizes hw, hl, corner radius r, with extra stations
    `side_v` down both long sides pushed out by bump(v) (ribs, flutes)."""
    def arc(cx, cz, a0):
        return [(cx + r * math.cos(math.radians(a0 + 90 * k / n)),
                 cz + r * math.sin(math.radians(a0 + 90 * k / n))) for k in range(n + 1)]
    pts = arc(hw - r, -hl + r, 270)
    pts += [(hw + bump(v), v) for v in side_v]
    pts += arc(hw - r, hl - r, 0)
    pts += arc(-hw + r, hl - r, 90)
    pts += [(-hw - bump(v), v) for v in reversed(side_v)]
    pts += arc(-hw + r, -hl + r, 180)
    return pts


def ring_normals(ring):
    """Outward 2D normals of a closed CCW ring (for offsetting ribs)."""
    n = len(ring)
    out = []
    for i in range(n):
        a, b = Vector(ring[i - 1]), Vector(ring[(i + 1) % n])
        t = (b - a).normalized()
        out.append((t.y, -t.x))
    return out


def catmull(pts, steps=4, closed=False):
    """Catmull-Rom through 2D or 3D points."""
    P = [Vector(p) for p in pts]
    n = len(P)
    out = []
    segs = n if closed else n - 1
    for i in range(segs):
        p0 = P[(i - 1) % n] if closed else P[max(i - 1, 0)]
        p1 = P[i % n]
        p2 = P[(i + 1) % n]
        p3 = P[(i + 2) % n] if closed else P[min(i + 2, n - 1)]
        for k in range(steps):
            t = k / steps
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    if not closed:
        out.append(P[-1])
    return [tuple(v) for v in out]


def _sorted_keys(xs, ys):
    if xs[0] > xs[-1]:
        return list(reversed(xs)), list(reversed(ys))
    return xs, ys


def smooth(xs, ys, x):
    """Smoothstep between keys (either order) - for section tables."""
    xs, ys = _sorted_keys(xs, ys)
    if x <= xs[0]:
        return ys[0]
    for i in range(len(xs) - 1):
        if x <= xs[i + 1]:
            t = (x - xs[i]) / (xs[i + 1] - xs[i])
            t = t * t * (3 - 2 * t)
            return ys[i] + (ys[i + 1] - ys[i]) * t
    return ys[-1]


def lerp_keys(xs, ys, x):
    xs, ys = _sorted_keys(xs, ys)
    if x <= xs[0]:
        return ys[0]
    for i in range(len(xs) - 1):
        if x <= xs[i + 1]:
            t = (x - xs[i]) / (xs[i + 1] - xs[i])
            return ys[i] + (ys[i + 1] - ys[i]) * t
    return ys[-1]


# ----------------------------------------------------------------------------------------------
# Mesh builders (all in mm)
# ----------------------------------------------------------------------------------------------

def loft(name, rings, cap0=True, cap1=True):
    """Skin a list of 3D rings (same point count, mm) with quads, capping both ends."""
    bm = bmesh.new()
    vr = [[bm.verts.new(Vector(p)) for p in r] for r in rings]
    n = len(rings[0])
    for a, b in zip(vr, vr[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if cap0:
        bm.faces.new(list(reversed(vr[0])))
    if cap1:
        bm.faces.new(vr[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.scale(bm, vec=(S, S, S), verts=bm.verts)
    return _link(name, bm)


def prism(name, pts, x0, x1):
    """A side profile (y, z) extruded across X from x0 to x1 (mm)."""
    return loft(name, [[(x0, y, z) for y, z in pts], [(x1, y, z) for y, z in pts]])


def prism_y(name, pts, y0, y1):
    """A front profile (x, z) extruded along Y."""
    return loft(name, [[(x, y0, z) for x, z in pts], [(x, y1, z) for x, z in pts]])


def prism_z(name, pts, z0, z1):
    """A top profile (x, y) extruded along Z."""
    return loft(name, [[(x, y, z0) for x, y in pts], [(x, y, z1) for x, y in pts]])


def box(name, size, center, rot=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    _xf(bm, center=center, rot=rot)
    return _link(name, bm)


def lathe(name, prof, center=(0, 0, 0), axis=(0, 1, 0), segs=24, closed=False, rot=None, phase=0.0):
    """Revolve a (radius, position-along-axis) profile, mm. r = 0 makes a pole; `closed` joins
    the last point back to the first (a tube with a bore)."""
    bm = bmesh.new()
    rings = []
    for r, t in prof:
        if r <= 1e-6:
            rings.append([bm.verts.new((0.0, t, 0.0))])
        else:
            rings.append([bm.verts.new((r * math.cos(phase + 2 * math.pi * k / segs), t,
                                         r * math.sin(phase + 2 * math.pi * k / segs)))
                          for k in range(segs)])
    pairs = list(zip(rings, rings[1:]))
    if closed:
        pairs.append((rings[-1], rings[0]))
    for A, B in pairs:
        if len(A) == 1 and len(B) == 1:
            continue
        for i in range(segs):
            j = (i + 1) % segs
            if len(A) == 1:
                bm.faces.new((A[0], B[j], B[i]))
            elif len(B) == 1:
                bm.faces.new((A[i], A[j], B[0]))
            else:
                bm.faces.new((A[i], A[j], B[j], B[i]))
    if not closed:
        if len(rings[0]) > 1:
            bm.faces.new(list(reversed(rings[0])))
        if len(rings[-1]) > 1:
            bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _xf(bm, center=center, axis=axis, rot=rot)
    return _link(name, bm)


def cyl(name, r, y0, y1, center=(0, 0, 0), axis=(0, 1, 0), segs=16, r1=None):
    r1 = r if r1 is None else r1
    return lathe(name, [(r, y0), (r1, y1)], center=center, axis=axis, segs=segs)


def dome(name, center, normal, r, h, segs=7, sink=0.8):
    """A rivet or screw head standing `h` proud of a surface along `normal`."""
    prof = [(r, -sink), (r, 0.0), (r * 0.8, h * 0.7), (0.0, h)]
    return lathe(name, prof, center=center, axis=normal, segs=segs)


def ellipsoid(name, center, radii, segs=16, rings=8):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    bmesh.ops.scale(bm, vec=Vector(radii), verts=bm.verts)
    _xf(bm, center=center)
    return _link(name, bm)


def sweep(name, path, section, closed=False, up=(0, 0, 1), cap=True):
    """Sweep a 2D section (u, v) along a 3D path (mm) with parallel-transport frames. u runs
    along the frame's side axis, v along its normal (the `up` hint at the start). `section`
    may be a function of (index, count) returning the section there, for a tapered sweep."""
    P = [Vector(p) for p in path]
    n = len(P)
    tang = []
    for i in range(n):
        if closed:
            t = P[(i + 1) % n] - P[i - 1]
        else:
            t = P[min(i + 1, n - 1)] - P[max(i - 1, 0)]
        tang.append(t.normalized())
    nrm = Vector(up)
    nrm = (nrm - tang[0] * nrm.dot(tang[0])).normalized()
    frames = []
    for i in range(n):
        if i > 0:
            q = tang[i - 1].rotation_difference(tang[i])
            nrm = q @ nrm
            nrm = (nrm - tang[i] * nrm.dot(tang[i])).normalized()
        side = tang[i].cross(nrm).normalized()
        frames.append((side, nrm))
    sec = section if callable(section) else (lambda i, n_: section)
    rings = [[P[i] + frames[i][0] * u + frames[i][1] * v for u, v in sec(i, n)] for i in range(n)]
    bm = bmesh.new()
    vr = [[bm.verts.new(p) for p in r] for r in rings]
    m = len(rings[0])
    pairs = list(zip(vr, vr[1:]))
    if closed:
        pairs.append((vr[-1], vr[0]))
    for a, b in pairs:
        for i in range(m):
            j = (i + 1) % m
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if cap and not closed:
        bm.faces.new(list(reversed(vr[0])))
        bm.faces.new(vr[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.scale(bm, vec=(S, S, S), verts=bm.verts)
    return _link(name, bm)


def circle(r, n=8):
    return [(r * math.cos(2 * math.pi * k / n), r * math.sin(2 * math.pi * k / n)) for k in range(n)]


def rect2(w, h, r=0.0, n=2):
    """Section rectangle (u, v) centred on the path, optional rounded corners."""
    if r <= 0:
        return [(w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2), (-w / 2, -h / 2)]
    pts = rrect(w, -h / 2, h / 2, r, r, n)
    return pts


def grip_loft(name, top, rake, length, w, d, flutes=0.6, grooves=0.0, stations=10, N=24,
              bottom_flare=1.2):
    """A pistol grip lofted down an axis raked `rake` degrees back from vertical: palm swell at
    the back, flatter front, flared butt, optional flutes down the sides and finger grooves
    (`grooves` mm deep, three of them) down the front."""
    rk = math.radians(rake)
    gt = Vector((0.0, -math.sin(rk), -math.cos(rk)))
    gn = Vector((0.0, math.cos(rk), -math.sin(rk)))
    g0 = Vector(top)

    def ring(sv):
        c = g0 + gt * sv
        t = sv / length
        ww = w + 2.8 * math.sin(math.pi * min(1.0, t * 1.1)) + bottom_flare * smooth([0.9, 1.0], [0, 1], t)
        dd = d - 3.5 * t + 2.0 * math.sin(math.pi * min(1.0, t * 1.3)) + 2.0 * smooth([0.88, 1.0], [0, 1], t)
        back = 0.5 + 0.08 * math.sin(math.pi * min(1.0, t * 1.3))
        pts = []
        for k in range(N):
            a = 2 * math.pi * k / N
            ca, sa = math.cos(a), math.sin(a)
            x = (ww / 2) * math.copysign(abs(ca) ** 0.7, ca)
            ex = 0.95 if sa > 0 else 0.7
            v = (dd * (1 - back if sa > 0 else back)) * math.copysign(abs(sa) ** ex, sa)
            if flutes > 0 and abs(ca) > 0.55 and 0.12 < t < 0.9:
                x -= math.copysign(flutes * (0.5 + 0.5 * math.cos(v * 1.1)), ca)
            if grooves > 0 and sa > 0.6 and 0.08 < t < 0.8:
                v -= grooves * max(0.0, math.sin(math.pi * (t - 0.08) / 0.24)) ** 2
            pts.append(tuple(c + Vector((x, 0, 0)) + gn * v))
        return pts
    ss = [length * (k / (stations - 1)) ** 0.9 for k in range(stations)]
    return loft(name, [ring(sv) for sv in ss])


def tapered(w0, w1, t0, t1, r=1.5, n=2):
    """Section function for sweep(): a rounded rectangle tapering from w0 x t0 to w1 x t1."""
    def f(i, count):
        k = i / max(1, count - 1)
        return rect2(w0 + (w1 - w0) * k, t0 + (t1 - t0) * k, r, n)
    return f


def roll(ob, deg):
    """Turn a built part about the gun's length axis (Y)."""
    ob.data.transform(Matrix.Rotation(math.radians(deg), 4, "Y"))
    return ob


# ----------------------------------------------------------------------------------------------
# Parts: finish, export node, bevel, booleans
# ----------------------------------------------------------------------------------------------

def part(ob, fin, node="Body", bevel=0.6, segs=2, angle=32, cuts=(), wn=True):
    PARTS.append(dict(ob=ob, fin=fin, node=node, bevel=bevel, segs=segs, angle=angle,
                      cuts=list(cuts), wn=wn))
    return ob


def cutter(ob):
    ob.hide_render = True
    ob.display_type = "WIRE"
    return ob


def _apply(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    bpy.data.meshes.remove(old)


def finalize(finishes):
    """Booleans, bevel and weighted normals applied; one material slot per finish; parts joined
    into their export nodes. Returns {node name: object}."""
    mats = {}
    for name in list(finishes) + [p["fin"] for p in PARTS]:
        if name not in mats:
            mats[name] = bpy.data.materials.new(name)
    used_cutters = set()
    for p in PARTS:
        ob = p["ob"]
        for c in p["cuts"]:
            mod = ob.modifiers.new("cut", "BOOLEAN")
            mod.operation = "DIFFERENCE"
            mod.solver = "EXACT"
            mod.object = c
            used_cutters.add(c.name)
        if p["bevel"] > 0:
            b = ob.modifiers.new("bevel", "BEVEL")
            b.width = p["bevel"] * S
            b.segments = p["segs"]
            b.limit_method = "ANGLE"
            b.angle_limit = math.radians(p["angle"])
            b.use_clamp_overlap = True
            b.miter_outer = "MITER_ARC"
        if p["wn"]:
            w = ob.modifiers.new("wn", "WEIGHTED_NORMAL")
            w.mode = "FACE_AREA"
            w.weight = 50
            w.keep_sharp = True
        _apply(ob)
        ob.data.materials.clear()
        ob.data.materials.append(mats[p["fin"]])
        p["tris"] = tris(ob)
    if os.environ.get("WEAPON_PARTS"):
        by = {}
        for p in PARTS:
            k = p["ob"].name.split(".")[0]
            by[k] = by.get(k, 0) + p["tris"]
        for k, v in sorted(by.items(), key=lambda kv: -kv[1])[:24]:
            print("    part %-20s %6d" % (k, v))
    for name in used_cutters:
        bpy.data.objects.remove(bpy.data.objects[name])
    nodes = {}
    for p in PARTS:
        nodes.setdefault(p["node"], []).append(p["ob"])
    out = {}
    for node, obs in nodes.items():
        bpy.ops.object.select_all(action="DESELECT")
        for o in obs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = obs[0]
        if len(obs) > 1:
            bpy.ops.object.join()
        ob = bpy.context.view_layer.objects.active
        ob.name = node
        ob.data.name = node
        out[node] = ob
    return out


def pivot(ob, at_mm, roll=0.0):
    """Move an object's origin to a point (mm) and turn its axes `roll` degrees about the
    gun's length, without moving its mesh - so a hinged part turns about its own hinge."""
    m = Matrix.Translation(Vector(at_mm) * S) @ Matrix.Rotation(math.radians(roll), 4, "Y")
    ob.data.transform(m.inverted())
    ob.matrix_world = m


def empty(name, at_mm):
    ob = bpy.data.objects.new(name, None)
    ob.location = Vector(at_mm) * S
    bpy.context.scene.collection.objects.link(ob)
    return ob


def tris(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


# ----------------------------------------------------------------------------------------------
# Finishes: procedural node trees, baked
# ----------------------------------------------------------------------------------------------

class NB:
    """Tiny node-graph builder."""

    def __init__(self, nt):
        self.nt = nt
        self.n = nt.nodes
        self.l = nt.links

    def put(self, sock, v):
        if isinstance(v, bpy.types.NodeSocket):
            self.l.new(v, sock)
        elif isinstance(v, (tuple, list)):
            vv = list(v)
            if len(sock.default_value) == 4 and len(vv) == 3:
                vv.append(1.0)
            sock.default_value = vv
        else:
            sock.default_value = v

    def math(self, op, a, b=0.0, clamp=False):
        m = self.n.new("ShaderNodeMath")
        m.operation = op
        m.use_clamp = clamp
        self.put(m.inputs[0], a)
        self.put(m.inputs[1], b)
        return m.outputs[0]

    def add(self, a, b):
        return self.math("ADD", a, b)

    def mul(self, a, b):
        return self.math("MULTIPLY", a, b)

    def sub(self, a, b):
        return self.math("SUBTRACT", a, b)

    def clamp01(self, a):
        return self.math("ADD", a, 0.0, clamp=True)

    def vmath(self, op, a, b=None, scale=None):
        m = self.n.new("ShaderNodeVectorMath")
        m.operation = op
        self.put(m.inputs[0], a)
        if b is not None:
            self.put(m.inputs[1], b)
        if scale is not None:
            self.put(m.inputs[3], scale)
        return m.outputs[1] if op in ("DOT_PRODUCT", "LENGTH", "DISTANCE") else m.outputs[0]

    def noise(self, vec, scale, detail=4.0, rough=0.55, dist=0.0):
        t = self.n.new("ShaderNodeTexNoise")
        self.put(t.inputs["Vector"], vec)
        t.inputs["Scale"].default_value = scale
        t.inputs["Detail"].default_value = detail
        t.inputs["Roughness"].default_value = rough
        t.inputs["Distortion"].default_value = dist
        return t.outputs["Fac"]

    def smooth(self, x, a, b, c=0.0, d=1.0):
        m = self.n.new("ShaderNodeMapRange")
        m.interpolation_type = "SMOOTHSTEP"
        m.clamp = True
        self.put(m.inputs[0], x)
        m.inputs[1].default_value = a
        m.inputs[2].default_value = b
        m.inputs[3].default_value = c
        m.inputs[4].default_value = d
        return m.outputs[0]

    def mixc(self, f, a, b):
        m = self.n.new("ShaderNodeMix")
        m.data_type = "RGBA"
        m.clamp_factor = True
        self.put(m.inputs[0], f)
        self.put(m.inputs[6], a)
        self.put(m.inputs[7], b)
        return m.outputs[2]

    def mixf(self, f, a, b):
        m = self.n.new("ShaderNodeMix")
        m.data_type = "FLOAT"
        m.clamp_factor = True
        self.put(m.inputs[0], f)
        self.put(m.inputs[2], a)
        self.put(m.inputs[3], b)
        return m.outputs[0]

    def cmul(self, c, f):
        """Colour times a scalar."""
        return self.vmath("SCALE", c, scale=f)

    def combine(self, x, y, z):
        m = self.n.new("ShaderNodeCombineXYZ")
        self.put(m.inputs[0], x)
        self.put(m.inputs[1], y)
        self.put(m.inputs[2], z)
        return m.outputs[0]

    def sep(self, v):
        m = self.n.new("ShaderNodeSeparateXYZ")
        self.put(m.inputs[0], v)
        return m.outputs

    def img(self, image, vec, closest=False):
        t = self.n.new("ShaderNodeTexImage")
        t.image = image
        t.interpolation = "Closest" if closest else "Linear"
        t.extension = "REPEAT"
        self.put(t.inputs["Vector"], vec)
        return t


def fetch(url, name):
    os.makedirs(CACHE, exist_ok=True)
    # build/ sits inside the Godot project: keep the editor from importing the cache
    open(os.path.join(CACHE, ".gdignore"), "a").close()
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        print("fetching", url)
        req = urllib.request.Request(url, headers={"User-Agent": "rando-game-asset-fetch/1.0"})
        with urllib.request.urlopen(req, timeout=180) as r, open(path, "wb") as f:
            f.write(r.read())
    return path


_WOOD = {}


def wood_images():
    if not _WOOD:
        for k, url in WOOD_SRC.items():
            img = bpy.data.images.load(fetch(url, "dark_wood_%s_1k.jpg" % k))
            if k != "diff":
                img.colorspace_settings.name = "Non-Color"
            _WOOD[k] = img
    return _WOOD


# A finish is a dict of knobs for build_finish(). Colours are linear RGB.
def finish(**kw):
    f = dict(
        base=(0.05, 0.05, 0.05), base2=None, tone_scale=5.0, tone_amt=0.5, speck=0.12,
        rough=0.5, rough2=None, rough_scale=30.0, metal=0.0,
        wear=0.0, wear_col=(0.5, 0.5, 0.5), wear_rough=0.3, wear_metal=1.0, wear_lo=0.3,
        wear_hi=0.5, wear_break=1.0,
        grime=0.4, grime_col=(0.04, 0.035, 0.03), grime_rough=0.75,
        pit=0.3, pit_scale=2200.0, bump=0.00025,
        scratch=0.0, scratch_col=None,
        wood=False, wood_tile=0.5, wood_tint=(1.0, 1.0, 1.0), wood_gain=1.0,
        marble=0.0, marble_col=None,
        chip_depth=0.0, handled=0.0, handled_col=None, handled_rough=-0.12,
        wood_bump=12.0, wood_contrast=0.75, dents=0.0,
        edge_radius=2.2, edge_gain=3.5, ao_dist=0.012,
    )
    f.update(kw)
    return f


def _triplanar(g, geo, image, tile):
    """Wood sampled with the grain along +Y (the gun's length) on every face."""
    pos = g.vmath("SCALE", geo.outputs["Position"], scale=1.0 / tile)
    px, py, pz = g.sep(pos)
    nx, ny, nz = g.sep(geo.outputs["Normal"])
    wx = g.math("POWER", g.math("ABSOLUTE", nx), 4.0)
    wy = g.math("POWER", g.math("ABSOLUTE", ny), 4.0)
    wz = g.math("POWER", g.math("ABSOLUTE", nz), 4.0)
    tot = g.add(g.add(wx, wy), wz)
    # X-facing: u = y (grain), v = z. Z-facing: u = y, v = x. Y-facing (end grain): (x, z).
    sx = g.img(image, g.combine(py, pz, 0.0)).outputs["Color"]
    sz = g.img(image, g.combine(py, g.add(px, 0.37), 0.0)).outputs["Color"]
    sy = g.img(image, g.combine(g.mul(px, 3.0), g.mul(pz, 0.4), 0.0)).outputs["Color"]
    c = g.vmath("ADD", g.vmath("SCALE", sx, scale=g.math("DIVIDE", wx, tot)),
                g.vmath("SCALE", sz, scale=g.math("DIVIDE", wz, tot)))
    return g.vmath("ADD", c, g.vmath("SCALE", sy, scale=g.math("DIVIDE", wy, tot)))


def build_finish(mat, F, masks_img):
    """Fill `mat` with the finish graph. Returns a dict of the sockets the passes route out."""
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    g = NB(nt)
    out = g.n.new("ShaderNodeOutputMaterial")
    geo = g.n.new("ShaderNodeNewGeometry")
    P = geo.outputs["Position"]
    uv = g.n.new("ShaderNodeUVMap")
    uv.uv_map = "UVMap"
    mask_node = g.img(masks_img, uv.outputs["UV"], closest=True)
    ms = g.sep(mask_node.outputs["Color"])
    edge, ao = ms[0], ms[1]

    # --- live masks (the first pass bakes these)
    bev = g.n.new("ShaderNodeBevel")
    bev.samples = 8
    bev.inputs["Radius"].default_value = F["edge_radius"] * S
    d = g.vmath("DOT_PRODUCT", bev.outputs["Normal"], geo.outputs["Normal"])
    edge_live = g.math("MULTIPLY", g.sub(1.0, d), F["edge_gain"], clamp=True)
    aon = g.n.new("ShaderNodeAmbientOcclusion")
    aon.samples = 16
    aon.only_local = True
    aon.inputs["Distance"].default_value = F["ao_dist"]
    masks_live = g.combine(edge_live, aon.outputs["AO"], 0.0)

    # --- noise fields
    n_large = g.noise(P, F["tone_scale"], 3.0, 0.5)
    n_med = g.noise(P, F["rough_scale"], 6.0, 0.6)
    n_fine = g.noise(P, 320.0, 4.0, 0.55)
    n_micro = g.noise(P, F["pit_scale"], 2.0, 0.5)

    # --- wear: convex edges (unoccluded), broken up so it chips rather than outlines
    convex = g.mul(edge, g.smooth(ao, 0.55, 0.95))
    wv = g.mul(convex, F["wear"])
    br = F["wear_break"]
    wv = g.add(wv, g.mul(g.sub(n_med, 0.5), 0.55 * br))
    wv = g.add(wv, g.mul(g.sub(n_fine, 0.5), 0.35 * br))
    wv = g.add(wv, g.mul(g.sub(n_large, 0.5), 0.25 * br))
    wear = g.smooth(wv, F["wear_lo"], F["wear_hi"]) if F["wear"] > 0 else 0.0
    # handled areas: broad soft patches where hands rub (polish on wood, bare patches on paint)
    handled = g.mul(g.smooth(n_large, 0.55, 0.8), F["handled"]) if F["handled"] > 0 else 0.0

    # --- grime in cavities
    gv = g.add(g.mul(g.sub(1.0, ao), 1.7 * F["grime"]), g.mul(g.sub(n_large, 0.5), 0.5 * F["grime"]))
    gv = g.add(gv, g.mul(g.sub(n_med, 0.5), 0.25))
    grime = g.smooth(gv, 0.2, 0.75)

    # --- base colour
    if F["wood"]:
        W = wood_images()
        wc = _triplanar(g, geo, W["diff"], F["wood_tile"])
        wh = g.sep(_triplanar(g, geo, W["disp"], F["wood_tile"]))[0]
        wr = g.sep(_triplanar(g, geo, W["rough"], F["wood_tile"]))[0]
        # pull the grain's contrast toward the scan's own average colour, then tint
        wc = g.mixc(F["wood_contrast"], WOOD_MEAN, wc)
        col = g.vmath("MULTIPLY", wc, F["wood_tint"])
        col = g.cmul(col, F["wood_gain"])
    else:
        wh = None
        wr = None
        b2 = F["base2"] if F["base2"] is not None else F["base"]
        tone = g.smooth(n_large, 0.5 - F["tone_amt"] * 0.5, 0.5 + F["tone_amt"] * 0.5)
        col = g.mixc(tone, F["base"], b2)
        if F["marble"] > 0:
            mv = g.noise(P, F["tone_scale"] * 3.0, 5.0, 0.6, dist=4.0)
            col = g.mixc(g.mul(g.smooth(mv, 0.45, 0.7), F["marble"]), col, F["marble_col"])
    col = g.cmul(col, g.add(1.0 - F["speck"], g.mul(n_fine, 2 * F["speck"])))
    if F["handled"] > 0:
        # hands darken and oil wood; on paint they rub it thin down to the grey phosphate
        if F["handled_col"] is not None:
            col = g.mixc(g.mul(handled, 0.75), col, F["handled_col"])
        else:
            col = g.cmul(col, g.sub(1.0, g.mul(handled, 0.2)))
    col = g.mixc(g.mul(grime, 0.8), col, F["grime_col"])
    if F["scratch"] > 0:
        # fine scuffs running along the gun (holsters, slings, benches), in sparse patches
        sp = g.vmath("MULTIPLY", P, (700.0, 22.0, 700.0))
        sc = g.smooth(g.noise(sp, 1.0, 2.0, 0.5), 0.635, 0.655)
        sc = g.mul(sc, g.smooth(g.noise(P, 11.0, 2.0), 0.56, 0.7))
        sc = g.mul(sc, F["scratch"])
        col = g.mixc(sc, col, F["scratch_col"] or F["wear_col"])
    else:
        sc = 0.0
    wcol = g.cmul(F["wear_col"], g.add(0.85, g.mul(n_fine, 0.3)))
    col = g.mixc(wear, col, wcol)

    # --- roughness / metal
    if F["wood"]:
        rough = g.add(g.mul(wr, 0.35), F["rough"] - 0.17)
    else:
        rough = g.mixf(n_med, F["rough"], F["rough2"] if F["rough2"] is not None else F["rough"])
    if F["handled"] > 0:
        rough = g.add(rough, g.mul(handled, F["handled_rough"]))
    rough = g.mixf(grime, rough, F["grime_rough"])
    if F["scratch"] > 0:
        rough = g.mixf(g.mul(sc, 0.7), rough, F["wear_rough"])
    rough = g.mixf(wear, rough, F["wear_rough"])
    rough = g.math("ADD", rough, 0.0, clamp=True)
    metal = g.mixf(wear, F["metal"], F["wear_metal"])
    if F["scratch"] > 0:
        metal = g.mixf(sc, metal, F["wear_metal"])

    # --- height -> bump
    h = g.mul(n_micro, F["pit"])
    h = g.add(h, g.mul(n_fine, F["pit"] * 0.6))
    if wh is not None:
        h = g.add(h, g.mul(g.sub(wh, 0.42), F["wood_bump"]))
    if F["dents"] > 0:
        # knocks: small soft dents where a cellular pattern peaks
        vor = g.n.new("ShaderNodeTexVoronoi")
        g.put(vor.inputs["Vector"], P)
        vor.inputs["Scale"].default_value = 90.0
        vor.feature = "F1"
        dmask = g.smooth(g.noise(P, 9.0, 2.0), 0.55, 0.7)
        h = g.sub(h, g.mul(g.mul(g.smooth(vor.outputs["Distance"], 0.18, 0.0), dmask), F["dents"]))
    if F["chip_depth"] > 0:
        h = g.sub(h, g.mul(wear, F["chip_depth"]))
    if F["scratch"] > 0:
        h = g.sub(h, g.mul(sc, 0.25))
    bump = g.n.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 1.0
    bump.inputs["Distance"].default_value = F["bump"]
    g.put(bump.inputs["Height"], h)

    bsdf = g.n.new("ShaderNodeBsdfPrincipled")
    g.put(bsdf.inputs["Base Color"], col)
    g.put(bsdf.inputs["Roughness"], rough)
    g.put(bsdf.inputs["Metallic"], metal)
    g.l.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    emit = g.n.new("ShaderNodeEmission")
    tgt = g.n.new("ShaderNodeTexImage")
    tgt.name = "BAKE_TARGET"
    nt.nodes.active = tgt
    return dict(out=out, bsdf=bsdf, emit=emit, tgt=tgt, mask_node=mask_node,
                masks=masks_live, albedo=col, mr=g.combine(1.0, rough, metal))


def route(sockets, what):
    nt = sockets["out"].id_data
    for l in list(sockets["out"].inputs["Surface"].links):
        nt.links.remove(l)
    for l in list(sockets["emit"].inputs["Color"].links):
        nt.links.remove(l)
    if what == "normal":
        nt.links.new(sockets["bsdf"].outputs["BSDF"], sockets["out"].inputs["Surface"])
    else:
        nt.links.new(sockets[what], sockets["emit"].inputs["Color"])
        nt.links.new(sockets["emit"].outputs["Emission"], sockets["out"].inputs["Surface"])


def unwrap(objs, atlases, fin_atlas):
    """Smart-project each atlas's faces into its own 0..1 square, across all objects."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        if not o.data.uv_layers:
            o.data.uv_layers.new(name="UVMap")
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.context.tool_settings.mesh_select_mode = (False, False, True)
    for atlas in atlases:
        for o in objs:
            bm = bmesh.from_edit_mesh(o.data)
            names = [m.name for m in o.data.materials]
            for f in bm.faces:
                f.select_set(fin_atlas.get(names[f.material_index]) == atlas)
            bmesh.update_edit_mesh(o.data)
        bpy.ops.uv.smart_project(angle_limit=math.radians(58), island_margin=ISLAND_MARGIN,
                                 area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
        bpy.ops.uv.pack_islands(rotate=True, margin=ISLAND_MARGIN)
    bpy.ops.object.mode_set(mode="OBJECT")


def bake(objs, finishes, fin_atlas, gun, tmp_dir):
    """Bake masks, then albedo, metal/roughness and normal for every atlas. Returns
    {atlas: {pass: image}}."""
    atlases = sorted(set(fin_atlas.values()))
    imgs = {}
    for a in atlases:
        imgs[a] = {}
        for p in ("masks", "albedo", "mr", "normal"):
            im = bpy.data.images.new("%s_%s" % (a, p), TEX, TEX, alpha=False,
                                     is_data=(p != "albedo"))
            if p != "albedo":
                im.colorspace_settings.name = "Non-Color"
            imgs[a][p] = im
    socks = {}
    for o in objs:
        for m in o.data.materials:
            if m.name in socks:
                continue
            a = fin_atlas[m.name]
            socks[m.name] = build_finish(m, finishes[m.name], imgs[a]["masks"])
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    sc = bpy.context.scene
    for p, kind, samples in (("masks", "EMIT", 16), ("albedo", "EMIT", 4), ("mr", "EMIT", 4),
                             ("normal", "NORMAL", 4)):
        t0 = time.time()
        sc.cycles.samples = samples
        for name, s in socks.items():
            s["tgt"].image = imgs[fin_atlas[name]][p]
            s["mask_node"].image = None if p == "masks" else imgs[fin_atlas[name]]["masks"]
            s["tgt"].select = True
            s["out"].id_data.nodes.active = s["tgt"]
            route(s, p)
        bpy.ops.object.bake(type=kind, margin=BAKE_MARGIN, margin_type="EXTEND", use_clear=True,
                            normal_space="TANGENT", uv_layer="UVMap")
        print("  baked %-6s in %.1f s" % (p, time.time() - t0))
    os.makedirs(os.path.join(tmp_dir, gun), exist_ok=True)
    for a in atlases:
        for p, im in imgs[a].items():
            # the exporter names each embedded image after its file, and Godot extracts it as
            # weapon_<gun>_<that name>.jpg
            im.filepath_raw = os.path.join(tmp_dir, gun, "%s_%s.png" % (a, p))
            im.file_format = "PNG"
            im.save()
    return imgs


def final_material(name, imgs):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    g = NB(nt)
    out = g.n.new("ShaderNodeOutputMaterial")
    bsdf = g.n.new("ShaderNodeBsdfPrincipled")
    uv = g.n.new("ShaderNodeUVMap")
    uv.uv_map = "UVMap"
    alb = g.img(imgs["albedo"], uv.outputs["UV"])
    mr = g.img(imgs["mr"], uv.outputs["UV"])
    nrm = g.img(imgs["normal"], uv.outputs["UV"])
    sepc = g.n.new("ShaderNodeSeparateColor")
    g.l.new(mr.outputs["Color"], sepc.inputs["Color"])
    nm = g.n.new("ShaderNodeNormalMap")
    g.l.new(nrm.outputs["Color"], nm.inputs["Color"])
    g.l.new(alb.outputs["Color"], bsdf.inputs["Base Color"])
    g.l.new(sepc.outputs["Green"], bsdf.inputs["Roughness"])
    g.l.new(sepc.outputs["Blue"], bsdf.inputs["Metallic"])
    g.l.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    g.l.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return m


def flat_material(name, F):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    base = F["base"] if not F["wood"] else (0.20, 0.08, 0.035)
    b.inputs["Base Color"].default_value = list(base) + [1.0]
    b.inputs["Roughness"].default_value = F["rough"]
    b.inputs["Metallic"].default_value = F["metal"]
    return m


def reassign(ob, mapping):
    """Swap each face's finish material for its atlas's final material."""
    old = [m.name for m in ob.data.materials]
    finals = []
    for n in old:
        if mapping[n] not in finals:
            finals.append(mapping[n])
    idx = [finals.index(mapping[n]) for n in old]
    fi = [0] * len(ob.data.polygons)
    ob.data.polygons.foreach_get("material_index", fi)
    ob.data.materials.clear()
    for m in finals:
        ob.data.materials.append(m)
    ob.data.polygons.foreach_set("material_index", [idx[i] for i in fi])


def build(gun, maker, nobake):
    reset()
    t0 = time.time()
    spec = maker()
    finishes = spec["finishes"]
    fin_atlas = spec["atlas"]
    nodes = finalize(list(finishes.keys()))
    for name, at in spec.get("pivots", {}).items():
        pivot(nodes[name], at[0], at[1])
    bakeable = list(nodes.values())
    tmp = os.path.join(CACHE, "bake")
    if nobake:
        mapping = {n: flat_material(n + "_flat", F) for n, F in finishes.items()}
        for o in bakeable:
            reassign(o, {m.name: mapping[m.name] for m in o.data.materials})
    else:
        atlases = sorted(set(fin_atlas.values()))
        unwrap(bakeable, atlases, fin_atlas)
        imgs = bake(bakeable, finishes, fin_atlas, gun, tmp)
        finals = {}
        for a in atlases:
            for p in ("albedo", "mr", "normal"):
                imgs[a][p].name = "%s_%s" % (a, p)
            finals[a] = final_material(a, imgs[a])
        for o in bakeable:
            reassign(o, {m.name: finals[fin_atlas[m.name]] for m in o.data.materials})
    empties = [empty(n, at) for n, at in spec["empties"].items()]
    total = 0
    for n, o in nodes.items():
        t = tris(o)
        total += t
        print("  node %-10s %6d triangles" % (n, t))
    print("  %s: %d triangles" % (gun, total))
    bpy.ops.object.select_all(action="DESELECT")
    for o in list(nodes.values()) + empties:
        o.select_set(True)
    path = os.path.join(OUT_DIR, "weapon_%s.glb" % gun)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_apply=True,
        export_image_format="JPEG", export_jpeg_quality=92, export_normals=True,
        export_tangents=False, export_materials="EXPORT", export_yup=True, export_extras=False,
        export_cameras=False, export_lights=False, export_animations=False)
    print("wrote %s (%.0f KB) in %.0f s" % (path, os.path.getsize(path) / 1024, time.time() - t0))


# ----------------------------------------------------------------------------------------------
# AK-47 (the AKM pattern: stamped receiver, slant brake, laminated wood, bakelite grip)
# ----------------------------------------------------------------------------------------------

AK_FIN = {
    # Black enamel over phosphate: dark and semi-gloss, rubbed thin to the grey phosphate where
    # hands go, worn through to bright steel on every edge a hand or a sling rubs.
    "blk": finish(base=(0.019, 0.020, 0.022), base2=(0.032, 0.032, 0.034), tone_amt=0.6,
                  rough=0.36, rough2=0.52, metal=0.5, wear=1.0, wear_col=(0.40, 0.40, 0.41),
                  wear_rough=0.26, wear_metal=1.0, wear_lo=0.26, wear_hi=0.46, grime=0.6,
                  grime_col=(0.020, 0.017, 0.013), pit=0.3, pit_scale=900.0, scratch=0.3,
                  scratch_col=(0.24, 0.24, 0.25), handled=0.55,
                  handled_col=(0.060, 0.059, 0.057), handled_rough=0.08),
    # Parkerised (phosphate) grey-black on the sight blocks, gas block, pins, trigger group.
    "park": finish(base=(0.030, 0.030, 0.029), base2=(0.044, 0.043, 0.040), rough=0.55,
                   rough2=0.68, metal=0.35, wear=0.9, wear_col=(0.40, 0.40, 0.40),
                   wear_rough=0.3, wear_metal=1.0, wear_lo=0.3, wear_hi=0.52, grime=0.6,
                   grime_col=(0.02, 0.018, 0.014), pit=0.45, pit_scale=900.0, scratch=0.2,
                   scratch_col=(0.2, 0.2, 0.2)),
    # Machined bolt carrier, charging handle, cleaning rod: dark bare steel, oil and carbon.
    "bright": finish(base=(0.12, 0.12, 0.125), base2=(0.17, 0.17, 0.17), rough=0.36,
                     rough2=0.5, metal=1.0, wear=0.6, wear_col=(0.45, 0.45, 0.45),
                     wear_rough=0.22, wear_lo=0.35, wear_hi=0.6, grime=0.9,
                     grime_col=(0.018, 0.016, 0.013), pit=0.25, pit_scale=900.0, scratch=0.3,
                     scratch_col=(0.35, 0.35, 0.35)),
    # Laminated birch under a red-brown oil finish: grain from Poly Haven's dark_wood, pulled
    # from its mahogany red toward brown. Edges worn back to paler raw wood, handled patches
    # darker and glossier, knocks and dents in the surface.
    "wood": finish(wood=True, wood_tile=0.45, wood_tint=(0.60, 1.15, 1.45), wood_gain=0.95,
                   wood_bump=8.0,
                   rough=0.47, wear=0.8, wear_col=(0.27, 0.15, 0.075), wear_rough=0.7,
                   wear_metal=0.0, wear_lo=0.32, wear_hi=0.58, grime=0.7,
                   grime_col=(0.018, 0.010, 0.006), grime_rough=0.72, pit=0.06, handled=0.8,
                   handled_rough=-0.14, speck=0.05, edge_radius=2.6, dents=0.6),
    # The plum-brown bakelite pistol grip, marbled, polished glossy by hands at the edges.
    "bakelite": finish(base=(0.042, 0.011, 0.007), base2=(0.068, 0.020, 0.010), tone_amt=0.7,
                       marble=0.6, marble_col=(0.026, 0.007, 0.005), rough=0.26, rough2=0.36,
                       metal=0.0, wear=0.7, wear_col=(0.09, 0.03, 0.016), wear_rough=0.24,
                       wear_metal=0.0, wear_lo=0.3, wear_hi=0.6, grime=0.6, pit=0.15,
                       pit_scale=900.0, handled=0.6),
}
AK_ATLAS = {"blk": "metal", "park": "metal", "bright": "metal", "wood": "wood", "bakelite": "wood"}


def ak47():
    X = 17.0  # receiver half width

    # --- receiver: the stamped box, the ejection port, magazine-guide dimples
    rec = prism("receiver", fillet([(-95, -34), (-95, 11), (175, 11), (175, -40), (-62, -40)],
                                   [2, 1, 1, 1.5, 14]), -X, X)
    port = cutter(box("port_cut", (13, 104, 16), (19.5, 71, 7.5)))
    dim_r = cutter(ellipsoid("dimple_r", (X + 3.4, 97, -9), (4.6, 13, 5.5)))
    dim_l = cutter(ellipsoid("dimple_l", (-X - 3.4, 97, -9), (4.6, 13, 5.5)))
    part(rec, "blk", bevel=0.7, cuts=[port, dim_r, dim_l])
    # bolt carrier seen through the port, and the charging handle on it
    part(box("carrier", (7.5, 100, 10.5), (9.8, 71, 5.6)), "bright", bevel=0.5)
    part(lathe("charging_handle", [(4.2, 10), (4.2, 25), (5.2, 28), (6.4, 31), (6.0, 34.5),
                                    (3.5, 36.5), (0, 37)], center=(0, 116, 5.5),
               axis=(1, 0, 0.16), segs=14), "bright", bevel=0.4)
    # rivets: front trunnion (5 a side), rear trunnion (3 a side); pins for trigger and hammer
    for sx in (1, -1):
        for y, z in ((137, -31), (152, -31), (167, -31), (145, -15), (164, -15),
                     (-84, -25), (-84, -5), (-72, -15)):
            part(dome("rivet", (sx * X, y, z), (sx, 0, 0), 2.5, 1.0), "blk", bevel=0)
        for y, z, r in ((3, -26, 3.0), (-23, -24, 3.0), (-2, -12, 2.4)):
            part(lathe("pin", [(0, 0), (r, 0), (r, 0.9), (r * 0.8, 1.3), (0, 1.3)],
                       center=(sx * (X - 0.4), y, z), axis=(sx, 0, 0), segs=8), "park", bevel=0)

    # --- dust cover: arched, with pressed ribs across the top
    def cover_ring(y, rib):
        base = rrect(35.6, 9.0, 33.0, 15.0, 0.6, n=3)
        if rib <= 0:
            return [(x, y, z) for x, z in base]
        nr = ring_normals(base)
        out = []
        for (x, z), (nx, nz) in zip(base, nr):
            w = rib * smooth([15.0, 22.0], [0.0, 1.0], z)
            out.append((x + nx * w, y, z + nz * w))
        return out
    ys = [-103.0]
    for rc in [-72 + 29 * i for i in range(8)]:
        ys += [rc - 3.4, rc, rc + 3.4]
    ys += [172.0]
    rings = []
    for y in ys:
        rib = 0.0
        for rc in [-72 + 29 * i for i in range(8)]:
            if abs(y - rc) < 0.5:
                rib = 1.2
        rings.append(cover_ring(y, rib))
    part(loft("dust_cover", rings), "blk", bevel=0.6, segs=1)
    part(lathe("cover_button", [(0, -110), (3.4, -110), (4.2, -108), (4.2, -100)],
               center=(0, 0, 18), segs=14), "park", bevel=0.4)

    # --- rear sight: block (holds the gas tube), ramp rails, leaf, slider
    part(prism("rear_sight_block", fillet([(175, -13), (175, 18), (208, 18), (216, 35),
                                          (237, 35), (237, -13)], [3, 1.5, 3, 3, 2, 4]),
               -13, 13), "park", bevel=1.2, segs=3)
    ramp = prism("sight_ramp", [(178, 17), (178, 21), (192, 23.4), (207, 24.6), (207, 17)], -7, 7)
    slot = cutter(box("ramp_slot", (8.5, 40, 10), (0, 193, 25)))
    part(ramp, "park", bevel=0.4, cuts=[slot])
    leaf = prism("sight_leaf", [(166, 24.6), (166, 30.5), (171, 30.5), (171, 27.6), (212, 27.2),
                                (212, 24.6)], -5.5, 5.5)
    notch = cutter(box("notch", (1.8, 8, 4), (0, 168, 30.5)))
    part(leaf, "park", bevel=0.35, cuts=[notch])
    part(box("sight_slider", (15, 7, 6.5), (0, 196, 26.2)), "park", bevel=0.5)
    part(lathe("slider_button", [(0, 0), (2.4, 0), (2.4, 2.2), (1.6, 3.0), (0, 3.0)],
               center=(7.5, 196, 26.2), axis=(1, 0, 0), segs=10), "park", bevel=0)
    part(prism("tube_lever", fillet([(221, 22), (221, 31), (243, 33), (245, 30), (226, 22)],
                                    [1, 2, 1.5, 1.5, 2]), 13, 15.2), "park", bevel=0.4)

    # --- barrel (with a real bore), gas tube, gas block
    part(lathe("barrel", [(0, 176), (10.5, 176), (10.5, 240), (9.6, 246), (9.0, 415),
                          (8.4, 470), (8.2, 521), (3.9, 521), (3.9, 470), (0, 470)], segs=18),
         "blk", bevel=0.4)
    part(lathe("gas_tube", [(0, 226), (8.2, 226), (8.2, 424), (0, 424)], center=(0, 0, 26),
               segs=20), "park", bevel=0.4)
    part(prism("gas_block", fillet([(416, -11.5), (416, 36), (431, 36), (452, 14),
                                    (452, -11.5)], [3, 6, 4, 3, 3]), -11, 11), "park", bevel=1.6,
         segs=3)
    part(lathe("swivel_stud_f", [(0, 0), (3, 0), (3, 3.5), (2.2, 4.2), (0, 4.2)],
               center=(-10.5, 436, -2), axis=(-1, 0, 0), segs=10), "park", bevel=0)
    loop = [(-15.2, 436 + 8 * math.sin(a), -9 - 9 * math.cos(a)) for a in
            [2 * math.pi * k / 16 for k in range(16)]]
    part(sweep("swivel_f", loop, circle(1.5, 8), closed=True, up=(1, 0, 0)), "park", bevel=0)

    # --- front sight: base, open-topped hood, post; cleaning rod under the barrel
    part(prism("front_sight_base", fillet([(480, -12.5), (480, 5), (492, 20.5), (515, 20.5),
                                          (517, 5), (517, -12.5)], [3, 5, 3, 3, 4, 3]),
               -10, 10), "park", bevel=1.5, segs=3)
    # the hood is a ring round the post, seen end-on down the sights, open at the top
    hood = lathe("sight_hood", [(8.3, -5.5), (11.3, -5.5), (11.3, 5.5), (8.3, 5.5)],
                 center=(0, 505, 30), segs=16, closed=True)
    slot2 = cutter(box("hood_slot", (7.6, 20, 12), (0, 505, 41)))
    part(hood, "park", bevel=0.5, cuts=[slot2])
    part(lathe("sight_post", [(3.2, 0), (3.2, 3.0), (1.4, 4.2), (1.2, 10.5), (0.9, 11.3),
                              (0, 11.3)], center=(0, 505, 20), axis=(0, 0, 1), segs=12),
         "park", bevel=0)
    part(lathe("cleaning_rod", [(0, 392), (2.9, 392), (2.9, 499), (3.9, 501), (3.9, 513),
                                (2.8, 516), (0, 516)], center=(0, 0, -16), segs=12),
         "bright", bevel=0)

    # --- slant muzzle brake: a bored tube with its upper right front cut away
    brake = lathe("brake", [(5.2, 512), (11.6, 512), (11.9, 515), (11.9, 550), (5.2, 550)],
                  segs=20, closed=True)
    n = Vector((0.42, 0.78, 0.62)).normalized()
    p0 = Vector((0, 539, 0))
    cut_b = cutter(box("brake_cut", (80, 80, 80), tuple(p0 + n * 40)))
    q = Vector((0, 0, 1)).rotation_difference(n)
    cut_b.data.transform(Matrix.Translation(-(p0 + n * 40) * S))
    cut_b.data.transform(q.to_matrix().to_4x4())
    cut_b.data.transform(Matrix.Translation((p0 + n * 40) * S))
    part(brake, "blk", bevel=0.5, cuts=[cut_b])

    # --- handguards: upper over the gas tube, lower with the palm swell; steel ferrules
    def upper_ring(y):
        w = lerp_keys([238, 392], [29.0, 27.0], y)
        k = 1.0
        if y < 240.5 or y > 389.5:
            k = 0.94
        r = rrect(w * k, 15.5 + (1 - k) * 8, 15.5 + (38 - 15.5) * k, 10.5 * k, 2.0, n=4)
        return [(x, y, z) for x, z in r]
    part(loft("upper_handguard", [upper_ring(y) for y in (238, 240.5, 260, 300, 340, 389.5, 392)]),
         "wood", bevel=0.8)

    def lower_ring(y):
        w = 44.5 + 6.0 * smooth([238, 262, 300, 318], [0, 1, 1, 0], y) - 1.5 * (y - 238) / 150
        k = 0.95 if (y < 240.5 or y > 385.5) else 1.0
        r = rrect(w * k, -27.0 * k, 13.5, 5.0, 15.0 * k, n=4)
        return [(x, y, z) for x, z in r]
    part(loft("lower_handguard", [lower_ring(y) for y in
                                  (238, 240.5, 250, 262, 280, 300, 318, 335, 360, 385.5, 388)]),
         "wood", bevel=0.8)
    fer = rrect(47.0, -28.8, 15.8, 5.5, 16.5, n=4)
    part(loft("rear_ferrule", [[(x, y, z) for x, z in fer] for y in (231, 240)]), "park",
         bevel=0.5)
    fer2 = rrect(45.5, -28.3, 15.2, 5.5, 16.0, n=4)
    part(loft("front_ferrule", [[(x, y, z) for x, z in fer2] for y in (387, 400)]), "park",
         bevel=0.5)
    part(prism("guard_lever", fillet([(384, -8), (384, 5), (404, 10), (407, 7), (389, -8)],
                                     [1.5, 2, 1.5, 1.5, 2]), 22.4, 24.6), "park", bevel=0.4)

    # --- magazine: curved, ribbed steel, 30 rounds' worth of sweep
    R, th0, L = 330.0, math.radians(8.0), 205.0
    top = Vector((0.0, 97.0, -30.0))

    def mag_frame(s):
        th = th0 + s / R
        # centreline integral of (0, sin th, -cos th)
        c = top + Vector((0.0, R * (math.cos(th0) - math.cos(th)), -R * (math.sin(th) - math.sin(th0))))
        return c, Vector((0.0, math.cos(th), math.sin(th)))

    def mag_ring(s, grow=0.0):
        c, nv = mag_frame(s)
        t = max(0.0, s) / L
        hw = (28.5 - 2.0 * t + grow) / 2
        hl = (71.0 - 7.0 * t + grow * 1.6) / 2
        vs = []
        for rc in (-12.0, 12.0):
            vs += [rc - 3.8, rc - 2.0, rc + 2.0, rc + 3.8]
        rib = lambda v: 1.15 if (grow == 0 and any(abs(v - rc) < 2.1 for rc in (-12.0, 12.0))) else 0.0
        return [tuple(c + Vector((x, 0, 0)) + nv * v) for x, v in box_ring(hw, hl, 4.5, 2, vs, rib)]

    ss = [-10.0] + [L * k / 14 for k in range(15)]
    part(loft("magazine", [mag_ring(s) for s in ss]), "blk", bevel=0.6, segs=1, angle=40)
    part(loft("mag_floor", [mag_ring(s, 1.4) for s in (L - 7.0, L + 1.2)]), "blk",
         bevel=0.7)
    c, nv = mag_frame(8.0)
    part(box("mag_catch_lug", (11, 6, 7), tuple(c - nv * 37.5)), "blk", bevel=0.5)

    # --- pistol grip: fluted bakelite, raked 20 degrees
    part(grip_loft("pistol_grip", (0.0, -40.0, -30.0), 20.0, 106.0, 28.5, 43.0), "bakelite",
         bevel=0.8)

    # --- trigger guard, magazine release paddle, trigger
    tg = catmull([(0, 55, -39.5), (0, 55.5, -47), (0, 50, -57), (0, 39, -60.5), (0, 0, -61.5),
                  (0, -10, -59.5), (0, -15.5, -52), (0, -17, -39.5)], steps=3)
    part(sweep("trigger_guard", tg, rect2(12.5, 2.6, 0.9, n=1), up=(0, 0, 1)), "park", bevel=0)
    pad = catmull([(0, 58.5, -39), (0, 59, -47), (0, 61.5, -56.5), (0, 64.5, -60.5)], steps=3)
    part(sweep("mag_release", pad, rect2(12.0, 2.6, 0.9), up=(0, 1, 0)), "park", bevel=0)
    trig = catmull([(0, 6, -38), (0, 6.5, -44), (0, 4.5, -51), (0, 1, -56), (0, -2.5, -58)],
                   steps=3)
    part(sweep("trigger", trig, rect2(6.0, 4.2, 1.4), up=(0, 1, 0)), "park", bevel=0)

    # --- selector lever on the right, at SAFE (lying along the top of the receiver side)
    part(prism("selector", fillet([(-86, -8), (-86, 4), (-77, 8.5), (62, 10.2), (71, 10.2),
                                   (73, 6), (73, -3.5), (64, -3.5), (61, -1.2), (-73, -2),
                                   (-80, -6.5)], [3, 3, 4, 1, 1.5, 1, 1, 1, 2, 3, 2], seg=2),
               X + 0.1, X + 1.7), "blk", bevel=0.35)
    part(lathe("selector_boss", [(0, 0), (6.3, 0), (6.3, 2.6), (5.6, 3.4), (0, 3.4)],
               center=(X, -80, -2), axis=(1, 0, 0), segs=16), "blk", bevel=0)
    part(box("selector_tab", (3.5, 7, 7.5), (X + 3.0, 68.5, -0.5)), "blk", bevel=0.4)

    # --- stock: lofted, dropping to the butt; steel tang, butt plate with trap door, swivel
    def stock_ring(y):
        zt = lerp_keys([-93, -325], [9.0, -27.0], y)
        u = min(1.0, max(0.0, (-93.0 - y) / 232.0))
        zb = -35.0 - 113.0 * u ** 1.22
        w = smooth([-93, -112, -160, -325], [30.0, 32.0, 33.5, 40.0], y)
        return [(x, y, z) for x, z in rrect(w, zb, zt, 0.42 * w, 9.0, n=4)]
    part(loft("stock", [stock_ring(y) for y in
                        [-90, -100, -112, -125, -140, -160, -185, -210, -240, -270, -300,
                         -318, -325]]), "wood", bevel=1.0)

    def butt_ring(y, k):
        r = rrect(41.4 * k, -149.5 * k + (1 - k) * -88, -25.8 * k + (1 - k) * -88, 17, 10, n=4)
        return [(x, y, z) for x, z in r]
    part(loft("butt_plate", [butt_ring(-324.0, 1.0), butt_ring(-330.5, 1.0),
                             butt_ring(-331.3, 0.985)]), "park", bevel=0.6)
    door = rrect(22, -112, -62, 4, 4, n=3)
    part(loft("trap_door", [[(x, -331.0, z) for x, z in door], [(x, -332.0, z) for x, z in door]]),
         "park", bevel=0.3)
    for z in (-40, -136):
        part(dome("butt_screw", (0, -331.2, z), (0, -1, 0), 3.2, 1.2), "park", bevel=0)
    part(prism("stock_tang", [(-90, 6.5), (-90, 10.8), (-138, 3.0), (-138, 0.0)], -4.5, 4.5),
         "blk", bevel=0.5)
    part(dome("tang_screw", (0, -130, 4.3), (0, 0.2, 1), 3.0, 1.1), "park", bevel=0)
    part(prism("swivel_plate_r", fillet([(-298, -80), (-298, -71), (-272, -71), (-272, -80)], 3),
               -21.2, -19.3), "park", bevel=0.4)
    for y in (-294, -276):
        part(dome("plate_screw", (-21.2, y, -75.5), (-1, 0, 0), 1.9, 0.8, segs=8), "park", bevel=0)
    rl = catmull([(-22.5, -291, -76), (-22.5, -291, -86), (-22.5, -285, -92),
                  (-22.5, -279, -86), (-22.5, -279, -76)], steps=3)
    rl = rl + [(-22.5, -285, -74.5)]
    part(sweep("swivel_r", rl, circle(1.6, 8), closed=True, up=(1, 0, 0)), "park", bevel=0)

    return dict(finishes=AK_FIN, atlas=AK_ATLAS, empties={"Muzzle": (0, 550, 0)})


# ----------------------------------------------------------------------------------------------
# Rocket launcher: an original shoulder-fired tube in the RPG pattern (no maker's marks)
# ----------------------------------------------------------------------------------------------

RL_FIN = {
    # Olive drab enamel on steel: chipped through to dark steel on edges, dust in the corners,
    # rubbed glossy where hands and the shoulder go.
    "olive": finish(base=(0.050, 0.056, 0.028), base2=(0.064, 0.068, 0.036), tone_amt=0.7,
                    rough=0.62, rough2=0.76, metal=0.0, wear=1.0, wear_col=(0.16, 0.16, 0.155),
                    wear_rough=0.4, wear_metal=1.0, wear_lo=0.2, wear_hi=0.4, grime=0.9,
                    grime_col=(0.11, 0.095, 0.068), grime_rough=0.9, pit=0.3, pit_scale=700.0,
                    chip_depth=0.5, scratch=0.6, scratch_col=(0.2, 0.2, 0.19), handled=0.85,
                    handled_col=(0.036, 0.038, 0.026), handled_rough=-0.18, bump=0.0003),
    # The warhead: a greener, glossier olive, fresh from its crate.
    "wh_olive": finish(base=(0.038, 0.052, 0.024), base2=(0.046, 0.060, 0.028), tone_amt=0.5,
                       rough=0.42, rough2=0.5, metal=0.0, wear=0.55, wear_col=(0.2, 0.2, 0.19),
                       wear_rough=0.35, wear_metal=1.0, wear_lo=0.4, wear_hi=0.6, grime=0.4,
                       grime_col=(0.09, 0.08, 0.06), pit=0.15, pit_scale=700.0, chip_depth=0.3,
                       scratch=0.15),
    "wh_band": finish(base=(0.20, 0.15, 0.035), base2=(0.23, 0.17, 0.04), rough=0.5, metal=0.0,
                      wear=0.6, wear_col=(0.2, 0.2, 0.19), wear_metal=1.0, wear_lo=0.4,
                      wear_hi=0.6, grime=0.4, pit=0.15, chip_depth=0.3),
    # Black phenolic grips and trigger housing: polished by hands, grey where it is scuffed.
    "black": finish(base=(0.020, 0.019, 0.018), base2=(0.028, 0.026, 0.024), rough=0.5,
                    rough2=0.62, metal=0.0, wear=0.8, wear_col=(0.07, 0.068, 0.065),
                    wear_rough=0.7, wear_metal=0.0, wear_lo=0.3, wear_hi=0.55, grime=0.6,
                    grime_col=(0.09, 0.08, 0.06), pit=0.5, pit_scale=900.0, handled=0.7,
                    handled_rough=-0.2),
    # Black enamel on the optic's aluminium body, worn to bare metal on its edges.
    "scope": finish(base=(0.016, 0.016, 0.017), base2=(0.024, 0.024, 0.025), rough=0.4,
                    rough2=0.5, metal=0.3, wear=0.9, wear_col=(0.5, 0.5, 0.52), wear_rough=0.3,
                    wear_metal=1.0, wear_lo=0.3, wear_hi=0.5, grime=0.5, pit=0.2,
                    pit_scale=900.0, scratch=0.2, scratch_col=(0.3, 0.3, 0.31)),
    "rubber": finish(base=(0.016, 0.016, 0.016), base2=(0.022, 0.021, 0.02), rough=0.82,
                     rough2=0.9, metal=0.0, wear=0.4, wear_col=(0.04, 0.04, 0.04),
                     wear_rough=0.6, wear_metal=0.0, grime=0.8, grime_col=(0.09, 0.08, 0.06),
                     pit=0.8, pit_scale=900.0),
    "glass": finish(base=(0.006, 0.009, 0.016), rough=0.04, metal=0.0, wear=0.0, grime=0.3,
                    grime_col=(0.05, 0.045, 0.035), grime_rough=0.4, pit=0.0),
    "steel": finish(base=(0.05, 0.05, 0.05), base2=(0.07, 0.07, 0.068), rough=0.45,
                    rough2=0.6, metal=0.8, wear=0.9, wear_col=(0.42, 0.42, 0.42),
                    wear_rough=0.28, wear_lo=0.3, wear_hi=0.52, grime=0.6,
                    grime_col=(0.03, 0.027, 0.02), pit=0.4, pit_scale=900.0, scratch=0.3),
    # Heat shields: the same CC0 grain, older and drier than the rifle's.
    "wood": finish(wood=True, wood_tile=0.5, wood_tint=(0.62, 1.1, 1.3), wood_gain=0.95,
                   wood_bump=10.0, wood_contrast=0.7, rough=0.55, wear=0.9,
                   wear_col=(0.26, 0.16, 0.085), wear_rough=0.75, wear_metal=0.0, wear_lo=0.3,
                   wear_hi=0.55, grime=0.8, grime_col=(0.05, 0.04, 0.028), grime_rough=0.85,
                   pit=0.08, handled=0.7, handled_rough=-0.15, speck=0.06, edge_radius=2.6,
                   dents=0.8),
}
RL_ATLAS = {"olive": "body", "black": "body", "scope": "body", "rubber": "body",
            "glass": "body", "steel": "body", "wh_olive": "warhead", "wh_band": "warhead",
            "wood": "wood"}


def rocket_launcher():
    A = 80.0  # the tube's axis height; the tube runs from y -560 (venturi) to +392 (muzzle)
    ax = (0, 0, A)

    # --- tube: front barrel (bored), the fat chamber, the flared venturi behind
    part(lathe("front_tube", [(20.5, 170), (24, 170), (24, 368), (26.5, 371), (27.2, 375),
                              (27.2, 389), (25.8, 392.5), (20.5, 392.5)], center=ax, segs=24,
               closed=True), "olive", bevel=0.6, segs=1)
    part(lathe("chamber", [(0, -306), (30.5, -306), (32, -300), (32, 176), (29, 182),
                           (24, 186), (0, 186)], center=ax, segs=24), "olive", bevel=0.8, segs=1)
    part(lathe("venturi", [(32.5, -300), (34.5, -345), (38.5, -420), (44, -505), (47.5, -541),
                           (48.5, -548), (48.5, -560), (45, -560), (44, -547), (39.5, -470),
                           (31, -392), (19, -330), (14, -312), (14, -303)], center=ax, segs=24,
               closed=True), "olive", bevel=0.7, segs=1)
    for y, r in ((-318, 33.4), (-554, 48.2)):  # reinforcing rings at the throat and the rim
        part(lathe("venturi_band", [(r, y - 5), (r + 2.2, y - 3.5), (r + 2.2, y + 3.5),
                                    (r, y + 5)], center=ax, segs=24, closed=True), "steel",
             bevel=0)

    # --- wooden heat shields in steel bands
    for y0, y1 in ((-268, -38), (48, 172)):
        part(lathe("heat_shield", [(32.3, y0), (37.5, y0), (40.5, y0 + 5), (40.8, (y0 + y1) / 2),
                                   (40.5, y1 - 5), (37.5, y1), (32.3, y1)], center=ax, segs=24,
                   closed=True), "wood", bevel=0)
        for yb in (y0 + 7, y1 - 7):
            part(lathe("shield_band", [(40.2, yb - 5), (42.2, yb - 4), (42.2, yb + 4),
                                       (40.2, yb + 5)], center=ax, segs=24, closed=True),
                 "steel", bevel=0)
            part(box("band_clamp", (8, 9, 6), (0, yb, A - 44.5)), "steel", bevel=0.8, segs=1)
            part(dome("band_screw", (0, yb, A - 47.5), (0, 0, -1), 2.4, 1.2), "steel", bevel=0)

    # --- trigger group and grips (black phenolic)
    part(prism("trigger_housing", fillet([(-32, 50), (46, 50), (46, 35), (36, 24), (-18, 24),
                                          (-32, 36)], [2, 2, 4, 5, 5, 4]), -11.5, 11.5),
         "black", bevel=1.0)
    for sx in (1, -1):
        for y, z in ((-20, 38), (32, 38)):
            part(lathe("housing_pin", [(0, 0), (2.8, 0), (2.8, 0.8), (2.2, 1.2), (0, 1.2)],
                       center=(sx * 11.3, y, z), axis=(sx, 0, 0), segs=8), "steel", bevel=0)
    part(grip_loft("grip", (0.0, 2.0, 30.0), 14.0, 102.0, 28.0, 42.0, flutes=0.0, grooves=2.2,
                   N=20, stations=9),
         "black", bevel=0.8)
    tg = catmull([(0, 40, 25.5), (0, 41.5, 15), (0, 37, 5), (0, 27, 1), (0, 16, 1.5),
                  (0, 11, 6)], steps=3)
    part(sweep("trigger_guard", tg, rect2(10.0, 3.0, 1.0, n=1), up=(0, 0, 1)), "steel", bevel=0)
    trig = catmull([(0, 25, 26), (0, 25.5, 20), (0, 23.5, 13), (0, 20, 9), (0, 17, 7.5)], steps=2)
    part(sweep("trigger", trig, rect2(6.0, 4.4, 1.4, n=1), up=(0, 1, 0)), "steel", bevel=0)
    part(lathe("fore_band", [(23.8, 226), (27.8, 227), (27.8, 243), (23.8, 244)], center=ax,
               segs=24, closed=True), "steel", bevel=0)
    part(box("fore_block", (16, 20, 10), (0, 235, A - 30)), "black", bevel=1.2)
    part(grip_loft("fore_grip", (0.0, 237.0, A - 33.0), -6.0, 92.0, 27.0, 34.0, flutes=0.0,
                   grooves=2.0, bottom_flare=2.0, N=20, stations=9), "black", bevel=0.8)

    # --- iron sights: folding front post with ears, rear leaf with a notch
    part(prism("front_sight_base", fillet([(334, A + 22), (334, A + 28), (356, A + 28),
                                           (356, A + 22)], 2), -7, 7), "olive", bevel=0.6)
    for sx in (1, -1):
        part(prism("front_sight_ear", fillet([(339, A + 27), (339, A + 43), (345, A + 44),
                                              (351, A + 43), (351, A + 27)], [0, 2, 2, 2, 0]),
                   sx * 5.0, sx * 7.0), "olive", bevel=0.4)
    part(lathe("front_post", [(1.3, 0), (1.3, 13), (0.9, 14), (0, 14)],
               center=(0, 345, A + 27), axis=(0, 0, 1), segs=8), "steel", bevel=0)
    part(prism("rear_sight_base", fillet([(-4, A + 30), (-4, A + 36), (30, A + 36), (30, A + 30)], 2),
               -8, 8), "olive", bevel=0.6)
    leaf = prism("rear_leaf", fillet([(2, A + 35), (2, A + 52), (7, A + 52), (9, A + 35)],
                                     [0, 1, 1, 0]), -7, 7)
    part(leaf, "olive", bevel=0.4, cuts=[cutter(box("leaf_notch", (3, 20, 6), (0, 5, A + 51)))])

    # --- the optic on its left-side bracket
    part(prism("optic_rail", fillet([(-30, A - 6), (-30, A + 22), (40, A + 22), (40, A - 6)], 3),
               -42, -29), "scope", bevel=0.8)
    for y in (-18, 28):
        part(dome("rail_screw", (-42, y, A + 8), (-1, 0, 0), 3.2, 1.3), "steel", bevel=0)
    part(prism("optic_arm", fillet([(-22, A + 10), (-22, A + 40), (30, A + 40), (30, A + 10)], 4),
               -55, -41), "scope", bevel=1.0)
    sc = (-60.0, 0.0, A + 52.0)
    part(lathe("optic_body", [(0, -118), (15.5, -118), (17.5, -112), (17.5, -96), (15, -88),
                              (15, 48), (17, 56), (20.5, 78), (20.5, 111), (18, 113),
                              (17.2, 110), (17.2, 99), (0, 99)], center=sc, segs=20),
         "scope", bevel=0.5)
    part(lathe("objective", [(0, 100.2), (17.1, 100.2), (17.1, 99.4), (0, 99.4)], center=sc,
               segs=24), "glass", bevel=0)
    part(lathe("eyecup", [(11.5, -163), (21.5, -163), (22.5, -159), (19.5, -142), (16.5, -126),
                          (15, -117), (11.5, -117)], center=sc, segs=20, closed=True),
         "rubber", bevel=0.6)
    part(lathe("eyepiece", [(0, -126), (11.4, -126), (11.4, -127), (0, -127)], center=sc,
               segs=20), "glass", bevel=0)
    part(lathe("turret_top", [(0, 0), (10.5, 0), (10.5, 12), (9.5, 13.2), (0, 13.2)],
               center=(sc[0], -12, sc[2] + 14.5), axis=(0, 0, 1), segs=14), "scope", bevel=0.4, segs=1)
    part(lathe("turret_side", [(0, 0), (9, 0), (9, 11), (8, 12), (0, 12)],
               center=(sc[0] - 16, -12, sc[2]), axis=(-1, 0, 0), segs=12), "scope", bevel=0.4, segs=1)
    part(box("battery_box", (14, 30, 12), (sc[0] + 4, -60, sc[2] - 17)), "scope", bevel=1.2)

    # --- sling loops
    for y, r in ((-380, 31.5), (300, 24.0)):  # sling loops hanging under the tube
        zc = A - r - 10
        part(box("sling_stud", (6, 10, 8), (0, y, A - r - 2)), "steel", bevel=0.6)
        loop = [(0, y + 7 * math.sin(a), zc + 7 * math.cos(a)) for a in
                [2 * math.pi * k / 12 for k in range(12)]]
        part(sweep("sling_loop", loop, circle(1.6, 6), closed=True, up=(1, 0, 0)), "steel", bevel=0)

    # --- the loaded warhead (its own node: hidden while the launcher reloads)
    part(lathe("warhead", [(0, 330), (19.5, 330), (19.5, 466), (22.5, 470), (22.5, 476),
                           (29, 486), (38, 502), (44.5, 521), (46.5, 540), (46.5, 566),
                           (44.5, 590), (37, 636), (27, 684), (17, 728), (10.5, 750),
                           (8, 754), (0, 754)], center=ax, segs=24), "wh_olive", node="Warhead",
         bevel=0.5)
    part(lathe("warhead_band", [(46.5, 546), (46.9, 547), (46.9, 559), (46.5, 560)],
               center=ax, segs=24, closed=True), "wh_band", node="Warhead", bevel=0)
    part(lathe("fuze", [(0, 748), (8.5, 748), (8.5, 766), (6.5, 770), (4.2, 790), (2.4, 800),
                        (0, 802)], center=ax, segs=16), "steel", node="Warhead", bevel=0.3)

    return dict(finishes=RL_FIN, atlas=RL_ATLAS, empties={"Muzzle": (0, 800, A)})


# ----------------------------------------------------------------------------------------------
# Shotgun: an original 12-gauge pump gun in the classic walnut-and-blued-steel pattern
# ----------------------------------------------------------------------------------------------

SG_FIN = {
    # Deep blued steel, polished: rubbed through to bright steel on the edges and worn to the
    # plum-brown old bluing turns where hands and holsters go.
    "blued": finish(base=(0.060, 0.066, 0.086), base2=(0.048, 0.052, 0.068), tone_amt=0.6,
                    rough=0.30, rough2=0.44, metal=0.8, wear=1.0, wear_col=(0.48, 0.48, 0.49),
                    wear_rough=0.2, wear_metal=1.0, wear_lo=0.26, wear_hi=0.46, grime=0.6,
                    grime_col=(0.02, 0.017, 0.013), grime_rough=0.6, pit=0.2, pit_scale=900.0,
                    scratch=0.35, scratch_col=(0.3, 0.3, 0.31), handled=0.6,
                    handled_col=(0.085, 0.062, 0.050), handled_rough=0.06),
    # Black anodised trigger plate and guard, worn to silver aluminium.
    "alloy": finish(base=(0.02, 0.02, 0.022), base2=(0.03, 0.03, 0.032), rough=0.4,
                    rough2=0.5, metal=0.6, wear=1.0, wear_col=(0.6, 0.6, 0.62), wear_rough=0.3,
                    wear_metal=1.0, wear_lo=0.28, wear_hi=0.48, grime=0.5, pit=0.2,
                    pit_scale=900.0, scratch=0.3, scratch_col=(0.35, 0.35, 0.36)),
    "bright": AK_FIN["bright"],
    # Oiled walnut: the same CC0 grain as the rifle, browner and glossier.
    "walnut": finish(wood=True, wood_tile=0.45, wood_tint=(0.52, 1.05, 1.3), wood_gain=0.9,
                     wood_bump=7.0, wood_contrast=0.8, rough=0.38, wear=0.8,
                     wear_col=(0.24, 0.13, 0.065), wear_rough=0.62, wear_metal=0.0,
                     wear_lo=0.32, wear_hi=0.58, grime=0.7, grime_col=(0.016, 0.009, 0.005),
                     grime_rough=0.7, pit=0.05, handled=0.8, handled_rough=-0.12, speck=0.05,
                     edge_radius=2.6, dents=0.5),
    "rubber": RL_FIN["rubber"],
    "spacer": finish(base=(0.55, 0.55, 0.52), rough=0.4, metal=0.0, wear=0.3,
                     wear_col=(0.4, 0.38, 0.34), wear_rough=0.5, wear_metal=0.0, grime=0.8,
                     grime_col=(0.1, 0.08, 0.05), pit=0.1),
    "brass": finish(base=(0.62, 0.43, 0.17), base2=(0.5, 0.33, 0.12), tone_amt=0.7, rough=0.3,
                    rough2=0.42, metal=1.0, wear=0.5, wear_col=(0.8, 0.62, 0.35),
                    wear_rough=0.2, wear_lo=0.35, wear_hi=0.6, grime=0.7,
                    grime_col=(0.05, 0.035, 0.015), pit=0.15),
    # The shell's red plastic hull.
    "hull": finish(base=(0.30, 0.025, 0.018), base2=(0.36, 0.035, 0.022), rough=0.42,
                   rough2=0.52, metal=0.0, wear=0.4, wear_col=(0.4, 0.1, 0.08), wear_rough=0.5,
                   wear_metal=0.0, grime=0.4, pit=0.2, scratch=0.2,
                   scratch_col=(0.45, 0.12, 0.1)),
}
SG_ATLAS = {"blued": "metal", "alloy": "metal", "bright": "metal", "rubber": "metal",
            "spacer": "metal", "brass": "metal", "hull": "metal", "walnut": "wood"}
PUMP_REST = 205.0     # the forend's rear end with the action closed
PUMP_TRAVEL = 80.0    # how far it slides back to open it (the PumpBack empty marks the end)


def curve(keys, y):
    """Catmull-Rom through (y, value) keys - a smooth section table without kinks."""
    keys = sorted(keys)
    if y <= keys[0][0]:
        return keys[0][1]
    if y >= keys[-1][0]:
        return keys[-1][1]
    for i in range(len(keys) - 1):
        if keys[i][0] <= y <= keys[i + 1][0]:
            y0, v0 = keys[max(i - 1, 0)]
            y1, v1 = keys[i]
            y2, v2 = keys[i + 1]
            y3, v3 = keys[min(i + 2, len(keys) - 1)]
            t = (y - y1) / (y2 - y1)
            m1 = (v2 - v0) / (y2 - y0) * (y2 - y1)
            m2 = (v3 - v1) / (y3 - y1) * (y2 - y1)
            t2, t3 = t * t, t * t * t
            return ((2 * t3 - 3 * t2 + 1) * v1 + (t3 - 2 * t2 + t) * m1
                    + (-2 * t3 + 3 * t2) * v2 + (t3 - t2) * m2)


def shotgun():
    X = 15.0
    MZ = -23.0  # the magazine tube's axis height, under the barrel

    # --- receiver: ejection port on the right, loading port underneath, the bolt in the port
    rec = prism("receiver", fillet([(-80, -34), (-80, 7), (-68, 17), (126, 17), (126, -34)],
                                   [2, 3, 1.5, 1.5, 1.5]), -X, X)
    port = cutter(box("eject_port", (12, 78, 20), (X + 3.5, 60, 1.5)))
    load = cutter(box("load_port", (20, 76, 12), (0, 72, -38)))
    part(rec, "blued", bevel=0.8, cuts=[port, load])
    part(box("bolt", (5.5, 78, 16), (8.8, 60, 1.5)), "bright", bevel=0.6)
    part(box("extractor", (1.2, 10, 4), (11.8, 92, 4)), "bright", bevel=0.2, segs=1)
    part(box("lifter", (16, 70, 3), (0, 72, -31)), "blued", bevel=0.5, segs=1)
    for sx in (1, -1):
        for y in (-40, 52):
            part(lathe("plate_pin", [(0, 0), (2.8, 0), (2.8, 0.7), (2.2, 1.1), (0, 1.1)],
                       center=(sx * (X - 0.3), y, -27), axis=(sx, 0, 0), segs=8), "blued", bevel=0)

    # --- barrel with a real 12-gauge bore, a ventilated rib and a brass bead
    part(lathe("barrel", [(9.3, 118), (12.0, 118), (12.0, 152), (11.2, 160), (10.8, 400),
                          (10.3, 628), (10.0, 633), (9.3, 633)], segs=20, closed=True),
         "blued", bevel=0.4, segs=1)
    part(prism_y("rib", [(-4.2, 14.2), (4.2, 14.2), (4.2, 16.6), (-4.2, 16.6)], 150, 628),
         "blued", bevel=0.4, segs=1)
    for i in range(16):
        y = 165 + i * 29.5
        part(box("rib_post", (3.2, 5, 4.5), (0, y, 12.6)), "blued", bevel=0, segs=1)
    part(ellipsoid("bead", (0, 624, 18.2), (1.9, 1.9, 1.9), segs=8, rings=5), "brass", bevel=0,
         wn=False)

    # --- magazine tube, its knurled cap with a sling swivel, the barrel hanger
    part(lathe("mag_tube", [(0, 118), (11, 118), (11, 562), (0, 562)], center=(0, 0, MZ),
               segs=18), "blued", bevel=0.4, segs=1)
    cap = [(0, 560), (12.4, 560)]
    for k in range(6):
        y = 563 + k * 4
        cap += [(12.4, y), (12.9, y + 1), (12.9, y + 2.5), (12.4, y + 3.5)]
    cap += [(12.4, 588), (11.4, 591), (7, 593), (0, 593)]
    part(lathe("mag_cap", cap, center=(0, 0, MZ), segs=18), "blued", bevel=0)
    part(box("cap_stud", (5, 8, 6), (0, 586, MZ - 14)), "blued", bevel=0.6, segs=1)
    loop = [(0, 586 + 5 * math.sin(a), MZ - 22 + 6 * math.cos(a)) for a in
            [2 * math.pi * k / 12 for k in range(12)]]
    part(sweep("cap_swivel", loop, circle(1.5, 6), closed=True, up=(1, 0, 0)), "blued", bevel=0)
    part(prism_y("barrel_hanger", rrect(26, MZ - 13.5, 13.5, 12.8, 12.8, n=4), 546, 556),
         "blued", bevel=0.6, segs=1)

    # --- the pump: ribbed walnut forend round the magazine tube, its steel nut and action bars
    def fore_ring(y, k=1.0):
        t = (y - PUMP_REST) / 225.0
        w = 43.0 + 2.5 * math.sin(math.pi * min(1.0, max(0.0, t)))
        r = rrect(w * k, MZ - 19.5 * k, MZ + 25.5 * k, 7.0, 17.0 * k, n=4)
        return [(x, y, z) for x, z in r]
    grooves = [PUMP_REST + 55 + i * 13.0 for i in range(10)]
    ys = [PUMP_REST, PUMP_REST + 2.5]
    for gy in grooves:
        ys += [gy - 1.8, gy, gy + 1.8]
    ys += [PUMP_REST + 222.5, PUMP_REST + 225]
    rings = []
    for y in ys:
        k = 0.95 if y in (PUMP_REST, PUMP_REST + 225) else 1.0
        if any(abs(y - gy) < 0.5 for gy in grooves):
            k = 0.955
        rings.append(fore_ring(y, k))
    part(loft("forend", rings), "walnut", node="Pump", bevel=0.6, segs=1)
    part(lathe("forend_nut", [(11.2, PUMP_REST - 9), (13.6, PUMP_REST - 8), (13.6, PUMP_REST + 1),
                              (11.2, PUMP_REST + 1)], center=(0, 0, MZ), segs=18, closed=True),
         "blued", node="Pump", bevel=0)
    for sx in (1, -1):
        part(box("action_bar", (2.0, PUMP_REST - 118, 6), (sx * 12.8, (PUMP_REST + 118) / 2, MZ + 6)),
             "blued", node="Pump", bevel=0.3, segs=1)

    # --- trigger plate, guard, trigger, cross-bolt safety, slide release
    part(prism("trigger_plate", fillet([(-62, -38), (-62, -33), (12, -33), (12, -38)], 2), -12, 12),
         "alloy", bevel=0.6, segs=1)
    tg = catmull([(0, 8, -37), (0, 9, -45), (0, 3, -54.5), (0, -10, -58.5), (0, -34, -57.5),
                  (0, -46, -50), (0, -50, -41), (0, -52, -37)], steps=3)
    part(sweep("trigger_guard", tg, rect2(9, 3.4, 1.2, n=1), up=(0, 0, 1)), "alloy", bevel=0)
    trig = catmull([(0, -8, -37), (0, -7, -43), (0, -9.5, -49.5), (0, -14.5, -53.5)], steps=2)
    part(sweep("trigger", trig, rect2(5.5, 4.0, 1.4, n=1), up=(0, 1, 0)), "blued", bevel=0)
    part(lathe("safety", [(0, -14.5), (3.4, -14.5), (3.6, -13.5), (3.6, 13.5), (3.4, 14.5),
                          (0, 14.5)], center=(0, -38, -41.5), axis=(1, 0, 0), segs=10),
         "blued", bevel=0)
    part(box("slide_release", (2.2, 15, 5), (-12.8, 4, -40)), "alloy", bevel=0.5, segs=1)

    # --- stock: semi-pistol grip, comb, white-line spacer and a rubber recoil pad
    zt_keys = [(-80, 13.0), (-100, 7.5), (-140, 0.5), (-200, -12.0), (-345, -43.0)]
    zb_keys = [(-80, -33.0), (-94, -42.0), (-112, -62.0), (-130, -79.0), (-146, -86.0),
               (-162, -88.0), (-200, -103.0), (-280, -140.0), (-345, -172.0)]
    w_keys = [(-80, 28.0), (-100, 30.0), (-140, 33.0), (-200, 37.0), (-345, 41.0)]

    def stock_ring(y, grow=0.0):
        zt = curve(zt_keys, y) + grow
        zb = curve(zb_keys, y) - grow
        w = curve(w_keys, y) + 2 * grow
        rb = 0.36 * w if y > -170 else 9.0 + grow
        return [(x, y, z) for x, z in rrect(w, zb, zt, 0.45 * w, rb, n=4)]
    sy = [-77, -86, -95, -105, -115, -125, -135, -145, -155, -168, -185, -205, -230, -260, -290,
          -318, -338, -345]
    part(loft("stock", [stock_ring(y) for y in sy]), "walnut", bevel=1.0, segs=2)
    part(loft("spacer", [stock_ring(-344.5, 0.3), stock_ring(-347.5, 0.3)]), "spacer", bevel=0.3,
         segs=1)
    pad = [stock_ring(-347.5, 0.8), stock_ring(-352, 1.0), stock_ring(-361, 1.0),
           stock_ring(-365, 0.2)]
    part(loft("recoil_pad", pad), "rubber", bevel=0.8, segs=2)
    part(lathe("stock_stud", [(0, 0), (4, 0), (4, 5), (3, 6), (0, 6)], center=(0, -300, -148),
               axis=(0, 0, -1), segs=10), "blued", bevel=0)

    # --- a spare shell (its own node: the script hides it and throws copies out of the port)
    part(lathe("shell_hull", [(0, -34), (10.2, -34), (10.3, 22), (9.6, 24.5), (5, 26),
                              (0, 25.5)], center=(8, 60, 2), segs=16), "hull", node="Shell",
         bevel=0.3, segs=1)
    part(lathe("shell_head", [(9.8, -46), (11.2, -46), (11.2, -44), (10.6, -43.2), (10.6, -34),
                              (9.8, -33), (0, -33), (0, -46)], center=(8, 60, 2), segs=16),
         "brass", node="Shell", bevel=0)

    return dict(finishes=SG_FIN, atlas=SG_ATLAS,
                pivots={"Pump": ((0, PUMP_REST, MZ), 0.0), "Shell": ((8, 60, 2), 0.0)},
                empties={"Muzzle": (0, 633, 0), "PumpBack": (0, PUMP_REST - PUMP_TRAVEL, MZ),
                         "EjectPort": (X + 4, 60, 3)})


GUNS = {"ak47": ak47, "rocket_launcher": rocket_launcher, "shotgun": shotgun}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    nobake = "--nobake" in argv
    names = [a for a in argv if not a.startswith("--")] or list(GUNS.keys())
    for n in names:
        print("== %s" % n)
        build(n, GUNS[n], nobake)


if __name__ == "__main__":
    main()
