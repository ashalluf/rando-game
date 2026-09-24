# Step: every texture of the hero, in plain python3 (numpy + PIL), from the CC0 MakeHuman sources
# and the texture-space arrays texspace.py wrote (the rest-pose surface point under every texel).
#
# Painted as functions of the 3D body rather than of the UV layout, so nothing stretches across a
# seam and every feature sits where the anatomy is:
#  skin     warmer, fuller complexion zones (flushed cheeks, nose and ears, blue-grey beard shadow,
#           darker sockets), the scalp under the hair taken to the hair colour, ambient occlusion;
#           a wrinkle normal map (forehead, glabella, crow's feet, under the eyes, nasolabial
#           folds, lips, neck rings, knuckles); roughness zones (oily T-zone, wet lips, matte
#           stubble); a mask for the game shader (stubble, thinness for transmission, cavity,
#           oil) and a tiling micro-detail (pores and crosshatch, plus stubble hairs in alpha)
#  suit     fold normal maps for a straight AND a closed joint (folds.py) and the per-joint mask
#           the game blends them by; occlusion; a tiling velour pile; the rib knit
#  hair     a strand atlas: eight clump columns, dense to fly-away, tips staggered and tapered
#  shoes    white leather with a rubber cupsole and stitched midsole, toe-cap perforations,
#           stitched eyestays and eyelets under the laces; the lace and tongue atlas
#  watch    a sunburst dial with a printed minute track (the indices and hands are geometry)
# glTF-material maps go to TEX (finalize.py embeds them in hero.glb); the extra maps the game
# shaders read go straight to assets/models/hero_x_*.png. Writes TEX/textures.json.
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import folds  # noqa: E402
import texlib as T  # noqa: E402

cfg = common.config()
look = cfg.get("look", {})
rng = np.random.default_rng(7)
D = common.MPFB_DATA
L = json.load(open(common.work("landmarks.json")))
HL = json.load(open(common.work("hairline.json")))
TEX = common.TEX
X = common.ASSETS
specs = {}


def tex(name):
    return os.path.join(TEX, name)


def extra(name):
    return os.path.join(X, name)


def load_src(p, mode="RGB"):
    return np.asarray(Image.open(os.path.join(D, p)).convert(mode)).astype(np.float32) / 255.0


def hairline_z(az):
    a = np.array([q[0] for q in HL["hairline"]])
    z = np.array([q[1] for q in HL["hairline"]])
    return np.interp(np.abs(az), a, z)


def azimuth(p):
    c = HL["centre"]
    return np.degrees(np.arctan2(p[:, 0], -(p[:, 1] - c[1])))


def v3(k):
    return np.asarray(L[k], np.float64)


def splat(img, cx, cy, rad, fn):
    """Apply fn(dx, dy, window) to a (2 rad + 1)^2 window of a tiling image round (cx, cy)."""
    n = img.shape[0]
    ix = np.arange(int(cx) - rad, int(cx) + rad + 1)
    iy = np.arange(int(cy) - rad, int(cy) + rad + 1)
    dx = (ix - cx)[None, :].astype(np.float32)
    dy = (iy - cy)[:, None].astype(np.float32)
    w = np.ix_(iy % n, ix % n)
    img[w] = fn(dx, dy, img[w])


