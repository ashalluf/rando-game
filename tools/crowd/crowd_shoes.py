# Crowd shoes (crowd-closeup-3): real soles, laces and eyelets on the MakeHuman library shoes.
#
# The pack's shoes are a smooth closed upper with the sole, the laces and the stitching only in
# the photo, decimated to ~650 triangles a shoe: from two metres every pair read as one slab.
# Called from build_character.py after the garments, on the bound shoe object, this adds:
#  - a SOLE: a band swept round the shoe's outline at the ground, standing a few millimetres
#    proud of the upper with a real sidewall (midsole, a groove, the outsole's edge; a boot's
#    welt; a dress shoe's leather edge with a stacked heel), its inner lip tucked inside the
#    upper - the upper's own photographed sole is hidden behind it
#  - an OUTSOLE under it (seen at every toe-off): a fan over the band's inner ring, the tread
#    painted (sneaker waves, boot lugs, a dress shoe's smooth leather and heel lift)
#  - LACES criss-crossing the throat from eyelet to eyelet (flat 4-sided ribbons arched off the
#    upper) and a bow - up the shaft on a boot - and metal or plastic EYELETS
# all as "own" parts (region "other": never recoloured, like the shoes), painted texel by texel
# by shoe_paint.py through garment_paint.py, weighted from the shoe itself so they bend with the
# foot exactly. Everything is placed from the shoe mesh and the foot bones, so any of the six
# pack shoes (and any build) gets it; `shoe` in a character's config overrides the colours.
import json
import math

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

import crowd_common as C
import garments as G

GID = 90                  # the shoes' garment id (past every outfit's)
STYLES = {"shoes01": "derby", "shoes02": "sneaker", "shoes03": "boot", "shoes04": "loafer",
          "shoes05": "sneaker", "shoes06": "sneaker"}
# Per style: sole height at the heel and at the toe (m), how far the sidewall stands proud of the
# upper (welt), the lacing (rows, the span along the shoe from the toe as fractions of its length,
# the half spacing of an eyelet pair at the first and last row), and whether the top rows climb
# a boot's shaft.
SOLE = {
    "sneaker": {"h": (0.030, 0.019), "welt": 0.0030, "rows": 5, "span": (0.31, 0.57), "half": (0.0085, 0.0125), "shaft": 0},
    "boot": {"h": (0.032, 0.024), "welt": 0.0050, "rows": 6, "span": (0.34, 0.60), "half": (0.0095, 0.0135), "shaft": 2},
    "derby": {"h": (0.026, 0.011), "welt": 0.0032, "rows": 4, "span": (0.40, 0.58), "half": (0.0085, 0.0115), "shaft": 0},
    "loafer": {"h": (0.024, 0.010), "welt": 0.0026, "rows": 0, "span": (0, 0), "half": (0, 0), "shaft": 0},
}
# Per pack shoe: sole (midsole / edge), outsole (tread and its edge), lace, eyelet colours (sRGB).
COLORS = {
    "shoes01": {"sole": [58, 38, 26], "outsole": [44, 30, 22], "lace": [62, 42, 30], "eyelet": [48, 44, 40]},
    "shoes02": {"sole": [226, 224, 218], "outsole": [132, 98, 64], "lace": [176, 176, 174], "eyelet": [196, 196, 194]},
    "shoes03": {"sole": [40, 34, 30], "outsole": [32, 29, 27], "lace": [92, 68, 46], "eyelet": [70, 64, 56], "welt": [78, 56, 38]},
    "shoes04": {"sole": [30, 26, 24], "outsole": [26, 22, 20], "lace": [30, 28, 26], "eyelet": [40, 40, 40]},
    "shoes05": {"sole": [224, 222, 216], "outsole": [74, 74, 76], "lace": [240, 238, 232], "eyelet": [228, 226, 220]},
    "shoes06": {"sole": [222, 220, 214], "outsole": [54, 60, 74], "lace": [36, 44, 74], "eyelet": [40, 48, 78]},
}
N_RING = 44               # points round a sole
LACE_W, LACE_T = 0.0068, 0.0017
BINS = 72


class _Ctx:
    """What garments.mesh_with_local_uv / new_mesh_object need of their context."""

    def __init__(self, body, name):
        self.name = name

        class _B:
            pass
        self.body = _B()
        self.body.obj = body
        self.body.mwi = body.matrix_world.inverted()


