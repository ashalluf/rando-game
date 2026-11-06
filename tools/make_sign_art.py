#!/usr/bin/env python3
"""Boulevard sign art: one atlas for the signs of LA's commercial streets (BoulevardSigns).

Everything here is ORIGINAL and drawn by this script: invented plaza and tenant names, motels,
liquor, check-cashing and tyre shops, window vinyl promos, banners, lamp-post banners for invented
city events and districts, and the street plates (parking, street cleaning, no stopping, the
invented BASIN TRANSIT bus stop). No real brand, business, logo, slogan or person. The Korean,
Armenian and Thai lettering is a decorative run of glyphs picked at random (no words), as the
brief asks; every phone number is a 555 number.

Writes assets/textures/boulevard_signs/sign_atlas.png (2048 x 3072, sRGB, alpha for the vinyl
cut-outs) in six families of equal cells (BoulevardSigns.FAMILIES and the shader's sg_rect() hold
the same grid; tests/signage_checks.gd checks the three agree):
  TENANT  512 x 128, 4 x 6, y 0     strip-mall pylon panels: 0-3 plaza headers, 4-23 tenants
  NAME    512 x 256, 4 x 3, y 768   pole sign heads: 0-4 motels, 5-6 liquor, 7-8 checks, 9-10 tyres, 11 spare
  VINYL   256 x 256, 8 x 2, y 1536  window vinyl (alpha cut)
  BANNER  512 x 128, 4 x 2, y 2048  vinyl banners over sign bands 0-5, wayfinding panels 6-7
  LAMPB   128 x 384, 16 x 1, y 2304 lamp-post banners
  PLATE   128 x 192, 16 x 2, y 2688 street plates, motel plates
It also writes scripts/world/sign_art_table.gd: the linear mean colour of the TENANT and NAME
cells, which a tall pole sign's far box is drawn in.

Fonts: DejaVu (Bitstream Vera licence), Liberation (SIL OFL 1.1), GNU FreeFont, WenQuanYi Zen Hei
and TLWG Loma (GPL with the font exception), from the system's font packages, rasterised into the
texture only (no font file ships).

    python3 tools/make_sign_art.py             # atlas + table
    python3 tools/make_sign_art.py --preview   # also build/sign_preview.jpg (half size)

Then `godot --headless --path . --import`, and commit the .png, its .import and the table.
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
OUT = os.path.join(ROOT, "assets", "textures", "boulevard_signs", "sign_atlas.png")
TABLE = os.path.join(ROOT, "scripts", "world", "sign_art_table.gd")
SEED = 20261005
SS = 2
W, H = 2048, 3072

# name: (origin y, cell w, cell h, columns, count)
FAMILIES = {
    "TENANT": (0, 512, 128, 4, 24),
    "NAME": (768, 512, 256, 4, 12),
    "VINYL": (1536, 256, 256, 8, 16),
    "BANNER": (2048, 512, 128, 4, 8),
    "LAMPB": (2304, 128, 384, 16, 16),
    "PLATE": (2688, 128, 192, 16, 32),
}

F = {
    "sans_b": "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "sans": "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "cond_b": "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "cond_bi": "/usr/share/fonts/truetype/liberation/LiberationSans-BoldItalic.ttf",
    "serif_b": "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf",
    "lserif_b": "/usr/share/fonts/truetype/liberation/LiberationSerif-Bold.ttf",
    "lserif_bi": "/usr/share/fonts/truetype/liberation/LiberationSerif-BoldItalic.ttf",
    "script": "/usr/share/fonts/truetype/freefont/FreeSerifBoldItalic.ttf",
    "free_b": "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf",
    "mono_b": "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
    "hangul": "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
    "thai": "/usr/share/fonts/opentype/tlwg/Loma-Bold.otf",
}
_font_cache = {}


def font(key, size):
    k = (key, int(size))
    if k not in _font_cache:
        _font_cache[k] = ImageFont.truetype(F[key], max(6, int(size)))
    return _font_cache[k]


def fit(key, text, max_w, max_h, stroke=0):
    lo, hi = 6, int(max_h * 1.6) + 2
    best = font(key, lo)
    while lo <= hi:
        mid = (lo + hi) // 2
        f = font(key, mid)
        x0, y0, x1, y1 = f.getbbox(text, stroke_width=int(stroke * mid / 40.0))
        if x1 - x0 <= max_w and y1 - y0 <= max_h:
            best = f
            lo = mid + 1
        else:
            hi = mid - 1
    return best


def text(d, xy, s, key, max_w, max_h, fill, anchor="mm", stroke=0, stroke_fill=None):
    f = fit(key, s, max_w, max_h, stroke)
    sw = int(stroke * f.size / 40.0)
    d.text(xy, s, font=f, fill=fill, anchor=anchor, stroke_width=sw, stroke_fill=stroke_fill)
    return f


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def vgrad(w, h, top, bottom):
    a = np.linspace(0.0, 1.0, h)[:, None, None]
    c = np.array(top, float)[None, None, :] * (1 - a) + np.array(bottom, float)[None, None, :] * a
    c = np.repeat(c, w, axis=1)
    img = Image.fromarray(np.clip(c, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    return img


def panel(w, h, bg, edge=None, inner=0.06):
    """A backlit acrylic face: the colour, brighter in the middle (the tubes behind it), darker
    at the frame's shadow."""
    img = Image.new("RGBA", (w, h), bg + (255,))
    arr = np.asarray(img).astype(float)
    yy, xx = np.mgrid[0:h, 0:w]
    dx = np.minimum(xx, w - 1 - xx) / max(1.0, w * inner)
    dy = np.minimum(yy, h - 1 - yy) / max(1.0, h * inner * 2.0)
    shade = np.clip(np.minimum(dx, dy), 0.0, 1.0) ** 0.5
    shade = 0.82 + 0.18 * shade
    arr[..., :3] *= shade[..., None]
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    if edge is not None:
        d = ImageDraw.Draw(img)
        b = max(2, int(min(w, h) * 0.035))
        d.rectangle([b, b, w - 1 - b, h - 1 - b], outline=edge + (255,), width=b)
    return img


