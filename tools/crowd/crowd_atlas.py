# Crowd step 2 (python3 + numpy + PIL): composes one character's atlases from the plan
# build_character.py wrote (WORK/<name>/atlas.json).
#
#   python3 tools/crowd/crowd_atlas.py crowd_a
#
#  body      every island of the skin, eyes, clothes and shoes, cropped out of its CC0 MakeHuman
#            texture (scaled per part: the face keeps its source density) and pasted where the
#            plan put it. Garment ambient occlusion multiplied in; printed logos painted out with
#            the fabric round them (crowd_config.json "garments" -> "erase", image fractions);
#            a blend of two MakeHuman skins where the config asks for a complexion between them;
#            the scalp under the hair taken to the hair colour, so the gaps between hair cards and
#            the welded middle / far bodies (which have no cards) read as hair, not a bald head.
#  normal    the garments' and shoes' own normal maps; skin relief from the skin photo's own
#            fine detail (pores, creases), which the source set has no map for
#  hair      hair, brows and lashes with their alpha, colours pushed out under the transparent
#            texels so the mips never pull in black fringes
# Writes WORK/<name>/body.jpg, body_nrm.jpg and hair.png (crowd_export.py embeds them).
import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import crowd_common as C  # noqa: E402
import texlib as T  # noqa: E402

NAME = sys.argv[1]
PLAN = json.load(open(C.work(NAME, "atlas.json")))
# The look keys are read again from crowd_config.json, so `FROM=crowd_atlas tools/crowd/build.sh`
# picks up a change to them without the Blender step. (Until this, the plan's copy from the last
# Blender build won and a tuned skin_normal_strength never reached the atlas.) Stubble or a beard
# on someone who had neither needs the full build: the beard zone is found in Blender.
_LOOK = ("hair_rgb", "skin", "skin_blend", "skin_tone", "skin_normal_strength", "garment_ao", "dye",
         "dye_contrast", "stubble", "beard", "beard_rgb")
_CFG = C.character(NAME)
for _k in _LOOK:
    if _k in _CFG:
        PLAN[_k] = _CFG[_k]
PAD = PLAN["pad"]
_cache = {}
BROW_DARKEN = 0.8      # a brow's mean against the hair colour
BROW_ALPHA_GAIN = 1.7  # the fringe let through the hair's cut (crowd_hair.gdshader alpha_cut 0.42)
BROW_SOLID = 0.75      # source alpha from which a brow texel is all brow; below it, toward the skin


def skin_source():
    """The skin texture, or a linear-light blend of several (same UV layout) for a complexion the
    source set does not have."""
    blend = PLAN.get("skin_blend") or [[PLAN["skin"][0], 1.0]]
    acc = None
    tot = 0.0
    for skin, w in blend:
        d = os.path.join(C.MPFB_DATA, "skins", skin)
        png = sorted(f for f in os.listdir(d) if f.endswith(".png") and "diffuse" in f)[0]
        a = T.srgb_to_lin(np.asarray(Image.open(os.path.join(d, png)).convert("RGB")).astype(np.float32) / 255.0)
        acc = a * w if acc is None else acc + a * w
        tot += w
    return Image.fromarray(T.to8(T.lin_to_srgb(acc / tot)))


