#!/usr/bin/env python3
"""The big vehicles in traffic: a 40 ft city bus, a box truck, a semi tractor and its 53 ft
trailer, built in Blender from code with tools/make_road_cars.py's pipeline (its profile-curve
loft, booleans, raycast parts, the seven material slots and the far twin):

    tools/road_cars_setup.sh                     # once: Blender 4.2 LTS into build/car_src/
    build/car_src/blender/blender-4.2.23-linux-x64/blender -b --factory-startup \\
        -P tools/make_big_vehicles.py -- bus box_truck semi [--render] [--nodetail]

Writes assets/models/road_<name>.glb, then run `godot --headless --path . --import` (CLAUDE.md,
measurement trap 1). `--render` writes Cycles previews to $RENDER_DIR like make_road_cars.py.

What is the same as the cars (read make_road_cars.py's docstring first): X lateral, Y along the
vehicle with the NOSE AT +Y, Z up, ground at Z = 0; the slots are bound by name in
Vehicle._add_body_model(); `paint` takes the car paint shader (and its livery stripes), `glass`
the cabin glass (CarCabin); no wheels in the full model (Vehicle draws generated truck wheels,
BigVehicles.wheel_mesh(), in the arches) and a `<name>_far` twin with a baked far wheel in every
arch. What is new:

  * An eighth slot, `sign`: the bus's destination signs (front, kerb side, rear), drawn by
    shaders/bus_sign.gdshader from the route's text. The run prints their rects in body space.
  * Extra nodes the game moves: the bus's door leaves (`door_fa`, `door_fb` front, `door_ra`,
    `door_rb` rear, each a mesh whose node origin is its hinge) and the semi's trailer
    (`road_semi_trailer` + `road_semi_trailer_far`, its origin at the kingpin). The far twins
    carry the doors closed and the trailer straight.
  * The box truck's box and the trailer are boxes with their own detail (posts, rails, the
    roll-up and swing doors, lamps); only the cabs and the bus are lofted.

Original designs, generic classes, no manufacturer's or agency's shapes, names or badges.
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_road_cars as rc  # noqa: E402

from make_road_cars import (  # noqa: E402
    PAINT, GLASS, TRIM, CHROME, TYRE, LIGHT_F, LIGHT_R, ramp, log, new_object, boolean, quad,
    add_box, tidy, grid_solid, oriented_grid, applied, hits_2d, rect_grid, mirror2,
    extrude_cutter, rounded_outline, eggcrate, surface_path, cut_grooves, sweep, wrap_band,
    circle_path, apply_modifiers, subsurf, join, shade, region_grid,
)

# The destination signs' slot, appended to the cars' seven (a car file never has it).
rc.SLOTS.append(("sign", (0.012, 0.010, 0.008), 0.0, 0.25, 0.0))
SIGN = len(rc.SLOTS) - 1
# Door glass that does NOT take the cabin glass: a door leaf moves, and the cabin trace works in
# the body mesh's own space. Plain dark glass (the model's own material in the game).
rc.SLOTS.append(("glass_door", (0.020, 0.024, 0.028), 0.0, 0.05, 0.0))
GLASS_DOOR = len(rc.SLOTS) - 1

OUT_DIR = rc.OUT_DIR

# The cars' probes start their rays 3-5 m out, which is inside a 12 m bus or a 4 m trailer.
rc.Surface.end_hit = lambda self, x, z, end: self.ray((x, end * 14.0, z), (0.0, -end, 0.0), 20.0)
rc.Surface.side_hit = lambda self, y, z, side=1.0: self.ray((side * 4.0, y, z), (-side, 0.0, 0.0), 8.0)
rc.Surface.top_hit = lambda self, x, y: self.ray((x, y, 7.0), (0.0, 0.0, -1.0), 9.0)


# --- shared helpers -------------------------------------------------------------------------------

def bevel_box(name, size, loc, mat, width=0.03, segments=2):
    """A box with rounded edges as its own object (one subdivision-free bevel)."""
    bm = bmesh.new()
    add_box(bm, size, loc, mat)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = new_object(name, bm)
    if width > 0.0:
        mod = ob.modifiers.new("bev", 'BEVEL')
        mod.width = width
        mod.segments = segments
        mod.limit_method = 'ANGLE'
        apply_modifiers(ob)
    return ob


def box_into(bm, x0, x1, y0, y1, z0, z1, mat):
    add_box(bm, (abs(x1 - x0), abs(y1 - y0), abs(z1 - z0)),
            ((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5), mat)


def tube(bm, path, r, mat, n=8, caps=True):
    prof = [(math.cos(2 * math.pi * k / n) * r, math.sin(2 * math.pi * k / n) * r) for k in range(n)]
    sweep(bm, [Vector(p) for p in path], prof, mat, caps=caps)


def disc_lamp(bm, x, y, z, r, mat, facing, depth=0.02, n=14, rim_mat=None):
    """A round lamp lens on a face looking along `facing` (+1 nose, -1 tail; or 'x+' / 'x-'),
    with a short black bezel behind it."""
    pts = []
    for k in range(n):
        a = 2 * math.pi * k / n
        pts.append((math.cos(a) * r, math.sin(a) * r))
    if facing in (1.0, -1.0):
        front = [bm.verts.new((x + a, y + facing * depth, z + b)) for a, b in pts]
        back = [bm.verts.new((x + a * 1.15, y, z + b * 1.15)) for a, b in pts]
    else:
        s = 1.0 if facing == "x+" else -1.0
        front = [bm.verts.new((x + s * depth, y + a, z + b)) for a, b in pts]
        back = [bm.verts.new((x, y + a * 1.15, z + b * 1.15)) for a, b in pts]
    f = bm.faces.new(front)
    f.material_index = mat
    for k in range(n):
        k2 = (k + 1) % n
        quad(bm, front[k], front[k2], back[k2], back[k], rim_mat if rim_mat is not None else TRIM)


def far_wheel_set(spec, segs=14):
    """The far twin's wheels for a big vehicle: `spec["axles"]` is a list of (y, dual) and every
    axle gets a tyre each side (two, side by side, on a dual axle), a little inside the generated
    wheel so the two never fight between the hand-over and the generated wheel's cut-off."""
    bm = bmesh.new()
    r = spec["wheel_r"] * 0.97
    w = spec["wheel_w"] * 0.88
    for y, dual in spec["axles"]:
        for side in (1.0, -1.0):
            if dual:
                for k in (0, 1):
                    x = side * (spec["dual_x"] + (0.5 - k) * spec["dual_gap"])
                    rc.far_wheel(bm, x, y, spec["axle_z"], r, w, side, segs)
            else:
                rc.far_wheel(bm, side * spec["wheel_x"], y, spec["axle_z"], r, w, side, segs)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object("far_wheels", bm)


def arch_cutter(spec):
    """One arch per axle: a blind pocket from inside the wheel to past the body, like the cars'."""
    bm = bmesh.new()
    for y, dual in spec["axles"]:
        R = spec["arch_r"]
        az = spec["axle_z"]
        x_in = spec["arch_in_dual"] if dual else spec["arch_in"]
        for side in (1.0, -1.0):
            prof = [(y + R, -0.3)]
            n = 32
            for k in range(n + 1):
                a = math.pi * k / n
                prof.append((y + R * math.cos(a), az + R * math.sin(a)))
            prof.append((y - R, -0.3))
            xa, xb = (x_in, 1.8) if side > 0 else (-1.8, -x_in)
            ra = [bm.verts.new((xa, f, z)) for f, z in prof]
            rb = [bm.verts.new((xb, f, z)) for f, z in prof]
            for k in range(len(prof) - 1):
                quad(bm, ra[k], ra[k + 1], rb[k + 1], rb[k], TRIM)
            quad(bm, ra[-1], ra[0], rb[0], rb[-1], TRIM)
            bm.faces.new(ra).material_index = TRIM
            bm.faces.new(list(reversed(rb))).material_index = TRIM
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object("cut_arch", bm)


def side_cutter(outline, side, x_in, x_out=1.9, mat=TRIM):
    """A prism across the car from x_in outward on one side, its outline drawn in side view
    (y, z): a door opening, a window."""
    bm = bmesh.new()
    xa, xb = (x_in, x_out) if side > 0 else (-x_out, -x_in)
    ra = [bm.verts.new((xa, a, b)) for a, b in outline]
    rb = [bm.verts.new((xb, a, b)) for a, b in outline]
    n = len(outline)
    for k in range(n):
        k2 = (k + 1) % n
        quad(bm, ra[k], ra[k2], rb[k2], rb[k], mat)
    bm.faces.new(ra).material_index = mat
    bm.faces.new(list(reversed(rb))).material_index = mat
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object("cut_side", bm)


def side_panel(bm, surf, y0, y1, z0, z1, proud, mat, side, rows=2, cols=None, thickness=0.0):
    """A flat part laid on a side over the side-view rectangle (y0..y1, z0..z1)."""
    cols = cols or max(2, int(abs(y1 - y0) / 0.3))
    g = [[(y0 + (y1 - y0) * c / cols, z0 + (z1 - z0) * r / rows) for c in range(cols + 1)]
         for r in range(rows + 1)]
    return applied(bm, surf, "side", g, proud, mat, side, thickness=thickness)


