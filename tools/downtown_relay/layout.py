#!/usr/bin/env python3
"""Lay the fitted grid onto the game and check every tower against its block."""
import json, math, os
from fit_grid import C, en, uv

B = 37.86
ANCHOR = (2800.0, 102.7)   # Pershing Square's centre in world XZ (5th St at z = 0)
SIDEWALK = 4.0

AVENUES = [  # name, u, width
    ("PARK VIEW ST", -2700.0, 16.0), ("ALVARADO ST", -2313.0, 22.0),
    ("GEORGIA ST", -835.0, 16.0), ("FIGUEROA ST", -566.5, 24.0), ("FLOWER ST", -440.6, 20.0),
    ("HOPE ST", -310.9, 18.0), ("GRAND AVE", -189.2, 22.0), ("OLIVE ST", -60.4, 18.0),
    ("HILL ST", 64.4, 20.0), ("BROADWAY", 191.0, 20.0), ("SPRING ST", 313.0, 18.0),
    ("MAIN ST", 435.7, 18.0), ("ALAMEDA ST", 590.0, 24.0),
]
STREETS = [  # name, v, width
    ("ARCADIA ST", -1377.5, 16.0), ("TEMPLE ST", -1193.2, 20.0), ("1ST ST", -879.5, 20.0),
    ("2ND ST", -715.5, 18.0), ("3RD ST", -506.1, 20.0), ("4TH ST", -305.2, 18.0),
    ("5TH ST", -102.7, 20.0), ("6TH ST", 97.5, 20.0), ("WILSHIRE BLVD", 210.0, 24.0),
    ("7TH ST", 301.3, 20.0), ("8TH ST", 501.7, 18.0), ("9TH ST", 704.2, 18.0),
    ("OLYMPIC BLVD", 903.1, 24.0), ("11TH ST", 1105.7, 18.0), ("12TH ST", 1307.1, 16.0),
    ("PICO BLVD", 1459.9, 22.0), ("VENICE BLVD", 1897.0, 22.0),
]

TOWERS = {  # id: (point keys, plan x, plan z)
    "dt_sail_tower": (["wilshire_grand"], 70.0, 84.0),
    "dt_five_drums": (["bonaventure"], 49.0, 57.0),
    "dt_black_twins": (["cnp_515", "cnp_555"], 42.0, 91.2),
    "dt_pyramid_crown": (["fig_601"], 42.0, 42.0),
    "dt_spire_pyramid": (["ey_725"], 36.0, 36.0),
    "dt_curved_white": (["t777"], 48.0, 43.0),
    "dt_bronze_slab": (["bofa_333hope"], 38.0, 52.0),
    "dt_dark_glass": (["citi_444"], 38.0, 42.0),
    "dt_granite_slab": (["aon_707"], 38.2, 58.2),
    "dt_park_a": (["metropolis"], 38.0, 44.0),
    "dt_park_c": (["aven"], 29.2, 29.2),
    "dt_faceted_twins": (["wf_333grand", "wf_355grand"], 38.0, 78.0),
    "dt_crown_cylinder": (["usbank"], 42.0, 42.0),
    "dt_park_b": (["circa"], 31.2, 33.2),
    "dt_plaza_one": (["onecal"], 35.0, 33.0),
    "dt_round_crown": (["twocal"], 40.0, 38.0),
    "dt_ellipse_crown": (["gasco"], 47.0, 35.0),
    "dt_park_d": (["eighth_grand"], 33.4, 33.4),
    "dt_unfinished": (["oceanwide"], 62.3, 78.0),
}
CIVIC = {
    "arena": (["arena"], 240.0, 200.0), "live_plaza": (["la_live"], 300.0, 200.0),
    "live_hotel": (["jw_marriott"], 90.0, 70.0), "convention_center": (["convention"], 600.0, 300.0),
    "ziggurat_hall": (["city_hall"], 140.0, 110.0), "civic_park": (["grand_park"], 110.0, 500.0),
    "concert_hall": (["disney_hall"], 140.0, 110.0), "lattice_museum": (["the_broad"], 80.0, 90.0),
    "pueblo_station": (["union_station"], 400.0, 250.0),
}


def point_uv(key):
    r = C[key]["results"][0]
    return uv(en(float(r["lat"]), float(r["lon"])), B)


def mean_uv(keys):
    ps = [point_uv(k) for k in keys]
    return (sum(p[0] for p in ps) / len(ps), sum(p[1] for p in ps) / len(ps))


def cell(table, x):
    for i in range(len(table) - 1):
        if table[i][1] <= x < table[i + 1][1]:
            return i
    return None


def inner(table, i):
    a, b = table[i], table[i + 1]
    return (a[1] + a[2] * 0.5 + SIDEWALK, b[1] - b[2] * 0.5 - SIDEWALK)


if __name__ == "__main__":
    print("avenue spacing:", [round(AVENUES[i + 1][1] - AVENUES[i][1], 1) for i in range(len(AVENUES) - 1)])
    print("street spacing:", [round(STREETS[i + 1][1] - STREETS[i][1], 1) for i in range(len(STREETS) - 1)])
    for label, table in (("TOWERS", TOWERS), ("CIVIC", CIVIC)):
        print(label)
        for tid, (keys, px, pz) in table.items():
            u, v = mean_uv(keys)
            iu, iv = cell(AVENUES, u), cell(STREETS, v)
            if iu is None or iv is None:
                print("  %-18s u=%7.1f v=%7.1f OUTSIDE the pinned grid" % (tid, u, v))
                continue
            (u0, u1), (v0, v1) = inner(AVENUES, iu), inner(STREETS, iv)
            fits = (u1 - u0 >= px) and (v1 - v0 >= pz)
            cu = min(max(u, u0 + px / 2), u1 - px / 2)
            cv = min(max(v, v0 + pz / 2), v1 - pz / 2)
            print("  %-18s u=%7.1f v=%7.1f  block %s-%s x %s-%s inner %5.1f x %5.1f  plan %5.1f x %5.1f %s  nudge %5.1f,%5.1f  game (%.1f, %.1f)" % (
                tid, u, v, AVENUES[iu][0], AVENUES[iu + 1][0], STREETS[iv][0], STREETS[iv + 1][0],
                u1 - u0, v1 - v0, px, pz, "ok" if fits else "TOO BIG", cu - u, cv - v, ANCHOR[0] + cu, ANCHOR[1] + cv))
    # Distances
    ch, ar = point_uv("city_hall"), point_uv("arena")
    print("city hall -> arena %.0f m" % math.dist(ch, ar))
    for k in ("pershing", "city_hall", "arena", "union_station", "macarthur", "four_level", "dodger_stadium", "convention"):
        p = point_uv(k)
        print("  %-16s game (%.0f, %.0f)" % (k, ANCHOR[0] + p[0], ANCHOR[1] + p[1]))
