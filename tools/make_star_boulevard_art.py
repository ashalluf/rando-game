#!/usr/bin/env python3
"""The walk of fame's lettering atlas (StarBoulevard, shaders/walk_of_fame.gdshader).

    python3 tools/make_star_boulevard_art.py

Writes assets/textures/star_boulevard/walk_atlas.png (1024 x 2048, one channel, white ink on
black) and scripts/world/star_names.gd (the names, so the game, the checks and the shader agree).

Layout (the shader's contract, mirrored by StarBoulevard.ATLAS_*):
  * rows 0-31 (y 0..1023): the names on the stars in brass capitals, one per 256 x 32 cell,
    four to a row, cell k at (k % 4, k // 4);
  * rows 32-63 (y 1024..2047 less the last 64 px): the same names as SIGNATURES in the
    forecourt's wet concrete (a slanted hand with a swash under it and a year), cell k at
    (k % 4, 32 + k // 4);
  * the last 64 px: the emblems, 64 x 64 each from x 0: film camera, television, record,
    microphone, theatre masks.

Every name is INVENTED (old-fashioned first names and made-up surnames): never a real person.
Fonts (rendered offline only, nothing ships but the image): DejaVu Serif Bold (Bitstream Vera
licence) for the capitals, Liberation Serif Bold Italic (SIL OFL) for the signatures.
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures", "star_boulevard", "walk_atlas.png")
TABLE = os.path.join(ROOT, "scripts", "world", "star_names.gd")
W, H = 1024, 2048
CW, CH = 256, 32
N = 120

FIRST = ["VERA", "DEXTER", "MAVIS", "LORNA", "OTTIS", "CORLISS", "DELPHINE", "HOLLIS", "IMOGEN",
         "BARNABY", "ROSALIND", "ELWOOD", "MARGO", "THADDEUS", "PEARL", "LEOPOLD", "ODETTE", "CASPER",
         "WINIFRED", "AUGUSTUS", "LUCINDA", "FENWICK", "OPAL", "SYLVESTER", "BEATRIX", "MONTGOMERY",
         "CLEMENTINE", "RUFUS", "DAPHNE", "AMBROSE", "TALLULAH", "VIRGIL", "ESMERALDA", "PERCIVAL",
         "LAVINIA", "CORNELIUS", "HONORA", "LAZLO", "MIRABEL", "GIDEON", "SAFFRON", "BENEDICT",
         "ROXANNE", "ALISTAIR", "CORA", "DESMOND", "FLORA", "EZEKIEL", "JUNO", "LANCELOT", "IVY",
         "MORDECAI", "PRISCILLA", "RAINER", "SELINA", "TOBIAS", "URSULA", "WENDELL", "XIMENA", "YOLANDA"]
LAST = ["BELLWEATHER", "QUILLFEATHER", "VANTREECE", "ASHGROVE", "HALLORAN", "DUSKWOOD", "MERRIVALE",
        "STARLING", "CRESSWELL", "LOCKHAVEN", "PENBRIDGE", "WYNDHAM", "FAIRCLOTH", "GOLDSBY",
        "MOONEYHAM", "SILVERTHORN", "BLACKWOOD", "CARRAWAY", "DELACORTE", "EVERHART", "FOXWORTH",
        "GALLOWAY", "HAWTHORNE", "IVERSON", "JARROWAY", "KESTREL", "LARKSPUR", "MAYBROOK",
        "NIGHTINGALE", "OAKSHOTT", "PELLINGTON", "QUINTRELL", "RAVENSCROFT", "SOMERVALE",
        "THISTLEWOOD", "UNDERHAY", "VALENTYNE", "WHITLOCK", "YARBOROUGH", "ZELLWEGAR", "AMBERLEY",
        "BRISTOWE", "CALLOWAY", "DUNMORE", "ELLSWORTH", "FERNSBY", "GRAYMARSH", "HOLLOWAY",
        "INGRAMSBY", "JESSOP", "KILBRIDE", "LOVEJOY", "MARCHBANK", "NORTHCOTT", "OSGOODE"]


def names():
    rng = random.Random(4242)
    out = []
    seen_first = {}
    seen_last = set()
    while len(out) < N:
        f = rng.choice(FIRST)
        l = rng.choice(LAST)
        if l in seen_last and rng.random() < 0.85:
            continue
        if seen_first.get(f, 0) >= 2:
            continue
        n = f + " " + l
        if n in out or len(n) > 22:
            continue
        out.append(n)
        seen_first[f] = seen_first.get(f, 0) + 1
        seen_last.add(l)
    return out


def fit_font(path, text, w, h, start):
    size = start
    while size > 8:
        f = ImageFont.truetype(path, size)
        b = f.getbbox(text)
        if b[2] - b[0] <= w and b[3] - b[1] <= h:
            return f
        size -= 1
    return ImageFont.truetype(path, 8)


def caps_cell(img, k, text):
    cx, cy = (k % 4) * CW, (k // 4) * CH
    f = fit_font("/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf", text, CW - 16, CH - 8, 24)
    d = ImageDraw.Draw(img)
    b = f.getbbox(text)
    tw, th = b[2] - b[0], b[3] - b[1]
    d.text((cx + (CW - tw) / 2 - b[0], cy + (CH - th) / 2 - b[1]), text, fill=255, font=f)


def sig_cell(img, k, text, rng):
    cx, cy = (k % 4) * CW, 1024 + (k // 4) * CH
    # A hand: the name in title case, slanted a little more, a swash under it, a year after it.
    parts = text.title().split(" ")
    s = parts[0][0] + ". " + parts[1] if rng.random() < 0.4 else parts[0] + " " + parts[1]
    year = str(rng.randint(1927, 1979))
    tile = Image.new("L", (CW * 2, CH * 2), 0)
    f = fit_font("/usr/share/fonts/truetype/liberation/LiberationSerif-BoldItalic.ttf", s, CW * 2 - 120, CH * 2 - 22, 46)
    d = ImageDraw.Draw(tile)
    b = f.getbbox(s)
    x0 = 8 - b[0]
    y0 = 4 - b[1]
    d.text((x0, y0), s, fill=255, font=f)
    fy = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSerif-Italic.ttf", 22)
    d.text((b[2] - b[0] + 22, 22), year, fill=230, font=fy)
    # The swash: a quadratic curve under the name, thicker in the middle.
    ex = b[2] - b[0] + 10
    py = CH * 2 - 10
    pts = []
    for i in range(41):
        t = i / 40.0
        x = 10 + (ex - 10) * t
        y = py - 6 * math.sin(t * math.pi) + 4 * (1 - t)
        pts.append((x, y))
    d.line(pts, fill=255, width=3)
    tile = tile.transform(tile.size, Image.AFFINE, (1, 0.18, -6, 0, 1, 0), resample=Image.BICUBIC)
    tile = tile.resize((CW, CH), Image.LANCZOS)
    img.paste(tile, (cx, cy))


def emblem(img, slot, kind):
    s = 64 * 4
    t = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(t)
    if kind == "camera":
        # A cine camera: body, two reels on top, the lens to the left.
        d.rounded_rectangle((70, 120, 200, 196), 10, fill=255)
        d.ellipse((60, 40, 130, 110), fill=255)
        d.ellipse((130, 40, 200, 110), fill=255)
        d.ellipse((82, 62, 108, 88), fill=0)
        d.ellipse((152, 62, 178, 88), fill=0)
        d.polygon([(70, 140), (28, 122), (28, 194), (70, 176)], fill=255)
        d.rectangle((110, 196, 150, 232), fill=255)
    elif kind == "tv":
        d.rounded_rectangle((36, 70, 220, 210), 22, fill=255)
        d.rounded_rectangle((56, 88, 176, 192), 14, fill=0)
        d.ellipse((188, 96, 208, 116), fill=0)
        d.ellipse((188, 132, 208, 152), fill=0)
        d.line([(128, 70), (90, 24)], fill=255, width=9)
        d.line([(128, 70), (170, 24)], fill=255, width=9)
    elif kind == "record":
        d.ellipse((30, 30, 226, 226), fill=255)
        for r in (80, 66, 52):
            d.ellipse((128 - r, 128 - r, 128 + r, 128 + r), outline=0, width=3)
        d.ellipse((96, 96, 160, 160), fill=0)
        d.ellipse((112, 112, 144, 144), fill=255)
        d.ellipse((122, 122, 134, 134), fill=0)
    elif kind == "mic":
        d.rounded_rectangle((92, 22, 164, 138), 36, fill=255)
        for y in range(44, 130, 14):
            d.line([(100, y), (156, y)], fill=0, width=4)
        d.arc((70, 70, 186, 176), 0, 180, fill=255, width=10)
        d.rectangle((122, 176, 134, 214), fill=255)
        d.rounded_rectangle((84, 210, 172, 228), 6, fill=255)
    elif kind == "masks":
        # Two masks overlapping: one smiling, one frowning.
        d.ellipse((30, 40, 140, 190), fill=255)
        d.ellipse((116, 66, 226, 216), fill=255)
        d.ellipse((116, 66, 226, 216), outline=0, width=6)
        for (x, y) in ((58, 92), (98, 92)):
            d.ellipse((x - 12, y - 8, x + 12, y + 8), fill=0)
        d.arc((52, 110, 118, 168), 20, 160, fill=0, width=7)
        for (x, y) in ((146, 120), (190, 120)):
            d.ellipse((x - 12, y - 8, x + 12, y + 8), fill=0)
        d.arc((138, 168, 198, 214), 200, 340, fill=0, width=7)
    t = t.resize((64, 64), Image.LANCZOS)
    img.paste(t, (slot * 64, H - 64))


def main():
    img = Image.new("L", (W, H), 0)
    ns = names()
    rng = random.Random(77)
    for k, n in enumerate(ns):
        caps_cell(img, k, n)
        sig_cell(img, k, n, rng)
    for slot, kind in enumerate(["camera", "tv", "record", "mic", "masks"]):
        emblem(img, slot, kind)
    img.save(OUT)
    with open(TABLE, "w") as fh:
        fh.write("class_name StarNames\n## Written by tools/make_star_boulevard_art.py: the names on the walk of fame's stars and the\n")
        fh.write("## forecourt's slabs, in the order of their cells in walk_atlas.png. Every one INVENTED.\n\n")
        fh.write("const NAMES := [\n")
        for i in range(0, len(ns), 4):
            fh.write("\t" + ", ".join('"%s"' % n for n in ns[i:i + 4]) + ",\n")
        fh.write("]\n")
    print("wrote", OUT, "and", TABLE, len(ns), "names")


if __name__ == "__main__":
    main()