# =================================================================================================
# SKIN
# =================================================================================================
SKIP = os.environ.get("HERO_TEX_SKIP", "").split(",")
# The skin is most of this step's time; HERO_TEX_SKIP=skin reuses the last skin maps.
specs.update(skin_base="hero_skin_diffuse.jpg", skin_normal="hero_skin_normal.jpg", skin_rough="hero_skin_roughness.png")
if "skin" not in SKIP:
    S = T.load_txs(common.work("txs_skin.npz"))
    cov = S["cov"]
    idx = np.nonzero(cov)
    Pc = S["P"][idx].astype(np.float64)
    Nc = S["N"][idx].astype(np.float64)
    x, y, z = Pc[:, 0], Pc[:, 1], Pc[:, 2]
    ax = np.abs(x)
    lips = S["a_lips"][idx]
    nails = np.clip(S["a_fingernails"][idx] + S["a_toenails"][idx], 0, 1)
    ears = S["a_ears"][idx]
    vao = np.clip(S["a_ao"][idx], 0, 1)
    eye_l, eye_r = v3("eye_l"), v3("eye_r")
    eye_z = (eye_l[2] + eye_r[2]) / 2
    eye_x = (abs(eye_l[0]) + abs(eye_r[0])) / 2
    eye_y = (eye_l[1] + eye_r[1]) / 2
    lc = v3("lips_center")
    lip_top, lip_bot, lip_w = L["lips_top"], L["lips_bottom"], L["lips_halfwidth"]
    ear_c = v3("ear_center")
    face_y = L["face_front_y"]
    head = z > lip_bot - 0.055
    front = Nc[:, 1] < -0.25
    ss = T.smoothstep

    # --- region masks -------------------------------------------------------------------------------
    # Beard: a moustache over the upper lip inside the mouth's width, then from the mouth corners up
    # along the cheek to the sideburn in front of the ear; fades down the throat.
    t_ = np.clip((ax - (lip_w + 0.004)) / max(ear_c[0] - 0.012 - (lip_w + 0.004), 1e-3), 0, 1)
    cheek_line = (lc[2] + 0.006) + t_ * (ear_c[2] + 0.004 - (lc[2] + 0.006))
    line = np.where(ax < lip_w + 0.004, lip_top + 0.008, cheek_line)
    beard = (1 - ss(ear_c[1] - 0.018, ear_c[1] + 0.006, y)) * (1 - ss(line - 0.006, line + 0.008, z)) \
        * ss(lip_bot - 0.085, lip_bot - 0.045, z) * (1 - ss(0.2, 0.6, lips)) * head
    beard *= np.where(z > lip_top, 0.75, 1.0)
    # the philtrum groove and the corners of the mouth grow thinner
    beard *= 1 - 0.35 * np.exp(-((ax) / 0.004) ** 2) * (z > lip_top)
    beard = np.clip(beard, 0, 1)
    az = azimuth(Pc)
    hz = hairline_z(az)
    # The painted scalp fades in over a distance measured ON the head, from the hairline drawn as
    # a band of texels: a fade in height alone is 9 mm wide where the hairline runs level and a
    # razor edge at the temples and sideburns, where it runs nearly vertical (a hard vertical
    # line of dark paint beside the eye). A little noise breaks the edge like a real hairline.
    band = head & (np.abs(z - hz) < 0.0015) & (z > ear_c[2] - 0.1)
    if band.any():
        from scipy.spatial import cKDTree
        dist, _ = cKDTree(Pc[band]).query(Pc, k=1, distance_upper_bound=0.05)
        dist = np.where(np.isfinite(dist), dist, 0.05)
        jag = np.sin(Pc[:, 0] * 2300.0) * np.sin(Pc[:, 2] * 1900.0 + Pc[:, 1] * 1700.0)
        sd = np.sign(z - hz) * dist + 0.0015 * jag
    else:
        sd = z - hz
    hair = ss(-0.003, 0.009, sd) * (z > ear_c[2] - 0.1) * (1 - ears)
    d_eye = np.minimum(np.linalg.norm(Pc - eye_l, axis=1), np.linalg.norm(Pc - eye_r, axis=1))
    socket = np.exp(-((d_eye - 0.012) / 0.010) ** 2) * head
    forehead = ss(eye_z + 0.018, eye_z + 0.03, z) * (1 - ss(hz - 0.012, hz, z)) * (ax < 0.055) * front
    nose = (ax < 0.02) * ss(lip_top + 0.008, lip_top + 0.015, z) * (1 - ss(eye_z - 0.005, eye_z + 0.012, z)) * (y < face_y + 0.035)
    nose_tip = np.exp(-(ax / 0.011) ** 2 - ((z - (lip_top + 0.024)) / 0.012) ** 2) * (y < face_y + 0.02)
    cheeks = np.exp(-((ax - 0.043) / 0.016) ** 2 - ((z - (eye_z - 0.03)) / 0.018) ** 2) * front * head
    chin = np.exp(-(ax / 0.018) ** 2 - ((z - (lip_bot - 0.025)) / 0.012) ** 2) * front
    tzone = np.clip(forehead + nose + 0.6 * chin, 0, 1)
    neck = (z < lip_bot - 0.05) * (z > 1.43)
    hands = ax > 0.45
    eyelids = np.exp(-((d_eye - 0.013) / 0.004) ** 2) * (z > eye_z - 0.008) * head

    # --- albedo -------------------------------------------------------------------------------------
    skin_png = [f for f in os.listdir(os.path.join(D, "skins", cfg["human"]["skin_mhmat"].replace(".mhmat", ""))) if f.endswith(".png")][0]
    src = load_src("skins/%s/%s" % (cfg["human"]["skin_mhmat"].replace(".mhmat", ""), skin_png))
    K = src.shape[0]
    assert K == cov.shape[0], "skin texture and texture space must share a size"
    lin = T.srgb_to_lin(src)
    # fuller, warmer complexion: the source is a pale studio photo, lit flat
    tint = np.array(look.get("skin_tint", [0.9, 0.78, 0.68]), np.float32)
    lum = lin @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    sat = look.get("skin_saturation", 1.18)
    lin = lum[..., None] + (lin - lum[..., None]) * sat
    lin = np.clip(lin * tint, 0, 1)
    L_ = lin[idx]


    def zone(col, mask, amount):
        return L_ * (1 - (mask * amount)[:, None] * (1 - np.array(col, np.float32))[None, :])


    flush = np.clip(0.55 * cheeks + 0.8 * nose_tip + 0.6 * ears + 0.25 * eyelids, 0, 1)
    L_ = zone([1.0, 0.86, 0.84], flush, 0.45)
    L_ = zone([0.9, 0.84, 0.88], socket, 0.5)
    L_ = zone([1.0, 0.97, 0.9], forehead, 0.4)
    st = look.get("stubble", 0.9)
    L_ = zone([0.74, 0.74, 0.78], beard, st * 0.85)
    lipc = look.get("lips", 0.3)
    L_ = zone([0.9, 0.7, 0.7], np.clip(lips, 0, 1), lipc)
    # the scalp under the hair: the hair's own colour, so any gap between cards shows roots
    hc = T.srgb_to_lin(np.array(look.get("hair_rgb", [14, 12, 11]), np.float32) / 255.0) * 1.8
    L_ = L_ * (1 - 0.92 * hair[:, None]) + hc[None, :] * 0.92 * hair[:, None]
    L_ *= (0.62 + 0.38 * vao)[:, None]
    alb = lin.copy()
    alb[idx] = L_
    alb = T.dilate(alb, cov, 6)
    specs["skin_base"] = T.save(T.lin_to_srgb(alb), tex("hero_skin_diffuse.jpg"), 2048, 93)


    # --- wrinkles (normal map) -----------------------------------------------------------------------
    def groove(dist, width, depth):
        return -depth * np.exp(-(dist / width) ** 2)


    def skin_height(p, e):
        x_, y_, z_ = p[:, 0], p[:, 1], p[:, 2]
        a_ = np.abs(x_)
        h = np.zeros(len(p))
        fr = Nc[e][:, 1] < -0.25
        hd = z_ > lip_bot - 0.055
        # forehead: four wavy horizontal lines between the brows and the hairline
        f_ = ss(eye_z + 0.024, eye_z + 0.034, z_) * (1 - ss(eye_z + 0.062, eye_z + 0.070, z_)) * ss(0.058, 0.035, a_) * fr
        for k, zz in enumerate((0.036, 0.045, 0.053, 0.060)):
            wave = zz + eye_z + 0.0015 * np.sin(a_ * 70 + k) + 0.0008 * np.sin(x_ * 190)
            h += f_ * groove(z_ - wave, 0.0011, 0.00009 * (1.0 - 0.15 * k))
        # glabella: two short vertical frown lines between the brows
        for s in (-1, 1):
            g_ = ss(eye_z + 0.008, eye_z + 0.016, z_) * (1 - ss(eye_z + 0.03, eye_z + 0.04, z_)) * fr
            h += g_ * groove(x_ - s * 0.0065, 0.0009, 0.00008)
        # crow's feet: a fan of short grooves out of each outer eye corner
        for s in (-1, 1):
            cx, cz = s * (eye_x + 0.021), eye_z - 0.001
            dx, dz = (x_ - cx) * s, z_ - cz
            r = np.hypot(dx, dz)
            ang = np.arctan2(dz, dx)
            near = ss(0.02, 0.0, r) * ss(-0.001, 0.003, dx) * hd
            for a0 in (-0.55, -0.2, 0.15, 0.5):
                h += near * groove((ang - a0) * r, 0.0007, 0.00008)
        # under the eyes: a soft crease below the lower lid
        for c_ in (eye_l, eye_r):
            du = np.hypot((x_ - c_[0]) / 1.25, z_ - (c_[2] - 0.0165))
            h += hd * np.exp(-(((x_ - c_[0]) / 0.013) ** 2)) * groove(z_ - (c_[2] - 0.0165 + 0.004 * ((x_ - c_[0]) / 0.013) ** 2), 0.0013, 0.00012) * (du < 0.02)
        # nasolabial folds: from the wing of the nose round to the corner of the mouth
        for s in (-1, 1):
            a0 = np.array([s * 0.019, lip_top + 0.021])
            b0 = np.array([s * (lip_w + 0.009), lc[2] - 0.011])
            d2 = b0 - a0
            t2 = np.clip(((x_ - a0[0]) * d2[0] + (z_ - a0[1]) * d2[1]) / (d2 @ d2), 0, 1)
            bow = 0.004 * np.sin(np.pi * t2)  # the fold bows out across the cheek
            px = a0[0] + d2[0] * t2 + s * bow
            pz = a0[1] + d2[1] * t2
            dist = np.hypot(x_ - px, z_ - pz)
            side = (x_ - px) * s  # + on the cheek side
            fade = ss(0.0, 0.15, t2) * (1 - ss(0.85, 1.0, t2)) * fr
            h += fade * (groove(dist, 0.0022, 0.00042) + 0.00016 * np.exp(-((side - 0.004) / 0.004) ** 2) * (dist < 0.012))
        # lips: fine vertical lines
        lp = (np.abs(z_ - lc[2]) < 0.012) * (a_ < lip_w) * fr
        h += lp * -0.00004 * np.abs(np.sin(x_ * 2 * np.pi / 0.0017 + 2 * np.sin(z_ * 900)))
        # neck: two soft rings across the front
        nk = (z_ < lip_bot - 0.045) * (z_ > 1.46) * (y_ < -0.02)
        for zz in (1.515, 1.54):
            h += nk * groove(z_ - zz - 0.004 * np.sin(x_ * 40), 0.0016, 0.00012)
        # knuckles: crease rings over every finger joint on the back of the hand, lines across the
        # palm side
        for side in ("Left", "Right"):
            for f in ("Index", "Middle", "Ring", "Pinky", "Thumb"):
                for j in (1, 2, 3):
                    kname = "%sHand%s%d" % (side, f, j)
                    if kname not in L:
                        continue
                    c_ = v3(kname)
                    tail = v3(kname + "_tail")
                    dvec = tail - c_
                    dl = np.linalg.norm(dvec)
                    dn = dvec / max(dl, 1e-6)
                    rel = p - c_
                    along = rel @ dn
                    radial = np.linalg.norm(rel - np.outer(along, dn), axis=1)
                    near = (radial < 0.014) & (np.abs(along) < 0.012)
                    if not near.any():
                        continue
                    for off in (-0.0018, 0.0, 0.0018):
                        h += near * groove(along - off, 0.0005, 0.00006 if j > 1 else 0.00008)
        # skin unevenness, very faint
        h += 0.000018 * folds.vnoise(p * 260.0, 5) + 0.000012 * folds.vnoise(p * 700.0, 6)
        return h


    nrm = T.surface_normal_map(skin_height, S["P"], S["N"], S["T"], S["B"], cov, eps=0.0002)
    nrm = T.dilate(nrm, cov, 6)
    specs["skin_normal"] = T.save(T.encode_normal(nrm), tex("hero_skin_normal.jpg"), 2048, 93)

    # --- roughness and the shader mask -------------------------------------------------------------------
    rough = 0.52 - 0.14 * tzone - 0.18 * np.clip(lips, 0, 1) - 0.12 * nose_tip + 0.05 * cheeks + 0.07 * beard * st \
        - 0.24 * nails + 0.14 * hair + 0.06 * hands - 0.06 * eyelids
    rough += 0.035 * folds.vnoise(Pc * 90.0, 8)
    R = np.full(cov.shape, 0.55, np.float32)
    R[idx] = np.clip(rough, 0.08, 0.95)
    R = T.dilate(R, cov, 6)
    specs["skin_rough"] = T.save(R, tex("hero_skin_roughness.png"), 1024)
    thin = np.clip(ears * 1.0 + 0.6 * np.exp(-((ax - 0.016) / 0.007) ** 2 - ((z - (lip_top + 0.02)) / 0.008) ** 2) * front + 0.5 * eyelids + 0.3 * hands, 0, 1)
    cav = np.clip(0.55 + 0.45 * vao, 0, 1)
    M = np.zeros(cov.shape + (4,), np.float32)
    M[..., 2] = 1.0
    M[idx] = np.stack([beard * st, thin, cav, tzone], 1)
    M = T.dilate(M, cov, 6)
    T.save(M, extra("hero_x_skin_mask.png"), 1024)

    # --- tiling micro detail: pores + crosshatch in RGB (a normal), stubble hairs in alpha -------------
    DS = 1024
    yy, xx = np.mgrid[0:DS, 0:DS].astype(np.float32)
    hgt = np.zeros((DS, DS), np.float32)
    # pores on a jittered grid, periodic so the tile wraps
    PS = 22
    w1 = T.tile_noise(rng, DS, 30) * 2.5
    for gy in range(0, DS, PS):
        for gx in range(0, DS, PS):
            if rng.random() < 0.18:
                continue
            sg = 1.3 + rng.random() * 1.6
            dep = 0.6 + 0.6 * rng.random()
            splat(hgt, gx + rng.random() * PS, gy + rng.random() * PS, 8,
                  lambda dx, dy, win, sg=sg, dep=dep: win - dep * np.exp(-(dx * dx + dy * dy) / (sg * sg)))
    # the crosshatch of skin's micro-relief: three families of fine grooves, periodic on the tile
    hx = np.zeros_like(hgt)
    for kx, ky in ((20, 31), (-27, 22), (37, -11)):
        ph = 2 * math.pi * (kx * xx + ky * yy) / DS
        hx -= np.abs(np.sin(ph + w1)) ** 8
    hgt += 0.45 * hx / 3.0
    hgt += 0.25 * T.tile_noise(rng, DS, 1.2) + 0.2 * T.tile_noise(rng, DS, 4.0)
    det = T.height_to_normal(hgt, look.get("pore_strength", 1.6))
    # stubble: hairs about a millimetre apart (the tile is ~3 cm), each a short soft dot
    stb = np.zeros((DS, DS), np.float32)
    HS = 26
    for gy in range(0, DS, HS):
        for gx in range(0, DS, HS):
            r = 2.0 + rng.random() * 1.6
            el = 1.4 + rng.random() * 0.8
            a = rng.random() * math.pi
            ca, sa = math.cos(a), math.sin(a)

            def dot(dx, dy, win, r=r, el=el, ca=ca, sa=sa):
                ux = dx * ca + dy * sa
                uy = -dx * sa + dy * ca
                return np.maximum(win, np.exp(-((ux / (r * el)) ** 2 + (uy / r) ** 2) * 1.6))
            splat(stb, gx + rng.random() * HS, gy + rng.random() * HS, 10, dot)
    detail = np.concatenate([T.encode_normal(det), stb[..., None]], -1)
    T.save(detail, extra("hero_x_skin_detail.png"))
    print("TEX skin: beard %.0f%% hair %.0f%% of the head's texels" % (100 * beard[head].mean(), 100 * hair[head].mean()))

