#!/usr/bin/env python3
"""The third wave of everyday road car bodies, so the street stops repeating: a compact EV hatch
(a closed face with a light bar, a black glass roof), a mid-size luxury sedan (a long bonnet, a
fastback deck, a chrome-barred mouth), a boxy compact SUV (round lamps, a slatted grille, a spare
wheel on the tailgate), a full-size crew-cab work truck (blacked-out trim, a cross-bed toolbox, a
ladder rack with a fibreglass ladder on it) and a 2-door sports coupe (a low roof, long doors, a
ducktail). Built with tools/make_road_cars.py's pipeline (its profile-curve loft, booleans,
raycast parts, the seven material slots and the far twin) and tools/make_more_cars.py's data-driven
detail builder, `everyday_details()`:

    tools/road_cars_setup.sh                     # once: Blender 4.2 LTS into build/car_src/
    build/car_src/blender/blender-4.2.23-linux-x64/blender -b --factory-startup \\
        -P tools/make_cars_3.py -- ev_hatch lux_sedan compact_suv work_truck coupe [--render]

Writes assets/models/road_<name>.glb, then run `godot --headless --path . --import` (CLAUDE.md,
measurement trap 1). The run prints each body's WHEEL_POSE row and `_dims()` numbers.

Every body is DERIVED from one of the older specs by station maps, so the loft (which is fussy)
is one that is known to build:

  * ev_hatch    the hatchback, CAB-FORWARD: the bonnet is squeezed and the screen's foot moved
                15 cm forward (`cab_forward()`), the face closed (a low intake only), lamps as
                thin blades joined by a full-width light bar, a full-width tail bar.
  * lux_sedan   the sedan with a LONG BONNET: everything ahead of the cowl stretched 24 cm, the
                front axle with it (dash-to-axle is what reads as a premium rear-drive saloon).
  * compact_suv the full-size SUV with its rear overhang cut and the whole car scaled to 88 %
                (93 % across) after the build, so the arches stay round round the scaled wheel.
  * work_truck  the pickup, its chrome blacked out (make_road_cars' CHROME rebound to TRIM while
                its details run), with a toolbox, a ladder rack and a ladder on it.
  * coupe       the sedan with shorter overhangs, the glasshouse dropped up to 9 cm, two long
                doors, a fixed quarter light and a ducktail.

Slots: the seven, plus `ladder` (the work truck's yellow fibreglass ladder; a plain StandardMaterial
in the game). Original designs, invented badges, no manufacturer's shapes or names.
"""

import copy
import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_road_cars as rc  # noqa: E402
import make_more_cars as mc  # noqa: E402

from make_road_cars import (  # noqa: E402
    PAINT, GLASS, TRIM, CHROME, TYRE, LIGHT_F, LIGHT_R, ramp, log, new_object, add_box,
    applied, fj_applied, rect_grid, blade_grid, mirror2, hits_2d, sweep, join,
)

rc.SLOTS.append(("ladder", (0.70, 0.46, 0.035), 0.0, 0.55, 0.0))
LADDER = len(rc.SLOTS) - 1


def clamp01(x):
    return min(max(x, 0.0), 1.0)


def piecewise(keys):
    """A monotone piecewise-linear station map through (old, new) keys, identity outside."""
    keys = sorted(keys)

    def fm(f):
        if f <= keys[0][0]:
            return f + (keys[0][1] - keys[0][0])
        for (a, a2), (b, b2) in zip(keys, keys[1:]):
            if f <= b:
                return a2 + (f - a) * (b2 - a2) / (b - a)
        return f + (keys[-1][1] - keys[-1][0])
    return fm


def map_profile(s, fm):
    """Applies a station map to the loft (make_more_cars.remap) - and to the axles, which remap
    leaves alone (it keeps the wheelbase)."""
    mc.remap(s, fm)
    s["front_axle"] = fm(s["front_axle"])
    s["rear_axle"] = fm(s["rear_axle"])


def lower(s, keys, w, amount):
    """Drops the profile curves `keys` by amount * w(f) (the coupe's glasshouse)."""
    for k in keys:
        s["profile"][k] = [(f, z - amount * w(f)) for f, z in s["profile"][k]]


def widen(s, k):
    s["profile"]["width"] = [(f, x * k) for f, x in s["profile"]["width"]]


