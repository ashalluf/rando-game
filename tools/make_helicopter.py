#!/usr/bin/env python3
"""Light utility helicopter for the air traffic (police and news liveries), built in Blender.

    blender -b --factory-startup --python tools/make_helicopter.py
    blender -b --factory-startup --python tools/make_helicopter.py -- --render out.png
    blender -b --factory-startup --python tools/make_helicopter.py -- --no-verify

Writes assets/models/helicopter.glb. Run `godot --headless --path . --import` after it, before
any render: Godot serves a cached import of a .glb (CLAUDE.md, measurement traps).

WHAT IT IS
----------
An original single-engine light helicopter in the 10 m class - the shape every city police and
news operator flies (a rounded five-seat cabin with a big wraparound canopy and chin windows,
a turbine under a cowling behind the mast, a slim boom, a swept fin with the tail rotor on its
left, a stabiliser with end plates, tubular skids). A CLASS study, not a copy of any type: no
maker's intakes, fairings or proportions were measured.

HOW IT IS BUILT
---------------
The cabin is one structured quad loft: stations along the length, each a section that is a
round-topped, flat-bottomed superellipse, with the ring vertices placed at fixed parameters
round the section. Because the grid is structured, every livery line is a ring index and every
window is a (station, ring) rectangle, so the stripe runs exactly along the body and the glass
edges are straight grid lines. Glass regions are inset and set back 1 cm, and the ring the inset
leaves is the black window rubber: real geometry, not paint. Parts that have hard edges in
life - cowling, fins, stabiliser, hub, searchlight - carry a bevel so they catch a highlight.
Skids and cross tubes are bevelled curves. Everything is smooth shaded with sharp edges only
where two faces meet at a real angle.

CONTRACT WITH THE GAME (scripts/vehicles/helicopter.gd)
------------------------------------------------------
Authored X = right, Y = forward (nose at +Y), Z = up, skid bottoms at Z = 0; glTF's Y-up turns
that into Godot's X right, Y up, nose at -Z. Nodes:
  Body                     fuselage, boom, fins, skids, cowling, details
  MainRotor (empty)        at the hub; spins about its local Y in Godot (Blender Z)
    MainRotorHub           mast top, hub, grips - always drawn
    MainRotorBlades        the four blades - hidden at speed, when the game draws a rotor disc
  TailRotor (empty)        at the tail rotor hub; spins about local X
    TailRotorHub, TailRotorBlades
  Searchlight              police only; origin at its gimbal, lens facing +Y (Godot -Z), so a
                           look_at() in Godot aims it
  CameraBall               news only; same convention
  LiveryPolice, LiveryNews lettering; the game shows one
Material slots, bound BY NAME: paint (upper body), paint2 (lower body), stripe, glass, trim,
metal, blade, lens, nav_red, nav_green, decal_police, decal_news. The game re-colours paint,
paint2, stripe and the decals per livery; the colours below are the police defaults.
Main rotor radius 5.35 m, tail rotor 0.78 m (MAIN_R, TAIL_R) - helicopter.gd sizes its rotor
discs from the node bounds, not from these numbers.

Names on it are original: "POLICE" is a word, not a department, and "RANDO 5" is an invented
station.
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "assets", "models", "helicopter.glb")

MAIN_R = 5.35
TAIL_R = 0.78
HUB = Vector((0.0, 0.22, 2.96))
TAIL_HUB = Vector((-0.235, -7.26, 2.36))

# name, linear base colour, metallic, roughness
SLOTS = [
    ("paint", (0.012, 0.028, 0.095), 0.35, 0.32),
    ("paint2", (0.80, 0.81, 0.82), 0.25, 0.34),
    ("stripe", (0.10, 0.34, 0.80), 0.30, 0.34),
    ("glass", (0.006, 0.008, 0.010), 0.0, 0.04),
    ("trim", (0.018, 0.018, 0.020), 0.1, 0.55),
    ("metal", (0.45, 0.45, 0.46), 1.0, 0.32),
    ("blade", (0.022, 0.022, 0.025), 0.2, 0.42),
    ("lens", (0.85, 0.90, 0.95), 0.0, 0.06),
    ("nav_red", (0.80, 0.03, 0.02), 0.0, 0.15),
    ("nav_green", (0.02, 0.70, 0.15), 0.0, 0.15),
    ("decal_police", (0.86, 0.87, 0.88), 0.0, 0.45),
    ("decal_news", (0.00, 0.13, 0.16), 0.0, 0.45),
]
MI = {s[0]: i for i, s in enumerate(SLOTS)}

# Cabin loft: (y, half width, bottom z, top z). Nose first.
STATIONS = [
    (3.20, 0.30, 0.93, 1.30),
    (3.06, 0.50, 0.79, 1.48),
    (2.86, 0.645, 0.67, 1.67),
    (2.60, 0.745, 0.585, 1.835),
    (2.30, 0.805, 0.535, 1.955),
    (1.95, 0.845, 0.512, 2.025),
    (1.60, 0.862, 0.502, 2.052),
    (1.45, 0.866, 0.500, 2.060),
    (1.00, 0.870, 0.500, 2.068),
    (0.35, 0.870, 0.500, 2.070),
    (0.20, 0.870, 0.501, 2.070),
    (-0.20, 0.862, 0.508, 2.064),
    (-0.70, 0.832, 0.535, 2.046),
    (-1.10, 0.762, 0.612, 2.008),
    (-1.50, 0.625, 0.775, 1.966),
    (-1.90, 0.445, 1.015, 1.925),
    (-2.25, 0.305, 1.275, 1.886),
    (-2.50, 0.245, 1.395, 1.862),
]
NOSE_TIP = (3.32, 1.11)
# Ring parameters for the right half, bottom centre (0) to top centre (0.5). The livery lines
# and window sills are exact entries so they fall on grid lines.
U_RIGHT = [0.0, 0.035, 0.075, 0.115, 0.155, 0.19, 0.212, 0.232, 0.25, 0.29, 0.33, 0.37, 0.415,
           0.46, 0.5]
U_STRIPE_LO, U_STRIPE_HI = 0.212, 0.232
U_SILL, U_HEAD = 0.25, 0.33

# Tail boom: (y, half width, half height, centre z).
BOOM = [
    (-2.10, 0.255, 0.275, 1.640),
    (-3.00, 0.232, 0.250, 1.665),
    (-4.00, 0.205, 0.222, 1.692),
    (-5.00, 0.180, 0.196, 1.720),
    (-6.00, 0.155, 0.170, 1.748),
    (-6.80, 0.137, 0.150, 1.770),
    (-7.40, 0.122, 0.135, 1.786),
]


# =============================================================================================
# Scene helpers
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


def activate(ob):
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def apply_modifiers(ob):
    activate(ob)
    for mod in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)


def bevel(ob, width, segments=2, angle=35.0):
    mod = ob.modifiers.new("bev", 'BEVEL')
    mod.width = width
    mod.segments = segments
    mod.limit_method = 'ANGLE'
    mod.angle_limit = math.radians(angle)
    mod.miter_outer = 'MITER_ARC'
    mod.harden_normals = False
    apply_modifiers(ob)


def shade(ob, sharp_deg=48.0):
    """Smooth everywhere; sharp only where two faces really do meet at an angle."""
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


def join(parts, name):
    bpy.ops.object.select_all(action='DESELECT')
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    ob = parts[0]
    ob.name = name
    ob.data.name = name
    return ob


def curve_to_mesh(ob):
    activate(ob)
    bpy.ops.object.convert(target='MESH')
    return bpy.context.view_layer.objects.active


def set_material(ob, slot):
    for poly in ob.data.polygons:
        poly.material_index = MI[slot]


# =============================================================================================
# Primitive builders (bmesh, in the caller's frame)
# =============================================================================================
def bm_box(bm, centre, size, mat, rot=None):
    res = bmesh.ops.create_cube(bm, size=1.0)
    m = Matrix.Diagonal((size[0], size[1], size[2], 1.0))
    if rot is not None:
        m = rot.to_4x4() @ m
    m = Matrix.Translation(centre) @ m
    bmesh.ops.transform(bm, matrix=m, verts=res["verts"])
    for f in {f for v in res["verts"] for f in v.link_faces}:
        f.material_index = MI[mat]
    return res["verts"]


def bm_cyl(bm, a, b, r1, r2, mat, segs=16, caps=True):
    """A (possibly tapered) cylinder from point a to point b."""
    axis = (b - a)
    length = axis.length
    res = bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=segs,
                                radius1=r1, radius2=r2, depth=length)
    # create_cone runs along local Z, centred on the origin. rotation_difference, not
    # to_track_quat: tracking Z with Y as the up axis is degenerate for a cylinder along Y.
    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(axis.normalized()).to_matrix().to_4x4()
    m = Matrix.Translation((a + b) * 0.5) @ rot
    bmesh.ops.transform(bm, matrix=m, verts=res["verts"])
    for f in {f for v in res["verts"] for f in v.link_faces}:
        f.material_index = MI[mat]
    return res["verts"]


def bm_sphere(bm, centre, radius, mat, u=16, v=10, scale=(1.0, 1.0, 1.0)):
    res = bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=radius)
    m = Matrix.Translation(centre) @ Matrix.Diagonal((scale[0], scale[1], scale[2], 1.0))
    bmesh.ops.transform(bm, matrix=m, verts=res["verts"])
    for f in {f for vv in res["verts"] for f in vv.link_faces}:
        f.material_index = MI[mat]
    return res["verts"]


def bm_loft(bm, rings, mat_fn, close_start=None, close_end=None):
    """Quads between consecutive closed rings (lists of Vector). mat_fn(i, j) -> slot name for
    the quad between ring i and i+1, ring positions j and j+1. close_start / close_end: None,
    'cap' (one n-gon) or a Vector (a pole)."""
    vrings = [[bm.verts.new(p) for p in ring] for ring in rings]
    n = len(rings[0])
    faces = []
    for i in range(len(vrings) - 1):
        a, b = vrings[i], vrings[i + 1]
        for j in range(n):
            k = (j + 1) % n
            f = bm.faces.new((a[j], b[j], b[k], a[k]))
            f.material_index = MI[mat_fn(i, j)]
            faces.append(f)
    for which, spec in ((0, close_start), (len(vrings) - 1, close_end)):
        if spec is None:
            continue
        ring = vrings[which]
        if isinstance(spec, Vector):
            pole = bm.verts.new(spec)
            for j in range(n):
                k = (j + 1) % n
                tri = (pole, ring[k], ring[j]) if which == 0 else (pole, ring[j], ring[k])
                f = bm.faces.new(tri)
                f.material_index = MI[mat_fn(0 if which == 0 else len(vrings) - 2, j)]
                faces.append(f)
        else:
            f = bm.faces.new(list(reversed(ring)) if which == 0 else ring)
            f.material_index = MI["paint"]
            faces.append(f)
    return faces


# =============================================================================================
# The cabin
# =============================================================================================
def ring_u():
    return U_RIGHT + [1.0 - u for u in reversed(U_RIGHT[1:-1])]


def section_point(u, w, zb, zt, n_side=2.7, n_top=2.15, n_bot=3.4):
    phi = 2.0 * math.pi * u - 0.5 * math.pi
    c, s = math.cos(phi), math.sin(phi)
    n_v = n_top if s > 0.0 else n_bot
    x = w * math.copysign(abs(c) ** (2.0 / n_side), c)
    zc = 0.5 * (zt + zb)
    h = 0.5 * (zt - zb)
    z = zc + h * math.copysign(abs(s) ** (2.0 / n_v), s)
    return x, z


def cabin_material(i, j):
    us = ring_u()
    n = len(us)
    ya, yb = STATIONS[i][0], STATIONS[i + 1][0]
    ym = 0.5 * (ya + yb)
    u0, u1 = us[j], (us[(j + 1) % n] if j + 1 < n else 1.0)
    um = 0.5 * (u0 + u1)
    um = min(um, 1.0 - um)
    if 1.60 <= ym <= 3.06 and U_STRIPE_HI < um < 0.43 and not (ym < 1.95 and um > 0.415):
        return "glass"
    if 2.30 <= ym <= 2.86 and 0.035 < um < 0.19:
        return "glass"
    if U_SILL < um < U_HEAD and (0.35 < ym < 1.45 or -0.70 < ym < 0.20):
        return "glass"
    if um < U_STRIPE_LO:
        return "paint2"
    if um < U_STRIPE_HI:
        return "stripe"
    return "paint"


def build_cabin(mats):
    bm = bmesh.new()
    rings = []
    for (y, w, zb, zt) in STATIONS:
        ring = []
        for u in ring_u():
            x, z = section_point(u, w, zb, zt)
            ring.append(Vector((x, y, z)))
        rings.append(ring)
    faces = bm_loft(bm, rings, cabin_material, close_start=Vector((0.0, NOSE_TIP[0], NOSE_TIP[1])),
                    close_end='cap')
    bm.normal_update()
    # Orient everything outward: the loft winding depends on the ring direction.
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    # Real window reveals: inset each glass region, set the glass back, rubber round it.
    glass = [f for f in bm.faces if f.material_index == MI["glass"]]
    res = bmesh.ops.inset_region(bm, faces=glass, thickness=0.026, depth=-0.012,
                                 use_even_offset=True, use_boundary=True)
    for f in res["faces"]:
        f.material_index = MI["trim"]
    return new_object("cabin", bm, mats)


def build_boom(mats):
    bm = bmesh.new()
    rings = []
    segs = 18
    for (y, w, h, zc) in BOOM:
        ring = []
        for k in range(segs):
            phi = 2.0 * math.pi * k / segs - 0.5 * math.pi
            c, s = math.cos(phi), math.sin(phi)
            x = w * math.copysign(abs(c) ** (2.0 / 2.5), c)
            z = zc + h * math.copysign(abs(s) ** (2.0 / 2.3), s)
            ring.append(Vector((x, y, z)))
        rings.append(ring)

    def mat(i, j):
        # The underside of the boom takes the lower-body colour, like the cabin below its stripe.
        phi = 2.0 * math.pi * (j + 0.5) / segs - 0.5 * math.pi
        return "paint2" if math.sin(phi) < -0.55 else "paint"

    # Capped at both ends (the front cap is hidden inside the cabin) so the mesh is closed and
    # recalc_face_normals can tell outside from inside.
    bm_loft(bm, rings, mat, close_start='cap', close_end='cap')
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return new_object("boom", bm, mats)


def build_cowling(mats):
    bm = bmesh.new()
    verts = bm_box(bm, Vector((0.0, -0.45, 2.21)), (0.92, 2.8, 0.52), "paint")
    # Taper the tail end in plan and in height, like a real engine fairing.
    for v in verts:
        t = max(0.0, min(1.0, (-v.co.y - 0.9) / 0.95))
        v.co.x *= 1.0 - 0.42 * t
        if v.co.z > 2.2:
            v.co.z -= 0.16 * t
        # The front slopes back into the mast fairing.
        if v.co.y > 0.8 and v.co.z > 2.2:
            v.co.y -= 0.22
    ob = new_object("cowling", bm, mats)
    bevel(ob, 0.11, segments=2, angle=30.0)
    return ob


def build_details(mats):
    bm = bmesh.new()
    # Engine intake grilles either side of the cowling, and the two exhaust stacks.
    for sx in (-1.0, 1.0):
        bm_box(bm, Vector((sx * 0.462, 0.05, 2.23)), (0.025, 0.62, 0.20), "trim")
        bm_box(bm, Vector((sx * 0.35, -1.20, 2.30)), (0.02, 0.44, 0.13), "trim")
        a = Vector((sx * 0.17, -1.62, 2.30))
        b = Vector((sx * 0.21, -1.98, 2.46))
        bm_cyl(bm, a, b, 0.085, 0.095, "metal", segs=14)
        bm_cyl(bm, b - (b - a).normalized() * 0.02, b + (b - a).normalized() * 0.01, 0.068,
               0.068, "trim", segs=14)
    # Mast fairing, the collar the rotor mast rises from.
    bm_cyl(bm, Vector((0.0, HUB.y, 2.35)), Vector((0.0, HUB.y, 2.62)), 0.26, 0.16, "paint", segs=18)
    # Belly antennas and the boom-top antenna.
    bm_box(bm, Vector((0.0, 0.35, 0.47)), (0.012, 0.16, 0.10), "trim",
           Matrix.Rotation(math.radians(-18.0), 3, 'X'))
    bm_box(bm, Vector((0.0, -4.4, 1.94)), (0.012, 0.18, 0.12), "trim",
           Matrix.Rotation(math.radians(20.0), 3, 'X'))
    # Pitot tube under the nose, door handles, the step on each side.
    bm_cyl(bm, Vector((0.26, 3.05, 1.05)), Vector((0.30, 3.40, 1.03)), 0.012, 0.009, "metal", segs=8)
    for sx in (-1.0, 1.0):
        bm_box(bm, Vector((sx * 0.878, 0.62, 1.22)), (0.02, 0.14, 0.025), "metal")
        bm_box(bm, Vector((sx * 0.878, -0.10, 1.22)), (0.02, 0.14, 0.025), "metal")
    ob = new_object("details", bm, mats)
    return ob


def build_fins(mats):
    bm = bmesh.new()
    # Vertical fin and ventral fin: one swept profile, extruded.
    prof = [(-6.36, 1.90), (-7.02, 3.02), (-7.42, 3.10), (-7.56, 2.96), (-7.44, 2.20),
            (-7.40, 1.62), (-7.44, 1.08), (-7.27, 1.05), (-6.96, 1.58), (-6.70, 1.74)]
    th = 0.045
    right = [bm.verts.new((th, y, z)) for (y, z) in prof]
    left = [bm.verts.new((-th, y, z)) for (y, z) in prof]
    n = len(prof)
    f = bm.faces.new(right)
    f.material_index = MI["paint"]
    f = bm.faces.new(list(reversed(left)))
    f.material_index = MI["paint"]
    for k in range(n):
        q = (k + 1) % n
        f = bm.faces.new((right[k], left[k], left[q], right[q]))
        f.material_index = MI["paint"]
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    fin = new_object("fin", bm, mats)
    bevel(fin, 0.022, segments=2, angle=30.0)
    # Horizontal stabiliser with end plates, and the nav light nubs on the plates.
    bm = bmesh.new()
    bm_box(bm, Vector((0.0, -5.88, 1.76)), (2.34, 0.46, 0.07), "paint")
    for sx in (-1.0, 1.0):
        bm_box(bm, Vector((sx * 1.19, -5.92, 1.80)), (0.05, 0.40, 0.36), "paint",
               Matrix.Rotation(math.radians(-8.0), 3, 'X'))
    stab = new_object("stab", bm, mats)
    bevel(stab, 0.018, segments=2, angle=30.0)
    bm = bmesh.new()
    bm_sphere(bm, Vector((-1.225, -5.70, 1.80)), 0.035, "nav_red", u=10, v=6)
    bm_sphere(bm, Vector((1.225, -5.70, 1.80)), 0.035, "nav_green", u=10, v=6)
    # The tail rotor gearbox fairing on the fin's left, which the rotor hub comes out of.
    bm_cyl(bm, Vector((-0.02, TAIL_HUB.y, TAIL_HUB.z)), Vector((TAIL_HUB.x + 0.07, TAIL_HUB.y,
           TAIL_HUB.z)), 0.10, 0.07, "paint", segs=14)
    nubs = new_object("nubs", bm, mats)
    return [fin, stab, nubs]


def tube(name, points, radius, mats, slot):
    cu = bpy.data.curves.new(name, 'CURVE')
    cu.dimensions = '3D'
    cu.bevel_depth = radius
    cu.bevel_resolution = 1
    cu.resolution_u = 3
    cu.use_fill_caps = True
    sp = cu.splines.new('BEZIER')
    sp.bezier_points.add(len(points) - 1)
    for bp, p in zip(sp.bezier_points, points):
        bp.co = p
        bp.handle_left_type = 'AUTO'
        bp.handle_right_type = 'AUTO'
    ob = bpy.data.objects.new(name, cu)
    bpy.context.scene.collection.objects.link(ob)
    ob = curve_to_mesh(ob)
    for m in mats:
        ob.data.materials.append(m)
    set_material(ob, slot)
    return ob


def build_skids(mats):
    parts = []
    for sx in (-1.0, 1.0):
        x = sx * 1.06
        parts.append(tube("skid", [Vector((x, -2.02, 0.085)), Vector((x, -1.80, 0.045)),
                                    Vector((x, 1.90, 0.045)), Vector((x, 2.30, 0.085)),
                                    Vector((x * 0.99, 2.52, 0.22)), Vector((x * 0.98, 2.60, 0.38))],
                          0.042, mats, "trim"))
        for y in (1.28, -0.98):
            parts.append(tube("cross", [Vector((x, y, 0.05)), Vector((x * 0.97, y, 0.30)),
                                         Vector((x * 0.80, y, 0.50)), Vector((x * 0.46, y, 0.57))],
                              0.046, mats, "trim"))
        # A step on the forward cross tube.
    bm = bmesh.new()
    for sx in (-1.0, 1.0):
        bm_box(bm, Vector((sx * 0.98, 1.28, 0.33)), (0.20, 0.30, 0.025), "metal",
               Matrix.Rotation(math.radians(sx * -12.0), 3, 'Y'))
    parts.append(new_object("steps", bm, mats))
    return parts


# =============================================================================================
# Rotors
# =============================================================================================
def blade_section(chord, thick):
    """Leading edge at +Y: a lens with a round nose and a sharp trailing edge."""
    return [(0.50 * chord, 0.00), (0.34 * chord, 0.50 * thick), (-0.05 * chord, 0.46 * thick),
            (-0.50 * chord, 0.03 * thick), (-0.05 * chord, -0.30 * thick),
            (0.34 * chord, -0.36 * thick)]


def build_blade(bm, angle, r_root, r_tip, chord_root, chord, chord_tip, thick, twist_root, coning,
                slot, sweep_tip=0.10, axis='Z'):
    """One blade along +X (then turned by `angle` about the rotor axis), in rotor-local space."""
    spans = [(r_root, chord_root, thick * 1.3, twist_root),
             (r_root + 0.35 * (r_tip - r_root) * 0.3, chord, thick, twist_root * 0.8),
             (r_tip - 0.35, chord, thick * 0.85, twist_root * 0.15),
             (r_tip, chord_tip, thick * 0.6, 0.0)]
    rings = []
    for (r, c, t, tw) in spans:
        sec = blade_section(c, t)
        ring = []
        tipback = sweep_tip * c if r >= r_tip - 1e-6 else 0.0
        for (cy, cz) in sec:
            # twist about the span axis
            ca, sa = math.cos(math.radians(tw)), math.sin(math.radians(tw))
            yy = cy * ca - cz * sa - tipback
            zz = cy * sa + cz * ca + r * math.sin(math.radians(coning))
            ring.append(Vector((r, yy, zz)))
        rings.append(ring)
    vr = [[bm.verts.new(p) for p in ring] for ring in rings]
    n = len(vr[0])
    new_faces = []
    for i in range(len(vr) - 1):
        for j in range(n):
            k = (j + 1) % n
            new_faces.append(bm.faces.new((vr[i][j], vr[i][k], vr[i + 1][k], vr[i + 1][j])))
    new_faces.append(bm.faces.new(list(reversed(vr[0]))))
    new_faces.append(bm.faces.new(vr[-1]))
    for f in new_faces:
        f.material_index = MI[slot]
    verts = [v for ring in vr for v in ring]
    if axis == 'Z':
        rot = Matrix.Rotation(angle, 4, 'Z')
    else:
        # Tail rotor: blades in the Y-Z plane, spinning about X. Built along +X with the chord
        # on Y, so first turn the span onto Z, then spin about X.
        rot = Matrix.Rotation(angle, 4, 'X') @ Matrix.Rotation(math.radians(-90.0), 4, 'Y')
    bmesh.ops.transform(bm, matrix=rot, verts=verts)
    return new_faces


def build_main_rotor(mats):
    hub_bm = bmesh.new()
    # Mast (runs down into the fairing), swashplate, hub, four blade grips.
    bm_cyl(hub_bm, Vector((0.0, 0.0, -0.62)), Vector((0.0, 0.0, 0.02)), 0.085, 0.085, "metal", segs=14)
    bm_cyl(hub_bm, Vector((0.0, 0.0, -0.40)), Vector((0.0, 0.0, -0.33)), 0.22, 0.22, "metal", segs=14)
    bm_cyl(hub_bm, Vector((0.0, 0.0, -0.06)), Vector((0.0, 0.0, 0.07)), 0.27, 0.24, "trim", segs=14)
    bm_cyl(hub_bm, Vector((0.0, 0.0, 0.07)), Vector((0.0, 0.0, 0.16)), 0.10, 0.06, "metal", segs=12)
    for k in range(4):
        a = k * 0.5 * math.pi
        d = Vector((math.cos(a), math.sin(a), 0.0))
        bm_box(hub_bm, d * 0.42, (0.36, 0.13, 0.085), "trim", Matrix.Rotation(a, 3, 'Z'))
        # Pitch link from the swashplate up to the grip's horn.
        side = Vector((-math.sin(a), math.cos(a), 0.0))
        bm_cyl(hub_bm, d * 0.20 + side * 0.10 + Vector((0.0, 0.0, -0.33)),
               d * 0.28 + side * 0.10 + Vector((0.0, 0.0, -0.03)), 0.014, 0.014, "metal", segs=6)
    hub = new_object("MainRotorHub", hub_bm, mats)
    bl_bm = bmesh.new()
    for k in range(4):
        build_blade(bl_bm, k * 0.5 * math.pi, 0.58, MAIN_R, 0.20, 0.30, 0.22, 0.042, 9.0, 2.2, "blade")
    blades = new_object("MainRotorBlades", bl_bm, mats)
    return hub, blades


def build_tail_rotor(mats):
    hub_bm = bmesh.new()
    bm_cyl(hub_bm, Vector((0.05, 0.0, 0.0)), Vector((-0.10, 0.0, 0.0)), 0.055, 0.045, "metal", segs=12)
    bm_cyl(hub_bm, Vector((-0.06, 0.0, 0.0)), Vector((-0.10, 0.0, 0.0)), 0.075, 0.075, "trim", segs=12)
    hub = new_object("TailRotorHub", hub_bm, mats)
    bl_bm = bmesh.new()
    for k in range(2):
        faces = build_blade(bl_bm, k * math.pi, 0.08, TAIL_R, 0.09, 0.13, 0.11, 0.022, 6.0, 0.0, "blade",
                            axis='X')
        # Shift the blades out to the hub's outboard face.
        verts = {v for f in faces for v in f.verts}
        bmesh.ops.translate(bl_bm, vec=Vector((-0.08, 0.0, 0.0)), verts=list(verts))
    blades = new_object("TailRotorBlades", bl_bm, mats)
    return hub, blades


# =============================================================================================
# Mission equipment
# =============================================================================================
def build_searchlight(mats):
    """A gimballed searchlight under the nose, lens facing +Y. Origin at the gimbal."""
    bm = bmesh.new()
    # Fork down from the mount, housing between its arms, lens, cooling rings at the back.
    bm_cyl(bm, Vector((0.0, 0.0, 0.10)), Vector((0.0, 0.0, -0.02)), 0.05, 0.05, "trim", segs=10)
    for sx in (-1.0, 1.0):
        bm_box(bm, Vector((sx * 0.19, 0.0, -0.08)), (0.03, 0.10, 0.18), "trim")
    bm_box(bm, Vector((0.0, 0.0, 0.0)), (0.41, 0.10, 0.03), "trim")
    bm_cyl(bm, Vector((0.0, -0.20, -0.14)), Vector((0.0, 0.17, -0.14)), 0.145, 0.16, "trim", segs=14)
    bm_cyl(bm, Vector((0.0, 0.17, -0.14)), Vector((0.0, 0.195, -0.14)), 0.168, 0.168, "metal", segs=14)
    bm_cyl(bm, Vector((0.0, 0.192, -0.14)), Vector((0.0, 0.200, -0.14)), 0.150, 0.150, "lens", segs=14)
    for k in range(3):
        y = -0.17 + k * 0.06
        bm_cyl(bm, Vector((0.0, y, -0.14)), Vector((0.0, y + 0.018, -0.14)), 0.165, 0.165, "metal", segs=14)
    return new_object("Searchlight", bm, mats)


def build_camera_ball(mats):
    bm = bmesh.new()
    bm_cyl(bm, Vector((0.0, 0.0, 0.26)), Vector((0.0, 0.0, 0.12)), 0.07, 0.09, "trim", segs=12)
    bm_sphere(bm, Vector((0.0, 0.0, 0.0)), 0.21, "paint2", u=14, v=9)
    # The window: a flat disc set into the front of the ball.
    bm_cyl(bm, Vector((0.0, 0.17, 0.0)), Vector((0.0, 0.205, 0.0)), 0.115, 0.105, "trim", segs=16)
    bm_cyl(bm, Vector((0.0, 0.203, 0.0)), Vector((0.0, 0.208, 0.0)), 0.10, 0.10, "lens", segs=16)
    return new_object("CameraBall", bm, mats)


# =============================================================================================
# Lettering
# =============================================================================================
def text_object(body, size, slot, mats):
    cu = bpy.data.curves.new("txt_" + body, 'FONT')
    cu.body = body
    cu.size = size
    cu.align_x = 'CENTER'
    cu.align_y = 'CENTER'
    cu.resolution_u = 2
    cu.space_character = 1.05
    ob = bpy.data.objects.new("txt_" + body, cu)
    bpy.context.scene.collection.objects.link(ob)
    ob = curve_to_mesh(ob)
    # Fine enough to follow a curved surface once shrink-wrapped.
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=1, use_grid_fill=True)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(ob.data)
    bm.free()
    for m in mats:
        ob.data.materials.append(m)
    set_material(ob, slot)
    return ob


def place_text(ob, side, y, z, x, target):
    """Stands a flat text mesh on the `side` (+1 right, -1 left) of the aircraft, reading from
    tail to nose on the right and nose to tail on the left, as lettering on a vehicle does,
    then wraps it onto `target`'s surface."""
    if side > 0:
        rot = Matrix(((0, 0, 1), (1, 0, 0), (0, 1, 0)))
    else:
        rot = Matrix(((0, 0, -1), (-1, 0, 0), (0, 1, 0)))
    ob.data.transform(rot.to_4x4())
    ob.location = Vector((x * side, y, z))
    mod = ob.modifiers.new("wrap", 'SHRINKWRAP')
    mod.target = target
    mod.wrap_method = 'NEAREST_SURFACEPOINT'
    mod.wrap_mode = 'OUTSIDE_SURFACE'
    mod.offset = 0.004
    apply_modifiers(ob)
    activate(ob)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def build_livery(name, words, mats, targets):
    parts = []
    for (body, size, slot, y, z, x, target_key) in words:
        for side in (1.0, -1.0):
            t = text_object(body, size, slot, mats)
            place_text(t, side, y, z, x, targets[target_key])
            parts.append(t)
    ob = join(parts, name)
    for poly in ob.data.polygons:
        poly.use_smooth = False
    return ob