def grain(img, amount, seed):
    rng = np.random.default_rng(seed)
    arr = np.asarray(img).astype(float)
    n = rng.normal(0.0, amount, arr.shape[:2])
    arr[..., :3] += n[..., None]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def glyph_run(rng, script, n):
    if script == "hangul":
        return "".join(chr(0xAC00 + rng.randrange(0, 11172)) for _ in range(n))
    if script == "armenian":
        caps = [chr(c) for c in range(0x0531, 0x0557)]
        small = [chr(c) for c in range(0x0561, 0x0587)]
        return "".join(rng.choice(caps if i == 0 else small) for i in range(n))
    if script == "thai":
        cons = [chr(c) for c in range(0x0E01, 0x0E2F)]
        vow = ["า", "ำ", "ิ", "ี", "เ", "แ", "โ", ""]
        out = ""
        for _ in range(n):
            out += rng.choice(cons) + rng.choice(vow)
        return out
    return ""


SCRIPT_FONT = {"hangul": "hangul", "armenian": "free_b", "thai": "thai"}


# --- TENANT panels ------------------------------------------------------------------------------

PLAZAS = [("PALMERA PLAZA", "#0f5c4c", "#f5e7c4"), ("ORCHID SQUARE", "#5a1f5e", "#f7e9f5"),
          ("BASIN CORNERS", "#1c3d7a", "#f2f2ea"), ("CASA VERDE CENTER", "#8a2c1c", "#fbe7c8")]
# (line 1, line 2 or "", bg, fg, font, script-run or None)
TENANTS = [
    ("GOLDEN NAILS", "& SPA", "#fbf6f4", "#c2185b", "lserif_bi", None),
    ("MORNING GLAZE", "DONUTS", "#fdf3df", "#d2541a", "cond_b", None),
    ("PHO LAN ANH", "NOODLE HOUSE", "#fffaf0", "#b81d1d", "cond_b", None),
    ("BOBA BLISS", "TEA & MILK", "#e9f7ef", "#5d3a8c", "sans_b", None),
    ("AUTO INSURANCE", "SEGUROS", "#ffd400", "#0d2b6b", "cond_b", None),
    ("SMILE DENTAL", "GROUP", "#ffffff", "#0b6fa4", "sans_b", None),
    ("COIN LAUNDRY", "WASH & FOLD", "#0a4fa0", "#ffffff", "cond_b", None),
    ("INCOME TAX", "NOTARY PUBLIC", "#ffffff", "#1d5b2b", "cond_b", None),
    ("MATTRESS", "OUTLET", "#16337a", "#ffffff", "cond_b", None),
    ("CELLULAR PLUS", "REPAIR - ACCESSORIES", "#f6f6f6", "#e0102b", "cond_bi", None),
    ("PIZZA FIESTA", "", "#fff4e0", "#c4140f", "lserif_b", None),
    ("TERIYAKI BOWL", "", "#ffffff", "#d84315", "cond_b", None),
    ("SMOKE & VAPE", "", "#121212", "#7cfc5a", "cond_b", None),
    ("ONE HOUR", "CLEANERS", "#ffffff", "#1a4a9c", "cond_b", None),
    ("TAQUERIA", "EL SOLECITO", "#ffcf3d", "#b0170f", "lserif_b", None),
    ("KOREAN BBQ", "", "#ffffff", "#b3001b", "cond_b", "hangul"),
    ("BAKERY", "", "#f6efe2", "#1e3f7c", "serif_b", "armenian"),
    ("THAI FOOD", "", "#fff8e8", "#6a1b9a", "cond_b", "thai"),
    ("CARNICERIA", "LA REINITA", "#fefefe", "#0f7a2a", "lserif_b", None),
    ("MARISCOS", "EL PUERTO AZUL", "#0a75b5", "#ffffff", "cond_bi", None),
]


def draw_tenant(i, w, h, rng):
    if i < 4:
        name, bg, fg = PLAZAS[i]
        img = panel(w, h, rgb(bg), edge=rgb(fg), inner=0.04)
        d = ImageDraw.Draw(img)
        text(d, (w / 2, h * 0.53), name, "lserif_b", w * 0.72, h * 0.58, rgb(fg) + (255,))
        # A small palm / star mark either side.
        for sx in (0.07, 0.93):
            cx, cy = w * sx, h * 0.5
            r = h * 0.14
            for k in range(5):
                a = -math.pi / 2 + k * 2 * math.pi / 5
                d.line([(cx, cy), (cx + math.cos(a) * r, cy + math.sin(a) * r)], fill=rgb(fg) + (255,), width=max(2, int(h * 0.05)))
        return img
    t = TENANTS[i - 4]
    l1, l2, bg, fg, fk, script = t
    img = panel(w, h, rgb(bg), inner=0.03)
    d = ImageDraw.Draw(img)
    fgc = rgb(fg) + (255,)
    if script:
        run = glyph_run(rng, script, rng.randint(3, 5) if script != "thai" else rng.randint(4, 6))
        text(d, (w * 0.5, h * 0.36), run, SCRIPT_FONT[script], w * 0.86, h * 0.5, fgc)
        text(d, (w * 0.5, h * 0.8), l1, fk, w * 0.7, h * 0.28, fgc)
    elif l2:
        text(d, (w * 0.5, h * 0.38), l1, fk, w * 0.9, h * 0.5, fgc)
        text(d, (w * 0.5, h * 0.8), l2, fk, w * 0.8, h * 0.27, fgc)
    else:
        text(d, (w * 0.5, h * 0.52), l1, fk, w * 0.9, h * 0.66, fgc)
    return grain(img, 2.0, 100 + i)


# --- NAME heads -----------------------------------------------------------------------------------

MOTELS = [("Comet", "MOTEL", "#13406e", "#ffd23f", "#ff4f7b"),
          ("Saguaro", "MOTOR LODGE", "#0f5d4a", "#fff1c9", "#ff9d2e"),
          ("Palm Aire", "MOTEL", "#f2e6c9", "#c4262e", "#1a8f8a"),
          ("Blue Jay", "INN", "#1d2b55", "#7fd3ff", "#ffe34d"),
          ("Rocket Court", "MOTEL", "#b5291e", "#fff6e0", "#ffd54a")]