def badge(bmp, surf, view, x, z, w, h, mat=CHROME):
    """An invented badge: a chevron of two slim bars, proud of the panel."""
    g = [[(x + w * 0.08 + w * 0.42 * c, z + h * (0.5 - 0.5 * c) + h * 0.35 * r - h * 0.18)
          for c in range(3)] for r in range(2)]
    applied(bmp, surf, view, g, 0.004, mat, thickness=0.004)
    applied(bmp, surf, view, mirror2(g), 0.004, mat, thickness=0.004)


# --- the compact EV hatch ----------------------------------------------------------------------

def ev_hatch():
    """A compact electric hatch (4.27 m): the hatchback's platform pulled cab-forward - a short
    sloping bonnet into a fast screen, a closed face with the lamps as thin blades joined by a
    light bar, a low intake only, flush handles, a black glass roof from the screen to the hatch
    and a full-width tail bar."""
    s = mc.hatchback()
    s["name"] = "ev_hatch"
    nose = s["nose"]
    # Cab-forward: the screen's foot from 0.86 to 1.01, the bonnet squeezed into what is left.
    g = piecewise([(0.06, 0.06), (0.86, 1.01), (nose, nose)])
    mc.remap(s, g)
    d = copy.copy(s["d"])
    fa = s["front_axle"]
    fm = mc.overhangs(1.29, -1.34, 2.135, -2.165, 2.065, -2.095)
    d["windows"] = [
        ("windscreen", "screen", g(0.10), g(0.84), 0.058),
        ("front", "side", -0.295, g(0.815)),
        ("rear", "side", -1.110, -0.395),
        ("quarter", "side", lambda j: fm(-1.62) + 0.12 * clamp01(0.0 if j is None else j - 5.0),
         -1.215),
        ("backlight", "screen", fm(-2.000), fm(-1.745), 0.050),
    ]
    # Thin lamp blades, a DRL line over each, no projector eyes.
    d["headlamp"] = {"blade": (0.40, 0.800, 0.680, 0.692, 0.026, 0.036),
                     "drl": (0.41, 0.790, 0.700, 0.710, 0.006, 0.007)}
    d.pop("lamp_band", None)
    # The closed face: one slim intake low in the bumper, nothing above it.
    d["grille"] = {"outline": [(-0.42, 0.405), (0.42, 0.405), (0.46, 0.335), (-0.46, 0.335)],
                   "round": 0.02, "cut_from": 2.00, "box": (-0.48, 0.48, 0.335, 0.405),
                   "y": (2.09, 2.03), "nv": 30, "nh": 2}
    d.pop("low", None)
    d["fogs"] = []
    d["front_band"] = (-0.70, 0.70, 0.268, 0.300)
    d["handles"] = [(g(0.28), 0.880), (-0.75, 0.905)]
    d["handle_mat"] = PAINT
    gs = d["gaps_side"]
    d["gaps_side"] = [
        [(g(0.835), 0.95), (g(0.828), 0.70), (g(0.820), 0.40), (g(0.815), 0.27)],
        gs[1],
        [(g(0.815), 0.27), (-0.352, 0.27)],
        [(g(fm(1.925)), 0.672), (g(fm(1.82)), 0.610), (g(fm(1.70)), 0.585), (fa + 0.362 + 0.03, 0.575)],
        gs[4],
    ]
    d["gaps_fj"] = [[(g(0.89), 5.40), (g(fm(2.115)), 5.40)], [(g(fm(2.115)), 5.40), (g(fm(2.115)), 7.0)]]
    d["sill_gap"] = (-0.352, 0.27)
    d["cowl"] = (g(0.83), g(0.90))
    d["belt_mat"] = GLASS
    d["tail"] = {
        "bar": (-0.62, 0.62, 0.962, 0.962, 0.013, 0.013),
        "bar_s": (-0.645, 0.645, 0.962, 0.962, 0.030, 0.030),
        "pieces": [
            ("glass", (0.50, 0.855, 0.958, 0.940, 0.060, 0.050, 2, 14)),
            ("red", (0.52, 0.845, 0.975, 0.958, 0.012, 0.010, 1, 14)),
            ("clear", (0.70, 0.78, 0.935, 0.935, 0.014, 0.014, 1, 3)),
            ("red", (0.62, 0.74, 0.43, 0.448, 1, 4)),
        ],
        "hmsl": (-0.14, 0.14, 1.285, 1.300),
    }
    d["mirror"] = (g(0.78), 5.05, (0.965, g(0.770), 0.990), (0.20, 0.080, 0.110))

    def extra(s, sec, surf, body, parts, bmt, bmp):
        # The light bar across the face, between the blades.
        applied(bmp, surf, "front", blade_grid(-0.40, 0.40, 0.694, 0.694, 0.0075, 0.0075, 1, 18),
                0.003, LIGHT_F, thickness=0.004)
        applied(bmp, surf, "front", blade_grid(-0.41, 0.41, 0.694, 0.694, 0.018, 0.018, 1, 18),
                0.0015, GLASS, thickness=0.003)
        badge(bmp, surf, "front", 0.0, 0.600, 0.075, 0.030)
        badge(bmt, surf, "rear", 0.0, 0.900, 0.070, 0.028)
        # The black glass roof, from the screen's head back to the spoiler.
        # (Fine rows and well proud: a coarse panel lets the curved roof poke through its cells.)
        fj_applied(bmt, surf, fm(-1.70), 0.08, lambda f: sec.j_along(f, 6.0, 0.06), 7.0, 44, 8,
                   0.006, GLASS, 1.0, thickness=0.004, centre=True)
        # An aero blade along the bottom of each door.
        for side in (1.0, -1.0):
            fj_applied(bmt, surf, -1.34 + 0.40, fa - 0.40, 1.80, 2.15, 1, 24, 0.008, GLASS, side,
                       thickness=0.008)

    d["extra"] = extra
    s["d"] = d
    s["details"] = mc.everyday_details
    return s