# =================================================================================================
# EYES, BROWS, LASHES
# =================================================================================================
rng = np.random.default_rng(21)  # each section its own stream, so skipping one changes nothing
eye = load_src("eyes/materials/" + look.get("eye", "brown") + "_eye.png")
el = T.srgb_to_lin(eye)
lum = el @ np.array([0.2126, 0.7152, 0.0722], np.float32)
H = el.shape[0]
yy, xx = np.mgrid[0:H, 0:H].astype(np.float32)
iris = np.zeros(lum.shape, bool)
rn = np.full(lum.shape, 9.0, np.float32)
for half in (xx < H / 2, xx >= H / 2):
    pupil = half & (lum < 0.01)
    cy_, cx_ = yy[pupil].mean(), xx[pupil].mean()
    r = np.hypot(yy - cy_, xx - cx_)
    ring = [lum[half & (np.abs(r - k) < 1.5)].mean() for k in range(4, int(0.2 * H))]
    edge = next(k for k, v in zip(range(4, int(0.2 * H)), ring) if v > 0.3)
    iris |= half & (r < edge + 1.5)
    rn = np.where(half, r / edge, rn)
iris_col = T.srgb_to_lin(np.array(look.get("iris_rgb", [92, 60, 36]), np.float32) / 255.0)
rel = np.clip(lum / (lum[iris].mean() + 1e-6), 0.1, 1.8) * (1 - 0.6 * np.clip((rn - 0.8) / 0.2, 0, 1))
el = np.where(iris[..., None], iris_col[None, None, :] * rel[..., None] * 0.85, el)
sclera = ~iris
el = np.where(sclera[..., None], el * np.array([0.86, 0.82, 0.78], np.float32) * 0.8, el)
# a few veins toward the corners, and the lids' shadow: a flat white sclera is what makes CG stare
vein = np.clip(T.tile_noise(rng, H, 0.7) * 3.0 - 1.6, 0, 1) * np.clip((rn - 1.6) / 1.5, 0, 1)
el = np.where(sclera[..., None], el * (1 - 0.35 * vein[..., None] * np.array([0.1, 0.6, 0.6], np.float32)), el)
lid = 1 - 0.55 * np.clip((rn - 1.2) / 1.4, 0, 1) ** 1.2
el = el * np.where(sclera, lid, 1.0)[..., None]
specs["eye_base"] = T.save(T.lin_to_srgb(el), tex("hero_eye_diffuse.jpg"), 512)