def end_panel(bm, surf, end, x0, x1, z0, z1, proud, mat, rows=2, cols=4, thickness=0.0):
    view = "front" if end > 0 else "rear"
    return applied(bm, surf, view, rect_grid(x0, x1, z0, z1, rows, cols), proud, mat,
                   thickness=thickness)


def sign_rect(name, lo, hi, report):
    """Remembers a destination sign's box (model space) for the report."""
    report.append((name, tuple(lo), tuple(hi)))


# --- the bus ---------------------------------------------------------------------------------------

def bus():
    """A 40 ft low-floor city bus: a flat, slightly domed face with one tall windscreen and the
    destination sign over it, a long box body with tight roof edges (the van's ninth anchor and
    pinned tangents), a window band down both sides, two plug doors on the kerb side (+x, the
    front one ahead of the front axle, the rear one between the axles), the engine at the back
    under a small high rear window, a roof pod over the front axle."""
    L = 12.19
    s = {"name": "bus", "length": L, "height": 3.25}
    s.update({
        "nose": 6.095, "tail": -6.095,
        "front_axle": 3.70, "rear_axle": -3.15, "axle_z": 0.500,
        "axles": [(3.70, False), (-3.15, True)],
        "wheel_r": 0.500, "wheel_w": 0.300, "wheel_x": 1.035,
        "dual_x": 0.935, "dual_gap": 0.330,
        "arch_r": 0.585, "arch_r_rear": 0.585, "arch_in": 0.64, "arch_in_dual": 0.58,
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
        "tangent_over": {5: (0.0, 1.0), 6: (-0.12, 1.0), 7: (-1.0, 0.0)},
        "nose_cap": {"steps": 3, "roll": lambda j: 0.085, "dome": 0.075,
                     "lean": lambda co: 0.03 * ramp(co.z, 1.6, 0.5)},
        "tail_cap": {"steps": 3, "roll": lambda j: 0.075, "dome": 0.030},
        "sculpt": [],
        "profile": {
            "top": [(6.095, 3.020), (5.95, 3.050), (-5.95, 3.050), (-6.095, 3.030)],
            "rail_z": [(6.095, 2.830), (5.95, 2.845), (-5.95, 2.845), (-6.095, 2.835)],
            "rail_w": [(6.095, 1.235), (6.00, 1.270), (5.90, 1.282), (-5.90, 1.282),
                       (-6.00, 1.270), (-6.095, 1.235)],
            "roof_z": [(6.095, 3.005), (5.95, 3.035), (-5.95, 3.035), (-6.095, 3.015)],
            "roof_w": [(6.095, 1.05), (5.95, 1.10), (-5.95, 1.10), (-6.095, 1.05)],
            "over_w": 1.0,
            "belt_z": 1.250,
            "belt_in": 0.004,
            "shoulder_z": 1.100,
            "width": [(6.095, 1.215), (6.07, 1.258), (6.02, 1.283), (5.92, 1.293),
                      (-5.92, 1.293), (-6.02, 1.283), (-6.07, 1.258), (-6.095, 1.215)],
            "low_z": 0.62,
            "low_in": 0.004,
            "sill_z": [(6.095, 0.360), (5.80, 0.330), (-5.80, 0.330), (-6.095, 0.380)],
            "sill_in": 0.030,
            "floor_z": [(6.095, 0.340), (5.80, 0.300), (-5.80, 0.300), (-6.095, 0.360)],
            "floor_in": 0.10,
        },
        # Doors on the kerb side (+x): (name, y front edge, y rear edge).
        "doors": [("f", 5.86, 4.62), ("r", -0.98, -2.22)],
        "door_z": (0.36, 2.62),
        "window_z": (1.32, 2.56),
    })
    s["details"] = bus_details
    s["signs"] = []
    return s


