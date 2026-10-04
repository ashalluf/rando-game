# Our own garments' texels (tools/crowd/garments.py), painted into the body atlas for
# crowd_atlas.py (python3 + numpy + PIL, no Blender).
#
# The garments have no source photo: their atlas rects are "virtual" in the plan. Every own
# garment triangle build_character.py dumped (own.npz: atlas UVs, rest-pose corners and normals,
# the bands' metric UVs, per-vertex ambient occlusion, which part it is) is rasterised into the
# 2048 px atlas, and each texel is painted from what the garment IS at that point on the body,
# worked out in 3D from the landmarks garments.py recorded (garments.json: the bones, every cut
# plane and hem line):
#
#   tee       side, shoulder, armhole and underarm seams; a coverstitch below the neckline; twin
#             needle hems; the rib collar's wales; jersey heather on request
#   trousers  waistband with topstitching and belt loops, fly with its J-stitch, front pockets
#             (scooped on jeans, slanted on chinos), the jeans' yoke, centre-back seam and patch
#             pockets, chinos' welt pockets and pressed crease, out- and inseams, folded hems;
#             denim worn pale over the thighs, knees and seat, whiskers at the hip and
#             honeycombs behind the knee, slub streaks down the leg
#   shirt     yoke, side and armhole seams, chest pocket, placket, collar and cuffs (bands),
#             stripes or a check that follow the body and turn with the sleeve
#   jacket    panel seams, welt pockets, the zip tapes, rib cuffs and hem band
#
# Every feature is a height (metres) and a colour change; the normal map is the height field's
# slope at each texel's own metric scale, so a seam is the same few millimetres on every body.
# Colours are the outfit's ("color", "thread", "wash", "pattern", ... in crowd_config.json),
# read again on every run, so `FROM=crowd_atlas tools/crowd/build.sh` is enough after a change.
import json
import math
import os

import numpy as np
from PIL import Image

import crowd_common as C
import texlib as T

TAU = 2.0 * math.pi


