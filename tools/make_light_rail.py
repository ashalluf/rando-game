#!/usr/bin/env python3
"""The Coral Line's light rail vehicle, built in Blender (headless).

    blender -b --factory-startup --python tools/make_light_rail.py
    blender -b --factory-startup --python tools/make_light_rail.py -- --render out.png

Writes assets/models/light_rail_car.glb. Run `godot --headless --path . --import` after it,
before any render: Godot serves a cached import of a .glb (CLAUDE.md, measurement traps).
`tools/road_cars_setup.sh` fetches the Blender this runs on.

WHAT IT IS
----------
An original high-floor articulated light rail vehicle of the class LA's lines run (a 27 m,
two-section, double-ended car on three bogies, the middle one under the articulation; a
2.65 m body; a raked cab front with a wraparound windscreen and a destination display; four
double plug doors a side; a single-arm pantograph; roof air conditioning). A CLASS study, not a
copy of any maker's car: the proportions are the class's, the nose, the window line and the
livery are this game's own. Livery: a white body, a band of the line's coral under the windows,
a black window band, dark skirts and roof equipment in grey (the game recolours none of it; the
coral is LightRail.LINE_COLOR).

HOW IT IS BUILT
---------------
ONE SECTION (half a car) is modelled; the game puts two back to back on the shared bogie and
couples two cars. The body is a structured quad loft: STATIONS along the length (every window,
mullion and door edge is a station), each a RING of fixed points round the section (every
livery line, sill, window head and door head is a ring point), so the band runs exactly along
the body, the windows are (station, ring) rectangles and the door openings are holes in the
grid. The nose rakes back above the belt and tapers in plan over its last stations, and is
closed by a cap. Glass is set back 1.5 cm from the skin so the window band reads as glazing in
a frame. Doors are separate leaves (glass upper part) the game slides open; behind the openings
is a simple interior box (floor, walls, ceiling, seats) that only the open doors show - the
windows trace their own cabin in the game's shader.

CONTRACT WITH THE GAME (scripts/vehicles/light_rail_train.gd)
------------------------------------------------------------
Authored X = right, Y = forward (cab nose at +Y), Z = up, rail top at Z = 0, the section's
origin halfway along it; glTF's Y-up turns that into Godot's X right, Y up, nose at -Z. Its
bogie pivots are at Y = +CAB_BOGIE (under the cab) and Y = -HALF (the articulation, shared).
Nodes:
  Body        the section's skin, windows, front, roof equipment, skirts, lettering
  Interior    the box behind the doors (floor, walls, ceiling, seats, poles)
  Door_<side>_<n>_<leaf>   side R/L, door 0 (rear) / 1 (front), leaf A (toward the rear) / B;
              each leaf's origin at its closed position's centre; it opens along +-Y
  Pantograph  on the roof, its head at CONTACT (the game's LightRail.CONTACT_HEIGHT)
  Bogie       one bogie at the origin (the game instances it at each pivot)
  Bellows     the articulation's gangway bellows, centred at the origin
Material slots, bound BY NAME: paint (white), band (coral), dark (window band, skirts), roof,
trim (grey metal), glass, lamp_head, lamp_tail, sign (destination display), interior,
interior_floor, seat, rubber, metal, door_glass.
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "assets", "models", "light_rail_car.glb")

HALF = 6.75          # half a section's length (section = 13.5 m, car = 27 m)
WIDTH = 1.325        # half the body's width
FLOOR = 0.95         # floor over the rail (high floor; platforms are 0.92)
CAB_BOGIE = 4.3      # cab bogie pivot, from the section's centre
CONTACT = 5.65       # the contact wire over the rail
NOSE = 6.15          # where the nose begins

# name, linear base colour, metallic, roughness
SLOTS = [
    ("paint", (0.80, 0.81, 0.80), 0.15, 0.28),
    ("band", (0.80, 0.135, 0.075), 0.15, 0.30),
    ("dark", (0.012, 0.012, 0.014), 0.10, 0.35),
    ("roof", (0.33, 0.34, 0.35), 0.30, 0.55),
    ("trim", (0.10, 0.10, 0.11), 0.40, 0.45),
    ("glass", (0.010, 0.012, 0.014), 0.0, 0.05),
    ("lamp_head", (0.90, 0.92, 0.95), 0.0, 0.08),
    ("lamp_tail", (0.40, 0.02, 0.02), 0.0, 0.10),
    ("sign", (0.02, 0.02, 0.02), 0.0, 0.20),
    ("interior", (0.62, 0.62, 0.60), 0.0, 0.60),
    ("interior_floor", (0.08, 0.08, 0.09), 0.0, 0.70),
    ("seat", (0.05, 0.08, 0.22), 0.0, 0.80),
    ("rubber", (0.015, 0.015, 0.015), 0.0, 0.70),
    ("metal", (0.45, 0.45, 0.46), 1.0, 0.35),
    ("door_glass", (0.010, 0.012, 0.014), 0.0, 0.05),
]
MI = {name: i for i, (name, _c, _m, _r) in enumerate(SLOTS)}

# The ring: (x, z) of the right half from the bottom centre round to the roof's crown; the left
# half mirrors it. Named heights are the livery and opening lines.
SKIRT = 0.55
BELT_LO = 0.80
BAND_LO = 1.06
SILL = 1.32
HEAD = 2.58
DOOR_HEAD = 2.88
RING = [
    (0.0, SKIRT), (0.95, SKIRT), (1.26, SKIRT + 0.02), (1.31, 0.68), (1.325, BELT_LO),
    (1.325, FLOOR), (1.325, BAND_LO), (1.325, SILL), (1.318, 1.95), (1.305, HEAD),
    (1.29, DOOR_HEAD), (1.26, 3.08), (1.16, 3.26), (0.95, 3.39), (0.55, 3.46), (0.0, 3.48),
]
# Ring indices (right half) of the named heights.
I_FLOOR = 5
I_BAND = 6
I_SILL = 7
I_HEAD = 9
I_DHEAD = 10

# The openings along the section (y from, y to): doors and windows; everything between is pillar.
DOORS = [(-4.35, -2.95), (0.55, 1.95)]
WINDOWS = [(-6.40, -5.50), (-5.42, -4.55), (-2.75, -1.70), (-1.62, -0.57), (-0.49, 0.35),
           (2.15, 3.50), (3.58, 4.95), (5.50, 6.05)]


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
        if me.polygons[fl[0]].normal.dot(me.polygons[fl[1]].normal) < lim:
            e.use_edge_sharp = True
        elif me.polygons[fl[0]].material_index != me.polygons[fl[1]].material_index:
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
    axis = (b - a)
    length = axis.length
    res = bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=segs,
                                radius1=r1, radius2=r2, depth=length)
    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(axis.normalized()).to_matrix().to_4x4()
    m = Matrix.Translation((a + b) * 0.5) @ rot
    bmesh.ops.transform(bm, matrix=m, verts=res["verts"])
    for f in {f for v in res["verts"] for f in v.link_faces}:
        f.material_index = MI[mat]
    return res["verts"]


def rounded_box(bm, centre, size, radius, mat):
    """A box with its vertical edges rounded (roof pods, equipment): a loft of a rounded rect."""
    sx, sy, sz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
    r = min(radius, sx * 0.95, sy * 0.95)
    pts = []
    for cx, cy, a0 in ((sx - r, sy - r, 0.0), (-sx + r, sy - r, 90.0), (-sx + r, -sy + r, 180.0), (sx - r, -sy + r, 270.0)):
        for k in range(4):
            a = math.radians(a0 + 90.0 * k / 3.0)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    bottom = [bm.verts.new(Vector((centre[0] + x, centre[1] + y, centre[2] - sz))) for x, y in pts]
    top = [bm.verts.new(Vector((centre[0] + x * 0.96, centre[1] + y * 0.97, centre[2] + sz))) for x, y in pts]
    n = len(pts)
    for j in range(n):
        k = (j + 1) % n
        f = bm.faces.new((bottom[j], bottom[k], top[k], top[j]))
        f.material_index = MI[mat]
    f = bm.faces.new(top)
    f.material_index = MI[mat]
    f = bm.faces.new(list(reversed(bottom)))
    f.material_index = MI[mat]


# =============================================================================================
# The body loft
# =============================================================================================
def stations():
    """Every y where something changes, from the articulation end to the nose's start, then the
    nose's own stations (raked and tapered)."""
    ys = {-HALF + 0.25, NOSE}
    for a, b in DOORS + WINDOWS:
        ys.add(a)
        ys.add(b)
    # Extra stations so long panels stay planar under the tumblehome and light evenly.
    for k in range(-6, 6):
        ys.add(k + 0.5)
    ys = sorted(y for y in ys if -HALF + 0.25 <= y <= NOSE)
    return ys