def _smooth_loop(a, passes):
    a = np.asarray(a, np.float64)
    for _ in range(passes):
        a = 0.25 * np.roll(a, 1, 0) + 0.5 * a + 0.25 * np.roll(a, -1, 0)
    return a


def _fill(vals):
    """Missing (nan) entries of a closed loop filled by linear interpolation round it."""
    v = np.asarray(vals, np.float64)
    ok = ~np.isnan(v)
    if ok.all() or not ok.any():
        return np.nan_to_num(v)
    idx = np.arange(len(v))
    good = idx[ok]
    ext = np.concatenate([good - len(v), good, good + len(v)])
    vv = np.concatenate([v[ok]] * 3)
    return np.interp(idx, ext, vv)


class Side:
    """One shoe: its frame (centre, forward f toward the toe, lateral, up), its outline at the
    ground and the BVH to project onto."""

    def __init__(self, V, F, sg, bvh, foot, toe):
        self.sg = sg
        m = (V[:, 0] * sg) > 0
        S = V[m]
        self.zmin = float(S[:, 2].min())
        f = np.array([toe[0] - foot[0], toe[1] - foot[1], 0.0])
        f /= np.linalg.norm(f)
        self.f = f
        self.lat = np.array([-f[1], f[0], 0.0])
        low = S[S[:, 2] < self.zmin + 0.045]
        along = low[:, :2] @ f[:2]
        across = low[:, :2] @ self.lat[:2]
        a0, a1 = along.min(), along.max()
        c0, c1 = across.min(), across.max()
        self.half_len = 0.5 * (a1 - a0)
        self.half_w = 0.5 * (c1 - c0)
        cx = f[:2] * (0.5 * (a0 + a1)) + self.lat[:2] * (0.5 * (c0 + c1))
        self.c = np.array([cx[0], cx[1], self.zmin])
        self.bvh = bvh
        self.S = S
        # outline: per angle bin (in the shoe's ellipse metric) the outermost low vertex
        q = np.stack([(low[:, :2] - cx) @ f[:2] / self.half_len, (low[:, :2] - cx) @ self.lat[:2] / self.half_w], 1)
        ang = np.arctan2(q[:, 1], q[:, 0])
        rad = np.linalg.norm(q, axis=1)
        b = ((ang + math.pi) / (2 * math.pi) * BINS).astype(int) % BINS
        rmax = np.full(BINS, np.nan)
        zb = np.full(BINS, np.nan)
        for k in range(BINS):
            mk = b == k
            if mk.any():
                rmax[k] = rad[mk].max()
                outer = mk & (rad > rad[mk].max() - 0.25)
                zb[k] = low[outer, 2].min()
        # smoothed hard: the outermost vertex of each bin jitters, and the sole's rim waved
        rmax = _smooth_loop(_fill(rmax), 7)
        zb = _smooth_loop(_fill(zb), 4)
        # resample to N_RING points evenly spaced along the outline
        th = (np.arange(BINS) + 0.5) / BINS * 2 * math.pi - math.pi
        pts = np.stack([cx[0] + (f[0] * np.cos(th) * self.half_len + self.lat[0] * np.sin(th) * self.half_w) * rmax,
                        cx[1] + (f[1] * np.cos(th) * self.half_len + self.lat[1] * np.sin(th) * self.half_w) * rmax], 1)
        seg = np.linalg.norm(np.roll(pts, -1, 0) - pts, axis=1)
        s = np.concatenate([[0.0], np.cumsum(seg)])
        total = s[-1]
        t = np.linspace(0.0, total, N_RING, endpoint=False)
        loopx = np.concatenate([pts[:, 0], pts[:1, 0]])
        loopy = np.concatenate([pts[:, 1], pts[:1, 1]])
        loopz = np.concatenate([zb, zb[:1]])
        self.ring = np.stack([np.interp(t, s, loopx), np.interp(t, s, loopy), np.interp(t, s, loopz)], 1)
        self.perim = float(total)
        # outward normals (2D) from the loop's tangent; the loop runs anticlockwise or clockwise,
        # so the sign is set from the centre
        tan = np.roll(self.ring[:, :2], -1, 0) - np.roll(self.ring[:, :2], 1, 0)
        n = np.stack([tan[:, 1], -tan[:, 0]], 1)
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
        out = self.ring[:, :2] - cx
        n *= np.sign((n * out).sum(1, keepdims=True))
        self.n = np.concatenate([n, np.zeros((N_RING, 1))], 1)
        self.toe = self.c + self.f * self.half_len
        self.heel = self.c - self.f * self.half_len

    def t_along(self, p):
        """0 at the heel, 1 at the toe."""
        return float(np.clip(((np.asarray(p) - self.heel)[:2] @ self.f[:2]) / (2 * self.half_len), 0.0, 1.0))

    def cast(self, p, d, reach=0.12):
        """The upper's surface from outside along d (unit) toward p: (point, outward normal)."""
        d = Vector(d).normalized()
        o = Vector(p) - d * reach
        hit = self.bvh.ray_cast(o, d, reach * 2.0)
        if hit[0] is None:
            return None, None
        nrm = hit[1] if hit[1].dot(-d) > 0 else -hit[1]
        return np.array(hit[0]), np.array(nrm)

    def down(self, xy, reach=0.3):
        """The top of the upper under (x, y)."""
        p, n = self.cast((xy[0], xy[1], self.zmin + 0.01), (0, 0, -1), reach)
        return p, n