# --- the luxury sedan -----------------------------------------------------------------------------

def lux_sedan():
    """A mid-size luxury saloon (5.18 m): the sedan's cabin and tail on a bonnet 24 cm longer
    (the front axle moves with it), a fastback deck with a lip, slim lamps over a tall
    chrome-barred mouth in a chrome surround, a full-width tail bar and twin exhaust tips."""
    s = rc.sedan()
    s["name"] = "lux_sedan"
    h = piecewise([(1.06, 1.06), (1.50, 1.74), (2.345, 2.585)])
    map_profile(s, h)
    # Lower and longer reading: the roof down 2 cm over the rear seats into the fastback.
    lower(s, ("top", "rail_z"), lambda f: ramp(f, 0.4, -0.4) * ramp(f, -2.0, -1.2), 0.02)
    s["d"] = {
        "windows": [
            ("windscreen", "screen", 0.14, 0.99, 0.058),
            ("front", "side", -0.055, 0.950),
            ("rear", "side", lambda j: -1.24 + 0.20 * clamp01(0.0 if j is None else j - 5.0), -0.140),
            ("backlight", "screen", -1.930, -0.860, 0.050),
        ],
        "headlamp": {"blade": (0.38, 0.840, 0.640, 0.624, 0.036, 0.048),
                     "drl": (0.39, 0.830, 0.660, 0.646, 0.007, 0.008),
                     "eyes": [0.54, 0.64, 0.74], "eye_z": 0.632, "eye_w": 0.026, "eye_h": 0.010},
        "grille": {"outline": [(-0.33, 0.610), (0.33, 0.610), (0.37, 0.360), (-0.37, 0.360)],
                   "round": 0.045, "cut_from": 2.50, "box": (-0.39, 0.39, 0.360, 0.610),
                   "y": (2.635, 2.570), "bars": 6, "bar_t": 0.014,
                   "surround": (-0.385, 0.385, 0.348, 0.622, 0.022)},
        "low": {"outline": [(-0.58, 0.318), (0.58, 0.318), (0.62, 0.272), (-0.62, 0.272)],
                "cut_from": 2.48, "box": (-0.64, 0.64, 0.272, 0.318), "y": (2.62, 2.56),
                "nv": 34, "nh": 1},
        "front_band": (-0.66, 0.66, 0.252, 0.272),
        "plate": (-0.265, 0.265, 0.505, 0.645),
        "handles": [(0.30, 0.880), (-0.66, 0.892)],
        "handle_mat": CHROME,
        "gaps_side": [
            [(1.00, 0.945), (0.995, 0.80), (0.985, 0.55), (0.98, 0.30)],
            [(-0.098, 0.99), (-0.098, 0.30)],
            [(h(2.215), 0.665), (h(2.13), 0.610), (h(2.03), 0.575), (h(1.50) + 0.388 + 0.03, 0.56)],
            [(-2.255, 0.905), (-2.20, 0.78), (-2.05, 0.66), (-1.33 - 0.388 - 0.03, 0.60)],
        ],
        "rear_door": (-1.02, 1.012, 0.045, 44.3, -12.0),
        "sill_gap": (0.98, 0.30),
        "gaps_fj": [[(1.07, 5.40), (h(2.325), 5.40)], [(h(2.325), 5.40), (h(2.325), 7.0)],
                    [(-1.985, 5.40), (-2.335, 5.40)]],
        "gaps_rear": [[(0.715, 1.008), (0.705, 0.902), (0.0, 0.895), (-0.705, 0.902), (-0.715, 1.008)],
                      [(0.835, 0.83), (0.80, 0.70), (0.72, 0.655), (0.0, 0.648), (-0.72, 0.655),
                       (-0.80, 0.70), (-0.835, 0.83)]],
        "fuel": (-1.56, 0.905),
        "black_pillars": [(-0.147, -0.048)],
        "black_dividers": [(-1.032, -1.010)],
        "belt_trim": (-1.23, 0.94),
        "belt_mat": CHROME,
        "rocker": (1.75, 2.25, CHROME),
        "cowl": (0.990, 1.062),
        "spoiler": (-2.30, -2.21, 0.009),
        "tail": {
            "bar": (-0.60, 0.60, 0.955, 0.955, 0.011, 0.011),
            "bar_s": (-0.62, 0.62, 0.955, 0.955, 0.026, 0.026),
            "pieces": [
                ("glass", (0.50, 0.860, 0.950, 0.940, 0.058, 0.046, 2, 14)),
                ("red", (0.52, 0.850, 0.968, 0.955, 0.014, 0.012, 1, 14)),
                ("red", (0.60, 0.845, 0.925, 0.920, 0.008, 0.007, 1, 12)),
                ("red", (0.64, 0.74, 0.43, 0.448, 1, 4)),
            ],
        },
        "rear_band": (-0.62, 0.62, 0.305, 0.425),
        "rear_chrome": [(0.38, 0.56, 0.330, 0.372), (-0.56, -0.38, 0.330, 0.372)],
        "mirror": (0.88, 5.05, (0.985, 0.835, 1.005), (0.20, 0.085, 0.115)),
        "extra": lambda s, sec, surf, body, parts, bmt, bmp: (
            badge(bmp, surf, "front", 0.0, 0.660, 0.085, 0.032),
            badge(bmt, surf, "rear", 0.0, 0.870, 0.080, 0.030)),
    }
    s["details"] = mc.everyday_details
    return s


