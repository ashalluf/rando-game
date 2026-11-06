#!/usr/bin/env python3
"""Robust fit of the downtown grid: rotation, avenue u and street v, with residuals.

Each street's points are taken only where that street is on the core grid (the numbered streets
bend at the 110 and the eastern avenues fan out south of 2nd), then trimmed iteratively (points
more than TRIM m off the group's median go), and the bearing is the one that minimises the
remaining scatter. Prints a JSON blob (fit.json) the GDScript table is written from.
"""
import json, math, os
from fit_grid import C, REF, M_LAT, M_LON, en, uv

HERE = os.path.dirname(os.path.abspath(__file__))
TRIM = 18.0

# Where each group is on the grid: (coord, lo, hi) of the OTHER coordinate the points may have.
# Avenues: v window (grid-south metres); streets: u window.
GROUPS = {
    # Avenues west of Main run straight from the civic centre to Pico.
    "av_figueroa": ("u", -1000, 1250), "avn_figueroa": ("u", -1000, -850),
    "av_flower": ("u", -900, 1500), "av_hope": ("u", -900, 1500),
    "av_grand": ("u", -1300, 1500), "avn_grand": ("u", -1300, -850),
    "av_olive": ("u", -900, 1500), "av_hill": ("u", -900, 1500),
    "av_broadway": ("u", -900, 1900), "avn_broadway": ("u", -1300, -850),
    "av_spring": ("u", -900, 700), "avn_spring": ("u", -1400, -850),
    # East of Spring the grid turns; these are measured where they cross the civic centre and
    # Little Tokyo (1st to 3rd), which is where the replica needs them.
    "av_main": ("u", -900, 300), "avn_main": ("u", -1400, -850),
    "avn_losangeles": ("u", -1400, -600), "av_losangeles": ("u", -900, -500),
    "av_sanpedro": ("u", -900, -500), "av_central": ("u", -950, -600), "av_alameda": ("u", -1700, -700),
    "wl_alvarado": ("u", 100, 800), "wl_parkview": ("u", 100, 800),
    # Streets between the 110 and Main.
    "st_1st": ("v", -650, 450), "st_2nd": ("v", -650, 450), "st_3rd": ("v", -650, 450),
    "st_4th": ("v", -650, 450), "st_5th": ("v", -650, 450), "st_6th": ("v", -650, 450),
    "st_wilshire": ("v", -800, -150), "st_7th": ("v", -650, 450), "st_8th": ("v", -650, 450),
    "st_9th": ("v", -650, 450), "st_olympic": ("v", -650, 450), "st_11th": ("v", -650, 450),
    "st_12th": ("v", -650, 450), "st_pico": ("v", -700, 450), "st_temple": ("v", -350, 450),
    "st_e1st": ("v", 300, 1200), "st_e2nd": ("v", 300, 1200), "st_e3rd": ("v", 300, 1200),
    "st_e4th": ("v", 300, 1200), "st_venice2": ("v", -900, 450), "st_etemple": ("v", 300, 1200),
    "st_chavez": ("v", -800, 1200),
}


def raw(key):
    out = []
    for r in C.get(key, {}).get("results", []):
        if r.get("class") == "highway":
            out.append(en(float(r["lat"]), float(r["lon"])))
    return out


def group_vals(b, key):
    coord, lo, hi = GROUPS[key]
    vals = []
    for p in raw(key):
        q = uv(p, b)
        other = q[1] if coord == "u" else q[0]
        if lo <= other <= hi:
            vals.append((q[0] if coord == "u" else q[1], other))
    # Trim round the median until stable.
    keep = vals
    for _ in range(5):
        if len(keep) < 2:
            break
        med = sorted(v for v, _ in keep)[len(keep) // 2]
        k2 = [(v, o) for v, o in vals if abs(v - med) <= TRIM]
        if k2 == keep:
            break
        keep = k2
    return keep


def scatter(b, keys):
    t, n = 0.0, 0
    for k in keys:
        vs = group_vals(b, k)
        if len(vs) < 2:
            continue
        m = sum(v for v, _ in vs) / len(vs)
        t += sum((v - m) ** 2 for v, _ in vs)
        n += len(vs)
    return t / max(n, 1), n


def best(keys):
    bb = None
    for i in range(3400, 4000):
        b = i / 100.0
        s, n = scatter(b, keys)
        if bb is None or s < bb[1]:
            bb = (b, s, n)
    return bb


if __name__ == "__main__":
    keys = [k for k in GROUPS if k in C]
    avs = [k for k in keys if GROUPS[k][0] == "u" and k.startswith(("av_", "avn_"))]
    sts = [k for k in keys if GROUPS[k][0] == "v"]
    # Bearing from the western core only (the eastern avenues are on another grid).
    core_av = [k for k in avs if k not in ("av_main", "avn_main", "avn_losangeles", "av_losangeles", "av_sanpedro", "av_central", "av_alameda")]
    core_st = [k for k in sts if not k.startswith(("st_e", "st_chavez", "st_venice2", "st_temple"))]
    b_av = best(core_av)
    b_st = best(core_st)
    b = best(core_av + core_st)
    print("avenue bearing %.2f (rms %.1f m, %d pts)" % (b_av[0], math.sqrt(b_av[1]), b_av[2]))
    print("street bearing %.2f + 90 (rms %.1f m, %d pts)" % (b_st[0], math.sqrt(b_st[1]), b_st[2]))
    print("joint square grid %.2f (rms %.1f m, %d pts)" % (b[0], math.sqrt(b[1]), b[2]))
    B = round(b[0], 1)
    out = {"ref": REF, "m_lat": M_LAT, "m_lon": M_LON, "bearing": B, "bearing_avenues": b_av[0],
        "bearing_streets": b_st[0], "rms": math.sqrt(b[1]), "points": b[2], "roads": {}, "landmarks": {}}
    for k in keys:
        vs = group_vals(B, k)
        if not vs:
            print("  %-16s no points in window" % k)
            continue
        m = sum(v for v, _ in vs) / len(vs)
        r = math.sqrt(sum((v - m) ** 2 for v, _ in vs) / len(vs))
        worst = max(abs(v - m) for v, _ in vs)
        out["roads"][k] = {"pos": m, "n": len(vs), "rms": r, "worst": worst,
            "span": [min(o for _, o in vs), max(o for _, o in vs)], "raw": len(raw(k))}
    for k, d in sorted(out["roads"].items(), key=lambda kv: (GROUPS[kv[0]][0], kv[1]["pos"])):
        print("  %-16s %s=%8.1f  n=%2d/%2d rms=%5.1f worst=%5.1f  along %6.0f..%6.0f" % (k, GROUPS[k][0], d["pos"], d["n"], d["raw"], d["rms"], d["worst"], d["span"][0], d["span"][1]))
    for k in sorted(C):
        if k.startswith(("av_", "avn_", "st_", "wl_")) or not C[k]["results"]:
            continue
        pts = []
        for r in C[k]["results"]:
            q = uv(en(float(r["lat"]), float(r["lon"])), B)
            pts.append([q[0], q[1], float(r["lat"]), float(r["lon"]), r.get("type"), r.get("display_name", "")[:60]])
        out["landmarks"][k] = pts
    json.dump(out, open(os.path.join(HERE, "fit.json"), "w"), indent=1)
    print("wrote fit.json")