def _sole_height(st, side, t):
    h0, h1 = SOLE[st]["h"]
    if st in ("derby", "loafer"):
        # a heel block under the back quarter, the forepart sole thin, a breast in between
        k = 1.0 - G.smoothstep(0.26, 0.32, t)
    else:
        k = 1.0 - G.smoothstep(0.18, 0.78, t)
    return h1 + (h0 - h1) * k


def build_sole(ctx, sides, st, asset):
    """The sole bands (one object, both shoes) and the outsoles (another)."""
    sp = SOLE[st]
    w = sp["welt"]
    verts, faces, fuv = [], [], []
    cverts, cfaces, cfuv = [], [], []
    land = []
    u_base = 0.0
    for sd in sides:
        rows = []
        ring_bottom = []
        u = u_base   # the two shoes side by side in u (overlapping, they would share texels)
        for i in range(N_RING + 1):
            k = i % N_RING
            p = sd.ring[k]
            n = sd.n[k]
            if i:
                u += float(np.linalg.norm(sd.ring[k][:2] - sd.ring[i - 1][:2]))
            t = sd.t_along(p)
            h = _sole_height(st, sd, t)
            # where the upper actually is at the sole's top: its inner lip goes 3 mm inside it
            hp, _hn = sd.cast((p[0], p[1], p[2] + h), (-n[0], -n[1], 0.0), 0.08)
            ru = 0.0 if hp is None else float((hp[:2] - p[:2]) @ n[:2])
            ru = min(max(ru, -0.012), 0.0)
            # (outward, up, what) from the outline point at the ground, from the inner bottom to
            # the lip: "u" underside, "s" sidewall, "l" the ledge onto the upper
            if st == "boot":
                prof = [(-0.010, 0.0, "u"), (w - 0.0018, 0.0, "s"), (w, 0.004, "s"), (w + 0.0008, 0.010, "s"),
                        (w + 0.0004, h - 0.009, "s"), (w + 0.0016, h - 0.006, "s"), (w + 0.0012, h - 0.001, "s"),
                        (ru - 0.003, h + 0.0012, "l")]
            elif st == "sneaker":
                prof = [(-0.010, 0.0, "u"), (w - 0.0016, 0.0, "s"), (w, 0.0036, "s"), (w + 0.0014, h * 0.5, "s"),
                        (w + 0.0004, h - 0.0018, "s"), (w * 0.4, h + 0.0006, "l"), (ru - 0.003, h + 0.0014, "l")]
            else:
                prof = [(-0.010, 0.0, "u"), (w - 0.0012, 0.0, "s"), (w, 0.0025, "s"), (w + 0.0004, h - 0.0016, "s"),
                        (w * 0.5, h + 0.0004, "l"), (ru - 0.003, h + 0.0010, "l")]
            # v (metres): the height up the sidewall, below 0 across the underside, past the
            # sole's height (h) across the ledge - what shoe_paint.py paints by
            row = []
            v_prev = None
            for j, (r, z, tag) in enumerate(prof):
                if tag == "u":
                    v = -(prof[1][0] - r)
                elif tag == "s":
                    v = z
                else:
                    v = v_prev + math.hypot(r - prof[j - 1][0], z - prof[j - 1][1])
                v = max(v, v_prev + 1e-4) if v_prev is not None else v
                v_prev = v
                q = p + n * r + np.array([0, 0, z])
                row.append((len(verts), (u, v)))
                verts.append(tuple(q))
            rows.append(row)
            if i < N_RING:
                ring_bottom.append(np.array(verts[row[0][0]]))
        for i in range(N_RING):
            a, b = rows[i], rows[i + 1]
            for j in range(len(a) - 1):
                faces.append((a[j][0], a[j + 1][0], b[j + 1][0], b[j][0]))
                fuv.append([a[j][1], a[j + 1][1], b[j + 1][1], b[j][1]])
        # outsole: a fan from the middle of the inner bottom ring
        rb = np.array(ring_bottom)
        base = len(cverts)
        mid = rb.mean(0)
        mid[2] = rb[:, 2].min()
        for q in rb:
            cverts.append(tuple(q))
        cverts.append(tuple(mid))
        for i in range(N_RING):
            a, b = base + i, base + (i + 1) % N_RING
            cfaces.append((a, b, base + N_RING))
            cfuv.append([tuple(cverts[a][:2]), tuple(cverts[b][:2]), tuple(cverts[base + N_RING][:2])])
        u_base = u + 0.05
        land.append({"sg": sd.sg, "heel": list(sd.heel), "toe": list(sd.toe), "f": list(sd.f), "zmin": sd.zmin})
    sole = G.mesh_with_local_uv(ctx, "shoe_sole", verts, faces, fuv)
    outsole = G.mesh_with_local_uv(ctx, "shoe_outsole", cverts, cfaces, cfuv)
    return sole, outsole, land