def dark_rgba(path, name, size, col):
    a = load_src(path, "RGBA")
    rgb = a[..., :3]
    lum_ = rgb.mean(-1, keepdims=True)
    rel_ = lum_ / (lum_[a[..., 3] > 0.5].mean() + 1e-6) if (a[..., 3] > 0.5).any() else 1.0
    rgb = np.clip(np.array(col, np.float32)[None, None, :] / 255.0 * np.clip(rel_, 0.4, 2.5), 0, 1)
    return T.save(np.concatenate([rgb, a[..., 3:]], -1), tex(name), size)


brow = cfg["human"]["eyebrows"].replace(".mhclo", "")
lash = cfg["human"]["eyelashes"].replace(".mhclo", "")
specs["brow_base"] = dark_rgba("eyebrows/%s/%s.png" % (brow, brow), "hero_brow.png", 512, look.get("brow_rgb", [26, 20, 17]))
specs["lash_base"] = dark_rgba("eyelashes/%s/%s.png" % (lash, lash), "hero_lash.png", 512, [12, 10, 9])

# =================================================================================================
# HAIR ATLAS: 8 columns of strand clumps, root at the top (v = 1), tip at the bottom
# =================================================================================================
rng = np.random.default_rng(22)  # each section its own stream, so skipping one changes nothing
HW, HH, COLS = 1024, 1024, 8
cw = HW // COLS
atlas = np.zeros((HH, HW, 4), np.float32)
rows = np.arange(HH, dtype=np.float32)
xs_ = np.arange(cw, dtype=np.float32)
KINDS = [(70, 1.25, 0.95), (64, 1.2, 0.95), (56, 1.15, 0.9), (44, 1.1, 0.85), (36, 1.05, 0.8), (26, 1.0, 0.72), (18, 0.95, 0.62), (7, 0.9, 0.5)]
for c, (n_strands, thick, reach) in enumerate(KINDS):
    cov_ = np.zeros((HH, cw), np.float32)
    col_ = np.zeros((HH, cw), np.float32)
    for k in range(n_strands):
        x0 = cw * (0.08 + 0.84 * rng.random())
        # tips staggered: the densest columns keep most strands to the end
        end = HH * (reach * (0.55 + 0.45 * rng.random()) + (1 - reach) * 0.4)
        wav = rng.random() * 2 * math.pi
        amp = 1.5 + 3.5 * rng.random()
        drift = (rng.random() - 0.5) * cw * 0.25
        xk = x0 + amp * np.sin(rows / HH * (2 + 3 * rng.random()) * math.pi + wav) + drift * rows / HH
        t = np.clip(rows / end, 0, 1)
        w = thick * (0.7 + 0.6 * rng.random()) * (1 - 0.7 * t ** 2)
        a = np.where(rows < end, 1.0, 0.0) * (1 - T.smoothstep(0.75, 1.0, t))
        prof = np.exp(-((xs_[None, :] - xk[:, None]) / w[:, None]) ** 2) * a[:, None]
        bright = 0.8 + 0.4 * rng.random()
        col_ = np.maximum(col_, prof * bright)
        cov_ = 1 - (1 - cov_) * (1 - np.clip(prof * 0.95, 0, 1))
    # the card's edges thin out, its root is dense
    edge = np.clip(np.minimum(xs_, cw - 1 - xs_) / (cw * 0.12), 0, 1)
    cov_ *= edge[None, :]
    root = T.smoothstep(0.0, 0.06, rows / HH)
    cov_ *= root[:, None] * 0.2 + 0.8
    atlas[:, c * cw:(c + 1) * cw, 0] = np.clip(col_ / np.maximum(cov_, 1e-3), 0, 1.3) * 0.75
    atlas[:, c * cw:(c + 1) * cw, 3] = np.clip(cov_, 0, 1)
