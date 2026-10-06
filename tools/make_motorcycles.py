#!/usr/bin/env python3
"""Motorcycles - a sport bike, a cruiser and a scooter - built in Blender from code, at real size.

    tools/road_cars_setup.sh                     # once: Blender 4.2 LTS into build/car_src/
    blender -b --factory-startup -P tools/make_motorcycles.py -- sport cruiser scooter [--render]
    # or, where download.blender.org is out of reach, the PyPI build of the same Blender:
    python3 -m venv build/bpy && build/bpy/bin/pip install bpy==4.2.0
    build/bpy/bin/python tools/make_motorcycles.py -- sport cruiser scooter [--render]

Writes assets/models/moto_<name>.glb. Then `godot --headless --path . --import` (CLAUDE.md,
measurement trap 1: Godot serves a cached import otherwise). `--render` also writes Cycles
previews to $RENDER_DIR (default build/car_src/renders). Motorcycle (scripts/vehicles/
motorcycle.gd) loads the files; the run prints the row of numbers its DIMS table needs.

ORIGINAL DESIGNS of three generic classes: a 600-class supersport (full fairing, twin-spar
beam frame, inline four, upside-down fork, a short stubby silencer), a big air-cooled V-twin
cruiser (teardrop tank, raked chrome fork, wire wheels, finned barrels, staggered pipes, a
valanced fender) and a 150-class step-through scooter (leg shield, floorboard, the engine and
its belt case as the swingarm). No manufacturer's shape, badge or name.

GEOMETRY. X lateral, Y along the bike with the NOSE AT +Y, Z up, the ground at Z = 0, Y = 0
midway between the axles; the glTF exporter turns that into Godot's X right, Y up, nose at -Z.
Real dimensions throughout (wheelbases 1.40 / 1.65 / 1.33 m, tyre sizes from their size codes,
seat heights 0.83 / 0.69 / 0.78 m).

FIVE NODES per file, which are the contract with Motorcycle:
  moto_<n>_body     everything fixed to the frame (origin at the bike's origin);
  moto_<n>_steer    the fork, the bars and what turns with them, origin ON THE STEERING AXIS at
                    the top of the headstock (Motorcycle turns it about the rake axis it prints);
  moto_<n>_wheel_f  the front wheel (tyre, rim, discs), origin at the front axle;
  moto_<n>_wheel_r  the rear wheel (and the rear sprocket or pulley), origin at the rear axle;
  moto_<n>_far      the whole bike, wheels and all, collapsed to ~3.5k triangles in TWO surfaces
                    (`paint_far` and `parts`, the rest folded into vertex colours: Vehicle's parts
                    shader), drawn past Motorcycle's far distance.
Material slots by name: paint (the bike's colour: car_paint.gdshader), frame (gloss black or the
beam's satin silver), chrome, metal (satin cast aluminium), dark (black anodised and cast parts),
trim (black plastic), rubber, tyre, seat, glass (screen), light_front, light_rear, amber.
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
OUT_DIR = os.path.join(REPO, "assets", "models")
RENDER_DIR = os.environ.get("RENDER_DIR", os.path.join(REPO, "build", "car_src", "renders"))

#   name, linear albedo, metallic, roughness, emission
SLOTS = [
    ("paint",       (0.80, 0.80, 0.80),    0.30, 0.30, 0.0),
    ("frame",       (0.020, 0.020, 0.022), 0.20, 0.30, 0.0),
    ("chrome",      (0.88, 0.89, 0.91),    1.00, 0.10, 0.0),
    ("metal",       (0.56, 0.57, 0.58),    1.00, 0.38, 0.0),
    ("dark",        (0.045, 0.045, 0.048), 0.60, 0.42, 0.0),
    ("trim",        (0.028, 0.028, 0.030), 0.00, 0.55, 0.0),
    ("rubber",      (0.020, 0.020, 0.021), 0.00, 0.80, 0.0),
    ("tyre",        (0.024, 0.024, 0.026), 0.00, 0.90, 0.0),
    ("seat",        (0.030, 0.028, 0.027), 0.00, 0.62, 0.0),
    ("glass",       (0.040, 0.045, 0.052), 0.00, 0.04, 0.0),
    ("light_front", (0.88, 0.90, 0.94),    0.00, 0.08, 1.4),
    ("light_rear",  (0.50, 0.025, 0.030),  0.00, 0.12, 0.25),
    ("amber",       (0.80, 0.36, 0.03),    0.00, 0.12, 0.10),
]
(PAINT, FRAME, CHROME, METAL, DARK, TRIM, RUBBER, TYRE, SEAT, GLASS, LIGHT_F, LIGHT_R,
 AMBER) = range(len(SLOTS))
MATS = []


def log(msg):
    print(msg, flush=True)


# --- scene and object helpers ------------------------------------------------------------------

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()
    for name, col, metal, rough, emit in SLOTS:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        b = m.node_tree.nodes.get("Principled BSDF")
        b.inputs["Base Color"].default_value = (col[0], col[1], col[2], 1.0)
        b.inputs["Metallic"].default_value = metal
        b.inputs["Roughness"].default_value = rough
        if emit > 0.0:
            b.inputs["Emission Color"].default_value = (col[0], col[1], col[2], 1.0)
            b.inputs["Emission Strength"].default_value = emit
        if name == "glass":
            b.inputs["Alpha"].default_value = 1.0
        MATS.append(m)


def to_object(name, bm, smooth=True, sharp_deg=40.0):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    for m in MATS:
        ob.data.materials.append(m)
    bpy.context.scene.collection.objects.link(ob)
    if smooth:
        shade(ob, sharp_deg)
    return ob


def apply_mods(ob):
    bpy.context.view_layer.objects.active = ob
    for mod in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)


def subsurf(ob, levels=2):
    mod = ob.modifiers.new("ss", 'SUBSURF')
    mod.levels = levels
    mod.render_levels = levels
    apply_mods(ob)


def shade(ob, sharp_deg=40.0):
    me = ob.data
    for p in me.polygons:
        p.use_smooth = True
    lim = math.cos(math.radians(sharp_deg))
    faces = {}
    for p in me.polygons:
        for ek in p.edge_keys:
            faces.setdefault(ek, []).append(p.index)
    for e in me.edges:
        fl = faces.get(e.key, [])
        if len(fl) != 2:
            e.use_edge_sharp = True
            continue
        a, b = me.polygons[fl[0]], me.polygons[fl[1]]
        if a.material_index != b.material_index or a.normal.dot(b.normal) < lim:
            e.use_edge_sharp = True


def join(objs, name=None):
    objs = [o for o in objs if o is not None]
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = objs[0]
    if name:
        ob.name = name
        ob.data.name = name
    return ob


def set_origin(ob, at):
    """Moves the object's origin to `at` (world), leaving the mesh where it is."""
    at = Vector(at)
    ob.data.transform(Matrix.Translation(-at))
    ob.location = at


def tris(ob):
    ob.data.calc_loop_triangles()
    return len(ob.data.loop_triangles)


def mirror_x(bm):
    """Mirrors everything in bm across x = 0 (a copy), for the parts built on one side."""
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    ret = bmesh.ops.duplicate(bm, geom=geom)
    verts = [g for g in ret["geom"] if isinstance(g, bmesh.types.BMVert)]
    faces = [g for g in ret["geom"] if isinstance(g, bmesh.types.BMFace)]
    for v in verts:
        v.co.x = -v.co.x
    bmesh.ops.reverse_faces(bm, faces=faces)


# --- primitive builders (all write into a bmesh) ------------------------------------------------

def face(bm, verts, mat):
    try:
        f = bm.faces.new(verts)
    except ValueError:
        return None
    f.material_index = mat
    return f


def rings_to_faces(bm, rings, mat, closed=True, mats=None):
    out = []
    n = len(rings[0])
    seg = n if closed else n - 1
    for i in range(len(rings) - 1):
        for k in range(seg):
            k2 = (k + 1) % n
            m = mats(i, k) if mats else mat
            f = face(bm, (rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]), m)
            if f:
                out.append(f)
    return out


def cap(bm, ring, mat, centre=None):
    if centre is None:
        return face(bm, ring, mat)
    c = bm.verts.new(centre)
    for k in range(len(ring)):
        face(bm, (ring[k], ring[(k + 1) % len(ring)], c), mat)
    return c


def lathe(bm, profile, segs, origin, axis='X', mat=0, mats=None, closed_ends=False, a0=0.0, a1=None):
    """Revolves profile [(radius, along)] about an axis through `origin`. Returns the rings."""
    o = Vector(origin)
    full = a1 is None
    a1 = math.tau if full else a1
    n = segs if full else segs + 1
    rings = []
    for r, t in profile:
        ring = []
        for k in range(n):
            a = a0 + (a1 - a0) * k / segs
            c, s = math.cos(a), math.sin(a)
            if axis == 'X':
                p = o + Vector((t, r * c, r * s))
            elif axis == 'Y':
                p = o + Vector((r * c, t, r * s))
            else:
                p = o + Vector((r * c, r * s, t))
            ring.append(bm.verts.new(p))
        rings.append(ring)
    faces = []
    for i in range(len(rings) - 1):
        for k in range(segs):
            k2 = (k + 1) % n if full else k + 1
            m = mats(i, k) if mats else mat
            f = face(bm, (rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]), m)
            if f:
                faces.append(f)
    if faces:
        bmesh.ops.recalc_face_normals(bm, faces=faces)
    return rings


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
    ref = Vector((0, 0, 1)) if abs(tans[0].z) < 0.9 else Vector((1, 0, 0))
    up = (ref - tans[0] * ref.dot(tans[0])).normalized()
    out = []
    for i in range(n):
        up = (up - tans[i] * up.dot(tans[i]))
        up = up.normalized() if up.length > 1e-6 else Vector((0, 0, 1))
        out.append((tans[i], up, tans[i].cross(up).normalized()))
    return out


def sweep(bm, path, profile, mat, caps=True, up=None):
    """A closed 2D profile [(a, b)] swept along `path` (Vectors). `profile` may be a function of
    the path index. `up` fixes the profile's b axis to a direction (else parallel transport)."""
    path = [Vector(p) for p in path]
    fr = frames(path)
    rings = []
    for i, p in enumerate(path):
        t, u, s = fr[i]
        if up is not None:
            u = Vector(up) - t * Vector(up).dot(t)
            u = u.normalized() if u.length > 1e-6 else fr[i][1]
            s = t.cross(u).normalized()
        pr = profile(i) if callable(profile) else profile
        rings.append([bm.verts.new(p + s * a + u * b) for a, b in pr])
    fs = rings_to_faces(bm, rings, mat)
    if caps:
        for ring in (rings[0], rings[-1]):
            f = face(bm, ring, mat)
            if f:
                fs.append(f)
    if fs:
        bmesh.ops.recalc_face_normals(bm, faces=fs)
    return rings


def circle(r, n, sx=1.0, sy=1.0):
    return [(r * sx * math.cos(math.tau * k / n), r * sy * math.sin(math.tau * k / n)) for k in range(n)]


def rrect(w, h, r, n=3):
    """A rounded rectangle profile, w x h, corner radius r, n segments a corner."""
    r = min(r, w * 0.5 - 1e-4, h * 0.5 - 1e-4)
    cx, cy = w * 0.5 - r, h * 0.5 - r
    pts = []
    for q, (sx, sy) in enumerate(((1, 1), (-1, 1), (-1, -1), (1, -1))):
        base = q * math.pi * 0.5
        for k in range(n + 1):
            a = base + (math.pi * 0.5) * k / n
            pts.append((sx * cx + r * math.cos(a), sy * cy + r * math.sin(a)))
    return pts


def tube(bm, path, r, mat, n=12, caps=True):
    return sweep(bm, path, circle(r, n), mat, caps)


def bez(p0, p1, p2, p3, n):
    p0, p1, p2, p3 = (Vector(p) for p in (p0, p1, p2, p3))
    out = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        out.append(p0 * u * u * u + p1 * 3 * u * u * t + p2 * 3 * u * t * t + p3 * t * t * t)
    return out


def polyline(pts, step):
    """Resamples a polyline at about `step`."""
    pts = [Vector(p) for p in pts]
    out = [pts[0]]
    for a, b in zip(pts, pts[1:]):
        d = (b - a).length
        k = max(1, int(round(d / step)))
        for i in range(1, k + 1):
            out.append(a.lerp(b, i / k))
    return out


