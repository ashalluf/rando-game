#!/usr/bin/env python3
"""More everyday road car bodies, so the street stops repeating: a 5-door compact hatchback, a
full-size three-row SUV, a minivan, a taxi (the sedan with its roof sign) and an older beater (a
1990s-shape notchback). Built with tools/make_road_cars.py's pipeline - its profile-curve loft,
booleans, raycast parts, the seven material slots and the far twin (read that file's docstring
first):

    tools/road_cars_setup.sh                     # once: Blender 4.2 LTS into build/car_src/
    build/car_src/blender/blender-4.2.23-linux-x64/blender -b --factory-startup \\
        -P tools/make_more_cars.py -- hatchback suv minivan taxi beater [--render] [--nodetail]

Writes assets/models/road_<name>.glb, then run `godot --headless --path . --import` (CLAUDE.md,
measurement trap 1). `--render` writes Cycles previews to $RENDER_DIR.

The same conventions as the cars: X lateral, Y along the car with the NOSE AT +Y, Z up, ground at
Z = 0; slots bound by name in Vehicle._add_body_model(); no wheels in the full model; a
`<name>_far` twin. What is new:

  * The details of the four lofted bodies are DATA (`spec["d"]`) for one shared builder,
    `everyday_details()`: the lamps, the grille mouth and its egg-crate or chrome bars, the
    intakes, the door and hatch gaps, the pillars, belt trim, rails, tail lamps, bumpers. Each
    body is its spec; nothing per body is code but a callback or two.
  * The taxi is the sedan's body with an eighth slot, `taxi_sign`: the lit box on a roof bar,
    drawn by shaders/taxi_sign.gdshader (lit by lamp_factor, the company's name on both faces).
  * The beater carries its wear in geometry where geometry is the truth - a dent pushed into the
    rear door (`dents`), a cracked and patched tail lamp (one lamp in pieces with a dark crack
    and a strip of tape) - and the paint-side wear (a door from another car, a primer patch, the
    clear coat gone chalky on the roof and bonnet) in car_paint.gdshaderinc's `wear` uniforms,
    which Vehicle sets from the rects this run prints (`BEATER_*` in vehicle.gd).

Original designs, generic classes, no manufacturer's shapes, names or badges.
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
    PAINT, GLASS, TRIM, CHROME, TYRE, LIGHT_F, LIGHT_R, ramp, log, new_object, boolean,
    add_box, tidy, grid_solid, oriented_grid, applied, fj_applied, hits_2d, rect_grid, mirror2,
    blade_grid, extrude_cutter, rounded_outline, eggcrate, surface_path, fj_path, cut_grooves,
    sweep, wrap_band, circle_path, cut_windows, build_glass, flush_handle, arch_lips, mirror,
    cladding, apply_modifiers, subsurf, join,
)

rc.SLOTS.append(("taxi_sign", (0.85, 0.80, 0.62), 0.0, 0.35, 0.0))
TAXI_SIGN = len(rc.SLOTS) - 1

RINGS = [0.0, 1.0, 1.6, 2.0, 2.4, 2.85, 3.35, 3.8, 3.92, 4.0, 4.08, 4.5, 5.0, 5.5, 6.1, 6.6, 7.0]
END_STEPS = [0.0, 0.012, 0.03, 0.055, 0.09, 0.135, 0.19, 0.26, 0.34]


def side_j_fn(sec, belt_gap=0.022, top_gap=0.020, z_cap=None):
    def side_j(f):
        lo = sec.j_along(f, 5.0, belt_gap)
        hi = sec.j_along(f, 6.0, top_gap, -1.0)
        if z_cap is not None:
            hi = min(hi, sec.j_at_z(f, z_cap))
        if hi < lo:
            lo = hi = (lo + hi) * 0.5
        return lo, hi
    return side_j


def screen_j_fn(sec, pillar):
    return lambda f: (sec.j_along(f, 6.0, pillar), 7.0)


def windows_from(s, sec):
    """The spec's window table: ("name", kind, f_lo, f_hi[, extra]) with kind "screen" (the
    centre glass: windscreen, backlight) or "side"; f_lo may be a callable of j for a slanted
    pillar."""
    side_j = side_j_fn(sec, s["d"].get("belt_gap", 0.022), s["d"].get("top_gap", 0.020))
    out = []
    for w in s["d"]["windows"]:
        name, kind, f0, f1 = w[:4]
        lo = f0 if callable(f0) else (lambda j, v=f0: v)
        hi = f1 if callable(f1) else (lambda j, v=f1: v)
        if kind == "screen":
            out.append({"name": name, "centre": True, "rows": 16, "cols": 12,
                        "f": (lambda j, lo=lo, hi=hi: (lo(j), hi(j))),
                        "j": screen_j_fn(sec, w[4] if len(w) > 4 else 0.058), "cut_shrink_j": 0.02})
        else:
            out.append({"name": name, "centre": False, "rows": 8, "cols": 14,
                        "f": (lambda j, lo=lo, hi=hi: (lo(j), hi(j))), "j": side_j,
                        "cut_shrink_j": 0.035})
    return out


def lamp_pocket(bmc, bmp, surf, grid):
    """A headlamp: a pocket cut into the nose and a gloss-black housing in it."""
    res = hits_2d(surf, "front", grid, 1.0)
    if not res:
        return
    pts, nrm = res
    grid_solid(bmc, [p + n * 0.03 for p, n in zip(pts, nrm)],
               [p - n * 0.018 for p, n in zip(pts, nrm)], len(grid), len(grid[0]), TRIM)
    oriented_grid(bmp, [p - n * 0.015 for p, n in zip(pts, nrm)], nrm, len(grid), len(grid[0]),
                  GLASS)


def round_grid(cx, cz, rx, rz, rings=3, segs=14):
    """A disc (rings x segs) as a 2D grid, for round lamps and badges."""
    g = []
    for r in range(rings + 1):
        t = r / rings
        g.append([(cx + rx * t * math.cos(2 * math.pi * k / segs),
                   cz + rz * t * math.sin(2 * math.pi * k / segs)) for k in range(segs + 1)])
    return g


def chrome_bars(bmp, x0, x1, z0, z1, y_front, n, thick=0.018, depth=0.03):
    """Horizontal chrome bars across a grille mouth (the SUV's face)."""
    for k in range(n):
        z = z0 + (z1 - z0) * (k + 0.5) / n
        add_box(bmp, (x1 - x0, depth, thick), ((x0 + x1) * 0.5, y_front - depth * 0.5, z), CHROME)


def dent(body, centre, radius, depth, axis=Vector((1, 0, 0))):
    """Pushes the body in round `centre` (the beater's door): a smooth crater along -axis on the
    side `centre.x` is on, with a little crumple, the way a parking-lot hit leaves a door."""
    me = body.data
    side = 1.0 if centre.x > 0 else -1.0
    push = Vector((axis.x * side, axis.y, axis.z))
    for v in me.vertices:
        if (v.co.x > 0) != (side > 0):
            continue
        d = (v.co - centre)
        d.x = 0.0
        x2 = d.length_squared / (radius * radius)
        if x2 >= 1.0:
            continue
        fall = (1.0 - x2) ** 2
        wob = 0.75 + 0.25 * math.sin(v.co.y * 47.0 + v.co.z * 31.0)
        v.co -= push * depth * fall * wob
    me.update()


def everyday_details(s, sec, surf, body, parts):
    d = s["d"]
    fa, ra, R = s["front_axle"], s["rear_axle"], s["arch_r"]
    wins = windows_from(s, sec)
    cut_windows(body, surf, wins)

    bmc = bmesh.new()
    bmp = bmesh.new()
    # Headlamps.
    hl = d["headlamp"]
    for side in (1.0, -1.0):
        if hl.get("round"):
            for cx, rr in hl["round"]:
                g = round_grid(cx, hl["z"], rr, rr)
                lamp_pocket(bmc, bmp, surf, g if side > 0 else mirror2(g))
                lens = round_grid(cx, hl["z"], rr * 0.62, rr * 0.62, 2, 12)
                applied(bmp, surf, "front", lens if side > 0 else mirror2(lens), -0.012, LIGHT_F)
        else:
            g = blade_grid(*hl["blade"], 3, 18)
            lamp_pocket(bmc, bmp, surf, g if side > 0 else mirror2(g))
            if "drl" in hl:
                drl = blade_grid(*hl["drl"], 1, 18)
                applied(bmp, surf, "front", drl if side > 0 else mirror2(drl), -0.011, LIGHT_F)
            for xc in hl.get("eyes", []):
                zc, hw, hh = hl["eye_z"], hl.get("eye_w", 0.034), hl.get("eye_h", 0.014)
                eye = rect_grid(xc - hw, xc + hw, zc - hh, zc + hh, 1, 3)
                applied(bmp, surf, "front", eye if side > 0 else mirror2(eye), -0.013, CHROME)
                lens = rect_grid(xc - hw * 0.7, xc + hw * 0.7, zc - hh * 0.65, zc + hh * 0.65, 1, 3)
                applied(bmp, surf, "front", lens if side > 0 else mirror2(lens), -0.0115, LIGHT_F)
            if "lens" in hl:
                # An old car's sealed lens: the whole lamp is the clear lens.
                lens = blade_grid(*hl["lens"], 2, 12)
                applied(bmp, surf, "front", lens if side > 0 else mirror2(lens), -0.009, LIGHT_F)
            if "amber" in hl:
                am = blade_grid(*hl["amber"], 1, 4)
                applied(bmp, surf, "front", am if side > 0 else mirror2(am), -0.009, LIGHT_R)
    if "lamp_band" in d:
        band = blade_grid(*d["lamp_band"], 2, 16)
        applied(bmp, surf, "front", band, 0.0025, GLASS, thickness=0.004)
    # Grille mouth.
    gr = d["grille"]
    boolean(body, extrude_cutter(rounded_outline(gr["outline"], gr.get("round", 0.04)), "y",
                                 gr["cut_from"], s["nose"] + 1.0))
    x0, x1, z0, z1 = gr["box"]
    if gr.get("bars"):
        eggcrate(bmp, x0, x1, z0, z1, gr["y"][0], gr["y"][1], 2, 1, thick=0.012)
        chrome_bars(bmp, x0, x1, z0, z1, gr["y"][0], gr["bars"], thick=gr.get("bar_t", 0.02))
    else:
        eggcrate(bmp, x0, x1, z0, z1, gr["y"][0], gr["y"][1], gr["nv"], gr["nh"],
                 thick=gr.get("thick", 0.0045))
    if "surround" in gr:
        # A chrome frame round the mouth.
        sx0, sx1, sz0, sz1, w = gr["surround"]
        for g in (rect_grid(sx0, sx1, sz1 - w, sz1, 1, 16), rect_grid(sx0, sx1, sz0, sz0 + w, 1, 16),
                  rect_grid(sx0, sx0 + w, sz0, sz1, 4, 1), rect_grid(sx1 - w, sx1, sz0, sz1, 4, 1)):
            applied(bmp, surf, "front", g, 0.006, CHROME, thickness=0.012)
    if "low" in d:
        lo = d["low"]
        boolean(body, extrude_cutter(rounded_outline(lo["outline"], 0.02), "y", lo["cut_from"],
                                     s["nose"] + 1.0))
        x0, x1, z0, z1 = lo["box"]
        eggcrate(bmp, x0, x1, z0, z1, lo["y"][0], lo["y"][1], lo.get("nv", 16), lo.get("nh", 1))
    for side in (1.0, -1.0):
        for fog in d.get("fogs", []):
            g = rect_grid(*fog, 1, 3)
            applied(bmp, surf, "front", g if side > 0 else mirror2(g), fog_proud(d), LIGHT_F)
    if "front_bumper" in d:
        z0, z1, proud, mat = d["front_bumper"]
        wrap_band(bmp, surf, 1.0, z0, z1, proud, mat, reach=0.30, corner_r=0.20, thickness=0.05)
    if "front_band" in d:
        g = rect_grid(*d["front_band"], 2, 26)
        applied(bmp, surf, "front", g, 0.004, TRIM, thickness=0.008)
    if "skid" in d:
        g = rect_grid(*d["skid"], 1, 12)
        applied(bmp, surf, "front", g, d.get("skid_proud", 0.010), CHROME, thickness=0.006)
    # Plate recess at the back.
    plate = rect_grid(*d["plate"], 2, 8)
    res = hits_2d(surf, "rear", plate, 1.0)
    if res:
        pts, nrm = res
        grid_solid(bmc, [p + n * 0.02 for p, n in zip(pts, nrm)],
                   [p - n * 0.010 for p, n in zip(pts, nrm)], 3, 9, TRIM)
    for side in (1.0, -1.0):
        for y, z in d["handles"]:
            flush_handle(bmc, bmp, surf, y, z, side, mat=d.get("handle_mat", PAINT),
                         length=d.get("handle_len", 0.15))
    tidy(bmc)
    boolean(body, new_object("cut_pockets", bmc))

    # Panel gaps.
    paths = []
    for side in (1.0, -1.0):
        for line in d["gaps_side"]:
            paths.append(surface_path(surf, "side", line, side))
        # The rear door's shut line runs round the rear arch.
        rd = d["rear_door"]
        arc = circle_path(ra, s["axle_z"], s["arch_r_rear"] + rd[2], rd[3], rd[4], 10)
        paths.append(surface_path(surf, "side", [(rd[0], rd[1]), (rd[0], arc[0][1])] + arc[1:],
                                  side))
        paths.append(surface_path(surf, "side", [(d["sill_gap"][0], d["sill_gap"][1]),
                                                  (arc[-1][0], d["sill_gap"][1])], side))
        for line in d.get("gaps_fj", []):
            paths.append(fj_path(surf, line, side))
    for line in d.get("gaps_rear", []):
        paths.append(surface_path(surf, "rear", line, 1.0))
    for line in d.get("gaps_one_side", []):
        paths.append(surface_path(surf, "side", line[1], line[0]))
    flap = circle_path(*d["fuel"], 0.075, 5.0, 352.0, 24)
    paths.append(surface_path(surf, "side", flap, -1.0 if d.get("fuel_left") else 1.0, step=0.015))
    cut_grooves(body, paths)

    parts.append(build_glass(surf, wins, 0.007))
    bmt = bmesh.new()
    for side in (1.0, -1.0):
        for f0, f1 in d.get("black_pillars", []):
            fj_applied(bmt, surf, f0, f1, lambda f: sec.j_along(f, 5.0, 0.018),
                       lambda f: sec.j_along(f, 6.0, 0.016, -1.0), 6, 3, 0.002, GLASS, side,
                       thickness=0.006)
        for f0, f1 in d.get("black_dividers", []):
            fj_applied(bmt, surf, f0, f1, lambda f: sec.j_along(f, 5.0, 0.022),
                       lambda f: sec.j_along(f, 6.0, 0.02, -1.0), 5, 1, -0.004, TRIM, side)
        b0, b1 = d["belt_trim"]
        fj_applied(bmt, surf, lambda j: b0, lambda j: b1, lambda f: sec.j_along(f, 5.0, 0.004),
                   lambda f: sec.j_along(f, 5.0, 0.017), 1, 44, 0.0025, d.get("belt_mat", CHROME),
                   side, thickness=0.005)
        if "rocker" in d:
            j0, j1, mat = d["rocker"]
            fj_applied(bmt, surf, ra + R + 0.03, fa - R - 0.03, j0, j1, 2, 30, 0.006, mat, side,
                       thickness=0.010)
        if "rub_strip" in d:
            z, h = d["rub_strip"]
            strip = surface_path(surf, "side", [(fa - R - 0.04, z), (ra + R + 0.04, z)], side,
                                 step=0.08)
            if len(strip) > 2:
                prof = [(-h, -0.004), (-h * 0.8, 0.008), (h * 0.8, 0.008), (h, -0.004)]
                sweep(bmt, [p for p, _n in strip], prof, TRIM, normals=[n for _p, n in strip])
        if "roof_rail" in d:
            f0, f1, j, lift = d["roof_rail"]
            rail = fj_path(surf, [(f0, j), (f1, j)], side, step=0.05)
            if len(rail) > 3:
                pts = [p + n * lift for p, n in rail]
                prof = [(-0.014, -0.012), (0.014, -0.012), (0.012, 0.012), (-0.012, 0.012)]
                sweep(bmt, pts, prof, d.get("rail_mat", TRIM), normals=[n for _p, n in rail])
                for k in (1, len(rail) // 2, len(rail) - 2):
                    p, n = rail[k]
                    add_box(bmt, (0.03, 0.08, lift + 0.01), p + n * (lift * 0.5), TRIM)
        for track in d.get("door_tracks", []):
            # A sliding door's track: a channel along the quarter, under the rear side glass.
            (f0, z0), (f1, z1) = track
            tr = surface_path(surf, "side", [(f0, z0), (f1, z1)], side, step=0.06)
            if len(tr) > 2:
                prof = [(-0.012, -0.005), (-0.012, 0.010), (0.012, 0.010), (0.012, -0.005)]
                sweep(bmt, [p for p, _n in tr], prof, TRIM, normals=[n for _p, n in tr])
        for (cy, cz, w, h) in d.get("side_markers", []):
            g = rect_grid(cy - w, cy + w, cz - h, cz + h, 1, 2)
            applied(bmt, surf, "side", g, 0.003, LIGHT_R, side, thickness=0.004)
    if "cowl" in d:
        c0, c1 = d["cowl"]
        fj_applied(bmt, surf, c0, c1, lambda f: sec.j_along(f, 5.0, 0.03), 7.0, 12, 3, 0.003,
                   TRIM, 1.0, thickness=0.006, centre=True)
    if "spoiler" in d:
        f0, f1, proud = d["spoiler"]
        fj_applied(bmt, surf, f0, f1, lambda f: sec.j_along(f, 6.0, 0.03), 7.0, 12, 2, proud,
                   PAINT, 1.0, thickness=0.02, centre=True)
    # Tail lamps.
    tl = d["tail"]
    if "bar" in tl:
        bar = blade_grid(*tl["bar"], 1, 24)
        applied(bmt, surf, "rear", bar, 0.003, LIGHT_R, thickness=0.006)
        bar_s = blade_grid(*tl["bar_s"], 1, 24)
        applied(bmt, surf, "rear", bar_s, 0.0015, GLASS, thickness=0.004)
    for side in (1.0, -1.0):
        for kind, args in tl["pieces"]:
            mat = {"glass": GLASS, "red": LIGHT_R, "clear": LIGHT_F, "trim": TRIM,
                   "chrome": CHROME}[kind]
            if callable(args):
                g = args(side)
                if g is None:
                    continue
            else:
                g = (blade_grid(*args[:6], args[6], args[7]) if len(args) == 8
                     else rect_grid(*args[:4], args[4], args[5]))
                g = g if side > 0 else mirror2(g)
            proud = {"glass": 0.002, "red": 0.0035, "clear": 0.0045, "trim": 0.004,
                     "chrome": 0.005}[kind]
            applied(bmt, surf, "rear", g, proud, mat,
                    thickness=0.005 if kind in ("glass", "trim", "chrome") else 0.0)
    if "hmsl" in tl:
        applied(bmt, surf, "rear", rect_grid(*tl["hmsl"], 1, 6), 0.004, LIGHT_R, thickness=0.008)
    if "rear_band" in d:
        g = rect_grid(*d["rear_band"], 2, 26)
        applied(bmt, surf, "rear", g, 0.005, d.get("rear_band_mat", TRIM), thickness=0.01)
    if "rear_bumper" in d:
        z0, z1, proud, mat = d["rear_bumper"]
        wrap_band(bmt, surf, -1.0, z0, z1, proud, mat, reach=0.24, corner_r=0.16, thickness=0.05)
    if "rear_skid" in d:
        g = rect_grid(*d["rear_skid"], 1, 12)
        applied(bmt, surf, "rear", g, 0.012, CHROME, thickness=0.006)
    for x0, x1, z0, z1 in d.get("rear_chrome", []):
        applied(bmt, surf, "rear", rect_grid(x0, x1, z0, z1, 1, 10), 0.004, CHROME, thickness=0.006)
    if d.get("cladding"):
        cladding(bmt, surf, s, *d["cladding"])
    elif d.get("lips", True):
        arch_lips(bmt, surf, s)
    if "extra" in d:
        d["extra"](s, sec, surf, body, parts, bmt, bmp)
    bmesh.ops.remove_doubles(bmt, verts=bmt.verts, dist=1e-6)
    parts.append(new_object("trims", bmt))
    bmesh.ops.remove_doubles(bmp, verts=bmp.verts, dist=1e-6)
    parts.append(new_object("inserts", bmp))
    for side in (1.0, -1.0):
        mf, mj, head, size = d["mirror"]
        mirror(parts, surf, s, side, mf, mj, head, size, head_mat=d.get("mirror_mat", PAINT))
    if "dents" in d:
        for c, r, depth in d["dents"]:
            dent(body, Vector(c), r, depth)


def overhangs(fa, ra, nose, tail, new_nose, new_tail):
    """A map of stations that keeps the wheelbase and scales the overhangs: the profiles are
    drawn for `nose` / `tail` and the car is built to `new_nose` / `new_tail`."""
    kf = (new_nose - fa) / (nose - fa)
    kr = (new_tail - ra) / (tail - ra)

    def fm(f):
        if f > fa:
            return fa + (f - fa) * kf
        if f < ra:
            return ra + (f - ra) * kr
        return f
    return fm


def remap(s, fm):
    """Applies a station map to every station the spec's loft reads (profiles, ends, cowl, deck,
    holding stations, creases, sculpt)."""
    for k, v in s["profile"].items():
        if isinstance(v, list):
            s["profile"][k] = [(fm(f), z) for f, z in v]
    for k in ("nose", "tail", "cowl", "deck"):
        s[k] = fm(s[k])
    s["extra_stations"] = [fm(f) for f in s.get("extra_stations", [])]
    s["station_creases"] = [(fm(f), a, b, c) for f, a, b, c in s.get("station_creases", [])]
    s["creases"] = [(j, v, fm(a), fm(b)) for j, v, a, b in s.get("creases", [])]
    s["sculpt"] = [(fm(a), fm(b), ff, j0, j1, jf, amt) for a, b, ff, j0, j1, jf, amt in s.get("sculpt", [])]
    s["length"] = s["nose"] - s["tail"]


def fog_proud(d):
    return d.get("fog_proud", -0.03)


# --- the hatchback -------------------------------------------------------------------------------

def hatchback():
    """A 5-door compact hatchback (4.33 m): a short bonnet, a long roof falling to a raked hatch
    with a spoiler over its glass, a short rear overhang, slim lamps, a wide low mouth."""
    s = {"name": "hatchback", "length": 4.30}
    s.update({
        "nose": 2.135, "tail": -2.165,
        "front_axle": 1.29, "rear_axle": -1.34, "axle_z": 0.318,
        "wheel_r": 0.318, "wheel_w": 0.215, "wheel_x": 0.772,
        "arch_r": 0.362, "arch_r_rear": 0.362, "arch_in": 0.55,
        "road": -0.170, "belt_probe_z": 0.9,
        "cowl": 0.86, "deck": -2.14, "gh_blend_front": 0.14, "gh_blend_rear": 0.04,
        "crown_at": 0.60, "tension": 1.0, "under_j": 1.0,
        "rings": RINGS, "end_steps": END_STEPS, "mid_step": 0.25,
        "extra_stations": [0.86, -1.72, -2.02],
        "creases": [(4.0, 0.8, -3.0, 3.0)],
        "nose_cap": {"steps": 3, "roll": lambda j: 0.045, "dome": 0.060,
                     "lean": lambda co: 0.040 * ramp(co.z, 0.72, 0.38)},
        "tail_cap": {"steps": 3, "roll": lambda j: 0.040, "dome": 0.030,
                     "lean": lambda co: -0.025 * ramp(co.z, 0.70, 0.40)},
        "sculpt": [
            (-1.05, -1.55, 0.40, 3.55, 4.3, 0.55, 0.011),
            (1.05, 1.55, 0.35, 3.55, 4.4, 0.50, 0.007),
            (0.80, -0.85, 0.35, 2.55, 3.1, 0.35, -0.010),
            (3.0, -3.0, 0.0, 3.97, 4.03, 0.10, 0.005),
            (0.95, 1.85, 0.22, 6.45, 7.0, 0.30, 0.008),
        ],
        "profile": {
            "top": [(2.135, 0.700), (2.10, 0.728), (2.03, 0.758), (1.90, 0.792), (1.70, 0.832),
                    (1.45, 0.872), (1.20, 0.905), (1.00, 0.928), (0.90, 0.942), (0.86, 0.952),
                    (0.78, 0.992), (0.62, 1.075), (0.45, 1.168), (0.30, 1.246), (0.18, 1.302),
                    (0.06, 1.345), (-0.10, 1.380), (-0.35, 1.400), (-0.70, 1.404),
                    (-1.00, 1.390), (-1.25, 1.366), (-1.45, 1.336), (-1.60, 1.304),
                    (-1.72, 1.268), (-1.80, 1.222), (-1.88, 1.162), (-1.95, 1.104),
                    (-2.00, 1.064), (-2.02, 1.050), (-2.07, 1.025), (-2.12, 1.002),
                    (-2.165, 0.975)],
            "rail_z": [(1.00, 0.920), (0.86, 0.945), (0.76, 0.990), (0.60, 1.065),
                       (0.45, 1.140), (0.30, 1.210), (0.15, 1.262), (0.0, 1.298),
                       (-0.25, 1.322), (-0.60, 1.328), (-1.00, 1.316), (-1.30, 1.290),
                       (-1.50, 1.258), (-1.65, 1.222), (-1.76, 1.176), (-1.86, 1.112),
                       (-1.95, 1.055), (-2.02, 1.025), (-2.10, 1.004), (-2.165, 0.988)],
            "rail_w": [(1.00, 0.800), (0.86, 0.790), (0.60, 0.768), (0.30, 0.748),
                       (0.0, 0.736), (-0.60, 0.732), (-1.20, 0.734), (-1.60, 0.740),
                       (-1.85, 0.744), (-2.165, 0.750)],
            "belt_z": [(2.135, 0.690), (2.05, 0.735), (1.85, 0.790), (1.55, 0.842),
                       (1.20, 0.885), (0.86, 0.918), (0.40, 0.940), (-0.40, 0.965),
                       (-1.00, 0.985), (-1.40, 1.010), (-1.70, 1.040), (-1.90, 1.052),
                       (-2.05, 1.025), (-2.165, 0.985)],
            "belt_in": [(2.135, 0.048), (1.8, 0.056), (0.0, 0.062), (-1.8, 0.066),
                        (-2.165, 0.055)],
            "shoulder_z": [(2.135, 0.600), (1.95, 0.690), (1.65, 0.735), (1.00, 0.752),
                           (0.00, 0.768), (-1.00, 0.790), (-1.70, 0.812), (-2.05, 0.820),
                           (-2.165, 0.810)],
            "width": [(2.135, 0.660), (2.115, 0.730), (2.08, 0.785), (2.02, 0.828),
                      (1.92, 0.860), (1.75, 0.884), (1.50, 0.896), (1.29, 0.899),
                      (1.00, 0.896), (0.30, 0.890), (-0.50, 0.891), (-1.00, 0.898),
                      (-1.34, 0.903), (-1.62, 0.898), (-1.85, 0.884), (-2.00, 0.862),
                      (-2.10, 0.832), (-2.145, 0.795), (-2.165, 0.740)],
            "low_z": [(2.135, 0.40), (1.3, 0.40), (0.0, 0.42), (-1.34, 0.44), (-2.165, 0.46)],
            "low_in": 0.040,
            "sill_z": [(2.135, 0.268), (1.95, 0.250), (1.60, 0.232), (1.29, 0.225),
                       (0.0, 0.215), (-1.34, 0.228), (-1.70, 0.265), (-1.95, 0.305),
                       (-2.165, 0.335)],
            "sill_in": [(2.135, 0.065), (1.8, 0.07), (-1.8, 0.07), (-2.165, 0.065)],
            "floor_z": [(2.135, 0.250), (1.95, 0.205), (1.60, 0.165), (1.29, 0.150),
                        (0.0, 0.145), (-1.34, 0.152), (-1.70, 0.205), (-1.95, 0.270),
                        (-2.165, 0.310)],
            "floor_in": 0.10,
        },
    })
    fm = overhangs(1.29, -1.34, 2.135, -2.165, 2.065, -2.095)
    remap(s, fm)
    s["d"] = {
        "windows": [
            ("windscreen", "screen", 0.10, 0.84, 0.058),
            ("front", "side", -0.295, 0.815),
            ("rear", "side", -1.110, -0.395),
            ("quarter", "side", lambda j: fm(-1.62) + 0.12 * min(max(0.0 if j is None else j - 5.0, 0.0), 1.0),
             -1.215),
            ("backlight", "screen", fm(-2.000), fm(-1.745), 0.050),
        ],
        "headlamp": {"blade": (0.36, 0.800, 0.652, 0.668, 0.062, 0.082),
                     "drl": (0.37, 0.790, 0.680, 0.700, 0.009, 0.011),
                     "eyes": [0.52, 0.63], "eye_z": 0.657},
        "lamp_band": (-0.37, 0.37, 0.665, 0.665, 0.030, 0.030),
        "grille": {"outline": [(-0.30, 0.600), (0.30, 0.600), (0.33, 0.545), (-0.33, 0.545)],
                   "round": 0.02, "cut_from": 2.02, "box": (-0.35, 0.35, 0.545, 0.600),
                   "y": (2.10, 2.05), "nv": 18, "nh": 1},
        "low": {"outline": [(-0.50, 0.470), (0.50, 0.470), (0.56, 0.330), (-0.56, 0.330)],
                "cut_from": 2.02, "box": (-0.58, 0.58, 0.330, 0.470), "y": (2.10, 2.04),
                "nv": 26, "nh": 3},
        "fogs": [(0.64, 0.74, 0.360, 0.385)],
        "front_band": (-0.74, 0.74, 0.255, 0.320),
        "plate": (-0.25, 0.25, 0.690, 0.820),
        "handles": [(0.28, 0.880), (-0.75, 0.905)],
        "gaps_side": [
            [(0.835, 0.95), (0.828, 0.70), (0.820, 0.40), (0.815, 0.27)],
            [(-0.352, 0.975), (-0.352, 0.27)],
            [(0.815, 0.27), (-0.352, 0.27)],
            [(fm(1.925), 0.672), (fm(1.82), 0.610), (fm(1.70), 0.585), (1.29 + 0.362 + 0.03, 0.575)],
            [(fm(-1.960), 0.905), (fm(-1.93), 0.780), (fm(-1.80), 0.640), (-1.34 - 0.362 - 0.03, 0.610)],
        ],
        "rear_door": (-1.170, 0.995, 0.055, 52.0, 8.0),
        "sill_gap": (-0.352, 0.27),
        "gaps_fj": [[(0.89, 5.40), (fm(2.115), 5.40)], [(fm(2.115), 5.40), (fm(2.115), 7.0)]],
        "gaps_rear": [[(0.64, 1.06), (0.665, 0.90), (0.67, 0.64), (0.0, 0.635), (-0.67, 0.64),
                       (-0.665, 0.90), (-0.64, 1.06)]],
        "fuel": (fm(-1.56), 0.875),
        "black_pillars": [(-0.395, -0.295), (-1.215, -1.110)],
        "belt_trim": (fm(-1.62), 0.83),
        "belt_mat": TRIM,
        "cowl": (0.83, 0.90),
        "spoiler": (fm(-1.80), fm(-1.71), 0.012),
        "tail": {
            "pieces": [
                ("glass", (0.48, 0.855, 0.955, 0.935, 0.105, 0.080, 3, 14)),
                ("red", (0.50, 0.845, 0.985, 0.958, 0.022, 0.018, 1, 14)),
                ("red", (0.56, 0.840, 0.915, 0.905, 0.014, 0.012, 1, 12)),
                ("clear", (0.66, 0.74, 0.935, 0.935, 0.024, 0.024, 1, 3)),
                ("red", (0.62, 0.74, 0.43, 0.448, 1, 4)),
            ],
            "hmsl": (-0.14, 0.14, 1.265, 1.285),
        },
        "rear_band": (-0.74, 0.74, 0.34, 0.47),
        "mirror": (0.78, 5.05, (0.965, 0.770, 0.985), (0.21, 0.085, 0.120)),
    }
    s["details"] = everyday_details
    return s


rc.SPECS["hatchback"] = hatchback


# --- the full-size SUV ---------------------------------------------------------------------------

def suv():
    """A full-size three-row SUV (5.35 m, 1.93 m tall): a long flat bonnet high over an upright
    face with a tall chrome-barred grille, a square body with a flat roof (the van's ninth
    anchor), three side windows, an upright tailgate, wide flanks and roof rails."""
    s = {"name": "suv", "length": 5.35, "height": 1.93}
    s.update({
        "nose": 2.665, "tail": -2.665,
        "front_axle": 1.70, "rear_axle": -1.37, "axle_z": 0.405,
        "wheel_r": 0.405, "wheel_w": 0.275, "wheel_x": 0.870,
        "arch_r": 0.468, "arch_r_rear": 0.468, "arch_in": 0.62,
        "road": -0.215, "belt_probe_z": 1.25,
        "cowl": 1.00, "deck": -2.62, "gh_blend_front": 0.12, "gh_blend_rear": 0.03,
        "crown_at": 0.62, "tension": 1.0, "under_j": 1.0,
        "rings": [0.0, 1.0, 1.6, 2.1, 2.85, 3.4, 3.92, 4.0, 4.08, 4.6, 5.0, 5.5, 6.0, 6.25,
                  6.5, 6.75, 7.0],
        "end_steps": [0.0, 0.012, 0.03, 0.06, 0.10, 0.16, 0.24],
        "mid_step": 0.36,
        "extra_stations": [1.06, 1.00, 0.94, -2.48, -2.55, -2.60],
        "creases": [(4.0, 0.6, -3.0, 3.0), (5.0, 0.5, -2.62, 1.00)],
        "station_creases": [(1.00, 0.5, 5.2, 7.0), (-2.55, 0.5, 6.0, 7.0)],
        "tangent_over": {6: (-0.10, 1.0), 7: (-1.0, 0.0)},
        "nose_cap": {"steps": 3, "roll": lambda j: 0.055, "dome": 0.030,
                     "lean": lambda co: 0.020 * ramp(co.z, 1.05, 0.70)},
        "tail_cap": {"steps": 3, "roll": lambda j: 0.050, "dome": 0.015},
        "sculpt": [
            (3.0, -3.0, 0.0, 3.97, 4.03, 0.10, 0.004),
            (-1.00, -1.75, 0.35, 3.55, 4.3, 0.55, 0.012),
            (1.35, 2.05, 0.30, 3.55, 4.4, 0.50, 0.012),
            (1.10, 2.40, 0.25, 6.50, 7.0, 0.30, 0.012),
        ],
        "profile": {
            "top": [(2.665, 1.150), (2.64, 1.176), (2.58, 1.198), (2.40, 1.224), (2.10, 1.250),
                    (1.70, 1.272), (1.30, 1.288), (1.06, 1.296), (1.00, 1.302), (0.94, 1.330),
                    (0.80, 1.420), (0.60, 1.555), (0.42, 1.672), (0.30, 1.745), (0.20, 1.800),
                    (0.10, 1.840), (0.0, 1.868), (-0.20, 1.892), (-0.50, 1.902),
                    (-2.40, 1.902), (-2.50, 1.896), (-2.55, 1.880), (-2.58, 1.820),
                    (-2.61, 1.640), (-2.63, 1.420), (-2.65, 1.240), (-2.665, 1.150)],
            "rail_z": [(1.20, 1.280), (1.00, 1.296), (0.94, 1.322), (0.80, 1.405),
                       (0.60, 1.528), (0.42, 1.630), (0.25, 1.705), (0.10, 1.752),
                       (-0.10, 1.778), (-0.50, 1.790), (-2.40, 1.790), (-2.50, 1.782),
                       (-2.55, 1.762), (-2.58, 1.700), (-2.61, 1.540), (-2.63, 1.380),
                       (-2.665, 1.260)],
            "rail_w": [(1.20, 0.935), (1.00, 0.925), (0.70, 0.905), (0.30, 0.885),
                       (-0.10, 0.878), (-1.20, 0.880), (-2.40, 0.880), (-2.665, 0.875)],
            "roof_z": [(1.20, 1.288), (1.00, 1.300), (0.94, 1.327), (0.80, 1.415),
                       (0.60, 1.545), (0.42, 1.658), (0.25, 1.737), (0.10, 1.790),
                       (-0.10, 1.828), (-0.50, 1.842), (-2.40, 1.842), (-2.50, 1.836),
                       (-2.55, 1.818), (-2.58, 1.760), (-2.61, 1.590), (-2.665, 1.300)],
            "roof_w": [(1.20, 0.60), (0.80, 0.62), (0.40, 0.74), (0.0, 0.80), (-2.40, 0.81),
                       (-2.665, 0.80)],
            "over_w": [(2.665, 0.0), (0.90, 0.0), (0.50, 1.0), (-2.665, 1.0)],
            "belt_z": [(2.665, 1.130), (2.55, 1.180), (2.30, 1.214), (1.80, 1.240),
                       (1.00, 1.262), (0.0, 1.274), (-1.20, 1.284), (-2.20, 1.296),
                       (-2.55, 1.300), (-2.665, 1.280)],
            "belt_in": [(2.665, 0.030), (2.0, 0.036), (0.0, 0.040), (-2.4, 0.042),
                        (-2.665, 0.036)],
            "shoulder_z": [(2.665, 0.980), (2.40, 1.060), (2.00, 1.090), (1.00, 1.100),
                           (-1.00, 1.110), (-2.40, 1.120), (-2.665, 1.100)],
            "width": [(2.665, 0.880), (2.645, 0.940), (2.60, 0.982), (2.50, 1.010),
                      (2.30, 1.024), (1.70, 1.030), (0.50, 1.026), (-0.50, 1.026),
                      (-1.37, 1.030), (-2.30, 1.024), (-2.50, 1.012), (-2.60, 0.990),
                      (-2.665, 0.940)],
            "low_z": [(2.665, 0.66), (0.0, 0.62), (-2.665, 0.66)],
            "low_in": 0.030,
            "sill_z": [(2.665, 0.470), (2.40, 0.450), (2.00, 0.420), (1.70, 0.405),
                       (0.0, 0.395), (-1.37, 0.405), (-1.80, 0.430), (-2.30, 0.470),
                       (-2.665, 0.500)],
            "sill_in": [(2.665, 0.060), (2.0, 0.065), (-2.0, 0.065), (-2.665, 0.060)],
            "floor_z": [(2.665, 0.440), (2.30, 0.380), (2.00, 0.320), (1.70, 0.290),
                        (0.0, 0.280), (-1.37, 0.290), (-1.80, 0.330), (-2.30, 0.420),
                        (-2.665, 0.470)],
            "floor_in": 0.12,
        },
    })
    fa, ra = 1.70, -1.37
    s["d"] = {
        "belt_gap": 0.024, "top_gap": 0.022,
        "windows": [
            ("windscreen", "screen", 0.07, 0.985, 0.062),
            ("front", "side", -0.330, 0.960),
            ("rear", "side", -1.395, -0.430),
            ("quarter", "side", -2.430, -1.500),
            ("backlight", "screen", -2.605, -2.555, 0.060),
        ],
        "headlamp": {"blade": (0.52, 0.925, 1.075, 1.085, 0.090, 0.105),
                     "drl": (0.53, 0.915, 1.032, 1.040, 0.012, 0.014),
                     "eyes": [0.66, 0.78], "eye_z": 1.082, "eye_w": 0.040, "eye_h": 0.018},
        "grille": {"outline": [(-0.53, 1.135), (0.53, 1.135), (0.53, 0.705), (-0.53, 0.705)],
                   "round": 0.04, "cut_from": 2.58, "box": (-0.55, 0.55, 0.705, 1.135),
                   "y": (2.665, 2.60), "bars": 4, "bar_t": 0.030,
                   "surround": (-0.565, 0.565, 0.690, 1.150, 0.030)},
        "low": {"outline": [(-0.50, 0.600), (0.50, 0.600), (0.46, 0.510), (-0.46, 0.510)],
                "cut_from": 2.56, "box": (-0.52, 0.52, 0.510, 0.600), "y": (2.64, 2.58)},
        "fogs": [(0.70, 0.84, 0.560, 0.600)],
        "fog_proud": 0.040,
        "front_bumper": (0.470, 0.680, 0.040, TRIM),
        "skid": (-0.48, 0.48, 0.470, 0.500), "skid_proud": 0.045,
        "plate": (-0.27, 0.27, 1.070, 1.210),
        "handles": [(0.50, 1.140), (-0.62, 1.155), ],
        "handle_mat": CHROME, "handle_len": 0.20,
        "gaps_side": [
            [(0.995, 1.28), (0.985, 1.00), (0.975, 0.70), (0.970, 0.44)],
            [(-0.425, 1.32), (-0.425, 0.44)],
            [(0.970, 0.44), (-0.425, 0.44)],
            [(2.50, 1.050), (2.30, 0.950), (2.20, 0.880), (fa + 0.468 + 0.04, 0.860)],
            [(-2.55, 1.10), (-2.50, 0.95), (-2.35, 0.86), (ra - 0.468 - 0.04, 0.84)],
        ],
        "rear_door": (-1.430, 1.300, 0.060, 60.0, 10.0),
        "sill_gap": (-0.425, 0.44),
        "gaps_fj": [[(1.05, 5.30), (2.62, 5.30)], [(2.62, 5.30), (2.62, 7.0)]],
        "gaps_rear": [[(0.80, 1.80), (0.82, 1.30), (0.82, 0.86), (0.0, 0.855), (-0.82, 0.86),
                       (-0.82, 1.30), (-0.80, 1.80)]],
        "fuel": (-1.95, 1.18),
        "fuel_left": True,
        "black_pillars": [(-0.430, -0.330), (-1.500, -1.395)],
        "belt_trim": (-2.43, 0.97),
        "rocker": (1.7, 2.3, CHROME),
        "roof_rail": (-0.10, -2.35, 6.75, 0.055),
        "rail_mat": CHROME,
        "cowl": (0.97, 1.05),
        "spoiler": (-2.53, -2.43, 0.014),
        "tail": {
            "pieces": [
                ("red", (0.78, 0.905, 1.020, 1.600, 6, 2)),
                ("glass", (0.77, 0.910, 1.000, 1.620, 6, 2)),
                ("clear", (0.80, 0.885, 1.220, 1.300, 1, 2)),
            ],
            "hmsl": (-0.18, 0.18, 1.845, 1.870),
        },
        "rear_chrome": [(-0.62, 0.62, 1.300, 1.330)],
        "rear_bumper": (0.500, 0.720, 0.045, TRIM),
        "rear_skid": (-0.40, 0.40, 0.520, 0.545),
        "cladding": (0.075, 0.016),
        "mirror": (0.90, 5.10, (1.140, 0.890, 1.390), (0.24, 0.10, 0.20)),
    }
    s["details"] = everyday_details
    return s


rc.SPECS["suv"] = suv


# --- the minivan ---------------------------------------------------------------------------------

def minivan():
    """A minivan (5.15 m, 1.78 m): a short sloped nose running into a fast windscreen, a long
    level roof, a tall glasshouse with a small front quarter light, sliding rear doors on both
    sides with their tracks along the quarter under the rear glass, an upright tailgate."""
    s = {"name": "minivan", "length": 5.15, "height": 1.78}
    s.update({
        "nose": 2.565, "tail": -2.585,
        "front_axle": 1.60, "rear_axle": -1.43, "axle_z": 0.358,
        "wheel_r": 0.358, "wheel_w": 0.235, "wheel_x": 0.852,
        "arch_r": 0.412, "arch_r_rear": 0.412, "arch_in": 0.60,
        "road": -0.190, "belt_probe_z": 1.1,
        "cowl": 1.38, "deck": -2.56, "gh_blend_front": 0.16, "gh_blend_rear": 0.03,
        "crown_at": 0.60, "tension": 1.0, "under_j": 1.0,
        "rings": RINGS, "end_steps": END_STEPS, "mid_step": 0.30,
        "extra_stations": [1.38, -2.36, -2.46],
        "creases": [(4.0, 0.7, -3.0, 3.0)],
        "station_creases": [(-2.46, 0.4, 6.0, 7.0)],
        "nose_cap": {"steps": 3, "roll": lambda j: 0.050, "dome": 0.060,
                     "lean": lambda co: 0.040 * ramp(co.z, 0.85, 0.45)},
        "tail_cap": {"steps": 3, "roll": lambda j: 0.045, "dome": 0.020,
                     "lean": lambda co: -0.015 * ramp(co.z, 0.80, 0.45)},
        "sculpt": [
            (-1.15, -1.75, 0.40, 3.55, 4.3, 0.55, 0.009),
            (1.35, 1.85, 0.35, 3.55, 4.4, 0.50, 0.008),
            (3.0, -3.0, 0.0, 3.97, 4.03, 0.10, 0.004),
            (1.45, 2.40, 0.22, 6.45, 7.0, 0.30, 0.008),
        ],
        "profile": {
            "top": [(2.565, 0.870), (2.53, 0.898), (2.45, 0.928), (2.30, 0.966), (2.10, 1.010),
                    (1.85, 1.060), (1.60, 1.106), (1.46, 1.130), (1.38, 1.146),
                    (1.28, 1.196), (1.10, 1.290), (0.90, 1.392), (0.70, 1.490), (0.52, 1.570),
                    (0.38, 1.626), (0.25, 1.668), (0.10, 1.700), (-0.10, 1.722),
                    (-0.50, 1.738), (-1.20, 1.742), (-1.90, 1.736), (-2.20, 1.722),
                    (-2.36, 1.705), (-2.42, 1.690), (-2.46, 1.660), (-2.50, 1.560),
                    (-2.53, 1.400), (-2.555, 1.220), (-2.575, 1.080), (-2.585, 1.020)],
            "rail_z": [(1.50, 1.120), (1.38, 1.140), (1.28, 1.188), (1.10, 1.278),
                       (0.90, 1.375), (0.70, 1.466), (0.50, 1.540), (0.30, 1.596),
                       (0.10, 1.632), (-0.20, 1.652), (-1.20, 1.660), (-2.20, 1.648),
                       (-2.36, 1.630), (-2.42, 1.612), (-2.46, 1.585), (-2.50, 1.500),
                       (-2.53, 1.350), (-2.585, 1.040)],
            "rail_w": [(1.50, 0.900), (1.38, 0.890), (1.10, 0.868), (0.70, 0.842),
                       (0.30, 0.826), (-0.20, 0.820), (-1.50, 0.822), (-2.30, 0.826),
                       (-2.585, 0.830)],
            "belt_z": [(2.565, 0.850), (2.45, 0.905), (2.20, 0.960), (1.90, 1.000),
                       (1.60, 1.030), (1.38, 1.046), (0.80, 1.050), (0.0, 1.058),
                       (-1.00, 1.066), (-1.80, 1.076), (-2.30, 1.086), (-2.50, 1.076),
                       (-2.585, 1.040)],
            "belt_in": [(2.565, 0.046), (2.0, 0.052), (0.0, 0.056), (-2.2, 0.060),
                        (-2.585, 0.050)],
            "shoulder_z": [(2.565, 0.740), (2.30, 0.820), (1.90, 0.856), (1.00, 0.870),
                           (0.00, 0.878), (-1.00, 0.888), (-2.20, 0.900), (-2.585, 0.884)],
            "width": [(2.565, 0.760), (2.545, 0.830), (2.50, 0.880), (2.42, 0.918),
                      (2.28, 0.950), (2.05, 0.975), (1.75, 0.990), (1.40, 0.996),
                      (0.50, 0.994), (-0.80, 0.994), (-1.60, 0.996), (-2.10, 0.988),
                      (-2.35, 0.972), (-2.48, 0.946), (-2.56, 0.906), (-2.585, 0.850)],
            "low_z": [(2.565, 0.45), (0.0, 0.46), (-2.585, 0.48)],
            "low_in": 0.035,
            "sill_z": [(2.565, 0.330), (2.30, 0.305), (1.90, 0.285), (1.60, 0.272),
                       (0.0, 0.262), (-1.43, 0.272), (-1.85, 0.300), (-2.30, 0.340),
                       (-2.585, 0.370)],
            "sill_in": [(2.565, 0.065), (2.0, 0.07), (-2.0, 0.07), (-2.585, 0.065)],
            "floor_z": [(2.565, 0.310), (2.30, 0.260), (1.90, 0.215), (1.60, 0.195),
                        (0.0, 0.185), (-1.43, 0.195), (-1.85, 0.240), (-2.30, 0.305),
                        (-2.585, 0.345)],
            "floor_in": 0.11,
        },
    })
    fa, ra = 1.60, -1.43
    fm = overhangs(1.60, -1.43, 2.565, -2.585, 2.48, -2.50)
    remap(s, fm)
    s["d"] = {
        "windows": [
            ("windscreen", "screen", 0.20, 1.355, 0.060),
            ("quarterlight", "side", 1.010, 1.300),
            ("front", "side", 0.060, 0.930),
            ("rear", "side", -1.180, -0.040),
            ("quarter", "side", fm(-2.380), -1.270),
            ("backlight", "screen", fm(-2.535), fm(-2.390), 0.055),
        ],
        "headlamp": {"blade": (0.40, 0.900, 0.820, 0.872, 0.068, 0.100),
                     "drl": (0.41, 0.885, 0.850, 0.904, 0.010, 0.012),
                     "eyes": [0.58, 0.70], "eye_z": 0.838},
        "lamp_band": (-0.40, 0.40, 0.808, 0.808, 0.028, 0.028),
        "grille": {"outline": [(-0.40, 0.760), (0.40, 0.760), (0.46, 0.660), (-0.46, 0.660)],
                   "round": 0.035, "cut_from": 2.47, "box": (-0.48, 0.48, 0.660, 0.760),
                   "y": (2.55, 2.49), "nv": 22, "nh": 3},
        "low": {"outline": [(-0.62, 0.520), (0.62, 0.520), (0.56, 0.360), (-0.56, 0.360)],
                "cut_from": 2.45, "box": (-0.64, 0.64, 0.360, 0.520), "y": (2.55, 2.48),
                "nv": 30, "nh": 4},
        "front_band": (-0.80, 0.80, 0.310, 0.350),
        "plate": (-0.25, 0.25, 0.860, 0.990),
        "handles": [(0.62, 1.000), (-0.20, 1.010)],
        "handle_mat": CHROME,
        "gaps_side": [
            [(1.355, 1.12), (1.345, 0.90), (1.335, 0.60), (1.330, 0.32)],
            [(0.010, 1.08), (0.000, 0.32)],
            [(1.330, 0.32), (0.000, 0.32)],
            [(fm(2.38), 0.858), (fm(2.26), 0.800), (fm(2.12), 0.770), (fa + 0.412 + 0.03, 0.760)],
            [(fm(-2.44), 0.95), (fm(-2.40), 0.84), (fm(-2.25), 0.760), (ra - 0.412 - 0.03, 0.730)],
        ],
        # The sliding door: its rear edge, round the arch to the sill.
        "rear_door": (-1.200, 1.100, 0.060, 58.0, 10.0),
        "sill_gap": (0.000, 0.32),
        "gaps_fj": [[(1.42, 5.40), (fm(2.53), 5.40)], [(fm(2.53), 5.40), (fm(2.53), 7.0)]],
        "gaps_rear": [[(0.72, 1.62), (0.75, 1.20), (0.76, 0.82), (0.0, 0.815), (-0.76, 0.82),
                       (-0.75, 1.20), (-0.72, 1.62)]],
        "fuel": (fm(-1.75), 0.960),
        "black_pillars": [(-0.040, 0.060), (-1.270, -1.180)],
        "black_dividers": [(0.930, 1.010)],
        "belt_trim": (fm(-2.38), 1.30),
        "belt_mat": CHROME,
        # The sliding doors' tracks along the quarter, under the rear side glass.
        "door_tracks": [((-1.24, 1.065), (fm(-2.18), 1.065))],
        "rub_strip": (0.560, 0.030),
        "roof_rail": (0.05, fm(-2.20), 6.70, 0.040),
        "cowl": (1.35, 1.42),
        "spoiler": (fm(-2.42), fm(-2.34), 0.012),
        "tail": {
            "pieces": [
                ("glass", (0.56, 0.850, 1.200, 1.190, 0.300, 0.260, 3, 10)),
                ("red", (0.57, 0.845, 1.300, 1.285, 0.060, 0.050, 1, 10)),
                ("red", (0.60, 0.840, 1.110, 1.105, 0.050, 0.044, 1, 8)),
                ("clear", (0.66, 0.80, 1.200, 1.195, 0.034, 0.030, 1, 3)),
            ],
            "hmsl": (-0.16, 0.16, 1.690, 1.710),
        },
        "rear_chrome": [(-0.58, 0.58, 1.180, 1.205)],
        "rear_band": (-0.82, 0.82, 0.380, 0.500),
        "mirror": (1.32, 5.05, (1.075, 1.300, 1.160), (0.23, 0.095, 0.15)),
    }
    s["details"] = everyday_details
    return s


rc.SPECS["minivan"] = minivan


# --- the beater ----------------------------------------------------------------------------------

BEATER_DENT = ((0.88, -0.62, 0.62), 0.20, 0.022)


def beater():
    """An older beater: a 1990s-shape notchback saloon (4.75 m). Upright screens, a short flat
    boot deck, a square glasshouse with thick pillars, flush sealed-beam lamps over a slot
    grille, chrome belt and bumper strips, narrow tyres. Its wear: a dent in the right rear door
    (geometry), one tail lamp cracked and taped (geometry), and the paint's wear (another car's
    door, a primer patch on the wing, chalky clear coat) from Vehicle's beater uniforms."""
    s = {"name": "beater", "length": 4.75}
    s.update({
        "nose": 2.365, "tail": -2.385,
        "front_axle": 1.45, "rear_axle": -1.17, "axle_z": 0.310,
        "wheel_r": 0.310, "wheel_w": 0.195, "wheel_x": 0.745,
        "arch_r": 0.362, "arch_r_rear": 0.362, "arch_in": 0.54,
        "road": -0.165, "belt_probe_z": 0.9,
        "cowl": 0.92, "deck": -1.52, "gh_blend_front": 0.10, "gh_blend_rear": 0.08,
        "crown_at": 0.62, "tension": 0.92, "under_j": 1.0,
        "rings": RINGS, "end_steps": END_STEPS, "mid_step": 0.27,
        "extra_stations": [0.92, -1.52, -1.60],
        "creases": [(4.0, 0.9, -3.0, 3.0), (5.0, 0.55, -2.38, 2.36)],
        "station_creases": [(-1.52, 0.35, 5.5, 7.0)],
        "nose_cap": {"steps": 3, "roll": lambda j: 0.035, "dome": 0.030,
                     "lean": lambda co: 0.015 * ramp(co.z, 0.66, 0.40)},
        "tail_cap": {"steps": 3, "roll": lambda j: 0.035, "dome": 0.025,
                     "lean": lambda co: -0.010 * ramp(co.z, 0.70, 0.40)},
        "sculpt": [
            (3.0, -3.0, 0.0, 3.97, 4.03, 0.10, 0.004),
        ],
        "profile": {
            "top": [(2.365, 0.675), (2.34, 0.700), (2.29, 0.720), (2.15, 0.742), (1.90, 0.770),
                    (1.60, 0.800), (1.30, 0.826), (1.05, 0.845), (0.96, 0.852), (0.92, 0.860),
                    (0.84, 0.920), (0.70, 1.020), (0.55, 1.120), (0.42, 1.205), (0.32, 1.262),
                    (0.22, 1.300), (0.10, 1.322), (-0.10, 1.334), (-0.50, 1.338),
                    (-0.85, 1.330), (-1.00, 1.318), (-1.10, 1.290), (-1.22, 1.215),
                    (-1.34, 1.115), (-1.44, 1.018), (-1.50, 0.968), (-1.52, 0.958),
                    (-1.60, 0.952), (-1.90, 0.950), (-2.20, 0.946), (-2.33, 0.938),
                    (-2.385, 0.915)],
            "rail_z": [(1.05, 0.840), (0.92, 0.856), (0.84, 0.908), (0.70, 0.998),
                       (0.55, 1.090), (0.42, 1.165), (0.30, 1.218), (0.15, 1.252),
                       (-0.10, 1.264), (-0.50, 1.266), (-0.85, 1.258), (-1.00, 1.244),
                       (-1.10, 1.218), (-1.22, 1.150), (-1.34, 1.058), (-1.44, 0.975),
                       (-1.52, 0.948), (-1.60, 0.944), (-2.385, 0.930)],
            "rail_w": [(1.05, 0.790), (0.92, 0.782), (0.60, 0.765), (0.20, 0.745),
                       (-0.30, 0.738), (-0.90, 0.740), (-1.30, 0.752), (-1.52, 0.760),
                       (-2.385, 0.762)],
            "belt_z": [(2.365, 0.665), (2.25, 0.712), (2.00, 0.748), (1.60, 0.780),
                       (1.20, 0.805), (0.92, 0.820), (0.40, 0.832), (-0.40, 0.842),
                       (-1.20, 0.856), (-1.60, 0.866), (-2.10, 0.872), (-2.30, 0.866),
                       (-2.385, 0.850)],
            "belt_in": [(2.365, 0.040), (2.0, 0.046), (0.0, 0.050), (-2.0, 0.052),
                        (-2.385, 0.046)],
            "shoulder_z": [(2.365, 0.590), (2.20, 0.660), (1.90, 0.690), (1.00, 0.705),
                           (0.00, 0.715), (-1.00, 0.725), (-2.00, 0.735), (-2.30, 0.735),
                           (-2.385, 0.720)],
            "width": [(2.365, 0.700), (2.350, 0.775), (2.32, 0.820), (2.26, 0.850),
                      (2.15, 0.866), (1.90, 0.874), (1.45, 0.876), (0.50, 0.872),
                      (-0.50, 0.872), (-1.17, 0.875), (-1.90, 0.872), (-2.15, 0.864),
                      (-2.28, 0.846), (-2.345, 0.810), (-2.385, 0.740)],
            "low_z": [(2.365, 0.40), (0.0, 0.40), (-2.385, 0.42)],
            "low_in": 0.030,
            "sill_z": [(2.365, 0.250), (2.20, 0.240), (1.80, 0.225), (1.45, 0.218),
                       (0.0, 0.210), (-1.17, 0.218), (-1.70, 0.240), (-2.10, 0.265),
                       (-2.385, 0.285)],
            "sill_in": [(2.365, 0.060), (2.0, 0.062), (-2.0, 0.062), (-2.385, 0.060)],
            "floor_z": [(2.365, 0.235), (2.20, 0.200), (1.80, 0.165), (1.45, 0.150),
                        (0.0, 0.145), (-1.17, 0.150), (-1.70, 0.190), (-2.10, 0.235),
                        (-2.385, 0.265)],
            "floor_in": 0.10,
        },
    })
    fa, ra = 1.45, -1.17
    fm = overhangs(1.45, -1.17, 2.365, -2.385, 2.30, -2.30)
    remap(s, fm)
    s["d"] = {
        "belt_gap": 0.026, "top_gap": 0.026,
        "windows": [
            ("windscreen", "screen", 0.20, 0.895, 0.068),
            ("front", "side", -0.135, 0.850),
            ("rear", "side", lambda j: -1.06 + 0.16 * min(max(0.0 if j is None else j - 5.0, 0.0), 1.0),
             -0.225),
            ("backlight", "screen", fm(-1.495), -1.080, 0.065),
        ],
        # Flush rectangular sealed-beam lamps with an amber corner each, a slot grille between.
        "headlamp": {"blade": (0.40, 0.775, 0.600, 0.596, 0.110, 0.104),
                     "lens": (0.41, 0.700, 0.600, 0.598, 0.094, 0.090),
                     "amber": (0.715, 0.770, 0.597, 0.596, 0.094, 0.092)},
        "grille": {"outline": [(-0.38, 0.648), (0.38, 0.648), (0.38, 0.555), (-0.38, 0.555)],
                   "round": 0.015, "cut_from": 2.29, "box": (-0.40, 0.40, 0.555, 0.648),
                   "y": (2.365, 2.31), "nv": 2, "nh": 4, "thick": 0.010,
                   "surround": (-0.395, 0.395, 0.548, 0.655, 0.014)},
        "front_bumper": (0.300, 0.490, 0.030, TRIM),
        "fogs": [],
        "skid": (-0.74, 0.74, 0.425, 0.442), "skid_proud": 0.034,
        "plate": (-0.24, 0.24, 0.650, 0.770),
        "handles": [(0.24, 0.775), (-0.64, 0.785)],
        "handle_mat": TRIM,
        "gaps_side": [
            [(0.905, 0.850), (0.900, 0.60), (0.895, 0.30), (0.890, 0.24)],
            [(-0.180, 0.860), (-0.180, 0.24)],
            [(0.890, 0.24), (-0.180, 0.24)],
            [(fm(2.250), 0.710), (fm(2.10), 0.650), (fm(2.00), 0.620), (fa + 0.362 + 0.03, 0.610)],
        ],
        "rear_door": (-1.000, 0.860, 0.050, 62.0, 10.0),
        "sill_gap": (-0.180, 0.24),
        "gaps_fj": [[(0.96, 5.35), (fm(2.34), 5.35)], [(fm(2.34), 5.35), (fm(2.34), 7.0)],
                    [(fm(-1.56), 5.40), (fm(-2.36), 5.40)], [(fm(-1.56), 5.40), (fm(-1.56), 7.0)]],
        "gaps_rear": [[(0.80, 0.900), (0.79, 0.780), (0.0, 0.775), (-0.79, 0.780), (-0.80, 0.900)]],
        "fuel": (fm(-1.52), 0.770),
        "black_pillars": [(-0.225, -0.135)],
        "belt_trim": (-1.06, 0.88),
        "belt_mat": CHROME,
        "rub_strip": (0.520, 0.024),
        "cowl": (0.89, 0.95),
        "tail": {
            "pieces": [
                # The left lamp whole; the right one is cut into pieces by beater_extra().
                ("glass", lambda side: None if side > 0 else
                 mirror2(rect_grid(0.355, 0.765, 0.735, 0.862, 2, 8))),
                ("red", lambda side: None if side > 0 else
                 mirror2(rect_grid(0.48, 0.755, 0.745, 0.852, 2, 6))),
                ("clear", lambda side: None if side > 0 else
                 mirror2(rect_grid(0.38, 0.46, 0.772, 0.826, 1, 2))),
            ],
        },
        "rear_bumper": (0.300, 0.510, 0.030, TRIM),
        "rear_chrome": [(-0.74, 0.74, 0.445, 0.462)],
        "lips": False,
        "mirror": (0.84, 5.05, (0.925, 0.790, 0.900), (0.18, 0.075, 0.105)),
        "mirror_mat": TRIM,
        "dents": [BEATER_DENT],
        "extra": lambda *a: beater_extra(*a),
    }
    s["details"] = everyday_details
    return s


def beater_extra(s, sec, surf, body, parts, bmt, bmp):
    """The right tail lamp, cracked: the lens in four pieces with a dark crack between them, a
    corner chunk gone (the trim behind shows) and a strip of tape across the crack."""
    pieces = [
        (0.48, 0.585, 0.800, 0.852),
        (0.595, 0.660, 0.812, 0.852),
        (0.48, 0.640, 0.745, 0.790),
        (0.672, 0.755, 0.760, 0.852),
    ]
    for x0, x1, z0, z1 in pieces:
        applied(bmt, surf, "rear", rect_grid(x0, x1, z0, z1, 2, 4), 0.0035, LIGHT_R)
    # The reverse lamp inboard, and the corner chunk that broke out showing the dark housing.
    applied(bmt, surf, "rear", rect_grid(0.38, 0.46, 0.772, 0.826, 1, 2), 0.0045, LIGHT_F)
    applied(bmt, surf, "rear", rect_grid(0.598, 0.665, 0.745, 0.802, 1, 2), 0.0015, TRIM,
            thickness=0.004)
    # The whole lamp's dark bezel behind the pieces (the cracks read through it).
    applied(bmt, surf, "rear", rect_grid(0.355, 0.765, 0.735, 0.862, 2, 8), 0.0018, GLASS,
            thickness=0.004)
    # Silver duct tape over the long crack, at a slant.
    tape = [[(0.578 + 0.032 * c - 0.016 * r, 0.746 + 0.052 * c + 0.004 * r) for c in range(3)]
            for r in range(2)]
    applied(bmt, surf, "rear", tape, 0.0050, CHROME)


rc.SPECS["beater"] = beater


# --- the taxi --------------------------------------------------------------------------------------

def taxi():
    """The sedan with a lit sign on its roof: a lightbox on a low black base, held by two feet
    on the roof. The paint is the TAXI livery (Vehicle), the lettering the sign shader's."""
    s = rc.sedan()
    s["name"] = "taxi"
    base = s["details"]

    def details(s, sec, surf, body, parts):
        base(s, sec, surf, body, parts)
        bm = bmesh.new()
        # Where the roof is: the top of the body over the B-pillar.
        top, n = surf.top_hit(0.0, TAXI_SIGN_Y)
        z = top.z
        w, d, h = 0.300, 0.150, 0.165
        # Feet on the roof, a black base, the lightbox on it (two faces lettered, ends plain).
        for x in (-0.20, 0.20):
            add_box(bm, (0.06, 0.12, 0.03), (x, TAXI_SIGN_Y, z + 0.010), TRIM)
        add_box(bm, (w * 2.1, d * 1.15, 0.028), (0.0, TAXI_SIGN_Y, z + 0.035), TRIM)
        ob = bmesh.new()
        add_box(ob, (w * 2.0, d, h), (0.0, TAXI_SIGN_Y, z + 0.049 + h * 0.5), TAXI_SIGN)
        bmesh.ops.recalc_face_normals(ob, faces=ob.faces)
        sign = new_object("taxi_sign", ob)
        mod = sign.modifiers.new("bev", 'BEVEL')
        mod.width = 0.018
        mod.segments = 3
        apply_modifiers(sign)
        # A thin chrome cap line along the top.
        add_box(bm, (w * 1.9, d * 0.6, 0.006), (0.0, TAXI_SIGN_Y, z + 0.049 + h + 0.001), CHROME)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        parts.append(new_object("taxi_base", bm))
        parts.append(sign)
        log("TAXI SIGN: roof z %.3f, box %.3f x %.3f x %.3f at y %.3f (centre z %.3f)"
            % (z, w * 2.0, d, h, TAXI_SIGN_Y, z + 0.049 + h * 0.5))

    s["details"] = details
    return s


TAXI_SIGN_Y = -0.42
rc.SPECS["taxi"] = taxi


def views(spec):
    v = rc.default_views(spec)
    if spec["name"] == "beater":
        L = spec["length"]
        v.append(("close", (-2.4, -L * 0.5 - 1.8, 1.25), (0.35, -L * 0.5 + 0.3, 0.70), 50))
        v.append(("dent", (3.2, -0.6, 0.95), (0.8, -0.6, 0.60), 50))
    return v


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = [a for a in argv if not a.startswith("--")] or ["hatchback"]
    do_render = "--render" in argv
    detail = "--nodetail" not in argv
    only_views = os.environ.get("VIEWS", "")
    for name in names:
        spec = rc.SPECS[name]()
        ob = rc.build(spec, detail)
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
            vs = views(spec)
            if only_views:
                vs = [v for v in vs if v[0] in only_views.split(",")]
            wh = rc.far_wheels(spec, 24)
            paint = {"taxi": (0.85, 0.52, 0.02), "beater": (0.30, 0.06, 0.05),
                     "suv": (0.02, 0.02, 0.022), "minivan": (0.45, 0.46, 0.48)}.get(name,
                                                                                   rc.PREVIEW_PAINT)
            rc.render_previews(join([ob, wh]), name, vs, paint=paint)


if __name__ == "__main__":
    main()
