#!/usr/bin/env python3
"""The city's working vehicles: a side-loader garbage truck, a street sweeper, a rollback tow truck
and an ice-cream truck, built in Blender from code on tools/make_big_vehicles.py and
tools/make_emergency_vehicles.py (and through them make_road_cars.py's pipeline: the profile-curve
loft, booleans, raycast parts, material slots and the far twin):

    tools/road_cars_setup.sh                     # once: Blender 4.2 LTS into build/car_src/
    build/car_src/blender/blender-4.2.23-linux-x64/blender -b --factory-startup \\
        -P tools/make_service_vehicles.py -- garbage sweeper tow ice_cream [--render]

Writes assets/models/road_<name>.glb; then run `godot --headless --path . --import` (CLAUDE.md,
measurement trap 1). `--render` writes Cycles previews to $RENDER_DIR.

Conventions are the cars' and the big vehicles' (read both docstrings): X lateral, Y along the
vehicle with the NOSE AT +Y, Z up, ground at Z = 0; the vehicle's RIGHT (the kerb side, US traffic)
is +X. No wheels in the full model; a `<name>_far` twin with baked far wheels on every axle (and
the moving parts folded in at rest). The garbage truck, the sweeper and the tow truck stand on the
box truck's cab-over cab and chassis (BodyType.BOX_TRUCK's numbers: the same axles, arches and
WHEEL_POSE); the ice-cream truck on the ambulance's cutaway cab.

MOVING PARTS are their own objects named `rig_<part>`, each with its node origin at its pivot, so
the game (ServiceVehicles) turns or slides them with no bones:

  * garbage: `rig_boom` - the telescopic boom under the hopper with the mast at its outer end
    (slides along +X); `rig_lift` - the lift lever and the grabber's two claws, origin at the
    mast's top pivot, hanging straight down at rest (turns about the vehicle's length);
  * sweeper: `rig_brush_r` / `rig_brush_l` - the gutter brooms (spin about their hub's vertical);
    `rig_broom` - the main pickup broom under the body (spins about X);
  * tow: `rig_bed` - the rollback deck with its headboard and winch, origin at the tilt pivot
    over the rear axle (the game slides it back and tilts it).

Slots added to the others' (the run prints which are used):

  * `beacon_amber`: amber warning lenses (the game flashes them);
  * `brush`: broom bristles; `menu`: the ice-cream truck's menu boards (painted by the game's
    shader from the panel's position); `canvas`: its awning; `cone`, `scoop`: the roof sign.

Original designs: generic classes, no manufacturer's shapes, names or badges.
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_emergency_vehicles as emv  # noqa: E402  (imports make_big_vehicles and its slots)
import make_big_vehicles as bv  # noqa: E402
import make_road_cars as rc  # noqa: E402

from make_road_cars import (  # noqa: E402
    PAINT, GLASS, TRIM, CHROME, TYRE, LIGHT_F, LIGHT_R, log, new_object, boolean, quad, tidy,
    rounded_outline, join, apply_modifiers, extrude_cutter,
)
from make_big_vehicles import (  # noqa: E402
    bevel_box, box_into, tube, disc_lamp, cylinder, mudflap, quarter_fender,
)
from make_emergency_vehicles import SATIN, STRIPE, lens, box_obj  # noqa: E402

rc.SLOTS.append(("beacon_amber", (0.95, 0.42, 0.02), 0.0, 0.08, 0.6))
AMBER = len(rc.SLOTS) - 1
rc.SLOTS.append(("brush", (0.035, 0.034, 0.036), 0.0, 0.85, 0.0))
BRUSH = len(rc.SLOTS) - 1
rc.SLOTS.append(("menu", (0.90, 0.88, 0.82), 0.0, 0.35, 0.0))
MENU = len(rc.SLOTS) - 1
rc.SLOTS.append(("canvas", (0.85, 0.20, 0.25), 0.0, 0.80, 0.0))
CANVAS = len(rc.SLOTS) - 1
rc.SLOTS.append(("cone", (0.72, 0.48, 0.22), 0.0, 0.70, 0.0))
CONE = len(rc.SLOTS) - 1
rc.SLOTS.append(("scoop", (0.95, 0.60, 0.68), 0.0, 0.45, 0.0))
SCOOP = len(rc.SLOTS) - 1

OUT_DIR = rc.OUT_DIR


# --- helpers ---------------------------------------------------------------------------------------

def section(hw, z0, z1, rt, rb, n=6):
    """A body cross-section in (x, z): a rectangle with top corners of radius rt and bottom corners
    rb, anticlockwise from the bottom right."""
    return rounded_outline([(hw, z0), (hw, z1), (-hw, z1), (-hw, z0)], 0.0, n=1) if rt <= 0.0 and rb <= 0.0 else \
        _section(hw, z0, z1, rt, rb, n)


def _section(hw, z0, z1, rt, rb, n):
    out = []

    def arc(cx, cz, r, a0, a1):
        for k in range(n + 1):
            a = math.radians(a0 + (a1 - a0) * k / n)
            out.append((cx + math.cos(a) * r, cz + math.sin(a) * r))
    arc(hw - rb, z0 + rb, rb, -90.0, 0.0)
    arc(hw - rt, z1 - rt, rt, 0.0, 90.0)
    arc(-hw + rt, z1 - rt, rt, 90.0, 180.0)
    arc(-hw + rb, z0 + rb, rb, 180.0, 270.0)
    return out


def loft(bm, rings, mat, cap_front=True, cap_back=True):
    """Lofts closed (x, z) sections along y: `rings` is [(y, [(x, z)], dz, scale)], every section
    the same point count. Caps the ends with n-gons."""
    vs = []
    for y, pts, dz, sc in rings:
        vs.append([bm.verts.new((x * sc, y, z * sc + dz)) for x, z in pts])
    n = len(vs[0])
    for a, b in zip(vs, vs[1:]):
        for k in range(n):
            k2 = (k + 1) % n
            quad(bm, a[k], a[k2], b[k2], b[k], mat)
    if cap_front:
        bm.faces.new(vs[0]).material_index = mat
    if cap_back:
        bm.faces.new(list(reversed(vs[-1]))).material_index = mat


def bevelled(name, bm, width=0.025, segments=2, angle=40.0):
    tidy(bm)
    ob = new_object(name, bm)
    mod = ob.modifiers.new("bev", 'BEVEL')
    mod.width = width
    mod.segments = segments
    mod.limit_method = 'ANGLE'
    mod.angle_limit = math.radians(angle)
    apply_modifiers(ob)
    return ob


def rig(name, bm, pivot):
    """A moving part: its mesh moved so the object's origin is `pivot` (the game's node origin)."""
    tidy(bm)
    ob = new_object(name, bm)
    ob.data.transform(Matrix.Translation((-pivot[0], -pivot[1], -pivot[2])))
    ob.location = pivot
    return ob


def ribs(bm, side, xs, ys, z0, z1, w=0.05, proud=0.028, mat=PAINT):
    """Vertical stiffening ribs (hat sections) on a flat side at x = side * xs."""
    for y in ys:
        box_into(bm, side * (xs - 0.005) if side > 0 else side * (xs + proud), side * (xs + proud) if side > 0 else side * (xs - 0.005),
                 y - w * 0.5, y + w * 0.5, z0, z1, mat)


def xbox(bm, x0, x1, y0, y1, z0, z1, mat):
    """box_into with the x range in either order."""
    box_into(bm, min(x0, x1), max(x0, x1), min(y0, y1), max(y0, y1), min(z0, z1), max(z0, z1), mat)


def beacon(bm, x, y, z, r=0.085, h=0.14, n=12):
    """A round amber beacon on a black base."""
    cylinder(bm, 0.0, x, z + 0.025, r * 1.15, y - 0.0, y, TRIM, n=n, axis="z") if False else None
    _vcyl(bm, x, y, z, r * 1.2, 0.04, TRIM, n)
    _vcyl(bm, x, y, z + 0.04, r, h, AMBER, n)


def _vcyl(bm, x, y, z, r, h, mat, n=12):
    ra = [bm.verts.new((x + math.cos(2 * math.pi * k / n) * r, y + math.sin(2 * math.pi * k / n) * r, z)) for k in range(n)]
    rb = [bm.verts.new((x + math.cos(2 * math.pi * k / n) * r, y + math.sin(2 * math.pi * k / n) * r, z + h)) for k in range(n)]
    for k in range(n):
        k2 = (k + 1) % n
        quad(bm, ra[k], ra[k2], rb[k2], rb[k], mat)
    bm.faces.new(list(reversed(ra))).material_index = mat
    bm.faces.new(rb).material_index = mat


def strip_box_parts(parts):
    """The box truck's details add its cargo box; the service bodies replace it."""
    keep = []
    for o in parts:
        if o.name.startswith("box_"):
            bpy.data.objects.remove(o, do_unlink=True)
        else:
            keep.append(o)
    parts[:] = keep