atlas[..., 1] = atlas[..., 0]
atlas[..., 2] = atlas[..., 0]
atlas[..., :3] = np.clip(atlas[..., :3], 0, 1)
specs["hair_base"] = T.save(atlas, tex("hero_hair.png"))

# =================================================================================================
# TRACKSUIT: fold normals (straight and closed joints), occlusion, the wrinkle mask
# =================================================================================================
rng = np.random.default_rng(23)  # each section its own stream, so skipping one changes nothing
S = T.load_txs(common.work("txs_suit.npz"))
cov = S["cov"]
idx = np.nonzero(cov)
Pc = S["P"][idx].astype(np.float64)
jac = S["a_jacket"][idx] > 0.5
gain = cfg.get("tracksuit", {}).get("fold_gain", 1.35)
dgain = cfg.get("tracksuit", {}).get("drape_gain", 1.35)


def suit_heights(p, e):
    f = folds.fields(p, jac[e], L)
    return {"rest": gain * f["rest"] - dgain * f["geom"], "bent": gain * f["bent"] - dgain * f["geom"]}


maps = T.surface_normal_map(suit_heights, S["P"], S["N"], S["T"], S["B"], cov, eps=0.0006)
for k, fname in (("rest", tex("hero_tracksuit_normal.jpg")), ("bent", extra("hero_x_suit_bent_normal.jpg"))):
    n_ = T.dilate(maps[k], cov, 8)
    T.save(T.encode_normal(n_), fname, 2048, 93)
