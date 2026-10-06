#!/usr/bin/env python3
"""The emergency vehicles: a US pumper fire engine and a Type III ambulance, built in Blender from
code on tools/make_big_vehicles.py (and through it tools/make_road_cars.py's pipeline: the
profile-curve loft, booleans, raycast parts, material slots and the far twin):

    tools/road_cars_setup.sh                     # once: Blender 4.2 LTS into build/car_src/
    build/car_src/blender/blender-4.2.23-linux-x64/blender -b --factory-startup \\
        -P tools/make_emergency_vehicles.py -- fire_engine ambulance [--render] [--nodetail]

Writes assets/models/road_<name>.glb; then run `godot --headless --path . --import` (CLAUDE.md,
measurement trap 1). `--render` writes Cycles previews to $RENDER_DIR.

Conventions are the cars' and the big vehicles' (read both docstrings): X lateral, Y along the
vehicle with the NOSE AT +Y, Z up, ground at Z = 0, so the vehicle's RIGHT (the kerb side, US
traffic) is +X. No wheels in the full model (the game draws BigVehicles.wheel_mesh() per axle);
a `<name>_far` twin with baked far wheels on every axle. The run prints the WHEEL_POSE / _dims
numbers plus the axles, the lamps, the light bar and a lettering spot in body space.

Slots added to the cars' seven and the big vehicles' two (sign, glass_door - unused here):

  * `beacon_red`, `beacon_white`: every warning lens, and nothing else. Each lens is its own small
    closed box or quad, mirrored left / right, so the game can pick a flash pattern from where a
    lens sits in mesh space (side, front / rear, height). The fire engine's rear arrow stick is
    the row of `beacon_white` lenses under the hose bed (an amber-emitting clear-lens stick).
  * `stripe`: reflective striping laid on the bodywork as thin proud strips (the fire engine's
    band and the ambulance's band and rear chevrons). Its colour is the game's to set.
  * `satin`: brushed / satin aluminium - roll-up doors, diamond-plate steps and decks, the pump
    panel, the ladders, hose bed dividers, fender trims (chrome would read as a mirror).
  * `hose`: the fire hose in the beds (a jacketed hose colour).

Original designs: generic classes (a custom-cab pumper, a cutaway-chassis box ambulance), no
manufacturer's shapes, names or badges.
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_big_vehicles as bv  # noqa: E402  (imports make_road_cars, appends sign / glass_door)
import make_road_cars as rc  # noqa: E402

from make_road_cars import (  # noqa: E402
    PAINT, GLASS, TRIM, CHROME, TYRE, LIGHT_F, LIGHT_R, ramp, log, new_object, boolean, quad,
    add_box, tidy, oriented_grid, applied, hits_2d, rect_grid, mirror2, extrude_cutter,
    rounded_outline, eggcrate, surface_path, cut_grooves, sweep, wrap_band, circle_path,
    apply_modifiers, join, blade_grid, grid_solid, fj_applied, oface,
)
from make_big_vehicles import (  # noqa: E402
    bevel_box, box_into, tube, disc_lamp, side_cutter, side_panel, end_panel, mudflap,
    frame_rails, cylinder, underride,
)

rc.SLOTS.append(("beacon_red", (0.42, 0.010, 0.012), 0.0, 0.08, 0.5))
BEACON_R = len(rc.SLOTS) - 1
rc.SLOTS.append(("beacon_white", (0.78, 0.80, 0.84), 0.0, 0.06, 0.35))
BEACON_W = len(rc.SLOTS) - 1
rc.SLOTS.append(("stripe", (0.82, 0.74, 0.46), 0.0, 0.30, 0.0))
STRIPE = len(rc.SLOTS) - 1
rc.SLOTS.append(("satin", (0.60, 0.61, 0.63), 1.0, 0.30, 0.0))
SATIN = len(rc.SLOTS) - 1
rc.SLOTS.append(("hose", (0.55, 0.40, 0.09), 0.0, 0.78, 0.0))
HOSE = len(rc.SLOTS) - 1

OUT_DIR = rc.OUT_DIR


# --- helpers ---------------------------------------------------------------------------------------

def box_obj(name, boxes, bevel=0.0, segments=2):
    """Several boxes (x0, x1, y0, y1, z0, z1, mat) as one object, every edge bevelled a little."""
    bm = bmesh.new()
    for b in boxes:
        box_into(bm, *b)
    ob = new_object(name, bm)
    if bevel > 0.0:
        mod = ob.modifiers.new("bev", 'BEVEL')
        mod.width = bevel
        mod.segments = segments
        mod.limit_method = 'ANGLE'
        apply_modifiers(ob)
    return ob


def lens(boxes, x0, x1, y0, y1, z0, z1, mat, housing=0.012, facing=None):
    """A warning lens (its own closed box in a beacon slot) on a black housing a little bigger
    behind it. `facing` is the axis the lens looks along ('y+', 'y-', 'x+', 'x-'); the housing
    sits behind it on that axis."""
    boxes.append((x0, x1, y0, y1, z0, z1, mat))
    h = housing
    if facing == "y+":
        boxes.append((x0 - h, x1 + h, y0 - 0.02, y0 + 0.004, z0 - h, z1 + h, TRIM))
    elif facing == "y-":
        boxes.append((x0 - h, x1 + h, y1 - 0.004, y1 + 0.02, z0 - h, z1 + h, TRIM))
    elif facing == "x+":
        boxes.append((x0 - 0.02, x0 + 0.004, y0 - h, y1 + h, z0 - h, z1 + h, TRIM))
    elif facing == "x-":
        boxes.append((x1 - 0.004, x1 + 0.02, y0 - h, y1 + h, z0 - h, z1 + h, TRIM))


# One slat's section, bottom to top: (fraction of the pitch, how far it stands proud).
SLAT_PROFILE = [(0.0, 0.0), (0.16, 0.0075), (0.84, 0.0075), (1.0, 0.0)]


def planar_dissolve(ob, deg=0.5):
    """Merges the flat stretches of a lofted shell (a cab's flat sides and roof are thousands of
    coplanar subdivision quads) into n-gons, keeping every material boundary and every bend
    over `deg` degrees: the silhouette and the shading do not move."""
    ob.data.calc_loop_triangles()
    n0 = len(ob.data.loop_triangles)
    mod = ob.modifiers.new("flat", 'DECIMATE')
    mod.decimate_type = 'DISSOLVE'
    mod.angle_limit = math.radians(deg)
    mod.delimit = {'MATERIAL', 'SHARP'}
    apply_modifiers(ob)
    ob.data.calc_loop_triangles()
    log("planar dissolve: %d -> %d triangles" % (n0, len(ob.data.loop_triangles)))


def gasket(bm, surf, view, outline, side=1.0, w=0.022, h=0.010, mat=TRIM):
    """A rubber surround swept round a window's outline on the (uncut) skin."""
    pts = list(outline) + [outline[0]]
    gp = rc.resample(surface_path(surf, view, pts, side, step=0.02), 0.055)
    if len(gp) > 4:
        sweep(bm, [p for p, _n in gp], [(-w * 0.5, -0.006), (-w * 0.4, h), (w * 0.4, h), (w * 0.5, -0.006)],
              mat, normals=[n for _p, n in gp])


def rollup_door(bm, side, xs, y0, y1, z0, z1, pitch=0.042, bar_z=None):
    """A roll-up door's curtain on a side face at x = side * xs: slats `pitch` tall, each a low
    convex bulge with a dark groove between, so the curtain reads as slats under any light; a
    lift bar across the bottom rail."""
    lo, hi = min(y0, y1), max(y0, y1)
    n = max(4, int(round((z1 - z0) / pitch)))
    prof = SLAT_PROFILE
    pts, nrm = [], []
    for k in range(n):
        za = z0 + (z1 - z0) * k / n
        zb = z0 + (z1 - z0) * (k + 1) / n
        for t, d in (prof if k == n - 1 else prof[:-1]):
            z = za + (zb - za) * t
            for y in (lo, hi):
                pts.append(Vector((side * (xs + d), y, z)))
                nrm.append(Vector((side, 0.0, 0.0)))
    rows = len(pts) // 2
    oriented_grid(bm, pts, nrm, rows, 2, SATIN)
    # Bottom rail (a heavier extrusion) and the lift bar on it.
    box_into(bm, side * (xs - 0.002), side * (xs + 0.022), lo + 0.004, hi - 0.004, z0 - 0.002, z0 + 0.075, SATIN)
    bz = z0 + 0.035 if bar_z is None else bar_z
    yc = (lo + hi) * 0.5
    w = min(0.42, (hi - lo) * 0.6)
    tube(bm, [Vector((side * (xs + 0.022), yc - w * 0.5, bz)), Vector((side * (xs + 0.055), yc - w * 0.5 + 0.03, bz)),
              Vector((side * (xs + 0.055), yc + w * 0.5 - 0.03, bz)), Vector((side * (xs + 0.022), yc + w * 0.5, bz))],
         0.011, CHROME, n=8)
    # Frame round the opening: jambs and head as a black gasket proud of the paint.
    box_into(bm, side * (xs - 0.01), side * (xs + 0.016), lo - 0.022, lo, z0 - 0.01, z1 + 0.02, TRIM)
    box_into(bm, side * (xs - 0.01), side * (xs + 0.016), hi, hi + 0.022, z0 - 0.01, z1 + 0.02, TRIM)
    box_into(bm, side * (xs - 0.01), side * (xs + 0.020), lo - 0.022, hi + 0.022, z1, z1 + 0.035, TRIM)