# --- the boxy compact SUV --------------------------------------------------------------------------

COMPACT_K = 0.88    # length and height (and the arches, so they stay round round the wheel)
COMPACT_KX = 0.93   # across


def compact_suv():
    """A boxy compact SUV (4.46 m, 1.70 m once scaled): the full-size SUV's square body with its
    rear overhang cut short and the whole car scaled down, an upright face with round lamps and
    a slatted black grille, black cladding and bumpers, roof rails, square tail lamps and a spare
    wheel on the tailgate."""
    s = mc.suv()
    s["name"] = "compact_suv"
    fm = mc.overhangs(1.70, -1.37, 2.665, -2.665, 2.665, -2.42)
    mc.remap(s, fm)
    fa, ra = 1.70, -1.37
    d = copy.copy(s["d"])
    d["windows"] = [
        ("windscreen", "screen", 0.07, 0.985, 0.062),
        ("front", "side", -0.330, 0.960),
        ("rear", "side", -1.395, -0.430),
        ("quarter", "side", fm(-2.430), fm(-1.500)),
        ("backlight", "screen", fm(-2.605), fm(-2.555), 0.060),
    ]
    d["headlamp"] = {"round": [(0.705, 0.104)], "z": 1.025}
    d["grille"] = {"outline": [(-0.52, 1.120), (0.52, 1.120), (0.52, 0.860), (-0.52, 0.860)],
                   "round": 0.03, "cut_from": 2.58, "box": (-0.53, 0.53, 0.860, 1.120),
                   "y": (2.665, 2.60), "nv": 2, "nh": 4, "thick": 0.030}
    d["low"] = {"outline": [(-0.46, 0.640), (0.46, 0.640), (0.42, 0.560), (-0.42, 0.560)],
                "cut_from": 2.56, "box": (-0.48, 0.48, 0.560, 0.640), "y": (2.64, 2.58),
                "nv": 12, "nh": 1}
    d["fogs"] = [(0.70, 0.80, 0.600, 0.630)]
    d["front_bumper"] = (0.470, 0.720, 0.045, TRIM)
    d["skid"] = (-0.44, 0.44, 0.475, 0.520)
    d.pop("handle_mat", None)
    d["handle_mat"] = TRIM
    gs = d["gaps_side"]
    d["gaps_side"] = gs[:4] + [[(fm(-2.55), 1.10), (fm(-2.50), 0.95), (fm(-2.35), 0.86),
                                (ra - 0.468 - 0.04, 0.84)]]
    d["fuel"] = (fm(-1.95), 1.18)
    d["belt_trim"] = (fm(-2.43), 0.97)
    d["belt_mat"] = TRIM
    d["rocker"] = (1.7, 2.3, TRIM)
    d["roof_rail"] = (-0.10, fm(-2.35), 6.75, 0.055)
    d["rail_mat"] = TRIM
    d["spoiler"] = (fm(-2.53), fm(-2.43), 0.014)
    d["gaps_rear"] = [[(0.80, 1.80), (0.82, 1.30), (0.82, 0.86), (0.0, 0.855), (-0.82, 0.86),
                       (-0.82, 1.30), (-0.80, 1.80)]]
    d["tail"] = {
        "pieces": [
            ("glass", (0.745, 0.905, 1.040, 1.420, 4, 2)),
            ("red", (0.760, 0.895, 1.200, 1.405, 3, 2)),
            ("red", (0.760, 0.895, 1.055, 1.120, 1, 2)),
            ("clear", (0.760, 0.895, 1.130, 1.190, 1, 2)),
        ],
        "hmsl": (-0.18, 0.18, 1.845, 1.870),
    }
    d.pop("rear_chrome", None)
    d["rear_bumper"] = (0.500, 0.760, 0.045, TRIM)
    d["rear_skid"] = (-0.40, 0.40, 0.520, 0.545)
    d["cladding"] = (0.095, 0.022)

    def extra(s, sec, surf, body, parts, bmt, bmp):
        badge(bmp, surf, "front", 0.0, 1.160, 0.080, 0.032)
        # The spare wheel on the tailgate, under a hard black cover.
        res = hits_2d(surf, "rear", [[(0.0, 1.27)]], 1.0)
        if res:
            y0 = res[0][0].y
            tb = bmesh.new()
            r, w = 0.335, 0.215
            rot = Matrix.Rotation(math.pi * 0.5, 4, 'X')
            bmesh.ops.create_cone(tb, cap_ends=True, segments=32, radius1=r, radius2=r, depth=w,
                                  matrix=Matrix.Translation((0.0, y0 - w * 0.5 - 0.03, 1.27)) @ rot)
            for fc in tb.faces:
                fc.material_index = TYRE
            cover = bmesh.new()
            bmesh.ops.create_cone(cover, cap_ends=True, segments=32, radius1=r * 0.97,
                                  radius2=r * 0.80, depth=0.05,
                                  matrix=Matrix.Translation((0.0, y0 - w - 0.055, 1.27)) @ rot)
            for fc in cover.faces:
                fc.material_index = TRIM
            # The bracket from the gate to the hub.
            add_box(cover, (0.10, 0.06, 0.10), (0.0, y0 - 0.02, 1.27), TRIM)
            for b in (tb, cover):
                bmesh.ops.recalc_face_normals(b, faces=b.faces)
            parts.append(new_object("spare_cover", cover))
            parts.append(new_object("spare", tb))

    d["extra"] = extra
    s["d"] = d
    s["details"] = mc.everyday_details
    s["post_scale"] = (COMPACT_KX, COMPACT_K)
    # Where the physics wheels meet the road (body space) for its 0.336 m physics tyre.
    s["road"] = -0.173
    return s