specs["ts_normal"] = "hero_tracksuit_normal.jpg"
hr = folds.fields(Pc, jac, L, which=("rest", "geom"))
hrest = gain * hr["rest"] - dgain * hr["geom"]
Hm = T.raster_values(hrest, cov)
cavity = np.clip((T.blur(Hm, 5.0) - Hm) / 0.0022, 0, 1)[idx]
ao = np.clip(S["a_ao"][idx], 0, 1)
pile = T.blur(rng.random(cov.shape).astype(np.float32) - 0.5, 14.0)
pile = pile / (np.abs(pile).max() + 1e-6)
occl = (0.45 + 0.55 * ao ** 1.3) * (1 - 0.45 * cavity)
A_ = np.full(cov.shape, 0.8, np.float32)
A_[idx] = np.clip(0.86 * occl * (1 + 0.06 * pile[idx]), 0, 1)
A_ = T.dilate(A_, cov, 8)
specs["ts_base"] = T.save(A_, tex("hero_tracksuit_diffuse.jpg"), 2048, 92)
W = folds.joint_weights(Pc, jac, L)
Wm = np.zeros(cov.shape + (4,), np.float32)
Wm[idx] = W
Wm = T.dilate(Wm, cov, 12)
T.save(Wm, extra("hero_x_suit_wrinkle_mask.png"), 512)
print("TEX suit: folds rest %.1f..%.1f mm" % (hrest.min() * 1000, hrest.max() * 1000))

# --- tiling: velour pile (RGB normal, A sheen patches) and rib knit ---------------------------------
PSZ = 512
fib = T.tile_noise(rng, PSZ, 0.6) + 0.5 * T.tile_noise(rng, PSZ, 1.4)
# pile lies a little one way: stretch the fibres along v
fib = 0.7 * fib + 0.3 * np.roll(fib, 1, 0)
pn = T.height_to_normal(fib, 0.9)
crush = T.tile_noise(rng, PSZ, 40.0) * 0.5 + 0.5
T.save(np.concatenate([T.encode_normal(pn), crush[..., None]], -1), extra("hero_x_pile.png"))
RS = 512
uu, vv = np.meshgrid(np.arange(RS) / RS, np.arange(RS) / RS)
rib_h = np.abs(np.sin(np.pi * uu * 8)) ** 0.55
# the knit: each rib is a column of V-shaped stitches
stitch = np.abs(np.sin(np.pi * (vv * 32 + np.abs(((uu * 16) % 1) - 0.5) * 1.2)))
rib_h = rib_h * (0.8 + 0.2 * stitch) + 0.05 * T.tile_noise(rng, RS, 0.7)
rn_ = T.height_to_normal(rib_h * 3.0, 1.0)
specs["rib_normal"] = T.save(T.encode_normal(rn_), tex("hero_rib_normal.jpg"), RS)
specs["rib_base"] = T.save(0.66 + 0.26 * rib_h, tex("hero_rib_diffuse.jpg"), RS)
# zip teeth: alternating interlocking teeth down the middle, tape either side
tz = ((np.floor(vv * 6) % 2) == (uu > 0.5)).astype(np.float32) * (np.abs(uu - 0.5) < 0.3)
tz = T.blur(tz, 1.2)
zn = T.height_to_normal(tz * 2.5, 1.0)
specs["zip_normal"] = T.save(T.encode_normal(zn), tex("hero_zip_normal.jpg"), 256)
specs["zip_base"] = T.save(0.18 + 0.82 * tz, tex("hero_zip_diffuse.jpg"), 256)

# =================================================================================================
# SHOES and LACES
# =================================================================================================
rng = np.random.default_rng(24)  # each section its own stream, so skipping one changes nothing
S = T.load_txs(common.work("txs_shoes.npz"))
marks = json.load(open(common.work("shoe_marks.json")))
cov = S["cov"]
idx = np.nonzero(cov)
Pc = S["P"][idx].astype(np.float64)
Nc = S["N"][idx].astype(np.float64)
SZ = cov.shape[0]
x, y, z = Pc[:, 0], Pc[:, 1], Pc[:, 2]
# both shoes share one mirrored UV island, so the texels only ever see one of them
TOE = {1: Pc[:, 1].min(), -1: Pc[:, 1].min()}
toe_y = np.full(len(Pc), TOE[1])
sole = z < 0.012
mid = (z >= 0.012) & (z < 0.030)
# the stitched line where the upper meets the cupsole, and a second row on the toe cap
stitch_z = 0.034
stitch = np.exp(-((z - stitch_z) / 0.0007) ** 2) * (0.5 + 0.5 * np.sign(np.sin((y + x) * 2 * np.pi / 0.004)))
toe_d = y - toe_y
toecap = (toe_d < 0.075) & (z > 0.03)
cap_line = np.exp(-((toe_d - 0.075) / 0.0008) ** 2) * (z > 0.03)
cap_stitch = np.exp(-((toe_d - 0.071) / 0.0006) ** 2) * (z > 0.03) * (0.5 + 0.5 * np.sign(np.sin(x * 2 * np.pi / 0.004)))
# perforations on the toe cap: a small grid of holes
perf = np.zeros(len(Pc))
pc = toecap & (z > 0.045) & (toe_d > 0.02) & (toe_d < 0.06)
gxv = (x * 220) % 1 - 0.5
gyv = (toe_d * 220) % 1 - 0.5
perf += pc * (np.hypot(gxv, gyv) < 0.18)
eyelets = np.array(marks["eyelets"])
de = np.min(np.linalg.norm(Pc[:, None, :] - eyelets[None, :, :], axis=2), axis=1)
eyelet_hole = de < 0.0019
eyelet_ring = (de >= 0.0019) & (de < 0.0033)
# eyestay: stitched panel edge running along each row of eyelets, a few mm outside it
eyestay = np.zeros(len(Pc))
per_foot = len(eyelets) // 2
for f0 in (0, per_foot):
    for i in range(0, per_foot - 2, 2):
        for s_ in (0, 1):
            a_ = eyelets[f0 + i + s_]
            b_ = eyelets[f0 + i + 2 + s_]
            d_ = b_ - a_
            t2 = np.clip(((Pc - a_) @ d_) / (d_ @ d_), 0, 1)
            dist = np.linalg.norm(Pc - (a_ + np.outer(t2, d_)), axis=1)
            eyestay = np.maximum(eyestay, np.exp(-((dist - 0.0058) / 0.0006) ** 2))