def erased(img, rects):
    """Printed logos painted out: each rect filled with the median of the fabric round it, feathered."""
    a = np.asarray(img).astype(np.float32)
    h, w = a.shape[:2]
    for x0, y0, x1, y1 in rects:
        X0, X1, Y0, Y1 = int(x0 * w), int(x1 * w), int(y0 * h), int(y1 * h)
        m = max(8, (X1 - X0) // 10)
        ring = np.concatenate([a[max(Y0 - m, 0):Y0, X0:X1].reshape(-1, a.shape[2]), a[Y1:Y1 + m, X0:X1].reshape(-1, a.shape[2]),
                               a[Y0:Y1, max(X0 - m, 0):X0].reshape(-1, a.shape[2]), a[Y0:Y1, X1:X1 + m].reshape(-1, a.shape[2])])
        fill = np.median(ring, axis=0)
        ys, xs = slice(max(Y0 - m, 0), min(Y1 + m, h)), slice(max(X0 - m, 0), min(X1 + m, w))
        yy, xx = np.mgrid[ys, xs]
        dx = np.maximum(np.maximum(X0 - xx, xx - X1), 0)
        dy = np.maximum(np.maximum(Y0 - yy, yy - Y1), 0)
        wgt = np.clip(1.0 - np.hypot(dx, dy) / m, 0.0, 1.0)[..., None]
        a[ys, xs] = a[ys, xs] * (1 - wgt) + fill * wgt
    return Image.fromarray(np.clip(a + 0.5, 0, 255).astype(np.uint8), img.mode)


def source(r, what, mode):
    """The rect's source image (diffuse, normal or ao) resized to the plan's scaled size."""
    nw, nh = r["scaled"]
    path = r["src"] if what == "diffuse" else r.get(what)
    key = (what, path, nw, nh, r["kind"], mode)
    if key in _cache:
        return _cache[key]
    if what == "diffuse" and r["kind"] == "skin":
        img = skin_source()
    elif path is None:
        img = None
    else:
        img = Image.open(path).convert(mode)
        if what == "diffuse":
            er = PLAN["garments"].get(r["asset"], {}).get("erase")
            if er:
                img = erased(img, er)
            if r.get("ao") and r["kind"] in ("garment", "hat"):
                ao = np.asarray(Image.open(r["ao"]).convert("L").resize(img.size, Image.LANCZOS)).astype(np.float32) / 255.0
                a = np.asarray(img).astype(np.float32)
                k = PLAN["garment_ao"]
                a[..., :3] *= (1.0 - k * (1.0 - ao))[..., None]
                img = Image.fromarray(np.clip(a + 0.5, 0, 255).astype(np.uint8), img.mode)
    if img is not None and img.size != (nw, nh):
        img = Image.merge(img.mode, [c.resize((nw, nh), Image.LANCZOS) for c in img.split()])
    _cache[key] = img
    return img


def dyed(img, rgb, contrast=1.0):
    """The garment in another colour: the source's brightness kept as shading round the dye (ratio
    to its own mean, so folds, seams and weave stay), its hue and saturation replaced."""
    a = np.asarray(img).astype(np.float32) / 255.0
    lum = a[..., :3] @ np.array([0.299, 0.587, 0.114], np.float32)
    mean = float(np.median(lum[lum > 0.08])) if (lum > 0.08).any() else 0.5
    shade = np.clip((lum / max(mean, 0.02)) ** contrast, 0.25, 1.9)[..., None]
    out = np.clip(np.array(rgb, np.float32) / 255.0 * shade, 0.0, 1.0)
    return Image.fromarray(T.to8(out))


def compose(rects, size, what, mode, background):
    out = Image.new(mode, (size, size), background)
    cov = np.zeros((size, size), bool)
    for r in rects:
        src = source(r, what, mode)
        dye = PLAN.get("dye", {}).get(r.get("region", ""))
        if what == "diffuse" and dye and src is not None:
            con = PLAN.get("dye_contrast", {}).get(r.get("region", ""), 1.0)
            key = ("dyed", id(src), tuple(dye), con)
            if key not in _cache:
                _cache[key] = dyed(src, dye, con)
            src = _cache[key]
        cx0, cy0, cx1, cy1 = r["crop"]
        dx, dy = r["dest"]
        box = (cx0 - PAD, cy0 - PAD, cx1 + PAD, cy1 + PAD)
        if src is None:
            continue
        out.paste(src.crop(box), (dx, dy))
        cov[dy:dy + r["h"], dx:dx + r["w"]] = True
    return out, cov


def skin_relief(alb, cov_skin, strength):
    """Height from the skin photo's own fine detail (a band-pass of its luminance) -> normal."""
    lum = alb[..., :3].mean(-1)
    hp = T.blur(lum, 1.6) - T.blur(lum, 6.0)
    return T.height_to_normal(hp * cov_skin, strength * 40.0)


# ---- body --------------------------------------------------------------------------------------
S = PLAN["size"]
body, cov = compose(PLAN["body"], S, "diffuse", "RGB", (128, 128, 128))
alb = np.asarray(body).astype(np.float32) / 255.0
if PLAN.get("skin_tone"):
    # a complexion nudged in linear light (the old pale MakeHuman skins read as white paper)
    tone = np.array(PLAN["skin_tone"], np.float32)
    for r in PLAN["body"]:
        if r["kind"] == "skin":
            dx, dy = r["dest"]
            sub = alb[dy:dy + r["h"], dx:dx + r["w"]]
            alb[dy:dy + r["h"], dx:dx + r["w"]] = T.lin_to_srgb(T.srgb_to_lin(sub) * tone)

def raster_mask(tris, size):
    """Per-vertex weights on atlas triangles ([[uv, uv, uv], [w, w, w]]) rasterised to a size x size map."""
    wmap = np.zeros((size, size), np.float32)
    for uvs, ws in tris:
        p = np.array([[u * size, (1.0 - v) * size] for u, v in uvs], np.float32)
        x0, y0 = np.floor(p.min(0)).astype(int)
        x1, y1 = np.ceil(p.max(0)).astype(int)
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, size - 1), min(y1, size - 1)
        if x1 < x0 or y1 < y0:
            continue
        yy, xx = np.mgrid[y0:y1 + 1, x0:x1 + 1].astype(np.float32) + 0.5
        (ax, ay), (bx, by), (cx, cy) = p
        d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(d) < 1e-9:
            continue
        l0 = ((by - cy) * (xx - cx) + (cx - bx) * (yy - cy)) / d
        l1 = ((cy - ay) * (xx - cx) + (ax - cx) * (yy - cy)) / d
        l2 = 1.0 - l0 - l1
        inside = (l0 >= -0.02) & (l1 >= -0.02) & (l2 >= -0.02)
        val = l0 * ws[0] + l1 * ws[1] + l2 * ws[2]
        sub = wmap[y0:y1 + 1, x0:x1 + 1]
        sub[inside] = np.maximum(sub[inside], val[inside])
    return wmap


