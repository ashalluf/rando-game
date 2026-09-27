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
PAD = PLAN["pad"]
_cache = {}


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


def dyed(img, rgb):
    """The garment in another colour: the source's brightness kept as shading round the dye (ratio
    to its own mean, so folds, seams and weave stay), its hue and saturation replaced."""
    a = np.asarray(img).astype(np.float32) / 255.0
    lum = a[..., :3] @ np.array([0.299, 0.587, 0.114], np.float32)
    mean = float(np.median(lum[lum > 0.08])) if (lum > 0.08).any() else 0.5
    shade = np.clip(lum / max(mean, 0.02), 0.25, 1.9)[..., None]
    out = np.clip(np.array(rgb, np.float32) / 255.0 * shade, 0.0, 1.0)
    return Image.fromarray(T.to8(out))


def compose(rects, size, what, mode, background):
    out = Image.new(mode, (size, size), background)
    cov = np.zeros((size, size), bool)
    for r in rects:
        src = source(r, what, mode)
        dye = PLAN.get("dye", {}).get(r.get("region", ""))
        if what == "diffuse" and dye and src is not None:
            key = ("dyed", id(src), tuple(dye))
            if key not in _cache:
                _cache[key] = dyed(src, dye)
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
    hp = T.blur(lum, 1.0) - T.blur(lum, 5.0)
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

# the scalp under the hair, in the hair's own colour (the looks that keep the model's hair)
if PLAN["scalp_tris"]:
    hair_rgb = PLAN.get("hair_rgb")
    if not hair_rgb and PLAN["hair"]:
        h = next(r for r in PLAN["hair"] if r["kind"] == "hair")
        a = np.asarray(Image.open(h["src"]).convert("RGBA")).astype(np.float32) / 255.0
        m = a[..., 3] > 0.6
        hair_rgb = list((a[..., :3][m].mean(0) * 255 * 0.75))
    col = np.array(hair_rgb or [30, 24, 20], np.float32) / 255.0
    wmap = np.zeros((S, S), np.float32)
    for uvs, ws in PLAN["scalp_tris"]:
        p = np.array([[u * S, (1.0 - v) * S] for u, v in uvs], np.float32)
        x0, y0 = np.floor(p.min(0)).astype(int)
        x1, y1 = np.ceil(p.max(0)).astype(int)
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, S - 1), min(y1, S - 1)
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
    rng = np.random.default_rng(3)
    strands = T.blur(rng.random((S, S)).astype(np.float32) - 0.5, 0.8)
    strands = strands / (np.abs(strands).max() + 1e-6)
    shade = np.clip(0.85 + 0.45 * strands, 0.5, 1.3)[..., None]
    w = np.clip(wmap, 0.0, 1.0)[..., None] * 0.95
    alb = alb * (1.0 - w) + (col * shade) * w
    print("ATLAS scalp painted over %d texels" % int((wmap > 0.5).sum()))

alb = T.dilate(alb, cov, 12)
T.save(alb, C.work(NAME, "body.jpg"), None, 92)

nrm_img, _ = compose(PLAN["body"], S, "normal", "RGB", (128, 128, 255))
nrm = np.asarray(nrm_img).astype(np.float32) / 255.0 * 2.0 - 1.0
cov_skin = np.zeros((S, S), np.float32)
for r in PLAN["body"]:
    if r["kind"] == "skin":
        dx, dy = r["dest"]
        cov_skin[dy:dy + r["h"], dx:dx + r["w"]] = 1.0
relief = skin_relief(np.asarray(body).astype(np.float32) / 255.0, cov_skin, PLAN["skin_normal_strength"])
sk = cov_skin[..., None] > 0.5
nrm = np.where(sk, relief, nrm)
nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True) + 1e-6
nrm = T.dilate(nrm, cov, 12)
T.save(T.encode_normal(nrm), C.work(NAME, "body_nrm.jpg"), PLAN["normal_size"], 92)

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
        a[..., :3] = np.clip(np.array(PLAN["hair_rgb"], np.float32) / 255.0 * shade, 0.0, 1.0)
    solid = a[..., 3] > 0.35
    rgb = T.dilate(a[..., :3], solid, 24)
    out = np.concatenate([rgb, a[..., 3:4]], -1)
    T.save(out, C.work(NAME, "hair.png"))
print("ATLAS done", NAME)
