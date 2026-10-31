# The crowd's shoe parts (crowd_shoes.py), painted texel by texel for garment_paint.py: the sole
# band by its metric v (height up the sidewall; < 0 the underside, > the sole's height the ledge
# onto the upper), the outsole's tread by position, the laces' braid along them, the eyelets.
# Colour in linear light and a height field in metres (the normal map), like every own garment.
import numpy as np

from garment_paint import _Sub, fbm, gauss, sstep, vnoise

TAU = 2.0 * np.pi


def _sole_h(style, sole, t):
    h0, h1 = sole["h"]
    if style in ("derby", "loafer"):
        k = 1.0 - sstep(0.26, 0.32, t)
    else:
        k = 1.0 - sstep(0.18, 0.78, t)
    return h1 + (h0 - h1) * k


def _along(P, L):
    """0 at the heel, 1 at the toe, per texel, from its own shoe's landmarks."""
    t = np.zeros(len(P))
    for sd in L["sides"]:
        m = (P[:, 0] * sd["sg"]) > 0
        heel, toe = np.array(sd["heel"]), np.array(sd["toe"])
        f = toe[:2] - heel[:2]
        ln = np.linalg.norm(f)
        t[m] = np.clip(((P[m, :2] - heel[:2]) @ (f / ln)) / ln, 0.0, 1.0)
    return t


def paint_shoes(pt, B, X, pidx, parts, L, spec):
    style = L["style"]
    sole = L["sole"]
    by = {parts[k]["part"]: k for k in pidx}
    if "sole" in by:
        _sole(pt, X, X.part == by["sole"], L, spec, style, sole)
    if "outsole" in by:
        _outsole(pt, X, X.part == by["outsole"], L, spec, style, sole)
    if "laces" in by:
        _laces(pt, X, X.part == by["laces"], spec)
    if "eyelets" in by:
        sel = X.part == by["eyelets"]
        sub = _Sub(pt, sel)
        sub.tint(np.ones(sel.sum()), spec["eyelet"], 1.0)
        sub.shade(0.85 + 0.15 * np.clip(X.N[sel, 2], 0.0, 1.0))
        sub.commit()


def _sole(pt, X, sel, L, spec, style, sole):
    sub = _Sub(pt, sel)
    P = X.P[sel]
    u, v = X.G[sel, 0], X.G[sel, 1]
    mpp = X.mpp[sel]
    t = _along(P, L)
    h = _sole_h(style, sole, t)
    n = len(P)
    sub.tint(np.ones(n), spec["sole"], 1.0)
    under = v < 0.0
    ledge = v > h - 0.0004
    if style == "sneaker":
        # the outsole's rubber up the first few millimetres, a groove over it, then the foam
        rub = 1.0 - sstep(0.0040, 0.0052, v)
        sub.tint(rub, spec["outsole"], 1.0)
        g = gauss(v - 0.0072, np.maximum(0.0006, 0.75 * mpp))
        sub.shade(1.0 - 0.28 * g)
        sub.h -= 0.0004 * g
        # foam: a faint grain, a moulded line along the middle, darker toward the ground (dirt)
        sub.shade(1.0 + 0.035 * fbm(P, 0.003, 2, seed=301))
        mid = gauss(v - 0.55 * h, np.maximum(0.0005, 0.75 * mpp))
        sub.shade(1.0 - 0.10 * mid)
        sub.h += 0.0002 * mid
        dirt = (1.0 - sstep(0.0, 0.016, v)) * (0.6 + 0.4 * fbm(P, 0.01, 2, seed=303))
        sub.tint(np.clip(dirt * 0.22, 0.0, 1.0), [96, 88, 76], 1.0)
    elif style == "boot":
        # lugs: notches across the lower sidewall; the welt at the top with its stitch row
        ph = (u / 0.011) % 1.0
        notch = (sstep(0.0, 0.08, ph) - sstep(0.30, 0.38, ph)) * (1.0 - sstep(0.008, 0.010, v))
        sub.shade(1.0 - 0.45 * notch)
        sub.h -= 0.0015 * notch
        welt = sstep(h - 0.0052, h - 0.0044, v)
        sub.tint(welt, spec.get("welt", spec["sole"]), 1.0)
        line = gauss(v - (h - 0.0048), np.maximum(0.0004, 0.6 * mpp))
        sub.shade(1.0 - 0.35 * line)
        st = gauss(v - (h - 0.0030), np.maximum(0.0005, 0.7 * mpp)) * (((u / 0.0042) % 1.0) < 0.6)
        sub.tint(st * 0.7, [150, 128, 96], 1.0)
        sub.h += 0.0003 * st
        sub.shade(1.0 + 0.06 * fbm(P, 0.004, 2, seed=307))
    else:
        # leather: a burnished edge, a stitch row round the forepart, the heel stacked in lifts
        sub.shade(1.0 + 0.05 * fbm(P, 0.006, 2, seed=311))
        st = gauss(v - (h - 0.0035), np.maximum(0.0004, 0.6 * mpp)) * (((u / 0.0036) % 1.0) < 0.55) * (t > 0.32)
        sub.shade(1.0 - 0.30 * st)
        sub.h -= 0.0002 * st
        heel = 1.0 - sstep(0.24, 0.27, t)
        lifts = heel * (np.abs(((v / 0.0052) % 1.0) - 0.5) < 0.08) * (v > 0.003) * (v < h - 0.012)
        sub.shade(1.0 - 0.35 * lifts)
        sub.h -= 0.0002 * lifts
        top = gauss(v - (h - 0.0008), np.maximum(0.0005, 0.7 * mpp))
        sub.shade(1.0 + 0.25 * top)
    # the underside's edge (seen at a toe-off) is the outsole's; the ledge into the upper darker
    sub.tint(under.astype(float), spec["outsole"], 1.0)
    sub.shade(np.where(ledge, 0.72, 1.0))
    sub.commit()