def draw_name(i, w, h, rng):
    if i < 5:
        name, sub, bg, fg, acc = MOTELS[i]
        img = Image.new("RGBA", (w, h), rgb(bg) + (255,))
        d = ImageDraw.Draw(img)
        # A boomerang swoosh and a starburst behind the script name (the Googie board's paint).
        d.polygon([(0, h * 0.78), (w, h * 0.55), (w, h * 0.68), (0, h * 0.95)], fill=rgb(acc) + (255,))
        cx, cy = w * 0.12, h * 0.22
        for k in range(12):
            a = k * math.pi / 6
            d.line([(cx, cy), (cx + math.cos(a) * h * 0.16, cy + math.sin(a) * h * 0.16)], fill=rgb(fg) + (255,), width=4)
        text(d, (w * 0.54, h * 0.36), name, "script", w * 0.8, h * 0.5, rgb(fg) + (255,), stroke=3, stroke_fill=(20, 20, 20, 255))
        text(d, (w * 0.5, h * 0.84), sub, "cond_b", w * 0.62, h * 0.2, rgb(fg if i == 2 else "#ffffff") + (255,))
        return grain(img, 2.5, 200 + i)
    if i in (5, 6):
        img = panel(w, h, (250, 250, 246) if i == 5 else (200, 18, 24), inner=0.03)
        d = ImageDraw.Draw(img)
        red = (205, 22, 28, 255)
        if i == 5:
            text(d, (w / 2, h * 0.38), "LIQUOR", "cond_b", w * 0.92, h * 0.6, red)
            d.rectangle([0, h * 0.7, w, h], fill=(18, 60, 140, 255))
            text(d, (w / 2, h * 0.85), "BEER - WINE - ICE - ATM", "cond_b", w * 0.86, h * 0.2, (255, 255, 255, 255))
        else:
            text(d, (w / 2, h * 0.3), "MINI MART", "cond_bi", w * 0.8, h * 0.34, (255, 230, 60, 255))
            text(d, (w / 2, h * 0.72), "LIQUOR", "cond_b", w * 0.9, h * 0.46, (255, 255, 255, 255), stroke=3, stroke_fill=(90, 0, 0, 255))
        return grain(img, 2.0, 300 + i)
    if i in (7, 8):
        img = panel(w, h, (255, 214, 0) if i == 7 else (14, 74, 160), inner=0.03)
        d = ImageDraw.Draw(img)
        if i == 7:
            text(d, (w / 2, h * 0.3), "CHECKS", "cond_b", w * 0.9, h * 0.4, (16, 40, 120, 255))
            text(d, (w / 2, h * 0.68), "CASHED", "cond_b", w * 0.9, h * 0.36, (200, 16, 30, 255))
            text(d, (w / 2, h * 0.92), "MONEY ORDERS - BILL PAY", "cond_b", w * 0.8, h * 0.11, (16, 40, 120, 255))
        else:
            text(d, (w / 2, h * 0.27), "CHECK EXPRESS", "cond_bi", w * 0.9, h * 0.3, (255, 255, 255, 255))
            d.rectangle([w * 0.06, h * 0.5, w * 0.94, h * 0.9], fill=(255, 214, 0, 255))
            text(d, (w / 2, h * 0.7), "CAMBIO DE CHEQUES", "cond_b", w * 0.82, h * 0.24, (14, 50, 120, 255))
        return grain(img, 2.0, 400 + i)
    if i in (9, 10):
        img = panel(w, h, (20, 20, 22) if i == 9 else (250, 200, 30), inner=0.03)
        d = ImageDraw.Draw(img)
        if i == 9:
            text(d, (w / 2, h * 0.32), "LLANTAS", "cond_b", w * 0.86, h * 0.44, (255, 205, 30, 255))
            text(d, (w / 2, h * 0.72), "TIRES - NEW & USED", "cond_b", w * 0.88, h * 0.25, (255, 255, 255, 255))
            text(d, (w / 2, h * 0.92), "OPEN 7 DAYS", "cond_b", w * 0.5, h * 0.1, (240, 60, 40, 255))
        else:
            text(d, (w / 2, h * 0.28), "TIRE SHOP", "cond_b", w * 0.9, h * 0.38, (20, 20, 20, 255))
            text(d, (w / 2, h * 0.64), "LLANTAS USADAS", "cond_bi", w * 0.86, h * 0.26, (190, 20, 20, 255))
            text(d, (w / 2, h * 0.88), "FLAT REPAIR - ALIGNMENT", "cond_b", w * 0.84, h * 0.12, (20, 20, 20, 255))
        return grain(img, 2.0, 500 + i)
    img = panel(w, h, (255, 255, 255))
    d = ImageDraw.Draw(img)
    text(d, (w / 2, h * 0.5), "OPEN 24 HRS", "cond_b", w * 0.9, h * 0.5, (200, 20, 30, 255))
    return img


# --- VINYL --------------------------------------------------------------------------------------