def rollup_rear(bm, yface, x0, x1, z0, z1, pitch=0.042):
    """The same curtain on the rear face (looking -Y), x0..x1."""
    n = max(4, int(round((z1 - z0) / pitch)))
    prof = SLAT_PROFILE
    pts, nrm = [], []
    for k in range(n):
        za = z0 + (z1 - z0) * k / n
        zb = z0 + (z1 - z0) * (k + 1) / n
        for t, d in (prof if k == n - 1 else prof[:-1]):
            z = za + (zb - za) * t
            for x in (x0, x1):
                pts.append(Vector((x, yface - d, z)))
                nrm.append(Vector((0.0, -1.0, 0.0)))
    oriented_grid(bm, pts, nrm, len(pts) // 2, 2, SATIN)
    box_into(bm, x0 + 0.004, x1 - 0.004, yface - 0.022, yface + 0.002, z0 - 0.002, z0 + 0.075, SATIN)
    tube(bm, [Vector((-0.20, yface - 0.022, z0 + 0.035)), Vector((-0.17, yface - 0.055, z0 + 0.035)),
              Vector((0.17, yface - 0.055, z0 + 0.035)), Vector((0.20, yface - 0.022, z0 + 0.035))], 0.011, CHROME, n=8)
    box_into(bm, x0 - 0.022, x0, yface - 0.016, yface + 0.01, z0 - 0.01, z1 + 0.02, TRIM)
    box_into(bm, x1, x1 + 0.022, yface - 0.016, yface + 0.01, z0 - 0.01, z1 + 0.02, TRIM)
    box_into(bm, x0 - 0.022, x1 + 0.022, yface - 0.020, yface + 0.01, z1, z1 + 0.035, TRIM)


def side_glass(gb, surf, side, y0, y1, z0, z1, inset=0.012, rows=4, cols=6):
    """Side glass laid on the (uncut) skin over a side-view rectangle, `inset` inside it."""
    g = [[(y0 + (y1 - y0) * c / cols, z0 + (z1 - z0) * r / rows) for c in range(cols + 1)]
         for r in range(rows + 1)]
    res = hits_2d(surf, "side", g, side)
    if res:
        p2, n2 = res
        oriented_grid(gb, [p - n * inset for p, n in zip(p2, n2)], n2, rows + 1, cols + 1, GLASS)
    return bool(res)


def flat_glass(gb, side, xs, y0, y1, z0, z1, rows=2, cols=3):
    pts = [Vector((side * xs, y0 + (y1 - y0) * c / cols, z0 + (z1 - z0) * r / rows))
           for r in range(rows + 1) for c in range(cols + 1)]
    oriented_grid(gb, pts, [Vector((side, 0, 0))] * len(pts), rows + 1, cols + 1, GLASS)


def rear_glass(gb, yface, x0, x1, z0, z1, rows=2, cols=3):
    pts = [Vector((x0 + (x1 - x0) * c / cols, yface, z0 + (z1 - z0) * r / rows))
           for r in range(rows + 1) for c in range(cols + 1)]
    oriented_grid(gb, pts, [Vector((0, -1, 0))] * len(pts), rows + 1, cols + 1, GLASS)


def arch_pocket(y, az, R, x_in, x_out=1.9, flat_top=0.0):
    """A wheel well for a box body: a round-topped pocket from x_in outward on both sides."""
    bm = bmesh.new()
    for side in (1.0, -1.0):
        prof = [(y + R + flat_top * 0.5, -0.3)]
        n = 28
        for k in range(n + 1):
            a = math.pi * k / n
            yy = y + R * math.cos(a) + (flat_top * 0.5 if math.cos(a) > 0 else -flat_top * 0.5)
            prof.append((yy, az + R * math.sin(a)))
        prof.append((y - R - flat_top * 0.5, -0.3))
        xa, xb = (x_in, x_out) if side > 0 else (-x_out, -x_in)
        ra = [bm.verts.new((xa, f, z)) for f, z in prof]
        rb = [bm.verts.new((xb, f, z)) for f, z in prof]
        for k in range(len(prof) - 1):
            quad(bm, ra[k], ra[k + 1], rb[k + 1], rb[k], TRIM)
        quad(bm, ra[-1], ra[0], rb[0], rb[-1], TRIM)
        bm.faces.new(ra).material_index = TRIM
        bm.faces.new(list(reversed(rb))).material_index = TRIM
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_object("cut_arch_body", bm)


def fender_trim(bm, y, az, R, xs, width=0.07, proud=0.012, a0=0.0, a1=180.0, mat=SATIN, z_min=0.0):
    """A flat polished trim ring round a wheel well on a flat side at |x| = xs, both sides."""
    n = 30
    for side in (1.0, -1.0):
        inner, outer = [], []
        for k in range(n + 1):
            a = math.radians(a0 + (a1 - a0) * k / n)
            ci, si = math.cos(a), math.sin(a)
            zi = az + R * si
            zo = az + (R + width) * si
            if zi < z_min and zo < z_min:
                continue
            inner.append(Vector((side * (xs + proud), y + R * ci, max(zi, z_min))))
            outer.append(Vector((side * (xs + proud), y + (R + width) * ci, max(zo, z_min))))
        pts = []
        for p, q in zip(inner, outer):
            pts += [p, q]
        m = len(inner)
        top = oriented_grid(bm, pts, [Vector((side, 0, 0))] * len(pts), m, 2, mat)
        # A lip turned in round the well's edge.
        back = [Vector((p.x - side * proud - side * 0.02, p.y, p.z)) for p in inner]
        for k in range(m - 1):
            oface(bm, (top[2 * k], top[2 * k + 2], bm.verts.new(back[k + 1]), bm.verts.new(back[k])), mat,
                  Vector((0, -(inner[k].y - y), -(inner[k].z - az))))


def stripe_run(bm, side, xs, y0, y1, z0, z1, gaps=(), proud=0.004):
    """A reflective stripe along a flat side, interrupted over the `gaps` (y ranges)."""
    lo, hi = min(y0, y1), max(y0, y1)
    segs = [(lo, hi)]
    for g0, g1 in gaps:
        gl, gh = min(g0, g1), max(g0, g1)
        nxt = []
        for a, b in segs:
            if b <= gl or a >= gh:
                nxt.append((a, b))
                continue
            if a < gl:
                nxt.append((a, gl))
            if b > gh:
                nxt.append((gh, b))
        segs = nxt
    for a, b in segs:
        if b - a > 0.05:
            box_into(bm, side * (xs - 0.002), side * (xs + proud), a, b, z0, z1, STRIPE)


def ladder(bm, side, x, y0, y1, z0, z1, rail_h=0.085, rail_t=0.032, rung_pitch=0.30, rung_r=0.016):
    """A ground ladder racked flat against a side: two box-section rails along y (top and bottom)
    and round rungs between them, with the butt and tip plates."""
    lo, hi = min(y0, y1), max(y0, y1)
    xa, xb = side * x, side * (x + rail_t)
    box_into(bm, xa, xb, lo, hi, z0, z0 + rail_h, SATIN)
    box_into(bm, xa, xb, lo, hi, z1 - rail_h, z1, SATIN)
    n = int((hi - lo - 0.2) / rung_pitch)
    xm = side * (x + rail_t * 0.5)
    for k in range(n + 1):
        y = lo + 0.1 + (hi - lo - 0.2) * k / max(n, 1)
        tube(bm, [Vector((xm, y, z0 + rail_h - 0.005)), Vector((xm, y, z1 - rail_h + 0.005))], rung_r, SATIN, n=6)
    for y in (lo, hi):
        box_into(bm, xa - side * 0.004, xb + side * 0.004, y - 0.02, y + 0.02, z0 - 0.01, z1 + 0.01, TRIM)


def hose_bed(bm, x0, x1, y_front, y_back, z_floor, layers, t=0.046):
    """Flat-loaded hose in one bed: layers folded at the front and back of the bed alternately.
    Each fold pair at the back is one sweep: along the top layer to the back, a U down, and along
    the next layer forward; the U folds are what shows at the rear of the bed."""
    w = (x1 - x0) * 0.98
    xc = (x0 + x1) * 0.5
    h = t * 0.80
    prof = [(-w * 0.5, -h * 0.30), (-w * 0.5 + 0.012, -h * 0.5), (w * 0.5 - 0.012, -h * 0.5),
            (w * 0.5, -h * 0.30), (w * 0.5, h * 0.30), (w * 0.5 - 0.012, h * 0.5),
            (-w * 0.5 + 0.012, h * 0.5), (-w * 0.5, h * 0.30)]
    for k in range(layers // 2):
        z_hi = z_floor + t * (2 * k + 1.5)
        z_lo = z_floor + t * (2 * k + 0.5)
        r = (z_hi - z_lo) * 0.5
        zc = (z_hi + z_lo) * 0.5
        yb = y_back + 0.012 * ((k * 7) % 3)  # folds a little uneven
        path = [Vector((xc, y_front, z_hi))]
        n = 8
        for i in range(n + 1):
            a = math.pi * 0.5 - math.pi * i / n
            path.append(Vector((xc, yb - r * math.cos(a) * 0.0 + (-r * math.cos(a)), zc + r * math.sin(a))))
        path.append(Vector((xc, y_front, z_lo)))
        # The profile's b axis must be the layer's up: sweep with explicit normals (perpendicular
        # to the path in the yz plane).
        nrm = []
        for i, p in enumerate(path):
            if i == 0:
                nrm.append(Vector((0, 0, 1)))
            elif i == len(path) - 1:
                nrm.append(Vector((0, 0, -1)))
            else:
                d = Vector((0.0, p.y - yb, p.z - zc))
                nrm.append(d.normalized() if d.length > 1e-6 else Vector((0, 0, 1)))
        sweep(bm, path, prof, HOSE, normals=nrm)


def crosslay(bm, y0, y1, z_floor, layers, half_w, t=0.050):
    """A crosslay bed: hose loaded across the body, its folds showing at both sides."""
    w = abs(y1 - y0) * 0.96
    yc = (y0 + y1) * 0.5
    h = t * 0.80
    prof = [(-w * 0.5, -h * 0.30), (-w * 0.5 + 0.012, -h * 0.5), (w * 0.5 - 0.012, -h * 0.5),
            (w * 0.5, -h * 0.30), (w * 0.5, h * 0.30), (w * 0.5 - 0.012, h * 0.5),
            (-w * 0.5 + 0.012, h * 0.5), (-w * 0.5, h * 0.30)]
    for k in range(layers):
        z_hi = z_floor + t * (k + 1.0)
        z_lo = z_floor + t * k
        r = (z_hi - z_lo) * 0.5
        zc = (z_hi + z_lo) * 0.5
        side = 1.0 if k % 2 == 0 else -1.0
        xe = side * (half_w + 0.004 * (k % 3))
        path = [Vector((-xe, yc, z_hi))]
        n = 8
        for i in range(n + 1):
            a = math.pi * 0.5 - math.pi * i / n
            path.append(Vector((xe + side * r * math.cos(a), yc, zc + r * math.sin(a))))
        path.append(Vector((-xe, yc, z_lo)))
        nrm = []
        for i, p in enumerate(path):
            if i == 0:
                nrm.append(Vector((0, 0, 1)))
            elif i == len(path) - 1:
                nrm.append(Vector((0, 0, -1)))
            else:
                d = Vector((p.x - xe, 0.0, p.z - zc))
                nrm.append(d.normalized() if d.length > 1e-6 else Vector((0, 0, 1)))
        sweep(bm, path, prof, HOSE, normals=nrm)


def gap_lines(bm, paths, w=0.005, proud=0.0012):
    """Panel gaps on a flat face as thin dark strips a hair proud of it (a flat box gets no
    boolean grooves: the solver reads its thin strips as inside-out on the bevelled corners)."""
    for path in paths:
        pts = [p for p, _n in path]
        nrm = [n for _p, n in path]
        if len(pts) < 2:
            continue
        sweep(bm, pts, [(-w * 0.5, -0.002), (-w * 0.5, proud), (w * 0.5, proud), (w * 0.5, -0.002)],
              TRIM, normals=nrm)


def chevrons(bm, yface, x0, x1, z0, z1, pitch=0.30, proud=0.004, mat=STRIPE):
    """Rear chevrons: diagonal stripe strips on a rear face (looking -Y) over x0..x1, z0..z1,
    leaning up toward the centre line (an inverted V), every other band left in the paint."""
    h = z1 - z0
    w = pitch * 0.5
    for side in (1.0, -1.0):
        x = 0.0
        while x < max(abs(x0), abs(x1)) + h:
            # A parallelogram band: bottom edge from x to x + w, top edge shifted toward the centre.
            pts = [(x, z0), (x + w, z0), (x + w - h, z1), (x - h, z1)]
            clipped = []
            for px, pz in pts:
                clipped.append((min(max(px, 0.0), abs(x1)), pz))
            if max(c[0] for c in clipped) - min(c[0] for c in clipped) > 0.01:
                vs = [bm.verts.new((side * px, yface - proud, pz)) for px, pz in clipped]
                bk = [bm.verts.new((side * px, yface + 0.002, pz)) for px, pz in clipped]
                oface(bm, vs, mat, Vector((0, -1, 0)))
                for k in range(4):
                    k2 = (k + 1) % 4
                    oface(bm, (vs[k], vs[k2], bk[k2], bk[k]), mat, Vector((0, -1, 0)))
            x += pitch


def gauge(bm, side, xs, y, z, r):
    """A round gauge on a flat side panel: chrome bezel, lit face, black needle."""
    disc_lamp(bm, side * xs, y, z, r * 1.12, CHROME, "x+" if side > 0 else "x-", depth=0.018, n=16)
    disc_lamp(bm, side * (xs + 0.019), y, z, r * 0.92, LIGHT_F, "x+" if side > 0 else "x-", depth=0.002, n=16,
              rim_mat=CHROME)
    box_into(bm, side * (xs + 0.021), side * (xs + 0.025), y - 0.004, y + 0.004, z - 0.004, z + r * 0.75, TRIM)


def report_points(spec, ob, far):
    """Body-space conversion for the extra points the report prints."""
    ys = [v.co.y for v in ob.data.vertices] + [v.co.y for v in far.data.vertices]
    cy = (max(ys) + min(ys)) * 0.5
    road = spec["road"]

    def body(p):
        return (round(p[0], 3), round(p[2] + road, 3), round(-(p[1] - cy), 3))
    print("   (body space = Godot: x right, y up from the road as the game places it, z = -model y "
          "about the bbox centre %.3f; nose toward -z)" % cy)
    for name, p in spec.get("points", []):
        print("   POINT %-28s %s" % (name, body(p)))
    for name, lo, hi in spec.get("rects", []):
        print("   RECT  %-28s lo %s hi %s" % (name, body(lo), body(hi)))


def count_slot(ob, slot_name):
    me = ob.data
    me.calc_loop_triangles()
    n = 0
    for t in me.loop_triangles:
        if me.materials[t.material_index].name == slot_name:
            n += 1
    return n


# --- the fire engine ------------------------------------------------------------------------------

def fire_engine():
    """A Type 1 pumper on a custom chassis: a tilt crew cab with a flat face, a big screen, a
    chrome-trimmed grille and quad headlamps, a raised rear roof over the crew; an extended chrome
    bumper with a mechanical siren on its deck; the pump house with its panels and crosslays
    behind the cab; then the body: roll-up compartments both sides, a hose bed on top at the
    back, ground ladders racked on the kerb side, the tailboard."""
    s = {"name": "fire_engine", "length": 10.0, "height": 3.20}
    s.update({
        "nose": 4.50, "tail": 1.30,
        "front_axle": 3.50, "rear_axle": -1.50, "axle_z": 0.530,
        "axles": [(3.50, False), (-1.50, True)],
        "wheel_r": 0.530, "wheel_w": 0.315, "wheel_x": 1.035,
        "dual_x": 0.905, "dual_gap": 0.335,
        "arch_r": 0.660, "arch_r_rear": 0.700, "arch_in": 0.62, "arch_in_dual": 0.50,
        "road": -0.31, "belt_probe_z": 1.6,
        "cowl": 7.0, "deck": -1.0, "gh_blend_front": 0.1, "gh_blend_rear": 0.1,
        "crown_at": 0.60, "tension": 1.0, "under_j": 1.0,
        "rings": [0.0, 1.0, 1.6, 2.1, 2.85, 3.4, 3.92, 4.0, 4.08, 4.6, 5.0, 5.5, 6.0, 6.25,
                  6.5, 6.75, 7.0],
        "end_steps": [0.0, 0.02, 0.06, 0.12, 0.20, 0.30],
        "mid_step": 0.55,
        "extra_stations": [2.98, 2.88, 2.80, 2.70, 2.62, 2.52],
        "creases": [(6.0, 0.30, -7.0, 7.0)],
        "station_creases": [(2.88, 0.55, 5.6, 7.0), (2.62, 0.55, 5.6, 7.0)],
        "tangent_over": {5: (-0.02, 1.0), 6: (-0.12, 1.0), 7: (-1.0, 0.0)},
        "nose_cap": {"steps": 3, "roll": lambda j: 0.085, "dome": 0.030,
                     "lean": lambda co: 0.035 * ramp(co.z, 1.75, 1.0)},
        "tail_cap": {"steps": 2, "roll": lambda j: 0.040, "dome": 0.008},
        "sculpt": [],
        "profile": {
            "top": [(4.50, 2.880), (4.40, 2.935), (4.25, 2.950), (2.98, 2.955), (2.88, 2.960),
                    (2.80, 3.030), (2.70, 3.120), (2.62, 3.160), (1.40, 3.170), (1.30, 3.150)],
            "rail_z": [(4.50, 2.760), (4.40, 2.800), (4.25, 2.810), (2.98, 2.815), (2.88, 2.820),
                       (2.80, 2.890), (2.70, 2.980), (2.62, 3.020), (1.40, 3.030), (1.30, 3.015)],
            "rail_w": [(4.50, 1.150), (4.40, 1.195), (4.25, 1.205), (1.40, 1.205), (1.30, 1.185)],
            "roof_z": [(4.50, 2.866), (4.40, 2.922), (4.25, 2.938), (2.98, 2.943), (2.88, 2.948),
                       (2.80, 3.018), (2.70, 3.108), (2.62, 3.148), (1.40, 3.158), (1.30, 3.138)],
            "roof_w": [(4.50, 0.98), (4.30, 1.04), (1.40, 1.04), (1.30, 1.02)],
            "over_w": 1.0,
            "belt_z": 1.880,
            "belt_in": 0.018,
            "shoulder_z": 1.650,
            "width": [(4.50, 1.175), (4.46, 1.222), (4.38, 1.243), (4.25, 1.250),
                      (1.40, 1.250), (1.34, 1.242), (1.30, 1.225)],
            "low_z": 1.10,
            "low_in": 0.006,
            "sill_z": [(4.50, 0.700), (4.30, 0.670), (1.30, 0.670)],
            "sill_in": 0.030,
            "floor_z": [(4.50, 0.670), (4.30, 0.630), (1.30, 0.640)],
            "floor_in": 0.08,
        },
        # The body behind the cab: y front, y back, z bottom, z top, half width.
        "pump": (1.27, 0.48),
        "body": (0.46, -4.78, 0.50, 2.60, 1.25),
        "tailboard": -5.00,
    })
    s["details"] = fire_details
    return s


def fire_details(s, sec, surf, body, parts):
    nose = s["nose"]
    fa, ra = s["front_axle"], s["rear_axle"]
    az = s["axle_z"]
    points, rects = [], []
    s["points"], s["rects"] = points, rects

    def face_y(x, z):
        loc, _n = surf.end_hit(x, z, 1.0)
        return loc.y if loc is not None else nose + 0.08

    face_f = face_y(0.0, 1.4)

    # --- openings in the cab ------------------------------------------------------------------
    scr = rounded_outline([(-1.10, 1.86), (1.10, 1.86), (1.07, 2.74), (-1.07, 2.74)], 0.12)
    gb = bmesh.new()
    g = [[(-1.10 + 2.20 * c / 12, 1.86 + 0.88 * r / 8) for c in range(13)] for r in range(9)]
    res = hits_2d(surf, "front", g, 1.0)
    if res:
        p2, n2 = res
        oriented_grid(gb, [p - n * 0.030 for p, n in zip(p2, n2)], n2, 9, 13, GLASS)
    gk = bmesh.new()
    gasket(gk, surf, "front", rounded_outline([(-1.115, 1.845), (1.115, 1.845), (1.085, 2.755), (-1.085, 2.755)], 0.13))
    boolean(body, extrude_cutter(scr, "y", nose - 0.20, nose + 0.6))
    # The grille's mouth.
    mouth = rounded_outline([(-0.60, 0.98), (0.60, 0.98), (0.60, 1.62), (-0.60, 1.62)], 0.03)
    boolean(body, extrude_cutter(mouth, "y", nose - 0.10, nose + 0.6))
    # Side windows: the front door's (a big pane with a low rear corner) and the crew door's
    # (taller, under the raised roof); a small one in the raised roof's side over the crew seats.
    wins = [((2.74, 1.96), (2.06, 2.72)), ((1.92, 1.96), (1.40, 2.88))]
    for side in (1.0, -1.0):
        for (ya, za), (yb, zb) in wins:
            hole = rounded_outline([(ya, za), (yb, za), (yb, zb), (ya, zb)], 0.06)
            boolean(body, side_cutter(hole, side, 1.0), quiet=True)
            side_glass(gb, surf, side, ya, yb, za, zb)
            gasket(gk, surf, "side", rounded_outline([(ya + 0.012, za - 0.012), (yb - 0.012, za - 0.012),
                                                     (yb - 0.012, zb + 0.012), (ya + 0.012, zb + 0.012)], 0.07), side)
    parts.append(new_object("gaskets", gk))
    tidy(gb)
    parts.append(new_object("glass", gb))

    # --- face: grille, headlamps, warning lamps, wipers ------------------------------------------
    bp = bmesh.new()
    eggcrate(bp, -0.60, 0.60, 0.98, 1.62, face_f - 0.02, face_f - 0.08, 3, 9, thick=0.022, mat=CHROME)
    gp = surface_path(surf, "front", [(0.63, 1.65), (0.63, 0.95), (-0.63, 0.95), (-0.63, 1.65), (0.63, 1.65)], 1.0, step=0.03)
    if len(gp) > 4:
        sweep(bp, [p for p, _n in gp], [(-0.035, -0.004), (-0.025, 0.026), (0.025, 0.026), (0.035, -0.004)],
              CHROME, normals=[n for _p, n in gp])
    # A blank chrome plate over the grille (where a department crest would go).
    end_panel(bp, surf, 1.0, -0.42, 0.42, 1.68, 1.78, 0.012, CHROME, rows=1, cols=6, thickness=0.02)
    for side in (1.0, -1.0):
        # Quad headlamps in a chrome bezel, an amber-lensed indicator under them (light_front).
        hb = rect_grid(side * 0.70, side * 1.13, 0.98, 1.28, 2, 6)
        applied(bp, surf, "front", hb if side > 0 else hb, 0.010, CHROME, thickness=0.04)
        for xc in (0.80, 1.03):
            hl = rect_grid(side * (xc - 0.09), side * (xc + 0.09), 1.04, 1.22, 1, 3)
            applied(bp, surf, "front", hl, 0.020, LIGHT_F, thickness=0.012)
        ind = rect_grid(side * 0.72, side * 1.11, 0.90, 0.95, 1, 4)
        applied(bp, surf, "front", ind, 0.012, LIGHT_F, thickness=0.02)
    tidy(bp)
    parts.append(new_object("face", bp))

    lb = []  # every warning lens: closed boxes, no bevel
    for side in (1.0, -1.0):
        # Two lenses above each headlamp bezel (red outboard, white inboard), two on the grille's
        # corners, and one each side round the cab's front corners (side-facing).
        for x0, x1, m in ((0.94, 1.12, BEACON_R), (0.71, 0.89, BEACON_W)):
            yf = face_y(side * (x0 + x1) * 0.5, 1.40)
            xa, xb = sorted((side * x0, side * x1))
            lens(lb, xa, xb, yf - 0.01, yf + 0.025, 1.34, 1.46, m, facing="y+")
        yf = face_y(side * 0.50, 1.72)
        xa, xb = sorted((side * 0.46, side * 0.58))
        lens(lb, xa, xb, yf - 0.01, yf + 0.022, 1.66, 1.78, BEACON_R, facing="y+")
        loc, _n = surf.side_hit(4.22, 1.40, side)
        xs = abs(loc.x) if loc is not None else 1.25
        xa, xb = sorted((side * (xs - 0.01), side * (xs + 0.025)))
        lens(lb, xa, xb, 4.10, 4.32, 1.34, 1.46, BEACON_R, facing="x+" if side > 0 else "x-")
    # The light bar across the roof's front edge: a black extrusion with end caps, its lens
    # modules (each its own closed, bevelled box) sitting in it end to end.
    roof_y0, roof_y1 = 4.14, 4.44
    zb = 2.950
    bar = [(-1.01, 1.01, roof_y0, roof_y1, zb, zb + 0.045, TRIM),
           (-1.01, 1.01, roof_y0 + 0.11, roof_y1 - 0.11, zb + 0.045, zb + 0.125, TRIM)]
    for k in (-1, 1):
        bar.append((k * 0.55 - 0.035, k * 0.55 + 0.035, roof_y0 + 0.06, roof_y1 - 0.06, zb - 0.03, zb, TRIM))
    mods = [(0.004, 0.160, BEACON_W), (0.168, 0.330, BEACON_R), (0.338, 0.500, BEACON_W),
            (0.508, 0.700, BEACON_R), (0.708, 0.996, BEACON_R)]
    bar_lenses = []
    for x0, x1, m in mods:
        for side in (1.0, -1.0):
            xa, xb = sorted((side * x0, side * x1))
            bar_lenses.append((xa, xb, roof_y0 + 0.004, roof_y1 - 0.004, zb + 0.043, zb + 0.150, m))
    parts.append(box_obj("lightbar_lenses", bar_lenses, bevel=0.016, segments=2))
    points.append(("lightbar_centre", (0.0, (roof_y0 + roof_y1) * 0.5, zb + 0.095)))
    rects.append(("lightbar", (-1.0, roof_y0, zb), (1.0, roof_y1, zb + 0.15)))
    # Clearance lamps (amber, light_front) on the cab roof's front edge at the corners.
    clear = []
    for side in (1.0, -1.0):
        xa, xb = sorted((side * 1.06, side * 1.14))
        clear.append((xa, xb, 4.30, 4.42, 2.935, 2.975, LIGHT_F))
    parts.append(box_obj("lightbar", bar + clear, bevel=0.006))

    # --- bumper, siren, horns ---------------------------------------------------------------------
    yb0 = face_f - 0.02
    yb1 = 5.00
    bb = [
        (-1.25, 1.25, yb1 - 0.13, yb1, 0.40, 0.80, CHROME),  # face beam
        (-1.25, -1.13, yb0, yb1 - 0.05, 0.40, 0.80, CHROME),  # end caps
        (1.13, 1.25, yb0, yb1 - 0.05, 0.40, 0.80, CHROME),
        (-1.13, 1.13, yb0, yb1 - 0.12, 0.74, 0.775, SATIN),  # diamond-plate deck
        (-1.13, 1.13, yb0, yb1 - 0.12, 0.40, 0.44, TRIM),  # gravel pan
        (-0.36, -0.24, yb1 - 0.04, yb1 + 0.04, 0.34, 0.42, TRIM),  # tow eyes
        (0.24, 0.36, yb1 - 0.04, yb1 + 0.04, 0.34, 0.42, TRIM),
    ]
    parts.append(box_obj("bumper", bb, bevel=0.012))
    bm = bmesh.new()
    # Air horns in black recesses in the beam.
    for x in (-0.78, -0.58):
        box_into(bm, x - 0.09, x + 0.09, yb1 - 0.004, yb1 + 0.006, 0.50, 0.70, TRIM)
        cone = [Vector((x, yb1 - 0.05, 0.60)), Vector((x, yb1 + 0.010, 0.60))]
        sweep(bm, cone, lambda i: [(math.cos(2 * math.pi * k / 14) * (0.025 if i == 0 else 0.075),
                                    math.sin(2 * math.pi * k / 14) * (0.025 if i == 0 else 0.075)) for k in range(14)],
              CHROME, caps=True)
        disc_lamp(bm, x, yb1 + 0.011, 0.60, 0.062, TRIM, 1.0, depth=0.001, n=14, rim_mat=CHROME)
    # The mechanical siren: a chrome drum on a pedestal, its axis along the truck, a black grille
    # in its face and a domed back.
    sx, sz, sr = 0.50, 1.00, 0.165
    cylinder(bm, 0, sx, sz, sr, yb1 - 0.40, yb1 - 0.12, CHROME, n=24)
    cylinder(bm, 0, sx, sz, sr * 0.82, yb1 - 0.12, yb1 - 0.10, CHROME, n=24)
    disc_lamp(bm, sx, yb1 - 0.10, sz, sr * 0.72, TRIM, 1.0, depth=0.004, n=24, rim_mat=CHROME)
    for k in range(-3, 4):
        box_into(bm, sx - sr * 0.70 * math.sqrt(max(0.0, 1 - (k / 4.0) ** 2)),
                 sx + sr * 0.70 * math.sqrt(max(0.0, 1 - (k / 4.0) ** 2)),
                 yb1 - 0.096, yb1 - 0.088, sz + k * 0.034 - 0.007, sz + k * 0.034 + 0.007, CHROME)
    dome = [Vector((sx, yb1 - 0.40 - 0.07 * math.sin(math.pi * 0.5 * i / 5), sz)) for i in range(6)]
    sweep(bm, dome, lambda i: [(math.cos(2 * math.pi * k / 24) * sr * math.cos(math.pi * 0.5 * i / 5.6),
                                math.sin(2 * math.pi * k / 24) * sr * math.cos(math.pi * 0.5 * i / 5.6)) for k in range(24)],
          CHROME, caps=True)
    box_into(bm, sx - 0.10, sx + 0.10, yb1 - 0.36, yb1 - 0.16, 0.775, sz - sr + 0.02, CHROME)
    box_into(bm, sx - 0.15, sx + 0.15, yb1 - 0.39, yb1 - 0.13, 0.775, 0.79, CHROME)
    points.append(("siren", (sx, yb1 - 0.25, sz)))
    # Bumper-end warning lamps, side-facing, and lenses in the bumper face.
    for side in (1.0, -1.0):
        xa, xb = sorted((side * 1.250, side * 1.272))
        lens(lb, xa, xb, yb1 - 0.30, yb1 - 0.10, 0.52, 0.66, BEACON_R, facing="x+" if side > 0 else "x-")
        xa, xb = sorted((side * 0.95, side * 1.10))
        lens(lb, xa, xb, yb1 - 0.004, yb1 + 0.016, 0.54, 0.66, BEACON_W if side > 0 else BEACON_R, facing="y+")
    # Wipers parked along the screen's foot; the mirrors on their arms.
    for side in (1.0, -1.0):
        tube(bm, [Vector((side * 0.06, face_y(side * 0.06, 1.90) + 0.02, 1.90)),
                  Vector((side * 0.96, face_y(side * 0.96, 1.92) + 0.02, 1.92))], 0.011, TRIM, n=6)
        # West-coast mirror: two arms from the A-pillar to a tall head ahead of the door.
        hx, hy, hz = side * 1.47, 4.30, 2.10
        for z in (1.70, 2.36):
            tube(bm, [Vector((side * 1.20, 4.36, z)), Vector((side * 1.36, 4.40, z)), Vector((hx, hy, z))], 0.016, CHROME, n=8)
        tube(bm, [Vector((hx, hy, 1.70)), Vector((hx, hy, 2.36))], 0.014, CHROME, n=8)
        box_into(bm, hx - 0.065, hx + 0.065, hy - 0.05, hy + 0.05, hz - 0.02, hz + 0.40, TRIM)
        box_into(bm, hx - 0.055, hx + 0.055, hy - 0.053, hy - 0.050, hz + 0.01, hz + 0.37, CHROME)
        box_into(bm, hx - 0.06, hx + 0.06, hy - 0.045, hy + 0.045, hz - 0.30, hz - 0.08, TRIM)
        box_into(bm, hx - 0.050, hx + 0.050, hy - 0.048, hy - 0.045, hz - 0.28, hz - 0.10, CHROME)
    tidy(bm)
    parts.append(new_object("bumper_parts", bm))

    # --- cab sides: door lines, handles, grab rails, steps ---------------------------------------
    paths = []
    for side in (1.0, -1.0):
        paths.append(surface_path(surf, "side", [(2.80, 0.70), (2.80, 2.76), (2.02, 2.76), (2.02, 0.70)], side))
        paths.append(surface_path(surf, "side", [(1.98, 0.70), (1.98, 2.93), (1.36, 2.93), (1.36, 0.70)], side))
        # The cab's tilt line round the front of the arch's top.
        arc = circle_path(fa, az, s["arch_r"] + 0.04, 15.0, 165.0, 18)
        paths.append(surface_path(surf, "side", arc, side))
    cut_grooves(body, [p for p in paths if len(p) > 2])
    bt = bmesh.new()
    for side in (1.0, -1.0):
        loc, _n = surf.side_hit(2.4, 1.4, side)
        xs = abs(loc.x) if loc is not None else 1.25
        # Paddle handles near each door's trailing edge.
        for y in (2.12, 1.48):
            box_into(bt, side * (xs - 0.002), side * (xs + 0.022), y - 0.09, y + 0.09, 1.42, 1.48, CHROME)
            box_into(bt, side * (xs - 0.002), side * (xs + 0.010), y - 0.10, y + 0.10, 1.40, 1.50, TRIM)
        # Grab rails on the A-pillar and the cab's rear corner.
        for y, z0, z1 in ((2.88, 1.30, 2.55), (1.32, 0.95, 2.70)):
            tube(bt, [Vector((side * xs, y, z0)), Vector((side * (xs + 0.07), y, z0 + 0.04)),
                      Vector((side * (xs + 0.07), y, z1 - 0.04)), Vector((side * xs, y, z1))], 0.016, CHROME, n=8)
        # Steps under the doors: a lower step on hangers and a recessed upper one.
        for y0, y1 in ((2.76, 2.06), (1.94, 1.40)):
            box_into(bt, side * 0.90, side * 1.22, y1, y0, 0.40, 0.44, SATIN)
            box_into(bt, side * 0.90, side * 1.22, y1, y0, 0.36, 0.40, TRIM)
            for y in (y0 - 0.05, y1 + 0.05):
                box_into(bt, side * 1.0, side * 1.04, y - 0.02, y + 0.02, 0.40, 0.66, TRIM)
        # The stripe along the cab, broken by the arch.
        stripe_run(bt, side, xs, 4.30, 1.31, 0.74, 0.88, gaps=[(fa - s["arch_r"] - 0.05, fa + s["arch_r"] + 0.05)])
    tidy(bt)
    parts.append(new_object("cab_trims", bt))
    points.append(("lettering_cab_door_R", (1.26, 2.42, 1.30)))
    rects.append(("lettering_cab_door_R", (1.26, 2.75, 1.10), (1.26, 2.07, 1.55)))

    # --- the pump house -------------------------------------------------------------------------
    pf, pr = s["pump"]
    yf0, yr0, z0, z1, hw = s["body"]
    ph = bv.bevel_box("pump_house", (2.44, pf - pr, 2.24 - 0.48), (0.0, (pf + pr) * 0.5, (2.24 + 0.48) * 0.5), PAINT,
                      width=0.02, segments=2)
    parts.append(ph)
    pb = bmesh.new()
    for side in (1.0, -1.0):
        xs = 1.22
        # The panel: a brushed plate with a hinged light hood over it.
        box_into(pb, side * (xs - 0.01), side * (xs + 0.010), pr + 0.03, pf - 0.03, 0.56, 2.18, SATIN)
        box_into(pb, side * (xs - 0.01), side * (xs + 0.10), pr + 0.01, pf - 0.01, 2.18, 2.24, SATIN)
        box_into(pb, side * (xs + 0.02), side * (xs + 0.09), pr + 0.05, pf - 0.05, 2.165, 2.18, LIGHT_F)
        # Gauges: the two masters, a row of discharge gauges.
        for y in (pf - 0.24, pf - 0.48):
            gauge(pb, side, xs + 0.010, y, 1.96, 0.075)
        for k in range(4):
            gauge(pb, side, xs + 0.010, pf - 0.12 - k * 0.17, 1.72, 0.042)
        # Labels (blank tags) and the discharge valve T-handles.
        for k in range(4):
            y = pf - 0.12 - k * 0.17
            box_into(pb, side * (xs + 0.010), side * (xs + 0.014), y - 0.05, y + 0.05, 1.58, 1.62, TRIM)
            tube(pb, [Vector((side * (xs + 0.010), y, 1.42)), Vector((side * (xs + 0.10), y, 1.42))], 0.012, CHROME, n=8)
            tube(pb, [Vector((side * (xs + 0.10), y, 1.37)), Vector((side * (xs + 0.10), y, 1.47))], 0.014, CHROME, n=8)
        # The big intake (steamer) with its cap, and two capped discharges low down.
        cylinder(pb, (pf + pr) * 0.5 + 0.08, side * xs, 0.96, 0.14, side * (xs + 0.010), side * (xs + 0.10), CHROME, n=20, axis="x")
        cylinder(pb, (pf + pr) * 0.5 + 0.08, side * xs, 0.96, 0.16, side * (xs + 0.10), side * (xs + 0.17), CHROME, n=20, axis="x")
        for k in range(3):
            a = 2 * math.pi * k / 3
            yy = (pf + pr) * 0.5 + 0.08 + math.cos(a) * 0.17
            zz = 0.96 + math.sin(a) * 0.17
            box_into(pb, side * (xs + 0.11), side * (xs + 0.16), yy - 0.025, yy + 0.025, zz - 0.025, zz + 0.025, CHROME)
        for y in (pf - 0.14, pr + 0.14):
            cylinder(pb, y, side * xs, 0.80, 0.065, side * (xs + 0.010), side * (xs + 0.12), CHROME, n=14, axis="x")
            cylinder(pb, y, side * xs, 0.80, 0.075, side * (xs + 0.12), side * (xs + 0.16), CHROME, n=14, axis="x")
        # Running-board step under the panel.
        box_into(pb, side * 0.95, side * 1.30, pr, pf, 0.40, 0.44, SATIN)
        box_into(pb, side * 0.95, side * 1.30, pr, pf, 0.36, 0.40, TRIM)
    # Crosslays across the top of the pump house, between satin bulkheads.
    for y in (pf - 0.02, (pf + pr) * 0.5, pr + 0.02):
        box_into(pb, -1.22, 1.22, y - 0.012, y + 0.012, 2.24, 2.62, SATIN)
    box_into(pb, -1.22, 1.22, pr, pf, 2.22, 2.25, SATIN)
    tidy(pb)
    hb2 = bmesh.new()
    for ya, yb_ in ((pf - 0.03, (pf + pr) * 0.5 + 0.015), ((pf + pr) * 0.5 - 0.015, pr + 0.03)):
        crosslay(hb2, ya, yb_, 2.25, 7, 1.16)
    parts.append(new_object("pump_panel", pb))
    parts.append(new_object("crosslays", hb2))

    # --- the body ---------------------------------------------------------------------------------
    shell = bv.bevel_box("body_shell", (hw * 2.0, yf0 - yr0, z1 - z0), (0.0, (yf0 + yr0) * 0.5, (z0 + z1) * 0.5),
                         PAINT, width=0.025, segments=2)
    rR = s["arch_r_rear"]
    boolean(shell, arch_pocket(ra, az, rR, 0.48, flat_top=0.10))
    # The hose bed: a channel down from the top, open at the back.
    hb_x, hb_floor, hb_front = 0.98, 1.84, -0.42
    bmh = bmesh.new()
    box_into(bmh, -hb_x, hb_x, yr0 - 0.5, hb_front, hb_floor, z1 + 0.5, TRIM)
    boolean(shell, new_object("cut_hosebed", bmh))
    # Compartment openings: a shallow pocket per door (its walls are the dark reveal).
    comps = [(yf0 - 0.06, -0.74, 0.92, 2.46), (-0.80, -2.20, 1.42, 2.46),
             (-2.26, -3.48, 0.92, 2.46), (-3.54, -4.70, 0.92, 2.46)]
    cut = bmesh.new()
    for side in (1.0, -1.0):
        for ya, yb_, za, zb_ in comps:
            xa, xb = (hw - 0.035, hw + 0.2) if side > 0 else (-hw - 0.2, -hw + 0.035)
            box_into(cut, xa, xb, yb_, ya, za, zb_, TRIM)
    # Rear compartment under the hose bed.
    box_into(cut, -0.62, 0.62, yr0 - 0.2, yr0 + 0.035, 0.90, 1.66, TRIM)
    boolean(shell, new_object("cut_compartments", cut))
    parts.append(shell)
    bd = bmesh.new()
    for side in (1.0, -1.0):
        for ya, yb_, za, zb_ in comps:
            rollup_door(bd, side, hw - 0.022, ya, yb_, za, zb_)
        # Rub rail at the body's foot, the stripe above it (broken by the wheel well).
        gap = [(ra - rR - 0.12, ra + rR + 0.12)]
        for a, b in ((yf0 - 0.02, ra + rR + 0.10), (ra - rR - 0.10, yr0 + 0.02)):
            box_into(bd, side * (hw - 0.01), side * (hw + 0.030), b, a, 0.52, 0.60, CHROME)
            box_into(bd, side * (hw - 0.01), side * (hw + 0.018), b, a, 0.505, 0.52, TRIM)
        stripe_run(bd, side, hw, yf0 - 0.02, yr0 + 0.02, 0.74, 0.86, gaps=gap)
        # Polished fender trim round the well.
        fender_trim(bd, ra, az, rR, hw - 0.004, width=0.075, proud=0.010, a0=0.0, a1=180.0)
        # Drip rail over the compartments and the body's top cap.
        box_into(bd, side * (hw - 0.01), side * (hw + 0.035), yr0 + 0.02, yf0 - 0.02, 2.52, 2.545, SATIN)
        box_into(bd, side * (hw - 0.30), side * (hw + 0.02), yr0, yf0, z1 - 0.004, z1 + 0.018, SATIN)
        # Grab rails at the rear corners.
        tube(bd, [Vector((side * (hw - 0.10), yr0, 0.80)), Vector((side * (hw - 0.10), yr0 - 0.07, 0.84)),
                  Vector((side * (hw - 0.10), yr0 - 0.07, 2.30)), Vector((side * (hw - 0.10), yr0, 2.34))], 0.016, CHROME, n=8)
        # Mudflaps behind the duals, side marker lamps.
        mudflap(bd, side * 0.90, ra - 0.80, 0.18, 0.62, w=0.62)
        for y in (yf0 - 0.15, ra, yr0 + 0.15):
            box_into(bd, side * hw, side * (hw + 0.02), y - 0.04, y + 0.04, 2.40, 2.45, LIGHT_F if y > ra - 0.1 else LIGHT_R)
    rollup_rear(bd, yr0 - 0.022, -0.62, 0.62, 0.90, 1.66)
    chevrons(bd, yr0, -hw + 0.03, hw - 0.03, 0.55, 0.86)
    # Hose bed: satin floor and dividers.
    box_into(bd, -hb_x, hb_x, yr0 + 0.01, hb_front, hb_floor - 0.01, hb_floor + 0.005, SATIN)
    for x in (-0.33, 0.33):
        box_into(bd, x - 0.008, x + 0.008, yr0 + 0.02, hb_front, hb_floor, z1 - 0.06, SATIN)
    box_into(bd, -hb_x, hb_x, hb_front - 0.02, hb_front + 0.004, hb_floor, z1, SATIN)
    # Tailboard: a diamond-plate step the width of the body, on the frame ends.
    tb = s["tailboard"]
    box_into(bd, -hw, hw, tb, yr0 + 0.02, 0.46, 0.52, SATIN)
    box_into(bd, -hw + 0.02, hw - 0.02, tb + 0.01, yr0, 0.38, 0.46, TRIM)
    # Deck gun on the body's front top: a chrome riser, an elbow, the nozzle forward.
    tube(bd, [Vector((0.0, -0.05, z1)), Vector((0.0, -0.05, 2.86)), Vector((0.0, 0.05, 2.96)),
              Vector((0.0, 0.40, 2.98))], 0.055, CHROME, n=14)
    cylinder(bd, 0, 0.0, 2.98, 0.07, 0.40, 0.55, CHROME, n=14)
    box_into(bd, -0.18, 0.18, -0.25, 0.15, z1, z1 + 0.05, SATIN)
    tidy(bd)
    parts.append(new_object("body_parts", bd))
    hb3 = bmesh.new()
    for x0b, x1b in ((-hb_x + 0.01, -0.345), (-0.315, 0.315), (0.345, hb_x - 0.01)):
        hose_bed(hb3, x0b, x1b, hb_front - 0.05, yr0 + 0.03, hb_floor + 0.006, 12)
    parts.append(new_object("hose", hb3))
    rects.append(("lettering_body_rear", (-0.62, yr0 - 0.03, 1.70), (0.62, yr0 - 0.03, 1.84)))

    # Ground ladders on the kerb side (+x): an extension ladder and a roof ladder outboard of it,
    # on brackets off the body's top edge.
    lad = bmesh.new()
    ladder(lad, 1.0, hw + 0.06, -0.30, -4.55, 2.62, 3.08)
    ladder(lad, 1.0, hw + 0.10, -0.55, -4.30, 2.66, 3.04, rail_h=0.07)
    ladder(lad, 1.0, hw + 0.14, -0.70, -4.10, 2.68, 3.02, rail_h=0.065)
    for y in (-0.70, -2.45, -4.20):
        box_into(lad, hw - 0.20, hw + 0.20, y - 0.04, y + 0.04, z1 + 0.005, z1 + 0.04, TRIM)
        box_into(lad, hw + 0.18, hw + 0.21, y - 0.04, y + 0.04, z1 + 0.005, 3.12, TRIM)
        box_into(lad, hw + 0.03, hw + 0.21, y - 0.04, y + 0.04, 3.10, 3.13, TRIM)
    tidy(lad)
    parts.append(new_object("ladders", lad))
    points.append(("ladder_centre_R", (hw + 0.14, -2.4, 2.85)))

    # --- rear lamps ------------------------------------------------------------------------------
    rl = []
    ry = yr0
    for side in (1.0, -1.0):
        # Top corners: a red lens facing back and one facing the side, on the hose bed walls.
        xa, xb = sorted((side * 1.02, side * 1.22))
        lens(rl, xa, xb, ry - 0.025, ry + 0.005, 2.28, 2.48, BEACON_R, facing="y-")
        xa, xb = sorted((side * (hw - 0.004), side * (hw + 0.022)))
        lens(rl, xa, xb, ry + 0.08, ry + 0.30, 2.28, 2.44, BEACON_R, facing="x+" if side > 0 else "x-")
        # Mid-level red warning lamps on the rear face above the tail lamps.
        xa, xb = sorted((side * 0.86, side * 1.14))
        lens(rl, xa, xb, ry - 0.025, ry + 0.005, 1.56, 1.68, BEACON_R, facing="y-")
        # Tail lamps: stop / tail, turn and reverse in a vertical chrome-bezel stack.
        xa, xb = sorted((side * 0.84, side * 1.16))
        rl.append((xa, xb, ry - 0.015, ry + 0.005, 0.70, 1.50, CHROME))
        for k, (za, zb_, m) in enumerate(((1.27, 1.47, LIGHT_R), (1.04, 1.24, LIGHT_R), (0.82, 1.01, LIGHT_F))):
            xa, xb = sorted((side * 0.88, side * 1.12))
            rl.append((xa, xb, ry - 0.030, ry - 0.015, za, zb_, m))
    # The arrow stick under the hose bed's lip: eight clear lenses (amber in use) in a black bar.
    rl.append((-0.66, 0.66, ry - 0.030, ry + 0.005, 1.70, 1.82, TRIM))
    for k in range(8):
        x0 = -0.62 + 1.24 * k / 8 + 0.008
        x1 = -0.62 + 1.24 * (k + 1) / 8 - 0.008
        rl.append((x0, x1, ry - 0.042, ry - 0.030, 1.72, 1.80, BEACON_W))
    rects.append(("arrow_stick (beacon_white, amber)", (-0.62, ry - 0.042, 1.72), (0.62, ry - 0.042, 1.80)))
    # Side-facing warning lamps mid-body (over the rear wheels, under the compartment) and low at
    # the front of the body (under its first door).
    for side in (1.0, -1.0):
        xa, xb = sorted((side * hw, side * (hw + 0.022)))
        fx = "x+" if side > 0 else "x-"
        lens(rl, xa, xb, ra - 0.11, ra + 0.11, 1.325, 1.395, BEACON_R, facing=fx)
        lens(rl, xa, xb, yf0 - 0.31, yf0 - 0.09, 0.625, 0.715, BEACON_R, facing=fx)
    parts.append(box_obj("rear_lamps", rl, bevel=0.0))
    parts.append(box_obj("lenses", lb, bevel=0.0))
    points.append(("headlamp_centre_R", (0.915, face_f, 1.13)))
    points.append(("tail_lamp_centre_R", (1.0, ry - 0.03, 1.15)))

    # --- chassis: frame, front frame horns, rear underride, the battery boxes -----------------------
    bc = bmesh.new()
    frame_rails(bc, nose - 0.10, yr0 + 0.10, 0.78, x=0.46, h=0.28)
    for side in (1.0, -1.0):
        box_into(bc, side * 0.40, side * 0.95, ra + 1.15, pr + 0.10, 0.40, 0.75, TRIM)
        box_into(bc, side * 0.60, side * 0.95, yr0 + 0.4, ra - 1.0, 0.36, 0.70, TRIM)
    tidy(bc)
    parts.append(new_object("chassis", bc))
    planar_dissolve(body)


rc.SPECS["fire_engine"] = fire_engine


# --- the ambulance -------------------------------------------------------------------------------

# The cab is the panel van's cab (make_road_cars.van) cut off behind its B-pillar, with a lower car
# roof in place of the high roof and a longer bonnet; its keys are written in the van's stations
# and stretched forward of the cowl here.
AMB_COWL = 2.28
AMB_STRETCH = 1.80


def _amb_f(f):
    return AMB_COWL + (f - AMB_COWL) * AMB_STRETCH if f > AMB_COWL else f


def _amb_keys(keys):
    return [(_amb_f(f), v) for f, v in keys]


def ambulance():
    """A Type III ambulance: a cutaway van cab (short bonnet, a car roof) with a modular box behind
    it - flat sides with radiused vertical corners, a kerb-side entry door, two rear doors, small
    side windows, compartments on the street side, warning lamps at the box's top corners and
    mid-sides, a light header over the cab, scene lights, a rear step bumper, duals at the back."""
    s = {"name": "ambulance", "length": 6.90, "height": 2.95}
    tail = 1.00
    s.update({
        "nose": _amb_f(2.965), "tail": tail,
        "front_axle": 2.80, "rear_axle": -1.22, "axle_z": 0.380,
        "axles": [(2.80, False), (-1.22, True)],
        "wheel_r": 0.380, "wheel_w": 0.235, "wheel_x": 0.870,
        "dual_x": 0.775, "dual_gap": 0.255,
        "arch_r": 0.450, "arch_r_rear": 0.470, "arch_in": 0.58, "arch_in_dual": 0.48,
        "road": -0.22, "belt_probe_z": 1.5,
        "cowl": AMB_COWL, "deck": -4.0, "gh_blend_front": 0.12, "gh_blend_rear": 0.02,
        "crown_at": 0.60, "tension": 1.0, "under_j": 1.0,
        "rings": [0.0, 1.0, 1.6, 2.1, 2.85, 3.4, 3.92, 4.0, 4.08, 4.6, 5.0, 5.5, 6.0, 6.25,
                  6.5, 6.75, 7.0],
        "end_steps": [0.0, 0.012, 0.03, 0.06, 0.10, 0.16, 0.24],
        "mid_step": 0.45,
        "extra_stations": [_amb_f(f) for f in (2.52, 2.40, 2.34)] + [2.28, 2.22, 2.00, 1.80, 1.74],
        "creases": [(4.0, 0.5, -3.0, 4.0), (5.0, 0.45, 0.9, 2.20)],
        "station_creases": [(2.28, 0.5, 5.2, 7.0)],
        "nose_cap": {"steps": 3, "roll": lambda j: 0.050, "dome": 0.030,
                     "lean": lambda co: 0.025 * ramp(co.z, 0.90, 0.55)},
        "tail_cap": {"steps": 2, "roll": lambda j: 0.045, "dome": 0.010},
        "sculpt": [],
        "profile": {
            "top": _amb_keys([(2.965, 1.045), (2.94, 1.065), (2.88, 1.080), (2.75, 1.105),
                              (2.60, 1.135), (2.45, 1.170), (2.34, 1.200), (2.28, 1.225),
                              (2.20, 1.343), (2.10, 1.503), (2.00, 1.663), (1.90, 1.823),
                              (1.82, 1.935), (1.74, 2.010), (1.64, 2.060), (1.50, 2.085),
                              (1.10, 2.095), (1.00, 2.085)]),
            "rail_z": _amb_keys([(2.36, 1.18), (2.28, 1.205), (2.20, 1.328), (2.10, 1.488),
                                 (2.00, 1.648), (1.90, 1.808), (1.82, 1.910), (1.74, 1.965),
                                 (1.64, 1.995), (1.50, 2.005), (1.10, 2.010), (1.00, 2.000)]),
            "rail_w": _amb_keys([(2.36, 0.955), (2.28, 0.950), (2.00, 0.935), (1.80, 0.915),
                                 (1.60, 0.905), (1.10, 0.905), (1.00, 0.890)]),
            "belt_z": _amb_keys([(2.965, 1.020), (2.85, 1.060), (2.60, 1.110), (2.40, 1.160),
                                 (2.28, 1.195), (2.00, 1.230), (1.30, 1.255), (1.00, 1.258)]),
            "belt_in": 0.020,
            "shoulder_z": _amb_keys([(2.965, 0.860), (2.70, 0.930), (2.30, 0.990), (1.80, 1.020),
                                     (1.00, 1.035)]),
            "width": _amb_keys([(2.965, 0.905), (2.95, 0.950), (2.91, 0.985), (2.82, 1.002),
                                (2.60, 1.010), (2.10, 1.015), (1.00, 1.015)]),
            "low_z": 0.72,
            "low_in": 0.012,
            "sill_z": _amb_keys([(2.965, 0.380), (2.75, 0.440), (2.10, 0.455), (1.00, 0.450)]),
            "sill_in": 0.045,
            "floor_z": _amb_keys([(2.965, 0.360), (2.60, 0.350), (2.10, 0.320), (1.00, 0.320)]),
            "floor_in": 0.12,
        },
        # The module: y front, y back, z bottom, z top, half width, corner radius.
        "module": (1.02, -3.08, 0.66, 2.86, 1.175, 0.11),
        "step": -3.30,
    })
    s["details"] = ambulance_details
    return s


def amb_windows(s, sec):
    def side_j(f):
        lo = sec.j_along(f, 5.0, 0.024)
        hi = sec.j_along(f, 6.0, 0.024, -1.0)
        if hi < lo:
            lo = hi = (lo + hi) * 0.5
        return lo, hi

    def screen_j(f):
        return (sec.j_along(f, 6.0, 0.060), 7.0)
    return [
        {"name": "windscreen", "centre": True, "rows": 14, "cols": 12,
         "f": lambda j: (1.765, 2.262), "j": screen_j, "cut_shrink_j": 0.02},
        {"name": "cab", "centre": False, "rows": 8, "cols": 12,
         "f": lambda j: (1.320, 2.240), "j": side_j, "cut_shrink_j": 0.035},
    ]


def module_shell(name, y0, y1, z0, z1, hw, r):
    """The box: a plan outline with radiused vertical corners, extruded up, its top and bottom
    edges eased."""
    pts = rounded_outline([(-hw, y1), (hw, y1), (hw, y0), (-hw, y0)], r, n=6)
    bm = bmesh.new()
    ra = [bm.verts.new((x, y, z0)) for x, y in pts]
    rb = [bm.verts.new((x, y, z1)) for x, y in pts]
    n = len(pts)
    for k in range(n):
        k2 = (k + 1) % n
        quad(bm, ra[k], ra[k2], rb[k2], rb[k], PAINT)
    bm.faces.new(ra).material_index = PAINT
    bm.faces.new(list(reversed(rb))).material_index = PAINT
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = new_object(name, bm)
    mod = ob.modifiers.new("bev", 'BEVEL')
    mod.width = 0.03
    mod.segments = 3
    mod.limit_method = 'ANGLE'
    mod.angle_limit = math.radians(50.0)
    apply_modifiers(ob)
    return ob


class FlatSurf:
    """A Surface-like probe for the module's flat faces (cut_grooves only needs points and
    normals): side faces at |x| = hw, rear face at y = yr."""


def flat_path(pts2d, side=None, xs=None, yface=None, step=0.5):
    """Points and normals along a polyline drawn on a flat face: a side (y, z) at x = side * xs,
    or the rear (x, z) at y = yface (looking -Y)."""
    out = []
    for a, b in rc.densify(pts2d, step):
        if yface is None:
            out.append((Vector((side * xs, a, b)), Vector((side, 0.0, 0.0))))
        else:
            out.append((Vector((a, yface, b)), Vector((0.0, -1.0, 0.0))))
    return out


def ambulance_details(s, sec, surf, body, parts):
    nose = s["nose"]
    fa, ra = s["front_axle"], s["rear_axle"]
    az = s["axle_z"]
    points, rects = [], []
    s["points"], s["rects"] = points, rects
    my0, my1, mz0, mz1, hw, cr = s["module"]

    # --- cab: windows, lamps, grille, bumper, door lines ---------------------------------------
    wins = amb_windows(s, sec)
    rc.cut_windows(body, surf, wins)
    parts.append(rc.build_glass(surf, wins, 0.008))
    nf = _amb_f
    bmc = bmesh.new()
    bmp = bmesh.new()
    # Headlamps: tall composite lamps at the bonnet's front corners, a black grille between.
    for side in (1.0, -1.0):
        g = rect_grid(0.56, 0.88, 0.76, 0.99, 3, 8)
        g = g if side > 0 else mirror2(g)
        res = hits_2d(surf, "front", g, 1.0)
        if res:
            pts, nrm = res
            grid_solid(bmc, [p + n * 0.03 for p, n in zip(pts, nrm)],
                       [p - n * 0.020 for p, n in zip(pts, nrm)], len(g), len(g[0]), TRIM)
            oriented_grid(bmp, [p - n * 0.017 for p, n in zip(pts, nrm)], nrm, len(g), len(g[0]), GLASS)
        for xc, m in ((0.66, LIGHT_F), (0.80, LIGHT_F)):
            eye = rect_grid(xc - 0.05, xc + 0.05, 0.82, 0.93, 1, 3)
            applied(bmp, surf, "front", eye if side > 0 else mirror2(eye), -0.014, CHROME)
            lensg = rect_grid(xc - 0.04, xc + 0.04, 0.83, 0.92, 1, 3)
            applied(bmp, surf, "front", lensg if side > 0 else mirror2(lensg), -0.012, m)
        ind = rect_grid(0.58, 0.86, 0.775, 0.805, 1, 4)
        applied(bmp, surf, "front", ind if side > 0 else mirror2(ind), -0.012, LIGHT_F)
    mouth = rounded_outline([(-0.50, 0.99), (0.50, 0.99), (0.50, 0.60), (-0.50, 0.60)], 0.04)
    boolean(body, extrude_cutter(mouth, "y", nose - 0.15, nose + 0.6))
    fl, _n = surf.end_hit(0.0, 0.75, 1.0)
    face_f = fl.y if fl is not None else nose
    eggcrate(bmp, -0.50, 0.50, 0.60, 0.99, face_f - 0.02, face_f - 0.08, 12, 4, thick=0.014, mat=CHROME)
    gp = surface_path(surf, "front", [(0.53, 1.02), (0.53, 0.57), (-0.53, 0.57), (-0.53, 1.02), (0.53, 1.02)], 1.0, step=0.03)
    if len(gp) > 4:
        sweep(bmp, [p for p, _n in gp], [(-0.03, -0.004), (-0.02, 0.022), (0.02, 0.022), (0.03, -0.004)],
              CHROME, normals=[n for _p, n in gp])
    # Chrome bumper right across with black end caps; a black valance under it.
    wrap_band(bmp, surf, 1.0, 0.40, 0.58, 0.060, CHROME, reach=0.26, corner_r=0.18, thickness=0.07)
    # Licence plate recess (blank) and a step pad on the bumper's top.
    box_into(bmp, -0.17, 0.17, face_f + 0.05, face_f + 0.075, 0.43, 0.55, TRIM)
    tidy(bmc)
    boolean(body, new_object("cut_lamp_pockets", bmc))
    lb = []
    # Grille lights (warning) at the grille's ends, and side-facing intersection lights on the
    # front wings.
    for side in (1.0, -1.0):
        xa, xb = sorted((side * 0.30, side * 0.44))
        lens(lb, xa, xb, face_f - 0.03, face_f - 0.005, 0.70, 0.78, BEACON_R if side < 0 else BEACON_W, facing="y+")
        loc, _n = surf.side_hit(nf(2.72), 0.82, side)
        xs = abs(loc.x) if loc is not None else 1.0
        xa, xb = sorted((side * (xs - 0.012), side * (xs + 0.012)))
        lens(lb, xa, xb, nf(2.72) - 0.08, nf(2.72) + 0.08, 0.78, 0.85, BEACON_R, facing="x+" if side > 0 else "x-")
    paths = []
    for side in (1.0, -1.0):
        arc = circle_path(fa, az, s["arch_r"] + 0.05, 20.0, 160.0, 14)
        paths.append(surface_path(surf, "side", arc, side))
        # The cab door.
        paths.append(surface_path(surf, "side", [(2.24, 1.20), (2.20, 0.95), (2.20, 0.47), (1.28, 0.47),
                                                  (1.28, 2.02), (1.71, 2.02)], side))
        paths.append(rc.fj_path(surf, [(2.30, 5.40), (nf(2.935), 5.40)], side))
    cut_grooves(body, [p for p in paths if len(p) > 2])
    parts.append(new_object("cab_inserts", bmp))
    bt = bmesh.new()
    for side in (1.0, -1.0):
        rc.flush_handle(bmesh.new(), bt, surf, 1.44, 1.12, side, length=0.16, height=0.040, mat=CHROME)
    tidy(bt)
    parts.append(new_object("cab_trims", bt))
    for side in (1.0, -1.0):
        # Tall towing-style mirrors (an ambulance needs them past the wide box).
        rc.mirror(parts, surf, s, side, 2.22, 5.10, (1.32, 2.24, 1.62), (0.10, 0.08, 0.44), head_mat=TRIM)

    # --- the module -------------------------------------------------------------------------------
    sh = module_shell("module", my0, my1, mz0, mz1, hw, cr)
    boolean(sh, arch_pocket(ra, az, s["arch_r_rear"], 0.40, flat_top=0.10))
    # Openings: kerb-side entry door window, the small side windows, rear door windows.
    door_y = (my0 - 0.08, my0 - 0.86)      # kerb-side entry door (front of the box)
    door_z = (mz0 + 0.06, mz1 - 0.22)
    cuts = bmesh.new()
    gb = bmesh.new()
    dwin = (door_y[0] - 0.12, door_y[1] + 0.12, 1.66, 2.36)
    box_into(cuts, hw - 0.04, hw + 0.2, dwin[1], dwin[0], dwin[2], dwin[3], TRIM)
    flat_glass(gb, 1.0, hw - 0.012, dwin[1], dwin[0], dwin[2], dwin[3])
    swin = (-0.30, -0.98, 1.92, 2.36)
    for side in (1.0, -1.0):
        xa, xb = (hw - 0.04, hw + 0.2) if side > 0 else (-hw - 0.2, -hw + 0.04)
        box_into(cuts, xa, xb, swin[1], swin[0], swin[2], swin[3], TRIM)
        flat_glass(gb, side, hw - 0.012, swin[1], swin[0], swin[2], swin[3])
    rdx = 0.885   # the rear doors' outer edges
    for side in (1.0, -1.0):
        xa, xb = sorted((side * 0.13, side * (rdx - 0.14)))
        box_into(cuts, xa, xb, my1 - 0.2, my1 + 0.04, 1.62, 2.36, TRIM)
        rear_glass(gb, my1 + 0.012, xa, xb, 1.62, 2.36)
    boolean(sh, new_object("cut_module_windows", cuts))
    # Panel lines: the entry door, the compartment doors (street side), the rear doors.
    comps_l = [(my0 - 0.10, my0 - 0.80, 0.86, 2.56), (my0 - 0.86, -0.40, 0.86, 1.80),
               (ra - 0.62, my1 + 0.12, 0.86, 2.56)]
    comps_r = [(-0.10, -0.62, 0.86, 1.80), (ra - 0.62, my1 + 0.12, 0.86, 1.80)]
    gpaths = []
    gpaths.append(flat_path([(door_y[0], door_z[0]), (door_y[0], door_z[1]), (door_y[1], door_z[1]),
                             (door_y[1], door_z[0])], 1.0, hw))
    for side, comps in ((-1.0, comps_l), (1.0, comps_r)):
        for ya, yb_, za, zb_ in comps:
            gpaths.append(flat_path([(ya, za), (ya, zb_), (yb_, zb_), (yb_, za), (ya, za)], side, hw))
    gpaths.append(flat_path([(rdx, mz0 + 0.06), (rdx, mz1 - 0.18), (-rdx, mz1 - 0.18), (-rdx, mz0 + 0.06)], yface=my1))
    gpaths.append(flat_path([(0.0, mz0 + 0.06), (0.0, mz1 - 0.18)], yface=my1))
    parts.append(sh)
    gl = bmesh.new()
    gap_lines(gl, gpaths)
    parts.append(new_object("module_gaps", gl))
    gk = bmesh.new()
    for side, (y0, y1, z0, z1) in ((1.0, dwin), (1.0, swin), (-1.0, swin)):
        lo, hi = min(y0, y1), max(y0, y1)
        e = 0.018
        for (a0, a1, b0, b1) in ((lo - e, hi + e, z1, z1 + e), (lo - e, hi + e, z0 - e, z0),
                                 (lo - e, lo, z0, z1), (hi, hi + e, z0, z1)):
            box_into(gk, side * (hw - 0.004), side * (hw + 0.008), a0, a1, b0, b1, TRIM)
    for side in (1.0, -1.0):
        xa, xb = sorted((side * 0.13, side * (rdx - 0.14)))
        e = 0.018
        for (a0, a1, b0, b1) in ((xa - e, xb + e, 2.36, 2.36 + e), (xa - e, xb + e, 1.62 - e, 1.62),
                                 (xa - e, xa, 1.62, 2.36), (xb, xb + e, 1.62, 2.36)):
            box_into(gk, a0, a1, my1 - 0.008, my1 + 0.004, b0, b1, TRIM)
    tidy(gk)
    parts.append(new_object("module_gaskets", gk))
    tidy(gb)
    parts.append(new_object("module_glass", gb))

    md = bmesh.new()
    # Handles: the entry door's paddle and a grab rail beside it; compartment latches (chrome
    # paddles); the rear doors' handles and the rear grab rails.
    box_into(md, hw - 0.002, hw + 0.020, door_y[1] + 0.06, door_y[1] + 0.22, 1.30, 1.36, CHROME)
    tube(md, [Vector((hw, my0 + 0.04, 1.00)), Vector((hw + 0.06, my0 + 0.04, 1.04)),
              Vector((hw + 0.06, my0 + 0.04, 2.10)), Vector((hw, my0 + 0.04, 2.14))], 0.015, CHROME, n=8)
    for side, comps in ((-1.0, comps_l), (1.0, comps_r)):
        for ya, yb_, za, zb_ in comps:
            yc = (ya + yb_) * 0.5
            zc = za + 0.30 if zb_ - za > 1.2 else (za + zb_) * 0.5
            box_into(md, side * (hw - 0.002), side * (hw + 0.018), yc - 0.08, yc + 0.08, zc - 0.03, zc + 0.03, CHROME)
    for side in (1.0, -1.0):
        box_into(md, side * 0.06, side * 0.20, my1 - 0.020, my1 + 0.002, 1.40, 1.45, CHROME)
        tube(md, [Vector((side * (rdx + 0.13), my1, 1.00)), Vector((side * (rdx + 0.13), my1 - 0.06, 1.04)),
                  Vector((side * (rdx + 0.13), my1 - 0.06, 2.10)), Vector((side * (rdx + 0.13), my1, 2.14))],
             0.015, CHROME, n=8)
        # Hinges down the rear doors' outer edges.
        for z in (1.0, 1.75, 2.45):
            box_into(md, side * (rdx - 0.02), side * (rdx + 0.04), my1 - 0.03, my1 + 0.002, z - 0.07, z + 0.07, SATIN)
    # Rear step bumper: a diamond-plate tread on a black box, the width of the doors.
    st = s["step"]
    box_into(md, -1.05, 1.05, st, my1 + 0.02, 0.48, 0.54, SATIN)
    box_into(md, -1.05, 1.05, st + 0.01, my1, 0.34, 0.48, TRIM)
    # Side step under the entry door.
    box_into(md, 0.90, hw + 0.20, door_y[1] + 0.05, door_y[0] - 0.05, 0.40, 0.44, SATIN)
    box_into(md, 0.90, hw + 0.20, door_y[1] + 0.05, door_y[0] - 0.05, 0.36, 0.40, TRIM)
    # The box's underside: rub rail at its foot, fender trims, mudflaps, the frame and tank.
    for side in (1.0, -1.0):
        rR = s["arch_r_rear"]
        for a, b in ((my0 - 0.10, ra + rR + 0.12), (ra - rR - 0.12, my1 + 0.10)):
            box_into(md, side * (hw - 0.01), side * (hw + 0.022), b, a, mz0 + 0.02, mz0 + 0.09, TRIM)
        fender_trim(md, ra, az, rR, hw - 0.004, width=0.06, proud=0.008, a0=0.0, a1=180.0, z_min=mz0)
        mudflap(md, side * 0.80, ra - 0.62, 0.15, 0.60, w=0.50)
        # The reflective band along the box (a red stripe in the game), broken by the well and
        # the entry door is crossed by it.
        stripe_run(md, side, hw, my0 - 0.03, my1 + 0.06, 1.04, 1.20)
        stripe_run(md, side, hw, my0 - 0.03, my1 + 0.06, 1.24, 1.28)
        # Side marker lamps (amber front, red rear) low on the box.
        box_into(md, side * hw, side * (hw + 0.018), my0 - 0.20, my0 - 0.12, 0.80, 0.84, LIGHT_F)
        box_into(md, side * hw, side * (hw + 0.018), my1 + 0.12, my1 + 0.20, 0.80, 0.84, LIGHT_R)
    frame_rails(md, nose - 0.4, my1 + 0.1, 0.58, x=0.43, h=0.18)
    box_into(md, -0.30, 0.30, ra + 0.65, my0 - 0.4, 0.34, 0.60, TRIM)
    # The cab's stripe continues the box's along the doors.
    for side in (1.0, -1.0):
        side_panel(md, surf, 2.16, my0 + 0.02, 1.04, 1.20, 0.003, STRIPE, side, rows=2, cols=8, thickness=0.004)
    chevrons(md, my1, -rdx + 0.03, rdx - 0.03, 0.70, 1.30, pitch=0.24)
    tidy(md)
    parts.append(new_object("module_parts", md))
    points.append(("lettering_box_side_R", (hw, -1.85, 1.75)))
    rects.append(("lettering_box_side_R", (hw, -2.70, 1.45), (hw, -1.00, 2.05)))
    rects.append(("lettering_header_front", (-0.70, my0 + 0.01, 2.36), (0.70, my0 + 0.01, 2.58)))

    # --- warning, scene and clearance lamps on the box ---------------------------------------------
    for side in (1.0, -1.0):
        fx = "x+" if side > 0 else "x-"
        # Top corners, front and back: a lens on the end face and one on the side.
        for y_end, facing, yo in ((my0, "y+", 1.0), (my1, "y-", -1.0)):
            xa, xb = sorted((side * 0.80, side * 1.02))
            if facing == "y+":
                lens(lb, xa, xb, my0 - 0.004, my0 + 0.022, 2.58, 2.78, BEACON_R, facing="y+")
            else:
                lens(lb, xa, xb, my1 - 0.022, my1 + 0.004, 2.58, 2.78, BEACON_R, facing="y-")
            xa, xb = sorted((side * (hw - 0.004), side * (hw + 0.022)))
            y_mid = y_end - yo * 0.32
            lens(lb, xa, xb, y_mid - 0.13, y_mid + 0.13, 2.58, 2.76, BEACON_R, facing=fx)
        # Mid-side warning lamp, and the scene floods either side of it.
        xa, xb = sorted((side * (hw - 0.004), side * (hw + 0.022)))
        lens(lb, xa, xb, -1.15 - 0.13, -1.15 + 0.13, 2.58, 2.76, BEACON_R, facing=fx)
        for y in (my0 - 1.15, my1 + 0.62):
            ha, hb_ = sorted((side * (hw - 0.004), side * (hw + 0.024)))
            la, lb_ = sorted((side * (hw + 0.024), side * (hw + 0.032)))
            lb.append((ha, hb_, y - 0.175, y + 0.175, 2.585, 2.755, TRIM))
            lb.append((la, lb_, y - 0.16, y + 0.16, 2.60, 2.74, LIGHT_F))
        # Mid-level red warning lamp on the rear, beside the doors; the tail lamp stacks.
        x0, x1 = sorted((side * (rdx + 0.025), side * (hw - 0.03)))
        lens(lb, x0, x1, my1 - 0.022, my1 + 0.004, 1.56, 1.72, BEACON_R, facing="y-")
        for za, zb_, m in ((1.24, 1.44, LIGHT_R), (1.02, 1.22, LIGHT_R), (0.84, 1.00, LIGHT_F)):
            lb.append((x0, x1, my1 - 0.022, my1 + 0.004, za, zb_, m))
        lb.append((x0 - 0.01, x1 + 0.01, my1 - 0.012, my1 + 0.004, 0.82, 1.46, CHROME))
    # The light header over the cab: white warning lenses either side of a lit header panel (a
    # place for the word on the front), clearance lamps along the box's top front edge.
    for side in (1.0, -1.0):
        xa, xb = sorted((side * 0.48, side * 0.74))
        lens(lb, xa, xb, my0 - 0.004, my0 + 0.022, 2.60, 2.76, BEACON_W, facing="y+")
        for x in (0.20, 0.36):
            xa, xb = sorted((side * (x - 0.04), side * (x + 0.04)))
            lb.append((xa, xb, my0 - 0.004, my0 + 0.016, 2.79, 2.83, LIGHT_F))
            xa, xb = sorted((side * (x - 0.04), side * (x + 0.04)))
            lb.append((xa, xb, my1 - 0.016, my1 + 0.004, 2.79, 2.83, LIGHT_R))
        # Load lights over the rear doors.
        xa, xb = sorted((side * 0.30, side * 0.62))
        lb.append((xa, xb, my1 - 0.03, my1 + 0.004, 2.64, 2.70, LIGHT_F))
    lb.append((-0.70, 0.70, my0 - 0.004, my0 + 0.020, 2.36, 2.58, TRIM))
    lb.append((-0.66, 0.66, my0 + 0.020, my0 + 0.026, 2.39, 2.55, LIGHT_F))
    # A centre rear warning lamp (white) between the load lights, at the top.
    lens(lb, -0.14, 0.14, my1 - 0.022, my1 + 0.004, 2.60, 2.76, BEACON_W, facing="y-")
    parts.append(box_obj("module_lamps", lb, bevel=0.0))
    points.append(("header_centre", (0.0, my0 + 0.02, 2.47)))
    points.append(("headlamp_centre_R", (0.73, face_f, 0.815)))
    points.append(("tail_lamp_centre_R", (1.03, my1 - 0.02, 1.14)))
    # Roof: an air-conditioning pod and a vent.
    parts.append(bv.bevel_box("roof_ac", (0.80, 0.90, 0.16), (0.0, -0.40, mz1 + 0.08), TRIM, width=0.04))
    parts.append(bv.bevel_box("roof_vent", (0.40, 0.40, 0.06), (0.0, -2.10, mz1 + 0.03), TRIM, width=0.015))
    planar_dissolve(body)


rc.SPECS["ambulance"] = ambulance


# --- main ---------------------------------------------------------------------------------------------

PREVIEW = {"fire_engine": (0.42, 0.012, 0.012), "ambulance": (0.82, 0.82, 0.80)}


def views_for(spec):
    n = spec["nose"]
    H = spec.get("height", 3.0)
    L = spec["length"]
    t = n - L
    return [
        ("front3", (L * 0.55 + 2.0, n + L * 0.55, 2.4), (0.0, n - L * 0.35, H * 0.42), 40),
        ("rear3", (-L * 0.5 - 2.0, t - L * 0.45, 2.8), (0.0, t + L * 0.4, H * 0.45), 40),
        ("side", (L * 1.15, n - L * 0.5, 1.6), (0.0, n - L * 0.5, H * 0.45), 40),
        ("sideL", (-L * 1.15, n - L * 0.5, 1.6), (0.0, n - L * 0.5, H * 0.45), 40),
        ("front", (0.0, n + 10.0, 1.8), (0.0, n - 2.0, H * 0.45), 45),
        ("rear", (0.0, t - 10.0, 2.0), (0.0, t + 2.0, H * 0.45), 45),
        ("close", (3.4, n + 2.6, 1.7), (0.6, n - 1.0, 1.4), 35),
        ("top", (6.0, n - L * 0.5 + 2.0, 9.0), (0.0, n - L * 0.5, 1.0), 40),
    ]


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = [a for a in argv if not a.startswith("--")] or ["fire_engine"]
    do_render = "--render" in argv
    detail = "--nodetail" not in argv
    only_views = os.environ.get("VIEWS", "")
    for name in names:
        spec = rc.SPECS[name]()
        ob = bv.build(spec, detail)
        far = bv.build_far(ob, spec, (), target=spec.get("far_target", 9000))
        far.data.calc_loop_triangles()
        bv.report(ob, spec, far)
        print("   far twin: %d triangles" % len(far.data.loop_triangles))
        report_points(spec, ob, far)
        zz = [v.co.z for v in ob.data.vertices]
        lowv = min(ob.data.vertices, key=lambda v: v.co.z).co
        highv = max(ob.data.vertices, key=lambda v: v.co.z).co
        print("   model z %.3f..%.3f (low at %s, high at %s)" % (min(zz), max(zz), tuple(round(c, 2) for c in lowv), tuple(round(c, 2) for c in highv)))
        used = sorted({ob.data.materials[p.material_index].name for p in ob.data.polygons})
        print("   slots used: %s" % used)
        if "--noexport" not in argv:
            path = os.path.join(OUT_DIR, "road_%s.glb" % name)
            bv.export([ob, far], path)
            print("wrote", path)
        bpy.data.objects.remove(far, do_unlink=True)
        if do_render:
            views = views_for(spec)
            if only_views:
                views = [v for v in views if v[0] in only_views.split(",")]
            wh = bv.far_wheel_set(spec, 24)
            render_obj = join([ob, wh])
            rc.render_previews(render_obj, name, views, paint=PREVIEW.get(name, (0.8, 0.8, 0.8)))


if __name__ == "__main__":
    main()