NOSE_STATIONS = [6.30, 6.45, 6.57, 6.66, 6.72]


def full_ring():
    """The whole ring (right half up, left half down), as (x, z, right-half index)."""
    right = [(x, z, i) for i, (x, z) in enumerate(RING)]
    left = [(-x, z, i) for i, (x, z) in reversed(list(enumerate(RING)))][1:-1]
    return right + left


def nose_shape(y, x, z):
    """Plan taper and rake at the nose: (x, y) of a ring point at station y."""
    t = max(0.0, (y - NOSE) / (HALF - NOSE))
    # Plan: the corners round off toward the front.
    taper = 1.0 - 0.10 * t * t
    # Rake: above the belt the front leans back (a 16 degree windscreen).
    rake = 0.0
    if z > BAND_LO:
        rake = t * min(z - BAND_LO, 2.2) * 0.28
    # The roof's front edge rounds down.
    return x * taper, y - rake


def body_material(i_seg, ring_idx_a, ring_idx_b, ya, yb):
    """Slot for the quad between ring points a, b (right-half indices) and stations ya..yb."""
    lo = min(ring_idx_a, ring_idx_b)
    hi = max(ring_idx_a, ring_idx_b)
    mid = (ya + yb) * 0.5
    if hi <= 2:
        return "dark"
    if hi <= 4:
        return "dark"
    if lo >= I_BAND and hi <= I_SILL:
        return "band"
    if lo >= I_SILL and hi <= I_HEAD:
        for a, b in WINDOWS:
            if a <= mid <= b:
                return "glass"
        return "dark"
    if lo >= 12:
        return "roof"
    return "paint"