def rbox(bm, size, loc, mat, bevel=0.01, segs=2, rot=None):
    """A box with bevelled edges (real catch-lights on every edge)."""
    sx, sy, sz = (s * 0.5 for s in size)
    co = [(-sx, -sy, -sz), (sx, -sy, -sz), (sx, sy, -sz), (-sx, sy, -sz),
          (-sx, -sy, sz), (sx, -sy, sz), (sx, sy, sz), (-sx, sy, sz)]
    m = rot if rot is not None else Matrix.Identity(3)
    v = [bm.verts.new(Vector(loc) + m @ Vector(c)) for c in co]
    fs = []
    for a, b, c, d in [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]:
        f = face(bm, (v[a], v[b], v[c], v[d]), mat)
        if f:
            fs.append(f)
    bmesh.ops.recalc_face_normals(bm, faces=fs)
    if bevel > 0.0:
        edges = list({e for f in fs for e in f.edges})
        res = bmesh.ops.bevel(bm, geom=edges, offset=bevel, segments=segs, profile=0.5, affect='EDGES',
                              clamp_overlap=True, material=mat)
        for f in res["faces"]:
            f.material_index = mat
    return v


def loft(bm, sections, mat, cap0=True, cap1=True, mats=None):
    """Quads between consecutive closed sections (lists of Vectors, same length)."""
    rings = [[bm.verts.new(Vector(p)) for p in s] for s in sections]
    fs = rings_to_faces(bm, rings, mat, mats=mats)
    if cap0:
        c = sum((Vector(p) for p in sections[0]), Vector()) / len(sections[0])
        cap(bm, rings[0], mat, c)
    if cap1:
        c = sum((Vector(p) for p in sections[-1]), Vector()) / len(sections[-1])
        cap(bm, rings[-1], mat, c)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return rings


def sect(y, cx, cz, w, h, n=16, e=2.6, flat_bottom=0.0, taper_top=0.0, taper_bottom=0.0):
    """A superellipse section in the XZ plane at Y: half width w/2, half height h/2, exponent e
    (2 an ellipse, higher squarer). `taper_top` narrows the top half (a tank's ridge)."""
    pts = []
    for k in range(n):
        a = math.tau * k / n
        c, s = math.cos(a), math.sin(a)
        x = math.copysign(abs(c) ** (2.0 / e), c) * w * 0.5
        z = math.copysign(abs(s) ** (2.0 / e), s) * h * 0.5
        if z > 0:
            x *= 1.0 - taper_top * (z / (h * 0.5))
        else:
            x *= 1.0 - taper_bottom * (-z / (h * 0.5))
            if flat_bottom > 0.0:
                z *= 1.0 - flat_bottom
        pts.append(Vector((cx + x, y, cz + z)))
    return pts


def rot_axis(axis, ang):
    return Matrix.Rotation(ang, 3, Vector(axis))


# --- shared parts ------------------------------------------------------------------------------

def tyre(bm, centre, r, w, profile_r, segs=72, tread=True):
    """A motorcycle tyre: a round crown (the section is nearly a half circle on a bike), the
    sidewall falling in to the bead. Tread grooves as shallow steps on the crown."""
    prof = []
    bead_r = r - w * 0.62
    # bead (inner) -> sidewall -> shoulder -> crown -> other side
    n_crown = 14
    half = w * 0.5
    side_pts = [(bead_r, -half * 0.70), (bead_r + (r - bead_r) * 0.25, -half * 0.98),
                (bead_r + (r - bead_r) * 0.55, -half * 1.00)]
    prof.extend(side_pts)
    # The crown: an arc of radius profile_r centred on the axis line at r - profile_r.
    cr = r - profile_r
    lim = math.asin(min(0.999, half * 0.98 / profile_r))
    for i in range(n_crown + 1):
        a = -lim + 2 * lim * i / n_crown
        prof.append((cr + profile_r * math.cos(a), profile_r * math.sin(a)))
    prof.extend([(p[0], -p[1]) for p in reversed(side_pts)])
    rings = lathe(bm, [(a, b) for a, b in prof], segs, centre, 'X', TYRE)
    # A closed tyre: the inner ring between the beads.
    face_inner = rings_to_faces(bm, [rings[-1], rings[0]], TYRE)
    bmesh.ops.recalc_face_normals(bm, faces=face_inner)
    if tread:
        # Tread grooves: thin dark slashes pressed into the crown (raised strips of rubber 1 mm
        # under the surface would be lost; these are short swept blades just proud of it).
        c = Vector(centre)
        for k in range(24):
            a0 = math.tau * k / 24
            for side in (-1, 1):
                pts = []
                for j in range(5):
                    t = j / 4.0
                    a = a0 + side * 0.10 * t
                    x = side * (0.10 + 0.55 * t) * half
                    rr = cr + math.sqrt(max(profile_r ** 2 - x * x, 0.0)) + 0.0012
                    pts.append(c + Vector((x, rr * math.cos(a), rr * math.sin(a))))
                sweep(bm, pts, [(-0.0035, 0.0), (0.0035, 0.0), (0.0035, 0.0012), (-0.0035, 0.0012)],
                      RUBBER, caps=True)


def cast_rim(bm, centre, r_rim, width, spokes=5, split=True, mat=PAINT, hub_r=0.055, segs=72):
    """A cast wheel: the rim hoop (flanges, well, a machined lip) and Y-split spokes to the hub."""
    c = Vector(centre)
    half = width * 0.5
    prof = [(r_rim + 0.012, -half), (r_rim + 0.016, -half + 0.006), (r_rim + 0.004, -half + 0.012),
            (r_rim - 0.010, -half + 0.022), (r_rim - 0.016, -half * 0.3), (r_rim - 0.030, 0.0),
            (r_rim - 0.016, half * 0.3), (r_rim - 0.010, half - 0.022), (r_rim + 0.004, half - 0.012),
            (r_rim + 0.016, half - 0.006), (r_rim + 0.012, half), (r_rim - 0.004, half),
            (r_rim - 0.012, half * 0.5), (r_rim - 0.036, 0.0), (r_rim - 0.012, -half * 0.5),
            (r_rim - 0.004, -half)]
    lathe(bm, prof + [prof[0]], segs, c, 'X', mat)
    # The machined lip: a bright band on each flange.
    for s in (-1, 1):
        lathe(bm, [(r_rim + 0.0165, s * (half - 0.004)), (r_rim + 0.0175, s * (half - 0.0015)),
                   (r_rim + 0.0125, s * (half + 0.0005))], segs, c, 'X', METAL)
    # Hub.
    hp = [(0.012, -0.06), (hub_r * 0.6, -0.062), (hub_r, -0.050), (hub_r * 1.05, -0.02),
          (hub_r * 0.85, 0.0), (hub_r * 1.05, 0.02), (hub_r, 0.050), (hub_r * 0.6, 0.062), (0.012, 0.06)]
    lathe(bm, hp, 24, c, 'X', mat)
    lathe(bm, [(0.004, -0.065), (0.016, -0.065), (0.016, 0.065), (0.004, 0.065)], 12, c, 'X', METAL)
    # Spokes: tapering blades from the hub to the rim's well, each one forking into two near the
    # rim when `split`.
    for k in range(spokes):
        a = math.tau * k / spokes
        branches = [-0.11, 0.11] if split else [0.0]
        for b in branches:
            pts = []
            for j in range(9):
                t = j / 8.0
                rr = hub_r * 0.9 + (r_rim - 0.03 - hub_r * 0.9) * t
                ang = a + b * smooth(t * 1.6 - 0.3) + 0.06 * t * t
                pts.append(c + Vector((0.0, rr * math.cos(ang), rr * math.sin(ang))))

            def prof_f(i, _b=b):
                t = i / 8.0
                th = (0.024 - 0.010 * t) * (0.62 if split else 1.0)
                wd = (0.022 - 0.010 * t) if split else (0.026 - 0.008 * t)
                return [(-wd * 0.5, -th * 0.5), (wd * 0.5, -th * 0.5), (wd * 0.42, th * 0.5), (-wd * 0.42, th * 0.5)]
            sweep(bm, pts, prof_f, mat, caps=True, up=Vector((1, 0, 0)))


def smooth(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3 - 2 * t)