FOLD_H = None  # the garments' fold heights at the albedo's size (metres), for the cavity below
FOLD_N = None  # and their normals at the normal map's size
if os.path.exists(C.work(NAME, "folds.npz")):
    # ---- folds: tools/hero/folds.py's field on every garment texel -------------------------------
    import folds as FF  # noqa: E402  (tools/hero)
    Z = np.load(C.work(NAME, "folds.npz"))
    L = json.load(open(C.work(NAME, "fold_landmarks.json")))
    NS = PLAN["normal_size"]
    Pm = np.zeros((NS, NS, 3), np.float32)
    Nm = np.zeros((NS, NS, 3), np.float32)
    Tm = np.zeros((NS, NS, 3), np.float32)
    Bm = np.zeros((NS, NS, 3), np.float32)
    Jm = np.zeros((NS, NS), bool)
    Gm = np.zeros((NS, NS), np.float32)
    fcov = np.zeros((NS, NS), bool)
    for uvt, pt, nt, jk, gn in zip(Z["uv"].astype(np.float64), Z["p"].astype(np.float64), Z["n"].astype(np.float64), Z["jacket"], Z["gain"]):
        q = uvt * NS
        q[:, 1] = NS - q[:, 1]
        x0, y0 = np.floor(q.min(0)).astype(int)
        x1, y1 = np.ceil(q.max(0)).astype(int)
        x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, NS - 1), min(y1, NS - 1)
        if x1 < x0 or y1 < y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        (ax, ay), (bx, by), (cx, cy) = q
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-12:
            continue
        w0 = ((by - cy) * (xs - cx) + (cx - bx) * (ys - cy)) / den
        w1 = ((cy - ay) * (xs - cx) + (ax - cx) * (ys - cy)) / den
        w2 = 1.0 - w0 - w1
        inside = (w0 >= -0.05) & (w1 >= -0.05) & (w2 >= -0.05)
        if not inside.any():
            continue
        yy = (ys[inside] - 0.5).astype(int)
        xx = (xs[inside] - 0.5).astype(int)
        w = np.stack([w0[inside], w1[inside], w2[inside]], 1)
        Pm[yy, xx] = w @ pt
        nn = w @ nt
        Nm[yy, xx] = nn / np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-9)
        # dP/du and dP/dv (Blender UV, v up)
        e1, e2 = pt[1] - pt[0], pt[2] - pt[0]
        d1, d2 = uvt[1] - uvt[0], uvt[2] - uvt[0]
        det = d1[0] * d2[1] - d1[1] * d2[0]
        if abs(det) < 1e-14:
            continue
        Tm[yy, xx] = (e1 * d2[1] - e2 * d1[1]) / det
        Bm[yy, xx] = (e2 * d1[0] - e1 * d2[0]) / det
        Jm[yy, xx] = bool(jk)
        Gm[yy, xx] = gn
        fcov[yy, xx] = True
    idx = np.nonzero(fcov)
    Jv, Gv = Jm[idx], Gm[idx]

    def fold_height(pts, sl):
        return FF.fields(pts, Jv[sl], L, which=("rest",))["rest"] * Gv[sl]
    FOLD_N = T.surface_normal_map(fold_height, Pm, Nm, Tm, Bm, fcov)
    hv = fold_height(Pm[idx].astype(np.float64), slice(0, len(idx[0])))
    hmap = np.zeros((NS, NS), np.float32)
    hmap[idx] = hv
    FOLD_H = np.asarray(Image.fromarray(hmap, "F").resize((PLAN["size"], PLAN["size"]), Image.BILINEAR))
    FOLD_COV = np.asarray(Image.fromarray(fcov.astype(np.uint8) * 255).resize((PLAN["size"], PLAN["size"]), Image.NEAREST)) > 127
    FOLD_NCOV = fcov
    print("ATLAS folds on %d texels, height %.1f..%.1f mm" % (len(hv), hv.min() * 1000, hv.max() * 1000))