def in_door(ya, yb, ia, ib):
    mid = (ya + yb) * 0.5
    lo = min(ia, ib)
    hi = max(ia, ib)
    for a, b in DOORS:
        if a < mid < b and lo >= I_FLOOR and hi <= I_DHEAD:
            return True
    return False


# The front: rings past the last nose station, scaled in toward the centre line and bulging a
# few centimetres forward, so the cab front is a grid of the same rings (the windscreen is a
# region of it, like a side window). (scale of x, metres forward of the last nose station).
FRONT_RINGS = [(0.82, 0.045), (0.56, 0.075), (0.28, 0.092)]


def front_material(ia, ib, xa, xb):
    lo, hi = min(ia, ib), max(ia, ib)
    if hi <= 4:
        return "dark"
    if lo >= I_BAND and hi <= I_SILL:
        return "band"
    if lo >= I_SILL and hi <= I_DHEAD:
        return "glass" if max(abs(xa), abs(xb)) < 1.02 else "dark"
    if lo >= 12:
        return "roof"
    return "paint"


def build_body(mats):
    bm = bmesh.new()
    ring = full_ring()
    ys = stations() + NOSE_STATIONS
    rows = []
    xs = []
    for y in ys:
        row = []
        xrow = []
        for (x, z, idx) in ring:
            if y > NOSE:
                nx, ny = nose_shape(y, x, z)
            else:
                nx, ny = x, y
            row.append(bm.verts.new(Vector((nx, ny, z))))
            xrow.append(nx)
        rows.append(row)
        xs.append(xrow)
    last = NOSE_STATIONS[-1]
    for sc, dy in FRONT_RINGS:
        row = []
        xrow = []
        for (x, z, idx) in ring:
            nx, ny = nose_shape(last, x, z)
            # The front bulges more low down than at the roof (the rake already leans it back).
            row.append(bm.verts.new(Vector((nx * sc, ny + dy * (1.0 - 0.4 * max(0.0, z - 1.0) / 2.5), z))))
            xrow.append(nx * sc)
        rows.append(row)
        xs.append(xrow)
    n = len(ring)
    n_side = len(ys)
    glass_faces = []
    for i in range(len(rows) - 1):
        front = i >= n_side - 1
        ya = ys[i] if i < n_side else HALF
        yb = ys[i + 1] if i + 1 < n_side else HALF
        for j in range(n):
            k = (j + 1) % n
            ia = ring[j][2]
            ib = ring[k][2]
            if ya < NOSE and in_door(ya, yb, ia, ib):
                continue
            if front:
                slot = front_material(ia, ib, xs[i + 1][j], xs[i + 1][k])
            else:
                slot = body_material(i, ia, ib, ya, yb)
                if ya >= NOSE - 0.001:
                    # The nose's flanks: the window band runs on round the corner as glazing frame.
                    lo, hi = min(ia, ib), max(ia, ib)
                    if lo >= I_SILL and hi <= I_DHEAD:
                        slot = "dark"
            f = bm.faces.new((rows[i][j], rows[i + 1][j], rows[i + 1][k], rows[i][k]))
            f.material_index = MI[slot]
            if slot == "glass":
                glass_faces.append(f)
    # The ends: the articulation end cap (dark) and the last sliver of the front.
    f = bm.faces.new(list(reversed(rows[0])))
    f.material_index = MI["dark"]
    # The front's last strip, joined across the centre line one ring band at a time (so the
    # windscreen and the band run straight across it).
    last_row = rows[-1]
    nr = len(RING)
    def at(jj):
        if jj == 0 or jj == nr - 1:
            return last_row[jj], last_row[jj]
        return last_row[jj], last_row[nr + (nr - 2 - jj)]
    for jj in range(nr - 1):
        r0, l0 = at(jj)
        r1, l1 = at(jj + 1)
        verts = [r0, r1, l1, l0]
        uniq = []
        for v in verts:
            if v not in uniq:
                uniq.append(v)
        if len(uniq) < 3:
            continue
        f = bm.faces.new(uniq)
        f.material_index = MI[front_material(jj, jj + 1, 0.0, 0.0)]
        if f.material_index == MI["glass"]:
            glass_faces.append(f)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    # Glass set back from the skin in a rubber surround: each window inset as a region.
    res = bmesh.ops.inset_region(bm, faces=glass_faces, thickness=0.035, depth=-0.018, use_even_offset=True)
    for f in res["faces"]:
        f.material_index = MI["rubber"]
    # Door jambs: the openings' reveals, so the skin has thickness at a door.
    for a, b in DOORS:
        for yy, sgn in ((a, 1.0), (b, -1.0)):
            for side in (1.0, -1.0):
                bm_box(bm, Vector((side * 1.27, yy + sgn * 0.03, (FLOOR + DOOR_HEAD) * 0.5)), (0.11, 0.06, DOOR_HEAD - FLOOR), "dark")
        for side in (1.0, -1.0):
            bm_box(bm, Vector((side * 1.27, (a + b) * 0.5, DOOR_HEAD - 0.03)), (0.11, b - a, 0.06), "dark")
            bm_box(bm, Vector((side * 1.27, (a + b) * 0.5, FLOOR - 0.02)), (0.11, b - a, 0.04), "metal")
    ob = new_object("Body", bm, mats)
    return ob