def wire_rim(bm, centre, r_rim, width, hub_r=0.07, n_spokes=40, segs=72):
    """A laced chrome wheel: a polished rim, a hub with two spoke flanges, crossed spokes."""
    c = Vector(centre)
    half = width * 0.5
    prof = [(r_rim + 0.010, -half), (r_rim + 0.013, -half + 0.004), (r_rim + 0.002, -half + 0.010),
            (r_rim - 0.008, -half * 0.4), (r_rim - 0.014, 0.0), (r_rim - 0.008, half * 0.4),
            (r_rim + 0.002, half - 0.010), (r_rim + 0.013, half - 0.004), (r_rim + 0.010, half),
            (r_rim - 0.002, half), (r_rim - 0.016, 0.0), (r_rim - 0.002, -half)]
    lathe(bm, prof + [prof[0]], segs, c, 'X', CHROME)
    hp = [(0.014, -0.085), (0.035, -0.085), (hub_r, -0.072), (hub_r, -0.060), (0.045, -0.055),
          (0.040, 0.0), (0.045, 0.055), (hub_r, 0.060), (hub_r, 0.072), (0.035, 0.085), (0.014, 0.085)]
    lathe(bm, hp, 32, c, 'X', CHROME)
    for k in range(n_spokes):
        side = -1 if k % 2 == 0 else 1
        a = math.tau * k / n_spokes
        cross = 0.32 * (1 if (k // 2) % 2 == 0 else -1)
        p0 = c + Vector((side * 0.066, (hub_r - 0.006) * math.cos(a), (hub_r - 0.006) * math.sin(a)))
        a1 = a + cross
        p1 = c + Vector((side * 0.012, (r_rim - 0.010) * math.cos(a1), (r_rim - 0.010) * math.sin(a1)))
        tube(bm, [p0, p1], 0.0021, CHROME, n=5, caps=False)
        # The nipple at the rim.
        tube(bm, [p1, p1 + (p1 - p0).normalized() * 0.012], 0.0036, CHROME, n=6, caps=True)


def disc(bm, centre, x, r_out, r_in, mat_disc=METAL, carrier=True, petal=False, segs=64, holes=True):
    """A brake disc at lateral offset x: the braking ring (wave edge when `petal`), the carrier
    and its arms, and the floating buttons between them; drilled holes as dark pocks."""
    c = Vector(centre) + Vector((x, 0, 0))
    th = 0.0055
    outer = []
    for k in range(segs):
        a = math.tau * k / segs
        rr = r_out * (1.0 - (0.025 * (0.5 + 0.5 * math.cos(a * 12)) if petal else 0.0))
        outer.append((a, rr))
    ri = r_in
    rings = []
    for xo in (-th * 0.5, th * 0.5):
        ro = [bm.verts.new(c + Vector((xo, rr * math.cos(a), rr * math.sin(a)))) for a, rr in outer]
        rin = [bm.verts.new(c + Vector((xo, ri * math.cos(a), ri * math.sin(a)))) for a, _ in outer]
        rings.append((ro, rin))
    fs = []
    for k in range(segs):
        k2 = (k + 1) % segs
        for side in (0, 1):
            ro, rin = rings[side]
            f = face(bm, (ro[k], ro[k2], rin[k2], rin[k]), mat_disc)
            if f:
                fs.append(f)
        f = face(bm, (rings[0][0][k], rings[0][0][k2], rings[1][0][k2], rings[1][0][k]), mat_disc)
        if f:
            fs.append(f)
        f = face(bm, (rings[0][1][k], rings[0][1][k2], rings[1][1][k2], rings[1][1][k]), mat_disc)
        if f:
            fs.append(f)
    bmesh.ops.recalc_face_normals(bm, faces=fs)
    if holes:
        # Cross-drilling read as rows of dark dots: tiny dark discs a hair proud of each face.
        for k in range(36):
            for j, rr in enumerate((r_in + (r_out - r_in) * 0.35, r_in + (r_out - r_in) * 0.68)):
                a = math.tau * (k + 0.5 * j) / 36
                for s in (-1, 1):
                    p = c + Vector((s * (th * 0.5 + 0.0004), rr * math.cos(a), rr * math.sin(a)))
                    ring = [bm.verts.new(p + Vector((0, 0.0032 * math.cos(t), 0.0032 * math.sin(t))))
                            for t in (math.tau * q / 6 for q in range(6))]
                    f = face(bm, ring if s > 0 else list(reversed(ring)), DARK)
    if carrier:
        lathe(bm, [(r_in - 0.002, -0.004), (r_in - 0.002, 0.004), (0.062, 0.006), (0.062, -0.006)],
              32, c, 'X', DARK)
        for k in range(10):
            a = math.tau * (k + 0.5) / 10
            p = c + Vector((0, r_in * math.cos(a), r_in * math.sin(a)))
            lathe(bm, [(0.0001, -0.006), (0.0065, -0.006), (0.0065, 0.006), (0.0001, 0.006)], 8, p, 'X', METAL)


def caliper(bm, centre, x, r_disc, ang, size=(0.045, 0.12, 0.07), mat=METAL, logo=False):
    """A radial caliper straddling the disc at angle `ang` round the axle."""
    c = Vector(centre)
    rr = r_disc - 0.022
    p = c + Vector((x, rr * math.cos(ang), rr * math.sin(ang)))
    m = rot_axis((1, 0, 0), ang - math.pi * 0.5)
    rbox(bm, size, p, mat, bevel=0.012, segs=2, rot=m)
    # The two halves' bridge bolts.
    for s in (-1, 1):
        tip = p + m @ Vector((0, s * size[1] * 0.36, size[2] * 0.35))
        lathe(bm, [(0.0001, -size[0] * 0.55), (0.007, -size[0] * 0.55), (0.007, size[0] * 0.55), (0.0001, size[0] * 0.55)],
              8, tip, 'X', CHROME)


def lamp_lens(bm, centre, normal, rx, rz, depth, mat, rim_mat=TRIM, segs=24):
    """A domed lens set in a shallow bezel, facing `normal`."""
    n = Vector(normal).normalized()
    up = Vector((0, 0, 1)) if abs(n.z) < 0.9 else Vector((0, 1, 0))
    sx = up.cross(n).normalized()
    sz = n.cross(sx).normalized()
    c = Vector(centre)
    rings = []
    for i, (k, d) in enumerate(((1.12, -depth), (1.12, 0.0), (1.0, 0.0), (0.92, depth * 0.45), (0.6, depth * 0.85), (0.0, depth))):
        ring = []
        for j in range(segs):
            a = math.tau * j / segs
            ring.append(bm.verts.new(c + sx * (rx * k * math.cos(a)) + sz * (rz * k * math.sin(a)) + n * d))
        rings.append(ring)
    fs = rings_to_faces(bm, rings[:3], rim_mat)
    fs += rings_to_faces(bm, rings[2:], mat)
    bmesh.ops.recalc_face_normals(bm, faces=fs)


def mirror_on_stalk(bm, base, tip, head_w, head_h, mat_head=TRIM, mat_glass=CHROME, out=1.0):
    tube(bm, polyline([base, tip], 0.03), 0.0055, mat_head, n=8)
    t = Vector(tip)
    rbox(bm, (head_w, 0.03, head_h), t + Vector((0, -0.012, 0)), mat_head, bevel=0.012, segs=3)
    # The glass faces the rider (-Y).
    q = [bm.verts.new(t + Vector((sx * head_w * 0.40, -0.0285, sz * head_h * 0.36))) for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    f = face(bm, q, mat_glass)
    if f and f.normal.y > 0:
        f.normal_flip()


def lever(bm, pivot, side, length=0.17, mat=METAL):
    p = Vector(pivot)
    pts = [p, p + Vector((side * 0.03, 0.035, -0.004)), p + Vector((side * length * 0.6, 0.045, -0.012)),
           p + Vector((side * length, 0.035, -0.018))]
    sweep(bm, polyline(pts, 0.02), [(-0.006, -0.003), (0.006, -0.003), (0.006, 0.003), (-0.006, 0.003)], mat)


def grip(bm, a, b, r=0.017):
    a, b = Vector(a), Vector(b)
    pts = polyline([a, b], 0.008)
    n = len(pts)

    def prof(i):
        t = i / max(n - 1, 1)
        rr = r * (1.0 + 0.08 * math.sin(t * math.pi)) + (0.003 if (i % 2 == 0 and 0.1 < t < 0.85) else 0.0)
        return circle(rr, 14)
    sweep(bm, pts, prof, RUBBER)
    lathe(bm, [(0.0001, 0.0), (r * 1.12, 0.0), (r * 1.12, 0.012), (r * 0.5, 0.016), (0.0001, 0.016)], 14, b, 'X'
          if abs((b - a).normalized().x) > 0.7 else 'Y', CHROME)


def footpeg(bm, at, side, length=0.11, mat=METAL, rubber=False):
    p = Vector(at)
    tube(bm, [p, p + Vector((side * length, 0.0, 0.0))], 0.012, RUBBER if rubber else mat, n=10)
    if not rubber:
        # Knurled teeth.
        for k in range(5):
            q = p + Vector((side * (0.02 + k * 0.02), 0.0, 0.012))
            rbox(bm, (0.006, 0.026, 0.004), q, mat, bevel=0.0)


def chain(bm, a_centre, a_r, b_centre, b_r, x, mat=DARK, links=None):
    """A chain run between two sprockets: the top and bottom runs as link plates."""
    a, b = Vector(a_centre), Vector(b_centre)
    d = (b - a)
    L = d.length
    u = d.normalized()
    nrm = Vector((1, 0, 0)).cross(u).normalized()
    for side in (1, -1):
        ra = a + nrm * (a_r * side)
        rb = b + nrm * (b_r * side)
        seg = rb - ra
        n = int(seg.length / 0.0159)
        for k in range(n):
            p = ra + seg * ((k + 0.5) / n)
            rbox(bm, (0.018, 0.016, 0.009), Vector((x, p.y, p.z)), mat if k % 2 else METAL, bevel=0.002, segs=1,
                 rot=Matrix.Rotation(math.atan2(seg.z, seg.y), 3, Vector((1, 0, 0))))


def sprocket(bm, centre, x, r, teeth, mat=DARK):
    c = Vector(centre) + Vector((x, 0, 0))
    pts = []
    for k in range(teeth * 2):
        a = math.tau * k / (teeth * 2)
        rr = r + (0.006 if k % 2 == 0 else -0.004)
        pts.append((a, rr))
    th = 0.006
    top = [bm.verts.new(c + Vector((th, rr * math.cos(a), rr * math.sin(a)))) for a, rr in pts]
    bot = [bm.verts.new(c + Vector((-th, rr * math.cos(a), rr * math.sin(a)))) for a, rr in pts]
    inner_t = [bm.verts.new(c + Vector((th, r * 0.55 * math.cos(a), r * 0.55 * math.sin(a)))) for a, _ in pts]
    inner_b = [bm.verts.new(c + Vector((-th, r * 0.55 * math.cos(a), r * 0.55 * math.sin(a)))) for a, _ in pts]
    n = len(pts)
    fs = []
    for k in range(n):
        k2 = (k + 1) % n
        for f in (face(bm, (top[k], top[k2], inner_t[k2], inner_t[k]), mat),
                  face(bm, (bot[k2], bot[k], inner_b[k], inner_b[k2]), mat),
                  face(bm, (top[k2], top[k], bot[k], bot[k2]), mat),
                  face(bm, (inner_t[k], inner_t[k2], inner_b[k2], inner_b[k]), mat)):
            if f:
                fs.append(f)
    bmesh.ops.recalc_face_normals(bm, faces=fs)


def finned_barrel(bm, base, axis, r, height, fins, fin_out, mat=METAL, fin_mat=None, segs=28):
    """An air-cooled cylinder barrel: a core with `fins` thin fins standing `fin_out` proud."""
    base = Vector(base)
    ax = Vector(axis).normalized()
    up = Vector((1, 0, 0)) if abs(ax.x) < 0.9 else Vector((0, 1, 0))
    s1 = up.cross(ax).normalized()
    s2 = ax.cross(s1).normalized()
    prof = []
    pitch = height / fins
    prof.append((0.0001, 0.0))
    prof.append((r, 0.0))
    for k in range(fins):
        z0 = k * pitch
        prof += [(r, z0 + pitch * 0.18), (r + fin_out, z0 + pitch * 0.30), (r + fin_out, z0 + pitch * 0.55),
                 (r, z0 + pitch * 0.68)]
    prof.append((r, height))
    prof.append((0.0001, height))
    rings = []
    for rr, z in prof:
        ring = []
        for j in range(segs):
            a = math.tau * j / segs
            # Squarish fins (a real barrel's fins are near-square in plan).
            c, s = math.cos(a), math.sin(a)
            k = 1.0
            if rr > r + 0.001:
                k = 1.0 / max(abs(c), abs(s)) ** 0.35
            ring.append(bm.verts.new(base + ax * z + s1 * (rr * k * c) + s2 * (rr * k * s)))
        rings.append(ring)
    fs = rings_to_faces(bm, rings, fin_mat if fin_mat is not None else mat)
    bmesh.ops.recalc_face_normals(bm, faces=fs)


# --- the far twin ------------------------------------------------------------------------------

def build_far(objs, name, target):
    """The whole bike (wheels and all, posed straight) collapsed to `target` triangles in two
    surfaces: paint_far, and parts with every other slot's albedo and roughness in the vertex
    colour (Vehicle.PARTS_SHADER)."""
    copies = []
    for ob in objs:
        c = ob.copy()
        c.data = ob.data.copy()
        bpy.context.scene.collection.objects.link(c)
        c.data.transform(c.matrix_world)
        c.matrix_world = Matrix.Identity(4)
        copies.append(c)
    far = join(copies, name + "_far")
    me = far.data
    col = me.color_attributes.new("Col", 'FLOAT_COLOR', 'CORNER')
    for poly in me.polygons:
        nm, c, _m, rough, _e = SLOTS[poly.material_index]
        r = rough if nm not in ("chrome", "metal") else 0.25
        cc = c
        if nm == "chrome":
            cc = (0.62, 0.63, 0.65)
        elif nm == "metal":
            cc = (0.40, 0.41, 0.42)
        for li in poly.loop_indices:
            col.data[li].color = (cc[0], cc[1], cc[2], r)
    paint_far = MATS[PAINT].copy()
    paint_far.name = "paint_far"
    parts = bpy.data.materials.new("parts")
    idx = [0 if p.material_index == PAINT else 1 for p in me.polygons]
    me.materials.clear()
    me.materials.append(paint_far)
    me.materials.append(parts)
    for p, k in zip(me.polygons, idx):
        p.material_index = k
    n = tris(far)
    mod = far.modifiers.new("dec", 'DECIMATE')
    mod.decimate_type = 'COLLAPSE'
    mod.ratio = min(1.0, target / max(n, 1))
    mod.use_collapse_triangulate = True
    apply_mods(far)
    shade(far, 45.0)
    return far


def export(objs, path):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    kw = dict(filepath=path, export_format='GLB', use_selection=True, export_apply=True,
              export_materials='EXPORT', export_yup=True, export_normals=True,
              export_texcoords=False, export_tangents=False, export_skins=False,
              export_animations=False, export_cameras=False, export_lights=False)
    try:
        bpy.ops.export_scene.gltf(export_vertex_color='ACTIVE', **kw)
    except TypeError:
        bpy.ops.export_scene.gltf(export_colors=True, **kw)


# --- the bikes ---------------------------------------------------------------------------------
#
# Each builder returns a dict: objects body / steer / wheel_f / wheel_r (already origin-placed),
# and the numbers Motorcycle needs (axles, radii, the steering axis, the rider's points).

def steer_frame(head, rake):
    """The steering axis through `head` (its top), raked back by `rake` (degrees): its unit
    direction up the axis, in this file's frame (Y forward)."""
    r = math.radians(rake)
    return Vector(head), Vector((0.0, -math.sin(r), math.cos(r)))


def along_axis(head, axis, z):
    """The point on the steering axis at height z."""
    t = (z - head.z) / axis.z
    return head + axis * t


def fork_legs(bm, axle, head, axis, x, r_lower, r_upper, lower_mat, upper_mat, usd=False, top_z=None):
    """A telescopic fork leg: from the axle lug up along the axis. Upside-down (`usd`): the fat
    outer tube is up top, the thin stanchion below."""
    # The leg runs parallel to the steering axis, through the axle offset forward of it.
    top = axle + axis * ((top_z if top_z else head.z) - axle.z) / axis.z
    split = axle + (top - axle) * (0.40 if usd else 0.55)
    a = Vector((x, axle.y, axle.z))
    b = Vector((x, split.y, split.z))
    c = Vector((x, top.y, top.z))
    if usd:
        # Stanchion (gold/black anodised) from the axle lug up into the outer tube.
        tube(bm, polyline([a + axis * 0.02, b + axis * 0.04], 0.04), r_lower, lower_mat, n=18)
        # Outer tube with a machined top cap.
        lathe_axis(bm, b, c, [(r_upper, 0.0), (r_upper * 1.03, 0.04), (r_upper * 1.03, 0.98), (r_upper * 0.8, 1.0), (0.004, 1.0)], upper_mat, 20)
        lathe_axis(bm, b, b + axis * 0.03, [(r_upper * 1.06, 0.0), (r_upper * 1.06, 1.0)], DARK, 20)
    else:
        lathe_axis(bm, a, b, [(0.004, 0.0), (r_lower, 0.02), (r_lower * 1.02, 0.6), (r_lower * 0.95, 1.0)], lower_mat, 20)
        tube(bm, polyline([b - axis * 0.02, c], 0.04), r_upper, upper_mat, n=18)
        # The dust seal.
        lathe_axis(bm, b - axis * 0.012, b + axis * 0.012, [(r_upper * 1.25, 0.0), (r_upper * 1.25, 1.0)], RUBBER, 18)
    # The axle lug.
    rbox(bm, (0.05, 0.075, 0.06), a, lower_mat if not usd else DARK, bevel=0.012)
    return top


def lathe_axis(bm, a, b, prof, mat, segs=16):
    """A lathe from point a to point b: prof [(radius, t 0..1 along a->b)]."""
    a, b = Vector(a), Vector(b)
    ax = (b - a)
    L = ax.length
    ax.normalize()
    up = Vector((1, 0, 0)) if abs(ax.x) < 0.9 else Vector((0, 1, 0))
    s1 = up.cross(ax).normalized()
    s2 = ax.cross(s1).normalized()
    rings = []
    for r, t in prof:
        rings.append([bm.verts.new(a + ax * (L * t) + s1 * (r * math.cos(math.tau * j / segs)) + s2 * (r * math.sin(math.tau * j / segs)))
                      for j in range(segs)])
    fs = rings_to_faces(bm, rings, mat)
    if prof[0][0] > 0.002:
        f = face(bm, rings[0], mat)
        if f:
            fs.append(f)
    if prof[-1][0] > 0.002:
        f = face(bm, rings[-1], mat)
        if f:
            fs.append(f)
    bmesh.ops.recalc_face_normals(bm, faces=fs)


def triple_clamp(bm, head, axis, z, xs, r_leg, plate_t=0.022, mat=METAL):
    """A clamp plate at height z on the axis holding legs at +-xs (and the stem)."""
    p = along_axis(head, axis, z)
    # The plate is square to the axis.
    ang = math.atan2(-axis.y, axis.z)
    m = rot_axis((1, 0, 0), -ang) if False else Matrix.Rotation(ang, 3, Vector((1, 0, 0)))
    rbox(bm, (xs * 2 + r_leg * 2.6, 0.085, plate_t), p + Vector((0, 0.025, 0)), mat, bevel=0.008, segs=2, rot=m)
    for s in (-1, 1):
        lathe_axis(bm, p + Vector((s * xs, 0.04, 0)) - axis * plate_t * 0.6, p + Vector((s * xs, 0.04, 0)) + axis * plate_t * 0.6,
                   [(r_leg * 1.28, 0.0), (r_leg * 1.28, 1.0)], mat, 20)


# ---------------------------------------------------------------------------------------------------
# The supersport
# ---------------------------------------------------------------------------------------------------

def build_sport():
    S = {"name": "sport", "wb": 1.40, "rake": 24.0}
    rf, rr = 0.300, 0.315
    yf, yr = 0.70, -0.70
    axf = Vector((0, yf, rf))
    axr = Vector((0, yr, rr))
    head, axis = steer_frame((0, 0.395, 0.905), 24.0)
    # The fork offset: the axle sits ahead of the axis.
    # --- wheels
    bmf = bmesh.new()
    tyre(bmf, axf, rf, 0.122, 0.072)
    cast_rim(bmf, axf, 0.216, 0.085, spokes=5, split=True, mat=DARK, hub_r=0.05)
    for s in (-1, 1):
        disc(bmf, axf, s * 0.075, 0.160, 0.105, petal=False)
    wf = to_object("moto_sport_wheel_f", bmf)
    bmr = bmesh.new()
    tyre(bmr, axr, rr, 0.180, 0.102)
    cast_rim(bmr, axr, 0.216, 0.140, spokes=5, split=True, mat=DARK, hub_r=0.058)
    disc(bmr, axr, 0.080, 0.110, 0.072, carrier=True)
    sprocket(bmr, axr, -0.088, 0.105, 43, DARK)
    wr = to_object("moto_sport_wheel_r", bmr)

    # --- steer: fork, clamps, clip-ons, front fender, calipers
    bs = bmesh.new()
    fork_x = 0.105
    tops = []
    for s in (-1, 1):
        tops.append(fork_legs(bs, Vector((s * fork_x, axf.y, axf.z)), head, axis, s * fork_x, 0.026, 0.0315, METAL, DARK, usd=True, top_z=head.z + 0.03))
    triple_clamp(bs, head, axis, head.z - 0.005, fork_x, 0.0315, 0.024, METAL)
    triple_clamp(bs, head, axis, head.z - 0.165, fork_x, 0.0315, 0.040, DARK)
    # Axle.
    tube(bs, [axf + Vector((-0.13, 0, 0)), axf + Vector((0.13, 0, 0))], 0.0125, METAL, n=12)
    # Radial calipers behind the legs, on the discs.
    for s in (-1, 1):
        caliper(bs, axf, s * 0.075, 0.160, math.radians(140), (0.05, 0.13, 0.065), METAL)
    # Clip-on bars below the top clamp: tube out and back, grips, levers, switchgear, mirrorless
    # (the mirrors are on the fairing).
    for s in (-1, 1):
        root = Vector((s * fork_x, 0, 0)) + along_axis(head, axis, head.z - 0.04)
        end = root + Vector((s * 0.20, -0.07, -0.03))
        tube(bs, polyline([root, end], 0.02), 0.011, DARK, n=12)
        rbox(bs, (0.05, 0.06, 0.05), root + Vector((s * 0.035, -0.012, 0)), DARK, bevel=0.01)
        g0 = root + Vector((s * 0.085, -0.03, -0.012))
        grip(bs, g0, end + Vector((s * 0.02, -0.006, -0.002)), 0.0165)
        rbox(bs, (0.045, 0.05, 0.04), g0 + Vector((-s * 0.012, 0, 0.004)), TRIM, bevel=0.01, segs=2)
        lever(bs, g0 + Vector((0, 0.03, 0.0)), s, 0.15, METAL)
        if s > 0:
            # The brake reservoir.
            rbox(bs, (0.035, 0.045, 0.04), g0 + Vector((-0.03, 0.01, 0.05)), DARK, bevel=0.008)
    # Front fender: a short hugger in paint, a strip over the tyre.
    sects = []
    for k in range(13):
        a = math.radians(28 + 96 * k / 12)
        rr_f = rf + 0.022
        cy = axf.y + rr_f * math.cos(a) * 0.98
        cz = axf.z + rr_f * math.sin(a)
        n = Vector((0, math.cos(a), math.sin(a)))
        w = 0.118 + 0.01 * math.sin(math.pi * k / 12)
        sects.append([Vector((x, cy, cz)) + n * (0.012 * (1 - (x / (w * 0.5)) ** 2)) for x in (-w * 0.5, -w * 0.25, 0.0, w * 0.25, w * 0.5)])
    bm_f = bmesh.new()
    grid = [[bm_f.verts.new(p) for p in row] for row in sects]
    for i in range(len(grid) - 1):
        for j in range(4):
            face(bm_f, (grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]), PAINT)
    bmesh.ops.recalc_face_normals(bm_f, faces=bm_f.faces[:])
    fender = to_object("fender", bm_f)
    sol = fender.modifiers.new("sol", 'SOLIDIFY')
    sol.thickness = 0.004
    apply_mods(fender)
    steer = join([to_object("moto_sport_steer", bs), fender], "moto_sport_steer")

    # --- body
    parts = []
    bb = bmesh.new()
    # The twin-spar beam: from the headstock down and back round the engine to the swingarm
    # pivot plates, satin silver, a tall rounded box section.
    pivot = Vector((0, -0.15, 0.40))
    hs_bot = along_axis(head, axis, head.z - 0.20)
    for s in (-1, 1):
        path = bez(head + Vector((s * 0.04, 0.0, -0.06)), head + Vector((s * 0.15, -0.12, -0.05)),
                   Vector((s * 0.16, 0.0, 0.60)), Vector((s * 0.115, -0.18, 0.52)), 14)
        sweep(bb, path, lambda i: rrect(0.035, 0.12 - 0.03 * i / 14, 0.012, 2), FRAME, caps=True, up=Vector((s, 0.0, 0.0)) if False else None)
        # Pivot plate.
        sweep(bb, polyline([Vector((s * 0.115, -0.18, 0.56)), Vector((s * 0.12, -0.17, 0.33))], 0.03),
              rrect(0.03, 0.09, 0.012, 2), FRAME)
    lathe_axis(bb, hs_bot, along_axis(head, axis, head.z + 0.01), [(0.032, 0.0), (0.032, 1.0)], FRAME, 20)
    # Swingarm: a braced box section from the pivot to the axle, both sides.
    for s in (-1, 1):
        path = polyline([Vector((s * 0.115, pivot.y, pivot.z)), Vector((s * 0.105, -0.45, 0.37)), Vector((s * 0.105, axr.y + 0.02, axr.z))], 0.03)
        sweep(bb, path, lambda i, n=len(path): rrect(0.030, 0.085 - 0.03 * i / max(n - 1, 1), 0.010, 2), FRAME)
        # Chain adjuster block.
        rbox(bb, (0.035, 0.05, 0.035), Vector((s * 0.107, axr.y, axr.z)), METAL, bevel=0.006)
    tube(bb, [axr + Vector((-0.125, 0, 0)), axr + Vector((0.125, 0, 0))], 0.012, METAL, n=12)
    # Rear caliper on the right, hung under the disc.
    caliper(bb, axr, 0.080, 0.110, math.radians(-110), (0.04, 0.08, 0.05), DARK)
    # Chain from the front sprocket to the rear.
    front_spr = Vector((0, -0.07, 0.35))
    sprocket(bb, front_spr, -0.088, 0.042, 16, DARK)
    chain(bb, front_spr, 0.045, axr, 0.107, -0.088)
    # Chain guard.
    sweep(bb, polyline([Vector((-0.10, -0.30, 0.43)), Vector((-0.10, -0.62, 0.41))], 0.04),
          [(-0.004, -0.01), (0.004, -0.01), (0.004, 0.02), (-0.004, 0.02)], TRIM)
    # The rear shock (behind the engine, visible through the frame).
    lathe_axis(bb, Vector((0, -0.28, 0.33)), Vector((0, -0.22, 0.62)), [(0.025, 0.0), (0.025, 0.25), (0.018, 0.3), (0.018, 1.0)], METAL, 14)
    tube(bb, polyline([Vector((0, -0.27, 0.36)), Vector((0, -0.23, 0.58))], 0.005), 0.034, AMBER if False else PAINT, n=10)

    # Engine: an inline four, crankcase cast in dark metal, the cylinder block canted forward,
    # the head with a cam cover, the side covers lathed.
    eng = bmesh.new()
    rbox(eng, (0.40, 0.36, 0.20), Vector((0, 0.02, 0.32)), DARK, bevel=0.03, segs=3)
    rbox(eng, (0.30, 0.26, 0.12), Vector((0, -0.02, 0.215)), DARK, bevel=0.03, segs=3)
    cant = Matrix.Rotation(math.radians(-32), 3, Vector((1, 0, 0)))
    blk = Vector((0, 0.13, 0.48))
    rbox(eng, (0.36, 0.16, 0.20), blk, DARK, bevel=0.02, segs=2, rot=cant)
    # Cooling fins hinted on the block's front.
    for k in range(5):
        rbox(eng, (0.34, 0.006, 0.012), blk + cant @ Vector((0, 0.083, -0.08 + k * 0.035)), DARK, bevel=0.0, rot=cant)
    hd = blk + cant @ Vector((0, 0.0, 0.14))
    rbox(eng, (0.37, 0.17, 0.08), hd, METAL, bevel=0.02, segs=2, rot=cant)
    rbox(eng, (0.33, 0.14, 0.05), hd + cant @ Vector((0, -0.005, 0.06)), DARK, bevel=0.02, segs=3, rot=cant)
    for s in (-1, 1):
        lathe(eng, [(0.0001, s * 0.200), (0.088, s * 0.200), (0.092, s * 0.215), (0.080, s * 0.232), (0.0001, s * 0.236)], 40, Vector((0, -0.01, 0.30)), 'X', METAL)
        lathe(eng, [(0.0001, s * 0.200), (0.062, s * 0.200), (0.064, s * 0.213), (0.0001, s * 0.218)], 32, Vector((0, 0.13, 0.25)), 'X', DARK)
        for k in range(6):
            a = math.tau * k / 6
            q = Vector((s * 0.222, -0.01 + 0.078 * math.cos(a), 0.30 + 0.078 * math.sin(a)))
            lathe(eng, [(0.0001, 0.0), (0.006, 0.0), (0.006, s * 0.008), (0.0001, s * 0.01)], 6, q, 'X', CHROME)
    # Headers: four pipes down from the head's front and back under the engine.
    for k in range(4):
        x = -0.135 + k * 0.09
        p0 = hd + cant @ Vector((x, 0.09, -0.06))
        path = bez(p0, p0 + Vector((0, 0.10, -0.10)), Vector((x * 0.6, 0.20, 0.10)), Vector((x * 0.25, 0.0, 0.09)), 14)
        tube(eng, path, 0.019, METAL, n=12)
    # Collector and the stubby silencer on the right, under the tail.
    col_path = bez(Vector((0, 0.0, 0.09)), Vector((0.02, -0.12, 0.09)), Vector((0.10, -0.22, 0.14)), Vector((0.14, -0.36, 0.26)), 10)
    tube(eng, col_path, 0.032, METAL, n=14)
    can_a = Vector((0.15, -0.36, 0.27))
    can_b = Vector((0.17, -0.64, 0.42))
    sweep(eng, polyline([can_a, can_b], 0.04), lambda i: rrect(0.09, 0.115 - 0.02 * i / 8.0, 0.035, 3), DARK)
    lathe_axis(eng, can_b - (can_b - can_a).normalized() * 0.03, can_b + (can_b - can_a).normalized() * 0.012, [(0.042, 0.0), (0.044, 0.5), (0.020, 1.0)], METAL, 20)
    lathe_axis(eng, can_b, can_b + (can_b - can_a).normalized() * 0.018, [(0.016, 0.0), (0.016, 1.0)], CHROME, 12)
    # Radiator: a curved core in a frame ahead of the engine, fins as dark slats.
    rad_c = Vector((0, 0.36, 0.52))
    rtilt = Matrix.Rotation(math.radians(-14), 3, Vector((1, 0, 0)))
    rbox(eng, (0.40, 0.045, 0.28), rad_c, TRIM, bevel=0.008, rot=rtilt)
    for k in range(18):
        rbox(eng, (0.38, 0.004, 0.006), rad_c + rtilt @ Vector((0, 0.024, -0.12 + k * 0.0141)), METAL, bevel=0.0, rot=rtilt)
    parts.append(to_object("engine", eng, sharp_deg=35.0))
    parts.append(to_object("chassis", bb, sharp_deg=35.0))

    # Bodywork: the tank, the seat, the tail and the fairing, lofted and subdivided.
    tank_secs = []
    for k in range(9):
        t = k / 8.0
        y = 0.33 - 0.45 * t
        top = 0.985 - 0.06 * t - 0.08 * (2 * t - 1) ** 4
        bot = 0.68 + 0.08 * t
        w = 0.25 + 0.17 * math.sin(math.pi * min(t * 1.2, 1.0)) - 0.10 * t
        tank_secs.append(sect(y, 0, (top + bot) * 0.5, w, top - bot, n=16, e=2.8, taper_top=0.32))
    bmt = bmesh.new()
    loft(bmt, tank_secs, PAINT)
    tank = to_object("tank", bmt)
    subsurf(tank, 2)
    parts.append(tank)
    # Fuel cap.
    bmc = bmesh.new()
    lathe(bmc, [(0.0001, 0.0), (0.045, 0.0), (0.046, 0.008), (0.040, 0.012), (0.0001, 0.012)], 24, Vector((0, 0.22, 0.955)), 'Z', METAL)
    parts.append(to_object("cap", bmc))
    # Rider seat, the tail and the pillion pad over it.
    seat_secs = []
    for k in range(7):
        t = k / 6.0
        y = -0.06 - 0.42 * t
        z = 0.845 + 0.02 * t - 0.018 * math.sin(math.pi * t)
        w = 0.20 + 0.10 * math.sin(math.pi * min(t * 1.4, 1.0))
        seat_secs.append(sect(y, 0, z - 0.035, w, 0.075, n=16, e=3.0))
    bms = bmesh.new()
    loft(bms, seat_secs, SEAT)
    seat = to_object("seat", bms)
    subsurf(seat, 2)
    parts.append(seat)
    tail_secs = []
    for k in range(12):
        t = k / 11.0
        y = -0.16 - 0.76 * t
        top = 0.80 + 0.135 * t ** 1.1
        bot = 0.62 + 0.27 * t ** 1.1
        w = 0.30 - 0.21 * t ** 1.4
        tail_secs.append(sect(y, 0, (top + bot) * 0.5, w, top - bot, n=18, e=2.8, taper_top=0.25))
    bml = bmesh.new()
    loft(bml, tail_secs, PAINT)
    tail = to_object("tail", bml)
    subsurf(tail, 2)
    parts.append(tail)
    pill = []
    for k in range(5):
        t = k / 4.0
        pill.append(sect(-0.50 - 0.18 * t, 0, 0.885 + 0.035 * t, 0.17 - 0.07 * t, 0.035, n=12, e=3.0))
    bmp = bmesh.new()
    loft(bmp, pill, SEAT)
    pobj = to_object("pillion", bmp)
    subsurf(pobj, 1)
    parts.append(pobj)
    # Taillight in the tail's tip, the licence hanger under it.
    bmx = bmesh.new()
    lamp_lens(bmx, Vector((0, -0.918, 0.912)), (0, -1, 0.25), 0.040, 0.016, 0.010, LIGHT_R)
    sweep(bmx, polyline([Vector((0, -0.84, 0.84)), Vector((0, -0.98, 0.74)), Vector((0, -1.01, 0.66))], 0.03), lambda i: rrect(0.10 + 0.04 * i / 6.0, 0.008, 0.003, 1), TRIM)
    for s in (-1, 1):
        tube(bmx, [Vector((s * 0.04, -0.97, 0.75)), Vector((s * 0.12, -0.98, 0.76))], 0.006, TRIM, n=8)
        lamp_lens(bmx, Vector((s * 0.125, -0.985, 0.76)), (s * 0.3, -1, 0), 0.012, 0.012, 0.012, AMBER, segs=12)
    parts.append(to_object("taillight", bmx))

    # The fairing: one lofted shell from the pointed nose back past the radiator to a slanted
    # rear edge by the rider's knees; the tank stands up out of it behind the screen.
    FAIR = [(1.015, 0.840, 0.805, 0.03), (0.990, 0.878, 0.760, 0.15), (0.95, 0.918, 0.718, 0.25),
            (0.88, 0.962, 0.668, 0.33), (0.80, 0.998, 0.600, 0.39), (0.72, 1.012, 0.505, 0.43),
            (0.64, 1.008, 0.405, 0.45), (0.55, 0.985, 0.335, 0.455), (0.45, 0.948, 0.300, 0.45),
            (0.35, 0.890, 0.290, 0.44), (0.25, 0.800, 0.295, 0.425), (0.16, 0.675, 0.315, 0.41)]
    fair = [sect(y, 0, (t + b_) * 0.5, w, t - b_, n=22, e=3.3, taper_top=0.62, taper_bottom=0.30) for y, t, b_, w in FAIR]
    bmF = bmesh.new()
    loft(bmF, fair, PAINT, cap0=True, cap1=False)
    fairing = to_object("fairing", bmF)
    subsurf(fairing, 2)
    sol = fairing.modifiers.new("sol", 'SOLIDIFY')
    sol.thickness = 0.004
    apply_mods(fairing)
    parts.append(fairing)
    # The belly pan under the engine.
    pan = []
    for k in range(6):
        t = k / 5.0
        y = 0.28 - 0.52 * t
        pan.append(sect(y, 0, 0.22 + 0.02 * t, 0.44 - 0.12 * t, 0.16 - 0.04 * t, n=14, e=3.0))
    bmb = bmesh.new()
    loft(bmb, pan, PAINT)
    belly = to_object("belly", bmb)
    subsurf(belly, 1)
    parts.append(belly)
    # Screen, headlamps, nose intake, mirrors with integrated indicators.
    bmg = bmesh.new()
    scr = []
    for k in range(7):
        t = k / 6.0
        y = 0.80 - 0.24 * t
        z = 0.995 + 0.12 * t ** 0.9
        w = 0.22 + 0.10 * t
        scr.append([Vector((x * w * 0.5, y - 0.02 * x * x, z - 0.075 * x * x)) for x in (-1, -0.66, -0.33, 0, 0.33, 0.66, 1)])
    g = [[bmg.verts.new(p) for p in row] for row in scr]
    for i in range(6):
        for j in range(6):
            face(bmg, (g[i][j], g[i][j + 1], g[i + 1][j + 1], g[i + 1][j]), GLASS)
    bmesh.ops.recalc_face_normals(bmg, faces=bmg.faces[:])
    for s in (-1, 1):
        lamp_lens(bmg, Vector((s * 0.075, 0.952, 0.872)), (s * 0.45, 1, 0.12), 0.055, 0.020, 0.008, LIGHT_F)
        mirror_on_stalk(bmg, Vector((s * 0.22, 0.70, 1.00)), Vector((s * 0.30, 0.66, 1.05)), 0.12, 0.05)
        lamp_lens(bmg, Vector((s * 0.36, 0.680, 1.05)), (s * 0.5, 1, 0), 0.03, 0.006, 0.004, AMBER, segs=10)
        # Side intakes in the flanks of the fairing.
        lamp_lens(bmg, Vector((s * 0.262, 0.58, 0.62)), (s, 0.15, 0), 0.10, 0.03, 0.004, TRIM, rim_mat=DARK)
    lamp_lens(bmg, Vector((0, 0.985, 0.835)), (0, 1, -0.2), 0.034, 0.020, 0.004, TRIM, rim_mat=DARK)
    # Instrument panel behind the screen.
    rbox(bmg, (0.16, 0.03, 0.09), Vector((0, 0.50, 1.00)), TRIM, bevel=0.01, rot=Matrix.Rotation(math.radians(-55), 3, Vector((1, 0, 0))))
    rbox(bmg, (0.12, 0.006, 0.06), Vector((0, 0.488, 1.008)), GLASS, bevel=0.0, rot=Matrix.Rotation(math.radians(-55), 3, Vector((1, 0, 0))))
    parts.append(to_object("screen", bmg))
    # Rider pegs and hangers, the pillion pegs, the kickstand (left, folded up), the shift and
    # brake levers.
    bmp2 = bmesh.new()
    for s in (-1, 1):
        sweep(bmp2, polyline([Vector((s * 0.12, -0.17, 0.48)), Vector((s * 0.15, -0.30, 0.36)), Vector((s * 0.13, -0.40, 0.42))], 0.02),
              rrect(0.012, 0.05, 0.004, 1), METAL)
        footpeg(bmp2, Vector((s * 0.15, -0.30, 0.355)), s, 0.075, METAL)
        footpeg(bmp2, Vector((s * 0.13, -0.53, 0.47)), s, 0.06, METAL)
        tube(bmp2, polyline([Vector((s * 0.165, -0.28, 0.36)), Vector((s * 0.17, -0.18, 0.33))], 0.02), 0.006, METAL, n=8)
    tube(bmp2, polyline([Vector((-0.13, -0.12, 0.25)), Vector((-0.16, -0.32, 0.22))], 0.02), 0.012, DARK, n=8)
    parts.append(to_object("pegs", bmp2))
    body = join(parts, "moto_sport_body")
    S.update({"axf": axf, "axr": axr, "rf": rf, "rr": rr, "head": head, "axis": axis,
              "wf_w": 0.122, "wr_w": 0.180,
              "seat": Vector((0, -0.24, 0.86)), "grip": Vector((0.30, 0.255, 0.835)),
              "peg": Vector((0.17, -0.31, 0.375)), "lean": 34.0, "lamp": Vector((0, 0.93, 0.92)),
              "tail": Vector((0, -0.92, 0.912)), "width": 0.72})
    return S, body, steer, wf, wr


# ---------------------------------------------------------------------------------------------------
# The cruiser
# ---------------------------------------------------------------------------------------------------

def build_cruiser():
    S = {"name": "cruiser", "wb": 1.65, "rake": 32.0}
    rf, rr = 0.330, 0.330
    yf, yr = 0.825, -0.825
    axf = Vector((0, yf, rf))
    axr = Vector((0, yr, rr))
    head, axis = steer_frame((0, 0.335, 0.985), 32.0)
    bmf = bmesh.new()
    tyre(bmf, axf, rf, 0.130, 0.085)
    wire_rim(bmf, axf, 0.205, 0.075, hub_r=0.075)
    disc(bmf, axf, 0.090, 0.150, 0.098, mat_disc=METAL, holes=True)
    wf = to_object("moto_cruiser_wheel_f", bmf)
    bmr = bmesh.new()
    tyre(bmr, axr, rr, 0.150, 0.092)
    wire_rim(bmr, axr, 0.205, 0.090, hub_r=0.08)
    disc(bmr, axr, 0.092, 0.145, 0.095, mat_disc=METAL)
    # The belt pulley on the left.
    lathe(bmr, [(0.06, -0.085), (0.165, -0.085), (0.172, -0.095), (0.172, -0.125), (0.165, -0.13), (0.06, -0.13)], 56, axr, 'X', DARK)
    lathe(bmr, [(0.0001, -0.1), (0.12, -0.1), (0.12, -0.104), (0.0001, -0.104)], 40, axr, 'X', CHROME)
    wr = to_object("moto_cruiser_wheel_r", bmr)

    bs = bmesh.new()
    fork_x = 0.125
    for s in (-1, 1):
        fork_legs(bs, Vector((s * fork_x, axf.y, axf.z)), head, axis, s * fork_x, 0.034, 0.0245, METAL, CHROME, usd=False, top_z=head.z + 0.02)
        # Chrome fork shrouds over the upper tubes.
        a = along_axis(head, axis, head.z - 0.30) + Vector((s * fork_x, 0.045, 0))
        b = along_axis(head, axis, head.z - 0.02) + Vector((s * fork_x, 0.045, 0))
        lathe_axis(bs, a, b, [(0.032, 0.0), (0.037, 0.15), (0.037, 1.0)], CHROME, 20)
    triple_clamp(bs, head, axis, head.z + 0.01, fork_x, 0.037, 0.03, CHROME)
    triple_clamp(bs, head, axis, head.z - 0.31, fork_x, 0.034, 0.045, CHROME)
    tube(bs, [axf + Vector((-0.15, 0, 0)), axf + Vector((0.15, 0, 0))], 0.012, CHROME, n=12)
    caliper(bs, axf, 0.090, 0.150, math.radians(150), (0.05, 0.12, 0.07), DARK)
    # Pull-back bars on risers, wide, chrome.
    rise = along_axis(head, axis, head.z + 0.03)
    bar_pts = []
    for s in (-1, 1):
        lathe_axis(bs, rise + Vector((s * 0.05, 0, 0)), rise + Vector((s * 0.05, 0, 0)) + axis * 0.09, [(0.016, 0.0), (0.016, 1.0)], CHROME, 12)
    top = rise + axis * 0.09
    path = []
    for k in range(17):
        t = (k / 16.0) * 2 - 1
        x = t * 0.40
        y = top.y + 0.02 - 0.20 * smooth(abs(t) * 1.2 - 0.15)
        z = top.z + 0.01 + 0.045 * smooth(abs(t) * 1.4 - 0.3)
        path.append(Vector((x, y, z)))
    tube(bs, path[3:14], 0.0127, CHROME, n=12, caps=True)
    for s in (-1, 1):
        a = path[0] if s < 0 else path[-1]
        b = path[3] if s < 0 else path[13]
        grip(bs, b, a, 0.0175)
        rbox(bs, (0.045, 0.05, 0.045), b + (b - a).normalized() * -0.01 + Vector((0, 0, 0)), CHROME, bevel=0.012, segs=2)
        lever(bs, b + Vector((0, 0.035, 0.0)), s, 0.17, CHROME)
        mirror_on_stalk(bs, b + Vector((s * -0.05, 0.02, 0.02)), b + Vector((s * 0.05, 0.06, 0.20)), 0.10, 0.065, CHROME, CHROME)
    # The 7-inch headlamp in a chrome bucket on ears, a pair of bullet indicators.
    hl = Vector((0, 0.56, 0.93))
    lathe(bs, [(0.0001, -0.12), (0.06, -0.115), (0.092, -0.07), (0.101, 0.0), (0.104, 0.01), (0.104, 0.018)], 40, hl + Vector((0, 0, 0)), 'Y', CHROME)
    lamp_lens(bs, hl + Vector((0, 0.018, 0)), (0, 1, 0), 0.094, 0.094, 0.020, LIGHT_F, rim_mat=CHROME, segs=40)
    for s in (-1, 1):
        tube(bs, [hl + Vector((s * 0.09, -0.04, 0)), along_axis(head, axis, head.z - 0.20) + Vector((s * 0.12, 0.05, 0))], 0.009, CHROME)
        bt = hl + Vector((s * 0.20, -0.02, 0.02))
        tube(bs, [hl + Vector((s * 0.09, -0.03, 0.02)), bt], 0.006, CHROME, n=8)
        lathe(bs, [(0.0001, -0.05), (0.022, -0.04), (0.026, 0.0), (0.026, 0.008)], 16, bt, 'Y', CHROME)
        lamp_lens(bs, bt + Vector((0, 0.008, 0)), (0, 1, 0), 0.023, 0.023, 0.010, AMBER, rim_mat=CHROME, segs=16)
    steer_core = to_object("moto_cruiser_steer", bs)
    # Front fender: a deep valanced fender, painted.
    fsec = []
    for k in range(15):
        a = math.radians(-20 + 170 * k / 14)
        rr_f = rf + 0.035
        cy = axf.y + rr_f * math.cos(a)
        cz = axf.z + rr_f * math.sin(a)
        n = Vector((0, math.cos(a), math.sin(a)))
        w = 0.17
        row = []
        for j in range(7):
            u = j / 6.0 * 2 - 1
            drop = 0.07 * (abs(u) ** 3)
            row.append(Vector((u * w * 0.5, cy, cz)) + n * (0.02 * (1 - u * u) - drop))
        fsec.append(row)
    bmv = bmesh.new()
    grid = [[bmv.verts.new(p) for p in row] for row in fsec]
    for i in range(len(grid) - 1):
        for j in range(6):
            face(bmv, (grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]), PAINT)
    bmesh.ops.recalc_face_normals(bmv, faces=bmv.faces[:])
    ff = to_object("ffender", bmv)
    subsurf(ff, 1)
    sol = ff.modifiers.new("sol", 'SOLIDIFY')
    sol.thickness = 0.004
    apply_mods(ff)
    steer = join([steer_core, ff], "moto_cruiser_steer")

    parts = []
    bb = bmesh.new()
    # Gloss black steel tube frame: backbone, down tubes, the cradle under the engine, the rear
    # loop, the seat rails.
    hs_bot = along_axis(head, axis, head.z - 0.24)
    lathe_axis(bb, hs_bot, along_axis(head, axis, head.z + 0.0), [(0.031, 0.0), (0.031, 1.0)], FRAME, 18)
    tube(bb, bez(head + Vector((0, -0.02, -0.03)), Vector((0, 0.05, 0.86)), Vector((0, -0.30, 0.78)), Vector((0, -0.42, 0.66)), 14), 0.022, FRAME, n=14)
    for s in (-1, 1):
        down = bez(hs_bot + Vector((s * 0.02, 0, 0)), Vector((s * 0.09, 0.40, 0.45)), Vector((s * 0.11, 0.32, 0.16)), Vector((s * 0.11, 0.18, 0.13)), 12)
        cradle = polyline([Vector((s * 0.11, 0.18, 0.13)), Vector((s * 0.11, -0.30, 0.13)), Vector((s * 0.12, -0.42, 0.20))], 0.04)
        rear = bez(Vector((s * 0.12, -0.42, 0.20)), Vector((s * 0.13, -0.50, 0.40)), Vector((s * 0.12, -0.45, 0.60)), Vector((s * 0.05, -0.42, 0.66)), 10)
        tube(bb, down + cradle[1:] + rear[1:], 0.016, FRAME, n=12)
        # Seat rail and the rear loop under the fender.
        tube(bb, bez(Vector((s * 0.05, -0.42, 0.66)), Vector((s * 0.12, -0.60, 0.64)), Vector((s * 0.13, -0.90, 0.60)), Vector((s * 0.12, -1.02, 0.58)), 12), 0.013, FRAME, n=10)
        # Swingarm tubes and the shock to the rail.
        tube(bb, polyline([Vector((s * 0.12, -0.42, 0.30)), Vector((s * 0.105, axr.y, axr.z))], 0.05), 0.020, FRAME, n=12)
        lathe_axis(bb, Vector((s * 0.12, -0.70, 0.36)), Vector((s * 0.13, -0.78, 0.66)), [(0.022, 0.0), (0.022, 0.3), (0.017, 0.35), (0.017, 0.65), (0.03, 0.66), (0.03, 1.0)], CHROME, 14)
        # Coil spring as a helix.
        hp = []
        a0 = Vector((s * 0.12, -0.70, 0.36))
        a1 = Vector((s * 0.13, -0.78, 0.66))
        ax = (a1 - a0)
        L = ax.length
        ax.normalize()
        e1 = Vector((1, 0, 0)).cross(ax).normalized()
        e2 = ax.cross(e1)
        for k in range(97):
            t = k / 96.0
            ang = t * math.tau * 7
            hp.append(a0 + ax * (0.06 + 0.17 * t) + e1 * 0.030 * math.cos(ang) + e2 * 0.030 * math.sin(ang))
        tube(bb, hp, 0.0055, CHROME, n=6)
    tube(bb, [axr + Vector((-0.14, 0, 0)), axr + Vector((0.14, 0, 0))], 0.013, CHROME, n=12)
    caliper(bb, axr, 0.092, 0.145, math.radians(-120), (0.045, 0.10, 0.06), DARK)
    parts.append(to_object("frame", bb, sharp_deg=35))

    # The V-twin: crankcase, two finned barrels and heads at a 45-degree vee, the rocker boxes,
    # pushrod tubes, the round air cleaner on the right, the primary cover on the left, the
    # gearbox behind, the belt to the rear pulley.
    eng = bmesh.new()
    cc = Vector((0, 0.02, 0.33))
    rbox(eng, (0.22, 0.34, 0.20), cc, METAL, bevel=0.05, segs=3)
    lathe(eng, [(0.0001, -0.13), (0.11, -0.13), (0.12, -0.12), (0.12, 0.12), (0.11, 0.13), (0.0001, 0.13)], 36, cc + Vector((0, 0.0, -0.01)), 'X', METAL)
    for side_ang, name in ((22.5, "front"), (-22.5, "rear")):
        ax = Vector((0, math.sin(math.radians(side_ang)), math.cos(math.radians(side_ang))))
        base = cc + Vector((0, 0.05 * math.copysign(1, side_ang), 0.06)) + ax * 0.04
        finned_barrel(eng, base, ax, 0.052, 0.20, 11, 0.032, DARK, DARK)
        # Highlight the fin edges: a polished ring on every other fin's lip.
        hd = base + ax * 0.20
        finned_barrel(eng, hd, ax, 0.056, 0.10, 5, 0.030, METAL, METAL)
        # Rocker box.
        rbox(eng, (0.13, 0.15, 0.06), hd + ax * 0.13, CHROME, bevel=0.025, segs=3, rot=Matrix.Rotation(math.radians(side_ang), 3, Vector((1, 0, 0))))
        # Pushrod tubes on the right.
        tube(eng, [cc + Vector((0.05, 0.05 * math.copysign(1, side_ang), 0.10)), hd + ax * 0.10 + Vector((0.05, -0.02 * math.copysign(1, side_ang), 0))], 0.012, CHROME, n=10)
        # Spark plug lead.
        tube(eng, polyline([hd + ax * 0.05 + Vector((-0.09, 0, 0)), hd + ax * 0.05 + Vector((-0.14, 0, -0.08))], 0.02), 0.005, TRIM, n=6)
    # Air cleaner: a big chrome dish on the right.
    lathe(eng, [(0.0001, 0.11), (0.10, 0.11), (0.115, 0.125), (0.115, 0.15), (0.10, 0.165), (0.0001, 0.17)], 40, Vector((0, 0.03, 0.60)), 'X', CHROME)
    # Primary cover (left): a chrome case from the engine back to the gearbox.
    sweep(eng, polyline([Vector((-0.14, 0.10, 0.27)), Vector((-0.14, -0.30, 0.30))], 0.04), lambda i: rrect(0.05, 0.19 - 0.03 * (i / 10.0), 0.05, 4), CHROME)
    lathe(eng, [(0.0001, -0.165), (0.085, -0.165), (0.09, -0.17), (0.0001, -0.175)], 32, Vector((0, 0.08, 0.28)), 'X', CHROME)
    # Gearbox.
    rbox(eng, (0.19, 0.18, 0.16), Vector((0, -0.26, 0.32)), METAL, bevel=0.03, segs=2)
    # Oil tank/battery box under the seat.
    rbox(eng, (0.20, 0.16, 0.16), Vector((0, -0.44, 0.48)), FRAME, bevel=0.03, segs=2)
    # Exhaust: two pipes out of the heads' right side, sweeping back along the right, staggered
    # slash-cut mufflers.
    for k, (z0, y0) in enumerate(((0.62, 0.20), (0.62, -0.12))):
        p0 = Vector((0.07, y0, z0 - 0.06))
        zr = 0.28 + 0.10 * k
        path = bez(p0, p0 + Vector((0.12, 0.05 if k == 0 else -0.02, -0.05)), Vector((0.19, -0.10, zr + 0.03)), Vector((0.19, -0.42, zr)), 14)
        path += polyline([Vector((0.19, -0.42, zr)), Vector((0.20, -0.62, zr + 0.01))], 0.05)[1:]
        tube(eng, path, 0.022, CHROME, n=14)
        m0 = Vector((0.20, -0.60, zr + 0.01))
        m1 = Vector((0.21, -1.12 + 0.05 * k, zr + 0.05))
        lathe_axis(eng, m0, m1, [(0.024, 0.0), (0.044, 0.12), (0.045, 0.5), (0.045, 1.0)], CHROME, 24)
        lathe_axis(eng, m1 - (m1 - m0).normalized() * 0.002, m1 + (m1 - m0).normalized() * 0.002, [(0.0001, 0.0), (0.040, 0.0), (0.040, 1.0), (0.0001, 1.0)], DARK, 24)
        # Heat shield on the front run.
        sweep(eng, polyline([Vector((0.215, -0.08, zr + 0.04)), Vector((0.215, -0.38, zr + 0.01))], 0.04), [(-0.002, -0.03), (0.002, -0.03), (0.003, 0.03), (-0.003, 0.03)], CHROME)
    # Belt run (left) to the pulley.
    chain(eng, Vector((0, -0.25, 0.30)), 0.055, axr, 0.17, -0.108, DARK)
    parts.append(to_object("engine", eng, sharp_deg=35))

    # Tank: a teardrop split by a chrome console with the speedometer.
    secs = []
    for k in range(10):
        t = k / 9.0
        y = 0.40 - 0.62 * t
        top = 0.93 + 0.03 * math.sin(math.pi * t) - 0.06 * t ** 3
        bot = 0.73 + 0.02 * t
        w = 0.20 + 0.20 * math.sin(math.pi * (0.15 + 0.85 * t) ** 0.8) - 0.06 * t ** 2
        secs.append(sect(y, 0, (top + bot) * 0.5, w, top - bot, n=18, e=2.3, taper_top=0.15))
    bmt = bmesh.new()
    loft(bmt, secs, PAINT)
    tank = to_object("tank", bmt)
    subsurf(tank, 2)
    parts.append(tank)
    bmc = bmesh.new()
    sweep(bmc, polyline([Vector((0, 0.24, 0.968)), Vector((0, -0.10, 0.958))], 0.02), rrect(0.075, 0.02, 0.009, 3), CHROME)
    lathe(bmc, [(0.0001, 0.0), (0.045, 0.0), (0.047, 0.012), (0.042, 0.022), (0.0001, 0.024)], 32, Vector((0, 0.16, 0.966)), 'Z', CHROME)
    lathe(bmc, [(0.0001, 0.023), (0.040, 0.023), (0.0001, 0.026)], 32, Vector((0, 0.16, 0.966)), 'Z', GLASS)
    for s in (-1, 1):
        lathe(bmc, [(0.0001, 0.0), (0.035, 0.0), (0.035, 0.010), (0.0001, 0.012)], 24, Vector((s * 0.08, 0.30, 0.95)), 'Z', CHROME)
    parts.append(to_object("console", bmc))
    # Low solo seat with a raised back, and the pillion pad.
    secs = []
    for k in range(9):
        t = k / 8.0
        y = -0.18 - 0.44 * t
        z = 0.70 - 0.035 * math.sin(math.pi * min(t * 1.2, 1)) + 0.10 * smooth((t - 0.55) * 2.2)
        w = 0.24 + 0.14 * math.sin(math.pi * min(t * 1.3, 1)) - 0.04 * t
        secs.append(sect(y, 0, z - 0.04, w, 0.09, n=16, e=3.0))
    bms = bmesh.new()
    loft(bms, secs, SEAT)
    seat = to_object("seat", bms)
    subsurf(seat, 2)
    parts.append(seat)
    # Rear fender: deep, valanced, over the tyre to a bobbed end with the lamp.
    fsec = []
    for k in range(15):
        a = math.radians(20 + 110 * k / 14)
        rr_f = rr + 0.045
        cy = axr.y - rr_f * math.cos(a)
        cz = axr.z + rr_f * math.sin(a)
        n = Vector((0, -math.cos(a), math.sin(a)))
        w = 0.24
        row = []
        for j in range(9):
            u = j / 8.0 * 2 - 1
            row.append(Vector((u * w * 0.5, cy, cz)) + n * (0.03 * (1 - u * u) - 0.10 * abs(u) ** 4))
        fsec.append(row)
    bmv = bmesh.new()
    grid = [[bmv.verts.new(p) for p in row] for row in fsec]
    for i in range(len(grid) - 1):
        for j in range(8):
            face(bmv, (grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]), PAINT)
    bmesh.ops.recalc_face_normals(bmv, faces=bmv.faces[:])
    rf_ob = to_object("rfender", bmv)
    subsurf(rf_ob, 1)
    sol = rf_ob.modifiers.new("sol", 'SOLIDIFY')
    sol.thickness = 0.004
    apply_mods(rf_ob)
    parts.append(rf_ob)
    bmx = bmesh.new()
    tl = Vector((0, -1.205, 0.64))
    lamp_lens(bmx, tl, (0, -1, 0.25), 0.045, 0.028, 0.016, LIGHT_R, rim_mat=CHROME)
    for s in (-1, 1):
        bt = Vector((s * 0.16, -1.10, 0.58))
        tube(bmx, [Vector((s * 0.12, -1.08, 0.60)), bt], 0.006, CHROME, n=8)
        lathe(bmx, [(0.0001, 0.05), (0.022, 0.04), (0.026, 0.0), (0.026, -0.008)], 16, bt, 'Y', CHROME)
        lamp_lens(bmx, bt + Vector((0, -0.008, 0)), (0, -1, 0), 0.023, 0.023, 0.010, AMBER, rim_mat=CHROME, segs=16)
    # Forward controls: pegs out front on the frame's down tubes, the shifter and the brake pedal.
    for s in (-1, 1):
        tube(bmx, polyline([Vector((s * 0.11, 0.22, 0.20)), Vector((s * 0.20, 0.26, 0.34))], 0.03), 0.014, CHROME, n=10)
        lathe_axis(bmx, Vector((s * 0.20, 0.26, 0.34)), Vector((s * 0.32, 0.26, 0.345)), [(0.0001, 0.0), (0.020, 0.02), (0.022, 0.5), (0.020, 0.98), (0.0001, 1.0)], RUBBER, 14)
        tube(bmx, polyline([Vector((s * 0.15, 0.10, 0.30)), Vector((s * 0.22, 0.32, 0.38))], 0.03), 0.007, CHROME, n=8)
    # Kickstand folded up on the left.
    tube(bmx, polyline([Vector((-0.12, -0.10, 0.16)), Vector((-0.15, -0.38, 0.13))], 0.03), 0.013, FRAME, n=8)
    parts.append(to_object("trim", bmx))
    body = join(parts, "moto_cruiser_body")
    S.update({"axf": axf, "axr": axr, "rf": rf, "rr": rr, "head": head, "axis": axis,
              "wf_w": 0.130, "wr_w": 0.150,
              "seat": Vector((0, -0.34, 0.705)), "grip": Vector((0.37, 0.24, 1.075)),
              "peg": Vector((0.27, 0.26, 0.37)), "lean": -6.0, "lamp": Vector((0, 0.60, 0.93)),
              "tail": Vector((0, -1.215, 0.64)), "width": 0.95})
    return S, body, steer, wf, wr