def cutout(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def draw_vinyl(i, w, h, rng):
    img = cutout(w, h)
    d = ImageDraw.Draw(img)
    white = (250, 250, 248, 255)
    red = (214, 24, 34, 255)
    yellow = (255, 214, 10, 255)
    if i == 0:
        d.rounded_rectangle([w * 0.04, h * 0.3, w * 0.96, h * 0.7], radius=12, fill=(250, 250, 248, 235))
        text(d, (w / 2, h * 0.42), "SE HABLA", "cond_b", w * 0.84, h * 0.15, red)
        text(d, (w / 2, h * 0.6), "ESPAÑOL", "cond_b", w * 0.84, h * 0.17, (20, 60, 150, 255))
    elif i == 1:
        d.rectangle([w * 0.08, h * 0.08, w * 0.92, h * 0.92], fill=yellow)
        text(d, (w / 2, h * 0.3), "NOW", "cond_b", w * 0.7, h * 0.24, (10, 10, 10, 255))
        text(d, (w / 2, h * 0.55), "HIRING", "cond_b", w * 0.78, h * 0.24, (10, 10, 10, 255))
        text(d, (w / 2, h * 0.8), "APPLY INSIDE", "cond_b", w * 0.7, h * 0.1, (10, 10, 10, 255))
    elif i == 2:
        img = vgrad(w, h, (230, 0, 90), (120, 0, 120))
        d = ImageDraw.Draw(img)
        d.rounded_rectangle([w * 0.55, h * 0.18, w * 0.86, h * 0.86], radius=16, fill=(20, 20, 26, 255))
        d.rounded_rectangle([w * 0.58, h * 0.22, w * 0.83, h * 0.8], radius=10, fill=(80, 190, 255, 255))
        text(d, (w * 0.28, h * 0.3), "$0", "cond_b", w * 0.44, h * 0.26, white)
        text(d, (w * 0.28, h * 0.5), "DOWN", "cond_b", w * 0.44, h * 0.12, white)
        text(d, (w * 0.28, h * 0.7), "NEW PHONE", "cond_b", w * 0.46, h * 0.09, yellow)
    elif i == 3:
        img = vgrad(w, h, (0, 120, 220), (0, 50, 140))
        d = ImageDraw.Draw(img)
        text(d, (w / 2, h * 0.24), "UNLIMITED", "cond_b", w * 0.86, h * 0.16, white)
        text(d, (w / 2, h * 0.52), "$25", "cond_b", w * 0.7, h * 0.34, yellow)
        text(d, (w / 2, h * 0.78), "TALK - TEXT - DATA /mo", "cond_b", w * 0.86, h * 0.09, white)
    elif i == 4:
        img = Image.new("RGBA", (w, h), (250, 205, 40, 255))
        d = ImageDraw.Draw(img)
        text(d, (w / 2, h * 0.11), "TACOS - BURRITOS", "cond_b", w * 0.9, h * 0.11, (170, 20, 10, 255))
        for k in range(4):
            cx = w * (0.27 if k % 2 == 0 else 0.73)
            cy = h * (0.42 if k < 2 else 0.77)
            r = w * 0.19
            d.ellipse([cx - r, cy - r * 0.75, cx + r, cy + r * 0.75], fill=(245, 240, 225, 255))
            for j in range(18):
                a = rng.random() * math.tau
                rr = rng.random() * r * 0.6
                c = rng.choice([(120, 60, 25), (150, 80, 30), (60, 140, 50), (200, 40, 30), (240, 230, 200)])
                px, py = cx + math.cos(a) * rr, cy + math.sin(a) * rr * 0.6
                d.ellipse([px - 7, py - 5, px + 7, py + 5], fill=c + (255,))
            d.rectangle([cx + r * 0.3, cy + r * 0.45, cx + r * 1.0, cy + r * 0.8], fill=(200, 20, 20, 255))
            text(d, (cx + r * 0.65, cy + r * 0.62), "$%d.99" % rng.randint(2, 9), "cond_b", r * 0.65, r * 0.3, white)
    elif i == 5:
        text(d, (w / 2, h * 0.32), "WE BUY", "cond_b", w * 0.86, h * 0.22, (255, 200, 30, 255), stroke=4, stroke_fill=(30, 20, 0, 255))
        text(d, (w / 2, h * 0.62), "GOLD", "cond_b", w * 0.86, h * 0.34, (255, 200, 30, 255), stroke=4, stroke_fill=(30, 20, 0, 255))
    elif i == 6:
        for k, (s, c) in enumerate([("EBT", (20, 90, 170, 255)), ("ATM", (20, 130, 60, 255)), ("ICE", (30, 160, 220, 255))]):
            y = h * (0.12 + 0.3 * k)
            d.rounded_rectangle([w * 0.1, y, w * 0.9, y + h * 0.24], radius=10, fill=c)
            text(d, (w / 2, y + h * 0.12), s, "cond_b", w * 0.7, h * 0.18, white)
    elif i == 7:
        d.ellipse([w * 0.06, h * 0.06, w * 0.94, h * 0.94], fill=red)
        text(d, (w / 2, h * 0.3), "SALE", "cond_b", w * 0.6, h * 0.18, white)
        text(d, (w / 2, h * 0.55), "50%", "cond_b", w * 0.66, h * 0.26, white)
        text(d, (w / 2, h * 0.75), "OFF", "cond_b", w * 0.4, h * 0.14, white)
    elif i in (8, 9, 10):
        script = ["hangul", "armenian", "thai"][i - 8]
        col = [(200, 20, 40, 255), (20, 40, 120, 255), (120, 20, 140, 255)][i - 8]
        for k in range(3):
            run = glyph_run(rng, script, rng.randint(3, 5))
            text(d, (w / 2, h * (0.22 + 0.27 * k)), run, SCRIPT_FONT[script], w * 0.9, h * 0.2, col if k != 1 else white,
                 stroke=3 if k == 1 else 0, stroke_fill=col)
        d.rectangle([w * 0.1, h * 0.92, w * 0.9, h * 0.95], fill=col)
    elif i == 11:
        d.rectangle([0, h * 0.25, w, h * 0.75], fill=red)
        text(d, (w / 2, h * 0.4), "GRAND", "cond_b", w * 0.8, h * 0.18, yellow)
        text(d, (w / 2, h * 0.62), "OPENING", "cond_b", w * 0.9, h * 0.18, white)
    elif i == 12:
        img = Image.new("RGBA", (w, h), (0, 110, 70, 255))
        d = ImageDraw.Draw(img)
        text(d, (w / 2, h * 0.3), "LOTTERY", "cond_b", w * 0.84, h * 0.2, yellow)
        text(d, (w / 2, h * 0.55), "SCRATCHERS", "cond_b", w * 0.84, h * 0.13, white)
        text(d, (w / 2, h * 0.78), "PLAY HERE", "cond_bi", w * 0.6, h * 0.12, yellow)
    elif i == 13:
        text(d, (w / 2, h * 0.18), "OPEN 7 DAYS", "cond_b", w * 0.86, h * 0.12, white)
        for k, s in enumerate(["MON-FRI  9AM-9PM", "SAT  10AM-8PM", "SUN  10AM-6PM"]):
            text(d, (w / 2, h * (0.42 + 0.14 * k)), s, "sans_b", w * 0.84, h * 0.08, white)
    elif i == 14:
        img = Image.new("RGBA", (w, h), (255, 220, 0, 255))
        d = ImageDraw.Draw(img)
        text(d, (w / 2, h * 0.24), "CHECKS", "cond_b", w * 0.8, h * 0.2, (16, 40, 120, 255))
        text(d, (w / 2, h * 0.44), "CASHED", "cond_b", w * 0.8, h * 0.18, red)
        text(d, (w / 2, h * 0.68), "MONEY ORDERS", "cond_b", w * 0.8, h * 0.1, (16, 40, 120, 255))
        text(d, (w / 2, h * 0.84), "ENVIOS DE DINERO", "cond_b", w * 0.84, h * 0.09, (16, 40, 120, 255))
    else:
        img = Image.new("RGBA", (w, h), (250, 250, 248, 255))
        d = ImageDraw.Draw(img)
        d.rectangle([0, 0, w, h * 0.3], fill=red)
        text(d, (w / 2, h * 0.15), "FOR LEASE", "cond_b", w * 0.86, h * 0.2, white)
        text(d, (w / 2, h * 0.5), "RETAIL SPACE", "cond_b", w * 0.84, h * 0.12, (20, 20, 20, 255))
        text(d, (w / 2, h * 0.75), "(213) 555-0164", "cond_b", w * 0.86, h * 0.13, red)
    return img


# --- BANNER ------------------------------------------------------------------------------------

def draw_banner(i, w, h, rng):
    if i >= 6:
        if i == 6:
            img = panel(w, h, (12, 98, 62), edge=(240, 240, 240), inner=0.02)
            d = ImageDraw.Draw(img)
            text(d, (w * 0.28, h * 0.32), "<  DOWNTOWN", "cond_b", w * 0.42, h * 0.3, (255, 255, 255, 255))
            text(d, (w * 0.72, h * 0.32), "CIVIC CENTER  >", "cond_b", w * 0.42, h * 0.3, (255, 255, 255, 255))
            text(d, (w * 0.5, h * 0.72), "^  ARENA DISTRICT", "cond_b", w * 0.6, h * 0.3, (255, 255, 255, 255))
        else:
            img = panel(w, h, (110, 62, 30), edge=(245, 235, 210), inner=0.02)
            d = ImageDraw.Draw(img)
            text(d, (w * 0.5, h * 0.32), "BEACH  >", "cond_b", w * 0.6, h * 0.3, (250, 240, 215, 255))
            text(d, (w * 0.5, h * 0.72), "<  MUSEUM ROW", "cond_b", w * 0.6, h * 0.3, (250, 240, 215, 255))
        return img
    spec = [("GRAND OPENING", (208, 18, 26), (255, 255, 255), (255, 214, 0)),
            ("LIQUIDATION SALE", (255, 214, 0), (190, 10, 20), (20, 20, 20)),
            ("NOW OPEN", (16, 60, 160), (255, 255, 255), (255, 214, 0)),
            ("STORE CLOSING", (250, 250, 250), (210, 20, 30), (20, 20, 20)),
            ("COMING SOON", (20, 20, 22), (255, 214, 0), (255, 255, 255)),
            ("GRAN APERTURA", (14, 120, 60), (255, 255, 255), (255, 60, 40))][i]
    s, bg, fg, acc = spec
    img = Image.new("RGBA", (w, h), bg + (255,))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w, h * 0.09], fill=acc + (255,))
    d.rectangle([0, h * 0.91, w, h], fill=acc + (255,))
    text(d, (w / 2, h / 2), s, "cond_b", w * 0.86, h * 0.6, fg + (255,))
    # Grommets in the corners.
    for gx in (0.025, 0.975):
        for gy in (0.2, 0.8):
            cx, cy = w * gx, h * gy
            d.ellipse([cx - 5, cy - 5, cx + 5, cy + 5], fill=(170, 170, 170, 255), outline=(60, 60, 60, 255), width=2)
    return grain(img, 3.0, 600 + i)