def cab_truck(name, box):
    """The box truck's spec (its cab-over cab, chassis, axles) under another name, with `box` the
    body's footprint (y front, y rear, z floor, z top, half width) for the chassis' cross sills."""
    s = bv.box_truck()
    s["name"] = name
    s["box"] = box
    return s


# --- the garbage truck ------------------------------------------------------------------------------

# Where the arm works: the hopper's span along the truck, the boom's height, the mast's pivot.
GB_HOPPER = (2.02, 0.70)
GB_ARM_Y = 1.36
GB_BOOM_Z = 0.86
GB_PIVOT = (1.34, GB_ARM_Y, 2.02)
GB_LEVER = 1.30


def garbage():
    """A side-loading refuse truck: the box truck's cab and chassis with a hopper behind the cab
    (low on the kerb side where the arm tips the bins in), a tall rounded packer body with
    stiffening ribs, a tailgate hinged at the top on two lift cylinders, amber beacons, and the
    automated arm on the kerb side."""
    s = cab_truck("garbage", (2.06, -4.30, 1.10, 3.45, 1.22))
    s["details"] = garbage_details
    s["height"] = 3.55
    return s


def garbage_details(s, sec, surf, body, parts):
    bv.box_truck_details(s, sec, surf, body, parts)
    strip_box_parts(parts)
    hw = 1.24
    yh0, yh1 = GB_HOPPER
    z0 = 1.08
    # Packer body: a rounded section lofted from the hopper back to the tailgate seam.
    sec_main = _section(hw, z0, 3.42, 0.46, 0.06, 6)
    bm = bmesh.new()
    loft(bm, [(yh1, sec_main, 0.0, 1.0), (-3.62, sec_main, 0.0, 1.0)], PAINT)
    parts.append(bevelled("packer", bm, 0.03, 2, 35.0))
    # Tailgate: the same section, its back eased in and rounded over.
    tg = bmesh.new()
    sec_tg = _section(hw - 0.02, z0 + 0.04, 3.40, 0.48, 0.06, 6)
    loft(tg, [(-3.66, sec_tg, 0.0, 1.0), (-4.02, sec_tg, -0.02, 0.995), (-4.24, _section(hw - 0.10, z0 + 0.25, 3.18, 0.42, 0.10, 6), 0.0, 1.0),
              (-4.32, _section(hw - 0.22, z0 + 0.45, 2.98, 0.32, 0.10, 6), 0.0, 1.0)], PAINT)
    parts.append(bevelled("tailgate", tg, 0.02, 2, 30.0))
    # Hopper: a floor, a high street-side wall, a low kerb-side wall (the arm tips over it), the
    # front bulkhead behind the cab and the packer's front face with its opening above the walls.
    hp = bmesh.new()
    box_into(hp, -hw, hw, yh1, yh0, z0, z0 + 0.10, PAINT)
    box_into(hp, -hw, -hw + 0.06, yh1, yh0, z0, 2.95, PAINT)
    box_into(hp, hw - 0.06, hw, yh1, yh0, z0, 2.05, PAINT)
    box_into(hp, -hw, hw, yh0 - 0.06, yh0, z0, 3.05, PAINT)
    # The hopper's rolled top edges and a lip over the kerb side wall.
    tube(hp, [(hw - 0.02, yh1, 2.05), (hw - 0.02, yh0, 2.05)], 0.045, PAINT, n=10)
    tube(hp, [(-hw + 0.03, yh1, 2.95), (-hw + 0.03, yh0, 2.95)], 0.04, PAINT, n=10)
    tube(hp, [(-hw, yh0 - 0.03, 3.05), (hw, yh0 - 0.03, 3.05)], 0.04, PAINT, n=10)
    # The packer blade inside the hopper (seen over the low wall): a slanted dark plate.
    xbox(hp, -hw + 0.07, hw - 0.07, yh1 + 0.02, yh1 + 0.14, z0 + 0.1, 2.9, TRIM)
    # Ribs down both sides of the packer and the hopper's street side.
    ys = [yh1 - 0.35 - 0.62 * k for k in range(7)]
    for side in (1.0, -1.0):
        ribs(hp, side, hw - 0.04, ys, z0 + 0.12, 3.00)
        box_into(hp, min(side * (hw - 0.01), side * (hw + 0.035)), max(side * (hw - 0.01), side * (hw + 0.035)), -3.62, yh1, z0 + 0.02, z0 + 0.16, TRIM)
    ribs(hp, -1.0, hw - 0.02, [yh1 + 0.40, yh0 - 0.35], z0 + 0.12, 2.90)
    parts.append(bevelled("hopper", hp, 0.012, 1, 50.0))

    tr = bmesh.new()
    # Tailgate hinges at the top, the lift cylinders down each side, the locks, the sill.
    for side in (1.0, -1.0):
        xs = side * (hw + 0.02)
        for y in (-3.58, -3.72):
            xbox(tr, xs, xs + side * 0.04, y - 0.05, y + 0.05, 3.18, 3.34, TRIM)
        tube(tr, [(xs + side * 0.06, -3.40, 2.60), (xs + side * 0.06, -3.82, 3.05)], 0.055, TRIM, n=10)
        tube(tr, [(xs + side * 0.06, -3.82, 3.05), (xs + side * 0.06, -3.95, 3.20)], 0.026, CHROME, n=8)
        xbox(tr, xs, xs + side * 0.07, -3.50, -3.70, z0 + 0.10, z0 + 0.32, TRIM)
        # Amber beacons on the body's top corners, front and back; marker lamps along the side.
        for y in (yh0 - 0.10, -3.50):
            beacon(tr, side * 0.98, y, 3.43 if y < 0 else 3.07)
        for k in range(4):
            y = yh1 - 0.3 - 1.05 * k
            xbox(tr, side * (hw - 0.004), side * (hw + 0.022), y - 0.04, y + 0.04, 3.05, 3.11, LIGHT_F if k < 3 else LIGHT_R)
        # Tail lamps on the tailgate's foot, a work light over the hopper.
        for zc in (z0 + 0.48, z0 + 0.66):
            disc_lamp(tr, side * 0.88, -4.26, zc, 0.06, LIGHT_R, -1.0)
        disc_lamp(tr, side * 0.60, -4.25, z0 + 0.48, 0.045, LIGHT_F, -1.0)
        quarter_fender(tr, s["rear_axle"], s["axle_z"], s["wheel_r"], side * 0.60, side * 1.18)
        mudflap(tr, side * 0.86, s["rear_axle"] - 0.70, 0.22, 0.95)
    # The tailgate's seam band and a step ladder up the street side, a hose reel box.
    xbox(tr, -0.12, 0.12, -4.33, -4.29, 1.70, 2.20, TRIM)
    for k in range(4):
        z = 1.25 + 0.42 * k
        xbox(tr, -hw - 0.09, -hw - 0.01, -3.20, -2.84, z, z + 0.04, CHROME)
    tube(tr, [(-hw - 0.06, -3.22, 1.10), (-hw - 0.06, -3.22, 2.80)], 0.018, CHROME, n=6)
    tube(tr, [(-hw - 0.06, -2.82, 1.10), (-hw - 0.06, -2.82, 2.80)], 0.018, CHROME, n=6)
    # Hydraulic tank and the arm's valve block on the kerb side under the hopper.
    cylinder(tr, 0, 0.78, 0.78, 0.24, 0.60, -0.40, SATIN, n=14)
    xbox(tr, 0.35, 0.95, yh0 - 0.05, yh1 + 0.05, z0 - 0.22, z0, TRIM)
    # Arm guide channel under the hopper (the boom slides in it).
    xbox(tr, 0.20, hw + 0.04, GB_ARM_Y - 0.17, GB_ARM_Y + 0.17, GB_BOOM_Z + 0.09, GB_BOOM_Z + 0.16, TRIM)
    xbox(tr, 0.20, hw + 0.04, GB_ARM_Y - 0.17, GB_ARM_Y - 0.13, GB_BOOM_Z - 0.12, GB_BOOM_Z + 0.16, TRIM)
    xbox(tr, 0.20, hw + 0.04, GB_ARM_Y + 0.13, GB_ARM_Y + 0.17, GB_BOOM_Z - 0.12, GB_BOOM_Z + 0.16, TRIM)
    # A camera pod at the hopper's kerb corner (the driver watches the arm on a screen).
    xbox(tr, hw - 0.02, hw + 0.08, yh0 - 0.18, yh0 - 0.06, 2.10, 2.22, TRIM)
    parts.append(bevelled("garbage_trims", tr, 0.006, 1, 50.0))
    s["rig_nodes"] = garbage_arm()
    s["points"] = [("arm_pivot", GB_PIVOT), ("grab", (GB_PIVOT[0], GB_ARM_Y, GB_PIVOT[2] - GB_LEVER))]