# ---------------------------------------------------------------------------------------------------
# The scooter
# ---------------------------------------------------------------------------------------------------

def build_scooter():
    S = {"name": "scooter", "wb": 1.33, "rake": 27.0}
    rf, rr = 0.272, 0.258
    yf, yr = 0.665, -0.665
    axf = Vector((0, yf, rf))
    axr = Vector((0, yr, rr))
    head, axis = steer_frame((0, 0.47, 0.90), 27.0)
    bmf = bmesh.new()
    tyre(bmf, axf, rf, 0.110, 0.070)
    cast_rim(bmf, axf, 0.178, 0.075, spokes=5, split=False, mat=METAL, hub_r=0.045)
    disc(bmf, axf, -0.060, 0.130, 0.085, petal=True, holes=False)
    wf = to_object("moto_scooter_wheel_f", bmf)
    bmr = bmesh.new()
    tyre(bmr, axr, rr, 0.130, 0.080)
    cast_rim(bmr, axr, 0.165, 0.090, spokes=5, split=False, mat=METAL, hub_r=0.05)
    disc(bmr, axr, 0.060, 0.110, 0.072, petal=True, holes=False)
    wr = to_object("moto_scooter_wheel_r", bmr)

    bs = bmesh.new()
    fork_x = 0.085
    for s in (-1, 1):
        fork_legs(bs, Vector((s * fork_x, axf.y, axf.z)), head, axis, s * fork_x, 0.026, 0.019, METAL, METAL, usd=False, top_z=head.z - 0.30)
    triple_clamp(bs, head, axis, head.z - 0.30, fork_x, 0.026, 0.03, DARK)
    lathe_axis(bs, along_axis(head, axis, head.z - 0.30), along_axis(head, axis, head.z + 0.08), [(0.018, 0.0), (0.018, 1.0)], DARK, 12)
    tube(bs, [axf + Vector((-0.11, 0, 0)), axf + Vector((0.11, 0, 0))], 0.011, METAL, n=12)
    caliper(bs, axf, -0.060, 0.130, math.radians(150), (0.045, 0.09, 0.055), DARK)
    # The handlebar cover: a moulded shell over the bars carrying the headlamp and the dash, the
    # grips out of its ends.
    top = along_axis(head, axis, head.z + 0.10)
    secs = []
    for k in range(9):
        t = k / 8.0 * 2 - 1
        x = t * 0.25
        d = 0.15 - 0.06 * abs(t) ** 2
        h = 0.10 - 0.04 * abs(t) ** 2
        ring = []
        for j in range(14):
            a = math.tau * j / 14
            c, s_ = math.cos(a), math.sin(a)
            ring.append(Vector((x, top.y + 0.01 + math.copysign(abs(c) ** (2 / 3.0), c) * d * 0.5,
                                top.z + 0.01 + math.copysign(abs(s_) ** (2 / 3.0), s_) * h * 0.5 - 0.03 * t * t)))
        secs.append(ring)
    bmh = bmesh.new()
    loft(bmh, secs, PAINT)
    hcover = to_object("hcover", bmh)
    subsurf(hcover, 2)
    bs2 = bmesh.new()
    for s in (-1, 1):
        a = Vector((s * 0.24, top.y + 0.0, top.z - 0.012))
        b = Vector((s * 0.355, top.y - 0.02, top.z - 0.02))
        grip(bs2, a, b, 0.017)
        lever(bs2, a + Vector((0.0, 0.04, 0)), s, 0.15, METAL)
        mirror_on_stalk(bs2, a + Vector((-s * 0.02, 0.02, 0.03)), a + Vector((s * 0.07, 0.03, 0.21)), 0.11, 0.07, TRIM, CHROME)
    lamp_lens(bs2, Vector((0, top.y + 0.085, top.z + 0.01)), (0, 1, 0.1), 0.085, 0.030, 0.012, LIGHT_F)
    rbox(bs2, (0.18, 0.03, 0.08), Vector((0, top.y - 0.05, top.z + 0.05)), TRIM, bevel=0.01, rot=Matrix.Rotation(math.radians(-50), 3, Vector((1, 0, 0))))
    rbox(bs2, (0.14, 0.004, 0.055), Vector((0, top.y - 0.066, top.z + 0.058)), GLASS, bevel=0.0, rot=Matrix.Rotation(math.radians(-50), 3, Vector((1, 0, 0))))
    # Front fender riding on the fork.
    fsec = []
    for k in range(11):
        a = math.radians(10 + 140 * k / 10)
        rr_f = rf + 0.03
        cy = axf.y + rr_f * math.cos(a)
        cz = axf.z + rr_f * math.sin(a)
        n = Vector((0, math.cos(a), math.sin(a)))
        fsec.append([Vector((u * 0.07, cy, cz)) + n * (0.012 * (1 - u * u) - 0.03 * u ** 4) for u in (-1, -0.5, 0, 0.5, 1)])
    g = [[bs2.verts.new(p) for p in row] for row in fsec]
    for i in range(len(g) - 1):
        for j in range(4):
            face(bs2, (g[i][j], g[i][j + 1], g[i + 1][j + 1], g[i + 1][j]), PAINT)
    steer = join([to_object("moto_scooter_steer", bs), hcover, to_object("hparts", bs2)], "moto_scooter_steer")

    parts = []
    # The body: leg shield + floor + the shell under the seat, lofted along Y.
    def body_sec(y):
        # Front apron (y > 0.38): tall and thin; floor (-0.12 < y < 0.38): a low tunnel under the
        # floorboard; rear (y < -0.12): the full shell under the seat.
        if y > 0.40:
            t = (y - 0.40) / 0.30
            top = 0.98 - 0.25 * t ** 1.5
            bot = 0.42 + 0.25 * t
            w = 0.46 - 0.18 * t
            return sect(y, 0, (top + bot) * 0.5, w, top - bot, n=20, e=3.2, taper_top=0.25)
        if y > -0.12:
            t = (0.40 - y) / 0.52
            ramp_t = smooth((t - 0.75) * 4)
            top = 0.47 + 0.30 * ramp_t + 0.40 * smooth((0.25 - t) * 4)
            bot = 0.25
            w = 0.38 + 0.02 * ramp_t
            return sect(y, 0, (top + bot) * 0.5, w, top - bot, n=20, e=4.0, taper_top=0.1)
        t = (-0.12 - y) / 0.78
        top = 0.74 + 0.06 * t
        bot = 0.30 + 0.30 * t ** 1.6
        w = 0.40 - 0.14 * t ** 2
        return sect(y, 0, (top + bot) * 0.5, w, top - bot, n=20, e=3.4, taper_top=0.15)
    ys = [0.70, 0.62, 0.54, 0.46, 0.41, 0.36, 0.24, 0.10, -0.04, -0.12, -0.20, -0.32, -0.46, -0.60, -0.74, -0.86, -0.90]
    bmB = bmesh.new()
    loft(bmB, [body_sec(y) for y in ys], PAINT)
    shell = to_object("shell", bmB)
    subsurf(shell, 2)
    parts.append(shell)
    # Floorboard mats: rubber strips.
    bmm = bmesh.new()
    for k in range(8):
        rbox(bmm, (0.34, 0.025, 0.006), Vector((0, -0.10 + 0.058 * k, 0.474)), RUBBER, bevel=0.002, segs=1)
    rbox(bmm, (0.37, 0.48, 0.008), Vector((0, 0.10, 0.468)), TRIM, bevel=0.004, segs=1)
    parts.append(to_object("mats", bmm))
    # Seat: long, stepped for the passenger.
    secs = []
    for k in range(10):
        t = k / 9.0
        y = -0.12 - 0.74 * t
        z = 0.80 + 0.045 * smooth((t - 0.5) * 3)
        w = 0.30 - 0.06 * t ** 2
        secs.append(sect(y, 0, z - 0.04, w, 0.10, n=16, e=3.2))
    bms = bmesh.new()
    loft(bms, secs, SEAT)
    seat = to_object("seat", bms)
    subsurf(seat, 2)
    parts.append(seat)
    # The engine unit (left) as the swingarm: the belt case, the cylinder under the floor's back
    # end, the air box; the rear shock; the exhaust on the right.
    eng = bmesh.new()
    sweep(eng, polyline([Vector((-0.10, -0.16, 0.32)), Vector((-0.10, axr.y + 0.02, axr.z + 0.01))], 0.03),
          lambda i: rrect(0.07, 0.17 - 0.04 * i / 17.0, 0.035, 4), METAL)
    lathe(eng, [(0.0001, -0.136), (0.07, -0.136), (0.075, -0.142), (0.0001, -0.146)], 32, Vector((0, axr.y, axr.z)), 'X', METAL)
    rbox(eng, (0.18, 0.18, 0.14), Vector((0.0, -0.18, 0.27)), DARK, bevel=0.03, segs=2)
    finned_barrel(eng, Vector((0.0, -0.06, 0.26)), (0, 1, 0.25), 0.045, 0.12, 6, 0.018, DARK, DARK)
    rbox(eng, (0.12, 0.22, 0.12), Vector((-0.10, -0.40, 0.48)), TRIM, bevel=0.03, segs=2)
    lathe_axis(eng, Vector((-0.10, -0.60, 0.33)), Vector((-0.11, -0.66, 0.60)), [(0.02, 0.0), (0.02, 0.3), (0.015, 0.35), (0.015, 1.0)], DARK, 12)
    lathe_axis(eng, Vector((0.10, -0.60, 0.33)), Vector((0.11, -0.66, 0.60)), [(0.02, 0.0), (0.02, 0.3), (0.015, 0.35), (0.015, 1.0)], DARK, 12)
    hp = []
    for k in range(73):
        t = k / 72.0
        a0 = Vector((-0.10, -0.60, 0.33))
        a1 = Vector((-0.11, -0.66, 0.60))
        ax = (a1 - a0).normalized()
        e1 = Vector((1, 0, 0)).cross(ax).normalized()
        e2 = ax.cross(e1)
        ang = t * math.tau * 6
        hp.append(a0 + (a1 - a0) * (0.15 + 0.7 * t) + e1 * 0.026 * math.cos(ang) + e2 * 0.026 * math.sin(ang))
    tube(eng, hp, 0.0045, PAINT, n=6)
    tube(eng, bez(Vector((0.03, 0.00, 0.22)), Vector((0.10, -0.05, 0.16)), Vector((0.14, -0.30, 0.22)), Vector((0.14, -0.44, 0.30)), 12), 0.018, METAL, n=12)
    mf0 = Vector((0.14, -0.44, 0.30))
    mf1 = Vector((0.15, -0.86, 0.40))
    sweep(eng, polyline([mf0, mf1], 0.04), lambda i: rrect(0.09, 0.11, 0.04, 3), DARK)
    sweep(eng, polyline([mf0 + Vector((0.048, 0.03, 0.01)), mf1 + Vector((0.048, 0.08, 0.0))], 0.04), [(-0.002, -0.04), (0.002, -0.04), (0.002, 0.04), (-0.002, 0.04)], METAL)
    lathe_axis(eng, mf1, mf1 + (mf1 - mf0).normalized() * 0.03, [(0.018, 0.0), (0.018, 1.0)], CHROME, 12)
    tube(eng, [axr + Vector((-0.15, 0, 0)), axr + Vector((0.11, 0, 0))], 0.011, METAL, n=12)
    caliper(eng, axr, 0.060, 0.110, math.radians(-110), (0.04, 0.08, 0.05), DARK)
    # Rear hugger, taillight in the tail, indicators, grab rail, the centre stand folded.
    secs = []
    for k in range(9):
        a = math.radians(30 + 110 * k / 8)
        rr_f = rr + 0.04
        cy = axr.y - rr_f * math.cos(a)
        cz = axr.z + rr_f * math.sin(a)
        n = Vector((0, -math.cos(a), math.sin(a)))
        secs.append([Vector((u * 0.07, cy, cz)) + n * (0.01 * (1 - u * u)) for u in (-1, -0.5, 0, 0.5, 1)])
    g = [[eng.verts.new(p) for p in row] for row in secs]
    for i in range(len(g) - 1):
        for j in range(4):
            face(eng, (g[i][j], g[i][j + 1], g[i + 1][j + 1], g[i + 1][j]), TRIM)
    parts.append(to_object("engine", eng, sharp_deg=35))
    bmx = bmesh.new()
    lamp_lens(bmx, Vector((0, -0.905, 0.68)), (0, -1, 0.2), 0.10, 0.030, 0.012, LIGHT_R)
    for s in (-1, 1):
        lamp_lens(bmx, Vector((s * 0.15, -0.86, 0.66)), (s * 0.5, -1, 0), 0.030, 0.015, 0.008, AMBER, segs=12)
        lamp_lens(bmx, Vector((s * 0.205, 0.64, 0.88)), (s * 0.5, 1, 0), 0.035, 0.016, 0.008, AMBER, segs=12)
    tube(bmx, bez(Vector((-0.14, -0.70, 0.82)), Vector((-0.15, -0.93, 0.84)), Vector((0.15, -0.93, 0.84)), Vector((0.14, -0.70, 0.82)), 16), 0.012, METAL, n=10)
    tube(bmx, polyline([Vector((-0.12, -0.20, 0.25)), Vector((-0.12, -0.42, 0.20))], 0.04), 0.012, DARK, n=8)
    tube(bmx, polyline([Vector((0.12, -0.20, 0.25)), Vector((0.12, -0.42, 0.20))], 0.04), 0.012, DARK, n=8)
    # The front grille under the leg shield's nose.
    for k in range(4):
        rbox(bmx, (0.10, 0.012, 0.008), Vector((0, 0.71 - 0.003 * k, 0.60 + 0.025 * k)), TRIM, bevel=0.002, segs=1)
    parts.append(to_object("trim", bmx))
    body = join(parts, "moto_scooter_body")
    S.update({"axf": axf, "axr": axr, "rf": rf, "rr": rr, "head": head, "axis": axis,
              "wf_w": 0.110, "wr_w": 0.130,
              "seat": Vector((0, -0.34, 0.81)), "grip": Vector((0.32, top.y - 0.012, top.z - 0.016)),
              "peg": Vector((0.10, 0.20, 0.48)), "lean": 4.0, "lamp": Vector((0, top.y + 0.09, top.z + 0.01)),
              "tail": Vector((0, -0.91, 0.68)), "width": 0.72})
    return S, body, steer, wf, wr