# --- LAMP banners ------------------------------------------------------------------------------

LAMPB = [("MIDTOWN", "ART WALK", "FIRST FRIDAYS", "#d6336c", "#ffffff"),
         ("BASIN", "JAZZ FEST", "JUNE 12-14", "#13315c", "#ffd166"),
         ("RANDO CITY", "MARATHON", "RUN THE BASIN", "#f77f00", "#ffffff"),
         ("VISTA", "HEIGHTS", "EST. 1924", "#2a9d8f", "#fdfcdc"),
         ("PALMERA", "ROW", "SHOP - DINE - STROLL", "#264653", "#e9c46a"),
         ("DIA DE", "MUERTOS", "OCT 30 - NOV 2", "#6a0572", "#ffbe0b"),
         ("FARMERS", "MARKET", "SUNDAYS 8-1", "#3a7d44", "#fff8e1"),
         ("LANTERN", "NIGHTS", "WINTER FESTIVAL", "#9d0208", "#ffd60a"),
         ("OLD", "BASIN", "HISTORIC DISTRICT", "#5e503f", "#eae0d5"),
         ("SHOP", "LOCAL", "SUPPORT YOUR STREET", "#0077b6", "#ffffff"),
         ("RANDO", "FILM FEST", "SEPT 18-27", "#111111", "#e63946"),
         ("CORAL", "LINE", "NOW RUNNING", "#ef476f", "#ffffff"),
         ("MIDTOWN", "ART WALK", "FIRST FRIDAYS", "#1d3557", "#f1faee"),
         ("VISTA", "HEIGHTS", "EST. 1924", "#e76f51", "#ffffff"),
         ("BASIN", "JAZZ FEST", "JUNE 12-14", "#ffd166", "#13315c"),
         ("PALMERA", "ROW", "SHOP - DINE - STROLL", "#e9c46a", "#264653")]