def bus_details(s, sec, surf, body, parts):
    zl, zh = s["window_z"]
    fz0, fz1 = s["door_z"]
    nose, tail = s["nose"], s["tail"]
    signs = s["signs"]
    # Where the (domed, rolled) end faces really are: the nose and tail stations are where the
    # loft stops, and the caps bulge past them.
    fl, _n = surf.end_hit(0.0, 1.8, 1.0)
    face_f = fl.y if fl is not None else nose + 0.1
    tl, _n = surf.end_hit(0.0, 2.4, -1.0)
    face_t = tl.y if tl is not None else tail - 0.1
    # --- openings -------------------------------------------------------------------------------
    # The windscreen and, over it, the front sign's window, in one black-framed recess.
    screen = rounded_outline([(-1.16, 0.98), (1.16, 0.98), (1.15, 2.66), (-1.15, 2.66)], 0.10)
    boolean(body, extrude_cutter(screen, "y", nose - 0.20, nose + 0.6))
    sign_hole = rounded_outline([(-1.10, 2.73), (1.10, 2.73), (1.10, 2.97), (-1.10, 2.97)], 0.05)
    boolean(body, extrude_cutter(sign_hole, "y", nose - 0.20, nose + 0.6))
    # Side window runs: (side, y front, y rear). The driver's window (-x) runs from the screen
    # pillar to the first window post; the kerb side's band is broken by the two doors.
    dz = s["doors"]
    runs = {1.0: [(dz[0][2] - 0.10, dz[1][1] + 0.10), (dz[1][2] - 0.10, tail + 0.85)],
            -1.0: [(nose - 0.28, nose - 1.40), (nose - 1.52, tail + 0.85)]}
    for side, spans in runs.items():
        for y0, y1 in spans:
            hole = rounded_outline([(y0, zl), (y1, zl), (y1, zh), (y0, zh)], 0.07)
            boolean(body, side_cutter(hole, side, 1.20), quiet=True)
    # The door openings (+x), and the kerb-side sign's window ahead of the first window post.
    for name, y0, y1 in dz:
        hole = rounded_outline([(y0, fz0 - 0.10), (y1, fz0 - 0.10), (y1, fz1), (y0, fz1)], 0.05)
        boolean(body, side_cutter(hole, 1.0, 1.10), quiet=True)
    # Rear window, high over the engine bay.
    rw = rounded_outline([(-0.95, 2.18), (0.95, 2.18), (0.95, 2.62), (-0.95, 2.62)], 0.08)
    boolean(body, extrude_cutter(rw, "y", tail - 0.6, tail + 0.20))
    rs = rounded_outline([(-0.42, 2.68), (0.42, 2.68), (0.42, 2.90), (-0.42, 2.90)], 0.04)
    boolean(body, extrude_cutter(rs, "y", tail - 0.6, tail + 0.20))

    # --- glass ----------------------------------------------------------------------------------
    gb = bmesh.new()
    sg = bmesh.new()
    # Windscreen: a flat sheet just inside the opening's mouth, raked 4 degrees back at the top.
    yf = face_f - 0.035

    def scr(x, z):
        return Vector((x, yf - (z - 0.98) * 0.07, z))
    rows, cols = 8, 10
    pts = [scr(-1.16 + 2.32 * c / cols, 0.98 + (2.66 - 0.98) * r / rows)
           for r in range(rows + 1) for c in range(cols + 1)]
    nrm = [Vector((0.0, 1.0, 0.07)).normalized()] * len(pts)
    oriented_grid(gb, pts, nrm, rows + 1, cols + 1, GLASS)
    # Rear window.
    yr = face_t + 0.035
    pts = [Vector((-0.95 + 1.90 * c / 6, yr, 2.18 + 0.44 * r / 2)) for r in range(3) for c in range(7)]
    oriented_grid(gb, pts, [Vector((0, -1, 0))] * len(pts), 3, 7, GLASS)
    # Side bands, flush with the skin less 8 mm.
    for side, spans in runs.items():
        for y0, y1 in spans:
            n = max(4, int(abs(y1 - y0) / 0.5))
            pts = [Vector((side * 1.275, y0 + (y1 - y0) * c / n, zl + (zh - zl) * r / 3))
                   for r in range(4) for c in range(n + 1)]
            oriented_grid(gb, pts, [Vector((side, 0, 0))] * len(pts), 4, n + 1, GLASS)
    # The signs: flush panels in their windows (front, rear) and one on the kerb side, in the
    # first window behind the front door (its top third).
    pts = [Vector((-1.10 + 2.20 * c / 8, face_f - 0.03, 2.73 + 0.24 * r / 1)) for r in range(2) for c in range(9)]
    oriented_grid(sg, pts, [Vector((0, 1, 0))] * len(pts), 2, 9, SIGN)
    sign_rect("front", (-1.10, face_f - 0.03, 2.73), (1.10, face_f - 0.03, 2.97), signs)
    pts = [Vector((-0.42 + 0.84 * c / 4, face_t + 0.03, 2.68 + 0.22 * r)) for r in range(2) for c in range(5)]
    oriented_grid(sg, pts, [Vector((0, -1, 0))] * len(pts), 2, 5, SIGN)
    sign_rect("rear", (-0.42, face_t + 0.03, 2.68), (0.42, face_t + 0.03, 2.90), signs)
    ys0, ys1 = dz[0][2] - 0.14, dz[0][2] - 1.24
    pts = [Vector((1.286, ys0 + (ys1 - ys0) * c / 4, 2.20 + 0.30 * r)) for r in range(2) for c in range(5)]
    oriented_grid(sg, pts, [Vector((1, 0, 0))] * len(pts), 2, 5, SIGN)
    sign_rect("side", (1.286, ys1, 2.20), (1.286, ys0, 2.50), signs)
    tidy(gb)
    parts.append(new_object("glass", gb))
    parts.append(new_object("signs", sg))

    # --- trims: window posts, the black mask round the screen, rub rails ------------------------
    bt = bmesh.new()
    for side, spans in runs.items():
        for y0, y1 in spans:
            n = max(1, int(round(abs(y1 - y0) / 1.32)))
            for k in range(1, n):
                y = y0 + (y1 - y0) * k / n
                box_into(bt, side * 1.268, side * 1.292, y - 0.045, y + 0.045, zl - 0.01, zh + 0.01, TRIM)
            # Sliding vents in the top third of every other pane.
            for k in range(0, n, 2):
                ya = y0 + (y1 - y0) * k / n
                yb = y0 + (y1 - y0) * (k + 1) / n
                box_into(bt, side * 1.276, side * 1.290, min(ya, yb) + 0.06, max(ya, yb) - 0.06,
                         zh - 0.36, zh - 0.34, TRIM)
    # The sign's black surround and the band between it and the screen.
    box_into(bt, -1.14, 1.14, face_f - 0.07, face_f - 0.025, 2.65, 2.75, TRIM)
    # Rub rails along both flanks (the lower one interrupted by the arches and the doors).
    for side in (1.0, -1.0):
        for z in (0.78,):
            stops = [(nose - 0.20, s["front_axle"] + s["arch_r"] + 0.08),
                     (s["front_axle"] - s["arch_r"] - 0.08, s["rear_axle"] + s["arch_r"] + 0.08),
                     (s["rear_axle"] - s["arch_r"] - 0.08, tail + 0.20)]
            for y0, y1 in stops:
                cuts = [(y0, y1)]
                if side > 0:
                    out = []
                    for a, b in cuts:
                        segs = [(a, b)]
                        for _n, d0, d1 in dz:
                            nxt = []
                            for p, q in segs:
                                if q < d0 + 0.05 and p > d1 - 0.05 and not (p < d1 or q > d0):
                                    pass
                                lo, hi = min(p, q), max(p, q)
                                dl, dh = min(d0, d1) - 0.05, max(d0, d1) + 0.05
                                if hi <= dl or lo >= dh:
                                    nxt.append((p, q))
                                else:
                                    if hi > dh:
                                        nxt.append((hi, dh))
                                    if lo < dl:
                                        nxt.append((dl, lo))
                            segs = nxt
                        out.extend(segs)
                    cuts = out
                for a, b in cuts:
                    if abs(a - b) > 0.2:
                        box_into(bt, side * 1.282, side * 1.318, min(a, b), max(a, b), z - 0.05, z + 0.05, TRIM)
    # Gutter strip along the roof edge over the window band.
    for side in (1.0, -1.0):
        box_into(bt, side * 1.270, side * 1.300, tail + 0.35, nose - 0.35, 2.83, 2.86, TRIM)
    # Front bumper and the rear one: black bands wrapping the corners.
    wrap_band(bt, surf, 1.0, 0.34, 0.62, 0.050, TRIM, reach=0.25, corner_r=0.25, thickness=0.07)
    wrap_band(bt, surf, -1.0, 0.36, 0.64, 0.050, TRIM, reach=0.25, corner_r=0.25, thickness=0.07)
    # Roof pod over the front axle: the air-conditioning shroud, and two hatches further back.
    tidy(bt)
    parts.append(new_object("trims", bt))
    pod = bevel_box("roof_pod", (2.10, 3.20, 0.24), (0.0, s["front_axle"] - 0.9, 3.13), PAINT,
                    width=0.08, segments=3)
    parts.append(pod)
    hb = bmesh.new()
    for y in (-0.6, -3.4):
        box_into(hb, -0.45, 0.45, y - 0.45, y + 0.45, 3.03, 3.10, TRIM)
    tidy(hb)
    parts.append(new_object("hatches", hb))

    # --- lamps ------------------------------------------------------------------------------------
    bl = bmesh.new()

    def face_y(end, x, z):
        loc, _n = surf.end_hit(x, z, end)
        return loc.y if loc is not None else (nose if end > 0 else tail)
    for side in (1.0, -1.0):
        # Twin round headlamps in a black pod each side under the screen, an amber indicator
        # inboard of them.
        end_panel(bl, surf, 1.0, side * 0.70, side * 1.13, 0.66, 0.90, 0.012, TRIM, thickness=0.03)
        for xc in (0.81, 1.01):
            disc_lamp(bl, side * xc, face_y(1.0, side * xc, 0.78) + 0.012, 0.78, 0.072, LIGHT_F, 1.0)
        end_panel(bl, surf, 1.0, side * 0.56, side * 0.67, 0.70, 0.86, 0.016, LIGHT_F, thickness=0.02)
        # Clearance lamps at the top corners of the face and down the flanks.
        end_panel(bl, surf, 1.0, side * 0.96, side * 1.06, 2.88, 2.92, 0.01, LIGHT_R, rows=1, cols=2)
        for y in (3.0, 0.0, -3.0, -5.6):
            box_into(bl, side * 1.293, side * 1.31, y - 0.05, y + 0.05, 0.92, 0.96, LIGHT_R)
        # Tail: a vertical stack of round lamps in a black strip on each rear corner.
        end_panel(bl, surf, -1.0, side * 0.96, side * 1.18, 0.80, 1.85, 0.010, TRIM, rows=4, cols=2, thickness=0.03)
        for k, z in enumerate((1.70, 1.46, 1.22, 0.98)):
            disc_lamp(bl, side * 1.07, face_y(-1.0, side * 1.07, z) - 0.010, z, 0.082,
                      LIGHT_F if k == 2 else LIGHT_R, -1.0)
    # High brake lamp under the rear sign.
    end_panel(bl, surf, -1.0, -0.30, 0.30, 2.95, 3.0, 0.008, LIGHT_R, rows=1, cols=3)
    # Engine-bay louvres low on the rear (a grille in a shallow black recess).
    yr = face_y(-1.0, 0.0, 1.1)
    eggcrate(bl, -0.85, 0.85, 0.72, 1.55, yr - 0.012, yr + 0.004, 16, 6, thick=0.012)
    end_panel(bl, surf, -1.0, -0.87, 0.87, 0.70, 1.57, -0.006, TRIM, rows=2, cols=6)
    parts.append(new_object("lamps", bl))

    # --- mirrors: tall stalks off the front corners, heads ahead of the screen ---------------------
    mb = bmesh.new()
    for side in (1.0, -1.0):
        root = (side * 1.20, nose - 0.25, 2.55)
        elbow = (side * 1.36, nose + 0.22, 2.70)
        head_c = (side * 1.42, nose + 0.32, 2.20)
        tube(mb, [root, elbow, (head_c[0], head_c[1], head_c[2] + 0.30)], 0.020, TRIM)
        box_into(mb, head_c[0] - 0.09, head_c[0] + 0.09, head_c[1] - 0.05, head_c[1] + 0.05,
                 head_c[2] - 0.28, head_c[2] + 0.28, TRIM)
        box_into(mb, head_c[0] - 0.075, head_c[0] + 0.075, head_c[1] - 0.056, head_c[1] - 0.05,
                 head_c[2] - 0.25, head_c[2] + 0.25, CHROME)
        # The wipers parked down the screen's edges.
        tube(mb, [(side * 1.05, nose + 0.015, 1.05), (side * 0.55, nose - 0.02, 2.35)], 0.010, TRIM, n=6)
    # A folded bike rack across the bumper.
    for x in (-0.55, 0.55):
        tube(mb, [(x, nose + 0.06, 0.62), (x, nose + 0.12, 1.00), (x * 0.4, nose + 0.12, 1.00)], 0.018, CHROME, n=6)
    tube(mb, [(-0.62, nose + 0.12, 0.98), (0.62, nose + 0.12, 0.98)], 0.018, CHROME, n=6)
    parts.append(new_object("mirrors", mb))

    # --- panel lines -----------------------------------------------------------------------------
    paths = []
    for side in (1.0, -1.0):
        # Skirt panels: the joint line along the flank under the windows and the vertical seams.
        paths.append(surface_path(surf, "side", [(nose - 0.35, 1.18), (tail + 0.35, 1.18)], side, step=0.04))
        for y in (2.2, -0.0 if side < 0 else -2.6, -4.6):
            paths.append(surface_path(surf, "side", [(y, 0.40), (y, 1.18)], side, step=0.04))
    # The engine-bay doors at the back.
    paths.append(surface_path(surf, "rear", [(-1.10, 0.66), (-1.10, 1.95), (1.10, 1.95), (1.10, 0.66)], 1.0))
    paths.append(surface_path(surf, "rear", [(0.0, 0.66), (0.0, 1.95)], 1.0))
    cut_grooves(body, [p for p in paths if len(p) > 2])

    # --- the doors: two leaves per opening, each its own node with its origin on its hinge --------
    s["door_nodes"] = []
    for name, y0, y1 in dz:
        half = (y0 - y1) * 0.5
        for k, (ya, yb) in enumerate(((y0, y0 - half), (y0 - half, y1))):
            leaf = bmesh.new()
            hinge_y = ya if k == 0 else yb
            # Frame: a slab of paint with the glass panes set into its outer face.
            x0, x1 = 1.255, 1.292
            lo, hi = min(ya, yb) + 0.006, max(ya, yb) - 0.006
            box_into(leaf, x0, x1, lo, hi, fz0, fz1 - 0.02, PAINT)
            # Upper glass and lower smoked panel, black rubber edge down the meeting stile.
            for zg0, zg1, mat in ((1.30, fz1 - 0.12, GLASS_DOOR), (0.48, 1.18, GLASS_DOOR)):
                pts = [Vector((x1 + 0.002, lo + 0.06 + (hi - lo - 0.12) * c / 2, zg0 + (zg1 - zg0) * r))
                       for r in range(2) for c in range(3)]
                oriented_grid(leaf, pts, [Vector((1, 0, 0))] * len(pts), 2, 3, mat)
            stile_y = lo if k == 0 else hi
            # The rubber down the meeting stile and a grab bar inside, in the dark glass's slot: a
            # leaf is its own node, and two surfaces (paint, glass) keep it two draws.
            box_into(leaf, x1 - 0.01, x1 + 0.012, stile_y - 0.015, stile_y + 0.015, fz0, fz1 - 0.02, GLASS_DOOR)
            tube(leaf, [(x0 - 0.03, (lo + hi) * 0.5, 0.9), (x0 - 0.03, (lo + hi) * 0.5, 2.2)], 0.016, GLASS_DOOR, n=6)
            tidy(leaf)
            ob = new_object("door_%s%s" % (name, "ab"[k]), leaf)
            # Origin on the hinge (the leaf's outer edge, at the opening's edge, skin side).
            ob.data.transform(__import__("mathutils").Matrix.Translation((-x1, -hinge_y, -fz0)))
            ob.location = (x1, hinge_y, fz0)
            s["door_nodes"].append(ob)
    for o in s["door_nodes"]:
        o.data.calc_loop_triangles()
        log("door %-8s %5d triangles" % (o.name, len(o.data.loop_triangles)))