# the scalp under the hair, in the hair's own colour (the looks that keep the model's hair)
if PLAN["scalp_tris"]:
    hair_rgb = PLAN.get("hair_rgb")
    if not hair_rgb and PLAN["hair"]:
        h = next(r for r in PLAN["hair"] if r["kind"] == "hair")
        a = np.asarray(Image.open(h["src"]).convert("RGBA")).astype(np.float32) / 255.0
        m = a[..., 3] > 0.6
        hair_rgb = list((a[..., :3][m].mean(0) * 255 * 0.75))
    col = np.array(hair_rgb or [30, 24, 20], np.float32) / 255.0
    wmap = raster_mask(PLAN["scalp_tris"], S)
    rng = np.random.default_rng(3)
    strands = T.blur(rng.random((S, S)).astype(np.float32) - 0.5, 0.8)
    strands = strands / (np.abs(strands).max() + 1e-6)
    shade = np.clip(0.85 + 0.45 * strands, 0.5, 1.3)[..., None]
    w = np.clip(wmap, 0.0, 1.0)[..., None] * 0.95
    alb = alb * (1.0 - w) + (col * shade) * w
    print("ATLAS scalp painted over %d texels" % int((wmap > 0.5).sum()))

# stubble or a beard where build_character.py found the beard zone: a darker, cooler shadow of
# short hairs (a speckle of dots about a millimetre apart at the face's texel density, in
# patches), or at "beard" 1 an opaque beard with strand shading
amount = max(PLAN.get("stubble", 0.0), PLAN.get("beard", 0.0))
if PLAN.get("beard_tris") and amount > 0.0:
    bm = raster_mask(PLAN["beard_tris"], S)
    bm = T.blur(bm, 1.5)
    rng = np.random.default_rng(11)
    dots = rng.random((S, S)).astype(np.float32)
    dots = np.clip((T.blur(dots, 0.6) - 0.5) * 6.0 + 0.5, 0.0, 1.0)
    patch = np.clip(0.75 + 0.5 * (T.blur(rng.random((S, S)).astype(np.float32), 9.0) - 0.5) * 8.0, 0.4, 1.2)
    brgb = PLAN.get("beard_rgb") or [v * 0.8 for v in (PLAN.get("hair_rgb") or [28, 22, 18])]
    bcol = T.srgb_to_lin(np.array(brgb, np.float32) / 255.0)
    lin = T.srgb_to_lin(alb)
    st = PLAN.get("stubble", 0.0)
    if st > 0.0:
        # Stubble is dark hairs over skin that still shows through: on pale skin a cool grey-blue
        # shadow, never the beard's own brown laid on as paint (that read as orange smudges).
        blum = float(bcol @ np.array([0.2126, 0.7152, 0.0722], np.float32))
        tint = np.array([0.50, 0.55, 0.64], np.float32) * (1.0 - blum) + bcol / max(blum, 1e-4) * 0.8 * blum
        tint = np.clip(0.2 + 0.8 * tint, 0.0, 1.0)
        k = np.clip(bm * st * 1.5 * patch * (0.6 + 0.4 * dots), 0.0, 1.0)[..., None]
        lin = lin * (1.0 - k + k * tint)
    bd = PLAN.get("beard", 0.0)
    if bd > 0.0:
        # soft strand shading: at a sharper grain a grey beard sparkled like frost
        strands = np.clip(0.9 + 0.3 * (T.blur(rng.random((S, S)).astype(np.float32), 1.3) - 0.5) * 6.0, 0.65, 1.15)
        k = np.clip(bm * bd * 1.3, 0.0, 1.0)[..., None]
        lin = lin * (1.0 - 0.92 * k) + bcol * strands[..., None] * 0.92 * k
    alb = T.lin_to_srgb(lin)
    print("ATLAS beard zone %d texels (stubble %.2f, beard %.2f)" % (int((bm > 0.5).sum()), st, bd))