BUILDERS = {"sport": build_sport, "cruiser": build_cruiser, "scooter": build_scooter}


# --- report, previews, main --------------------------------------------------------------------

def gd(v):
    """A file-frame point as Godot body space (x, z up, -y)."""
    return "Vector3(%.3f, %.3f, %.3f)" % (v.x, v.z, -v.y)


def report(S, body, steer, wf, wr, far):
    allv = []
    for ob in (body, steer, wf, wr):
        mw = ob.matrix_world
        allv += [mw @ v.co for v in ob.data.vertices]
    ys = [v.y for v in allv]
    xs = [v.x for v in allv]
    zs = [v.z for v in allv]
    print("== %s: body %d, steer %d, wheels %d + %d, far %d triangles" % (
        S["name"], tris(body), tris(steer), tris(wf), tris(wr), tris(far)))
    print("   length %.3f width %.3f height %.3f  y %.3f..%.3f" % (max(ys) - min(ys), max(xs) - min(xs), max(zs), min(ys), max(ys)))
    ax = S["axis"]
    print('   DIMS row: {"length": %.3f, "width": %.3f, "height": %.3f, "front": %s, "rear": %s, "rf": %.3f, "rr": %.3f,'
          % (max(ys) - min(ys), max(xs) - min(xs), max(zs), gd(S["axf"]), gd(S["axr"]), S["rf"], S["rr"]))
    print('      "head": %s, "rake": %.1f, "axis": Vector3(%.4f, %.4f, %.4f), "seat": %s, "grip": %s, "peg": %s, "lean": %.1f,'
          % (gd(S["head"]), S["rake"], ax.x, ax.z, -ax.y, gd(S["seat"]), gd(S["grip"]), gd(S["peg"]), S["lean"]))
    print('      "lamp": %s, "tail": %s, "tyre_w": Vector2(%.3f, %.3f)}' % (gd(S["lamp"]), gd(S["tail"]), S["wf_w"], S["wr_w"]))