rc.SPECS["bus"] = bus


# --- cargo boxes (the box truck's body and the semi's trailer) ------------------------------------

def cargo_box(name, y_front, y_rear, z0, z1, hw, rear="rollup", marker_step=3.0, rail_z=None):
    """A van body: a bevelled shell in the paint slot (the livery goes on it), aluminium corner
    posts, top and bottom rails, a front cap rail, marker lamps along the top, a rear frame with
    the doors (`rear` "rollup": a roll-up door of 30 cm slats with a handle; "swing": two swing
    doors with four lock rods and hinges), tail lamps in the rear sill and a rub rail.
    Returns [shell, trims, lamps] as objects."""
    L = y_front - y_rear
    ym = (y_front + y_rear) * 0.5
    shell = bevel_box(name + "_shell", (hw * 2.0, L, z1 - z0), (0.0, ym, (z0 + z1) * 0.5), PAINT,
                      width=0.035, segments=2)
    bt = bmesh.new()
    al = CHROME
    e = 0.012
    # Corner posts on the four vertical edges, rails along the top and the bottom.
    for sx in (1.0, -1.0):
        for y in (y_front, y_rear):
            sy = 1.0 if y == y_front else -1.0
            box_into(bt, sx * (hw - 0.04), sx * (hw + e), y - sy * 0.07, y + sy * e, z0 - 0.01, z1 + 0.01, al)
        box_into(bt, sx * (hw - 0.01), sx * (hw + e), y_rear + 0.05, y_front - 0.05, z1 - 0.10, z1 + 0.01, al)
        box_into(bt, sx * (hw - 0.01), sx * (hw + e + 0.004), y_rear + 0.05, y_front - 0.05, z0 - 0.02, z0 + 0.14, al)
        # Scuff band along the bottom and the vertical posts (logistics posts) every 1.2 m.
        n = max(2, int(L / 1.2))
        for k in range(1, n):
            y = y_rear + L * k / n
            box_into(bt, sx * (hw - 0.005), sx * (hw + 0.006), y - 0.025, y + 0.025, z0 + 0.14, z1 - 0.10, al)
        if rail_z is not None:
            box_into(bt, sx * (hw - 0.005), sx * (hw + 0.010), y_rear + 0.1, y_front - 0.1, rail_z - 0.04, rail_z + 0.04, al)
    for y, sy in ((y_front, 1.0), (y_rear, -1.0)):
        box_into(bt, -hw - e, hw + e, y - sy * 0.04, y + sy * e, z1 - 0.10, z1 + 0.01, al)
        box_into(bt, -hw - e, hw + e, y - sy * 0.04, y + sy * (e + 0.004), z0 - 0.02, z0 + 0.10, al)
    # Rear frame and doors.
    yr = y_rear
    box_into(bt, -hw - e, -hw + 0.10, yr - 0.03, yr + 0.02, z0, z1, al)
    box_into(bt, hw - 0.10, hw + e, yr - 0.03, yr + 0.02, z0, z1, al)
    box_into(bt, -hw, hw, yr - 0.03, yr + 0.02, z1 - 0.20, z1, al)
    box_into(bt, -hw, hw, yr - 0.05, yr + 0.02, z0, z0 + 0.16, al)
    dz0, dz1 = z0 + 0.16, z1 - 0.20
    dx = hw - 0.10
    if rear == "rollup":
        n = int((dz1 - dz0) / 0.30)
        for k in range(n):
            za = dz0 + (dz1 - dz0) * k / n
            zb = dz0 + (dz1 - dz0) * (k + 1) / n
            box_into(bt, -dx, dx, yr - 0.022, yr - 0.004, za + 0.008, zb - 0.008, PAINT)
            box_into(bt, -dx, dx, yr - 0.012, yr + 0.0, zb - 0.010, zb + 0.010, TRIM)
        box_into(bt, -0.14, 0.14, yr - 0.05, yr - 0.02, dz0 + 0.12, dz0 + 0.17, al)
    else:
        for side in (1.0, -1.0):
            box_into(bt, side * 0.006, side * dx, yr - 0.024, yr - 0.004, dz0, dz1, PAINT)
            for k, xr in enumerate((0.28, 0.82)):
                x = side * xr * dx
                tube(bt, [(x, yr - 0.045, dz0 + 0.06), (x, yr - 0.045, dz1 - 0.06)], 0.014, al, n=6)
                for zc in (dz0 + 0.45, dz1 - 0.45):
                    box_into(bt, x - 0.03, x + 0.03, yr - 0.06, yr - 0.03, zc - 0.05, zc + 0.05, al)
            for zc in (dz0 + 0.25, (dz0 + dz1) * 0.5, dz1 - 0.25):
                box_into(bt, side * (dx - 0.03), side * (dx + 0.06), yr - 0.05, yr - 0.02, zc - 0.07, zc + 0.07, al)
        box_into(bt, -0.008, 0.008, yr - 0.03, yr - 0.004, dz0, dz1, TRIM)
    tidy(bt)
    trims = new_object(name + "_trims", bt)
    bl = bmesh.new()
    # Marker lamps: amber along the sides (red at the back), three clearance lamps at the top of
    # the rear frame, tail lamps set into the rear sill.
    n = max(2, int(L / marker_step))
    for sx in (1.0, -1.0):
        for k in range(n + 1):
            y = y_front - 0.15 - (L - 0.3) * k / n
            box_into(bl, sx * (hw + e), sx * (hw + e + 0.02), y - 0.04, y + 0.04, z1 - 0.07, z1 - 0.03,
                     LIGHT_R if k == n else LIGHT_F)
        box_into(bl, sx * (hw + e), sx * (hw + e + 0.02), y_rear + 0.15, y_rear + 0.25, z0 + 0.03, z0 + 0.07, LIGHT_R)
    for x in (-0.25, 0.0, 0.25):
        box_into(bl, x - 0.04, x + 0.04, yr - 0.05, yr - 0.03, z1 - 0.14, z1 - 0.08, LIGHT_R)
    for sx in (1.0, -1.0):
        for k, xc in enumerate((0.95, 0.78)):
            disc_lamp(bl, sx * (hw - 0.25 + xc - 0.95), yr - 0.05, z0 + 0.08, 0.055, LIGHT_R, -1.0)
        disc_lamp(bl, sx * (hw - 0.62), yr - 0.05, z0 + 0.08, 0.04, LIGHT_F, -1.0)
    tidy(bl)
    lamps = new_object(name + "_lamps", bl)
    return [shell, trims, lamps]


def underride(bm, y, z, hw, mat=TRIM):
    """The rear impact guard: a horizontal bar on two legs from the frame."""
    box_into(bm, -hw + 0.10, hw - 0.10, y - 0.06, y + 0.06, z - 0.06, z + 0.06, mat)
    for x in (-hw * 0.6, hw * 0.6):
        box_into(bm, x - 0.04, x + 0.04, y - 0.04, y + 0.30, z, z + 0.45, mat)


def mudflap(bm, x, y, z0, z1, w=0.55):
    box_into(bm, x - w * 0.5, x + w * 0.5, y - 0.006, y + 0.006, z0, z1, TYRE)


def frame_rails(bm, y0, y1, z, x=0.43, h=0.26):
    for sx in (1.0, -1.0):
        box_into(bm, sx * (x - 0.04), sx * (x + 0.04), min(y0, y1), max(y0, y1), z - h * 0.5, z + h * 0.5, TRIM)
    n = max(2, int(abs(y0 - y1) / 1.2))
    for k in range(n + 1):
        y = y1 + (y0 - y1) * k / n
        box_into(bm, -x, x, y - 0.03, y + 0.03, z - 0.08, z + 0.08, TRIM)