def _ribbon(verts, faces, fuv, pts, nrms, u0):
    """A flat lace along pts (4-sided, a flattened diamond); u metres along it, v round it."""
    u = u0
    sec = [(-0.5, 0.0), (0.0, 0.5), (0.5, 0.0), (0.0, -0.5)]
    rows = []
    for i, (p, n) in enumerate(zip(pts, nrms)):
        tng = pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]
        tng = tng / max(np.linalg.norm(tng), 1e-9)
        b = np.cross(tng, n)
        b /= max(np.linalg.norm(b), 1e-9)
        n2 = np.cross(b, tng)
        if i:
            u += float(np.linalg.norm(p - pts[i - 1]))
        row = []
        for k, (wv, hv) in enumerate(sec):
            row.append((len(verts), (u, k * 0.0025)))
            verts.append(tuple(p + b * (wv * LACE_W) + n2 * (hv * LACE_T)))
        rows.append(row)
    for i in range(len(rows) - 1):
        for k in range(4):
            k2 = (k + 1) % 4
            a, b2, c, d = rows[i][k], rows[i][k2], rows[i + 1][k2], rows[i + 1][k]
            v2 = b2[1][1] if k2 else 0.01
            quad = [a, (b2[0], (b2[1][0], v2)), (c[0], (c[1][0], v2)), d]
            # every face out from the lace's own centre line (it is an open tube: no recalc)
            P = [np.array(verts[q[0]]) for q in quad]
            nrm = np.cross(P[1] - P[0], P[2] - P[0])
            if float(nrm @ (sum(P) / 4.0 - 0.5 * (pts[i] + pts[i + 1]))) < 0.0:
                quad = quad[::-1]
            faces.append(tuple(q[0] for q in quad))
            fuv.append([q[1] for q in quad])
    return u