def garbage_arm():
    """The arm in two moving parts: the boom (a telescopic beam in the guide channel with a mast up
    its outer end to the lift pivot) and the lift (a lever hanging from the pivot with the grabber's
    curved claws on its foot, which close round a bin)."""
    px, py, pz = GB_PIVOT
    bm = bmesh.new()
    # Boom: outer and inner sections, the mast, its gusset, the hose loop.
    xbox(bm, 0.22, px - 0.02, py - 0.11, py + 0.11, GB_BOOM_Z - 0.10, GB_BOOM_Z + 0.08, SATIN)
    xbox(bm, px - 0.30, px + 0.10, py - 0.13, py + 0.13, GB_BOOM_Z - 0.12, GB_BOOM_Z + 0.10, TRIM)
    xbox(bm, px - 0.02, px + 0.10, py - 0.12, py + 0.12, GB_BOOM_Z - 0.12, pz + 0.10, TRIM)
    xbox(bm, px - 0.20, px - 0.02, py - 0.03, py + 0.03, GB_BOOM_Z + 0.10, GB_BOOM_Z + 0.40, TRIM)
    tube(bm, [(px + 0.11, py - 0.07, GB_BOOM_Z), (px + 0.20, py - 0.07, (GB_BOOM_Z + pz) * 0.5), (px + 0.11, py - 0.07, pz - 0.15)], 0.016, TYRE, n=6)
    # The lift cylinder up the mast.
    tube(bm, [(px + 0.13, py + 0.06, GB_BOOM_Z + 0.05), (px + 0.13, py + 0.06, pz - 0.35)], 0.045, TRIM, n=10)
    tube(bm, [(px + 0.13, py + 0.06, pz - 0.35), (px + 0.13, py + 0.06, pz - 0.10)], 0.022, CHROME, n=8)
    boom = rig("rig_boom", bm, (0.22, py, GB_BOOM_Z))
    lm = bmesh.new()
    # Lift: the lever (a box beam with the pivot boss), the grabber frame and two claws.
    cylinder(lm, py, px, pz, 0.075, py - 0.16, py + 0.16, CHROME, n=14, axis="x") if False else None
    _ycyl(lm, px, pz, 0.08, py - 0.17, py + 0.17, CHROME)
    gz = pz - GB_LEVER
    xbox(lm, px + 0.10, px + 0.24, py - 0.07, py + 0.07, gz + 0.05, pz, SATIN)
    # Grabber frame: a crossbar along the truck at the lever's foot, the claws off its ends
    # curving outward round where the bin will be (a 0.62 m bin centred 0.40 m out).
    xbox(lm, px + 0.18, px + 0.30, py - 0.42, py + 0.42, gz - 0.10, gz + 0.12, TRIM)
    xbox(lm, px + 0.28, px + 0.34, py - 0.30, py + 0.30, gz - 0.22, gz + 0.22, TYRE)
    for sy in (1.0, -1.0):
        pts = []
        for k in range(7):
            a = math.radians(-8.0 + 70.0 * k / 6)
            pts.append((px + 0.33 + math.sin(a) * 0.36, py + sy * (0.40 - (1.0 - math.cos(a)) * 0.42), gz))
        prof = [(-0.025, -0.06), (0.025, -0.06), (0.025, 0.06), (-0.025, 0.06)]
        rc.sweep(lm, [Vector(p) for p in pts], prof, TRIM)
        tube(lm, [Vector(p) + Vector((0, 0, 0.065)) for p in pts], 0.012, TYRE, n=6)
    lift = rig("rig_lift", lm, GB_PIVOT)
    return [boom, lift]