def cylinder(bm, axis_y, cx, cz, r, y0, y1, mat, n=16, axis="y"):
    """A capped cylinder along y (a fuel tank) or x."""
    ring0, ring1 = [], []
    for k in range(n):
        a = 2 * math.pi * k / n
        if axis == "y":
            ring0.append(bm.verts.new((cx + math.cos(a) * r, y0, cz + math.sin(a) * r)))
            ring1.append(bm.verts.new((cx + math.cos(a) * r, y1, cz + math.sin(a) * r)))
        else:
            ring0.append(bm.verts.new((y0, axis_y + math.cos(a) * r, cz + math.sin(a) * r)))
            ring1.append(bm.verts.new((y1, axis_y + math.cos(a) * r, cz + math.sin(a) * r)))
    for k in range(n):
        k2 = (k + 1) % n
        quad(bm, ring0[k], ring0[k2], ring1[k2], ring1[k], mat)
    bm.faces.new(ring0).material_index = mat
    bm.faces.new(list(reversed(ring1))).material_index = mat


def quarter_fender(bm, y, z_axle, r, x0, x1, mat=TRIM, a0=15.0, a1=165.0, n=12):
    """A fender arc over a wheel (or a dual), a black moulded half-shell."""
    pts = [(y + (r + 0.08) * math.cos(math.radians(a0 + (a1 - a0) * k / n)),
            z_axle + (r + 0.08) * math.sin(math.radians(a0 + (a1 - a0) * k / n))) for k in range(n + 1)]
    for k in range(n):
        ya, za = pts[k]
        yb, zb = pts[k + 1]
        v = [bm.verts.new((x0, ya, za)), bm.verts.new((x1, ya, za)), bm.verts.new((x1, yb, zb)), bm.verts.new((x0, yb, zb))]
        f = bm.faces.new(v)
        f.material_index = mat
        v2 = [bm.verts.new((x0, ya, za + 0.02)), bm.verts.new((x0, yb, zb + 0.02)), bm.verts.new((x1, yb, zb + 0.02)), bm.verts.new((x1, ya, za + 0.02))]
        bm.faces.new(v2).material_index = mat


# --- the box truck ---------------------------------------------------------------------------------

def box_truck():
    """A 26 ft medium-duty box truck with a cab-over cab: a tall flat-faced cab with a deep
    windscreen and a grille under it, the front axle under the seats, a 6.3 m dry box on the
    frame behind with a roll-up door, dual rear wheels, a fuel tank and steps."""
    s = {"name": "box_truck", "length": 8.60, "height": 3.55}
    s.update({
        "nose": 4.30, "tail": 2.22,
        "front_axle": 3.50, "rear_axle": -2.30, "axle_z": 0.440,
        "axles": [(3.50, False), (-2.30, True)],
        "wheel_r": 0.440, "wheel_w": 0.235, "wheel_x": 0.860,
        "dual_x": 0.800, "dual_gap": 0.270,
        "arch_r": 0.520, "arch_r_rear": 0.520, "arch_in": 0.55, "arch_in_dual": 0.50,
        "road": -0.26, "belt_probe_z": 1.4,
        "cowl": 7.0, "deck": -1.0, "gh_blend_front": 0.1, "gh_blend_rear": 0.1,
        "crown_at": 0.60, "tension": 1.0, "under_j": 1.0,
        "rings": [0.0, 1.0, 1.6, 2.1, 2.85, 3.4, 3.92, 4.0, 4.08, 4.6, 5.0, 5.5, 6.0, 6.25,
                  6.5, 6.75, 7.0],
        "end_steps": [0.0, 0.015, 0.04, 0.08, 0.13, 0.20, 0.30],
        "mid_step": 0.45,
        "extra_stations": [],
        "creases": [(6.0, 0.30, -7.0, 7.0)],
        "station_creases": [],
        "tangent_over": {5: (-0.03, 1.0), 6: (-0.15, 1.0), 7: (-1.0, 0.0)},
        "nose_cap": {"steps": 3, "roll": lambda j: 0.090, "dome": 0.060,
                     "lean": lambda co: 0.05 * ramp(co.z, 1.4, 0.7)},
        "tail_cap": {"steps": 2, "roll": lambda j: 0.040, "dome": 0.010},
        "sculpt": [],
        "profile": {
            "top": [(4.30, 2.500), (4.15, 2.540), (2.35, 2.545), (2.22, 2.530)],
            "rail_z": [(4.30, 2.360), (4.15, 2.390), (2.35, 2.390), (2.22, 2.380)],
            "rail_w": [(4.30, 0.930), (4.15, 0.975), (2.35, 0.975), (2.22, 0.960)],
            "roof_z": [(4.30, 2.490), (4.15, 2.525), (2.35, 2.530), (2.22, 2.515)],
            "roof_w": [(4.30, 0.78), (4.15, 0.82), (2.35, 0.82), (2.22, 0.80)],
            "over_w": 1.0,
            "belt_z": 1.560,
            "belt_in": 0.020,
            "shoulder_z": 1.380,
            "width": [(4.30, 0.960), (4.26, 1.005), (4.18, 1.028), (4.05, 1.035),
                      (2.35, 1.035), (2.25, 1.025), (2.22, 1.005)],
            "low_z": 0.98,
            "low_in": 0.006,
            "sill_z": [(4.30, 0.780), (4.10, 0.740), (2.22, 0.760)],
            "sill_in": 0.030,
            "floor_z": [(4.30, 0.760), (4.10, 0.700), (2.22, 0.730)],
            "floor_in": 0.08,
        },
        "box": (2.06, -4.30, 1.10, 3.55, 1.22),
    })
    s["details"] = box_truck_details
    return s