def render(S, objs, views=None):
    import make_road_cars as rc
    os.makedirs(RENDER_DIR, exist_ok=True)
    rc.RENDER_DIR = RENDER_DIR
    ob = join([o.copy() if False else o for o in objs])
    for m in ob.data.materials:
        if m.name == "paint":
            b = m.node_tree.nodes.get("Principled BSDF")
            b.inputs["Base Color"].default_value = {"sport": (0.55, 0.03, 0.03), "cruiser": (0.02, 0.03, 0.06), "scooter": (0.55, 0.55, 0.50)}[S["name"]] + (1.0,)
            b.inputs["Metallic"].default_value = 0.3
            b.inputs["Roughness"].default_value = 0.3
            if "Coat Weight" in b.inputs:
                b.inputs["Coat Weight"].default_value = 1.0
                b.inputs["Coat Roughness"].default_value = 0.03
    v = views or [
        ("side", (3.6, 0.0, 0.75), (0.0, 0.0, 0.55), 50),
        ("front3", (2.0, 2.4, 1.2), (0.0, 0.0, 0.55), 45),
        ("rear3", (-1.9, -2.5, 1.35), (0.0, -0.1, 0.55), 45),
        ("left", (-3.6, 0.2, 0.8), (0.0, 0.0, 0.55), 50),
    ]
    rc.preview_materials = lambda o, p: None
    rc.render_previews(ob, "moto_" + S["name"], v, samples=int(os.environ.get("SAMPLES", "20")), res=(960, 640))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = [a for a in argv if not a.startswith("--")] or ["sport", "cruiser", "scooter"]
    for name in names:
        reset_scene()
        S, body, steer, wf, wr = BUILDERS[name]()
        set_origin(steer, S["head"])
        set_origin(wf, S["axf"])
        set_origin(wr, S["axr"])
        far = build_far([body, steer, wf, wr], "moto_" + name, 3500)
        report(S, body, steer, wf, wr, far)
        if "--noexport" not in argv:
            os.makedirs(OUT_DIR, exist_ok=True)
            path = os.path.join(OUT_DIR, "moto_%s.glb" % name)
            export([body, steer, wf, wr, far], path)
            print("wrote", path)
        bpy.data.objects.remove(far, do_unlink=True)
        if "--render" in argv:
            render(S, [body, steer, wf, wr])


if __name__ == "__main__":
    sys.path.insert(0, HERE)
    main()