# fold valleys a little darker (the light a fold's own sides keep out of it)
if FOLD_H is not None:
    cav = np.clip(1.0 + 14.0 * np.minimum(FOLD_H, 0.0) + 5.0 * np.maximum(FOLD_H, 0.0), 0.86, 1.03)
    alb = np.where(FOLD_COV[..., None], alb * cav[..., None], alb)

alb = T.dilate(alb, cov, 12)
T.save(alb, C.work(NAME, "body.jpg"), None, 92)

nrm_img, _ = compose(PLAN["body"], S, "normal", "RGB", (128, 128, 255))
nrm = np.asarray(nrm_img).astype(np.float32) / 255.0 * 2.0 - 1.0
# The photo's own relief on the head only (creases, the lips, the ears); on the body it was JPEG
# noise amplified into lumpy skin. The body's skin is flat here and gets the tiling pores.
cov_skin = np.zeros((S, S), np.float32)
cov_head = np.zeros((S, S), np.float32)
for r in PLAN["body"]:
    if r["kind"] == "skin":
        dx, dy = r["dest"]
        cov_skin[dy:dy + r["h"], dx:dx + r["w"]] = 1.0
        if r["part"] == "skin_head":
            cov_head[dy:dy + r["h"], dx:dx + r["w"]] = 1.0
relief = skin_relief(np.asarray(body).astype(np.float32) / 255.0, cov_head, PLAN["skin_normal_strength"])
sk = cov_skin[..., None] > 0.5
nrm = np.where(sk, relief, nrm)
nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True) + 1e-6
nrm = T.dilate(nrm, cov, 12)
NSZ = PLAN["normal_size"]
if FOLD_N is not None:
    # the garments' own normal maps at the atlas' normal size, then the folds added as slopes
    enc = T.encode_normal(nrm)
    small = np.asarray(Image.fromarray(T.to8(enc)).resize((NSZ, NSZ), Image.LANCZOS)).astype(np.float32) / 255.0 * 2.0 - 1.0
    fx = np.where(FOLD_NCOV[..., None], FOLD_N, np.array([0.0, 0.0, 1.0], np.float32))
    comb = np.stack([small[..., 0] / np.maximum(small[..., 2], 0.2) + fx[..., 0] / np.maximum(fx[..., 2], 0.2),
                     small[..., 1] / np.maximum(small[..., 2], 0.2) + fx[..., 1] / np.maximum(fx[..., 2], 0.2),
                     np.ones_like(small[..., 0])], -1)
    comb /= np.linalg.norm(comb, axis=-1, keepdims=True)
    T.save(T.encode_normal(comb), C.work(NAME, "body_nrm.jpg"), None, 92)