def box_truck_details(s, sec, surf, body, parts):
    nose = s["nose"]
    fl, _n = surf.end_hit(0.0, 1.9, 1.0)
    face_f = fl.y if fl is not None else nose + 0.1
    # Windscreen on the face, the grille under it.
    scr = rounded_outline([(-0.93, 1.47), (0.93, 1.47), (0.90, 2.30), (-0.90, 2.30)], 0.09)
    boolean(body, extrude_cutter(scr, "y", nose - 0.20, nose + 0.6))
    mouth = rounded_outline([(-0.62, 0.98), (0.62, 0.98), (0.62, 1.34), (-0.62, 1.34)], 0.04)
    boolean(body, extrude_cutter(mouth, "y", nose - 0.08, nose + 0.6))
    # Door windows and the small rear cab window.
    for side in (1.0, -1.0):
        hole = rounded_outline([(4.02, 1.62), (3.12, 1.62), (3.12, 2.27), (3.80, 2.27), (4.02, 2.05)], 0.05)
        boolean(body, side_cutter(hole, side, 0.85), quiet=True)
    rw = rounded_outline([(-0.55, 1.75), (0.55, 1.75), (0.55, 2.15), (-0.55, 2.15)], 0.05)
    boolean(body, extrude_cutter(rw, "y", s["tail"] - 0.5, s["tail"] + 0.15))
    gb = bmesh.new()
    pts = [Vector((-0.93 + 1.86 * c / 8, face_f - 0.035 - (z - 1.47) * 0.08, z))
           for z in [1.47 + 0.83 * r / 6 for r in range(7)] for c in range(9)]
    oriented_grid(gb, pts, [Vector((0, 1, 0.08)).normalized()] * len(pts), 7, 9, GLASS)
    for side in (1.0, -1.0):
        g = [[(3.12 + 0.90 * c / 4, 1.62 + 0.65 * r / 3) for c in range(5)] for r in range(4)]
        g = [[(y, z) for y, z in row if not (y > 3.80 and z > 2.05 + (4.02 - y) / 0.22 * 0.22)] for row in g]
        g = [[(min(y, 4.0 - max(z - 2.05, 0.0)), z) for y, z in row] for row in [[(3.12 + 0.88 * c / 4, 1.62 + 0.65 * r / 3) for c in range(5)] for r in range(4)]]
        res = hits_2d(surf, "side", g, side)
        if res:
            p2, n2 = res
            oriented_grid(gb, [p - n * 0.010 for p, n in zip(p2, n2)], n2, 4, 5, GLASS)
    pts = [Vector((-0.55 + 1.10 * c / 4, s["tail"] - 0.03, 1.75 + 0.40 * r)) for r in range(2) for c in range(5)]
    oriented_grid(gb, pts, [Vector((0, -1, 0))] * len(pts), 2, 5, GLASS)
    tidy(gb)
    parts.append(new_object("glass", gb))

    bp = bmesh.new()
    eggcrate(bp, -0.62, 0.62, 0.98, 1.34, face_f - 0.01, face_f - 0.07, 14, 4, thick=0.012)
    yb = face_f
    # Bumper, steel and heavy, wider than the cab; tow hooks; the step plate in its top.
    box_into(bp, -1.08, 1.08, yb - 0.12, yb + 0.10, 0.42, 0.74, TRIM)
    box_into(bp, -1.07, 1.07, yb + 0.10, yb + 0.112, 0.46, 0.70, CHROME)
    for side in (1.0, -1.0):
        end_panel(bp, surf, 1.0, side * 0.66, side * 0.98, 1.00, 1.30, 0.012, TRIM, thickness=0.04)
        for xc in (0.74, 0.90):
            disc_lamp(bp, side * xc, yb + 0.012, 1.15, 0.065, LIGHT_F, 1.0)
        end_panel(bp, surf, 1.0, side * 0.68, side * 0.96, 1.02, 1.06, 0.014, LIGHT_F, rows=1, cols=3)
        box_into(bp, side * 0.80, side * 0.95, yb + 0.10, yb + 0.13, 0.55, 0.62, LIGHT_F)
        # Clearance lamps on the cab roof's front edge.
        for x in (0.30, 0.55, 0.80) if side > 0 else (-0.30,):
            pass
    for x in (-0.20, 0.0, 0.20):
        end_panel(bp, surf, 1.0, x - 0.04, x + 0.04, 2.44, 2.48, 0.01, LIGHT_F, rows=1, cols=1)
    # Steps under each door, behind the front wheel; the mirrors; a wiper pair.
    for side in (1.0, -1.0):
        for z in (0.48, 0.80):
            box_into(bp, side * 0.80, side * 1.02, s["front_axle"] - 0.86, s["front_axle"] - 0.56, z - 0.03, z + 0.03, TRIM)
        box_into(bp, side * 0.95, side * 1.01, s["front_axle"] - 0.86, s["front_axle"] - 0.56, 0.42, 0.86, TRIM)
        tube(bp, [(side * 1.0, nose - 0.30, 2.20), (side * 1.22, nose - 0.05, 2.25), (side * 1.24, nose + 0.05, 1.90)], 0.018, TRIM)
        box_into(bp, side * 1.17, side * 1.31, nose + 0.0, nose + 0.08, 1.45, 1.95, TRIM)
        box_into(bp, side * 1.18, side * 1.30, nose - 0.005, nose + 0.001, 1.48, 1.92, CHROME)
        tube(bp, [(side * 0.86, face_f + 0.01, 1.52), (side * 0.20, face_f - 0.03, 1.62)], 0.010, TRIM, n=6)
    parts.append(new_object("inserts", bp))

    # Panel lines: the doors.
    paths = []
    for side in (1.0, -1.0):
        paths.append(surface_path(surf, "side", [(4.06, 2.33), (4.06, 0.80)], side))
        paths.append(surface_path(surf, "side", [(3.05, 2.33), (3.05, 0.80)], side))
        paths.append(surface_path(surf, "side", [(4.06, 2.33), (3.05, 2.33)], side))
    cut_grooves(body, [p for p in paths if len(p) > 2])

    # The box and the chassis under it.
    yf, yr, z0, z1, hw = s["box"]
    parts.extend(cargo_box("box", yf, yr, z0, z1, hw, "rollup", rail_z=z0 + 0.95))
    bc = bmesh.new()
    frame_rails(bc, s["tail"] + 0.2, yr + 0.15, 0.82)
    # Cross sills under the box floor.
    for k in range(9):
        y = yr + 0.3 + (yf - yr - 0.6) * k / 8
        box_into(bc, -hw + 0.03, hw - 0.03, y - 0.04, y + 0.04, z0 - 0.12, z0, TRIM)
    cylinder(bc, 0, -0.80, 0.68, 0.24, s["tail"] - 0.15, s["tail"] - 1.15, CHROME)
    box_into(bc, 0.62, 0.95, s["tail"] - 0.30, s["tail"] - 0.85, 0.48, 0.86, TRIM)
    # Side guards between the axles and the rear fenders, mudflaps, the underride bar.
    for side in (1.0, -1.0):
        box_into(bc, side * 1.10, side * 1.14, s["rear_axle"] + 0.70, s["tail"] - 1.25, 0.55, 0.62, TRIM)
        quarter_fender(bc, s["rear_axle"], s["axle_z"], s["wheel_r"], side * 0.60, side * 1.13)
        mudflap(bc, side * 0.85, s["rear_axle"] - 0.70, 0.22, 0.95)
    underride(bc, yr + 0.20, 0.55, hw)
    parts.append(new_object("chassis", bc))


rc.SPECS["box_truck"] = box_truck


# --- the semi -------------------------------------------------------------------------------------

def semi():
    """A long-nose sleeper tractor and a 53 ft dry van: a high bonnet over a tall chrome grille
    between swept-back headlamps, a raked two-piece windscreen, a cab with a high-roof sleeper
    and its fairing, fuel tanks and steps under the doors, exhaust stacks, two drive axles under
    the fifth wheel; the trailer (its own node, origin at the kingpin) on a sliding tandem."""
    s = {"name": "semi", "length": 7.10, "height": 4.10}
    s.update({
        "nose": 3.80, "tail": -1.70,
        "front_axle": 2.75, "rear_axle": -3.41, "axle_z": 0.510,
        "axles": [(2.75, False), (-2.75, True), (-4.07, True)],
        "wheel_r": 0.510, "wheel_w": 0.290, "wheel_x": 1.035,
        "dual_x": 0.920, "dual_gap": 0.320,
        "arch_r": 0.610, "arch_r_rear": 0.610, "arch_in": 0.62, "arch_in_dual": 0.55,
        "road": -0.30, "belt_probe_z": 2.0,
        "cowl": 1.75, "deck": -2.5, "gh_blend_front": 0.18, "gh_blend_rear": 0.05,
        "crown_at": 0.62, "tension": 1.0, "under_j": 1.0,
        "rings": [0.0, 1.0, 1.6, 2.1, 2.85, 3.4, 3.92, 4.0, 4.08, 4.6, 5.0, 5.5, 6.0, 6.25,
                  6.5, 6.75, 7.0],
        "end_steps": [0.0, 0.015, 0.04, 0.08, 0.13, 0.20, 0.30],
        "mid_step": 0.40,
        "extra_stations": [1.80, 1.75, 1.70, 1.16, 1.10, 1.04, 0.15, -0.60, -0.70],
        "creases": [(4.0, 0.4, 1.9, 3.8)],
        "station_creases": [(1.75, 0.5, 5.2, 7.0)],
        "tangent_over": {6: (-0.10, 1.0), 7: (-1.0, 0.0)},
        "nose_cap": {"steps": 3, "roll": lambda j: 0.06, "dome": 0.03},
        "tail_cap": {"steps": 2, "roll": lambda j: 0.05, "dome": 0.012},
        "sculpt": [],
        "profile": {
            "top": [(3.80, 1.430), (3.76, 1.480), (3.65, 1.540), (3.30, 1.620), (2.80, 1.720),
                    (2.30, 1.810), (1.95, 1.880), (1.80, 1.920), (1.75, 1.950), (1.65, 2.090),
                    (1.45, 2.380), (1.25, 2.660), (1.16, 2.780), (1.10, 2.850), (1.00, 2.910),
                    (0.85, 2.950), (0.40, 2.965), (0.15, 3.000), (-0.05, 3.200),
                    (-0.25, 3.500), (-0.45, 3.780), (-0.60, 3.900), (-0.70, 3.950),
                    (-1.62, 3.960), (-1.70, 3.920)],
            "rail_z": [(1.95, 1.860), (1.75, 1.930), (1.65, 2.060), (1.45, 2.340), (1.25, 2.610),
                       (1.16, 2.730), (1.10, 2.790), (1.00, 2.840), (0.85, 2.870),
                       (0.40, 2.885), (0.15, 2.920), (-0.05, 3.110), (-0.25, 3.400),
                       (-0.45, 3.670), (-0.60, 3.790), (-0.70, 3.840), (-1.62, 3.850),
                       (-1.70, 3.810)],
            "rail_w": [(1.95, 0.90), (1.75, 0.98), (1.40, 1.08), (1.10, 1.12), (0.50, 1.17),
                       (-0.70, 1.19), (-1.62, 1.19), (-1.70, 1.17)],
            "roof_z": [(1.95, 1.875), (1.75, 1.945), (1.65, 2.080), (1.45, 2.365), (1.25, 2.645),
                       (1.16, 2.762), (1.10, 2.828), (1.00, 2.885), (0.85, 2.925),
                       (0.40, 2.940), (0.15, 2.975), (-0.05, 3.170), (-0.25, 3.465),
                       (-0.45, 3.740), (-0.60, 3.860), (-0.70, 3.910), (-1.62, 3.920),
                       (-1.70, 3.880)],
            "roof_w": [(1.95, 0.55), (1.75, 0.62), (1.40, 0.80), (1.10, 0.92), (0.40, 0.98),
                       (-0.70, 1.02), (-1.70, 1.00)],
            "over_w": [(3.80, 0.0), (2.0, 0.0), (1.55, 1.0), (-1.70, 1.0)],
            "belt_z": [(3.80, 1.300), (3.50, 1.420), (3.00, 1.560), (2.40, 1.680),
                       (1.95, 1.760), (1.75, 1.800), (1.55, 1.880), (1.20, 1.920),
                       (0.40, 1.940), (-1.70, 1.960)],
            "belt_in": [(3.80, 0.06), (2.0, 0.10), (1.6, 0.04), (-1.70, 0.03)],
            "shoulder_z": [(3.80, 1.000), (3.40, 1.200), (2.80, 1.380), (2.00, 1.500),
                           (1.60, 1.560), (-1.70, 1.620)],
            "width": [(3.80, 0.880), (3.75, 0.950), (3.55, 1.050), (3.10, 1.120),
                      (2.40, 1.160), (1.95, 1.180), (1.70, 1.215), (1.40, 1.240),
                      (-1.62, 1.245), (-1.70, 1.225)],
            "low_z": [(3.80, 0.760), (2.80, 0.900), (1.70, 1.150), (-1.70, 1.200)],
            "low_in": 0.010,
            "sill_z": [(3.80, 0.560), (3.30, 0.600), (2.75, 0.640), (1.70, 0.860),
                       (-1.70, 0.900)],
            "sill_in": 0.035,
            "floor_z": [(3.80, 0.520), (3.30, 0.560), (2.75, 0.600), (1.70, 0.820),
                        (-1.70, 0.860)],
            "floor_in": 0.10,
        },
        "kingpin": (-3.30, 1.22),
        "trailer": {"front": -2.40, "length": 16.15, "hw": 1.295, "floor": 1.22, "top": 4.11,
                    "axles": [-16.05, -17.30]},
    })
    s["details"] = semi_details
    return s