def _ycyl(bm, x, z, r, y0, y1, mat, n=14):
    ra = [bm.verts.new((x + math.cos(2 * math.pi * k / n) * r, y0, z + math.sin(2 * math.pi * k / n) * r)) for k in range(n)]
    rb = [bm.verts.new((x + math.cos(2 * math.pi * k / n) * r, y1, z + math.sin(2 * math.pi * k / n) * r)) for k in range(n)]
    for k in range(n):
        k2 = (k + 1) % n
        quad(bm, ra[k], ra[k2], rb[k2], rb[k], mat)
    bm.faces.new(ra).material_index = mat
    bm.faces.new(list(reversed(rb))).material_index = mat


rc.SPECS["garbage"] = garbage


# --- the street sweeper -----------------------------------------------------------------------------

SW_BROOM = (0.0, -0.75, 0.34)        # main broom axis centre
SW_BROOM_R = 0.34
SW_GUTTER = (1.06, 1.80, 0.30)       # kerb-side gutter broom hub
SW_GUTTER_R = 0.50


def sweeper():
    """A truck-mounted street sweeper: the box truck's cab and chassis with a rounded debris hopper
    behind the cab, a water tank across the back, the gutter brooms either side between the axles,
    the main pickup broom under its hood, spray bars, an amber light bar and a strobe."""
    s = cab_truck("sweeper", (2.06, -4.25, 1.10, 3.05, 1.20))
    s["details"] = sweeper_details
    s["height"] = 3.30
    return s


def sweeper_details(s, sec, surf, body, parts):
    bv.box_truck_details(s, sec, surf, body, parts)
    strip_box_parts(parts)
    hw = 1.20
    z0 = 1.10
    # Debris hopper: a rounded box with a raked rear face (it tips back to dump).
    bm = bmesh.new()
    sh = _section(hw, z0, 3.02, 0.36, 0.08, 6)
    loft(bm, [(2.02, sh, 0.0, 1.0), (-2.30, sh, 0.0, 1.0), (-2.55, _section(hw - 0.04, z0 + 0.12, 2.92, 0.34, 0.08, 6), 0.0, 1.0)], PAINT)
    parts.append(bevelled("hopper", bm, 0.03, 2, 35.0))
    wt = bmesh.new()
    # Water tank across the back, lower and darker, a fill neck and a ladder.
    loft(wt, [(-2.62, _section(hw, z0 - 0.05, 2.30, 0.20, 0.10, 5), 0.0, 1.0), (-4.15, _section(hw, z0 - 0.05, 2.30, 0.20, 0.10, 5), 0.0, 1.0)], PAINT)
    parts.append(bevelled("tank", wt, 0.02, 2, 35.0))
    tr = bmesh.new()
    _vcyl(tr, -0.6, -3.4, 2.30, 0.12, 0.10, TRIM)
    for k in range(4):
        xbox(tr, -0.25, 0.25, -4.20, -4.16, 1.35 + 0.30 * k, 1.38 + 0.30 * k, CHROME)
    tube(tr, [(-0.27, -4.18, 1.20), (-0.27, -4.18, 2.35)], 0.016, CHROME, n=6)
    tube(tr, [(0.27, -4.18, 1.20), (0.27, -4.18, 2.35)], 0.016, CHROME, n=6)
    # Hopper hinge, dump cylinders, the rear seal frame.
    for side in (1.0, -1.0):
        tube(tr, [(side * (hw + 0.05), -1.6, 1.30), (side * (hw + 0.05), -2.35, 2.20)], 0.050, TRIM, n=10)
        xbox(tr, side * (hw - 0.01), side * (hw + 0.03), -2.48, -2.40, z0 + 0.10, 2.90, TRIM)
        # Ribs, the side access doors' frames, marker lamps.
        ribs(tr, side, hw - 0.03, [1.40, 0.40, -0.60, -1.60], z0 + 0.15, 2.90, proud=0.022)
        for k in range(3):
            y = 1.8 - 1.9 * k
            xbox(tr, side * (hw - 0.004), side * (hw + 0.022), y - 0.04, y + 0.04, 2.92, 2.98, LIGHT_F)
        for zc in (1.40, 1.58):
            disc_lamp(tr, side * 0.95, -4.16, zc, 0.06, LIGHT_R, -1.0)
        quarter_fender(tr, s["rear_axle"], s["axle_z"], s["wheel_r"], side * 0.60, side * 1.16)
        mudflap(tr, side * 0.86, s["rear_axle"] - 0.70, 0.18, 0.90)
        # Spray bars ahead of the brooms, with nozzles.
        tube(tr, [(side * 0.72, SW_GUTTER[1] + 0.55, 0.62), (side * 1.18, SW_GUTTER[1] + 0.55, 0.50)], 0.018, CHROME, n=6)
        for k in range(3):
            x = side * (0.82 + 0.13 * k)
            _vcyl(tr, x, SW_GUTTER[1] + 0.55, 0.43, 0.014, 0.06, CHROME, n=6)
        # The gutter broom's support arm from the frame to the hub.
        gx = side * SW_GUTTER[0]
        tube(tr, [(side * 0.45, SW_GUTTER[1] + 0.25, 0.80), (gx * 0.92, SW_GUTTER[1] + 0.15, 0.62), (gx, SW_GUTTER[1], SW_GUTTER[2] + 0.22)], 0.040, TRIM, n=8)
        _vcyl(tr, gx, SW_GUTTER[1], SW_GUTTER[2] + 0.14, 0.11, 0.12, TRIM)
    # The main broom's hood and the pickup head behind it, a conveyor housing up into the hopper.
    bx, by, bz = SW_BROOM
    hood = []
    for k in range(9):
        a = math.radians(15.0 + 150.0 * k / 8)
        hood.append((by + math.cos(a) * (SW_BROOM_R + 0.07), bz + math.sin(a) * (SW_BROOM_R + 0.07)))
    for (ya, za), (yb, zb) in zip(hood, hood[1:]):
        v = [tr.verts.new((-0.86, ya, za)), tr.verts.new((0.86, ya, za)), tr.verts.new((0.86, yb, zb)), tr.verts.new((-0.86, yb, zb))]
        tr.faces.new(v).material_index = TRIM
    for sx in (-0.88, 0.86):
        xbox(tr, sx, sx + 0.02, by - 0.45, by + 0.45, 0.10, bz + 0.42, TRIM)
    xbox(tr, -0.70, 0.70, -1.55, -1.10, 0.10, 0.60, TRIM)
    xbox(tr, -0.40, 0.40, -1.75, -1.25, 0.55, 1.10, SATIN)
    # Rubber skirts round the pickup head.
    xbox(tr, -0.95, 0.95, -1.62, -1.58, 0.03, 0.30, TYRE)
    # Amber light bar on the cab roof and a strobe on the hopper's top rear.
    xbox(tr, -0.70, 0.70, 2.30, 2.48, 2.55, 2.60, TRIM)
    for k in range(5):
        x = -0.56 + 0.28 * k
        lens(tr_lenses := [], x - 0.11, x + 0.11, 2.31, 2.47, 2.60, 2.72, AMBER) if False else None
    lb = []
    for k in range(5):
        x = -0.56 + 0.28 * k
        lb.append((x - 0.12, x + 0.12, 2.31, 2.47, 2.60, 2.72, AMBER))
    beacon(tr, 0.0, -2.20, 3.02, r=0.09, h=0.15)
    beacon(tr, 0.9, -3.9, 2.30, r=0.07, h=0.12)
    beacon(tr, -0.9, -3.9, 2.30, r=0.07, h=0.12)
    # A suction hose stowed on the hopper roof (the wand for drains).
    tube(tr, [(-0.6, 1.6, 3.10), (-0.6, -1.2, 3.10), (-0.2, -1.6, 3.10), (0.4, -1.6, 3.10)], 0.10, TYRE, n=12)
    for y in (1.2, 0.0, -1.0):
        xbox(tr, -0.75, -0.45, y - 0.04, y + 0.04, 3.00, 3.12, CHROME)
    parts.append(bevelled("sweeper_trims", tr, 0.006, 1, 50.0))
    parts.append(box_obj("sweeper_lamps", lb))
    s["rig_nodes"] = sweeper_brooms()