def build_front_details(mats):
    """Headlights, tail lights, the destination display, the coupler cover, the wipers, the
    anticlimber, the line bullet."""
    bm = bmesh.new()
    y_front = HALF
    ys_front = NOSE_STATIONS[-1]
    for side in (1.0, -1.0):
        # Headlight cluster: a dark bezel with a bright lens, low at each corner.
        bm_box(bm, Vector((side * 0.86, y_front + 0.035, 0.98)), (0.40, 0.06, 0.18), "dark")
        bm_cyl(bm, Vector((side * 0.96, y_front + 0.05, 0.98)), Vector((side * 0.96, y_front + 0.075, 0.98)), 0.07, 0.07, "lamp_head", segs=12)
        bm_cyl(bm, Vector((side * 0.78, y_front + 0.05, 0.98)), Vector((side * 0.78, y_front + 0.075, 0.98)), 0.055, 0.055, "lamp_head", segs=12)
        # Tail / marker lamps, outboard.
        bm_box(bm, Vector((side * 1.12, y_front + 0.0, 0.98)), (0.10, 0.06, 0.12), "lamp_tail")
        # Wiper.
        _wx, wy = nose_shape(ys_front, side * 0.45, 1.5)
        bm_box(bm, Vector((side * 0.45, wy + 0.09, 1.5)), (0.03, 0.03, 0.7), "trim",
               rot=Matrix.Rotation(math.radians(70.0 * side), 3, 'Y'))
    # Destination display over the windscreen (the game lights its text).
    _dx, dy = nose_shape(ys_front, 0.0, 3.0)
    bm_box(bm, Vector((0.0, dy + 0.075, 3.0)), (1.5, 0.05, 0.22), "sign")
    # Anticlimber and coupler cover, below the band.
    bm_box(bm, Vector((0.0, y_front + 0.02, 0.70)), (1.6, 0.10, 0.16), "trim")
    bm_box(bm, Vector((0.0, y_front + 0.05, 0.50)), (0.8, 0.12, 0.30), "dark")
    # High-mounted third lamp over the display.
    _hx, hy = nose_shape(ys_front, 0.0, 3.2)
    bm_box(bm, Vector((0.0, hy + 0.07, 3.2)), (0.30, 0.05, 0.06), "lamp_head")
    ob = new_object("Front", bm, mats)
    return ob