def semi_windows(s, sec):
    def screen_j(f):
        return (sec.j_along(f, 6.0, 0.07), 7.0)

    def side_j(f):
        lo = sec.j_along(f, 5.0, 0.03)
        hi = min(sec.j_at_z(f, 2.74), sec.j_along(f, 6.0, 0.03, -1.0))
        if hi < lo:
            lo = hi = (lo + hi) * 0.5
        return lo, hi
    return [
        {"name": "windscreen", "centre": True, "rows": 14, "cols": 12,
         "f": lambda j: (1.18, 1.72), "j": screen_j, "cut_shrink_j": 0.02},
        {"name": "door", "centre": False, "rows": 8, "cols": 10,
         "f": lambda j: (0.52, 1.55), "j": side_j, "cut_shrink_j": 0.03},
    ]


def semi_details(s, sec, surf, body, parts):
    nose, tail = s["nose"], s["tail"]
    wins = semi_windows(s, sec)
    rc.cut_windows(body, surf, wins)
    # Sleeper bunk window each side.
    for side in (1.0, -1.0):
        hole = rounded_outline([(-0.95, 2.20), (-0.55, 2.20), (-0.55, 2.50), (-0.95, 2.50)], 0.06)
        boolean(body, side_cutter(hole, side, 1.10), quiet=True)
    parts.append(rc.build_glass(surf, wins, 0.008))
    gb = bmesh.new()
    for side in (1.0, -1.0):
        side_panel(gb, surf, -0.95, -0.55, 2.20, 2.50, -0.010, GLASS, side, rows=1, cols=2)
    parts.append(new_object("sleeper_glass", gb))
    fl, _n = surf.end_hit(0.0, 1.0, 1.0)
    face_f = fl.y if fl is not None else nose
    # The grille: a tall chrome surround with horizontal bars, cut into the bonnet's nose.
    mouth = rounded_outline([(-0.56, 0.62), (0.56, 0.62), (0.52, 1.38), (-0.52, 1.38)], 0.05)
    boolean(body, extrude_cutter(mouth, "y", nose - 0.10, nose + 0.6))
    bp = bmesh.new()
    eggcrate(bp, -0.56, 0.56, 0.62, 1.38, face_f - 0.03, face_f - 0.09, 2, 13, thick=0.020, mat=CHROME)
    gp = surface_path(surf, "front", [(0.58, 1.40), (0.58, 0.60), (-0.58, 0.60), (-0.58, 1.40), (0.58, 1.40)], 1.0, step=0.03)
    if len(gp) > 4:
        sweep(bp, [p for p, _n in gp], [(-0.04, -0.004), (-0.03, 0.03), (0.03, 0.03), (0.04, -0.004)],
              CHROME, normals=[n for _p, n in gp])
    for side in (1.0, -1.0):
        # Headlamps swept back along the bonnet's corners, in a black housing.
        hl = [[(side * (0.68 + 0.26 * c / 4), 1.10 + 0.20 * r / 2 - 0.10 * c / 4) for c in range(5)] for r in range(3)]
        applied(bp, surf, "front", hl, 0.012, TRIM, thickness=0.05)
        for xc in (0.76, 0.88):
            disc_lamp(bp, side * xc, surf.end_hit(side * xc, 1.12, 1.0)[0].y + 0.014 if surf.end_hit(side * xc, 1.12, 1.0)[0] else nose,
                      1.12 - (xc - 0.68) * 0.4, 0.060, LIGHT_F, 1.0)
        end_panel(bp, surf, 1.0, side * 0.66, side * 0.93, 1.02, 1.05, 0.016, LIGHT_F, rows=1, cols=3)
    # Chrome bumper, the full width, tow hooks under it.
    box_into(bp, -1.20, 1.20, face_f - 0.20, face_f + 0.10, 0.40, 0.72, CHROME)
    box_into(bp, -1.18, 1.18, face_f - 0.24, face_f + 0.05, 0.34, 0.40, TRIM)
    for x in (-0.45, 0.45):
        box_into(bp, x - 0.04, x + 0.04, face_f + 0.06, face_f + 0.14, 0.36, 0.44, TRIM)
    # Clearance lamps over the windscreen and on the sleeper fairing.
    for x in (-0.30, -0.15, 0.0, 0.15, 0.30):
        box_into(bp, x - 0.03, x + 0.03, 1.08, 1.12, 2.90, 2.94, LIGHT_F)
    parts.append(new_object("face", bp))

    # Panel lines: the bonnet's tilt line, the doors.
    paths = []
    for side in (1.0, -1.0):
        paths.append(surface_path(surf, "side", [(1.82, 1.85), (1.82, 0.75)], side))
        paths.append(surface_path(surf, "side", [(1.62, 2.80), (1.62, 0.90)], side))
        paths.append(surface_path(surf, "side", [(0.40, 2.85), (0.40, 0.92)], side))
        paths.append(surface_path(surf, "side", [(1.62, 0.92), (0.40, 0.92)], side))
    cut_grooves(body, [p for p in paths if len(p) > 2])

    bc = bmesh.new()
    frame_rails(bc, nose - 0.4, -4.85, 0.92, x=0.44, h=0.30)
    for side in (1.0, -1.0):
        # Fuel tanks with straps under the doors; a step box behind them; the deck plate; the
        # exhaust stack up the sleeper's back corner; drive fenders and mudflaps.
        cylinder(bc, 0, side * 0.90, 0.62, 0.30, 1.30, -0.10, CHROME, n=18)
        for y in (1.10, 0.10):
            box_into(bc, side * 0.58, side * 1.22, y - 0.03, y + 0.03, 0.30, 0.94, TRIM)
        for z in (0.48, 0.86):
            box_into(bc, side * 0.95, side * 1.22, 1.50, 1.62, z - 0.025, z + 0.025, CHROME)
        box_into(bc, side * 0.55, side * 1.20, -0.30, -1.55, 0.40, 0.95, TRIM)
        tube(bc, [(side * 1.13, -1.80, 1.05), (side * 1.13, -1.80, 4.25)], 0.065, CHROME, n=14)
        box_into(bc, side * 1.07, side * 1.19, -1.88, -1.72, 2.2, 3.4, CHROME)
        for y in (-2.75, -4.07):
            quarter_fender(bc, y, s["axle_z"], s["wheel_r"], side * 0.55, side * 1.18, a0=40.0, a1=140.0, n=8)
        mudflap(bc, side * 0.92, -4.85, 0.20, 0.95, w=0.62)
        # The air cleaner on the cab's flank.
        cylinder(bc, 1.70, side * 1.20, 1.55, 0.18, 1.85, 1.55, CHROME, n=14, axis="y") if False else None
    # Fifth wheel plate.
    kp_y, kp_z = s["kingpin"]
    box_into(bc, -0.55, 0.55, kp_y - 0.55, kp_y + 0.55, kp_z - 0.12, kp_z - 0.04, TRIM)
    box_into(bc, -0.62, 0.62, -1.80, -2.20, 1.05, 1.10, CHROME)
    parts.append(new_object("chassis", bc))
    for side in (1.0, -1.0):
        rc.mirror(parts, surf, s, side, 1.55, 5.3, (1.40, 1.55, 2.30), (0.10, 0.08, 0.50), head_mat=CHROME)

    # --- the trailer, its own objects (origin at the kingpin; built in place, moved after) -------
    t = s["trailer"]
    tf = t["front"]
    tr = tf - t["length"]
    tparts = cargo_box("trailer", tf, tr, t["floor"], t["top"], t["hw"], "swing", marker_step=3.2)
    tb = bmesh.new()
    # Floor frame, cross members, the landing gear, the sliding tandem's subframe, side skirts.
    for sx in (1.0, -1.0):
        box_into(tb, sx * 0.40, sx * 0.48, tr + 0.3, tf - 0.4, t["floor"] - 0.40, t["floor"] - 0.02, TRIM)
    for k in range(24):
        y = tr + 0.25 + (t["length"] - 0.5) * k / 23
        box_into(tb, -t["hw"] + 0.05, t["hw"] - 0.05, y - 0.03, y + 0.03, t["floor"] - 0.12, t["floor"] - 0.02, TRIM)
    gy = tf - 2.6
    for sx in (1.0, -1.0):
        box_into(tb, sx * 0.80, sx * 0.92, gy - 0.06, gy + 0.06, 0.40, t["floor"] - 0.10, TRIM)
        box_into(tb, sx * 0.72, sx * 1.00, gy - 0.14, gy + 0.14, 0.30, 0.36, TRIM)
        box_into(tb, sx * 0.86, sx * 0.88, gy - 0.30, gy - 0.06, t["floor"] - 0.10, 0.70, TRIM)
        # Side skirts between the landing gear and the tandem.
        box_into(tb, sx * (t["hw"] - 0.06), sx * (t["hw"] - 0.04), t["axles"][0] + 1.0, gy - 0.6, 0.38, t["floor"] - 0.02, TRIM)
    ya, yb = t["axles"]
    for sx in (1.0, -1.0):
        box_into(tb, sx * 0.40, sx * 0.52, yb - 0.7, ya + 0.7, t["floor"] - 0.62, t["floor"] - 0.38, TRIM)
        mudflap(tb, sx * 0.92, yb - 0.70, 0.20, 0.95, w=0.62)
    underride(tb, tr + 0.25, 0.55, t["hw"])
    tidy(tb)
    tparts.append(new_object("trailer_frame", tb))
    s["trailer_parts"] = tparts
    s["trailer_spec"] = {"axles": [(ya, True), (yb, True)], "wheel_r": s["wheel_r"],
                         "wheel_w": s["wheel_w"], "dual_x": s["dual_x"], "dual_gap": s["dual_gap"],
                         "axle_z": s["axle_z"], "wheel_x": s["wheel_x"]}