def apply_post_scale(ob, s):
    """Scales the built body (x across, y and z alike) and every spec number the far twin and
    the report read."""
    kx, k = s["post_scale"]
    ob.scale = (kx, k, k)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for key in ("front_axle", "rear_axle", "axle_z", "wheel_r", "wheel_w", "arch_r", "arch_r_rear",
                "nose", "tail", "length", "height", "belt_probe_z"):
        if key in s:
            s[key] *= k
    s["wheel_x"] *= kx
    s["arch_in"] *= kx


# --- the work truck --------------------------------------------------------------------------------

def work_truck():
    """A full-size crew-cab work truck: the pickup in its work trim - every chrome part of it
    (grille surround, slats, bumpers, step) in black - with a cross-bed toolbox, a steel ladder
    rack over the bed, a yellow fibreglass ladder on it running forward over the cab, a hitch
    receiver and mud flaps."""
    s = rc.pickup()
    s["name"] = "work_truck"
    base = s["details"]

    def details(s, sec, surf, body, parts):
        keep = rc.CHROME
        rc.CHROME = TRIM
        try:
            base(s, sec, surf, body, parts)
        finally:
            rc.CHROME = keep
        bm = bmesh.new()
        rail_z, rail_x = 1.384, 0.955
        # Cross-bed toolbox behind the cab, sitting on the rails, black, with chrome latches.
        add_box(bm, (1.96, 0.46, 0.25), (0.0, -1.42, rail_z + 0.125 + 0.008), TRIM)
        add_box(bm, (1.98, 0.48, 0.02), (0.0, -1.42, rail_z + 0.258), TRIM)
        for x in (-0.62, 0.62):
            add_box(bm, (0.12, 0.012, 0.035), (x, -1.66, rail_z + 0.20), CHROME)
        # The rack: two hoops over the bed, two rails along the top.
        top = 2.06
        for f in (-1.80, -2.86):
            for side in (1.0, -1.0):
                add_box(bm, (0.055, 0.055, top - rail_z), (side * (rail_x - 0.035), f,
                                                          (top + rail_z) * 0.5), TRIM)
                add_box(bm, (0.14, 0.12, 0.015), (side * (rail_x - 0.035), f, rail_z + 0.0075), TRIM)
            add_box(bm, (2.0 * rail_x - 0.02, 0.06, 0.06), (0.0, f, top), TRIM)
        # The rails run on forward over the cab to a bar on two feet on the roof's drip rails.
        for side in (1.0, -1.0):
            add_box(bm, (0.05, 3.25, 0.05), (side * (rail_x - 0.035), -1.285, top + 0.055), TRIM)
            add_box(bm, (0.05, 0.05, top - 1.95), (side * 0.80, 0.25, (top + 1.95) * 0.5), TRIM)
            add_box(bm, (0.16, 0.10, 0.02), (side * 0.80, 0.25, 1.96), TRIM)
            add_box(bm, (0.16, 0.06, 0.05), (side * 0.87, 0.25, top + 0.03), TRIM)
        add_box(bm, (2.0 * rail_x - 0.02, 0.06, 0.06), (0.0, 0.25, top + 0.055), TRIM)
        # A strobe bar on the front hoop (amber lenses read as the tail lamps' red off).
        add_box(bm, (0.70, 0.08, 0.05), (0.0, -1.80, top + 0.06), TRIM)
        for x in (-0.24, 0.24):
            add_box(bm, (0.16, 0.085, 0.035), (x, -1.80, top + 0.07), LIGHT_R)
        # Hitch receiver under the step, mud flaps behind each wheel.
        add_box(bm, (0.065, 0.36, 0.065), (0.0, -3.06, 0.50), TRIM)
        add_box(bm, (0.10, 0.03, 0.10), (0.0, -3.24, 0.50), TRIM)
        for f in (s["front_axle"] - 0.50, s["rear_axle"] - 0.53):
            for side in (1.0, -1.0):
                add_box(bm, (0.30, 0.012, 0.28), (side * 0.86, f, 0.30), TYRE)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        parts.append(new_object("rack", bm))
        # The ladder: two rails and rungs, on the hoops, overhanging the cab to the screen.
        lb = bmesh.new()
        lz, ly0, ly1, lx = top + 0.13, -2.98, 0.70, 0.215
        for side in (1.0, -1.0):
            add_box(lb, (0.03, ly1 - ly0, 0.085), (side * lx, (ly0 + ly1) * 0.5, lz), LADDER)
        n = int((ly1 - ly0) / 0.30)
        for k in range(n + 1):
            y = ly0 + 0.06 + k * (ly1 - ly0 - 0.12) / n
            add_box(lb, (2.0 * lx, 0.032, 0.032), (0.0, y, lz), CHROME)
        # A second fly section on top, offset back.
        for side in (1.0, -1.0):
            add_box(lb, (0.028, 2.40, 0.075), (side * (lx - 0.03), -1.65, lz + 0.085), LADDER)
        for k in range(8):
            add_box(lb, (2.0 * (lx - 0.03), 0.03, 0.03), (0.0, -2.75 + k * 0.32, lz + 0.085), CHROME)
        # Straps over the hoops.
        for f in (-1.80, -2.86):
            add_box(lb, (0.50, 0.04, 0.012), (0.0, f, lz + 0.135), TRIM)
        bmesh.ops.recalc_face_normals(lb, faces=lb.faces)
        parts.append(new_object("ladder", lb))
        log("WORK TRUCK: rack top %.2f, ladder z %.2f" % (top, lz))

    s["details"] = details
    s["height"] = 2.30
    return s


