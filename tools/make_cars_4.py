#!/usr/bin/env python3
"""The fourth wave of everyday road car bodies (fleet wave 5, `car-variety-4`), so a downtown
street and the freeway stop repeating the same dozen shapes: a compact estate WAGON (a long flat
roof to an upright tailgate, tall tail lamps up the D-pillars), a 2-door MUSCLE coupe (an upright
wide grille with round lamps set in it, a bonnet scoop, a black bonnet panel, round quad tail
lamps), a big LUXURY SUV (the full-size SUV with a longer bonnet, slim lamps, a tall chrome
grille, chrome everywhere, a full-width tail bar), a small KEI-style city VAN (a one-box van 3.4 m
long and 1.9 m tall on 13-inch wheels, glazed all round, sliding doors both sides) and an older
1970s land-yacht SEDAN (5.5 m, square, quad round lamps, chrome bumpers, a vinyl roof). Built
with tools/make_road_cars.py's pipeline (its loft, booleans, raycast parts, slots, far twin) and
tools/make_more_cars.py's data-driven detail builder, `everyday_details()`:

    tools/road_cars_setup.sh                     # once: Blender 4.2 LTS into build/car_src/
    build/car_src/blender/blender-4.2.23-linux-x64/blender -b --factory-startup \\
        -P tools/make_cars_4.py -- wagon muscle lux_suv kei_van classic [--render]

Writes assets/models/road_<name>.glb, then run `godot --headless --path . --import` (CLAUDE.md,
measurement trap 1). The run prints each body's WHEEL_POSE row and `_dims()` numbers.

Every body is DERIVED from an older spec by station maps (the loft is fussy: a profile edit that
looks harmless can leave the body non-manifold and roll every later boolean back - the log
counts `rolled back`):

  * wagon    the hatchback stretched behind the B-pillar (rear axle 26 cm back, the rear
             overhang 26 cm longer), its roof held level to the tail and dropped into an upright
             tailgate.
  * muscle   tools/make_cars_3.py's coupe, 3 cm lower in the roof and 3 % wider, with a new face.
  * lux_suv  the full-size SUV with everything ahead of the cowl stretched 12 cm (the front axle
             with it).
  * kei_van  the high-roof panel van with its load box cut short (the rear axle and the tail
             pulled in), then the whole van scaled to 76 % (73 % across) after the build, so the
             arches stay round round the scaled wheel (make_cars_3's `post_scale`).
  * classic  the old beater's square notchback stretched 15 % every way along and 3 % across.

Original designs, invented badges, no manufacturer's shapes or names.
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
import make_cars_3 as c3  # noqa: E402

from make_road_cars import (  # noqa: E402
    PAINT, GLASS, TRIM, CHROME, TYRE, LIGHT_F, LIGHT_R, ramp, log, new_object, add_box,
    applied, fj_applied, rect_grid, blade_grid, mirror2, hits_2d, sweep, join, boolean, tidy,
    grid_solid, oriented_grid, extrude_cutter, rounded_outline, eggcrate, surface_path, fj_path,
    cut_grooves, wrap_band, circle_path, cut_windows, build_glass, flush_handle, mirror, cladding,
)

piecewise = c3.piecewise
map_profile = c3.map_profile
lower = c3.lower
widen = c3.widen
badge = c3.badge
clamp01 = c3.clamp01


def map_d(d, h):
    """A spec's detail table moved by the station map h: every key whose numbers are stations
    (f along the car) gets them mapped; heights, j's and x's stay."""
    d = copy.copy(d)

    def mf(v):
        if callable(v):
            return lambda j, v=v: h(v(j))
        return h(v)

    wins = []
    for w in d.get("windows", []):
        w = list(w)
        w[2] = mf(w[2])
        w[3] = mf(w[3])
        wins.append(tuple(w))
    d["windows"] = wins
    d["gaps_side"] = [[(h(f), z) for f, z in line] for line in d.get("gaps_side", [])]
    d["gaps_fj"] = [[(h(f), j) for f, j in line] for line in d.get("gaps_fj", [])]
    d["handles"] = [(h(f), z) for f, z in d.get("handles", [])]
    for k in ("black_pillars", "black_dividers"):
        if k in d:
            d[k] = [(h(a), h(b)) for a, b in d[k]]
    for k in ("belt_trim", "cowl"):
        if k in d:
            d[k] = (h(d[k][0]), h(d[k][1]))
    if "spoiler" in d:
        d["spoiler"] = (h(d["spoiler"][0]), h(d["spoiler"][1]), d["spoiler"][2])
    for k in ("fuel", "sill_gap"):
        if k in d:
            d[k] = (h(d[k][0]), d[k][1])
    if "rear_door" in d:
        rd = list(d["rear_door"])
        rd[0] = h(rd[0])
        d["rear_door"] = tuple(rd)
    if "mirror" in d:
        mf_, mj, head, size = d["mirror"]
        d["mirror"] = (h(mf_), mj, (head[0], h(head[1]), head[2]), size)
    if "roof_rail" in d:
        f0, f1, j, lift = d["roof_rail"]
        d["roof_rail"] = (h(f0), h(f1), j, lift)
    if "door_tracks" in d:
        d["door_tracks"] = [((h(a[0]), a[1]), (h(b[0]), b[1])) for a, b in d["door_tracks"]]
    return d


def replace_tail(s, key, f_from, pts):
    """Drops the profile `key`'s keys behind f_from and puts `pts` there (the wagon's roof)."""
    keep = [(f, z) for f, z in s["profile"][key] if f > f_from]
    s["profile"][key] = keep + sorted(pts, key=lambda p: -p[0])


# --- the compact wagon -----------------------------------------------------------------------------

def wagon():
    """A compact estate (4.70 m): the hatchback's front and doors on a wheelbase 26 cm longer, a
    long flat roof held level right back to an upright tailgate, a three-light glasshouse with a
    long quarter window, roof rails, tall tail lamps up the D-pillars and a chrome belt."""
    s = mc.hatchback()
    s["name"] = "wagon"
    h = piecewise([(-0.40, -0.40), (-1.34, -1.58), (-2.095, -2.64)])
    d0 = s["d"]
    map_profile(s, h)
    ra = s["rear_axle"]
    # The roof: level to the tailgate, which drops nearly upright into the bumper.
    replace_tail(s, "top", -0.95, [
        (-1.00, 1.398), (-1.40, 1.392), (-1.80, 1.384), (-2.10, 1.374), (-2.30, 1.362),
        (-2.42, 1.346), (-2.48, 1.326), (-2.52, 1.296), (-2.55, 1.240), (-2.575, 1.160),
        (-2.595, 1.080), (-2.615, 1.020), (-2.64, 0.975)])
    replace_tail(s, "rail_z", -0.95, [
        (-1.00, 1.318), (-1.40, 1.314), (-1.80, 1.308), (-2.10, 1.300), (-2.30, 1.290),
        (-2.42, 1.274), (-2.50, 1.240), (-2.55, 1.160), (-2.60, 1.060), (-2.64, 0.990)])
    replace_tail(s, "belt_z", -0.95, [
        (-1.00, 0.985), (-1.50, 1.000), (-2.00, 1.012), (-2.40, 1.018), (-2.55, 1.008),
        (-2.64, 0.985)])
    s["extra_stations"] = [0.86, -2.42, -2.52]
    d = map_d(d0, h)
    d["windows"] = [
        ("windscreen", "screen", 0.10, 0.84, 0.058),
        ("front", "side", -0.295, 0.815),
        ("rear", "side", h(-1.110), -0.395),
        ("quarter", "side", lambda j: -2.34 + 0.06 * clamp01(0.0 if j is None else j - 5.0),
         h(-1.215)),
        ("backlight", "screen", -2.585, -2.470, 0.050),
    ]
    d["black_pillars"] = [(-0.395, -0.295), (h(-1.215), h(-1.110))]
    d["belt_trim"] = (-2.34, 0.83)
    d["belt_mat"] = CHROME
    d["spoiler"] = (-2.50, -2.43, 0.010)
    d["roof_rail"] = (-0.15, -2.25, 6.75, 0.045)
    d["rail_mat"] = TRIM
    d["fuel"] = (-2.02, 0.890)
    gs = d["gaps_side"]
    d["gaps_side"] = gs[:4] + [[(-2.47, 0.905), (-2.43, 0.780), (-2.30, 0.640),
                                (ra - 0.362 - 0.03, 0.610)]]
    d["gaps_rear"] = [[(0.66, 1.07), (0.68, 0.90), (0.68, 0.64), (0.0, 0.635), (-0.68, 0.64),
                       (-0.68, 0.90), (-0.66, 1.07)]]
    # Tall lamps up the D-pillars, a slim bar across the gate between them.
    d["tail"] = {
        "pieces": [
            ("glass", (0.600, 0.735, 0.800, 1.250, 6, 2)),
            ("red", (0.612, 0.725, 0.940, 1.235, 4, 2)),
            ("red", (0.612, 0.725, 0.815, 0.860, 1, 2)),
            ("clear", (0.612, 0.725, 0.872, 0.928, 1, 2)),
            ("red", (0.62, 0.74, 0.43, 0.448, 1, 4)),
        ],
        "hmsl": (-0.14, 0.14, 1.305, 1.322),
    }
    d["rear_chrome"] = [(-0.46, 0.46, 0.965, 0.978)]
    d["rear_band"] = (-0.74, 0.74, 0.34, 0.47)
    d.pop("lamp_band", None)
    d["headlamp"] = {"blade": (0.36, 0.800, 0.640, 0.660, 0.058, 0.074),
                     "drl": (0.37, 0.790, 0.668, 0.690, 0.008, 0.010),
                     "eyes": [0.50, 0.60, 0.70], "eye_z": 0.648, "eye_w": 0.026, "eye_h": 0.010}
    d["grille"] = {"outline": [(-0.34, 0.610), (0.34, 0.610), (0.38, 0.520), (-0.38, 0.520)],
                   "round": 0.025, "cut_from": 2.02, "box": (-0.40, 0.40, 0.520, 0.610),
                   "y": (2.10, 2.05), "bars": 3, "bar_t": 0.010,
                   "surround": (-0.395, 0.395, 0.512, 0.618, 0.012)}

    def extra(s, sec, surf, body, parts, bmt, bmp):
        badge(bmp, surf, "front", 0.0, 0.570, 0.070, 0.028)
        badge(bmt, surf, "rear", 0.0, 1.000, 0.065, 0.026)

    d["extra"] = extra
    s["d"] = d
    s["details"] = mc.everyday_details
    return s


# --- the muscle coupe ------------------------------------------------------------------------------

def muscle():
    """A 2-door muscle coupe (4.73 m): the sports coupe's platform 3 cm lower in the roof and
    3 % wider, an upright full-width grille with round lamps set in its ends, a scoop on a black
    bonnet panel, vents behind the front wheels, round quad tail lamps in a black panel, quad
    tips and a ducktail."""
    s = c3.coupe()
    s["name"] = "muscle"
    lower(s, ("top", "rail_z"), lambda f: ramp(f, 1.02, 0.45) * ramp(f, -2.20, -1.25), 0.030)
    widen(s, 1.03)
    d = s["d"]
    fa = s["front_axle"]
    # An upright mouth the whole width of the face: round lamps in its ends, a split bar.
    d["grille"] = {"outline": [(-0.70, 0.640), (0.70, 0.640), (0.70, 0.470), (-0.70, 0.470)],
                   "round": 0.03, "cut_from": 2.24, "box": (-0.72, 0.72, 0.470, 0.640),
                   "y": (2.35, 2.28), "nv": 36, "nh": 5, "thick": 0.0045}
    d["headlamp"] = {"round": [(0.585, 0.056)], "z": 0.556}
    d["low"] = {"outline": [(-0.50, 0.400), (0.50, 0.400), (0.56, 0.300), (-0.56, 0.300)],
                "cut_from": 2.22, "box": (-0.58, 0.58, 0.300, 0.400), "y": (2.34, 2.27),
                "nv": 24, "nh": 2}
    d["front_band"] = (-0.70, 0.70, 0.258, 0.290)
    d["tail"] = {
        "pieces": [
            ("glass", (0.20, 0.80, 0.760, 0.900, 2, 16)),
            ("red", (0.62, 0.78, 0.785, 0.875, 2, 4)),
            ("red", (0.42, 0.58, 0.785, 0.875, 2, 4)),
            ("clear", (0.25, 0.38, 0.800, 0.860, 1, 3)),
            ("red", (0.64, 0.74, 0.43, 0.448, 1, 4)),
        ],
    }
    d["rear_band"] = (-0.68, 0.68, 0.300, 0.440)

    def extra(s, sec, surf, body, parts, bmt, bmp):
        # The black bonnet panel and the scoop on it, the split bar across the mouth.
        fj_applied(bmt, surf, 1.25, 2.05, lambda f: sec.j_along(f, 6.0, 0.25), 7.0, 18, 6,
                   0.003, GLASS, 1.0, thickness=0.004, centre=True)
        top, _n = surf.top_hit(0.0, 1.55)
        if top is not None:
            sb = bmesh.new()
            # A low scoop: a black shell 4 cm proud, its open mouth facing forward.
            add_box(sb, (0.40, 0.46, 0.022), (0.0, 1.56, top.z + 0.020), TRIM)
            add_box(sb, (0.34, 0.40, 0.020), (0.0, 1.53, top.z + 0.036), TRIM)
            add_box(sb, (0.30, 0.012, 0.022), (0.0, 1.737, top.z + 0.030), GLASS)
            bmesh.ops.recalc_face_normals(sb, faces=sb.faces)
            parts.append(new_object("scoop", sb))
        applied(bmp, surf, "front", rect_grid(-0.70, 0.70, 0.548, 0.562, 1, 20), 0.010, CHROME,
                thickness=0.010)
        badge(bmp, surf, "front", 0.0, 0.590, 0.085, 0.034)
        badge(bmt, surf, "rear", 0.0, 0.830, 0.075, 0.030)
        # Vents behind each front wheel.
        for side in (1.0, -1.0):
            for k in range(3):
                z0 = 0.560 + k * 0.032
                g = rect_grid(fa - 0.66 + k * 0.025, fa - 0.47, z0, z0 + 0.016, 1, 4)
                applied(bmt, surf, "side", g, 0.004, TRIM, side, thickness=0.006)

    d["extra"] = extra
    return s


# --- the luxury SUV --------------------------------------------------------------------------------

def lux_suv():
    """A big luxury SUV (5.6 m): the full-size SUV with its bonnet 12 cm longer (the front axle
    with it), slim lamps over a tall chrome-barred grille in a heavy surround, chrome belt,
    rocker, rails and window line, a full-width tail bar and quad tips."""
    s = mc.suv()
    s["name"] = "lux_suv"
    h = piecewise([(1.06, 1.06), (1.70, 1.82), (2.665, 2.785)])
    d0 = s["d"]
    map_profile(s, h)
    d = map_d(d0, h)
    fa, ra = s["front_axle"], s["rear_axle"]
    n = s["nose"]
    d["headlamp"] = {"blade": (0.56, 0.930, 1.110, 1.120, 0.040, 0.050),
                     "drl": (0.57, 0.920, 1.080, 1.086, 0.007, 0.008),
                     "eyes": [0.68, 0.76, 0.84], "eye_z": 1.115, "eye_w": 0.028, "eye_h": 0.012}
    d["grille"] = {"outline": [(-0.55, 1.165), (0.55, 1.165), (0.55, 0.660), (-0.55, 0.660)],
                   "round": 0.05, "cut_from": n - 0.085, "box": (-0.57, 0.57, 0.660, 1.165),
                   "y": (n, n - 0.065), "bars": 9, "bar_t": 0.016,
                   "surround": (-0.585, 0.585, 0.640, 1.185, 0.040)}
    d["low"] = {"outline": [(-0.62, 0.590), (0.62, 0.590), (0.58, 0.520), (-0.58, 0.520)],
                "cut_from": n - 0.105, "box": (-0.64, 0.64, 0.520, 0.590), "y": (n - 0.025, n - 0.085),
                "nv": 30, "nh": 1}
    d["fogs"] = [(0.74, 0.88, 0.540, 0.565)]
    d["front_bumper"] = (0.470, 0.640, 0.040, TRIM)
    d["skid"] = (-0.62, 0.62, 0.600, 0.618)
    d["skid_proud"] = 0.045
    d["belt_mat"] = CHROME
    d["rail_mat"] = CHROME
    d["rocker"] = (1.6, 2.3, CHROME)
    d["handle_mat"] = CHROME
    d["cladding"] = None
    d["tail"] = {
        "bar": (-0.70, 0.70, 1.300, 1.300, 0.014, 0.014),
        "bar_s": (-0.72, 0.72, 1.300, 1.300, 0.034, 0.034),
        "pieces": [
            ("glass", (0.74, 0.910, 1.100, 1.460, 4, 2)),
            ("red", (0.755, 0.900, 1.240, 1.445, 3, 2)),
            ("red", (0.755, 0.900, 1.115, 1.165, 1, 2)),
            ("clear", (0.755, 0.900, 1.175, 1.228, 1, 2)),
        ],
        "hmsl": (-0.18, 0.18, 1.845, 1.870),
    }
    d["rear_chrome"] = [(0.40, 0.52, 0.520, 0.560), (0.56, 0.68, 0.520, 0.560),
                        (-0.52, -0.40, 0.520, 0.560), (-0.68, -0.56, 0.520, 0.560)]
    d["rear_skid"] = (-0.50, 0.50, 0.600, 0.618)

    def extra(s, sec, surf, body, parts, bmt, bmp):
        badge(bmp, surf, "front", 0.0, 1.215, 0.095, 0.036)
        badge(bmt, surf, "rear", 0.0, 1.380, 0.090, 0.034)
        # A chrome window line: the glasshouse's foot and head, door to tailgate.
        for side in (1.0, -1.0):
            fj_applied(bmt, surf, -2.45, 0.95, lambda f: sec.j_along(f, 6.0, 0.010),
                       lambda f: sec.j_along(f, 6.0, 0.024), 1, 44, 0.0030, CHROME, side,
                       thickness=0.005)
            # A chrome side vent on each front wing.
            g = rect_grid(fa - 0.60, fa - 0.42, 1.020, 1.050, 1, 3)
            applied(bmt, surf, "side", g, 0.005, CHROME, side, thickness=0.008)
        # Running boards along the sills, between the arches.
        for side in (1.0, -1.0):
            rb = bmesh.new()
            y0, y1 = ra + 0.52, fa - 0.52
            add_box(rb, (0.16, y1 - y0, 0.035), (side * 1.000, (y0 + y1) * 0.5, 0.395), TRIM)
            add_box(rb, (0.012, y1 - y0, 0.012), (side * 1.078, (y0 + y1) * 0.5, 0.412), CHROME)
            bmesh.ops.recalc_face_normals(rb, faces=rb.faces)
            parts.append(new_object("running_board", rb))

    d["extra"] = extra
    s["d"] = d
    s["details"] = mc.everyday_details
    s["length"] = s["nose"] - s["tail"]
    return s


# --- the kei-style city van ------------------------------------------------------------------------

KEI_K = 0.76     # along and up (and the arches, so they stay round round the wheel)
KEI_KX = 0.73    # across


def kei_van():
    """A small one-box city van (3.45 m, 1.94 m tall once scaled): the panel van's short nose,
    steep screen and box, its load box cut short (the rear axle pulled in under it), glazed all
    round with a sliding door on each side, a top-hinged tailgate with a big glass, small square
    lamps, black bumpers, 13-inch wheels."""
    s = rc.van()
    s["name"] = "kei_van"
    g = piecewise([(1.26, 1.26), (-1.56, -1.05), (-2.73, -1.55)])
    map_profile(s, g)
    # The tailgate rounds into the roof a little more than the barn doors did.
    s["profile"]["top"] = [(f, z if f > -1.47 else z - 0.03 * ramp(f, -1.47, -1.55))
                           for f, z in s["profile"]["top"]]
    s["details"] = kei_details
    s["height"] = 2.55
    s["post_scale"] = (KEI_KX, KEI_K)
    s["road"] = -0.149
    return s


def kei_details(s, sec, surf, body, parts):
    """make_road_cars.van_details for the short body: the same cab, the sliding door on BOTH
    sides, side windows down the box, a top-hinged tailgate with a big glass."""
    fa, ra, R = s["front_axle"], s["rear_axle"], s["arch_r"]
    belt_gap = 0.024

    def side_j(f):
        lo = sec.j_along(f, 5.0, belt_gap)
        hi = min(sec.j_at_z(f, 2.05), sec.j_along(f, 6.0, 0.022, -1.0))
        if hi < lo:
            lo = hi = (lo + hi) * 0.5
        return lo, hi

    def screen_j(pillar):
        return lambda f: (sec.j_along(f, 6.0, pillar), 7.0)

    wins = [
        {"name": "windscreen", "centre": True, "rows": 16, "cols": 12,
         "f": lambda j: (1.765, 2.262), "j": screen_j(0.060), "cut_shrink_j": 0.02},
        {"name": "cab", "centre": False, "rows": 8, "cols": 12,
         "f": lambda j: (1.300, 2.240), "j": side_j, "cut_shrink_j": 0.035},
        {"name": "slider", "centre": False, "rows": 8, "cols": 12,
         "f": lambda j: (0.12, 1.12), "j": side_j, "cut_shrink_j": 0.035},
        {"name": "box", "centre": False, "rows": 8, "cols": 10,
         "f": lambda j: (-1.42, -0.06), "j": side_j, "cut_shrink_j": 0.035},
    ]
    cut_windows(body, surf, wins)

    bmc = bmesh.new()
    bmp = bmesh.new()
    # Small square headlamps under the bonnet's edge, an amber corner each.
    for side in (1.0, -1.0):
        lamp = rect_grid(0.60, 0.88, 0.840, 0.940, 2, 6)
        g = lamp if side > 0 else mirror2(lamp)
        res = hits_2d(surf, "front", g, 1.0)
        if res:
            pts, nrm = res
            grid_solid(bmc, [p + n * 0.03 for p, n in zip(pts, nrm)],
                       [p - n * 0.020 for p, n in zip(pts, nrm)], len(g), len(g[0]), TRIM)
            oriented_grid(bmp, [p - n * 0.017 for p, n in zip(pts, nrm)], nrm, len(g), len(g[0]),
                          GLASS)
        lens = rect_grid(0.62, 0.79, 0.852, 0.928, 1, 4)
        applied(bmp, surf, "front", lens if side > 0 else mirror2(lens), -0.012, LIGHT_F)
        am = rect_grid(0.80, 0.865, 0.852, 0.928, 1, 2)
        applied(bmp, surf, "front", am if side > 0 else mirror2(am), -0.012, LIGHT_R)
    # A slim grille between them, a bar of the body colour over it.
    mouth = rounded_outline([(-0.50, 0.920), (0.50, 0.920), (0.50, 0.840), (-0.50, 0.840)], 0.02)
    boolean(body, extrude_cutter(mouth, "y", 2.84, 3.4))
    eggcrate(bmp, -0.52, 0.52, 0.840, 0.920, 2.955, 2.895, 3, 2, thick=0.010)
    # Black bumper right across with a lower intake and the plate.
    wrap_band(bmp, surf, 1.0, 0.365, 0.640, 0.050, TRIM, reach=0.30, corner_r=0.20,
              thickness=0.06)
    for side in (1.0, -1.0):
        fog = rect_grid(0.74, 0.86, 0.450, 0.490, 1, 3)
        applied(bmp, surf, "front", fog if side > 0 else mirror2(fog), 0.052, LIGHT_F)
    plate_f = rect_grid(-0.24, 0.24, 0.470, 0.600, 1, 6)
    applied(bmp, surf, "front", plate_f, 0.055, TRIM, thickness=0.01)
    # Rear: black bumper, the plate recess on the gate, its handle.
    wrap_band(bmp, surf, -1.0, 0.380, 0.600, 0.050, TRIM, reach=0.24, corner_r=0.12,
              thickness=0.065)
    plate = rect_grid(-0.18, 0.18, 0.800, 0.950, 2, 6)
    res = hits_2d(surf, "rear", plate, 1.0)
    if res:
        pts, nrm = res
        grid_solid(bmc, [p + n * 0.02 for p, n in zip(pts, nrm)],
                   [p - n * 0.010 for p, n in zip(pts, nrm)], 3, 7, TRIM)
    applied(bmp, surf, "rear", rect_grid(-0.10, 0.10, 1.020, 1.055, 1, 3), 0.006, TRIM,
            thickness=0.012)
    for side in (1.0, -1.0):
        flush_handle(bmc, bmp, surf, 1.44, 1.10, side, length=0.16, height=0.040, mat=TRIM)
        flush_handle(bmc, bmp, surf, 0.18, 1.08, side, length=0.16, height=0.040, mat=TRIM)
    tidy(bmc)
    boolean(body, new_object("cut_pockets", bmc))

    paths = []
    for side in (1.0, -1.0):
        arc = circle_path(fa, s["axle_z"], R + 0.050, 84.0, 172.0, 12)
        front = [(2.225, 1.205), (2.17, 0.95)] + arc + [(1.27, 0.42)]
        paths.append(surface_path(surf, "side", front, side))
        paths.append(surface_path(surf, "side", [(1.27, 0.42), (1.27, 2.065)], side))
        paths.append(surface_path(surf, "side", [(1.27, 2.065), (1.705, 2.065)], side))
        paths.append(fj_path(surf, [(2.30, 5.40), (2.935, 5.40)], side))
        paths.append(fj_path(surf, [(2.935, 5.40), (2.935, 7.0)], side))
        # The sliding door, both sides.
        paths.append(surface_path(surf, "side", [(1.18, 0.42), (1.18, 2.10), (0.05, 2.10),
                                                  (0.05, 0.42), (1.18, 0.42)], side))
    # The tailgate: its outline, hinged at the roof.
    paths.append(surface_path(surf, "rear", [(0.775, 0.605), (0.775, 2.300), (-0.775, 2.300),
                                              (-0.775, 0.605), (0.775, 0.605)], 1.0))
    flap = circle_path(-0.70, 1.02, 0.070, 5.0, 352.0, 24)
    paths.append(surface_path(surf, "side", flap, -1.0, step=0.015))
    cut_grooves(body, paths)

    parts.append(build_glass(surf, wins, 0.008))
    bmt = bmesh.new()
    # The tailgate glass: a big dark pane laid on the gate (the rear view has no loft window).
    applied(bmt, surf, "rear", rect_grid(-0.66, 0.66, 1.380, 2.180, 4, 10), 0.004, GLASS,
            thickness=0.008)
    applied(bmt, surf, "rear", rect_grid(-0.69, 0.69, 1.355, 2.205, 1, 10), 0.002, TRIM,
            thickness=0.006)
    for side in (1.0, -1.0):
        # Rubbing strip along the lower flanks.
        for f0, f1 in ((fa - R - 0.05, ra + R + 0.05), (ra - R - 0.05, -1.50)):
            strip = surface_path(surf, "side", [(f0, 0.690), (f1, 0.690)], side, step=0.10)
            if len(strip) > 2:
                prof = [(-0.055, -0.004), (-0.045, 0.010), (0.045, 0.010), (0.055, -0.004)]
                sweep(bmt, [p for p, _n in strip], prof, TRIM, normals=[n for _p, n in strip])
        # The sliding door's track along the box, under the rear side glass.
        track = surface_path(surf, "side", [(0.03, 1.300), (-0.95, 1.300)], side, step=0.08)
        if len(track) > 2:
            prof = [(-0.010, -0.004), (-0.010, 0.012), (0.010, 0.012), (0.010, -0.004)]
            sweep(bmt, [p for p, _n in track], prof, TRIM, normals=[n for _p, n in track])
        # The pillars between the side windows in black.
        for f0, f1 in ((1.14, 1.30), (-0.06, 0.12)):
            fj_applied(bmt, surf, f0, f1, lambda f: sec.j_along(f, 5.0, 0.018),
                       lambda f: min(sec.j_along(f, 6.0, 0.016, -1.0), sec.j_at_z(f, 2.06)), 6, 3,
                       0.002, GLASS, side, thickness=0.006)
        # Tail lamps: tall slim pillars in the rear corners.
        tl = rect_grid(0.800, 0.895, 0.660, 1.300, 5, 3)
        applied(bmt, surf, "rear", tl if side > 0 else mirror2(tl), 0.004, LIGHT_R, thickness=0.008)
        rev = rect_grid(0.815, 0.880, 0.900, 0.990, 1, 2)
        applied(bmt, surf, "rear", rev if side > 0 else mirror2(rev), 0.0055, LIGHT_F)
    applied(bmt, surf, "rear", rect_grid(-0.16, 0.16, 2.420, 2.460, 1, 6), 0.004, LIGHT_R,
            thickness=0.008)
    fj_applied(bmt, surf, 2.245, 2.325, lambda f: sec.j_along(f, 5.0, 0.03), 7.0, 12, 3, 0.003,
               TRIM, 1.0, thickness=0.006, centre=True)
    # Roof rails (a city van carries a ladder or crates up there).
    for side in (1.0, -1.0):
        rail = fj_path(surf, [(1.05, 6.70), (-1.35, 6.70)], side, step=0.06)
        if len(rail) > 3:
            pts = [p + nn * 0.05 for p, nn in rail]
            prof = [(-0.016, -0.012), (0.016, -0.012), (0.014, 0.014), (-0.014, 0.014)]
            sweep(bmt, pts, prof, TRIM, normals=[nn for _p, nn in rail])
            for k in (1, len(rail) // 2, len(rail) - 2):
                p, nn = rail[k]
                add_box(bmt, (0.04, 0.10, 0.06), p + nn * 0.025, TRIM)
    cladding(bmt, surf, s, width=0.080, height=0.018)
    badge(bmp, surf, "front", 0.0, 0.990, 0.080, 0.032)
    bmesh.ops.remove_doubles(bmt, verts=bmt.verts, dist=1e-6)
    parts.append(new_object("trims", bmt))
    bmesh.ops.remove_doubles(bmp, verts=bmp.verts, dist=1e-6)
    parts.append(new_object("inserts", bmp))
    for side in (1.0, -1.0):
        mirror(parts, surf, s, side, 2.20, 5.10, (1.19, 2.21, 1.56), (0.20, 0.10, 0.32),
               head_mat=TRIM)


# --- the 1970s sedan -------------------------------------------------------------------------------

def classic():
    """A 1970s full-size sedan (5.5 m): the beater's square notchback stretched every way along
    and widened, quad round headlamps in a wide egg-crate grille in a chrome frame, a stand-up
    bonnet ornament, chrome bumpers, a chrome belt and rocker, a black vinyl roof, wide tail
    lamps right across the back and narrow tall-walled tyres."""
    s = mc.beater()
    s["name"] = "classic"
    h = piecewise([(-2.30, -2.75), (-1.17, -1.40), (1.45, 1.55), (2.30, 2.75)])
    d0 = s["d"]
    map_profile(s, h)
    widen(s, 1.03)
    s["profile"]["rail_w"] = [(f, x * 1.03) for f, x in s["profile"]["rail_w"]]
    lower(s, ("top", "rail_z"), lambda f: ramp(f, 0.90, 0.50) * ramp(f, -1.45, -1.05), 0.025)
    d = map_d(d0, h)
    d.pop("dents", None)
    d.pop("extra", None)
    d["headlamp"] = {"round": [(0.700, 0.072), (0.535, 0.072)], "z": 0.600}
    d["grille"] = {"outline": [(-0.44, 0.665), (0.44, 0.665), (0.44, 0.540), (-0.44, 0.540)],
                   "round": 0.012, "cut_from": s["nose"] - 0.075, "box": (-0.46, 0.46, 0.540, 0.665),
                   "y": (s["nose"], s["nose"] - 0.055), "nv": 16, "nh": 4, "thick": 0.008,
                   "surround": (-0.80, 0.80, 0.520, 0.685, 0.016)}
    d["front_bumper"] = (0.355, 0.470, 0.034, CHROME)
    d["skid"] = (-0.80, 0.80, 0.405, 0.418)
    d["skid_proud"] = 0.036
    d["rear_bumper"] = (0.365, 0.480, 0.034, CHROME)
    d["rear_chrome"] = [(-0.80, 0.80, 0.700, 0.712), (-0.80, 0.80, 0.858, 0.870)]
    d["rocker"] = (1.6, 2.2, CHROME)
    d["handle_mat"] = CHROME
    d["mirror_mat"] = CHROME
    d["lips"] = True
    # Wide tail lamps right across, a chrome bar round them, the plate between.
    d["tail"] = {
        "pieces": [
            ("glass", (0.28, 0.83, 0.715, 0.855, 2, 10)),
            ("red", (0.30, 0.82, 0.725, 0.845, 2, 10)),
            ("clear", (0.32, 0.42, 0.740, 0.830, 1, 2)),
        ],
    }
    d["plate"] = (-0.22, 0.22, 0.540, 0.660)

    def extra(s, sec, surf, body, parts, bmt, bmp):
        # The vinyl roof: a black satin skin from the screen's head to the backlight's.
        fj_applied(bmt, surf, h(-1.08), 0.70, lambda f: sec.j_along(f, 6.0, 0.03), 7.0, 30, 8,
                   0.004, TRIM, 1.0, thickness=0.004, centre=True)
        # A stand-up ornament on the bonnet's front edge, a crest on the boot.
        top, _n = surf.top_hit(0.0, s["nose"] - 0.12)
        if top is not None:
            ob = bmesh.new()
            add_box(ob, (0.020, 0.050, 0.050), (0.0, s["nose"] - 0.12, top.z + 0.024), CHROME)
            add_box(ob, (0.040, 0.030, 0.012), (0.0, s["nose"] - 0.12, top.z + 0.004), CHROME)
            bmesh.ops.recalc_face_normals(ob, faces=ob.faces)
            parts.append(new_object("ornament", ob))
        badge(bmt, surf, "rear", 0.0, 0.900, 0.080, 0.030)
        # Chrome wheel-arch mouldings and a full-length side spear.
        for side in (1.0, -1.0):
            spear = surface_path(surf, "side", [(s["nose"] - 0.30, 0.640), (s["tail"] + 0.30, 0.660)],
                                 side, step=0.08)
            if len(spear) > 2:
                prof = [(-0.012, -0.003), (-0.009, 0.007), (0.009, 0.007), (0.012, -0.003)]
                sweep(bmt, [p for p, _n in spear], prof, CHROME, normals=[n for _p, n in spear])

    d["extra"] = extra
    s["d"] = d
    s["details"] = mc.everyday_details
    return s


rc.SPECS["wagon"] = wagon
rc.SPECS["muscle"] = muscle
rc.SPECS["lux_suv"] = lux_suv
rc.SPECS["kei_van"] = kei_van
rc.SPECS["classic"] = classic

PREVIEW = {"wagon": (0.10, 0.18, 0.30), "muscle": (0.55, 0.10, 0.02),
           "lux_suv": (0.02, 0.02, 0.025), "kei_van": (0.85, 0.85, 0.84),
           "classic": (0.45, 0.30, 0.10)}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = [a for a in argv if not a.startswith("--")] or ["wagon"]
    do_render = "--render" in argv
    detail = "--nodetail" not in argv
    for name in names:
        spec = rc.SPECS[name]()
        ob = rc.build(spec, detail)
        if "post_scale" in spec:
            c3.apply_post_scale(ob, spec)
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