# ---- small helpers ------------------------------------------------------------------------------
def sstep(a, b, x):
    t = np.clip((np.asarray(x, np.float64) - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def gauss(d, w):
    return np.exp(-(np.asarray(d) / np.maximum(w, 1e-6)) ** 2)


def srgb(rgb):
    return np.array(rgb, np.float64) / 255.0


def _hash3(i, j, k, seed):
    h = (i * 73856093) ^ (j * 19349663) ^ (k * 83492791) ^ (seed * 2654435761)
    h = (h ^ (h >> 13)) * 1274126177
    h = h ^ (h >> 16)
    return (h & 0xFFFFFF).astype(np.float64) / float(0xFFFFFF)


def vnoise(p, scale, seed=0):
    """Smooth value noise in 3D (trilinear, smoothstepped), -0.5..0.5; p (n,3) metres, scale m."""
    q = np.asarray(p, np.float64) / scale
    i = np.floor(q).astype(np.int64)
    f = q - i
    f = f * f * (3.0 - 2.0 * f)
    out = np.zeros(len(q))
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[:, 0] if dx else 1 - f[:, 0]) * (f[:, 1] if dy else 1 - f[:, 1]) * (f[:, 2] if dz else 1 - f[:, 2])
                out += w * _hash3(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz, seed)
    return out - 0.5


def fbm(p, scale, octaves=3, seed=0):
    out = np.zeros(len(p))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        out += amp * vnoise(p, scale / (2 ** o), seed + o * 7)
        tot += amp
        amp *= 0.5
    return out / tot


def seg_dist(Q, pts):
    """Distance from 2D points Q (n,2) to a polyline pts (m,2), and the arc length along it of the
    nearest point."""
    pts = np.asarray(pts, np.float64)
    best = np.full(len(Q), np.inf)
    along = np.zeros(len(Q))
    run = 0.0
    for a, b in zip(pts[:-1], pts[1:]):
        ab = b - a
        L2 = max(float(ab @ ab), 1e-12)
        t = np.clip(((Q - a) @ ab) / L2, 0.0, 1.0)
        d = np.linalg.norm(Q - (a + t[:, None] * ab), axis=1)
        m = d < best
        best[m] = d[m]
        along[m] = run + t[m] * math.sqrt(L2)
        run += math.sqrt(L2)
    return best, along


def poly_sdf(Q, poly):
    """Signed distance to a closed 2D polygon (negative inside)."""
    closed = np.vstack([poly, poly[:1]])
    d, _ = seg_dist(Q, closed)
    inside = np.zeros(len(Q), bool)
    x, y = Q[:, 0], Q[:, 1]
    for (x0, y0), (x1, y1) in zip(closed[:-1], closed[1:]):
        c = ((y0 > y) != (y1 > y)) & (x < (x1 - x0) * (y - y0) / np.where(np.abs(y1 - y0) < 1e-12, 1e-12, y1 - y0) + x0)
        inside ^= c
    return np.where(inside, -d, d)


# ---- the texels ---------------------------------------------------------------------------------
class Texels:
    """Every atlas texel an own garment triangle covers: its rest-pose point, normal, metric band
    UV, ambient occlusion, part, and the metres one texel spans there."""

    def __init__(self, Z, size):
        uv = Z["uv"].astype(np.float64)
        p, n, g, ao = (Z[k].astype(np.float64) for k in ("p", "n", "guv", "ao"))
        part = Z["part"]
        tid = np.full((size, size), -1, np.int64)
        b0 = np.zeros((size, size))
        b1 = np.zeros((size, size))
        q = uv * size
        q[..., 1] = size - q[..., 1]
        for t in range(len(q)):
            (ax, ay), (bx, by), (cx, cy) = q[t]
            x0, y0 = int(max(math.floor(min(ax, bx, cx)), 0)), int(max(math.floor(min(ay, by, cy)), 0))
            x1, y1 = int(min(math.ceil(max(ax, bx, cx)), size - 1)), int(min(math.ceil(max(ay, by, cy)), size - 1))
            if x1 < x0 or y1 < y0:
                continue
            xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if abs(den) < 1e-12:
                continue
            w0 = ((by - cy) * (xs - cx) + (cx - bx) * (ys - cy)) / den
            w1 = ((cy - ay) * (xs - cx) + (ax - cx) * (ys - cy)) / den
            w2 = 1.0 - w0 - w1
            inside = (w0 >= -0.03) & (w1 >= -0.03) & (w2 >= -0.03)
            sub = tid[y0:y1 + 1, x0:x1 + 1]
            # a texel takes the triangle it is most inside of (shared edges, the tolerance)
            mine = inside & ((sub < 0) | (np.minimum(np.minimum(w0, w1), w2) >= 0))
            sub[mine] = t
            b0[y0:y1 + 1, x0:x1 + 1][mine] = w0[mine]
            b1[y0:y1 + 1, x0:x1 + 1][mine] = w1[mine]
        self.cov = tid >= 0
        self.iy, self.ix = np.nonzero(self.cov)
        t = tid[self.iy, self.ix]
        w = np.stack([b0[self.iy, self.ix], b1[self.iy, self.ix], 1.0 - b0[self.iy, self.ix] - b1[self.iy, self.ix]], 1)
        w = np.clip(w, 0.0, 1.0)
        w /= w.sum(1, keepdims=True)
        self.tri = t
        self.P = np.einsum("nk,nkd->nd", w, p[t])
        N = np.einsum("nk,nkd->nd", w, n[t])
        self.N = N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
        self.G = np.einsum("nk,nkd->nd", w, g[t])
        self.ao = np.einsum("nk,nk->n", w, ao[t])
        self.part = part[t]
        # which part of a top: 0 torso, 1 left sleeve, 2 right sleeve (garments.py's "zone")
        self.zone = Z["zone"][t] if "zone" in Z.files else np.zeros(len(t), np.int32)
        # metres per texel, per triangle
        e1, e2 = p[:, 1] - p[:, 0], p[:, 2] - p[:, 0]
        a3 = 0.5 * np.linalg.norm(np.cross(e1, e2), axis=1)
        f1, f2 = q[:, 1] - q[:, 0], q[:, 2] - q[:, 0]
        a2 = 0.5 * np.abs(f1[:, 0] * f2[:, 1] - f1[:, 1] * f2[:, 0])
        mpp = np.sqrt(a3 / np.maximum(a2, 1e-9))
        self.mpp = mpp[t]
        self.size = size


# ---- what each garment is, texel by texel ------------------------------------------------------
class Paint:
    """Accumulates one garment's colour (linear RGB) and height (metres) over its texels."""

    def __init__(self, n, base_rgb):
        self.lin = np.tile(T.srgb_to_lin(srgb(base_rgb)), (n, 1))
        self.h = np.zeros(n)

    def tint(self, mask_w, rgb, amount=1.0):
        """Toward another colour (sRGB), by weight per texel."""
        w = np.clip(np.asarray(mask_w) * amount, 0.0, 1.0)[:, None]
        self.lin = self.lin * (1 - w) + T.srgb_to_lin(srgb(rgb))[None, :] * w

    def shade(self, factor):
        self.lin = self.lin * np.asarray(factor)[:, None]


def seam(pt, d, mpp, along=None, side=1.0, stitch=None, rows=(), thread=None, groove=0.0004, ridge=0.0005,
         allowance=0.007, width=0.0009, dark=0.12):
    """A seam at signed distance d: the groove where the panels meet (darker), the allowance
    pressed to one side under the cloth (a soft ridge), and topstitch rows at the given offsets
    (signed, the side the allowance lies) in the thread colour, a little raised, dashed along
    `along` when given."""
    w = np.maximum(width, 0.75 * mpp)
    g = gauss(d, w)
    pt.h -= groove * g
    pt.shade(1.0 - dark * g)
    s = d * side
    pt.h += ridge * sstep(-0.0005, 0.0015, s) * (1.0 - sstep(allowance * 0.6, allowance, s))
    for off in rows:
        tw = np.maximum(0.0006, 0.6 * mpp)
        r = gauss(d - off * side, tw)
        if along is not None:
            dash = 0.55 + 0.45 * np.cos(TAU * along / 0.0034) ** 2
            r = r * dash
        pt.h += 0.00025 * r
        if thread is not None:
            pt.tint(r, thread, 0.85)
        else:
            pt.shade(1.0 - 0.18 * r)


def hem_band(pt, d_edge, depth, mpp, rows, thread=None, along=None, roll=0.0005):
    """A folded hem above an edge (d_edge = distance from the cut edge into the garment): the
    doubled cloth a touch raised over `depth`, falling away at the stitch rows."""
    pt.h += roll * (1.0 - sstep(depth - 0.002, depth + 0.001, d_edge)) * sstep(-0.001, 0.002, d_edge)
    for r in rows:
        tw = np.maximum(0.0006, 0.6 * mpp)
        k = gauss(d_edge - r, tw)
        if along is not None:
            k = k * (0.55 + 0.45 * np.cos(TAU * along / 0.0032) ** 2)
        pt.h -= 0.0002 * k
        if thread is not None:
            pt.tint(k, thread, 0.8)
        else:
            pt.shade(1.0 - 0.16 * k)
    # the fold itself catches a little light and wears
    pt.shade(1.0 + 0.04 * gauss(d_edge, 0.0015))


def edge_dist(P, hems, tag_prefix):
    """Distance from each point to the hem lines whose tag starts with tag_prefix (3D polylines)."""
    best = np.full(len(P), np.inf)
    for tag, pts in hems:
        if not tag.startswith(tag_prefix):
            continue
        A = np.asarray(pts, np.float64)
        A = np.vstack([A, A[:1]])
        for a, b in zip(A[:-1], A[1:]):
            ab = b - a
            L2 = max(float(ab @ ab), 1e-12)
            t = np.clip(((P - a) @ ab) / L2, 0.0, 1.0)
            d = np.linalg.norm(P - (a + t[:, None] * ab), axis=1)
            best = np.minimum(best, d)
    return best


class Body:
    """The rest-pose landmarks (Blender space: the figure faces -Y, its left is +X, Z up)."""

    def __init__(self, meta):
        self.b = {k: np.array(v) for k, v in meta["bones"].items()}
        self.crotch = meta["crotch_z"]

    def B(self, n):
        return self.b[n]

    def torso_axis_y(self, z):
        """The torso's centre depth at height z (between the hips, chest and neck joints)."""
        zs = [self.b["Hips"][2], self.b["Spine01"][2], self.b["Spine"][2], self.b["neck"][2]]
        ys = [self.b["Hips"][1], self.b["Spine01"][1], self.b["Spine"][1], self.b["neck"][1]]
        o = np.argsort(zs)
        return np.interp(z, np.array(zs)[o], np.array(ys)[o])

    def azimuth(self, P):
        """Round the torso axis: 0 front, +pi/2 the figure's left (+x), pi the back."""
        yc = self.torso_axis_y(P[:, 2])
        return np.arctan2(P[:, 0], -(P[:, 1] - yc)), np.hypot(P[:, 0], P[:, 1] - yc)

    def limb(self, P, a, b):
        """(s along a->b, radial unit vectors, radius) for points round a limb segment."""
        a, b = self.B(a), self.B(b)
        ax = (b - a) / np.linalg.norm(b - a)
        d = P - a
        s = d @ ax
        r = d - np.outer(s, ax)
        rl = np.linalg.norm(r, axis=1)
        return s, r / np.maximum(rl, 1e-9)[:, None], rl, ax


# ---- the tee ------------------------------------------------------------------------------------
def paint_top_seams(pt, B, X, sel, L, spec, thread, kind):
    """Side, shoulder and armhole seams of a set-in-sleeve top, and the underarm seam."""
    P = X.P[sel]
    mpp = X.mpp[sel]
    N = X.N[sel]
    ch = B.B("Spine")
    yc = B.torso_axis_y(P[:, 2])
    armpit_z = ch[2] + 0.03
    sh_x = abs(B.B("LeftArm")[0])
    for side, sg in (("Left", 1.0), ("Right", -1.0)):
        s_arm, rdir, rl, ax = B.limb(P, side + "Arm", side + "ForeArm")
        on_side = (P[:, 0] * sg) > 0
        # sleeve vs body by the shell's own zones (garments.py); by the armhole plane alone, the
        # whole torso under a 45-degree bind-pose arm counted as sleeve
        arm_s = s_arm - 0.01
        zone = X.zone[sel]
        sleeve = on_side & (zone == (1 if side == "Left" else 2))
        torso = ~sleeve & (zone == 0)
        # side seam: where the torso's mid-depth plane meets its side, below the armpit
        m = torso & on_side & (np.abs(P[:, 0]) > 0.06) & (P[:, 2] < armpit_z)
        if m.any():
            d = np.where(m, P[:, 1] - yc, 1.0)
            _seam_into(pt, sel, d, mpp, rows=(0.006,) if kind != "tee" else (), side=1.0, thread=thread, along=P[:, 2])
        # shoulder seam: the same plane over the top of the shoulder, neck to armhole
        m = torso & on_side & (P[:, 2] > ch[2] + 0.06) & (np.abs(P[:, 0]) > 0.05) & (N[:, 2] > 0.2)
        if m.any():
            d = np.where(m, P[:, 1] - (B.B("neck")[1] + 0.012), 1.0)
            _seam_into(pt, sel, d, mpp, rows=(), side=-1.0, thread=thread, along=P[:, 0])
        # armhole: the plane across the arm at the joint, round the shoulder
        near = on_side & (np.linalg.norm(P - B.B(side + "Arm"), axis=1) < 0.16)
        if near.any():
            d = np.where(near, arm_s, 1.0)
            _seam_into(pt, sel, d, mpp, rows=(0.006,) if kind == "shirt" else (), side=-1.0, thread=thread, along=P[:, 2])
        # underarm: along the sleeve's underside (the side facing the body in the bind pose)
        under = np.array([-sg, 0.0, -1.0])
        under = under - ax * (under @ ax)
        under /= np.linalg.norm(under)
        pn = np.cross(ax, under)
        m = sleeve & ((rdir @ under) > 0.3)
        if m.any():
            d = np.where(m, (P - B.B(side + "Arm")) @ pn, 1.0)
            _seam_into(pt, sel, d, mpp, rows=(), side=1.0, thread=thread, along=s_arm)


def _seam_into(pt, sel, d, mpp, **kw):
    """seam() on the subset `sel` of a Paint whose arrays cover all of this garment's texels."""
    sub = _Sub(pt, sel)
    seam(sub, d, mpp, **kw)
    sub.commit()


class _Sub:
    """A view of some texels of a Paint, written back by commit()."""

    def __init__(self, pt, sel):
        self.pt, self.sel = pt, sel
        self.lin = pt.lin[sel].copy()
        self.h = pt.h[sel].copy()

    def tint(self, mask_w, rgb, amount=1.0):
        Paint.tint(self, mask_w, rgb, amount)

    def shade(self, factor):
        Paint.shade(self, factor)

    def commit(self):
        self.pt.lin[self.sel] = self.lin
        self.pt.h[self.sel] = self.h


def paint_tee(pt, B, X, sel_shell, sel_collar, L, spec):
    thread = None
    if spec.get("heather"):
        p = X.P[sel_shell]
        k = fbm(p, 0.004, 2, seed=5) * 0.10 + vnoise(p, 0.0015, seed=9) * 0.08
        sub = _Sub(pt, sel_shell)
        sub.shade(1.0 + k)
        sub.commit()
    paint_top_seams(pt, B, X, sel_shell, L, spec, thread, "tee")
    P = X.P[sel_shell]
    mpp = X.mpp[sel_shell]
    sub = _Sub(pt, sel_shell)
    # twin-needle hems at the bottom and the sleeves
    d = edge_dist(P, L["hems"], "hem")
    hem_band(sub, d, 0.018, mpp, rows=(0.011, 0.017), along=P[:, 0])
    d = edge_dist(P, L["hems"], "sleeve")
    hem_band(sub, d, 0.016, mpp, rows=(0.010, 0.015), along=P[:, 2])
    # the coverstitch round the neck, just under the neckline plane
    if "neck_cut" in L:
        zb, zf, yb, yf = L["neck_cut"]
        no = np.cross([1.0, 0.0, 0.0], [0.0, yf - yb, zf - zb])
        no /= np.linalg.norm(no)
        if no[2] < 0:
            no = -no
        dn = -((P - np.array([0.0, yb, zb])) @ no)
        near = P[:, 2] > zf - 0.06
        hem_band(sub, np.where(near, dn, 1.0), 0.008, mpp, rows=(0.007,), along=P[:, 0], roll=0.0)
    sub.commit()
    if sel_collar is not None and sel_collar.any():
        # 1x1 rib: wales across the band (along its section), a hair darker than the body
        g = X.G[sel_collar]
        sub = _Sub(pt, sel_collar)
        rib = np.cos(TAU * g[:, 0] / 0.0024)
        sub.h += 0.00022 * rib
        sub.shade(0.97 + 0.03 * rib)
        sub.commit()


# ---- trousers -----------------------------------------------------------------------------------
def paint_trousers(pt, B, X, sel, L, spec, outfit_color):
    style = L["style"]
    P = X.P[sel]
    N = X.N[sel]
    mpp = X.mpp[sel]
    sub = _Sub(pt, sel)
    denim = style in ("jeans", "slim", "shorts")
    thread = spec.get("thread", [196, 142, 70] if denim else None)
    if thread is None:
        thread = list(np.clip(np.array(outfit_color) * 0.82, 0, 255))
    co, no = np.array(L["waist_co"]), np.array(L["waist_no"])
    dw = -((P - co) @ no)                 # metres below the waist edge
    th, rr = B.azimuth(P)
    hips = B.B("Hips")
    front = np.cos(th)                    # 1 front, -1 back
    crotch = B.crotch
    # ---- the cloth itself: denim worn pale where it rubs, slub streaks down the leg
    if denim:
        wash = spec.get("wash", 0.35)
        leg_s = np.zeros(len(P))
        leg_r = np.zeros(len(P))
        leg_fwd = np.zeros(len(P))
        for side, sg in (("Left", 1.0), ("Right", -1.0)):
            m = (P[:, 0] * sg) > 0
            s1, rd1, r1, ax1 = B.limb(P[m], side + "UpLeg", side + "Leg")
            leg_s[m] = s1
            leg_fwd[m] = -rd1[:, 1]
            leg_r[m] = r1
        knee_z = B.B("LeftLeg")[2]
        thigh = gauss((P[:, 2] - (crotch - 0.12)) / 0.16, 1.0) * sstep(0.1, 0.8, leg_fwd) * (P[:, 2] < crotch + 0.02)
        knee = gauss((P[:, 2] - (knee_z + 0.02)) / 0.07, 1.0) * sstep(0.2, 0.9, leg_fwd)
        seat = gauss((P[:, 2] - (crotch + 0.07)) / 0.08, 1.0) * sstep(0.3, 0.9, -front) * (P[:, 2] > crotch - 0.05)
        fade = np.clip(0.75 * thigh + 0.6 * knee + 0.55 * seat, 0.0, 1.0)
        # slub: irregular streaks running down the leg (noise stretched along it)
        slub = fbm(np.stack([P[:, 0] * 6.0, P[:, 1] * 6.0, P[:, 2] * 0.35], 1), 0.05, 3, seed=21)
        mottle = fbm(P, 0.03, 3, seed=33)
        light = np.clip(fade * (0.45 + 0.55 * (0.5 + mottle)) * wash * 1.6, 0.0, 1.0)
        pale = T.srgb_to_lin(srgb(spec.get("fade_color", [120, 150, 190])))
        sub.lin = sub.lin * (1.0 - 0.55 * light[:, None]) + pale[None, :] * (0.55 * light[:, None])
        sub.shade(1.0 + 0.16 * slub + 0.08 * mottle)
        # whiskers: short pale streaks fanning out and up from the crotch over the top of the thigh
        wk = np.zeros(len(P))
        for side, sg in (("Left", 1.0), ("Right", -1.0)):
            m = ((P[:, 0] * sg) > 0) & (front > 0.3) & (P[:, 2] > crotch - 0.10) & (P[:, 2] < crotch + 0.06)
            if not m.any():
                continue
            Q = np.stack([P[m, 0] * sg, P[m, 2]], 1)
            acc = np.zeros(m.sum())
            for k in range(5):
                ang = math.radians(8 + 9 * k)
                y0 = crotch - 0.035 + 0.018 * k
                a = np.array([0.025, y0])
                b = a + np.array([math.cos(ang), math.sin(ang)]) * (0.07 - 0.006 * k)
                d, al = seg_dist(Q, [a, b])
                ln = np.linalg.norm(b - a)
                acc = np.maximum(acc, gauss(d, 0.0035) * np.sin(np.clip(al / ln, 0, 1) * math.pi) ** 0.7)
            wk[m] = acc
        hc = np.zeros(len(P))
        for side, sg in (("Left", 1.0), ("Right", -1.0)):
            m = ((P[:, 0] * sg) > 0) & (front < -0.2)
            if not m.any():
                continue
            kz = B.B(side + "Leg")[2]
            for k in range(3):
                z0 = kz - 0.015 + 0.02 * k
                hc[m] = np.maximum(hc[m], gauss(P[m, 2] - z0, 0.0035) * gauss(P[m, 0] * sg - abs(B.B(side + "Leg")[0]), 0.035))
        streak = np.clip((wk + hc) * wash * 1.4, 0.0, 1.0)
        sub.lin = sub.lin * (1.0 - 0.45 * streak[:, None]) + pale[None, :] * (0.45 * streak[:, None])
        sub.h -= 0.0004 * (wk + hc)
    else:
        sub.shade(1.0 + 0.05 * fbm(P, 0.02, 2, seed=41))
    # ---- waistband: band, topstitching, the seam under it, belt loops
    band = 0.038 if style != "leggings" else 0.055
    inb = (dw > -0.002) & (dw < band + 0.002)
    if style != "leggings":
        hem_band(sub, np.where(P[:, 2] > crotch, dw, 1.0), band, mpp, rows=(0.0035, band - 0.0035), thread=thread, along=th * rr)
        seam(sub, np.where(P[:, 2] > crotch + 0.04, dw - band, 1.0), mpp, side=-1.0, groove=0.0006, dark=0.2)
        # belt loops: azimuths from the front (radians), each 12 mm wide, from the top edge down
        for a0 in (math.radians(x) for x in (-150, -105, -40, 40, 105, 150, 180)):
            da = np.angle(np.exp(1j * (th - a0))) * rr
            m = (np.abs(da) < 0.012) & (dw > -0.003) & (dw < band + 0.012)
            if not m.any():
                continue
            prof = (1.0 - sstep(0.0045, 0.0065, np.abs(da))) * sstep(-0.003, 0.0, dw) * (1.0 - sstep(band + 0.008, band + 0.012, dw))
            sub.h += 0.0014 * prof
            sub.shade(1.0 - 0.25 * gauss(np.abs(da) - 0.0058, 0.0009) * (prof > 0.05))
            # bar tacks at each end
            for zt in (0.002, band + 0.008):
                k = gauss(dw - zt, 0.0012) * (np.abs(da) < 0.0055)
                sub.tint(k, thread, 0.9)
    else:
        seam(sub, np.where(P[:, 2] > crotch + 0.04, dw - band, 1.0), mpp, side=-1.0, rows=(0.004,), groove=0.0005)
    # ---- the fly and the centre seams
    fx = np.abs(P[:, 0])
    frontish = (front > 0.4)
    if style != "leggings":
        # centre front: the fly's edge, waistband to crotch
        m = frontish & (dw > band) & (P[:, 2] > crotch - 0.01)
        seam(sub, np.where(m, P[:, 0], 1.0), mpp, side=1.0, groove=0.0006, dark=0.25)
        # J-stitch on the figure's left (+x), curving into the centre at the bottom
        fly_len = 0.15 if style != "shorts" else 0.12
        z0 = co[2] - band
        J = [(0.034, z0), (0.034, z0 - fly_len + 0.03), (0.026, z0 - fly_len + 0.008), (0.006, z0 - fly_len)]
        J2 = [(0.028, z0), (0.028, z0 - fly_len + 0.032), (0.021, z0 - fly_len + 0.013), (0.006, z0 - fly_len + 0.006)]
        m = frontish & (P[:, 0] > -0.005) & (P[:, 2] > z0 - fly_len - 0.03) & (P[:, 2] < z0)
        if m.any():
            Q = np.stack([P[m, 0], P[m, 2]], 1)
            sm = _Sub(sub, m)
            for line in ((J, J2) if denim else (J,)):
                d, al = seg_dist(Q, line)
                seam(sm, d, mpp[m], along=al, rows=(0.0,), thread=thread, groove=0.0002, ridge=0.0, dark=0.05)
            # the fly shield's edge is a slight step
            sm.h += 0.0004 * (1.0 - sstep(-0.001, 0.001, Q[:, 0] - 0.034)) * (Q[:, 1] > z0 - fly_len + 0.03)
            sm.commit()
    # back: centre seam (jeans: felled with two rows), and a yoke or darts
    back = front < -0.4
    m = back & (dw > band) & (P[:, 2] > crotch - 0.02)
    if style != "leggings":
        seam(sub, np.where(m, P[:, 0], 1.0), mpp, side=1.0, along=P[:, 2], rows=(0.003, 0.009) if denim else (), thread=thread, dark=0.2)
    if denim and style != "leggings":
        # yoke: deeper at the centre back
        tb = np.angle(np.exp(1j * (th - math.pi)))
        zy = co[2] - band - 0.020 - 0.045 * np.clip(1.0 - np.abs(tb) / 1.4, 0.0, 1.0)
        m = (np.abs(tb) < 1.45) & (P[:, 2] > crotch)
        seam(sub, np.where(m, P[:, 2] - zy, 1.0), mpp, side=1.0, along=th * rr, rows=(0.003, 0.009), thread=thread, dark=0.18)
        # patch pockets on the seat
        for sg in (1.0, -1.0):
            c_th = math.pi - sg * 0.62
            u = np.angle(np.exp(1j * (th - c_th))) * rr
            top = co[2] - band - 0.072
            m = (np.abs(u) < 0.11) & (P[:, 2] < top + 0.02) & (P[:, 2] > top - 0.2) & back
            if not m.any():
                continue
            Q = np.stack([u[m] * -sg, P[m, 2]], 1)
            w2, hh = 0.068, 0.145
            poly = np.array([(-w2, top), (w2, top), (w2 * 0.96, top - hh + 0.025), (0.0, top - hh), (-w2 * 0.96, top - hh + 0.025)])
            sd = poly_sdf(Q, poly)
            sm = _Sub(sub, m)
            sm.h += 0.0007 * (1.0 - sstep(-0.0015, 0.0005, sd))
            seam(sm, sd, mpp[m], side=-1.0, along=Q[:, 0] + Q[:, 1], rows=(0.002, 0.008), thread=thread, groove=0.0003, ridge=0.0, dark=0.3)
            # the pocket's top hem
            seam(sm, np.where(sd < 0.001, Q[:, 1] - (top - 0.016), 1.0), mpp[m], side=1.0, along=Q[:, 0], rows=(0.0,), thread=thread, groove=0.0002, ridge=0.0, dark=0.05)
            sm.commit()
    elif style == "chinos":
        # two welt pockets with a button above each, and darts
        for sg in (1.0, -1.0):
            c_th = math.pi - sg * 0.6
            u = np.angle(np.exp(1j * (th - c_th))) * rr
            zt = co[2] - band - 0.05
            m = back & (np.abs(u) < 0.09) & (np.abs(P[:, 2] - zt) < 0.02)
            if not m.any():
                continue
            sm = _Sub(sub, m)
            box = (np.abs(u[m]) < 0.065)
            sm.h -= 0.0009 * box * gauss(P[m, 2] - zt, 0.0012)
            sm.shade(1.0 - 0.55 * box * gauss(P[m, 2] - zt, 0.0011))
            for dz in (0.004, -0.004):
                k = box * gauss(P[m, 2] - zt - dz, 0.0008)
                sm.shade(1.0 - 0.12 * k)
            sm.commit()
            # button
            bm = back & (np.hypot(u, P[:, 2] - (zt + 0.012)) < 0.008)
            if bm.any():
                sb = _Sub(sub, bm)
                r = np.hypot(u[bm], P[bm, 2] - (zt + 0.012))
                sb.h += 0.0012 * (1.0 - sstep(0.004, 0.0055, r))
                sb.shade(0.8 + 0.1 * (r < 0.0035))
                sb.commit()
    # ---- front pockets: a scooped opening on jeans, a slant on chinos and shorts
    if style != "leggings":
        for sg in (1.0, -1.0):
            m = (front > -0.2) & ((P[:, 0] * sg) > 0) & (dw > band - 0.004) & (dw < band + 0.16)
            if not m.any():
                continue
            u = th[m] * sg * rr[m]          # metres round from the front centre toward the side
            v = dw[m]
            side_u = (math.pi / 2) * float(np.median(rr[m]))
            if denim:
                curve = [(side_u * 0.42, band), (side_u * 0.47, band + 0.035), (side_u * 0.62, band + 0.068), (side_u * 0.86, band + 0.088), (side_u * 1.02, band + 0.09)]
            else:
                curve = [(side_u * 0.48, band), (side_u * 1.02, band + 0.15)]
            Q = np.stack([u, v], 1)
            d, al = seg_dist(Q, curve)
            sm = _Sub(sub, m)
            # the opening is an edge: the facing behind it a little darker (seen into the pocket)
            sd = np.sign((Q[:, 0] - np.interp(Q[:, 1], [c[1] for c in curve], [c[0] for c in curve])))
            seam(sm, d * sd, mpp[m], side=-1.0, along=al, rows=(0.004, 0.010) if denim else (0.006,), thread=thread, groove=0.0006, ridge=0.0006, dark=0.35)
            sm.commit()
    # ---- side seams (out) and inseams, down the legs
    for side, sg in (("Left", 1.0), ("Right", -1.0)):
        m = (P[:, 0] * sg) > 0
        if not m.any():
            continue
        # the plane through the leg's axis, square to the front, on each half
        a = B.B(side + "UpLeg")
        k = B.B(side + "Leg")
        f = B.B(side + "Foot")
        upper = P[:, 2] > k[2]
        y_ax = np.where(upper, np.interp(P[:, 2], [k[2], a[2]], [k[1], a[1]]), np.interp(P[:, 2], [f[2], k[2]], [f[1], k[1]]))
        x_ax = np.where(upper, np.interp(P[:, 2], [k[2], a[2]], [k[0], a[0]]), np.interp(P[:, 2], [f[2], k[2]], [f[0], k[0]]))
        outer = m & (P[:, 0] * sg > x_ax * sg) & (dw > band + 0.003)
        # on the hips, the torso's mid plane takes over from the leg's
        yc = np.where(P[:, 2] > crotch, B.torso_axis_y(P[:, 2]) * sstep(crotch, crotch + 0.1, P[:, 2]) + y_ax * (1 - sstep(crotch, crotch + 0.1, P[:, 2])), y_ax)
        seam(sub, np.where(outer, P[:, 1] - yc, 1.0), mpp, side=1.0, along=P[:, 2], rows=(0.006,) if style == "chinos" else (), thread=thread, dark=0.16)
        inner = m & (P[:, 0] * sg < x_ax * sg) & (P[:, 2] < crotch + 0.005)
        seam(sub, np.where(inner, P[:, 1] - y_ax, 1.0), mpp, side=-1.0, along=P[:, 2], rows=(0.003, 0.009) if denim else (), thread=thread, dark=0.16)
        if style == "chinos":
            # the pressed crease down the front of the leg
            fwd_ok = m & (P[:, 1] < y_ax) & (P[:, 2] < crotch - 0.05)
            dcr = np.where(fwd_ok, P[:, 0] - x_ax, 1.0)
            sub.h += 0.0008 * gauss(dcr, 0.004) * fwd_ok
            sub.shade(1.0 + 0.04 * gauss(dcr, 0.0025) * fwd_ok)
    # ---- the hems at the leg ends
    d = edge_dist(P, L["hems"], "hem")
    depth = {"shorts": 0.03, "leggings": 0.01}.get(style, 0.016)
    rows = (0.012,) if style != "leggings" else (0.006, 0.009)
    hem_band(sub, d, depth, mpp, rows=rows, thread=thread if denim else None, along=th * rr, roll=0.0008 if style != "leggings" else 0.0002)
    if denim:
        # roping: the folded edge wears pale
        sub.lin = sub.lin * (1 - 0.3 * gauss(d, 0.002)[:, None]) + T.srgb_to_lin(srgb(spec.get("fade_color", [120, 150, 190])))[None, :] * 0.3 * gauss(d, 0.002)[:, None]
    sub.commit()


# ---- shirt and jacket ---------------------------------------------------------------------------
def body_uv(B, P, zone):
    """Pattern coordinates that follow the body (metres): round the torso and up it, or round
    each arm and along it past the armhole (so a stripe runs down the body and down the sleeve,
    as cloth is cut)."""
    th, rr = B.azimuth(P)
    u = th * 0.16
    v = P[:, 2].copy()
    for side, sg in (("Left", 1.0), ("Right", -1.0)):
        m = (P[:, 0] * sg) > 0
        s1, rd1, r1, ax1 = B.limb(P[m], side + "Arm", side + "ForeArm")
        s2, rd2, r2, ax2 = B.limb(P[m], side + "ForeArm", side + "Hand")
        on = zone[m] == (1 if side == "Left" else 2)
        fore = s2 > 0.0
        # azimuth round the arm from its front
        fwd = np.array([0.0, -1.0, 0.0])
        rd = np.where(fore[:, None], rd2, rd1)
        axd = np.where(fore[:, None], ax2[None, :], ax1[None, :])
        f = fwd[None, :] - axd * (axd @ fwd)[:, None]
        f /= np.maximum(np.linalg.norm(f, axis=1, keepdims=True), 1e-9)
        lat = np.cross(axd, f)
        az = np.arctan2(np.einsum("ij,ij->i", rd, lat), np.einsum("ij,ij->i", rd, f))
        ua = az * 0.05 + 10.0 * sg
        va = np.where(fore, s2 + np.linalg.norm(B.B(side + "ForeArm") - B.B(side + "Arm")), s1)
        uu, vv = u[m], v[m]
        uu[on] = ua[on]
        vv[on] = -va[on]
        u[m], v[m] = uu, vv
    return u, v


def pattern(pt, B, P, spec, zone):
    """Stripes or a check woven into the cloth (colours sRGB), on body-following coordinates."""
    pat = spec.get("pattern")
    if not pat:
        return
    u, v = body_uv(B, P, zone)
    kind = pat.get("type", "stripes")
    c2 = pat.get("color", [240, 240, 236])
    per = pat.get("period", 0.012)
    w = pat.get("width", 0.35)

    def bars(x, period, width):
        f = (x / period) % 1.0
        e = 0.06
        return sstep(0.0, e, f) * (1.0 - sstep(width, width + e, f))
    if kind == "stripes":
        pt.tint(bars(u, per, w), c2, pat.get("strength", 0.9))
    else:
        # a check: warp and weft bars, darker where they cross (twill-like)
        a = bars(u, per, w)
        b = bars(v, per * pat.get("aspect", 1.0), w)
        pt.tint(np.clip(a + b - a * b, 0, 1), c2, pat.get("strength", 0.7) * 0.6)
        pt.tint(a * b, pat.get("cross", c2), pat.get("strength", 0.7))
        if pat.get("fine"):
            pt.tint(bars(u + per * 0.5, per, 0.08) + bars(v + per * 0.5, per, 0.08), pat["fine"], 0.5)


def paint_shirt(pt, B, X, pidx, parts, L, spec):
    sel_all = np.isin(X.part, pidx)
    shell = np.isin(X.part, [k for k in pidx if parts[k]["part"] == "shell"])
    P = X.P[sel_all]
    sub = _Sub(pt, sel_all)
    zone = X.zone[sel_all].copy()
    cuffs = np.isin(X.part[sel_all], [k for k in pidx if parts[k]["part"] == "cuff"])
    zone[cuffs] = np.where(P[cuffs, 0] > 0, 1, 2)
    pattern(sub, B, P, spec, zone)
    sub.shade(1.0 + 0.04 * fbm(P, 0.025, 2, seed=51))
    sub.commit()
    thread = spec.get("thread")
    paint_top_seams(pt, B, X, shell, L, spec, thread, "shirt")
    P = X.P[shell]
    mpp = X.mpp[shell]
    sub = _Sub(pt, shell)
    # back yoke: across the shoulder blades
    th, rr = B.azimuth(P)
    zy = B.B("neck")[2] - spec.get("yoke", 0.11)
    back = np.cos(th) < -0.15
    seam(sub, np.where(back & (np.abs(P[:, 0]) < abs(B.B("LeftArm")[0]) * 0.95), P[:, 2] - zy, 1.0), mpp, side=1.0, along=P[:, 0], rows=(0.004,), thread=thread)
    # chest pocket on the figure's left
    if spec.get("pocket", True):
        ch = B.B("Spine")
        top = ch[2] + 0.035
        m = (np.cos(th) > 0.3) & (P[:, 0] > 0.02) & (P[:, 0] < 0.2) & (np.abs(P[:, 2] - top + 0.06) < 0.09)
        if m.any():
            Q = np.stack([P[m, 0], P[m, 2]], 1)
            cx = 0.092
            poly = np.array([(cx - 0.055, top), (cx + 0.055, top), (cx + 0.055, top - 0.115), (cx, top - 0.13), (cx - 0.055, top - 0.115)])
            sd = poly_sdf(Q, poly)
            sm = _Sub(sub, m)
            sm.h += 0.0005 * (1.0 - sstep(-0.001, 0.0005, sd))
            seam(sm, sd, mpp[m], side=-1.0, along=Q[:, 0] + Q[:, 1], rows=(0.0025,), thread=thread, groove=0.0003, ridge=0.0, dark=0.22)
            seam(sm, np.where(sd < 0.0, Q[:, 1] - (top - 0.022), 1.0), mpp[m], side=1.0, along=Q[:, 0], rows=(0.0,), thread=thread, groove=0.0002, ridge=0.0, dark=0.06)
            sm.commit()
    # the hems
    d = edge_dist(P, L["hems"], "hem")
    hem_band(sub, d, 0.009, mpp, rows=(0.006,), thread=thread, along=th * rr)
    d = edge_dist(P, L["hems"], "sleeve")
    hem_band(sub, d, 0.009, mpp, rows=(0.006,), thread=thread, along=P[:, 2])
    sub.commit()
    # bands: the collar's edge stitched, the placket's two rows, cuffs edge-stitched
    for k in pidx:
        kind = parts[k]["part"]
        m = X.part == k
        if not m.any() or kind in ("shell", "buttons"):
            continue
        g = X.G[m]
        s = _Sub(pt, m)
        if kind == "placket":
            w = float(spec.get("placket_w", 0.034))
            vv = g[:, 1] - np.median(g[:, 1])
            for off in (-w * 0.5 + 0.004, w * 0.5 - 0.004):
                r = gauss(vv - off, np.maximum(0.0006, 0.6 * X.mpp[m]))
                s.h -= 0.00018 * r
                if thread:
                    s.tint(r, thread, 0.8)
                else:
                    s.shade(1.0 - 0.15 * r)
        else:
            # along each band's profile the stitch rows sit a few mm in from its folded edges
            vmax = float(g[:, 1].max())
            for off in (0.004, vmax - 0.006):
                r = gauss(g[:, 1] - off, np.maximum(0.0006, 0.6 * X.mpp[m]))
                s.h -= 0.00015 * r
                s.shade(1.0 - 0.12 * r)
        s.commit()


def paint_jacket(pt, B, X, pidx, parts, L, spec):
    sel_all = np.isin(X.part, pidx)
    shell = np.isin(X.part, [k for k in pidx if parts[k]["part"] == "shell"])
    thread = spec.get("thread")
    sub = _Sub(pt, sel_all)
    sub.shade(1.0 + 0.05 * fbm(X.P[sel_all], 0.03, 2, seed=61))
    sub.commit()
    paint_top_seams(pt, B, X, shell, L, spec, thread, "shirt")
    P = X.P[shell]
    mpp = X.mpp[shell]
    sub = _Sub(pt, shell)
    th, rr = B.azimuth(P)
    # welt pockets: a slanted slit each side at the waist, bound edges
    hip = B.B("LeftUpLeg")[2]
    for sg in (1.0, -1.0):
        m = ((P[:, 0] * sg) > 0) & (np.cos(th) > 0.0) & (P[:, 2] > hip - 0.02) & (P[:, 2] < hip + 0.22)
        if not m.any():
            continue
        Q = np.stack([P[m, 0] * sg, P[m, 2]], 1)
        a = np.array([0.075, hip + 0.17])
        b = np.array([0.125, hip + 0.03])
        d, al = seg_dist(Q, [a, b])
        sm = _Sub(sub, m)
        sm.h -= 0.0008 * gauss(d, 0.0012)
        sm.shade(1.0 - 0.5 * gauss(d, 0.0011))
        sm.h += 0.0004 * gauss(d - 0.006, 0.004)
        seam(sm, d - 0.009, mpp[m], side=1.0, along=al, rows=(0.0,), thread=thread, groove=0.0001, ridge=0.0, dark=0.03)
        sm.commit()
    d = edge_dist(P, L["hems"], "")
    sub.h -= 0.0003 * gauss(d - 0.006, 0.001)
    sub.commit()
    for k in pidx:
        kind = parts[k]["part"]
        m = X.part == k
        if not m.any():
            continue
        g = X.G[m]
        s = _Sub(pt, m)
        if kind in ("band", "cuff"):
            # rib: wales across the band
            rib = np.cos(TAU * g[:, 0] / 0.0026)
            s.h += 0.0003 * rib
            s.shade(0.95 + 0.04 * rib)
        elif kind == "zip":
            teeth = np.cos(TAU * g[:, 0] / 0.0032)
            s.h += 0.0005 * teeth
            s.shade(0.85 + 0.15 * (teeth > 0))
        elif kind == "zip_tape":
            s.shade(0.9 + 0.05 * np.cos(TAU * g[:, 0] / 0.001))
        elif kind == "collar":
            vmax = float(g[:, 1].max())
            r = gauss(g[:, 1] - vmax * 0.42, np.maximum(0.0006, 0.6 * X.mpp[m]))
            s.shade(1.0 - 0.12 * r)
        s.commit()


# ---- entry point ----------------------------------------------------------------------------------
def paint(name, size):
    """(albedo sRGB float (size, size, 3), coverage, normal (size, size, 3) tangent space,
    coverage) for every own-garment texel of `name`, or None when it has none."""
    work = C.work(name, "own.npz")
    if not os.path.exists(work):
        return None
    Z = np.load(work)
    parts = json.load(open(C.work(name, "own_parts.json")))
    meta = json.load(open(C.work(name, "garments.json")))
    cfg = C.character(name)
    outfit = cfg.get("outfit", [])
    B = Body(meta)
    X = Texels(Z, size)
    n = len(X.P)
    lin = np.zeros((n, 3))
    H = np.zeros(n)
    by_gid = {}
    for k, prt in enumerate(parts):
        by_gid.setdefault(prt["gid"], []).append(k)
    landmarks = {G["gid"]: G for G in meta["garments"]}
    for gid, pidx in by_gid.items():
        spec = dict(landmarks[gid]["spec"])
        if gid < len(outfit):
            spec.update(outfit[gid])     # colours from today's config
        color = spec.get("color", [128, 128, 128])
        selg = np.isin(X.part, pidx)
        pt = Paint(n, color)
        L = landmarks[gid]
        shell = np.isin(X.part, [k for k in pidx if parts[k]["part"] == "shell"])
        kind = spec["type"]
        if kind == "tee":
            collar = np.isin(X.part, [k for k in pidx if parts[k]["part"] == "collar_rib"])
            paint_tee(pt, B, X, shell, collar, L, spec)
        elif kind == "trousers":
            paint_trousers(pt, B, X, shell, L, spec, color)
        elif kind in PAINTERS:
            PAINTERS[kind](pt, B, X, pidx, parts, L, spec)
        # "other" parts (buttons, zips) keep their own colour
        for k in pidx:
            if parts[k]["region"] == "other":
                m = X.part == k
                c = spec.get(parts[k]["part"] + "_color", spec.get("trim_color", [232, 228, 218] if kind == "shirt" else [40, 40, 42]))
                pt.lin[m] = T.srgb_to_lin(srgb(c))
        lin[selg] = pt.lin[selg]
        H[selg] = pt.h[selg]
    # ambient occlusion (rest pose, against the whole character), as the library clothes' AO maps
    k = cfg.get("garment_ao", 0.55)
    lin *= (1.0 - k * (1.0 - np.clip(X.ao, 0.0, 1.0)))[:, None]
    alb = np.zeros((size, size, 3), np.float32)
    alb[X.iy, X.ix] = T.lin_to_srgb(np.clip(lin, 0.0, 1.0))
    # normals from the height field's slope at each texel's metric scale
    Himg = np.zeros((size, size), np.float64)
    Himg[X.iy, X.ix] = H
    Mimg = np.zeros((size, size), np.float64)
    Mimg[X.iy, X.ix] = X.mpp
    Himg = T.dilate(Himg, X.cov, 3)
    Mimg = T.dilate(Mimg, X.cov, 3)
    gx = (np.roll(Himg, -1, 1) - np.roll(Himg, 1, 1)) * 0.5 / np.maximum(Mimg, 1e-6)
    gy = (np.roll(Himg, 1, 0) - np.roll(Himg, -1, 0)) * 0.5 / np.maximum(Mimg, 1e-6)
    nrm = np.stack([-gx, -gy, np.ones_like(gx)], -1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    print("PAINT %s: %d texels over %d garments, height %.2f..%.2f mm" % (name, n, len(by_gid), H.min() * 1000, H.max() * 1000))
    return alb, X.cov, nrm.astype(np.float32), X.cov


PAINTERS = {"shirt": paint_shirt, "jacket": paint_jacket}