def build_laces(ctx, sides, st):
    """Laces, bows and eyelets of every laced shoe; (laces, eyelets, marks) or (None, None, {})."""
    sp = SOLE[st]
    if not sp["rows"]:
        return None, None, {}
    verts, faces, fuv = [], [], []
    ec, en = [], []
    marks = {"eyelets": [], "knots": []}
    for sd in sides:
        L = 2 * sd.half_len
        rows = []
        nrow = sp["rows"]
        for i in range(nrow):
            tt = i / max(nrow - 1, 1)
            shaft = sp["shaft"] and i >= nrow - sp["shaft"]
            s = sp["span"][0] + (sp["span"][1] - sp["span"][0]) * tt
            half = sp["half"][0] + (sp["half"][1] - sp["half"][0]) * tt
            ctr = sd.toe - sd.f * (s * L)
            pair = []
            for lat_s in (-1.0, 1.0):
                xy = ctr[:2] + sd.lat[:2] * (lat_s * half)
                if shaft:
                    # up the front of a boot's shaft: cast back at the front from ahead
                    k = i - (nrow - sp["shaft"]) + 1
                    top = sd.S[:, 2].max()
                    z = sd.zmin + 0.085 + (top - sd.zmin - 0.105) * k / sp["shaft"]
                    base = sd.toe - sd.f * (sp["span"][1] * L) + sd.lat * (lat_s * half)
                    p, n = sd.cast((base[0], base[1], z), -sd.f, 0.12)
                else:
                    p, n = sd.down(xy)
                if p is None:
                    p, n = None, None
                pair.append((p, n))
            if pair[0][0] is None or pair[1][0] is None:
                continue
            rows.append((pair, shaft))
        if len(rows) < 2:
            continue
        for pair, _shaft in rows:
            for p, n in pair:
                ec.append(p + n * 0.0002)
                en.append(n)
                marks["eyelets"].append(list(p))

        def project(q, nguess):
            p, n = sd.cast(q, -nguess, 0.06)
            if p is None:
                return q, nguess
            return p, n

        def lace(a, na, b, nb, lift):
            pts, nrs = [], []
            for k in range(5):
                t = k / 4
                q = a * (1 - t) + b * t
                ng = na * (1 - t) + nb * t
                ng /= max(np.linalg.norm(ng), 1e-9)
                p, n = project(q, ng)
                arch = math.sin(math.pi * t)
                pts.append(p + n * (0.0010 + (0.0030 + lift) * arch))
                nrs.append(n)
            return np.array(pts), np.array(nrs)
        u = 0.0
        segs = [(rows[0][0][0], rows[0][0][1], 0.0)]
        for i in range(len(rows) - 1):
            segs.append((rows[i][0][0], rows[i + 1][0][1], 0.0012 * (i % 2)))
            segs.append((rows[i][0][1], rows[i + 1][0][0], 0.0012 * ((i + 1) % 2)))
        for (pa, na), (pb, nb), lift in segs:
            pts, nrs = lace(pa, na, pb, nb, lift)
            u = _ribbon(verts, faces, fuv, pts, nrs, u) + 0.02
        # the bow over the top pair: two loops lying back toward the toe and two tails
        (pa, na), (pb, nb) = rows[-1][0]
        kn = (na + nb)
        kn /= np.linalg.norm(kn)
        knot = (pa + pb) * 0.5 + kn * 0.005
        marks["knots"].append(list(knot))
        fwd = sd.f.copy()
        if rows[-1][1]:
            # on a boot's shaft the loops hang down its front
            fwd = np.array([0.0, 0.0, -1.0])
        latv = sd.lat
        for s in (-1.0, 1.0):
            loop = []
            for k in range(7):
                a = 2 * math.pi * k / 6
                c = 0.5 - 0.5 * math.cos(a)
                loop.append(knot + latv * (s * 0.014 * c) + fwd * (0.010 * math.sin(a) + 0.004 * c) + kn * (0.0035 * c))
            u = _ribbon(verts, faces, fuv, np.array(loop), np.array([kn] * len(loop)), u) + 0.02
            tail = []
            for k in range(4):
                t = k / 3
                q = knot + latv * (s * (0.005 + 0.010 * t)) + fwd * (0.004 + 0.018 * t) - kn * (0.010 * t * t)
                p, n = project(q, kn)
                if float((p - q) @ kn) > 0.0:
                    q = p + n * 0.0015
                tail.append(q)
            u = _ribbon(verts, faces, fuv, np.array(tail), np.array([kn] * len(tail)), u) + 0.02
    if not faces:
        return None, None, {}
    laces = G.mesh_with_local_uv(ctx, "shoe_laces", verts, faces, fuv)
    # a sneaker's eyelets are punched in its upper (the photo has them); boots and dress shoes
    # get metal ones
    eyelets = G.discs(ctx, "shoe_eyelets", ec, en, 0.0026, 0.0007, seg=5) if ec and st != "sneaker" else None
    return laces, eyelets, marks