def draw_lampb(i, w, h, rng):
    l1, l2, l3, bg, fg = LAMPB[i]
    img = vgrad(w, h, rgb(bg), tuple(max(0, c - 40) for c in rgb(bg)))
    d = ImageDraw.Draw(img)
    fgc = rgb(fg) + (255,)
    # Pole sleeves top and bottom, a motif in the middle.
    d.rectangle([0, 0, w, h * 0.05], fill=(0, 0, 0, 90))
    d.rectangle([0, h * 0.95, w, h], fill=(0, 0, 0, 90))
    text(d, (w / 2, h * 0.17), l1, "cond_b", w * 0.86, h * 0.08, fgc)
    text(d, (w / 2, h * 0.27), l2, "cond_b", w * 0.86, h * 0.09, fgc)
    cx, cy, r = w * 0.5, h * 0.55, w * 0.32
    kind = i % 4
    if kind == 0:
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=fgc, width=6)
        d.ellipse([cx - r * 0.45, cy - r * 0.45, cx + r * 0.45, cy + r * 0.45], fill=fgc)
    elif kind == 1:
        pts = []
        for k in range(10):
            a = -math.pi / 2 + k * math.pi / 5
            rr = r if k % 2 == 0 else r * 0.45
            pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
        d.polygon(pts, fill=fgc)
    elif kind == 2:
        d.line([(cx, cy + r), (cx, cy - r * 0.6)], fill=fgc, width=6)
        for k in range(7):
            a = -math.pi * (0.1 + 0.8 * k / 6)
            d.line([(cx, cy - r * 0.6), (cx + math.cos(a) * r, cy - r * 0.6 + math.sin(a) * r * 0.5)], fill=fgc, width=5)
    else:
        for k in range(3):
            y = cy - r + k * r * 0.8
            d.polygon([(cx - r, y + r * 0.5), (cx, y), (cx + r, y + r * 0.5)], outline=fgc, width=5)
    text(d, (w / 2, h * 0.86), l3, "cond_b", w * 0.86, h * 0.05, fgc)
    return grain(img, 2.0, 700 + i)


# --- PLATES -------------------------------------------------------------------------------------

def plate_base(w, h, bg=(250, 250, 247), border=None):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([1, 1, w - 2, h - 2], radius=10, fill=bg + (255,))
    if border:
        d.rounded_rectangle([5, 5, w - 6, h - 6], radius=7, outline=border + (255,), width=3)
    return img, d


def p_circle(d, cx, cy, r, ring, slash=True, letter="P", lc=(10, 10, 10)):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=ring + (255,), width=6)
    text(d, (cx, cy), letter, "sans_b", r * 1.2, r * 1.3, lc + (255,))
    if slash:
        o = r * 0.7
        d.line([(cx - o, cy - o), (cx + o, cy + o)], fill=ring + (255,), width=7)


def broom(d, cx, cy, s, c):
    d.line([(cx - s, cy - s), (cx + s * 0.3, cy + s * 0.3)], fill=c + (255,), width=4)
    d.polygon([(cx + s * 0.1, cy + s * 0.1), (cx + s, cy + s * 0.2), (cx + s * 0.2, cy + s)], fill=c + (255,))