# =============================================================================================
# Assembly
# =============================================================================================
def empty(name, loc):
    ob = bpy.data.objects.new(name, None)
    ob.location = loc
    bpy.context.scene.collection.objects.link(ob)
    return ob


def parent_to(child, parent):
    child.parent = parent
    child.matrix_parent_inverse = Matrix.Identity(4)
    child.location = Vector((0.0, 0.0, 0.0))


def build():
    reset_scene()
    mats = make_materials()
    cabin = build_cabin(mats)
    boom = build_boom(mats)
    cowling = build_cowling(mats)
    details = build_details(mats)
    fins = build_fins(mats)
    skids = build_skids(mats)
    for ob in [cabin, boom] + fins + [cowling]:
        shade(ob)
    # Lettering first, while the cabin and the boom are still separate targets to wrap onto.
    # The boom words wear the livery's decal colour; the cabin words sit on the lower body
    # colour and wear the UPPER body colour (slot "paint"), which is the contrast both liveries
    # want: navy on white for the police, white on teal for the news.
    police = build_livery("LiveryPolice", [
        ("POLICE", 0.30, "decal_police", -4.05, 1.69, 0.30, "boom"),
        ("POLICE", 0.24, "paint", -0.25, 0.80, 0.95, "cabin"),
    ], mats, {"boom": boom, "cabin": cabin})
    news = build_livery("LiveryNews", [
        ("RANDO 5", 0.25, "decal_news", -4.15, 1.69, 0.30, "boom"),
        ("NEWS", 0.28, "paint", -0.25, 0.80, 0.95, "cabin"),
    ], mats, {"boom": boom, "cabin": cabin})
    body = join([cabin, boom, cowling, details] + fins + skids, "Body")
    shade(body)
    rotor = empty("MainRotor", HUB)
    hub, blades = build_main_rotor(mats)
    for ob in (hub, blades):
        shade(ob, 40.0)
        parent_to(ob, rotor)
    tail = empty("TailRotor", TAIL_HUB)
    thub, tblades = build_tail_rotor(mats)
    for ob in (thub, tblades):
        shade(ob, 40.0)
        parent_to(ob, tail)
    light = build_searchlight(mats)
    shade(light, 40.0)
    light.location = Vector((0.40, 2.30, 0.50))
    cam = build_camera_ball(mats)
    shade(cam, 40.0)
    cam.location = Vector((0.0, 2.72, 0.46))
    return [body, rotor, hub, blades, tail, thub, tblades, light, cam, police, news]


