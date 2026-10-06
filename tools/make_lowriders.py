#!/usr/bin/env python3
"""Two classic lowrider bodies, built with tools/make_road_cars.py's pipeline (its profile-curve
loft, booleans, raycast parts, the seven material slots and the far twin - read that file's
docstring first):

    tools/road_cars_setup.sh                     # once: Blender 4.2 LTS into build/car_src/
    build/car_src/blender/blender-4.2.23-linux-x64/blender -b --factory-startup \\
        -P tools/make_lowriders.py -- lowrider_hardtop lowrider_coupe [--render] [--nodetail]

(download.blender.org is blocked from the fleet's boxes: `pip install bpy==4.2.0` into a
python3.11 venv gives the same Blender as a module; `bpyenv/bin/python tools/make_lowriders.py --
lowrider_hardtop` runs it. It may segfault on exit AFTER writing the file - harmless.)

Writes assets/models/road_lowrider_hardtop.glb and road_lowrider_coupe.glb; then
`godot --headless --path . --import` (CLAUDE.md, measurement trap 1).

  * lowrider_hardtop: a 1960s full-size two-door hardtop (5.42 m): a long flat bonnet and deck,
    a pillarless glasshouse (door glass and quarter glass meet with no B-pillar), a wrapped
    windscreen, a sloping formal roof, quad round headlamps either side of a full-width chrome
    grille, triple round tail lamps in a chrome tail panel, a chrome spear down each flank,
    rocker mouldings, blade bumpers, bullet mirrors.
  * lowrider_coupe: a 1980s personal-luxury coupe (5.08 m): a long bonnet, an upright chrome
    grille between stacked rectangular headlamps, long doors, a formal roof with a steep
    backlight, a thick C-pillar with an opera window, a padded vinyl half roof (the `trim`
    slot), wrap-round tail lamps, chrome-faced bumpers with black rub strips.

Both are drawn LOW: the sill a hand over the road, small 13" wheel arches the tyres tuck into.
The game draws its own wire wheels (Lowrider.wire_wheel()); the far twin bakes plain ones. The
paint (candy, flake, pinstripes, patterned roof) is car_paint.gdshaderinc's `custom` block,
placed from the numbers this run prints (LOWRIDER lines: shoulder, bonnet, roof, deck).

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
import make_more_cars as mc  # noqa: E402

from make_road_cars import (  # noqa: E402
    PAINT, GLASS, TRIM, CHROME, TYRE, LIGHT_F, LIGHT_R, log, new_object, boolean,
    add_box, tidy, grid_solid, applied, fj_applied, hits_2d, rect_grid, mirror2,
    blade_grid, extrude_cutter, rounded_outline, eggcrate, surface_path, fj_path, cut_grooves,
    sweep, wrap_band, circle_path, cut_windows, build_glass, flush_handle, mirror, join,
)
from make_more_cars import round_grid, lamp_pocket, chrome_bars, windows_from  # noqa: E402

RINGS = mc.RINGS
END_STEPS = mc.END_STEPS


def lowrider_details(s, sec, surf, body, parts):
    """everyday_details() for two-door classics: no rear door, round or stacked lamps, chrome
    everywhere a 1960s / 1980s car had it, the spear and the rocker moulding."""
    d = s["d"]
    fa, ra, R = s["front_axle"], s["rear_axle"], s["arch_r"]
    wins = windows_from(s, sec)
    cut_windows(body, surf, wins)

    bmc = bmesh.new()
    bmp = bmesh.new()
    hl = d["headlamp"]
    for side in (1.0, -1.0):
        if hl.get("round"):
            for cx, rr in hl["round"]:
                g = round_grid(cx, hl["z"], rr, rr, 3, 16)
                lamp_pocket(bmc, bmp, surf, g if side > 0 else mirror2(g))
                # The chrome bezel ring, then the lens a little inside it.
                ring = [[(cx + rr * (1.0 + 0.16 * t) * math.cos(2 * math.pi * k / 20),
                          hl["z"] + rr * (1.0 + 0.16 * t) * math.sin(2 * math.pi * k / 20))
                         for k in range(21)] for t in (0.0, 1.0)]
                applied(bmp, surf, "front", ring if side > 0 else mirror2(ring), 0.004, CHROME,
                        thickness=0.010)
                lens = round_grid(cx, hl["z"], rr * 0.92, rr * 0.92, 3, 16)
                applied(bmp, surf, "front", lens if side > 0 else mirror2(lens), -0.006, LIGHT_F)
        for x0, x1, z0, z1 in hl.get("rects", []):
            g = rect_grid(x0, x1, z0, z1, 2, 6)
            lamp_pocket(bmc, bmp, surf, g if side > 0 else mirror2(g))
            lens = rect_grid(x0 + 0.008, x1 - 0.008, z0 + 0.008, z1 - 0.008, 2, 6)
            applied(bmp, surf, "front", lens if side > 0 else mirror2(lens), -0.006, LIGHT_F)
        for x0, x1, z0, z1 in hl.get("bezels", []):
            w = 0.012
            for g in (rect_grid(x0, x1, z1 - w, z1, 1, 8), rect_grid(x0, x1, z0, z0 + w, 1, 8),
                      rect_grid(x0, x0 + w, z0, z1, 3, 1), rect_grid(x1 - w, x1, z0, z1, 3, 1)):
                applied(bmp, surf, "front", g if side > 0 else mirror2(g), 0.006, CHROME,
                        thickness=0.012)
        for x0, x1, z0, z1 in hl.get("ambers", []):
            g = rect_grid(x0, x1, z0, z1, 1, 4)
            applied(bmp, surf, "front", g if side > 0 else mirror2(g), 0.004, LIGHT_R,
                    thickness=0.006)
    # Grille mouth: cut, then chrome bars across it (or a vertical-bar chrome grille).
    gr = d["grille"]
    boolean(body, extrude_cutter(rounded_outline(gr["outline"], gr.get("round", 0.02)), "y",
                                 gr["cut_from"], s["nose"] + 1.0))
    x0, x1, z0, z1 = gr["box"]
    eggcrate(bmp, x0, x1, z0, z1, gr["y"][0], gr["y"][1], gr.get("nv", 2), gr.get("nh", 1),
             thick=0.010, mat=TRIM)
    if gr.get("bars"):
        chrome_bars(bmp, x0, x1, z0, z1, gr["y"][0] + 0.004, gr["bars"], thick=gr.get("bar_t", 0.012))
    if gr.get("vbars"):
        n = gr["vbars"]
        for k in range(n):
            x = x0 + (x1 - x0) * (k + 0.5) / n
            add_box(bmp, (0.010, 0.03, z1 - z0), (x, gr["y"][0] - 0.010, (z0 + z1) * 0.5), CHROME)
    if "surround" in gr:
        sx0, sx1, sz0, sz1, w = gr["surround"]
        for g in (rect_grid(sx0, sx1, sz1 - w, sz1, 1, 18), rect_grid(sx0, sx1, sz0, sz0 + w, 1, 18),
                  rect_grid(sx0, sx0 + w, sz0, sz1, 4, 1), rect_grid(sx1 - w, sx1, sz0, sz1, 4, 1)):
            applied(bmp, surf, "front", g, 0.008, CHROME, thickness=0.014)
    for x0, x1, z0, z1 in d.get("front_chrome", []):
        applied(bmp, surf, "front", rect_grid(x0, x1, z0, z1, 1, 16), 0.006, CHROME, thickness=0.010)
    if "front_bumper" in d:
        z0, z1, proud, mat = d["front_bumper"]
        wrap_band(bmp, surf, 1.0, z0, z1, proud, mat, reach=d.get("bumper_reach", 0.34),
                  corner_r=0.16, thickness=0.06)
    if "front_rub" in d:
        z0, z1, proud = d["front_rub"]
        wrap_band(bmp, surf, 1.0, z0, z1, proud, TRIM, reach=d.get("bumper_reach", 0.34) - 0.02,
                  corner_r=0.16, thickness=0.03)
    plate = rect_grid(*d["plate"], 2, 8)
    res = hits_2d(surf, "rear", plate, 1.0)
    if res:
        pts, nrm = res
        grid_solid(bmc, [p + n * 0.02 for p, n in zip(pts, nrm)],
                   [p - n * 0.010 for p, n in zip(pts, nrm)], 3, 9, TRIM)
    for side in (1.0, -1.0):
        for y, z in d["handles"]:
            flush_handle(bmc, bmp, surf, y, z, side, mat=CHROME, length=d.get("handle_len", 0.13))
    tidy(bmc)
    boolean(body, new_object("cut_pockets", bmc))

    # Panel gaps: the long door, the bonnet and the deck lid.
    paths = []
    for side in (1.0, -1.0):
        for line in d["gaps_side"]:
            paths.append(surface_path(surf, "side", line, side))
        for line in d.get("gaps_fj", []):
            paths.append(fj_path(surf, line, side))
    for line in d.get("gaps_rear", []):
        paths.append(surface_path(surf, "rear", line, 1.0))
    flap = circle_path(*d["fuel"], 0.06, 5.0, 352.0, 20)
    paths.append(surface_path(surf, "side", flap, -1.0, step=0.015))
    cut_grooves(body, paths)

    parts.append(build_glass(surf, wins, 0.007))
    bmt = bmesh.new()
    for side in (1.0, -1.0):
        for f0, f1 in d.get("black_pillars", []):
            fj_applied(bmt, surf, f0, f1, lambda f: sec.j_along(f, 5.0, 0.018),
                       lambda f: sec.j_along(f, 6.0, 0.016, -1.0), 6, 3, 0.002, GLASS, side,
                       thickness=0.006)
        for f0, f1 in d.get("dividers", []):
            # A pillarless hardtop's glass meets with only a thin chrome edge between.
            fj_applied(bmt, surf, f0, f1, lambda f: sec.j_along(f, 5.0, 0.010),
                       lambda f: sec.j_along(f, 6.0, 0.010, -1.0), 6, 2, 0.004, CHROME, side,
                       thickness=0.006)
        b0, b1 = d["belt_trim"]
        fj_applied(bmt, surf, lambda j: b0, lambda j: b1, lambda f: sec.j_along(f, 5.0, 0.004),
                   lambda f: sec.j_along(f, 5.0, 0.019), 1, 60, 0.003, CHROME, side,
                   thickness=0.006)
        # The drip rail / window reveal over the glass, chrome.
        if "reveal" in d:
            r0, r1 = d["reveal"]
            fj_applied(bmt, surf, r0, r1, lambda f: sec.j_along(f, 6.0, 0.004, -1.0),
                       lambda f: sec.j_along(f, 6.0, 0.016), 1, 60, 0.003, CHROME, side,
                       thickness=0.006)
        if "rocker" in d:
            z0, z1 = d["rocker"]
            strip = surface_path(surf, "side", [(fa - R - 0.05, (z0 + z1) * 0.5),
                                                (ra + R + 0.05, (z0 + z1) * 0.5)], side, step=0.06)
            if len(strip) > 2:
                h = (z1 - z0) * 0.5
                prof = [(-h, -0.003), (-h, 0.006), (-h * 0.4, 0.010), (h * 0.6, 0.009), (h, 0.004),
                        (h, -0.003)]
                sweep(bmt, [p for p, _n in strip], prof, CHROME, normals=[n for _p, n in strip])
        for z, h, f0, f1 in d.get("spears", []):
            strip = surface_path(surf, "side", [(f0, z), (f1, z)], side, step=0.05)
            if len(strip) > 2:
                prof = [(-h, -0.003), (-h * 0.7, 0.007), (0.0, 0.010), (h * 0.7, 0.007), (h, -0.003)]
                sweep(bmt, [p for p, _n in strip], prof, CHROME, normals=[n for _p, n in strip])
        if "rub_strip" in d:
            z, h = d["rub_strip"]
            strip = surface_path(surf, "side", [(fa - R - 0.04, z), (ra + R + 0.04, z)], side,
                                 step=0.06)
            if len(strip) > 2:
                prof = [(-h, -0.004), (-h * 0.8, 0.008), (h * 0.8, 0.008), (h, -0.004)]
                sweep(bmt, [p for p, _n in strip], prof, TRIM, normals=[n for _p, n in strip])
        for f0, f1, j0, j1 in d.get("vinyl", []):
            # The padded half roof: a vinyl skin a few mm proud over the roof's rear half and the
            # C-pillars, its edge rolled under a chrome strip.
            fj_applied(bmt, surf, f0, f1, j0, j1, 10, 8, 0.0045, TRIM, side, thickness=0.006)
        for (cy, cz, w, h) in d.get("side_markers", []):
            g = rect_grid(cy - w, cy + w, cz - h, cz + h, 1, 2)
            applied(bmt, surf, "side", g, 0.003, LIGHT_R, side, thickness=0.004)
        for (cy, cz, w, h) in d.get("front_markers", []):
            g = rect_grid(cy - w, cy + w, cz - h, cz + h, 1, 2)
            applied(bmt, surf, "side", g, 0.003, LIGHT_F, side, thickness=0.004)
        for (cy, cz, r) in d.get("opera_lamps", []):
            g = round_grid(cy, cz, r * 0.5, r, 2, 10)
            applied(bmt, surf, "side", g, 0.004, LIGHT_F, side, thickness=0.006)
    if "cowl" in d:
        c0, c1 = d["cowl"]
        fj_applied(bmt, surf, c0, c1, lambda f: sec.j_along(f, 5.0, 0.03), 7.0, 12, 3, 0.003,
                   TRIM, 1.0, thickness=0.006, centre=True)
    for f0, f1, jw in d.get("vinyl_top", []):
        fj_applied(bmt, surf, f0, f1, jw, 7.0, 10, 6, 0.0045, TRIM, 1.0, thickness=0.006,
                   centre=True)
    # Tail lamps and the chrome tail panel.
    tl = d["tail"]
    for side in (1.0, -1.0):
        for kind, args in tl["pieces"]:
            mat = {"glass": GLASS, "red": LIGHT_R, "clear": LIGHT_F, "trim": TRIM,
                   "chrome": CHROME}[kind]
            g = args(side) if callable(args) else rect_grid(*args[:4], args[4], args[5])
            if g is None:
                continue
            if not callable(args) and side < 0:
                g = mirror2(g)
            proud = {"glass": 0.002, "red": 0.0045, "clear": 0.0055, "trim": 0.004,
                     "chrome": 0.003}[kind]
            applied(bmt, surf, "rear", g, proud, mat,
                    thickness=0.006 if kind in ("glass", "trim", "chrome") else 0.0)
    if "rear_bumper" in d:
        z0, z1, proud, mat = d["rear_bumper"]
        wrap_band(bmt, surf, -1.0, z0, z1, proud, mat, reach=d.get("bumper_reach", 0.34) - 0.06,
                  corner_r=0.14, thickness=0.06)
    if "rear_rub" in d:
        z0, z1, proud = d["rear_rub"]
        wrap_band(bmt, surf, -1.0, z0, z1, proud, TRIM, reach=d.get("bumper_reach", 0.34) - 0.08,
                  corner_r=0.14, thickness=0.03)
    for x0, x1, z0, z1 in d.get("rear_chrome", []):
        applied(bmt, surf, "rear", rect_grid(x0, x1, z0, z1, 1, 16), 0.004, CHROME, thickness=0.008)
    bmesh.ops.remove_doubles(bmt, verts=bmt.verts, dist=1e-6)
    parts.append(new_object("trims", bmt))
    bmesh.ops.remove_doubles(bmp, verts=bmp.verts, dist=1e-6)
    parts.append(new_object("inserts", bmp))
    for side in (1.0, -1.0):
        mf, mj, head, size = d["mirror"]
        mirror(parts, surf, s, side, mf, mj, head, size, head_mat=CHROME)
    # The numbers the paint shader's custom block is placed from (Vehicle / Lowrider): the mesh
    # is exported Y-up, so mesh x = x, mesh y = z, mesh z = -f.
    log("LOWRIDER %s: shoulder z %.3f, belt z %.3f, bonnet f %.3f..%.3f, roof f %.3f..%.3f, "
        "deck f %.3f..%.3f, half width %.3f"
        % (s["name"], sec.c["shoulder_z"](0.0), sec.c["belt_z"](0.0), s["cowl"], s["nose"],
           d["roof_f"][0], d["roof_f"][1], s["tail"], s["deck"], sec.c["width"](0.0)))


# --- the 1960s hardtop ---------------------------------------------------------------------------

def lowrider_hardtop():
    s = {"name": "lowrider_hardtop", "length": 5.42}
    fa, ra = 1.40, -1.62
    s.update({
        "nose": 2.66, "tail": -2.76,
        "front_axle": fa, "rear_axle": ra, "axle_z": 0.300,
        "wheel_r": 0.292, "wheel_w": 0.160, "wheel_x": 0.790,
        "arch_r": 0.372, "arch_r_rear": 0.372, "arch_in": 0.62,
        "road": -0.120, "belt_probe_z": 0.84, "height": 1.30,
        "cowl": 0.62, "deck": -1.86, "gh_blend_front": 0.10, "gh_blend_rear": 0.08,
        "crown_at": 0.55, "tension": 0.90, "under_j": 1.0,
        "rings": RINGS, "end_steps": END_STEPS, "mid_step": 0.27,
        "extra_stations": [0.62, -1.86, -1.94, 2.60, -2.70],
        "creases": [(4.0, 1.0, -3.0, 3.0), (5.0, 0.7, -2.8, 2.7)],
        "station_creases": [(-1.86, 0.35, 5.5, 7.0), (2.60, 0.4, 4.0, 7.0), (-2.70, 0.4, 4.0, 7.0)],
        "nose_cap": {"steps": 3, "roll": lambda j: 0.028, "dome": 0.018,
                     "lean": lambda co: 0.010 * rc.ramp(co.z, 0.70, 0.40)},
        "tail_cap": {"steps": 3, "roll": lambda j: 0.026, "dome": 0.016,
                     "lean": lambda co: -0.006 * rc.ramp(co.z, 0.76, 0.40)},
        "sculpt": [],
        "profile": {
            "top": [(2.66, 0.735), (2.645, 0.775), (2.62, 0.800), (2.52, 0.818), (2.20, 0.833),
                    (1.80, 0.846), (1.30, 0.858), (0.90, 0.866), (0.70, 0.872), (0.62, 0.878),
                    (0.55, 0.925), (0.42, 1.010), (0.28, 1.095), (0.14, 1.160), (0.00, 1.205),
                    (-0.20, 1.238), (-0.50, 1.255), (-0.85, 1.252), (-1.05, 1.236),
                    (-1.20, 1.205), (-1.35, 1.140), (-1.50, 1.060), (-1.64, 0.985),
                    (-1.76, 0.928), (-1.86, 0.898), (-1.94, 0.892), (-2.30, 0.888),
                    (-2.62, 0.880), (-2.71, 0.862), (-2.76, 0.820)],
            "rail_z": [(0.90, 0.856), (0.62, 0.874), (0.55, 0.912), (0.42, 0.988), (0.28, 1.060),
                       (0.14, 1.118), (0.00, 1.158), (-0.20, 1.186), (-0.50, 1.198),
                       (-0.85, 1.194), (-1.05, 1.180), (-1.20, 1.152), (-1.35, 1.092),
                       (-1.50, 1.018), (-1.64, 0.952), (-1.76, 0.905), (-1.86, 0.882),
                       (-1.94, 0.878), (-2.76, 0.870)],
            "rail_w": [(0.90, 0.950), (0.62, 0.945), (0.42, 0.905), (0.20, 0.858), (0.00, 0.832),
                       (-0.60, 0.815), (-1.10, 0.818), (-1.40, 0.850), (-1.70, 0.905),
                       (-1.86, 0.930), (-2.76, 0.935)],
            "belt_z": [(2.66, 0.735), (2.62, 0.790), (2.50, 0.808), (2.00, 0.822), (1.20, 0.836),
                       (0.62, 0.846), (0.00, 0.852), (-1.00, 0.858), (-1.86, 0.864),
                       (-2.40, 0.866), (-2.66, 0.858), (-2.76, 0.815)],
            "belt_in": [(2.66, 0.030), (2.4, 0.034), (0.0, 0.040), (-2.4, 0.036), (-2.76, 0.030)],
            "shoulder_z": [(2.66, 0.660), (2.60, 0.700), (2.40, 0.712), (1.00, 0.716),
                           (0.00, 0.718), (-1.00, 0.720), (-2.40, 0.724), (-2.66, 0.718),
                           (-2.76, 0.690)],
            "width": [(2.66, 0.840), (2.65, 0.915), (2.62, 0.960), (2.55, 0.990), (2.40, 1.002),
                      (2.00, 1.006), (1.00, 1.006), (0.00, 1.004), (-1.00, 1.006),
                      (-2.20, 1.006), (-2.55, 0.998), (-2.68, 0.975), (-2.73, 0.940),
                      (-2.76, 0.880)],
            "low_z": [(2.66, 0.400), (0.0, 0.390), (-2.76, 0.410)],
            "low_in": 0.026,
            "sill_z": [(2.66, 0.240), (2.40, 0.215), (1.80, 0.185), (1.40, 0.175), (0.0, 0.165),
                       (-1.62, 0.172), (-2.20, 0.192), (-2.55, 0.215), (-2.76, 0.245)],
            "sill_in": [(2.66, 0.050), (0.0, 0.055), (-2.76, 0.050)],
            "floor_z": [(2.66, 0.225), (2.40, 0.195), (1.80, 0.150), (1.40, 0.140), (0.0, 0.130),
                        (-1.62, 0.138), (-2.20, 0.165), (-2.55, 0.195), (-2.76, 0.230)],
            "floor_in": 0.10,
        },
    })
    s["d"] = {
        "belt_gap": 0.024, "top_gap": 0.018,
        "windows": [
            ("windscreen", "screen", 0.005, 0.598, 0.055),
            ("front", "side", -0.535, 0.585),
            ("rear", "side", lambda j: -1.30 + 0.20 * min(max(0.0 if j is None else j - 5.0, 0.0), 1.0),
             -0.555),
            ("backlight", "screen", -1.835, -1.115, 0.060),
        ],
        "roof_f": (-1.15, 0.0),
        # Quad round sealed beams either side of a full-width chrome grille.
        "headlamp": {"round": [(0.555, 0.082), (0.790, 0.082)], "z": 0.618,
                     "bezels": [(0.455, 0.890, 0.520, 0.714)]},
        "grille": {"outline": [(-0.44, 0.700), (0.44, 0.700), (0.44, 0.470), (-0.44, 0.470)],
                   "round": 0.012, "cut_from": 2.60, "box": (-0.45, 0.45, 0.470, 0.700),
                   "y": (2.66, 2.62), "nv": 12, "nh": 1, "bars": 6, "bar_t": 0.010,
                   "surround": (-0.92, 0.92, 0.462, 0.715, 0.016)},
        "front_chrome": [(-0.93, 0.93, 0.708, 0.722)],
        "front_bumper": (0.305, 0.430, 0.032, CHROME),
        "bumper_reach": 0.30,
        "plate": (-0.170, 0.170, 0.470, 0.590),
        "handles": [(-0.50, 0.808)],
        "handle_len": 0.11,
        "gaps_side": [
            [(0.640, 0.852), (0.636, 0.60), (0.630, 0.30), (0.625, 0.185)],
            [(-0.585, 0.858), (-0.585, 0.180)],
            [(0.625, 0.185), (-0.585, 0.180)],
        ],
        "gaps_fj": [[(0.66, 5.35), (2.60, 5.35)], [(2.60, 5.35), (2.60, 7.0)],
                    [(-1.92, 5.40), (-2.70, 5.40)], [(-1.92, 5.40), (-1.92, 7.0)]],
        "gaps_rear": [[(0.86, 0.835), (0.855, 0.812), (0.0, 0.808), (-0.855, 0.812),
                       (-0.86, 0.835)]],
        "fuel": (-2.35, 0.770),
        "belt_trim": (-1.84, 0.60),
        "reveal": (-1.12, 0.56),
        "rocker": (0.205, 0.255),
        # The spear: a chrome strip down the whole flank on the feature line.
        "spears": [(0.640, 0.010, -2.62, 2.50)],
        "front_markers": [(2.36, 0.560, 0.055, 0.016)],
        "side_markers": [(-2.52, 0.560, 0.045, 0.016)],
        "cowl": (0.58, 0.66),
        "tail": {
            "pieces": [
                # The tail panel: brushed chrome from lamp to lamp, then three round lamps a side.
                ("chrome", (0.0, 0.95, 0.620, 0.800, 1, 16)),
                ("trim", (0.0, 0.95, 0.612, 0.620, 1, 16)),
            ] + [(k, (lambda side, cx=cx, k=k, r=r: (lambda g: g if side > 0 else mirror2(g))(
                round_grid(cx, 0.710, r, r, 3, 16)))) for cx in (0.47, 0.66, 0.85)
                 for k, r in (("glass", 0.074), ("red", 0.064))] + [
                ("clear", (lambda side: (lambda g: g if side > 0 else mirror2(g))(
                    round_grid(0.47, 0.710, 0.024, 0.024, 2, 12)))),
            ],
        },
        "rear_bumper": (0.315, 0.440, 0.032, CHROME),
        "rear_chrome": [(-0.95, 0.95, 0.802, 0.812)],
        "dividers": [(-0.565, -0.525)],
        "mirror": (0.42, 5.05, (1.035, 0.40, 0.900), (0.10, 0.075, 0.065)),
    }
    s["details"] = lowrider_details
    return s


rc.SPECS["lowrider_hardtop"] = lowrider_hardtop


# --- the 1980s coupe -----------------------------------------------------------------------------

def lowrider_coupe():
    s = {"name": "lowrider_coupe", "length": 5.08}
    fa, ra = 1.30, -1.42
    s.update({
        "nose": 2.50, "tail": -2.58,
        "front_axle": fa, "rear_axle": ra, "axle_z": 0.300,
        "wheel_r": 0.292, "wheel_w": 0.160, "wheel_x": 0.740,
        "arch_r": 0.365, "arch_r_rear": 0.365, "arch_in": 0.58,
        "road": -0.120, "belt_probe_z": 0.84, "height": 1.30,
        "cowl": 0.52, "deck": -1.72, "gh_blend_front": 0.10, "gh_blend_rear": 0.06,
        "crown_at": 0.55, "tension": 0.88, "under_j": 1.0,
        "rings": RINGS, "end_steps": END_STEPS, "mid_step": 0.27,
        "extra_stations": [0.52, -1.72, -1.78, 2.44, -2.52, -1.34, -1.40],
        "creases": [(4.0, 1.0, -3.0, 3.0), (5.0, 0.8, -2.6, 2.5)],
        "station_creases": [(-1.72, 0.45, 5.5, 7.0), (2.44, 0.5, 4.0, 7.0), (-2.52, 0.5, 4.0, 7.0),
                            (-1.34, 0.30, 6.0, 7.0)],
        "nose_cap": {"steps": 3, "roll": lambda j: 0.022, "dome": 0.012,
                     "lean": lambda co: 0.004 * rc.ramp(co.z, 0.78, 0.40)},
        "tail_cap": {"steps": 3, "roll": lambda j: 0.022, "dome": 0.012,
                     "lean": lambda co: -0.004 * rc.ramp(co.z, 0.78, 0.40)},
        "sculpt": [],
        "profile": {
            "top": [(2.50, 0.780), (2.49, 0.810), (2.46, 0.826), (2.30, 0.836), (1.80, 0.848),
                    (1.20, 0.860), (0.70, 0.870), (0.52, 0.876), (0.44, 0.925), (0.30, 1.012),
                    (0.16, 1.092), (0.02, 1.160), (-0.12, 1.212), (-0.30, 1.244), (-0.60, 1.262),
                    (-1.00, 1.262), (-1.25, 1.256), (-1.34, 1.248), (-1.40, 1.222),
                    (-1.50, 1.150), (-1.60, 1.060), (-1.68, 0.985), (-1.72, 0.948),
                    (-1.78, 0.938), (-2.20, 0.932), (-2.46, 0.924), (-2.54, 0.900),
                    (-2.58, 0.860)],
            "rail_z": [(0.70, 0.858), (0.52, 0.868), (0.44, 0.912), (0.30, 0.990), (0.16, 1.062),
                       (0.02, 1.122), (-0.12, 1.166), (-0.30, 1.194), (-0.60, 1.206),
                       (-1.00, 1.206), (-1.25, 1.200), (-1.34, 1.192), (-1.40, 1.170),
                       (-1.50, 1.100), (-1.60, 1.020), (-1.68, 0.958), (-1.72, 0.930),
                       (-1.78, 0.922), (-2.58, 0.912)],
            "rail_w": [(0.70, 0.835), (0.52, 0.830), (0.30, 0.790), (0.00, 0.760), (-0.60, 0.745),
                       (-1.20, 0.750), (-1.40, 0.765), (-1.60, 0.800), (-1.72, 0.820),
                       (-2.58, 0.825)],
            "belt_z": [(2.50, 0.780), (2.46, 0.818), (2.30, 0.826), (1.60, 0.836), (0.52, 0.850),
                       (0.00, 0.858), (-1.00, 0.866), (-1.72, 0.880), (-2.30, 0.890),
                       (-2.52, 0.886), (-2.58, 0.858)],
            "belt_in": [(2.50, 0.026), (2.3, 0.030), (0.0, 0.036), (-2.3, 0.032), (-2.58, 0.028)],
            "shoulder_z": [(2.50, 0.700), (2.44, 0.735), (2.20, 0.742), (0.00, 0.748),
                           (-2.20, 0.760), (-2.50, 0.758), (-2.58, 0.730)],
            "width": [(2.50, 0.800), (2.49, 0.860), (2.46, 0.895), (2.38, 0.912), (2.10, 0.918),
                      (1.00, 0.920), (0.00, 0.920), (-1.00, 0.920), (-2.20, 0.918),
                      (-2.44, 0.912), (-2.53, 0.890), (-2.58, 0.840)],
            "low_z": [(2.50, 0.410), (0.0, 0.400), (-2.58, 0.420)],
            "low_in": 0.024,
            "sill_z": [(2.50, 0.250), (2.20, 0.215), (1.70, 0.188), (1.30, 0.178), (0.0, 0.168),
                       (-1.42, 0.175), (-2.00, 0.195), (-2.36, 0.222), (-2.58, 0.250)],
            "sill_in": [(2.50, 0.045), (0.0, 0.050), (-2.58, 0.045)],
            "floor_z": [(2.50, 0.235), (2.20, 0.195), (1.70, 0.155), (1.30, 0.142), (0.0, 0.132),
                        (-1.42, 0.140), (-2.00, 0.168), (-2.36, 0.200), (-2.58, 0.235)],
            "floor_in": 0.10,
        },
    })
    s["d"] = {
        "belt_gap": 0.024, "top_gap": 0.024,
        "windows": [
            ("windscreen", "screen", -0.090, 0.505, 0.060),
            ("front", "side", -0.700, 0.495),
            # The opera window in the broad C-pillar.
            ("rear", "side", lambda j: -1.02 + 0.10 * min(max(0.0 if j is None else j - 5.0, 0.0), 1.0),
             -0.780),
            ("backlight", "screen", -1.700, -1.360, 0.075),
        ],
        "roof_f": (-1.30, -0.10),
        # Stacked rectangular sealed beams (two a side), amber parking lamps under them.
        "headlamp": {"rects": [(0.390, 0.585, 0.665, 0.765), (0.390, 0.585, 0.548, 0.648)],
                     "bezels": [(0.375, 0.600, 0.535, 0.778)],
                     "ambers": [(0.640, 0.870, 0.548, 0.590)]},
        "grille": {"outline": [(-0.33, 0.778), (0.33, 0.778), (0.33, 0.470), (-0.33, 0.470)],
                   "round": 0.010, "cut_from": 2.44, "box": (-0.34, 0.34, 0.470, 0.778),
                   "y": (2.50, 2.46), "nv": 2, "nh": 3, "vbars": 22,
                   "surround": (-0.355, 0.355, 0.458, 0.792, 0.020)},
        "front_chrome": [(-0.90, 0.90, 0.790, 0.800)],
        "front_bumper": (0.300, 0.455, 0.055, CHROME),
        "front_rub": (0.345, 0.385, 0.062),
        "bumper_reach": 0.36,
        "plate": (-0.165, 0.165, 0.470, 0.585),
        "handles": [(-0.62, 0.800)],
        "handle_len": 0.14,
        "gaps_side": [
            [(0.548, 0.848), (0.545, 0.60), (0.540, 0.30), (0.535, 0.192)],
            [(-0.735, 0.866), (-0.735, 0.180)],
            [(0.535, 0.192), (-0.735, 0.180)],
        ],
        "gaps_fj": [[(0.56, 5.35), (2.44, 5.35)], [(2.44, 5.35), (2.44, 7.0)],
                    [(-1.78, 5.40), (-2.52, 5.40)], [(-1.78, 5.40), (-1.78, 7.0)]],
        "gaps_rear": [[(0.82, 0.880), (0.815, 0.860), (0.0, 0.856), (-0.815, 0.860),
                       (-0.82, 0.880)]],
        "fuel": (-1.95, 0.760),
        "belt_trim": (-1.70, 0.50),
        "reveal": (-1.00, 0.46),
        "rocker": (0.208, 0.262),
        "rub_strip": (0.560, 0.020),
        "spears": [(0.752, 0.006, -2.50, 2.40)],
        "front_markers": [(2.30, 0.570, 0.060, 0.018)],
        "side_markers": [(-2.40, 0.585, 0.060, 0.018)],
        "opera_lamps": [(-1.17, 0.960, 0.030)],
        # The padded half roof over the roof's rear and the C-pillars (the trim slot).
        "vinyl": [(-1.38, -0.80, lambda f: sec_j6(f), 7.0)],
        "cowl": (0.48, 0.56),
        "tail": {
            "pieces": [
                # Wide wrap-round lamps across the tail panel, a chrome bar through them and a
                # reversing lamp inboard, the plate between them.
                ("glass", (0.20, 0.915, 0.600, 0.800, 2, 12)),
                ("red", (0.33, 0.905, 0.612, 0.788, 2, 10)),
                ("clear", (0.21, 0.32, 0.630, 0.770, 2, 2)),
                ("chrome", (0.20, 0.915, 0.694, 0.706, 1, 12)),
            ],
        },
        "rear_bumper": (0.310, 0.465, 0.055, CHROME),
        "rear_rub": (0.355, 0.395, 0.062),
        "rear_chrome": [(-0.20, 0.20, 0.794, 0.806)],
        "mirror": (0.36, 5.05, (0.955, 0.34, 0.905), (0.12, 0.070, 0.075)),
    }
    s["details"] = lowrider_details
    return s


def sec_j6(f):
    """The vinyl roof's lower edge: just under the rail line (set in main from the section)."""
    return _SEC[0].j_along(f, 6.0, 0.03, -1.0) if _SEC else 5.9


_SEC = []


def coupe_details(s, sec, surf, body, parts):
    _SEC.clear()
    _SEC.append(sec)
    lowrider_details(s, sec, surf, body, parts)


def lowrider_coupe_spec():
    s = lowrider_coupe()
    s["details"] = coupe_details
    return s


rc.SPECS["lowrider_coupe"] = lowrider_coupe_spec


def views(spec):
    v = rc.default_views(spec)
    L = spec["length"]
    v.append(("close", (2.6, L * 0.5 + 1.6, 1.05), (0.3, L * 0.5 - 0.2, 0.60), 45))
    v.append(("tail", (-2.4, -L * 0.5 - 1.8, 1.10), (0.3, -L * 0.5 + 0.2, 0.62), 45))
    return v


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = [a for a in argv if not a.startswith("--")] or ["lowrider_hardtop"]
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
            paint = {"lowrider_hardtop": (0.30, 0.02, 0.08), "lowrider_coupe": (0.03, 0.10, 0.28)}[name]
            rc.render_previews(join([ob, wh]), name, vs, paint=paint)


if __name__ == "__main__":
    main()