def build_roof(mats, pantograph_base):
    bm = bmesh.new()
    # Air conditioning pods.
    for yc in (-4.2, 2.9):
        rounded_box(bm, (0.0, yc, 3.62), (1.75, 2.6, 0.32), 0.25, "roof")
        for k in range(5):
            bm_box(bm, Vector((0.0, yc - 0.9 + 0.45 * k, 3.785)), (1.3, 0.12, 0.02), "trim")
    # Resistor box and the pantograph's base frame.
    rounded_box(bm, (0.0, -1.6, 3.58), (1.2, 1.4, 0.22), 0.08, "trim")
    if pantograph_base:
        bm_box(bm, Vector((0.0, 0.9, 3.53)), (1.3, 1.5, 0.08), "trim")
        for x in (-0.55, 0.55):
            for y in (0.3, 1.5):
                bm_cyl(bm, Vector((x, y, 3.48)), Vector((x, y, 3.60)), 0.05, 0.05, "rubber", segs=8)
    # Gutters along the cant rail.
    for side in (1.0, -1.0):
        bm_box(bm, Vector((side * 1.235, 0.0, 3.13)), (0.04, 2.0 * HALF - 1.4, 0.04), "trim")
    return new_object("Roof", bm, mats)


def build_skirt_details(mats):
    """Under the body between the bogies: equipment boxes and the step plates."""
    bm = bmesh.new()
    for yc, ln in ((-1.0, 3.6), (1.8, 1.6)):
        bm_box(bm, Vector((0.0, yc, 0.42)), (1.9, ln, 0.26), "trim")
    return new_object("Under", bm, mats)