def _weights_from(obj, src):
    for g in src.vertex_groups:
        if g.name not in obj.vertex_groups:
            obj.vertex_groups.new(name=g.name)
    m = obj.modifiers.new("DT", 'DATA_TRANSFER')
    m.object = src
    m.use_vert_data = True
    m.data_types_verts = {'VGROUP_WEIGHTS'}
    m.vert_mapping = 'POLYINTERP_NEAREST'
    m.layers_vgroup_select_src = 'ALL'
    m.layers_vgroup_select_dst = 'NAME'
    G.activate(obj)
    bpy.ops.object.modifier_apply(modifier=m.name)


def build(body, arm, cfg, name, shoe_obj):
    """The soles, outsoles, laces and eyelets for `shoe_obj` (a MakeHuman pack shoe on the bound
    rig); returns the new objects (marked crowd_own, gid GID) and writes their landmarks into
    WORK/<name>/garments.json for the painter. [] when the shoe is not one we know."""
    asset = shoe_obj.name.split(".")[-1]
    st = STYLES.get(asset)
    if st is None:
        print("CROWD shoes: %s is not a known pack shoe, left as it is" % asset)
        return []
    ctx = _Ctx(body, name)
    mw = shoe_obj.matrix_world
    V = np.array([tuple(mw @ v.co) for v in shoe_obj.data.vertices])
    F = [tuple(p.vertices) for p in shoe_obj.data.polygons]
    bvh = BVHTree.FromPolygons([tuple(v) for v in V], F)
    amw = arm.matrix_world
    sides = []
    for side, sg in (("Left", 1.0), ("Right", -1.0)):
        foot = np.array(amw @ arm.data.bones[side + "Foot"].head_local)
        toe = np.array(amw @ arm.data.bones[side + "ToeBase"].tail_local)
        sides.append(Side(V, F, sg, bvh, foot, toe))
    sole, outsole, land = build_sole(ctx, sides, st, asset)
    laces, eyelets, marks = build_laces(ctx, sides, st)
    objs = [sole, outsole] + [o for o in (laces, eyelets) if o is not None]
    for o in objs:
        part = o.name.split(".")[-1].replace("shoe_", "")
        if part in ("sole", "outsole"):
            G.fix_winding(o, (lambda c, sides=sides: _centre_of(sides, c)))
        G.triangulate(o)
        _weights_from(o, shoe_obj)
        o["crowd_px_per_m"] = G.PX_PER_M * (1.6 if part in ("laces", "eyelets") else 1.0)
        G.mark(o, "shoes", part, "other", "jersey", GID)
    colors = dict(COLORS.get(asset, COLORS["shoes05"]))
    colors.update(cfg.get("shoe", {}))
    L = {"type": "shoes", "gid": GID, "style": st, "asset": asset, "sides": land, "marks": marks,
         "parts": [o.name for o in objs], "spec": dict({"type": "shoes", "style": st}, **colors),
         "sole": SOLE[st]}
    path = C.work(name, "garments.json")
    try:
        meta = json.load(open(path))
    except (OSError, ValueError):
        bones = {b.name: list(amw @ b.head_local) for b in arm.data.bones}
        meta = {"garments": [], "bones": bones, "crotch_z": 0.0}
    meta["garments"] = [g for g in meta["garments"] if g.get("gid") != GID] + [L]
    with open(path, "w") as f:
        json.dump(meta, f)
    print("CROWD shoes (%s, %s): %s" % (asset, st, ", ".join("%s %d tris" % (o.name, G.tris(o)) for o in objs)))
    return objs


def _centre_of(sides, c):
    """Inside the shoe nearest c: its centre line at the sole's middle height (fix_winding)."""
    sd = sides[0] if c[0] * sides[0].sg > 0 else sides[1]
    rel = np.array(c) - sd.c
    along = float(rel[:2] @ sd.f[:2])
    along = max(min(along, sd.half_len * 0.8), -sd.half_len * 0.8)
    p = sd.c + sd.f * along
    return (p[0], p[1], sd.zmin + 0.012)
