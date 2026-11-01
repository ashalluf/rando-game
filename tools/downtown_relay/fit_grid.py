#!/usr/bin/env python3
"""Fit the downtown LA street grid from geocoded centre-line points (geocode_cache.json).

Frame: local east/north metres about REF (Pershing Square as geocoded), WGS84 metres per degree
at REF's latitude. Grid: avenues run along bearing B (grid north), streets along B + 90.
u = metres along the streets toward grid east, v = metres along the avenues toward grid SOUTH
(so +v is the game's +Z once the grid is turned onto the game axes).
"""
import json, math, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
C = json.load(open(os.path.join(HERE, "geocode_cache.json")))

REF = (float(C["pershing"]["results"][0]["lat"]), float(C["pershing"]["results"][0]["lon"]))
PHI = math.radians(REF[0])
M_LAT = 111132.954 - 559.822 * math.cos(2 * PHI) + 1.175 * math.cos(4 * PHI)
M_LON = 111412.84 * math.cos(PHI) - 93.5 * math.cos(3 * PHI) + 0.118 * math.cos(5 * PHI)


def en(lat, lon):
    return ((lon - REF[1]) * M_LON, (lat - REF[0]) * M_LAT)


def uv(p, b):
    br = math.radians(b)
    a = (math.sin(br), math.cos(br))       # grid north (along the avenues)
    s = (math.cos(br), -math.sin(br))      # grid east (along the streets)
    return (p[0] * s[0] + p[1] * s[1], -(p[0] * a[0] + p[1] * a[1]))


def pts(key):
    out = []
    for r in C.get(key, {}).get("results", []):
        if r.get("class") != "highway" and not key.startswith("fw_"):
            continue
        out.append(en(float(r["lat"]), float(r["lon"])))
    return out


AVENUES = [k for k in C if k.startswith("av_") or k.startswith("avn_") or k.startswith("wl_")]
STREETS = [k for k in C if k.startswith("st_")]
# The core the grid is fitted in: the streets bend west of the 110 and east of Alameda.
CORE_U = (-1300.0, 1500.0)
CORE_V = (-1500.0, 1900.0)


def groups(b, keys, coord):
    g = {}
    for k in keys:
        for p in pts(k):
            q = uv(p, b)
            if CORE_U[0] <= q[0] <= CORE_U[1] and CORE_V[0] <= q[1] <= CORE_V[1]:
                g.setdefault(k, []).append(q[coord])
    return g


def cost(b, reject=None):
    tot, n = 0.0, 0
    for keys, coord in ((AVENUES, 0), (STREETS, 1)):
        for k, vals in groups(b, keys, coord).items():
            if reject and k in reject:
                vals = [v for i, v in enumerate(vals) if i not in reject[k]]
            if len(vals) < 2:
                continue
            m = sum(vals) / len(vals)
            tot += sum((v - m) ** 2 for v in vals)
            n += len(vals)
    return tot / max(n, 1)


def best_bearing(keys_coord=None):
    best = None
    for i in range(2000, 5000):
        b = i / 100.0
        c = cost(b)
        if best is None or c < best[1]:
            best = (b, c)
    return best


if __name__ == "__main__":
    print("REF", REF, "m/deg lat %.1f lon %.1f" % (M_LAT, M_LON))
    b, c = best_bearing()
    print("joint bearing %.2f  rms %.1f m" % (b, math.sqrt(c)))
    # Separate fits, to see whether the grid is square.
    for name, keys, coord in (("avenues", AVENUES, 0), ("streets", STREETS, 1)):
        bb = None
        for i in range(2000, 5000):
            x = i / 100.0
            t, n = 0.0, 0
            for k, vals in groups(x, keys, coord).items():
                if len(vals) < 2:
                    continue
                m = sum(vals) / len(vals)
                t += sum((v - m) ** 2 for v in vals)
                n += len(vals)
            if bb is None or t / max(n, 1) < bb[1]:
                bb = (x, t / max(n, 1))
        print("%s alone: bearing %.2f rms %.1f" % (name, bb[0], math.sqrt(bb[1])))
    for keys, coord, label in ((AVENUES, 0, "u"), (STREETS, 1, "v")):
        g = groups(b, keys, coord)
        rows = []
        for k, vals in g.items():
            m = sum(vals) / len(vals)
            r = math.sqrt(sum((v - m) ** 2 for v in vals) / len(vals))
            rows.append((m, k, len(vals), r, min(vals) - m, max(vals) - m))
        for m, k, n, r, lo, hi in sorted(rows):
            print("  %-16s %s=%8.1f  n=%2d rms=%5.1f  [%+.1f %+.1f]" % (k, label, m, n, r, lo, hi))
    print("landmarks (u, v):")
    for k in sorted(C):
        if k.startswith(("av_", "avn_", "st_", "wl_", "fw_")) or not C[k]["results"]:
            continue
        r = C[k]["results"][0]
        q = uv(en(float(r["lat"]), float(r["lon"])), b)
        print("  %-22s u=%8.1f v=%8.1f" % (k, q[0], q[1]))
    for k in sorted(C):
        if k.startswith("fw_"):
            print(k)
            for r in C[k]["results"]:
                q = uv(en(float(r["lat"]), float(r["lon"])), b)
                print("   u=%8.1f v=%8.1f  %s %s" % (q[0], q[1], r["type"], r["display_name"][:50]))