def gutter_broom(name, x, y, z, r):
    """A gutter broom: a steel disc on the hub with bundles of wire bristles splaying down and out
    to the road, origin at the hub (spins about its vertical)."""
    bm = bmesh.new()
    _vcyl(bm, x, y, z, r * 0.46, 0.06, SATIN, n=16)
    n = 28
    for k in range(n):
        a = 2 * math.pi * (k + 0.5) / n
        c, sn = math.cos(a), math.sin(a)
        p0 = Vector((x + c * r * 0.40, y + sn * r * 0.40, z + 0.02))
        p1 = Vector((x + c * r, y + sn * r, 0.015))
        d = (p1 - p0)
        side = Vector((-sn, c, 0.0)) * 0.035
        up = d.cross(side).normalized() * 0.010
        # A flat tapering bundle: a thin box between its two ends.
        v = [bm.verts.new(p0 - side - up), bm.verts.new(p0 + side - up), bm.verts.new(p1 + side * 1.6 - up), bm.verts.new(p1 - side * 1.6 - up),
             bm.verts.new(p0 - side + up), bm.verts.new(p0 + side + up), bm.verts.new(p1 + side * 1.6 + up), bm.verts.new(p1 - side * 1.6 + up)]
        for f in ((0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)):
            quad(bm, *[v[i] for i in f], BRUSH)
    return rig(name, bm, (x, y, z))


def sweeper_brooms():
    out = []
    for side, nm in ((1.0, "rig_brush_r"), (-1.0, "rig_brush_l")):
        out.append(gutter_broom(nm, side * SW_GUTTER[0], SW_GUTTER[1], SW_GUTTER[2], SW_GUTTER_R))
    bm = bmesh.new()
    bx, by, bz = SW_BROOM
    # Main broom: a core with rings of bristle strips around it.
    _xcyl(bm, by, bz, 0.10, -0.82, 0.82, SATIN)
    rows = 12
    for k in range(rows):
        a = 2 * math.pi * k / rows
        c, sn = math.cos(a), math.sin(a)
        for j in range(7):
            x0 = -0.78 + 1.56 * j / 7
            x1 = x0 + 1.56 / 7 - 0.02
            tw = 0.04
            p = lambda rr, dt: Vector((0.0, by + math.cos(a + dt) * rr, bz + math.sin(a + dt) * rr))
            pts = [p(0.10, -tw), p(0.10, tw), p(SW_BROOM_R, tw * 1.6), p(SW_BROOM_R, -tw * 1.6)]
            v0 = [bm.verts.new((x0, q.y, q.z)) for q in pts]
            v1 = [bm.verts.new((x1, q.y, q.z)) for q in pts]
            for i in range(4):
                i2 = (i + 1) % 4
                quad(bm, v0[i], v0[i2], v1[i2], v1[i], BRUSH)
            bm.faces.new(list(reversed(v0))).material_index = BRUSH
            bm.faces.new(v1).material_index = BRUSH
    out.append(rig("rig_broom", bm, SW_BROOM))
    return out


def _xcyl(bm, y, z, r, x0, x1, mat, n=14):
    ra = [bm.verts.new((x0, y + math.cos(2 * math.pi * k / n) * r, z + math.sin(2 * math.pi * k / n) * r)) for k in range(n)]
    rb = [bm.verts.new((x1, y + math.cos(2 * math.pi * k / n) * r, z + math.sin(2 * math.pi * k / n) * r)) for k in range(n)]
    for k in range(n):
        k2 = (k + 1) % n
        quad(bm, ra[k], ra[k2], rb[k2], rb[k], mat)
    bm.faces.new(list(reversed(ra))).material_index = mat
    bm.faces.new(rb).material_index = mat


rc.SPECS["sweeper"] = sweeper


# --- the tow truck ----------------------------------------------------------------------------------

TOW_BED = (2.02, -4.95)      # deck front and back (y)
TOW_DECK_Z = 1.30            # deck top
TOW_PIVOT = (0.0, -2.30, 1.02)


def tow():
    """A rollback car carrier: the box truck's cab and chassis under a 7 m steel deck that slides
    back and tilts to the road, with a headboard and its light bar, a winch, side rails with tie-down
    slots, toolboxes under the deck, the wheel-lift stowed under the tail, an amber light bar on the
    cab roof."""
    s = cab_truck("tow", (2.06, -4.30, 1.02, 1.04, 1.20))
    s["details"] = tow_details
    s["height"] = 3.10
    return s