def draw_plate(i, w, h, rng):
    G = (14, 110, 54)
    R = (205, 22, 32)
    K = (12, 12, 12)
    T = (0, 128, 128)
    if i in (0, 1, 18):
        img, d = plate_base(w, h, border=G)
        hrs = {0: "2", 1: "1", 18: "4"}[i]
        text(d, (w / 2, h * 0.2), hrs + " HR", "cond_b", w * 0.8, h * 0.17, G + (255,))
        text(d, (w / 2, h * 0.38), "PARKING", "cond_b", w * 0.8, h * 0.11, G + (255,))
        text(d, (w / 2, h * 0.56), "8AM - 6PM", "cond_b", w * 0.8, h * 0.1, G + (255,))
        text(d, (w / 2, h * 0.72), "EXCEPT", "cond_b", w * 0.6, h * 0.08, G + (255,))
        text(d, (w / 2, h * 0.85), "SUNDAY", "cond_b", w * 0.6, h * 0.08, G + (255,))
    elif i in (2, 3):
        img, d = plate_base(w, h, border=R)
        p_circle(d, w * 0.5, h * 0.17, h * 0.1, R)
        day = "TUESDAY" if i == 2 else "THURSDAY"
        t = "8AM - 10AM" if i == 2 else "12PM - 3PM"
        text(d, (w / 2, h * 0.38), t, "cond_b", w * 0.84, h * 0.1, R + (255,))
        text(d, (w / 2, h * 0.52), day, "cond_b", w * 0.84, h * 0.1, R + (255,))
        text(d, (w / 2, h * 0.66), "STREET", "cond_b", w * 0.7, h * 0.08, R + (255,))
        text(d, (w / 2, h * 0.77), "CLEANING", "cond_b", w * 0.8, h * 0.08, R + (255,))
        broom(d, w * 0.5, h * 0.89, h * 0.05, R)
    elif i in (4, 19, 11):
        img, d = plate_base(w, h, bg=(250, 250, 247), border=R)
        if i == 4:
            text(d, (w / 2, h * 0.22), "NO", "cond_b", w * 0.7, h * 0.17, R + (255,))
            text(d, (w / 2, h * 0.42), "STOPPING", "cond_b", w * 0.84, h * 0.12, R + (255,))
            text(d, (w / 2, h * 0.62), "ANY", "cond_b", w * 0.6, h * 0.12, R + (255,))
            text(d, (w / 2, h * 0.8), "TIME", "cond_b", w * 0.6, h * 0.12, R + (255,))
        elif i == 19:
            p_circle(d, w * 0.5, h * 0.3, h * 0.17, R)
            text(d, (w / 2, h * 0.62), "ANY", "cond_b", w * 0.6, h * 0.12, R + (255,))
            text(d, (w / 2, h * 0.8), "TIME", "cond_b", w * 0.6, h * 0.12, R + (255,))
        else:
            text(d, (w / 2, h * 0.2), "NO", "cond_b", w * 0.6, h * 0.13, R + (255,))
            text(d, (w / 2, h * 0.37), "STOPPING", "cond_b", w * 0.84, h * 0.11, R + (255,))
            text(d, (w / 2, h * 0.58), "BUS", "cond_b", w * 0.7, h * 0.14, R + (255,))
            text(d, (w / 2, h * 0.78), "ZONE", "cond_b", w * 0.7, h * 0.14, R + (255,))
    elif i == 5:
        img, d = plate_base(w, h, border=R)
        text(d, (w / 2, h * 0.15), "TOW-AWAY", "cond_b", w * 0.84, h * 0.11, R + (255,))
        text(d, (w / 2, h * 0.33), "NO STOPPING", "cond_b", w * 0.84, h * 0.1, R + (255,))
        text(d, (w / 2, h * 0.52), "7AM - 9AM", "cond_b", w * 0.8, h * 0.1, R + (255,))
        text(d, (w / 2, h * 0.68), "4PM - 7PM", "cond_b", w * 0.8, h * 0.1, R + (255,))
        text(d, (w / 2, h * 0.85), "MON - FRI", "cond_b", w * 0.7, h * 0.09, R + (255,))
    elif i == 6:
        img, d = plate_base(w, h, border=G)
        text(d, (w / 2, h * 0.16), "2 HR PARKING", "cond_b", w * 0.84, h * 0.09, G + (255,))
        text(d, (w / 2, h * 0.32), "VEHICLES WITH", "cond_b", w * 0.8, h * 0.07, G + (255,))
        text(d, (w / 2, h * 0.43), "DISTRICT", "cond_b", w * 0.7, h * 0.07, G + (255,))
        text(d, (w / 2, h * 0.6), "%d" % rng.randint(20, 99), "cond_b", w * 0.6, h * 0.2, G + (255,))
        text(d, (w / 2, h * 0.8), "PERMITS EXEMPT", "cond_b", w * 0.84, h * 0.07, G + (255,))
    elif i == 7:
        img, d = plate_base(w, h, bg=(250, 250, 247), border=K)
        text(d, (w / 2, h * 0.2), "LOADING", "cond_b", w * 0.84, h * 0.12, K + (255,))
        text(d, (w / 2, h * 0.37), "ZONE", "cond_b", w * 0.7, h * 0.12, K + (255,))
        text(d, (w / 2, h * 0.6), "30 MIN", "cond_b", w * 0.7, h * 0.14, K + (255,))
        text(d, (w / 2, h * 0.82), "7AM - 6PM", "cond_b", w * 0.7, h * 0.09, K + (255,))
    elif i == 8:
        img, d = plate_base(w, h, border=R)
        p_circle(d, w * 0.5, h * 0.35, h * 0.2, R)
        text(d, (w / 2, h * 0.72), "<-  ->", "cond_b", w * 0.7, h * 0.12, R + (255,))
    elif i in (9, 10):
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        d.rounded_rectangle([1, 1, w - 2, h - 2], radius=10, fill=(250, 250, 247, 255))
        d.rectangle([1, 1, w - 2, h * 0.36], fill=T + (255,))
        text(d, (w / 2, h * 0.12), "BASIN", "cond_b", w * 0.8, h * 0.1, (255, 255, 255, 255))
        text(d, (w / 2, h * 0.26), "TRANSIT", "cond_b", w * 0.8, h * 0.1, (255, 255, 255, 255))
        if i == 9:
            text(d, (w / 2, h * 0.5), "BUS", "cond_b", w * 0.7, h * 0.14, K + (255,))
            text(d, (w / 2, h * 0.66), "STOP", "cond_b", w * 0.7, h * 0.14, K + (255,))
            text(d, (w / 2, h * 0.86), "INFO 555-0100", "cond_b", w * 0.84, h * 0.07, K + (255,))
        else:
            for k, n in enumerate(rng.sample([2, 4, 14, 16, 18, 20, 28, 30, 33, 51, 81, 204], 3)):
                y = h * (0.47 + 0.15 * k)
                d.rounded_rectangle([w * 0.18, y - h * 0.06, w * 0.82, y + h * 0.06], radius=6, fill=K + (255,))
                text(d, (w / 2, y), str(n), "cond_b", w * 0.5, h * 0.1, (255, 255, 255, 255))
    elif i in (12, 13, 14, 15):
        bgs = [(18, 60, 130), (200, 30, 40), (250, 210, 40), (14, 120, 140)]
        fgs = [(255, 255, 255), (255, 255, 255), (20, 20, 20), (255, 255, 255)]
        lines = [("COLOR", "TV"), ("FREE", "WIFI"), ("WEEKLY", "RATES"), ("POOL", "A/C")][i - 12]
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        d.rounded_rectangle([1, 1, w - 2, h - 2], radius=14, fill=bgs[i - 12] + (255,), outline=(240, 240, 240, 255), width=4)
        text(d, (w / 2, h * 0.34), lines[0], "cond_b", w * 0.84, h * 0.24, fgs[i - 12] + (255,))
        text(d, (w / 2, h * 0.66), lines[1], "cond_b", w * 0.84, h * 0.24, fgs[i - 12] + (255,))
    elif i in (16, 17):
        img, d = plate_base(w, h, border=K)
        sgn = -1 if i == 16 else 1
        cx, cy = w * 0.5, h * 0.5
        d.line([(cx - sgn * w * 0.32, cy), (cx + sgn * w * 0.26, cy)], fill=K + (255,), width=12)
        d.polygon([(cx + sgn * w * 0.38, cy), (cx + sgn * w * 0.16, cy - h * 0.12), (cx + sgn * w * 0.16, cy + h * 0.12)], fill=K + (255,))
    elif i == 20:
        img, d = plate_base(w, h, border=R)
        text(d, (w / 2, h * 0.2), "ANTI", "cond_b", w * 0.6, h * 0.12, R + (255,))
        text(d, (w / 2, h * 0.36), "GRIDLOCK", "cond_b", w * 0.84, h * 0.11, R + (255,))
        text(d, (w / 2, h * 0.52), "ZONE", "cond_b", w * 0.6, h * 0.11, R + (255,))
        text(d, (w / 2, h * 0.72), "$%d FINE" % rng.choice([93, 113, 163]), "cond_b", w * 0.84, h * 0.1, R + (255,))
    elif i == 21:
        img, d = plate_base(w, h, border=K)
        text(d, (w / 2, h * 0.2), "PASSENGER", "cond_b", w * 0.84, h * 0.1, K + (255,))
        text(d, (w / 2, h * 0.36), "LOADING", "cond_b", w * 0.84, h * 0.11, K + (255,))
        text(d, (w / 2, h * 0.52), "ONLY", "cond_b", w * 0.6, h * 0.11, K + (255,))
        text(d, (w / 2, h * 0.75), "5 MIN", "cond_b", w * 0.6, h * 0.13, K + (255,))
    elif i == 22:
        img, d = plate_base(w, h, border=R)
        text(d, (w / 2, h * 0.18), "NO PARKING", "cond_b", w * 0.86, h * 0.1, R + (255,))
        text(d, (w / 2, h * 0.36), "VEHICLES", "cond_b", w * 0.84, h * 0.1, R + (255,))
        text(d, (w / 2, h * 0.52), "OVER 6 FT", "cond_b", w * 0.84, h * 0.1, R + (255,))
        text(d, (w / 2, h * 0.68), "HIGH", "cond_b", w * 0.6, h * 0.1, R + (255,))
        text(d, (w / 2, h * 0.86), "2AM - 6AM", "cond_b", w * 0.7, h * 0.08, R + (255,))
    elif i == 23:
        img, d = plate_base(w, h, bg=(250, 250, 247), border=(30, 70, 160))
        text(d, (w / 2, h * 0.3), "METERED", "cond_b", w * 0.84, h * 0.12, (30, 70, 160, 255))
        text(d, (w / 2, h * 0.5), "PARKING", "cond_b", w * 0.84, h * 0.12, (30, 70, 160, 255))
        text(d, (w / 2, h * 0.72), "PAY AT METER", "cond_b", w * 0.84, h * 0.08, (30, 70, 160, 255))
    else:
        # 24-31: more stacks' worth of the common ones, slightly different times.
        img, d = plate_base(w, h, border=R if i % 2 == 0 else G)
        c = R if i % 2 == 0 else G
        if i % 2 == 0:
            p_circle(d, w * 0.5, h * 0.17, h * 0.1, R)
            day = ["MONDAY", "WEDNESDAY", "FRIDAY", "TUESDAY"][(i - 24) // 2]
            text(d, (w / 2, h * 0.38), ["10AM - 1PM", "8AM - 10AM", "12PM - 2PM", "6AM - 8AM"][(i - 24) // 2], "cond_b", w * 0.84, h * 0.1, c + (255,))
            text(d, (w / 2, h * 0.52), day, "cond_b", w * 0.84, h * 0.1, c + (255,))
            text(d, (w / 2, h * 0.66), "STREET", "cond_b", w * 0.7, h * 0.08, c + (255,))
            text(d, (w / 2, h * 0.77), "CLEANING", "cond_b", w * 0.8, h * 0.08, c + (255,))
            broom(d, w * 0.5, h * 0.89, h * 0.05, R)
        else:
            text(d, (w / 2, h * 0.2), ["1 HR", "2 HR", "30 MIN", "4 HR"][(i - 25) // 2], "cond_b", w * 0.8, h * 0.17, c + (255,))
            text(d, (w / 2, h * 0.38), "PARKING", "cond_b", w * 0.8, h * 0.11, c + (255,))
            text(d, (w / 2, h * 0.58), ["9AM - 6PM", "7AM - 7PM", "8AM - 8PM", "8AM - 4PM"][(i - 25) // 2], "cond_b", w * 0.8, h * 0.1, c + (255,))
            text(d, (w / 2, h * 0.78), "MON - SAT", "cond_b", w * 0.7, h * 0.09, c + (255,))
    # Sheeting: a faint grain, and the plate's edge stays crisp.
    return grain(img, 1.5, 800 + i)


DRAW = {"TENANT": draw_tenant, "NAME": draw_name, "VINYL": draw_vinyl, "BANNER": draw_banner,
        "LAMPB": draw_lampb, "PLATE": draw_plate}


def main():
    rng = random.Random(SEED)
    atlas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    means = {}
    for fam, (oy, cw, ch, cols, count) in FAMILIES.items():
        means[fam] = []
        for i in range(count):
            cell = DRAW[fam](i, cw * SS, ch * SS, rng)
            cell = cell.resize((cw, ch), Image.LANCZOS)
            x = (i % cols) * cw
            y = oy + (i // cols) * ch
            atlas.paste(cell, (x, y))
            a = np.asarray(cell).astype(float) / 255.0
            w8 = a[..., 3:4]
            lin = np.where(a[..., :3] <= 0.04045, a[..., :3] / 12.92, ((a[..., :3] + 0.055) / 1.055) ** 2.4)
            m = (lin * w8).sum(axis=(0, 1)) / max(1e-6, w8.sum())
            means[fam].append(tuple(float(v) for v in m))
    # Cut-out cells keep a colour under their transparent texels (the colour of their nearest
    # painted neighbour, by dilation), or mips and filtering bleed black round every letter.
    arr = np.asarray(atlas).copy()
    rgbf = arr[..., :3].astype(float)
    alpha = arr[..., 3].astype(float) / 255.0
    acc = rgbf * alpha[..., None]
    wsum = alpha.copy()
    for _ in range(4):
        img_acc = Image.fromarray(np.clip(acc / np.maximum(wsum[..., None], 1e-6), 0, 255).astype(np.uint8), "RGB")
        blurred = np.asarray(img_acc.filter(ImageFilter.BoxBlur(3))).astype(float)
        wb = np.asarray(Image.fromarray((np.clip(wsum, 0, 1) * 255).astype(np.uint8), "L").filter(ImageFilter.BoxBlur(3))).astype(float) / 255.0
        empty = wsum < 0.02
        acc[empty] = blurred[empty] * wb[empty][..., None]
        wsum[empty] = wb[empty]
    fill = np.clip(acc / np.maximum(wsum[..., None], 1e-6), 0, 255)
    out = np.where(alpha[..., None] > 0.0, rgbf, fill)
    arr[..., :3] = out.astype(np.uint8)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    Image.fromarray(arr, "RGBA").save(OUT, optimize=True)
    with open(TABLE, "w") as f:
        f.write("class_name SignArtTable\n")
        f.write("## GENERATED by tools/make_sign_art.py - do not edit. The LINEAR mean colour of the TENANT and\n")
        f.write("## NAME cells of assets/textures/boulevard_signs/sign_atlas.png (a tall pole sign's far box).\n\n")
        for fam in ("TENANT", "NAME"):
            cs = ", ".join("Color(%.4f, %.4f, %.4f)" % m for m in means[fam])
            f.write("const %s_MEAN: Array[Color] = [%s]\n" % (fam, cs))
        f.write("const FAMILIES := {%s}\n" % ", ".join(
            '"%s": [%d, %d, %d, %d, %d]' % (k, *v) for k, v in FAMILIES.items()))
    if "--preview" in sys.argv:
        os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
        bg = Image.new("RGBA", (W, H), (90, 90, 96, 255))
        bg.alpha_composite(Image.open(OUT))
        bg.convert("RGB").resize((W // 2, H // 2), Image.LANCZOS).save(os.path.join(ROOT, "build", "sign_preview.jpg"), quality=88)
    print("wrote", OUT, "and", TABLE)


if __name__ == "__main__":
    main()