grain = folds.vnoise(Pc * 2600.0, 9) * 0.6 + folds.vnoise(Pc * 900.0, 10) * 0.4
col = np.zeros((len(Pc), 3), np.float32)
leather = np.array([0.90, 0.89, 0.87])
col[:] = leather * (1 + 0.02 * grain[:, None])
col[mid] = np.array([0.86, 0.855, 0.84])
col[sole] = np.array([0.80, 0.79, 0.76]) * (1 + 0.04 * folds.vnoise(Pc[sole] * 1500.0, 11)[:, None])
col *= (1 - 0.35 * stitch * (z < 0.04))[:, None]
col *= (1 - 0.25 * (cap_line + cap_stitch))[:, None]
col *= (1 - 0.3 * eyestay)[:, None]
col = np.where(perf[:, None] > 0, col * 0.35, col)
col = np.where(eyelet_hole[:, None], np.array([0.05, 0.05, 0.05]), col)
col = np.where(eyelet_ring[:, None], np.array([0.72, 0.72, 0.72]), col)
col *= (0.72 + 0.28 * S["a_ao"][idx])[:, None]
img = np.full(cov.shape + (3,), 0.85, np.float32)
img[idx] = col
img = T.dilate(img, cov, 8)
specs["shoes_base"] = T.save(img, tex("hero_shoes_diffuse.jpg"), SZ)


def shoe_height(p, e):
    x_, y_, z_ = p[:, 0], p[:, 1], p[:, 2]
    h = 0.00004 * folds.vnoise(p * 2600.0, 9) + 0.00003 * folds.vnoise(p * 900.0, 10)
    h -= 0.00025 * np.exp(-((z_ - stitch_z) / 0.0006) ** 2)
    ty = y_ - np.where(x_ > 0, TOE[1], TOE[-1])
    h -= 0.0002 * np.exp(-((ty - 0.075) / 0.0007) ** 2) * (z_ > 0.03)
    dd = np.min(np.linalg.norm(p[:, None, :] - eyelets[None, :, :], axis=2), axis=1)
    h -= 0.0006 * (dd < 0.0019) - 0.00015 * np.exp(-((dd - 0.0026) / 0.0005) ** 2)
    # sole: a tread band round the side of the cupsole
    h -= 0.0003 * (z_ < 0.012) * (np.abs(np.sin(z_ * 2 * np.pi / 0.004)) > 0.7)
    return h


sn = T.surface_normal_map(shoe_height, S["P"], S["N"], S["T"], S["B"], cov, eps=0.0003)
sn = T.dilate(sn, cov, 8)
specs["shoes_normal"] = T.save(T.encode_normal(sn), tex("hero_shoes_normal.jpg"), SZ)
R = np.full(cov.shape, 0.5, np.float32)
R[idx] = np.clip(0.42 + 0.35 * sole + 0.12 * mid + 0.04 * grain - 0.1 * eyelet_ring, 0.1, 1)
R = T.dilate(R, cov, 8)
specs["shoes_rough"] = T.save(R, tex("hero_shoes_roughness.png"), 512)
# lace and tongue atlas: braid on top (v 0.5..1), tongue mesh on the bottom
LS = 512
uu, vv = np.meshgrid(np.arange(LS) / LS, np.arange(LS) / LS)
lace = np.zeros((LS, LS), np.float32)
top = vv < 0.5  # image rows: top half = v 0.5..1
bu = (uu * 4) % 1
bv = (vv * 12) % 1
braid = np.abs(np.sin(np.pi * (bu * 2 + bv))) * np.abs(np.sin(np.pi * (bu * 2 - bv)))
mesh = 0.5 + 0.5 * np.sin(uu * 2 * np.pi * 26) * np.sin(vv * 2 * np.pi * 26)
lace = np.where(top, braid, mesh * 0.6 + 0.4)
lcol = np.where(top, 0.84 + 0.12 * lace, 0.82 + 0.1 * lace)
specs["lace_base"] = T.save(lcol, tex("hero_laces_diffuse.jpg"), LS)
specs["lace_normal"] = T.save(T.encode_normal(T.height_to_normal(lace * 2.0, 1.0)), tex("hero_laces_normal.jpg"), LS)