else:
    T.save(T.encode_normal(nrm), C.work(NAME, "body_nrm.jpg"), NSZ, 92)

# ---- hair --------------------------------------------------------------------------------------
if PLAN["hair"]:
    H = PLAN["hair_size"]
    hair, hcov = compose(PLAN["hair"], H, "diffuse", "RGBA", (0, 0, 0, 0))
    a = np.asarray(hair).astype(np.float32) / 255.0
    if PLAN.get("hair_rgb"):
        # the photographed cards taken to the character's own hair colour, their brightness kept
        # as the strands' shading (ratio to the mean of the opaque texels)
        lum = a[..., :3] @ np.array([0.299, 0.587, 0.114], np.float32)
        m = a[..., 3] > 0.5
        mean = float(lum[m].mean()) if m.any() else 0.3
        shade = np.clip(lum / max(mean, 0.02), 0.3, 1.8)[..., None]
        dyed_rgb = np.clip(np.array(PLAN["hair_rgb"], np.float32) / 255.0 * shade, 0.0, 1.0)
        take = np.zeros(a.shape[:2], bool)
        for r in PLAN["hair"]:
            if r["kind"] == "hair":
                dx, dy = r["dest"]
                take[dy:dy + r["h"], dx:dx + r["w"]] = True
        a[..., :3] = np.where(take[..., None], dyed_rgb, a[..., :3])
    # Brows. Cut out at the hair's threshold, a photographed brow came out as a solid near-black
    # bar (its texels are a third as bright as the hair, and only its dense core passes the cut).
    # Here each brow is shaded round the hair colour from ITS OWN mean (a redhead's brows are
    # auburn, a grey head's grey), a little darker than the hair, and its thin fringe is let
    # through the cut but coloured toward the skin, i.e. the blend the card would have drawn,
    # baked - so the edge is soft and the hairs thin out instead of stopping.
    body_skin = np.zeros(alb.shape[:2], bool)
    for r in PLAN["body"]:
        if r["kind"] == "skin" and r["part"] != "skin_head":
            dx, dy = r["dest"]
            body_skin[dy:dy + r["h"], dx:dx + r["w"]] = True
    body_skin &= cov
    skin_rgb = np.median(alb[body_skin], axis=0) if body_skin.any() else np.array([0.7, 0.55, 0.45], np.float32)
    brow_rgb = np.array(PLAN.get("hair_rgb") or [30, 24, 20], np.float32) / 255.0 * BROW_DARKEN
    for r in PLAN["hair"]:
        if r["kind"] != "brows":
            continue
        dx, dy = r["dest"]
        s = a[dy:dy + r["h"], dx:dx + r["w"]]
        lum = s[..., :3] @ np.array([0.299, 0.587, 0.114], np.float32)
        m = s[..., 3] > 0.3
        mean = float(lum[m].mean()) if m.any() else 0.1
        col = np.clip(brow_rgb * np.clip(lum / max(mean, 0.01), 0.55, 1.5)[..., None], 0.0, 1.0)
        al = np.clip(s[..., 3] * BROW_ALPHA_GAIN, 0.0, 1.0)
        k = np.clip(s[..., 3] / BROW_SOLID, 0.0, 1.0)[..., None] ** 0.8
        s[..., :3] = col * k + skin_rgb[None, None, :] * (1.0 - k)
        s[..., 3] = al
    solid = a[..., 3] > 0.35
    rgb = T.dilate(a[..., :3], solid, 24)
    out = np.concatenate([rgb, a[..., 3:4]], -1)
    T.save(out, C.work(NAME, "hair.png"))
print("ATLAS done", NAME)