def tow_details(s, sec, surf, body, parts):
    bv.box_truck_details(s, sec, surf, body, parts)
    strip_box_parts(parts)
    tr = bmesh.new()
    # Subframe and the tilt cylinders (shown at rest), the toolboxes either side.
    for sx in (0.50, -0.50):
        xbox(tr, sx - 0.07, sx + 0.07, -4.20, 1.95, 0.92, 1.12, TRIM)
    for side in (1.0, -1.0):
        tube(tr, [(side * 0.30, 0.6, 0.98), (side * 0.30, -1.6, 1.10)], 0.07, TRIM, n=10)
        tube(tr, [(side * 0.30, -1.6, 1.10), (side * 0.30, -2.0, 1.12)], 0.035, CHROME, n=8)
        xb0, xb1 = sorted((side * 0.62, side * 1.20))
        box_into(tr, xb0, xb1, 0.15, 1.80, 0.52, 1.12, SATIN)
        # Toolbox lids' latches, the grab handle.
        for y in (0.55, 1.40):
            xbox(tr, side * 1.20, side * 1.22, y - 0.06, y + 0.06, 1.00, 1.04, CHROME)
        quarter_fender(tr, s["rear_axle"], s["axle_z"], s["wheel_r"], side * 0.60, side * 1.16)
        mudflap(tr, side * 0.86, s["rear_axle"] - 0.70, 0.22, 0.95)
        # A work light on the cab's back corner.
        xbox(tr, side * 0.85, side * 1.00, 2.18, 2.24, 2.40, 2.52, TRIM)
        xbox(tr, side * 0.86, side * 0.99, 2.16, 2.18, 2.41, 2.51, LIGHT_F)
    # Amber light bar on the cab roof.
    xbox(tr, -0.75, 0.75, 3.00, 3.50, 2.55, 2.60, TRIM)
    lb = []
    for k in range(6):
        x = -0.625 + 0.25 * k
        lb.append((x - 0.11, x + 0.11, 3.02, 3.48, 2.60, 2.72, AMBER if k in (0, 2, 3, 5) else LIGHT_F))
    # Wheel-lift stowed under the tail: the boom, the crossbar and the two L-arms folded up.
    xbox(tr, -0.12, 0.12, -4.60, -3.40, 0.62, 0.80, TRIM)
    xbox(tr, -0.95, 0.95, -4.72, -4.58, 0.58, 0.78, SATIN)
    for side in (1.0, -1.0):
        xbox(tr, side * 0.70, side * 0.92, -4.74, -4.58, 0.78, 1.00, SATIN)
    bv.underride(tr, -4.30, 0.55, 1.10)
    parts.append(bevelled("tow_trims", tr, 0.006, 1, 50.0))
    parts.append(box_obj("tow_lamps", lb))
    s["rig_nodes"] = [tow_bed()]


def tow_bed():
    y0, y1 = TOW_BED
    z = TOW_DECK_Z
    hw = 1.22
    bm = bmesh.new()
    # Deck plate on longitudinal channels, its tail bevelled down to a thin edge for loading.
    xbox(bm, -hw + 0.10, hw - 0.10, y1 + 0.35, y0, z - 0.05, z, SATIN)
    v = [bm.verts.new(p) for p in ((-hw + 0.10, y1 + 0.35, z), (hw - 0.10, y1 + 0.35, z), (hw - 0.10, y1, z - 0.18), (-hw + 0.10, y1, z - 0.18))]
    bm.faces.new(v).material_index = SATIN
    for sx in (-0.50, 0.50):
        xbox(bm, sx - 0.08, sx + 0.08, y1 + 0.30, y0, z - 0.30, z - 0.05, TRIM)
    for k in range(7):
        y = y0 - 0.20 - (y0 - y1 - 0.6) * k / 6
        xbox(bm, -hw + 0.12, hw - 0.12, y - 0.04, y + 0.04, z - 0.22, z - 0.05, TRIM)
    # Side rails (the deck's edges) with tie-down slots, a stake pocket every metre.
    for side in (1.0, -1.0):
        xbox(bm, side * (hw - 0.10), side * hw, y1 + 0.05, y0, z - 0.26, z + 0.06, PAINT)
        n = int((y0 - y1) / 0.40)
        for k in range(1, n):
            y = y1 + 0.2 + (y0 - y1 - 0.4) * k / n
            xbox(bm, side * (hw - 0.004), side * (hw + 0.006), y - 0.10, y + 0.10, z - 0.15, z - 0.05, TRIM)
        for k in range(6):
            y = y0 - 0.5 - 1.05 * k
            xbox(bm, side * (hw - 0.02), side * (hw + 0.03), y - 0.05, y + 0.05, z - 0.30, z - 0.26, TRIM)
        # Tail lamps and markers on the deck's tail.
        disc_lamp(bm, side * 0.95, y1 - 0.004, z - 0.12, 0.05, LIGHT_R, -1.0)
        xbox(bm, side * (hw - 0.004), side * (hw + 0.018), y1 + 0.20, y1 + 0.30, z - 0.14, z - 0.08, LIGHT_R)
        xbox(bm, side * (hw - 0.004), side * (hw + 0.018), y0 - 0.30, y0 - 0.20, z - 0.14, z - 0.08, LIGHT_F)
    # Headboard: a frame with a mesh panel (a grid of bars) and a light bar on top.
    hz1 = z + 1.15
    for side in (1.0, -1.0):
        xbox(bm, side * (hw - 0.10), side * hw, y0 - 0.10, y0, z, hz1, PAINT)
    xbox(bm, -hw, hw, y0 - 0.10, y0, hz1 - 0.10, hz1, PAINT)
    xbox(bm, -hw, hw, y0 - 0.10, y0, z, z + 0.12, PAINT)
    for k in range(1, 9):
        x = -hw + 2 * hw * k / 9
        xbox(bm, x - 0.012, x + 0.012, y0 - 0.06, y0 - 0.04, z + 0.12, hz1 - 0.10, TRIM)
    for k in range(1, 4):
        zz = z + 0.12 + (hz1 - z - 0.22) * k / 4
        xbox(bm, -hw + 0.10, hw - 0.10, y0 - 0.06, y0 - 0.04, zz - 0.012, zz + 0.012, TRIM)
    xbox(bm, -0.70, 0.70, y0 - 0.12, y0 + 0.02, hz1, hz1 + 0.06, TRIM)
    for k in range(4):
        x = -0.52 + 0.35 * k
        xbox(bm, x - 0.12, x + 0.12, y0 - 0.12, y0 + 0.02, hz1 + 0.06, hz1 + 0.16, AMBER)
    # Winch at the headboard's foot, its cable running back along the deck to a hook.
    bx = 0.0
    _xcyl(bm, y0 - 0.32, z + 0.18, 0.13, -0.32, 0.32, TRIM)
    _xcyl(bm, y0 - 0.32, z + 0.18, 0.10, -0.25, 0.25, CHROME)
    xbox(bm, -0.42, 0.42, y0 - 0.55, y0 - 0.10, z, z + 0.06, TRIM)
    tube(bm, [(bx, y0 - 0.45, z + 0.12), (bx, y0 - 1.20, z + 0.03)], 0.008, CHROME, n=5)
    xbox(bm, -0.05, 0.05, y0 - 1.30, y0 - 1.18, z, z + 0.07, TRIM)
    return rig("rig_bed", bm, TOW_PIVOT)


