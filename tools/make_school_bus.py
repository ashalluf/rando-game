#!/usr/bin/env python3
"""The school bus: a 40 ft transit-style (Type D) school bus, the kind California districts run,
built in Blender from code on tools/make_big_vehicles.py (and through it tools/make_road_cars.py's
pipeline: the profile-curve loft, booleans, raycast parts, the material slots and the far twin):

    tools/road_cars_setup.sh                     # once: Blender 4.2 LTS into build/car_src/
    build/car_src/blender/blender-4.2.23-linux-x64/blender -b --factory-startup \\
        -P tools/make_school_bus.py -- school_bus [--render] [--nodetail]

Writes assets/models/road_school_bus.glb; then run `godot --headless --path . --import` (CLAUDE.md,
measurement trap 1). `--render` writes Cycles previews to $RENDER_DIR.

Conventions are the cars' and the big vehicles' (read both docstrings): X lateral, Y along the bus
with the NOSE AT +Y, Z up, ground at Z = 0, the kerb side +X. No wheels in the full model (the game
draws BigVehicles.wheel_mesh() per axle); a `school_bus_far` twin with baked far wheels.

What makes it a school bus: the flat face with a two-piece windscreen and the SCHOOL BUS sign over
it between the eight-way warning lamps (amber inboard, red outboard - the `amber` slot is added to
the cars' seven and the big vehicles' two), the entrance door ahead of the setback front axle on
the kerb side (two glazed leaves, folded shut), rows of split-sash windows down both sides, three
black rub rails, the STOP arm folded against the driver's side and the crossing arm on the front
bumper, the rear emergency door between two windows, roof hatches, and the district's name down
both flanks. The district is invented (RANDO UNIFIED SCHOOL DISTRICT); no manufacturer's shapes,
names or badges.
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_big_vehicles as bv  # noqa: E402  (imports make_road_cars, appends sign / glass_door)
import make_road_cars as rc  # noqa: E402

from make_road_cars import (  # noqa: E402
    PAINT, GLASS, TRIM, CHROME, TYRE, LIGHT_F, LIGHT_R, ramp, log, new_object, boolean, quad,
    add_box, tidy, oriented_grid, rect_grid, extrude_cutter, rounded_outline, surface_path,
    cut_grooves, wrap_band, join,
)
from make_big_vehicles import (  # noqa: E402
    box_into, disc_lamp, side_cutter, end_panel, side_panel, mudflap, GLASS_DOOR, tube,
)

rc.SLOTS.append(("amber", (0.85, 0.42, 0.03), 0.0, 0.10, 0.3))
AMBER = len(rc.SLOTS) - 1

OUT_DIR = rc.OUT_DIR
DISTRICT = "RANDO UNIFIED SCHOOL DISTRICT"

# Half width of the body (a school bus is 96 in wide: 2.44 m).
HW = 1.222


def school_bus():
    """The Type D: a flat, slightly domed face, a long body with rounded roof edges, the door ahead
    of the front axle, the engine up front between the driver and the door (no rear grille)."""
    L = 12.19
    s = {"name": "school_bus", "length": L, "height": 3.10}
    k = HW / 1.293
    s.update({
        "nose": 6.095, "tail": -6.095,
        "front_axle": 3.62, "rear_axle": -2.62, "axle_z": 0.500,
        "axles": [(3.62, False), (-2.62, True)],
        "wheel_r": 0.500, "wheel_w": 0.300, "wheel_x": 0.985,
        "dual_x": 0.885, "dual_gap": 0.330,
        "arch_r": 0.585, "arch_r_rear": 0.585, "arch_in": 0.62, "arch_in_dual": 0.56,
        "road": -0.30, "belt_probe_z": 2.0,
        "cowl": 7.5, "deck": -7.5, "gh_blend_front": 0.1, "gh_blend_rear": 0.1,
        "crown_at": 0.60, "tension": 1.0, "under_j": 1.0,
        "rings": [0.0, 1.0, 1.6, 2.1, 2.85, 3.4, 3.92, 4.0, 4.08, 4.6, 5.0, 5.5, 6.0, 6.25,
                  6.5, 6.75, 7.0],
        "end_steps": [0.0, 0.015, 0.04, 0.08, 0.14, 0.22, 0.32],
        "mid_step": 0.62,
        "extra_stations": [],
        "creases": [(6.0, 0.35, -7.0, 7.0)],
        "station_creases": [],
        # The roof edge rolls over on a bigger radius than the city bus's (school bus roof bows).
        "tangent_over": {5: (0.0, 1.0), 6: (-0.25, 1.0), 7: (-1.0, 0.0)},
        "nose_cap": {"steps": 3, "roll": lambda j: 0.080, "dome": 0.060,
                     "lean": lambda co: 0.025 * ramp(co.z, 1.6, 0.5)},
        "tail_cap": {"steps": 3, "roll": lambda j: 0.070, "dome": 0.020},
        "sculpt": [],
        "profile": {
            "top": [(6.095, 2.930), (5.95, 2.960), (-5.95, 2.960), (-6.095, 2.940)],
            "rail_z": [(6.095, 2.640), (5.95, 2.660), (-5.95, 2.660), (-6.095, 2.650)],
            "rail_w": [(6.095, 1.17), (6.00, 1.200), (5.90, 1.212), (-5.90, 1.212),
                       (-6.00, 1.200), (-6.095, 1.17)],
            "roof_z": [(6.095, 2.880), (5.95, 2.905), (-5.95, 2.905), (-6.095, 2.890)],
            "roof_w": [(6.095, 0.92), (5.95, 0.96), (-5.95, 0.96), (-6.095, 0.92)],
            "over_w": 1.0,
            "belt_z": 1.420,
            "belt_in": 0.004,
            "shoulder_z": 1.250,
            "width": [(6.095, 1.215 * k), (6.07, 1.258 * k), (6.02, 1.283 * k), (5.92, HW),
                      (-5.92, HW), (-6.02, 1.283 * k), (-6.07, 1.258 * k), (-6.095, 1.215 * k)],
            "low_z": 0.70,
            "low_in": 0.004,
            "sill_z": [(6.095, 0.420), (5.80, 0.400), (-5.80, 0.400), (-6.095, 0.430)],
            "sill_in": 0.030,
            "floor_z": [(6.095, 0.400), (5.80, 0.380), (-5.80, 0.380), (-6.095, 0.410)],
            "floor_in": 0.10,
        },
        # The entrance door on the kerb side (+x): (name, y front edge, y rear edge).
        "doors": [("f", 5.80, 4.98)],
        "door_z": (0.42, 2.50),
        "window_z": (1.56, 2.50),
    })
    s["details"] = school_details
    s["signs"] = []
    return s


def text_obj(text, size, mat, rot, loc, extrude=0.003):
    """Flat lettering as a mesh object in slot `mat`: Blender's built-in font, centred, turned by
    `rot` (a Matrix) and put at `loc`."""
    cu = bpy.data.curves.new("txt", 'FONT')
    cu.body = text
    cu.size = size
    cu.align_x = 'CENTER'
    cu.align_y = 'CENTER'
    cu.extrude = extrude
    cu.resolution_u = 3
    tmp = bpy.data.objects.new("txt", cu)
    bpy.context.scene.collection.objects.link(tmp)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
    bpy.data.objects.remove(tmp, do_unlink=True)
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    for f in bm.faces:
        f.material_index = mat
    bmesh.ops.transform(bm, matrix=Matrix.Translation(loc) @ rot, verts=bm.verts)
    return new_object("text_" + text[:8], bm)


# Facing a side: lettering made in XY (reading +X, facing +Z) is turned to face +X / -X / +Y / -Y.
ROT_FRONT = Matrix.Rotation(math.pi, 4, 'Z') @ Matrix.Rotation(math.pi * 0.5, 4, 'X')
ROT_REAR = Matrix.Rotation(math.pi * 0.5, 4, 'X')
ROT_KERB = Matrix.Rotation(math.pi * 0.5, 4, 'Z') @ Matrix.Rotation(math.pi * 0.5, 4, 'X')
ROT_STREET = Matrix.Rotation(-math.pi * 0.5, 4, 'Z') @ Matrix.Rotation(math.pi * 0.5, 4, 'X')


def school_details(s, sec, surf, body, parts):
    zl, zh = s["window_z"]
    fz0, fz1 = s["door_z"]
    nose, tail = s["nose"], s["tail"]
    fl, _n = surf.end_hit(0.0, 1.8, 1.0)
    face_f = fl.y if fl is not None else nose + 0.1
    tl, _n = surf.end_hit(0.0, 1.8, -1.0)
    face_t = tl.y if tl is not None else tail - 0.1
    xs = HW + 0.002

    # --- openings ---------------------------------------------------------------------------------
    # The windscreen: two panes either side of a centre post, the sign panel over them.
    for side in (1.0, -1.0):
        x_in, x_out = side * 0.045, side * 1.10
        pane = rounded_outline([(min(x_in, x_out), 1.22), (max(x_in, x_out), 1.22),
                                (max(x_in, x_out), 2.50), (min(x_in, x_out), 2.50)], 0.09)
        boolean(body, extrude_cutter(pane, "y", nose - 0.20, nose + 0.6))
    # Side windows: separate openings, each a sash; the kerb side starts behind the door, the
    # driver's side has the driver's sliding window first.
    pitch = 0.92
    win_w = 0.76
    dz = s["doors"]
    starts = {1.0: dz[0][2] - 0.22, -1.0: nose - 0.30}
    win = {}
    for side, y_start in starts.items():
        ys = []
        y = y_start
        while y - win_w > tail + 1.05:
            ys.append((y, y - win_w))
            y -= pitch
        win[side] = ys
        for y0, y1 in ys:
            hole = rounded_outline([(y1, zl), (y0, zl), (y0, zh), (y1, zh)], 0.06)
            boolean(body, side_cutter(hole, side, HW - 0.04), quiet=True)
    # The entrance door's opening.
    for name, y0, y1 in dz:
        hole = rounded_outline([(y1, fz0 - 0.10), (y0, fz0 - 0.10), (y0, fz1), (y1, fz1)], 0.05)
        boolean(body, side_cutter(hole, 1.0, HW - 0.12), quiet=True)
    # The rear: the emergency door in the middle, a window each side of it, high.
    for x0, x1 in ((-1.02, -0.50), (0.50, 1.02)):
        rw = rounded_outline([(x0, 1.62), (x1, 1.62), (x1, 2.45), (x0, 2.45)], 0.06)
        boolean(body, extrude_cutter(rw, "y", tail - 0.6, tail + 0.20))
    dw = rounded_outline([(-0.36, 1.55), (0.36, 1.55), (0.36, 2.45), (-0.36, 2.45)], 0.05)
    boolean(body, extrude_cutter(dw, "y", tail - 0.6, tail + 0.20))

    # --- glass ------------------------------------------------------------------------------------
    gb = bmesh.new()
    yf = face_f - 0.035
    for side in (1.0, -1.0):
        x_in, x_out = side * 0.045, side * 1.10
        rows, cols = 6, 6
        pts = [Vector((x_in + (x_out - x_in) * c / cols, yf - (z - 1.22) * 0.05, z))
               for r in range(rows + 1) for c in range(cols + 1)
               for z in [1.22 + (2.50 - 1.22) * r / rows]]
        oriented_grid(gb, pts, [Vector((0.0, 1.0, 0.05)).normalized()] * len(pts), rows + 1, cols + 1, GLASS)
    yr = face_t + 0.03
    for x0, x1, z0 in ((-1.02, -0.50, 1.62), (0.50, 1.02, 1.62), (-0.36, 0.36, 1.55)):
        pts = [Vector((x0 + (x1 - x0) * c / 3, yr, z0 + (2.45 - z0) * r / 2)) for r in range(3) for c in range(4)]
        oriented_grid(gb, pts, [Vector((0, -1, 0))] * len(pts), 3, 4, GLASS)
    for side, ys in win.items():
        for y0, y1 in ys:
            pts = [Vector((side * (HW - 0.012), y0 + (y1 - y0) * c / 2, zl + (zh - zl) * r / 2))
                   for r in range(3) for c in range(3)]
            oriented_grid(gb, pts, [Vector((side, 0, 0))] * len(pts), 3, 3, GLASS)
    tidy(gb)
    parts.append(new_object("glass", gb))

    # --- trims: sash frames, rub rails, bumpers, the sign band, the centre post -------------------
    bt = bmesh.new()
    for side, ys in win.items():
        for y0, y1 in ys:
            lo, hi = min(y0, y1), max(y0, y1)
            # The split sash: the bar across at 45 %, the upper sash's frame, a rubber surround.
            zb = zl + (zh - zl) * 0.45
            box_into(bt, side * (HW - 0.015), side * (HW + 0.004), lo, hi, zb - 0.025, zb + 0.025, CHROME)
            box_into(bt, side * (HW - 0.010), side * (HW + 0.006), lo, lo + 0.03, zl, zh, TRIM)
            box_into(bt, side * (HW - 0.010), side * (HW + 0.006), hi - 0.03, hi, zl, zh, TRIM)
            box_into(bt, side * (HW - 0.010), side * (HW + 0.006), lo, hi, zh - 0.03, zh, TRIM)
            box_into(bt, side * (HW - 0.010), side * (HW + 0.006), lo, hi, zl, zl + 0.03, TRIM)
            # The latches on the upper sash.
            for yy in (lo + 0.12, hi - 0.12):
                box_into(bt, side * (HW - 0.004), side * (HW + 0.012), yy - 0.03, yy + 0.03, zb + 0.03, zb + 0.06, CHROME)
    # Three black rub rails down both flanks (broken by the arches and the door), and one under
    # the windows.
    for side in (1.0, -1.0):
        for z in (0.62, 0.98, 1.34):
            spans = [(tail + 0.15, s["rear_axle"] - s["arch_r"] - 0.08),
                     (s["rear_axle"] + s["arch_r"] + 0.08, s["front_axle"] - s["arch_r"] - 0.08),
                     (s["front_axle"] + s["arch_r"] + 0.08, nose - 0.18)]
            for a, b in spans:
                if side > 0:
                    # The door gap.
                    d0, d1 = dz[0][2] - 0.04, dz[0][1] + 0.04
                    if b > d0:
                        if a < d0:
                            box_into(bt, side * HW, side * (HW + 0.035), a, d0, z - 0.045, z + 0.045, TRIM)
                        if b > d1:
                            box_into(bt, side * HW, side * (HW + 0.035), d1, b, z - 0.045, z + 0.045, TRIM)
                        continue
                if z < 0.7 and (a < s["front_axle"] < b or a < s["rear_axle"] < b):
                    continue
                box_into(bt, side * HW, side * (HW + 0.035), a, b, z - 0.045, z + 0.045, TRIM)
        # The drip rail over the windows.
        box_into(bt, side * (HW - 0.01), side * (HW + 0.02), tail + 0.3, nose - 0.3, 2.60, 2.63, TRIM)
    # The windscreen's centre post and its black surround; the sign band's frame.
    box_into(bt, -0.045, 0.045, face_f - 0.06, face_f - 0.01, 1.20, 2.52, TRIM)
    box_into(bt, -1.12, 1.12, face_f - 0.05, face_f - 0.012, 2.52, 2.56, TRIM)
    # Black bumpers wrapping the corners.
    wrap_band(bt, surf, 1.0, 0.46, 0.74, 0.060, TRIM, reach=0.30, corner_r=0.25, thickness=0.08)
    wrap_band(bt, surf, -1.0, 0.46, 0.74, 0.060, TRIM, reach=0.30, corner_r=0.25, thickness=0.08)
    tidy(bt)
    parts.append(new_object("trims", bt))

    # --- lamps ------------------------------------------------------------------------------------
    bl = bmesh.new()

    def face_y(end, x, z):
        loc, _n = surf.end_hit(x, z, end)
        return loc.y if loc is not None else (nose if end > 0 else tail)
    for end in (1.0, -1.0):
        for side in (1.0, -1.0):
            # The eight-way warning lamps over the screen / the rear windows, in black visors:
            # amber inboard, red outboard.
            for xc, mat in ((0.62, AMBER), (0.90, LIGHT_R)):
                z = 2.67
                y = face_y(end, side * xc, z)
                end_panel(bl, surf, end, side * (xc - 0.14), side * (xc + 0.14), z - 0.14, z + 0.14, 0.010, TRIM, rows=1, cols=2, thickness=0.03)
                disc_lamp(bl, side * xc, y + end * 0.02, z, 0.105, mat, end)
                box_into(bl, side * (xc - 0.13), side * (xc + 0.13), (y + end * 0.02) if end > 0 else (y + end * 0.12),
                         (y + end * 0.12) if end > 0 else (y + end * 0.02), z + 0.11, z + 0.13, TRIM)
        # The sign panel between them: yellow, its black letters (below).
        end_panel(bl, surf, end, -0.44, 0.44, 2.58, 2.78, 0.008, PAINT, rows=1, cols=3, thickness=0.02)
    for side in (1.0, -1.0):
        # Headlamps: a pair of rounded-rectangle lamps in a black pod low on each side of the face.
        end_panel(bl, surf, 1.0, side * 0.62, side * 1.12, 0.74, 0.98, 0.012, TRIM, thickness=0.03)
        for xc in (0.76, 0.98):
            disc_lamp(bl, side * xc, face_y(1.0, side * xc, 0.86) + 0.012, 0.86, 0.085, LIGHT_F, 1.0)
        end_panel(bl, surf, 1.0, side * 0.50, side * 0.60, 0.78, 0.94, 0.016, AMBER, thickness=0.02)
        # Tail: the stacked stop, turn and reversing lamps on each rear corner.
        end_panel(bl, surf, -1.0, side * 0.92, side * 1.16, 0.84, 1.48, 0.010, TRIM, rows=3, cols=2, thickness=0.03)
        for kk, (z, mat) in enumerate(((1.36, LIGHT_R), (1.14, AMBER), (0.94, LIGHT_F))):
            disc_lamp(bl, side * 1.04, face_y(-1.0, side * 1.04, z) - 0.010, z, 0.090, mat, -1.0)
        # Amber side markers and the strobe-free clearance lamps along the flanks.
        for y in (4.4, 0.6, -3.4):
            box_into(bl, side * HW, side * (HW + 0.02), y - 0.06, y + 0.06, 0.80, 0.86, AMBER)
        for y in (5.6, -5.7):
            box_into(bl, side * (HW - 0.06), side * (HW - 0.02), y - 0.05, y + 0.05, 2.86, 2.90, AMBER if y > 0 else LIGHT_R)
    # The grille: a black louvred panel low in the face (the radiator is up front on a Type D).
    yg = face_y(1.0, 0.0, 0.85)
    rc.eggcrate(bl, -0.42, 0.42, 0.70, 1.05, yg - 0.012, yg + 0.004, 12, 4, thick=0.012)
    end_panel(bl, surf, 1.0, -0.44, 0.44, 0.68, 1.07, -0.006, TRIM, rows=2, cols=4)
    parts.append(new_object("lamps", bl))

    # --- lettering --------------------------------------------------------------------------------
    parts.append(text_obj("SCHOOL BUS", 0.118, TRIM, ROT_FRONT, Vector((0.0, face_y(1.0, 0.0, 2.68) + 0.032, 2.68))))
    parts.append(text_obj("SCHOOL BUS", 0.118, TRIM, ROT_REAR, Vector((0.0, face_y(-1.0, 0.0, 2.68) - 0.032, 2.68))))
    for side, rot in ((1.0, ROT_KERB), (-1.0, ROT_STREET)):
        parts.append(text_obj(DISTRICT, 0.16, TRIM, rot, Vector((side * (HW + 0.004), -0.6, 1.16))))
    parts.append(text_obj("EMERGENCY DOOR", 0.065, TRIM, ROT_REAR, Vector((0.0, face_t - 0.006, 2.53))))
    parts.append(text_obj("STOP WHEN RED LIGHTS FLASH", 0.07, TRIM, ROT_REAR, Vector((0.0, face_t - 0.006, 1.50))))

    # --- the STOP arm (folded against the driver's side) and the crossing arm ---------------------
    sa = bmesh.new()
    cx, cz = 4.25, 1.98
    r_oct = 0.25
    oct_pts = [(cx + r_oct * math.cos(math.radians(22.5 + 45.0 * i)), cz + r_oct * math.sin(math.radians(22.5 + 45.0 * i))) for i in range(8)]
    # The red octagon plate (paint slot would take the yellow: it is a light_rear lens-red plate).
    xo = -(HW + 0.07)
    vf = [sa.verts.new((xo, y, z)) for y, z in oct_pts]
    vb = [sa.verts.new((xo + 0.012, y, z)) for y, z in oct_pts]
    f = sa.faces.new(vf)
    f.material_index = LIGHT_R
    f = sa.faces.new(list(reversed(vb)))
    f.material_index = LIGHT_R
    for i in range(8):
        quad(sa, vf[i], vf[(i + 1) % 8], vb[(i + 1) % 8], vb[i], LIGHT_R)
    # Its hinge box on the body and the two lamps.
    box_into(sa, -(HW + 0.07), -HW, cx + 0.28, cx + 0.42, cz - 0.20, cz + 0.20, TRIM)
    # The arm's two red lamps, top and bottom of the octagon.
    for dzz in (0.19, -0.19):
        box_into(sa, xo - 0.03, xo, cx - 0.04, cx + 0.04, cz + dzz - 0.04, cz + dzz + 0.04, LIGHT_R)
    tidy(sa)
    parts.append(new_object("stop_arm", sa))
    parts.append(text_obj("STOP", 0.13, LIGHT_F, ROT_STREET, Vector((xo - 0.002, cx, cz))))
    ca = bmesh.new()
    # The crossing arm: a hinge pod on the bumper's kerb corner and the yellow bar folded across it.
    yb = face_y(1.0, 0.9, 0.60) + 0.09
    box_into(ca, 0.80, 1.05, yb - 0.04, yb + 0.06, 0.50, 0.70, TRIM)
    box_into(ca, -0.70, 0.86, yb + 0.06, yb + 0.10, 0.58, 0.62, PAINT)
    tidy(ca)
    parts.append(new_object("cross_arm", ca))

    # --- mirrors: the big crossview mirrors on the front corners and the side mirrors ---------------
    mb = bmesh.new()
    for side in (1.0, -1.0):
        root = (side * 1.15, nose - 0.20, 2.40)
        elbow = (side * 1.36, nose + 0.18, 2.55)
        head_c = (side * 1.42, nose + 0.26, 2.05)
        tube(mb, [root, elbow, (head_c[0], head_c[1], head_c[2] + 0.30)], 0.020, TRIM)
        box_into(mb, head_c[0] - 0.09, head_c[0] + 0.09, head_c[1] - 0.05, head_c[1] + 0.05,
                 head_c[2] - 0.26, head_c[2] + 0.26, TRIM)
        box_into(mb, head_c[0] - 0.075, head_c[0] + 0.075, head_c[1] - 0.056, head_c[1] - 0.05,
                 head_c[2] - 0.23, head_c[2] + 0.23, CHROME)
        # The crossview mirror: a black dome on a stalk low at each front corner.
        tube(mb, [(side * 1.05, nose + 0.02, 1.15), (side * 1.32, nose + 0.32, 1.32)], 0.016, TRIM, n=6)
        box_into(mb, side * 1.36 - 0.11, side * 1.36 + 0.11, nose + 0.31, nose + 0.41, 1.27, 1.45, TRIM)
        tube(mb, [(side * 1.05, nose + 0.015, 1.25), (side * 0.50, nose - 0.02, 2.30)], 0.010, TRIM, n=6)
    parts.append(new_object("mirrors", mb))
    # Roof hatches (two emergency hatches) and the roof's centre seam.
    hb = bmesh.new()
    for y in (2.3, -2.6):
        box_into(hb, -0.42, 0.42, y - 0.42, y + 0.42, 2.94, 3.00, TRIM)
        box_into(hb, -0.36, 0.36, y - 0.36, y + 0.36, 3.00, 3.03, CHROME)
    tidy(hb)
    parts.append(new_object("hatches", hb))

    # --- panel lines ------------------------------------------------------------------------------
    paths = []
    for side in (1.0, -1.0):
        for y in (3.0, 0.4, -1.8, -4.2):
            paths.append(surface_path(surf, "side", [(y, 0.45), (y, 1.40)], side, step=0.04))
    # The emergency door's outline at the back.
    paths.append(surface_path(surf, "rear", [(-0.42, 0.50), (-0.42, 2.52), (0.42, 2.52), (0.42, 0.50)], 1.0))
    cut_grooves(body, [p for p in paths if len(p) > 2])

    # --- the entrance door: two glazed leaves folded shut, each its own node on its hinge ---------
    s["door_nodes"] = []
    for name, y0, y1 in dz:
        half = (y0 - y1) * 0.5
        for kk, (ya, yb2) in enumerate(((y0, y0 - half), (y0 - half, y1))):
            leaf = bmesh.new()
            hinge_y = ya if kk == 0 else yb2
            x0, x1 = HW - 0.04, HW - 0.005
            lo, hi = min(ya, yb2) + 0.006, max(ya, yb2) - 0.006
            box_into(leaf, x0, x1, lo, hi, fz0, fz1 - 0.02, PAINT)
            for zg0, zg1 in ((1.32, fz1 - 0.12), (0.52, 1.20)):
                pts = [Vector((x1 + 0.002, lo + 0.05 + (hi - lo - 0.10) * c / 2, zg0 + (zg1 - zg0) * r))
                       for r in range(2) for c in range(3)]
                oriented_grid(leaf, pts, [Vector((1, 0, 0))] * len(pts), 2, 3, GLASS_DOOR)
            stile_y = lo if kk == 0 else hi
            box_into(leaf, x1 - 0.01, x1 + 0.012, stile_y - 0.015, stile_y + 0.015, fz0, fz1 - 0.02, GLASS_DOOR)
            tidy(leaf)
            ob = new_object("door_%s%s" % (name, "ab"[kk]), leaf)
            ob.data.transform(Matrix.Translation((-x1, -hinge_y, -fz0)))
            ob.location = (x1, hinge_y, fz0)
            s["door_nodes"].append(ob)
    for o in s["door_nodes"]:
        o.data.calc_loop_triangles()
        log("door %-8s %5d triangles" % (o.name, len(o.data.loop_triangles)))


rc.SPECS["school_bus"] = school_bus


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = [a for a in argv if not a.startswith("--")] or ["school_bus"]
    do_render = "--render" in argv
    detail = "--nodetail" not in argv
    only_views = os.environ.get("VIEWS", "")
    for name in names:
        spec = rc.SPECS[name]()
        ob = bv.build(spec, detail)
        doors = spec.get("door_nodes", [])
        far = bv.build_far(ob, spec, doors)
        far.data.calc_loop_triangles()
        bv.report(ob, spec, far)
        print("   far twin: %d triangles" % len(far.data.loop_triangles))
        used = sorted({ob.data.materials[p.material_index].name for p in ob.data.polygons})
        print("   slots used: %s" % used)
        if "--noexport" not in argv:
            path = os.path.join(OUT_DIR, "road_%s.glb" % name)
            bv.export([ob] + list(doors) + [far], path)
            print("wrote", path)
        bpy.data.objects.remove(far, do_unlink=True)
        if do_render:
            views = bv.big_views(spec)
            if only_views:
                views = [v for v in views if v[0] in only_views.split(",")]
            wh = bv.far_wheel_set(spec, 24)
            render_obj = join([ob, wh] + list(doors))
            rc.render_previews(render_obj, name, views, paint=(0.98, 0.68, 0.04))


if __name__ == "__main__":
    main()