def build_lettering(mats, body):
    parts = []
    for side in (1.0, -1.0):
        for text, size, y, z, slot in (("BASIN METRO", 0.17, -1.4, 0.93, "dark"),):
            cu = bpy.data.curves.new("txt", 'FONT')
            cu.body = text
            cu.size = size
            cu.align_x = 'CENTER'
            cu.align_y = 'CENTER'
            cu.resolution_u = 2
            cu.space_character = 1.12
            ob = bpy.data.objects.new("txt", cu)
            bpy.context.scene.collection.objects.link(ob)
            activate(ob)
            bpy.ops.object.convert(target='MESH')
            ob = bpy.context.view_layer.objects.active
            for m in mats:
                ob.data.materials.append(m)
            for poly in ob.data.polygons:
                poly.material_index = MI[slot]
            if side > 0:
                rot = Matrix(((0, 0, 1), (1, 0, 0), (0, 1, 0)))
            else:
                rot = Matrix(((0, 0, -1), (-1, 0, 0), (0, 1, 0)))
            ob.data.transform(rot.to_4x4())
            ob.location = Vector((side * 1.332, y, z))
            activate(ob)
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
            parts.append(ob)
    # The line's bullet: a coral disc with a white "C" on each side behind the cab.
    for side in (1.0, -1.0):
        bm = bmesh.new()
        bm_cyl(bm, Vector((side * 1.327, 5.05, 2.0)), Vector((side * 1.334, 5.05, 2.0)), 0.20, 0.20, "band", segs=24)
        parts.append(new_object("bullet", bm, mats))
    return join(parts, "Lettering")


def build_interior(mats):
    bm = bmesh.new()
    y0, y1 = -HALF + 0.3, NOSE - 0.6
    ln = y1 - y0
    yc = (y0 + y1) * 0.5
    # Floor, ceiling, walls (inward-facing: built as a box and flipped).
    verts = bm_box(bm, Vector((0.0, yc, (FLOOR + 2.95) * 0.5)), (2.40, ln, 2.95 - FLOOR), "interior")
    faces = {f for v in verts for f in v.link_faces}
    for f in faces:
        f.normal_flip()
        if f.normal.z > 0.5:
            f.material_index = MI["interior_floor"]
    # Seats (pairs facing each other) and the vertical poles by the doors.
    for y in (-5.8, -5.0, -1.9, -0.8, 2.8, 4.0):
        for side in (1.0, -1.0):
            bm_box(bm, Vector((side * 0.72, y, FLOOR + 0.45)), (0.92, 0.45, 0.10), "seat")
            bm_box(bm, Vector((side * 0.72, y + 0.24, FLOOR + 0.80)), (0.92, 0.08, 0.62), "seat")
    for a, b in DOORS:
        for y in (a - 0.25, b + 0.25):
            for side in (1.0, -1.0):
                bm_cyl(bm, Vector((side * 0.9, y, FLOOR)), Vector((side * 0.9, y, 2.95)), 0.02, 0.02, "metal", segs=8)
    # Cab partition.
    bm_box(bm, Vector((0.0, y1, (FLOOR + 2.95) * 0.5)), (2.4, 0.05, 2.95 - FLOOR), "interior")
    return new_object("Interior", bm, mats)