# --- the sports coupe -----------------------------------------------------------------------------

def coupe():
    """A 2-door sports coupe (4.62 m): the sedan's platform with short overhangs, the
    glasshouse dropped up to 9 cm into a fast roof, two long doors with a fixed quarter light
    behind them, a wide low mouth with corner intakes, aggressive slim lamps, a ducktail, a
    thin tail bar and quad exhaust tips. 2 cm wider in the hips."""
    s = rc.sedan()
    s["name"] = "coupe"
    fm = mc.overhangs(1.50, -1.33, 2.345, -2.36, 2.255, -2.23)
    mc.remap(s, fm)
    lower(s, ("top", "rail_z"), lambda f: ramp(f, 1.02, 0.45) * ramp(f, fm(-1.96), -1.25), 0.088)
    widen(s, 1.02)
    fa, ra = 1.50, -1.33
    s["d"] = {
        "windows": [
            ("windscreen", "screen", 0.14, 0.99, 0.058),
            ("front", "side", -0.640, 0.950),
            ("quarter", "side", lambda j: -1.42 + 0.28 * clamp01(0.0 if j is None else j - 5.0),
             -0.735),
            ("backlight", "screen", fm(-1.930), -0.860, 0.050),
        ],
        "headlamp": {"blade": (0.40, 0.845, 0.632, 0.612, 0.032, 0.050),
                     "drl": (0.41, 0.835, 0.650, 0.630, 0.006, 0.007),
                     "eyes": [0.62], "eye_z": 0.620, "eye_w": 0.030, "eye_h": 0.010},
        "grille": {"outline": [(-0.52, 0.480), (0.52, 0.480), (0.64, 0.268), (-0.64, 0.268)],
                   "round": 0.06, "cut_from": fm(2.30), "box": (-0.66, 0.66, 0.268, 0.480),
                   "y": (fm(2.40), fm(2.33)), "nv": 44, "nh": 7, "thick": 0.0042},
        "front_band": (-0.68, 0.68, 0.250, 0.272),
        "plate": (-0.25, 0.25, 0.500, 0.635),
        "handles": [(-0.50, 0.905)],
        "handle_mat": PAINT,
        "gaps_side": [
            [(1.00, 0.945), (0.995, 0.80), (0.985, 0.55), (0.98, 0.30)],
            [(-0.700, 0.995), (-0.705, 0.60), (-0.710, 0.30)],
            [(0.98, 0.30), (-0.710, 0.30)],
            [(fm(2.215), 0.665), (fm(2.13), 0.610), (fm(2.03), 0.575), (fa + 0.388 + 0.03, 0.56)],
            [(fm(-2.255), 0.905), (fm(-2.20), 0.78), (fm(-2.05), 0.66), (ra - 0.388 - 0.03, 0.60)],
        ],
        "gaps_fj": [[(1.07, 5.40), (fm(2.325), 5.40)], [(fm(2.325), 5.40), (fm(2.325), 7.0)],
                    [(fm(-1.985), 5.40), (fm(-2.335), 5.40)]],
        "gaps_rear": [[(0.715, 1.000), (0.705, 0.895), (0.0, 0.888), (-0.705, 0.895), (-0.715, 1.000)]],
        "fuel": (-1.52, 0.905),
        "fuel_left": True,
        "black_pillars": [(-0.735, -0.640)],
        "belt_trim": (-1.40, 0.94),
        "belt_mat": GLASS,
        "rocker": (1.70, 2.20, TRIM),
        "cowl": (0.990, 1.062),
        "spoiler": (fm(-2.33), fm(-2.24), 0.022),
        "tail": {
            "bar": (-0.62, 0.62, 0.958, 0.958, 0.009, 0.009),
            "bar_s": (-0.64, 0.64, 0.958, 0.958, 0.022, 0.022),
            "pieces": [
                ("glass", (0.52, 0.870, 0.952, 0.935, 0.050, 0.068, 2, 14)),
                ("red", (0.54, 0.860, 0.972, 0.960, 0.010, 0.010, 1, 14)),
                ("red", (0.835, 0.858, 0.935, 0.925, 0.050, 0.044, 2, 1)),
                ("red", (0.64, 0.74, 0.43, 0.448, 1, 4)),
            ],
        },
        "rear_band": (-0.66, 0.66, 0.295, 0.430),
        "rear_chrome": [(0.30, 0.38, 0.325, 0.372), (0.42, 0.50, 0.325, 0.372),
                        (-0.38, -0.30, 0.325, 0.372), (-0.50, -0.42, 0.325, 0.372)],
        "mirror": (0.86, 5.05, (0.995, 0.815, 0.975), (0.21, 0.080, 0.100)),
    }

    def extra(s, sec, surf, body, parts, bmt, bmp):
        badge(bmp, surf, "front", 0.0, 0.535, 0.075, 0.030)
        badge(bmt, surf, "rear", 0.0, 0.860, 0.070, 0.028)
        # A gloss black roof panel (the contrast roof of the class).
        fj_applied(bmt, surf, fm(-1.85), 0.10, lambda f: sec.j_along(f, 6.0, 0.06), 7.0, 44, 8,
                   0.006, GLASS, 1.0, thickness=0.004, centre=True)

    s["d"]["extra"] = extra
    s["details"] = mc.everyday_details
    return s