rc.SPECS["tow"] = tow


# --- the ice-cream truck -----------------------------------------------------------------------------

def ice_cream():
    """An ice-cream truck: the ambulance's cutaway van cab with a shorter box behind it - a serving
    window on the kerb side under a striped awning with a stainless counter, menu boards round the
    window and down the street side, a giant cone on the roof, a loudspeaker horn for the chime,
    flashers, a rear step."""
    s = emv.ambulance()
    s["name"] = "ice_cream"
    s["module"] = (1.02, -3.00, 0.66, 2.78, 1.175, 0.12)
    s["details"] = ice_cream_details
    s["height"] = 3.55
    return s


def ice_cream_details(s, sec, surf, body, parts):
    # The cab is the ambulance's; reuse its whole detail pass and then replace the module's parts.
    emv.ambulance_details(s, sec, surf, body, parts)
    drop = ("module", "cut_module", "module_gaps", "module_gaskets", "module_glass", "module_parts", "module_lamps", "roof_ac", "roof_vent")
    keep = []
    for o in parts:
        if o.name.split(".")[0] in drop:
            bpy.data.objects.remove(o, do_unlink=True)
        else:
            keep.append(o)
    parts[:] = keep
    my0, my1, mz0, mz1, hw, cr = s["module"]
    ra, az = s["rear_axle"], s["axle_z"]
    sh = emv.module_shell("module", my0, my1, mz0, mz1, hw, cr)
    boolean(sh, emv.arch_pocket(ra, az, s["arch_r_rear"], 0.40, flat_top=0.10))
    # The serving window on the kerb side and a small one on the street side; rear door window.
    win = (-0.10, -1.85, 1.38, 2.22)
    cuts = bmesh.new()
    box_into(cuts, hw - 0.04, hw + 0.2, win[1], win[0], win[2], win[3], TRIM)
    box_into(cuts, -hw - 0.2, -hw + 0.04, -0.30, -0.90, 1.70, 2.25, TRIM)
    boolean(sh, new_object("cut_module_windows", cuts))
    parts.append(sh)
    gb = bmesh.new()
    # Two sliding panes, one pushed open behind the other; the inside of the box seen through.
    emv.flat_glass(gb, 1.0, hw - 0.04, win[1], (win[0] + win[1]) * 0.5 + 0.05, win[2], win[3])
    emv.flat_glass(gb, 1.0, hw - 0.07, (win[0] + win[1]) * 0.5 - 0.05, win[0], win[2], win[3])
    emv.flat_glass(gb, -1.0, hw - 0.012, -0.90, -0.30, 1.70, 2.25)
    tidy(gb)
    parts.append(new_object("module_glass", gb))
    md = bmesh.new()
    # Inside: a dark back wall and freezer chests (seen through the open pane), the counter.
    box_into(md, 0.10, 0.14, win[1], win[0], 0.70, 2.40, TRIM)
    box_into(md, 0.14, hw - 0.10, win[1] + 0.05, win[0] - 0.05, 0.70, 1.30, CHROME)
    box_into(md, hw - 0.02, hw + 0.22, win[1] - 0.05, win[0] + 0.05, 1.30, 1.36, CHROME)
    for y in (win[1] + 0.15, win[0] - 0.15):
        tube(md, [(hw + 0.02, y, 1.30), (hw + 0.20, y, 1.33)], 0.012, CHROME, n=6)
    # Window frame.
    e = 0.03
    for (a0, a1, b0, b1) in ((win[1] - e, win[0] + e, win[3], win[3] + e), (win[1] - e, win[0] + e, win[2] - e, win[2]),
                             (win[1] - e, win[1], win[2], win[3]), (win[0], win[0] + e, win[2], win[3]),
                             ((win[0] + win[1]) * 0.5 - 0.02, (win[0] + win[1]) * 0.5 + 0.02, win[2], win[3])):
        box_into(md, hw - 0.01, hw + 0.012, a0, a1, b0, b1, CHROME)
    # Menu boards: either side of the window and a long one along the street side.
    for (y0, y1, z0, z1) in ((my0 - 0.08, win[0] + 0.08, 1.05, 2.45), (win[1] - 0.08, my1 + 0.25, 1.05, 2.45)):
        box_into(md, hw - 0.004, hw + 0.012, y1, y0, z0, z1, MENU)
    box_into(md, -hw - 0.012, -hw + 0.004, my1 + 0.25, -1.00, 1.05, 2.45, MENU)
    box_into(md, -hw - 0.012, -hw + 0.004, -0.20, my0 - 0.08, 1.05, 1.62, MENU)
    # The back: a menu board over the step and the tail lamps.
    box_into(md, -0.85, 0.85, my1 - 0.012, my1 + 0.004, 1.45, 2.45, MENU)
    for side in (1.0, -1.0):
        for za, zb, m in ((1.12, 1.30, LIGHT_R), (0.94, 1.10, LIGHT_F)):
            box_into(md, min(side * 0.90, side * 1.10), max(side * 0.90, side * 1.10), my1 - 0.022, my1 + 0.004, za, zb, m)
        disc_lamp(md, side * 0.75, my0 + 0.012, mz1 - 0.12, 0.07, AMBER, 1.0)
        disc_lamp(md, side * 0.75, my1 - 0.012, mz1 - 0.12, 0.07, AMBER, -1.0)
        emv.fender_trim(md, ra, az, s["arch_r_rear"], hw - 0.004, width=0.06, proud=0.008, a0=0.0, a1=180.0, z_min=mz0)
        mudflap(md, side * 0.80, ra - 0.62, 0.15, 0.60, w=0.50)
        box_into(md, min(side * (hw - 0.01), side * (hw + 0.022)), max(side * (hw - 0.01), side * (hw + 0.022)), my1 + 0.10, my0 - 0.10, mz0 + 0.02, mz0 + 0.09, TRIM)
    box_into(md, -1.05, 1.05, s["step"] + 0.25, my1 + 0.02, 0.48, 0.54, SATIN)
    box_into(md, -1.05, 1.05, s["step"] + 0.26, my1, 0.34, 0.48, TRIM)
    rc.frame_rails if False else None
    bv.frame_rails(md, s["nose"] - 0.4, my1 + 0.1, 0.58, x=0.43, h=0.18)
    # Awning: a rolled canvas over the window on two arms.
    ay0, ay1 = win[1] - 0.15, win[0] + 0.15
    v = [md.verts.new(p) for p in ((hw + 0.02, ay1, 2.42), (hw + 0.02, ay0, 2.42), (hw + 0.62, ay0, 2.22), (hw + 0.62, ay1, 2.22))]
    md.faces.new(v).material_index = CANVAS
    v = [md.verts.new(p) for p in ((hw + 0.62, ay1, 2.22), (hw + 0.62, ay0, 2.22), (hw + 0.62, ay0, 2.10), (hw + 0.62, ay1, 2.10))]
    md.faces.new(v).material_index = CANVAS
    for y in (ay0 + 0.05, ay1 - 0.05):
        tube(md, [(hw, y, 1.95), (hw + 0.60, y, 2.20)], 0.012, CHROME, n=6)
    _xcyl_y = None
    tube(md, [(hw + 0.03, ay0, 2.45), (hw + 0.03, ay1, 2.45)], 0.05, CANVAS, n=10)
    tidy(md)
    parts.append(new_object("module_parts", md))
    # Roof: the cone sign (a waffle cone with two scoops) on a plinth, the loudspeaker horn.
    rm = bmesh.new()
    box_into(rm, -0.20, 0.20, -1.35, -0.95, mz1, mz1 + 0.10, TRIM)
    _cone(rm, 0.0, -1.15, mz1 + 0.10, 0.20, 0.62, CONE)
    _ball(rm, 0.0, -1.15, mz1 + 0.80, 0.22, SCOOP)
    _ball(rm, 0.0, -1.15, mz1 + 1.06, 0.18, MENU)
    box_into(rm, -0.15, 0.15, 0.30, 0.50, mz1, mz1 + 0.06, TRIM)
    _horn(rm, 0.0, 0.40, mz1 + 0.16)
    tidy(rm)
    parts.append(new_object("roof_sign", rm))
    emv.planar_dissolve(body) if False else None
    s["points"] = [("window", (hw, (win[0] + win[1]) * 0.5, (win[2] + win[3]) * 0.5)),
                   ("letter_side_R", (hw, -1.0, 2.55))]