def build_doors(mats):
    """Two leaves per door per side. Each leaf: a panel with a glazed upper part."""
    obs = []
    for side, sname in ((1.0, "R"), (-1.0, "L")):
        for n, (a, b) in enumerate(DOORS):
            w = (b - a) * 0.5
            for leaf, (la, lb) in (("A", (a, a + w)), ("B", (a + w, b))):
                bm = bmesh.new()
                cy = (la + lb) * 0.5
                h = DOOR_HEAD - FLOOR
                lw = lb - la - 0.01
                # Built round the leaf's own centre (the node's origin).
                bm_box(bm, Vector((0.0, 0.0, -h * 0.5 + 0.40)), (0.045, lw, 0.80), "paint")
                bm_box(bm, Vector((0.0, 0.0, h * 0.5 - 0.06)), (0.045, lw, 0.12), "dark")
                for edge in (-1.0, 1.0):
                    bm_box(bm, Vector((0.0, edge * (lw * 0.5 - 0.04), 0.35)), (0.045, 0.08, h - 0.8 - 0.12), "dark")
                bm_box(bm, Vector((side * 0.005, 0.0, 0.35)), (0.03, lw - 0.16, h - 0.8 - 0.12), "door_glass")
                # The coral band carried across the door at the band height.
                bm_box(bm, Vector((side * 0.024, 0.0, (BAND_LO + SILL) * 0.5 - (FLOOR + h * 0.5))), (0.004, lw, SILL - BAND_LO), "band")
                ob = new_object("Door_%s_%d_%s" % (sname, n, leaf), bm, mats)
                ob.location = Vector((side * 1.30, cy, FLOOR + h * 0.5))
                obs.append(ob)
    return obs


def build_pantograph(mats):
    """A single-arm pantograph, raised so the head meets the contact wire at CONTACT."""
    bm = bmesh.new()
    base_z = 3.60
    knee = Vector((0.0, 1.95, 4.62))
    foot = Vector((0.0, 0.25, base_z + 0.05))
    head = Vector((0.0, 0.95, CONTACT - 0.06))
    for x in (-0.18, 0.18):
        bm_cyl(bm, foot + Vector((x, 0, 0)), knee + Vector((x * 0.3, 0, 0)), 0.035, 0.03, "metal", segs=8)
    bm_cyl(bm, knee, head, 0.025, 0.02, "metal", segs=8)
    bm_cyl(bm, foot + Vector((0, 0.15, 0.02)), knee + Vector((0, -0.25, -0.15)), 0.015, 0.015, "metal", segs=6)
    # Head: two carbon strips across, with horns.
    for dy in (-0.15, 0.15):
        bm_box(bm, head + Vector((0.0, dy, 0.03)), (1.30, 0.05, 0.05), "rubber")
        for side in (1.0, -1.0):
            bm_cyl(bm, head + Vector((side * 0.65, dy, 0.03)), head + Vector((side * 0.90, dy, -0.12)), 0.012, 0.012, "metal", segs=6)
    bm_box(bm, head + Vector((0.0, 0.0, -0.02)), (0.25, 0.32, 0.04), "metal")
    # The base frame and its springs.
    bm_box(bm, foot + Vector((0.0, 0.2, -0.02)), (0.9, 0.7, 0.06), "trim")
    bm_cyl(bm, foot + Vector((0.3, 0.4, 0.02)), foot + Vector((0.3, 0.9, 0.3)), 0.04, 0.04, "trim", segs=8)
    return new_object("Pantograph", bm, mats)


def build_bogie(mats):
    """A motor bogie: two wheelsets (0.71 m wheels on 1435 mm), side frames, springs, the motor."""
    bm = bmesh.new()
    gauge = 1.435
    for wy in (-0.95, 0.95):
        for side in (1.0, -1.0):
            x = side * (gauge * 0.5 + 0.035)
            bm_cyl(bm, Vector((x - side * 0.06, wy, 0.355)), Vector((x + side * 0.06, wy, 0.355)), 0.355, 0.355, "metal", segs=20)
            bm_cyl(bm, Vector((x + side * 0.06, wy, 0.355)), Vector((x + side * 0.07, wy, 0.355)), 0.30, 0.30, "trim", segs=20)
        bm_cyl(bm, Vector((-0.80, wy, 0.355)), Vector((0.80, wy, 0.355)), 0.08, 0.08, "trim", segs=10)
    for side in (1.0, -1.0):
        x = side * 1.0
        bm_box(bm, Vector((x, 0.0, 0.50)), (0.18, 2.6, 0.22), "trim")
        bm_box(bm, Vector((x, 0.0, 0.62)), (0.24, 0.9, 0.12), "dark")
        for wy in (-0.95, 0.95):
            bm_box(bm, Vector((x, wy, 0.36)), (0.22, 0.30, 0.20), "dark")
            bm_cyl(bm, Vector((x, wy * 0.7, 0.58)), Vector((x, wy * 0.7, 0.72)), 0.07, 0.07, "rubber", segs=10)
    bm_box(bm, Vector((0.0, 0.0, 0.55)), (1.9, 0.5, 0.18), "trim")
    bm_box(bm, Vector((0.0, -0.45, 0.38)), (0.9, 0.4, 0.34), "dark")
    return new_object("Bogie", bm, mats)