def export(objs):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(
        filepath=OUT, export_format='GLB', use_selection=True,
        export_apply=True, export_materials='EXPORT', export_yup=True,
        export_normals=True, export_texcoords=False, export_tangents=False,
        export_skins=False, export_animations=False, export_cameras=False,
        export_lights=False,
    )


def render(path, objs):
    """A close-up for the handoff, in the police livery, on Cycles (runs headless)."""
    scene = bpy.context.scene
    for ob in objs:
        if ob.name == "LiveryNews" or ob.name == "CameraBall":
            ob.hide_render = True
    # Ground, sun, sky.
    bpy.ops.mesh.primitive_plane_add(size=60.0, location=(0.0, 0.0, 0.0))
    ground = bpy.context.active_object
    gm = bpy.data.materials.new("ground")
    gm.use_nodes = True
    gb = gm.node_tree.nodes.get("Principled BSDF")
    gb.inputs["Base Color"].default_value = (0.16, 0.16, 0.17, 1.0)
    gb.inputs["Roughness"].default_value = 0.85
    ground.data.materials.append(gm)
    sun_data = bpy.data.lights.new("sun", 'SUN')
    sun_data.energy = 4.0
    sun_data.angle = math.radians(1.5)
    sun = bpy.data.objects.new("sun", sun_data)
    sun.rotation_euler = (math.radians(50.0), math.radians(10.0), math.radians(140.0))
    scene.collection.objects.link(sun)
    world = bpy.data.worlds.new("world")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.42, 0.55, 0.75, 1.0)
    bg.inputs["Strength"].default_value = 0.9
    scene.world = world
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 50.0
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    target = Vector((0.0, -1.2, 1.35))
    cam.location = Vector((8.2, 7.6, 3.1))
    cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
    scene.camera = cam
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.film_transparent = False
    scene.view_settings.view_transform = 'AgX'
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def verify(path):
    """Read the numbers back out of the file that was actually written, not out of the scene."""
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=path)
    total = 0
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    report = []
    for ob in sorted(bpy.context.scene.objects, key=lambda o: o.name):
        if ob.type != 'MESH':
            report.append("  %-16s empty at %s" % (ob.name, tuple(round(c, 3) for c in ob.matrix_world.translation)))
            continue
        me = ob.data
        me.calc_loop_triangles()
        tris = len(me.loop_triangles)
        total += tris
        slots = sorted({ms.material.name for ms in ob.material_slots if ms.material})
        report.append("  %-16s %5d tris  %s" % (ob.name, tris, ", ".join(slots)))
        for v in me.vertices:
            w = ob.matrix_world @ v.co
            mn = Vector((min(mn.x, w.x), min(mn.y, w.y), min(mn.z, w.z)))
            mx = Vector((max(mx.x, w.x), max(mx.y, w.y), max(mx.z, w.z)))
    return total, mn, mx, report


def main(argv):
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    objs = build()
    export(objs)
    if "--render" in argv:
        render(argv[argv.index("--render") + 1], objs)
    if "--no-verify" in argv:
        print("  -> " + OUT)
        return
    total, mn, mx, report = verify(OUT)
    print("READ BACK FROM %s" % os.path.basename(OUT))
    print("\n".join(report))
    print("  triangles : %d" % total)
    print("  bbox      : width %.3f  length %.3f  height %.3f" % (mx.x - mn.x, mx.y - mn.y, mx.z - mn.z))
    print("  extents   : x %+.3f..%+.3f  y %+.3f..%+.3f  z %+.3f..%+.3f" % (mn.x, mx.x, mn.y, mx.y, mn.z, mx.z))
    print("  -> " + OUT)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    main(args)