rc.SPECS["semi"] = semi


# --- assembly ---------------------------------------------------------------------------------------

def build(spec, detail=True):
    """make_road_cars.build() with the big vehicles' arches (one per axle, deeper over a dual)."""
    rc.reset_scene()
    rc.MATS.clear()
    rc.MATS.extend(rc.make_materials())
    sec = rc.Section(spec)
    body = rc.build_body(spec, sec)
    boolean(body, arch_cutter(spec))
    surf = rc.Surface(body, sec)
    parts = [body]
    if detail:
        spec["details"](spec, sec, surf, body, parts)
    rc.decimate_underbody(body)
    for o in parts:
        o.data.calc_loop_triangles()
        log("part %-14s %6d triangles" % (o.name, len(o.data.loop_triangles)))
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
    for o in spec.get("door_nodes", []):
        shade(o)
    return ob


def build_far(ob, spec, extra=(), target=9000):
    """make_road_cars.build_far() with every axle's far wheels and the moving parts (`extra`,
    copied in place: the doors closed) folded into the twin."""
    src = ob
    if extra:
        copies = [ob.copy()]
        copies[0].data = ob.data.copy()
        bpy.context.scene.collection.objects.link(copies[0])
        for e in extra:
            c = e.copy()
            c.data = e.data.copy()
            bpy.context.scene.collection.objects.link(c)
            c.data.transform(c.matrix_world)
            c.matrix_world = __import__("mathutils").Matrix.Identity(4)
            copies.append(c)
        src = join(copies)
        src.name = ob.name + "_farsrc"
    saved = rc.far_wheels
    rc.far_wheels = lambda sp, segs=14: far_wheel_set(sp, segs)
    try:
        far = rc.build_far(src, spec, target)
    finally:
        rc.far_wheels = saved
    far.name = ob.name + "_far"
    far.data.name = far.name
    if src is not ob:
        bpy.data.objects.remove(src, do_unlink=True)
    return far


def report(ob, spec, far=None):
    rc.report(ob, spec, far)
    me = ob.data
    zs = [v.co.z for v in me.vertices]
    ys = [v.co.y for v in me.vertices]
    if far is not None:
        zs += [v.co.z for v in far.data.vertices]
        ys += [v.co.y for v in far.data.vertices]
    cy = (max(ys) + min(ys)) * 0.5
    road = spec["road"]
    # Body space (Godot): x as is, y = model z + road, z = -(model y - cy).
    print("   AXLES (body z, dual): %s" % [(round(-(y - cy), 3), d) for y, d in spec["axles"]])
    for name, lo, hi in spec.get("signs", []):
        a = Vector((lo[0], lo[2] + road, -(lo[1] - cy)))
        b = Vector((hi[0], hi[2] + road, -(hi[1] - cy)))
        print("   SIGN %s: lo %s hi %s" % (name, tuple(round(v, 3) for v in a), tuple(round(v, 3) for v in b)))
    for o in spec.get("door_nodes", []):
        h = o.location
        print("   DOOR %s hinge (body) %.3f %.3f %.3f" % (o.name, h.x, h.z + road, -(h.y - cy)))


def export(objs, path):
    rc.export(objs, path)


def build_trailer(spec):
    """The semi's trailer as two objects, the full one and its far twin, with their origin on the
    kingpin (the node Vehicle swings the trailer on)."""
    from mathutils import Matrix
    parts = spec["trailer_parts"]
    for o in parts:
        o.data.calc_loop_triangles()
        log("trailer part %-14s %6d triangles" % (o.name, len(o.data.loop_triangles)))
    tr = join(parts)
    tr.name = "road_semi_trailer"
    tr.data.name = tr.name
    shade(tr)
    kp_y, kp_z = spec["kingpin"]
    tr.data.transform(Matrix.Translation((0.0, -kp_y, -kp_z)))
    tr.location = (0.0, kp_y, kp_z)
    far = build_far(tr, spec["trailer_spec"], target=3500)
    far.name = "road_semi_trailer_far"
    far.data.name = far.name
    return tr, far


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = [a for a in argv if not a.startswith("--")] or ["bus"]
    do_render = "--render" in argv
    detail = "--nodetail" not in argv
    only_views = os.environ.get("VIEWS", "")
    for name in names:
        spec = rc.SPECS[name]()
        ob = build(spec, detail)
        doors = spec.get("door_nodes", [])
        far = build_far(ob, spec, doors)
        far.data.calc_loop_triangles()
        report(ob, spec, far)
        print("   far twin: %d triangles" % len(far.data.loop_triangles))
        objs = [ob] + list(doors) + [far]
        trailer = []
        if "trailer_parts" in spec:
            tr, tfar = build_trailer(spec)
            tr.data.calc_loop_triangles()
            tfar.data.calc_loop_triangles()
            ys = [v.co.y for v in ob.data.vertices] + [v.co.y for v in far.data.vertices]
            cy = (max(ys) + min(ys)) * 0.5
            kp_y, kp_z = spec["kingpin"]
            print("   TRAILER: %d triangles, far %d; kingpin (body) y %.3f z %.3f; axles (trailer z) %s; "
                  "rear end (trailer z) %.3f"
                  % (len(tr.data.loop_triangles), len(tfar.data.loop_triangles), kp_z + spec["road"],
                     -(kp_y - cy), [round(-(y - kp_y), 3) for y, _d in spec["trailer_spec"]["axles"]],
                     -((spec["trailer"]["front"] - spec["trailer"]["length"]) - kp_y)))
            trailer = [tr, tfar]
            objs += trailer
        if "--noexport" not in argv:
            path = os.path.join(OUT_DIR, "road_%s.glb" % name)
            export(objs, path)
            print("wrote", path)
        bpy.data.objects.remove(far, do_unlink=True)
        if trailer:
            bpy.data.objects.remove(trailer[1], do_unlink=True)
        if do_render:
            views = big_views(spec)
            if only_views:
                views = [v for v in views if v[0] in only_views.split(",")]
            wh = far_wheel_set(spec, 24)
            extra = list(doors)
            if trailer:
                extra.append(trailer[0])
                tw = far_wheel_set(spec["trailer_spec"], 24)
                extra.append(tw)
            render_obj = join([ob, wh] + extra)
            rc.render_previews(render_obj, name, views, paint=(0.80, 0.80, 0.78))


def big_views(spec):
    L = spec["length"] + (spec["trailer"]["length"] if "trailer" in spec else 0.0)
    H = spec.get("height", 3.0)
    if "trailer" in spec:
        n = spec["nose"]
        return [
            ("front3", (7.5, n + 7.5, 2.6), (0.0, n - 2.5, 1.9), 40),
            ("rear3", (-6.0, -L + 3.5, 3.0), (0.0, -L * 0.45, 2.0), 40),
            ("side", (L * 1.05, -L * 0.42 + 3.0, 1.8), (0.0, -L * 0.42 + 3.0, 1.9), 40),
            ("close", (3.6, n + 3.2, 1.8), (0.4, n - 0.6, 1.4), 35),
        ]
    return [
        ("front3", (L * 0.55 + 2.0, L * 0.5 + L * 0.55, 2.4), (0.0, L * 0.12, H * 0.42), 40),
        ("rear3", (-L * 0.5 - 2.0, -L * 0.5 - L * 0.5, 2.6), (0.0, -L * 0.1, H * 0.45), 40),
        ("side", (L * 1.15, 0.0, 1.6), (0.0, 0.0, H * 0.45), 40),
        ("front", (0.0, L * 0.5 + 10.0, 1.8), (0.0, 0.0, H * 0.45), 45),
        ("close", (3.4, L * 0.5 + 2.6, 1.7), (0.6, L * 0.5 - 1.0, 1.4), 35),
    ]


if __name__ == "__main__":
    main()