def build_bellows(mats):
    bm = bmesh.new()
    for k in range(9):
        y = -0.24 + 0.06 * k
        w = 1.22 if k % 2 == 0 else 1.18
        bm_box(bm, Vector((0.0, y, 1.95)), (2 * w, 0.055, 2.6), "rubber")
    return new_object("Bellows", bm, mats)


# =============================================================================================
# Assembly
# =============================================================================================
def build():
    reset_scene()
    mats = make_materials()
    body = build_body(mats)
    front = build_front_details(mats)
    roof = build_roof(mats, True)
    under = build_skirt_details(mats)
    letters = build_lettering(mats, body)
    for ob in (front, roof, under, letters):
        shade(ob, 35.0)
    shade(body, 35.0)
    body = join([body, front, roof, under, letters], "Body")
    shade(body, 35.0)
    interior = build_interior(mats)
    shade(interior, 30.0)
    doors = build_doors(mats)
    for d in doors:
        shade(d, 30.0)
    panto = build_pantograph(mats)
    shade(panto, 40.0)
    bogie = build_bogie(mats)
    shade(bogie, 40.0)
    bellows = build_bellows(mats)
    shade(bellows, 40.0)
    return [body, interior, panto, bogie, bellows] + doors


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
    scene = bpy.context.scene
    # A second section back to back, as the game puts them, for the preview.
    bpy.ops.mesh.primitive_plane_add(size=80.0, location=(0.0, 0.0, 0.0))
    ground = bpy.context.active_object
    gm = bpy.data.materials.new("ground")
    gm.use_nodes = True
    gb = gm.node_tree.nodes.get("Principled BSDF")
    gb.inputs["Base Color"].default_value = (0.16, 0.16, 0.17, 1.0)
    gb.inputs["Roughness"].default_value = 0.85
    ground.data.materials.append(gm)
    for ob in objs:
        if ob.name == "Bogie":
            for y in (CAB_BOGIE, -HALF):
                c = ob.copy()
                c.location = Vector((0.0, y, 0.0))
                scene.collection.objects.link(c)
            ob.hide_render = True
        if ob.name == "Bellows":
            ob.location = Vector((0.0, -HALF, 0.0))
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
    cam_data.lens = 40.0
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    target = Vector((0.0, 1.5, 1.6))
    cam.location = Vector((9.0, 14.0, 3.2))
    cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
    scene.camera = cam
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 32
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.view_settings.view_transform = 'AgX'
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def verify(path):
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=path)
    total = 0
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    report = []
    for ob in sorted(bpy.context.scene.objects, key=lambda o: o.name):
        if ob.type != 'MESH':
            continue
        me = ob.data
        me.calc_loop_triangles()
        tris = len(me.loop_triangles)
        total += tris
        slots = sorted({ms.material.name for ms in ob.material_slots if ms.material})
        report.append("  %-16s %5d tris  %s" % (ob.name, tris, ", ".join(slots)))
        if ob.name == "Body":
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
    total, mn, mx, report = verify(OUT)
    print("READ BACK FROM %s" % os.path.basename(OUT))
    print("\n".join(report))
    print("  triangles : %d" % total)
    print("  body bbox : x %+.3f..%+.3f  y %+.3f..%+.3f  z %+.3f..%+.3f" % (mn.x, mx.x, mn.y, mx.y, mn.z, mx.z))
    print("  -> " + OUT)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    main(args)