# =================================================================================================
# WATCH DIAL: black sunburst, a printed minute track; the indices and hands are geometry
# =================================================================================================
DSZ = 512
yy, xx = np.mgrid[0:DSZ, 0:DSZ].astype(np.float32)
c0 = DSZ / 2
r = np.hypot(xx - c0, yy - c0) / c0
ang = np.arctan2(yy - c0, xx - c0)
dial = np.full((DSZ, DSZ, 3), 0.010, np.float32) * (1 + 0.8 * (0.5 + 0.5 * np.cos(ang * 90)))[..., None]
dial *= (1 + 0.5 * (1 - r))[..., None]
im = Image.fromarray(T.to8(T.lin_to_srgb(dial)))
dr = ImageDraw.Draw(im)
for m_ in range(60):
    a_ = m_ / 60 * 2 * math.pi
    rr = 0.93
    px, py = c0 + math.sin(a_) * rr * c0, c0 - math.cos(a_) * rr * c0
    s_ = 3 if m_ % 5 else 5
    dr.ellipse([px - s_, py - s_, px + s_, py + s_], fill=(205, 200, 190))
dr.ellipse([c0 - 0.97 * c0, c0 - 0.97 * c0, c0 + 0.97 * c0, c0 + 0.97 * c0], outline=(150, 120, 60), width=3)
im.save(tex("hero_dial.jpg"), quality=93)
specs["dial"] = "hero_dial.jpg"


# =================================================================================================
# MATERIAL TABLE (finalize.py) - keys are the MPFB / our object suffixes
# =================================================================================================
def rgb(c):
    return [float(v) for v in T.srgb_to_lin(np.array(c, np.float32) / 255.0)]


eyes_key = cfg["human"]["eyes"].replace(".mhclo", "")
shoes_key = next(c.replace(".mhclo", "") for c in cfg["human"]["clothes"] if c.startswith("shoes"))
ts_col = rgb(look.get("tracksuit_rgb", [22, 22, 24]))
velour = {"roughness": 0.78, "specular": 0.22, "color_factor": ts_col,
          "sheen": {"weight": 1.0, "roughness": 0.3, "tint": rgb(look.get("sheen_rgb", [110, 110, 118]))}}
gold = {"color": rgb(look.get("gold_rgb", [255, 208, 128])), "metallic": 1.0}
mats = {
    "body": {"name": "hero_skin", "base": specs["skin_base"], "rough_map": specs["skin_rough"], "normal": specs["skin_normal"],
             "normal_strength": 1.0, "specular": 0.5, "sss": 0.18},
    eyes_key: {"name": "hero_eyes", "base": specs["eye_base"], "roughness": 0.06, "specular": 0.8, "clearcoat": 1.0},
    brow: {"name": "hero_brows", "base": specs["brow_base"], "roughness": 0.7, "alpha_clip": 0.35, "double_sided": True},
    lash: {"name": "hero_lashes", "base": specs["lash_base"], "roughness": 0.7, "alpha_clip": 0.35, "double_sided": True},
    shoes_key: {"name": "hero_shoes", "base": specs["shoes_base"], "normal": specs["shoes_normal"], "rough_map": specs["shoes_rough"],
                "normal_strength": 1.0, "roughness": 1.0, "specular": 0.4},
    "shoe_laces": {"name": "hero_laces", "base": specs["lace_base"], "normal": specs["lace_normal"], "roughness": 0.85, "specular": 0.3},
    "hair": {"name": "hero_hair", "base": specs["hair_base"], "color_factor": rgb(look.get("hair_rgb", [14, 12, 11])),
             "roughness": look.get("hair_roughness", 0.42), "specular": 0.35, "alpha_clip": 0.3, "double_sided": True},
    "tracksuit": {"name": "hero_tracksuit", "base": specs["ts_base"], "normal": specs["ts_normal"], **velour},
    "ts_rib": {"name": "hero_tracksuit_rib", "base": specs["rib_base"], "normal": specs["rib_normal"], "normal_strength": 0.9, **velour},
    "ts_pipe": {"name": "hero_piping", "color": rgb(look.get("trim_rgb", [240, 238, 232])), "roughness": 0.6, "specular": 0.3,
                "sheen": {"weight": 0.5, "tint": [1.0, 1.0, 1.0], "roughness": 0.4}},
    "ts_tank": {"name": "hero_tank", "base": specs["rib_base"], "normal": specs["rib_normal"], "normal_strength": 0.6,
                "color_factor": rgb([240, 238, 234]), "roughness": 0.88, "specular": 0.3},
    "ts_metal": {"name": "hero_zipper", "base": specs["zip_base"], "normal": specs["zip_normal"], "color_factor": rgb([196, 196, 202]),
                 "metallic": 1.0, "roughness": 0.3},
    "ts_gold": {"name": "hero_gold", **gold, "roughness": 0.14},
    "ts_dial": {"name": "hero_dial", "base": specs["dial"], "roughness": 0.12, "specular": 0.8, "clearcoat": 1.0},
    "ts_crystal": {"name": "hero_crystal", "color": [1.0, 1.0, 1.0], "roughness": 0.02, "specular": 1.0, "alpha": 0.12},
}
json.dump({"materials": mats}, open(tex("textures.json"), "w"), indent=1)
for f in sorted(os.listdir(TEX)):
    if f.endswith((".jpg", ".png")):
        im = Image.open(tex(f))
        print("TEX", f, im.size, im.mode, os.path.getsize(tex(f)) // 1024, "KB")
for f in sorted(os.listdir(X)):
    if f.startswith("hero_x_") and f.endswith((".jpg", ".png")):
        print("TEX extra", f, Image.open(extra(f)).size, os.path.getsize(extra(f)) // 1024, "KB")