rc.SPECS["ev_hatch"] = ev_hatch
rc.SPECS["lux_sedan"] = lux_sedan
rc.SPECS["compact_suv"] = compact_suv
rc.SPECS["work_truck"] = work_truck
rc.SPECS["coupe"] = coupe

PREVIEW = {"ev_hatch": (0.55, 0.57, 0.58), "lux_sedan": (0.02, 0.025, 0.035),
           "compact_suv": (0.20, 0.26, 0.18), "work_truck": (0.80, 0.80, 0.80),
           "coupe": (0.45, 0.03, 0.02)}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = [a for a in argv if not a.startswith("--")] or ["ev_hatch"]
    do_render = "--render" in argv
    detail = "--nodetail" not in argv
    for name in names:
        spec = rc.SPECS[name]()
        ob = rc.build(spec, detail)
        if "post_scale" in spec:
            apply_post_scale(ob, spec)
        path = os.path.join(rc.OUT_DIR, "road_%s.glb" % name)
        far = rc.build_far(ob, spec)
        far.data.calc_loop_triangles()
        rc.report(ob, spec, far)
        print("   far twin: %d triangles" % len(far.data.loop_triangles))
        if "--noexport" not in argv:
            rc.export([ob, far], path)
            print("wrote", path)
        bpy.data.objects.remove(far, do_unlink=True)
        if do_render:
            vs = rc.default_views(spec)
            only = os.environ.get("VIEWS", "")
            if only:
                vs = [v for v in vs if v[0] in only.split(",")]
            wh = rc.far_wheels(spec, 24)
            rc.render_previews(join([ob, wh]), name, vs, paint=PREVIEW.get(name, rc.PREVIEW_PAINT))


if __name__ == "__main__":
    main()