def _outsole(pt, X, sel, L, spec, style, sole):
    sub = _Sub(pt, sel)
    P = X.P[sel]
    mpp = X.mpp[sel]
    t = _along(P, L)
    n = len(P)
    sub.tint(np.ones(n), spec["outsole"], 1.0)
    x, y = P[:, 0], P[:, 1]
    if style == "sneaker":
        # a wave tread across the forepart and the heel, a smooth band under the arch
        wav = np.sin(TAU * (y / 0.0075 + 0.25 * np.sin(TAU * x / 0.02)))
        fade = 1.0 - sstep(0.0015, 0.004, mpp)
        k = (wav > 0.2).astype(float) * fade * (1.0 - 0.8 * (sstep(0.32, 0.38, t) - sstep(0.55, 0.62, t)))
        sub.shade(1.0 - 0.25 * k)
        sub.h += 0.0010 * k
    elif style == "boot":
        cell = (np.abs((x / 0.012) % 1.0 - 0.5) < 0.32) & (np.abs((y / 0.014) % 1.0 - 0.5) < 0.30)
        k = cell.astype(float) * (1.0 - sstep(0.002, 0.005, mpp))
        sub.shade(1.0 + 0.12 * k)
        sub.h += 0.0020 * k
    else:
        heel = 1.0 - sstep(0.24, 0.27, t)
        sub.shade(1.0 - 0.18 * heel)
        sub.shade(1.0 + 0.05 * fbm(P, 0.008, 2, seed=313))
    sub.commit()


def _laces(pt, X, sel, spec):
    sub = _Sub(pt, sel)
    u, v = X.G[sel, 0], X.G[sel, 1]
    mpp = X.mpp[sel]
    n = len(u)
    sub.tint(np.ones(n), spec["lace"], 1.0)
    # a flat braid: chevrons of yarn along the lace, faded to its average under a texel
    br = np.sin(TAU * (u / 0.0024 + np.abs(v - 0.005) / 0.003))
    fade = 1.0 - sstep(0.0006, 0.0016, mpp)
    sub.shade(1.0 + 0.16 * br * fade)
    sub.h += 0.00015 * br * fade
    sub.commit()