def _cone(bm, x, y, z, r, h, mat, n=14):
    ring = [bm.verts.new((x + math.cos(2 * math.pi * k / n) * r, y + math.sin(2 * math.pi * k / n) * r, z + h)) for k in range(n)]
    tip = bm.verts.new((x, y, z))
    for k in range(n):
        bm.faces.new((tip, ring[(k + 1) % n], ring[k])).material_index = mat
    bm.faces.new(ring).material_index = mat


def _ball(bm, x, y, z, r, mat, n=12, m=8):
    rows = []
    for j in range(1, m):
        a = math.pi * j / m
        rows.append([bm.verts.new((x + math.sin(a) * math.cos(2 * math.pi * k / n) * r,
                                   y + math.sin(a) * math.sin(2 * math.pi * k / n) * r,
                                   z + math.cos(a) * r)) for k in range(n)])
    top = bm.verts.new((x, y, z + r))
    bot = bm.verts.new((x, y, z - r))
    for k in range(n):
        k2 = (k + 1) % n
        bm.faces.new((top, rows[0][k], rows[0][k2])).material_index = mat
        bm.faces.new((bot, rows[-1][k2], rows[-1][k])).material_index = mat
    for a, b in zip(rows, rows[1:]):
        for k in range(n):
            k2 = (k + 1) % n
            quad(bm, a[k], b[k], b[k2], a[k2], mat)


def _horn(bm, x, y, z, n=12):
    """A loudspeaker horn facing forward: a flared bell on a driver can."""
    rings = []
    for yy, r in ((y - 0.18, 0.06), (y - 0.05, 0.06), (y + 0.05, 0.09), (y + 0.15, 0.15), (y + 0.20, 0.17)):
        rings.append([bm.verts.new((x + math.cos(2 * math.pi * k / n) * r, yy, z + math.sin(2 * math.pi * k / n) * r)) for k in range(n)])
    for a, b in zip(rings, rings[1:]):
        for k in range(n):
            k2 = (k + 1) % n
            quad(bm, a[k], a[k2], b[k2], b[k], TRIM)
    bm.faces.new(list(reversed(rings[0]))).material_index = TRIM
    bm.faces.new(rings[-1]).material_index = TYRE


rc.SPECS["ice_cream"] = ice_cream


# --- main ---------------------------------------------------------------------------------------------

PREVIEW = {"garbage": (0.90, 0.90, 0.88), "sweeper": (0.92, 0.92, 0.90), "tow": (0.80, 0.08, 0.06),
           "ice_cream": (0.95, 0.95, 0.93)}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = [a for a in argv if not a.startswith("--")] or ["garbage"]
    do_render = "--render" in argv
    only_views = os.environ.get("VIEWS", "")
    for name in names:
        spec = rc.SPECS[name]()
        ob = bv.build(spec, True)
        rigs = spec.get("rig_nodes", [])
        for o in rigs:
            o.data.calc_loop_triangles()
            log("rig %-14s %6d triangles, pivot %s" % (o.name, len(o.data.loop_triangles), tuple(round(c, 3) for c in o.location)))
            rc.shade(o)
        far = bv.build_far(ob, spec, rigs, target=spec.get("far_target", 9000))
        far.data.calc_loop_triangles()
        bv.report(ob, spec, far)
        print("   far twin: %d triangles" % len(far.data.loop_triangles))
        ys = [v.co.y for v in ob.data.vertices] + [v.co.y for v in far.data.vertices]
        cy = (max(ys) + min(ys)) * 0.5
        road = spec["road"]
        for o in rigs:
            h = o.location
            print("   RIG %s pivot (body) %.3f %.3f %.3f" % (o.name, h.x, h.z + road, -(h.y - cy)))
        for nm, p in spec.get("points", []):
            print("   POINT %s (body) %.3f %.3f %.3f" % (nm, p[0], p[2] + road, -(p[1] - cy)))
        used = sorted({ob.data.materials[p.material_index].name for p in ob.data.polygons})
        print("   slots used: %s" % used)
        if "--noexport" not in argv:
            path = os.path.join(OUT_DIR, "road_%s.glb" % name)
            bv.export([ob] + rigs + [far], path)
            print("wrote", path)
        bpy.data.objects.remove(far, do_unlink=True)
        if do_render:
            views = emv.views_for(spec)
            if only_views:
                views = [v for v in views if v[0] in only_views.split(",")]
            wh = bv.far_wheel_set(spec, 24)
            render_obj = join([ob, wh] + rigs)
            rc.render_previews(render_obj, name, views, paint=PREVIEW.get(name, (0.8, 0.8, 0.8)))


if __name__ == "__main__":
    main()
