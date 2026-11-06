#!/usr/bin/env python3
"""Writes shaders/vinyl_lettering.gdshaderinc: the shop-window vinyl's stroke font and its text.

    python3 tools/make_vinyl_font.py [--preview out.png]

The font is a sans-serif drawn as centre-line strokes on a grid six units tall (the cap height),
x from 0 to the glyph's width; the shader draws a round-capped stroke of a chosen weight round
the centre lines (a distance field, so it antialiases and can carry an outline). Curves are arcs
sampled here into straight segments, at most MAX_SEGS a glyph.

Segments are packed four coordinates to a uint (x 6 bits in tenths of a unit, y 7 bits in tenths
with one unit of offset, so a comma or a dollar's bar can leave the cap box). Digits are tabular
(DIGIT_W), so a string with hash digits in it ('#', drawn as a digit of the shop's own hash) has
a width known here.

The text: Building.SHOP_NAMES (read from scripts/world/building.gd, in order, so a shop's name
index is the string index) followed by the PHRASES below, five characters to a uint. The smoke
test (tests/shop_vinyl_checks.gd) decodes the table and compares it with Building.SHOP_NAMES:
change the names, rerun this.

--preview renders every glyph and a few strings with the same distance field (PIL), to judge the
font in a second without Godot.
"""
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "shaders" / "vinyl_lettering.gdshaderinc"
MAX_SEGS = 16
DIGIT_W = 3.6
TRACK = 1.7      # space between two glyphs' centre-line boxes, in units
SPACE_ADV = 2.6   # a word space


def arc(cx, cy, rx, ry, a0, a1, n):
    pts = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        pts.append((cx + rx * math.cos(a), cy + ry * math.sin(a)))
    return pts


def ellipse(cx, cy, rx, ry, n):
    return arc(cx, cy, rx, ry, 90, 450, n)


# Each glyph: (width, [polyline, ...]); a polyline is a list of points.
G = {}
G["A"] = (4.2, [[(0, 0), (2.1, 6), (4.2, 0)], [(0.75, 2.0), (3.45, 2.0)]])
G["B"] = (3.9, [[(0, 0), (0, 6), (2.3, 6)] + arc(2.3, 4.55, 1.4, 1.45, 90, -90, 4)[1:] + [(0, 3.1)],
                [(0, 3.1), (2.35, 3.1)] + arc(2.35, 1.55, 1.55, 1.55, 90, -90, 4)[1:] + [(0, 0)]])
G["C"] = (4.0, [arc(2.15, 3, 2.15, 3, 42, 318, 12)])
G["D"] = (4.1, [[(0, 0), (0, 6), (1.4, 6)] + arc(1.4, 3, 2.7, 3, 90, -90, 8)[1:] + [(0, 0)]])
G["E"] = (3.5, [[(3.5, 6), (0, 6), (0, 0), (3.5, 0)], [(0, 3.1), (3.0, 3.1)]])
G["F"] = (3.4, [[(3.4, 6), (0, 6), (0, 0)], [(0, 3.1), (2.9, 3.1)]])
G["G"] = (4.3, [arc(2.2, 3, 2.15, 3, 42, 360, 11) + [(4.35, 0.4)], [(4.35, 2.8), (2.4, 2.8)]])
G["H"] = (4.0, [[(0, 0), (0, 6)], [(4, 0), (4, 6)], [(0, 3.1), (4, 3.1)]])
G["I"] = (0.0, [[(0, 0), (0, 6)]])
G["J"] = (3.0, [[(3, 6), (3, 1.5)] + arc(1.5, 1.5, 1.5, 1.5, 0, -180, 5)[1:]])
G["K"] = (3.9, [[(0, 0), (0, 6)], [(3.8, 6), (0, 2.1)], [(1.35, 3.45), (3.9, 0)]])
G["L"] = (3.3, [[(0, 6), (0, 0), (3.3, 0)]])
G["M"] = (5.0, [[(0, 0), (0, 6), (2.5, 1.0), (5, 6), (5, 0)]])
G["N"] = (4.0, [[(0, 0), (0, 6), (4, 0), (4, 6)]])
G["O"] = (4.5, [ellipse(2.25, 3, 2.25, 3, 14)])
G["P"] = (3.8, [[(0, 0), (0, 6), (2.2, 6)] + arc(2.2, 4.35, 1.6, 1.65, 90, -90, 5)[1:] + [(0, 2.7)]])
G["Q"] = (4.5, [ellipse(2.25, 3, 2.25, 3, 13), [(2.7, 1.3), (4.5, -0.4)]])
G["R"] = (3.9, [[(0, 0), (0, 6), (2.2, 6)] + arc(2.2, 4.4, 1.6, 1.6, 90, -90, 5)[1:] + [(0, 2.8)],
                [(1.9, 2.8), (3.9, 0)]])
G["S"] = (3.8, [arc(1.9, 4.5, 1.8, 1.5, 20, 270, 6) + arc(1.9, 1.5, 1.9, 1.5, 90, -160, 7)[1:]])
G["T"] = (4.0, [[(0, 6), (4, 6)], [(2, 6), (2, 0)]])
G["U"] = (4.0, [[(0, 6), (0, 2)] + arc(2, 2, 2, 2, 180, 360, 7)[1:] + [(4, 6)]])
G["V"] = (4.2, [[(0, 6), (2.1, 0), (4.2, 6)]])
G["W"] = (5.6, [[(0, 6), (1.35, 0), (2.8, 4.8), (4.25, 0), (5.6, 6)]])
G["X"] = (4.0, [[(0, 6), (4, 0)], [(0, 0), (4, 6)]])
G["Y"] = (4.2, [[(0, 6), (2.1, 2.9), (4.2, 6)], [(2.1, 2.9), (2.1, 0)]])
G["Z"] = (3.9, [[(0.1, 6), (3.9, 6), (0, 0), (3.9, 0)]])
# Tabular digits, all DIGIT_W wide (centred in their cell).
D = DIGIT_W
G["0"] = (D, [ellipse(D / 2, 3, D / 2, 3, 14)])
G["1"] = (D, [[(0.7, 4.8), (2.0, 6), (2.0, 0)]])
G["2"] = (D, [arc(1.8, 4.2, 1.8, 1.8, 165, -15, 6) + [(0, 0), (D, 0)]])
G["3"] = (D, [arc(1.75, 4.55, 1.65, 1.45, 155, -90, 6) + arc(1.8, 1.6, 1.8, 1.6, 90, -155, 6)[1:]])
G["4"] = (D, [[(2.75, 0), (2.75, 6), (0, 1.7), (D, 1.7)]])
G["5"] = (D, [[(3.3, 6), (0.45, 6), (0.25, 3.3)] + arc(1.75, 2.0, 1.85, 2.0, 140, -140, 8)[1:]])
six = [arc(1.8, 1.9, 1.8, 1.9, 180, 540, 10), [(0.0, 1.9), (0.35, 4.0), (1.2, 5.5), (2.9, 6.0)]]
G["6"] = (D, six)
G["9"] = (D, [[(D - x, 6 - y) for (x, y) in pl] for pl in six])
G["7"] = (D, [[(0, 6), (D, 6), (1.2, 0)]])
G["8"] = (D, [ellipse(D / 2, 4.55, 1.55, 1.45, 8), ellipse(D / 2, 1.55, 1.8, 1.55, 8)])
G["&"] = (4.0, [[(4.0, 0), (1.0, 3.6), (0.6, 4.3), (0.65, 5.2), (1.25, 5.95), (2.05, 5.95),
                  (2.6, 5.3), (2.55, 4.5), (1.9, 3.8), (0.35, 2.6), (0.05, 1.6), (0.35, 0.65),
                  (1.1, 0.0), (2.0, 0.0), (2.9, 0.6), (3.9, 2.3)]])
G["-"] = (2.2, [[(0, 2.6), (2.2, 2.6)]])
G["."] = (0.0, [[(0, 0.1), (0, 0.15)]])
G[","] = (0.4, [[(0.4, 0.3), (0.0, -0.8)]])
G[":"] = (0.0, [[(0, 0.1), (0, 0.15)], [(0, 3.7), (0, 3.75)]])
G["'"] = (0.0, [[(0, 6), (0, 4.5)]])
G["/"] = (3.0, [[(0, -0.3), (3, 6.3)]])
G["!"] = (0.0, [[(0, 6), (0, 1.9)], [(0, 0.1), (0, 0.15)]])
G["$"] = (3.8, [G["S"][1][0], [(1.9, -0.7), (1.9, 6.7)]])
G["%"] = (4.6, [ellipse(0.9, 4.8, 0.9, 1.2, 6), [(0.3, 0.0), (4.3, 6.0)], ellipse(3.7, 1.2, 0.9, 1.2, 6)])
G["("] = (1.4, [arc(3.0, 3, 2.6, 4.0, 132, 228, 6)])
G[")"] = (1.4, [arc(-1.6, 3, 2.6, 4.0, 48, -48, 6)])
G["#"] = (D, [[(1.2, 0.3), (1.6, 5.7)], [(2.4, 0.3), (2.8, 5.7)], [(0.2, 3.9), (3.5, 3.9)], [(0.1, 2.0), (3.4, 2.0)]])
G["+"] = (3.4, [[(0, 2.8), (3.4, 2.8)], [(1.7, 1.1), (1.7, 4.5)]])

# Character codes: 0 space, then CHARS. '@' is not a glyph: in a string it is a digit of the
# shop's own hash (drawn with the digit glyphs, so its width is DIGIT_W).
CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789&-.,:'/!$%()#+"
HASH_DIGIT = len(CHARS) + 1

# Phrases after the names. The shader picks them by index (VT_P_* below); keep the order or
# update vinyl_lettering's constants with it. Every business, number and claim is invented; the
# phone numbers are in the fictional 555-01xx range.
PHRASES = [
    "SALE",                  # 0  big promo
    "NOW OPEN",
    "OPEN 7 DAYS",
    "GRAND OPENING",
    "WE ACCEPT ALL CARDS",
    "CASH ONLY",             # 5
    "ATM INSIDE",
    "HABLAMOS ESPANOL",
    "COME IN, WE'RE OPEN",
    "50% OFF",
    "WALK-INS WELCOME",      # 10
    "FREE WIFI",
    "EVERYTHING MUST GO",
    "OPEN LATE",
    "CLOSING SALE",
    "HOURS",                 # 15 door plate heading
    "MON-FRI 9-6",
    "SAT 10-5",
    "SUN CLOSED",
    "MON-SAT 10-7",
    "SUN 11-4",              # 20
    "OPEN 7 DAYS",
    "7AM-10PM",
    "OPEN 24 HOURS",
    "MON-SUN 8-8",
    "OPEN",                  # 25 the door's OPEN plate
    "CALL 555-01@@",         # 26 under-name lines
    "SINCE 19@@",
    "FAMILY OWNED",
    "(213) 555-01@@",
    "SE HABLA ESPANOL",      # 30
    "LOCALLY OWNED",
    "EST. 19@@",
    "@@@@",                  # 33 the street number on the door's transom
    "THANK YOU",
    "PLEASE COME AGAIN",     # 35
    "NO PUBLIC RESTROOM",
    "PULL",
    "WASH & FOLD",           # 38 from here on, lines that belong to one kind of shop
    "COIN LAUNDRY",
    "FRESH DAILY",           # 40
    "DINE IN - TAKE OUT",
    "CATERING",
    "WE DELIVER",
    "ALTERATIONS",
    "NEW ARRIVALS",          # 45
    "BY APPOINTMENT",
    "MON-FRI 9-5",
    "FREE CONSULTATION",
    "GIFT CARDS",
]

# The room kinds (Building.ShopRoom / shop_interior.gdshaderinc ROOM_*), in order.
KINDS = ["RETAIL", "CLOTHING", "CAFE", "RESTAURANT", "LAUNDROMAT", "BARBER", "BANK", "LOBBY"]
ALL = set(KINDS)
SELLS = {"RETAIL", "CLOTHING"}
FOOD = {"CAFE", "RESTAURANT"}
# Which kinds of shop each phrase can stand in the window of: a line is only ever drawn on a kind
# it is listed for (tests/shop_vinyl_checks.gd holds the tables below to this). A BANK kind is
# also the dentist, the tax office and the money-transfer counter (Building.SHOP_NAME_ROOMS), a
# BARBER the nail salon and the tattoo parlour, so a kind's lines must fit every name under it.
FITS = {
    "SALE": SELLS, "50% OFF": SELLS, "CLOSING SALE": SELLS, "EVERYTHING MUST GO": SELLS,
    "NOW OPEN": ALL, "GRAND OPENING": ALL, "OPEN LATE": ALL - {"BANK"},
    "OPEN 7 DAYS": ALL - {"BANK"}, "COME IN, WE'RE OPEN": ALL,
    "WE ACCEPT ALL CARDS": SELLS | FOOD | {"BARBER", "LAUNDROMAT"},
    "CASH ONLY": FOOD | {"BARBER", "LAUNDROMAT", "RETAIL"}, "ATM INSIDE": {"RETAIL"},
    "HABLAMOS ESPANOL": ALL, "SE HABLA ESPANOL": ALL, "WALK-INS WELCOME": {"BARBER"},
    "FREE WIFI": FOOD | {"LAUNDROMAT"}, "WASH & FOLD": {"LAUNDROMAT"}, "COIN LAUNDRY": {"LAUNDROMAT"},
    "FRESH DAILY": {"CAFE"}, "DINE IN - TAKE OUT": FOOD, "CATERING": FOOD, "WE DELIVER": FOOD,
    "ALTERATIONS": {"CLOTHING"}, "NEW ARRIVALS": {"CLOTHING"}, "BY APPOINTMENT": {"BARBER", "BANK"},
    "MON-FRI 9-5": {"BANK"}, "FREE CONSULTATION": {"BANK"}, "GIFT CARDS": SELLS | FOOD | {"BARBER"},
    "CALL 555-01@@": ALL, "(213) 555-01@@": ALL, "SINCE 19@@": ALL, "EST. 19@@": ALL,
    "FAMILY OWNED": ALL, "LOCALLY OWNED": ALL,
}
# Per kind, eight lines for under the name and eight promos for another bay (repeats weight them).
GENERIC_TAGS = ["CALL 555-01@@", "(213) 555-01@@", "SINCE 19@@", "FAMILY OWNED"]
TAGS = {
    "RETAIL": ["OPEN 7 DAYS", "WE ACCEPT ALL CARDS", "LOCALLY OWNED", "EST. 19@@"] + GENERIC_TAGS,
    "CLOTHING": ["ALTERATIONS", "NEW ARRIVALS", "OPEN 7 DAYS", "EST. 19@@"] + GENERIC_TAGS,
    "CAFE": ["FREE WIFI", "FRESH DAILY", "DINE IN - TAKE OUT", "OPEN 7 DAYS"] + GENERIC_TAGS,
    "RESTAURANT": ["DINE IN - TAKE OUT", "CATERING", "WE DELIVER", "EST. 19@@"] + GENERIC_TAGS,
    "LAUNDROMAT": ["WASH & FOLD", "COIN LAUNDRY", "OPEN 7 DAYS", "FREE WIFI"] + GENERIC_TAGS,
    "BARBER": ["WALK-INS WELCOME", "BY APPOINTMENT", "OPEN 7 DAYS", "SE HABLA ESPANOL"] + GENERIC_TAGS,
    "BANK": ["MON-FRI 9-5", "BY APPOINTMENT", "SE HABLA ESPANOL", "FREE CONSULTATION"] + GENERIC_TAGS,
    "LOBBY": ["CALL 555-01@@", "(213) 555-01@@", "SINCE 19@@", "EST. 19@@", "LOCALLY OWNED",
              "SE HABLA ESPANOL", "FAMILY OWNED", "CALL 555-01@@"],
}
PROMOS = {
    "RETAIL": ["SALE", "50% OFF", "CLOSING SALE", "EVERYTHING MUST GO", "WE ACCEPT ALL CARDS",
               "ATM INSIDE", "GRAND OPENING", "CASH ONLY"],
    "CLOTHING": ["SALE", "50% OFF", "NEW ARRIVALS", "CLOSING SALE", "ALTERATIONS", "GRAND OPENING",
                 "WE ACCEPT ALL CARDS", "GIFT CARDS"],
    "CAFE": ["FREE WIFI", "NOW OPEN", "OPEN LATE", "FRESH DAILY", "DINE IN - TAKE OUT", "WE DELIVER",
             "CASH ONLY", "GRAND OPENING"],
    "RESTAURANT": ["OPEN LATE", "NOW OPEN", "CATERING", "WE DELIVER", "GRAND OPENING", "CASH ONLY",
                   "GIFT CARDS", "HABLAMOS ESPANOL"],
    "LAUNDROMAT": ["WASH & FOLD", "COIN LAUNDRY", "FREE WIFI", "OPEN 7 DAYS", "OPEN LATE",
                   "CASH ONLY", "NOW OPEN", "HABLAMOS ESPANOL"],
    "BARBER": ["WALK-INS WELCOME", "NOW OPEN", "OPEN 7 DAYS", "CASH ONLY", "GIFT CARDS",
               "HABLAMOS ESPANOL", "GRAND OPENING", "COME IN, WE'RE OPEN"],
    "BANK": ["HABLAMOS ESPANOL", "NOW OPEN", "BY APPOINTMENT", "FREE CONSULTATION", "MON-FRI 9-5",
             "SE HABLA ESPANOL", "COME IN, WE'RE OPEN", "GRAND OPENING"],
    "LOBBY": ["NOW OPEN", "HABLAMOS ESPANOL", "GRAND OPENING", "COME IN, WE'RE OPEN", "NOW OPEN",
              "SE HABLA ESPANOL", "GRAND OPENING", "NOW OPEN"],
}
# Promos drawn big and red, and those at the middle size.
LOUD = ["SALE", "50% OFF", "CLOSING SALE"]
MID = ["GRAND OPENING", "EVERYTHING MUST GO", "NEW ARRIVALS", "WASH & FOLD"]


def kind_tables():
    for k in KINDS:
        for line in TAGS[k] + PROMOS[k]:
            assert k in FITS[line], (k, line)
        assert len(TAGS[k]) == 8 and len(PROMOS[k]) == 8, k
    idx = {p: i for i, p in enumerate(PHRASES)}
    tag = [idx[p] for k in KINDS for p in TAGS[k]]
    promo = [idx[p] for k in KINDS for p in PROMOS[k]]
    # Per phrase, a bit per kind it fits (0: not a window line).
    mask = [sum(1 << i for i, k in enumerate(KINDS) if k in FITS.get(p, ())) for p in PHRASES]
    size = [2 if p in LOUD else (1 if p in MID else 0) for p in PHRASES]
    return tag, promo, mask, size


def shop_names():
    src = (ROOT / "scripts" / "world" / "building.gd").read_text()
    m = re.search(r"const SHOP_NAMES := \[(.*?)\]", src, re.S)
    return re.findall(r'"([^"]*)"', m.group(1))


def glyph_segments(ch):
    w, pls = G[ch]
    segs = []
    for pl in pls:
        for a, b in zip(pl[:-1], pl[1:]):
            segs.append((a[0], a[1], b[0], b[1]))
    assert len(segs) <= MAX_SEGS, (ch, len(segs))
    return w, segs


def pack_seg(s):
    x0, y0, x1, y1 = s
    q = [round(x0 * 10), round((y0 + 1) * 10), round(x1 * 10), round((y1 + 1) * 10)]
    assert 0 <= q[0] < 64 and 0 <= q[2] < 64 and 0 <= q[1] < 128 and 0 <= q[3] < 128, (s, q)
    return q[0] | (q[1] << 6) | (q[2] << 13) | (q[3] << 19)


def unpack_seg(u):
    return ((u & 63) / 10, ((u >> 6) & 127) / 10 - 1, ((u >> 13) & 63) / 10, ((u >> 19) & 127) / 10 - 1)


def code(ch):
    if ch == " ":
        return 0
    if ch == "@":
        return HASH_DIGIT
    return CHARS.index(ch) + 1


def advance(c):
    if c == 0:
        return SPACE_ADV
    if c == HASH_DIGIT:
        return DIGIT_W + TRACK
    return G[CHARS[c - 1]][0] + TRACK


def text_width(s):
    # The ink's centre-line extent: the advances less the last glyph's tracking.
    if not s:
        return 0.0
    return sum(advance(code(ch)) for ch in s) - TRACK


def build():
    names = shop_names()
    strings = names + PHRASES
    for s in strings:
        for ch in s:
            assert ch == " " or ch == "@" or ch in CHARS, (s, ch)
    # Glyph table.
    starts, counts, adv, segs = [0], [0], [SPACE_ADV], [0]
    for ch in CHARS:
        w, gs = glyph_segments(ch)
        starts.append(len(segs))
        counts.append(len(gs))
        adv.append(w + TRACK)
        segs.extend(pack_seg(s) for s in gs)
    # Text table: five 6-bit codes per uint.
    text, t_start, t_len, t_width = [], [], [], []
    cursor = 0
    for s in strings:
        t_start.append(cursor)
        t_len.append(len(s))
        t_width.append(text_width(s))
        cursor += len(s)
        text.extend(code(ch) for ch in s)
    packed = []
    for i in range(0, len(text), 5):
        u = 0
        for k, c in enumerate(text[i:i + 5]):
            assert c < 64
            u |= c << (6 * k)
        packed.append(u)
    return names, strings, starts, counts, adv, segs, packed, t_start, t_len, t_width


def fmt_list(vals, per=12, kind="int"):
    if kind == "float":
        items = ["%.2f" % v for v in vals]
    elif kind == "uint":
        items = ["%du" % v for v in vals]
    else:
        items = [str(v) for v in vals]
    lines = []
    for i in range(0, len(items), per):
        lines.append("\t" + ", ".join(items[i:i + per]))
    return ",\n".join(lines)


def write():
    names, strings, starts, counts, adv, segs, packed, t_start, t_len, t_width = build()
    n_g = len(starts)
    p0 = len(names)
    out = []
    out.append("// Shop-window vinyl: a stroke font and the text it writes (building.gdshader's shop_decal()).")
    out.append("// GENERATED by tools/make_vinyl_font.py - do not edit by hand; rerun it after changing")
    out.append("// Building.SHOP_NAMES or the phrases (tests/shop_vinyl_checks.gd decodes this file and")
    out.append("// compares it with Building.SHOP_NAMES).")
    out.append("//")
    out.append("// Glyphs are centre-line segments on a grid six units tall; vt_ink() draws them as a")
    out.append("// round-capped stroke of a given weight with an optional outline, antialiased by the pixel")
    out.append("// size it is handed and faded to the text's average ink once a stroke is under a pixel.")
    out.append("// Codes: 0 space, 1.. '%s', %d a digit of the shop's own hash." % (CHARS, HASH_DIGIT))
    out.append("// Needs shop_hash(uint, uint) from the including shader.")
    out.append("")
    out.append("const int VT_GLYPHS = %d;" % n_g)
    out.append("const int VT_HASH_DIGIT = %d;" % HASH_DIGIT)
    out.append("const int VT_MAX_SEGS = %d;" % MAX_SEGS)
    out.append("const int VT_MAX_LEN = %d;" % max(t_len))
    out.append("const float VT_TRACK = %.2f;" % TRACK)
    out.append("const float VT_DIGIT_ADV = %.2f;" % (DIGIT_W + TRACK))
    out.append("// The first phrase's string index (strings 0..%d are Building.SHOP_NAMES)." % (p0 - 1))
    out.append("const int VT_PHRASE0 = %d;" % p0)
    out.append("const int VT_STRINGS = %d;" % len(strings))
    out.append("const int VT_G_START[%d] = int[](\n%s);" % (n_g, fmt_list(starts, 16)))
    out.append("const int VT_G_COUNT[%d] = int[](\n%s);" % (n_g, fmt_list(counts, 16)))
    out.append("const float VT_ADV[%d] = float[](\n%s);" % (n_g, fmt_list(adv, 12, "float")))
    out.append("// x0 6 bits, y0 + 1 7 bits, x1 6 bits, y1 + 1 7 bits, all in tenths of a unit.")
    out.append("const uint VT_SEG[%d] = uint[](\n%s);" % (len(segs), fmt_list(segs, 8, "uint")))
    out.append("// Five 6-bit codes per uint.")
    out.append("const uint VT_TEXT[%d] = uint[](\n%s);" % (len(packed), fmt_list(packed, 8, "uint")))
    out.append("const int VT_T_START[%d] = int[](\n%s);" % (len(strings), fmt_list(t_start, 16)))
    out.append("const int VT_T_LEN[%d] = int[](\n%s);" % (len(strings), fmt_list(t_len, 16)))
    out.append("// Each string's width in units (centre lines; the stroke adds its weight either side).")
    out.append("const float VT_T_WIDTH[%d] = float[](\n%s);" % (len(strings), fmt_list(t_width, 12, "float")))
    out.append("// The strings, for reading this file:")
    for i, s in enumerate(strings):
        out.append("//   %d %s" % (i, s))
    tag, promo, mask, size = kind_tables()
    out.append("// Per room kind (ROOM_*, in order), eight lines under the name and eight promos, as phrase")
    out.append("// numbers (add VT_PHRASE0). Every line fits the kind: VT_FITS (a bit per kind) says which")
    out.append("// kinds a phrase may stand in the window of, and the check holds the tables to it.")
    out.append("const int VT_TAG[64] = int[](\n%s);" % fmt_list(tag, 8))
    out.append("const int VT_PROMO[64] = int[](\n%s);" % fmt_list(promo, 8))
    out.append("const int VT_FITS[%d] = int[](\n%s);" % (len(mask), fmt_list(mask, 16)))
    out.append("// A promo's size: 0 small, 1 middle, 2 big and red.")
    out.append("const int VT_PROMO_SIZE[%d] = int[](\n%s);" % (len(size), fmt_list(size, 16)))
    out.append(LIB)
    OUT.write_text("\n".join(out) + "\n")
    print("wrote", OUT.relative_to(ROOT), "-", n_g, "glyphs,", len(segs), "segments,", len(strings), "strings,",
          len(packed), "text words")


LIB = r"""
int vt_char(int s, int i) {
	int k = VT_T_START[s] + i;
	return int((VT_TEXT[k / 5] >> uint(6 * (k % 5))) & 63u);
}

float vt_seg_dist(vec2 p, uint u) {
	vec2 a = vec2(float(u & 63u), float((u >> 6u) & 127u)) * 0.1 - vec2(0.0, 1.0);
	vec2 b = vec2(float((u >> 13u) & 63u), float((u >> 19u) & 127u)) * 0.1 - vec2(0.0, 1.0);
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-5), 0.0, 1.0);
	return length(pa - ba * h);
}

// Distance (units) from p to glyph code c.
float vt_glyph_dist(int c, vec2 p) {
	if (c <= 0 || c >= VT_GLYPHS) {
		return 1e3;
	}
	int start = VT_G_START[c];
	int count = VT_G_COUNT[c];
	float d = 1e3;
	for (int i = 0; i < VT_MAX_SEGS; i++) {
		if (i >= count) {
			break;
		}
		d = min(d, vt_seg_dist(p, VT_SEG[start + i]));
	}
	return d;
}

float vt_width(int s) {
	return VT_T_WIDTH[s];
}

// String s, its left end at q.x = 0 and its baseline at q.y = 0 (metres), cap height h. `weight`
// is the stroke's half width in units (0.42 regular, 0.55 bold), `outline` an outline's width
// round it in units (0 none). `key` feeds the hash digits. `px_m` is a pixel's size in metres.
// Returns (ink, outline) cover.
vec2 vt_ink(int s, vec2 q, float h, float weight, float outline, uint key, float px_m) {
	float unit = h / 6.0;
	vec2 p = q / unit;
	float pad = weight + outline + 0.2;
	float w = VT_T_WIDTH[s];
	if (p.x < -pad || p.x > w + pad || p.y < -1.0 - pad || p.y > 7.0 + pad) {
		return vec2(0.0);
	}
	float px = px_m / unit;
	// Under a pixel a stroke aliases; past that the text is drawn as its average.
	float avg_mix = smoothstep(1.0, 2.4, px / max(weight, 0.05));
	float box = step(0.0, p.y) * step(p.y, 6.0) * step(0.0, p.x) * step(p.x, w);
	if (avg_mix >= 0.999) {
		return vec2(box * (0.20 + weight * 0.25), box * outline * 0.25);
	}
	// Walk the string to the glyph under p (and its neighbour on the near side, whose stroke
	// can reach over the gap at a heavy weight - it never does at these trackings, so one).
	int n = VT_T_LEN[s];
	float x = 0.0;
	int c = 0;
	float gx = 0.0;
	int digit = 0;
	for (int i = 0; i < VT_MAX_LEN; i++) {
		if (i >= n) {
			break;
		}
		int ci = vt_char(s, i);
		float adv = ci == VT_HASH_DIGIT ? VT_DIGIT_ADV : VT_ADV[ci];
		if (ci == VT_HASH_DIGIT) {
			digit++;
		}
		if (p.x < x + adv - VT_TRACK * 0.5 || i == n - 1) {
			c = ci;
			gx = x;
			break;
		}
		x += adv;
	}
	if (c == VT_HASH_DIGIT) {
		// A digit of the shop's own hash (code 27 is '0').
		c = 27 + int(shop_hash(key, 60u + uint(digit)) % 10u);
	}
	float d = vt_glyph_dist(c, p - vec2(gx, 0.0));
	float aa = max(px, 0.02) * 0.75;
	float ink = 1.0 - smoothstep(weight - aa, weight + aa, d);
	float ring = outline > 0.0 ? (1.0 - smoothstep(weight + outline - aa, weight + outline + aa, d)) - ink : 0.0;
	return mix(vec2(ink, ring), vec2(box * (0.20 + weight * 0.25), box * outline * 0.25), avg_mix);
}
"""


def preview(path):
    from PIL import Image
    import numpy as np
    names, strings, starts, counts, adv, segs, packed, t_start, t_len, t_width = build()
    lines = [CHARS[:26], CHARS[26:], "PHARMACY  NAILS & SPA  COFFEE STOP", "CALL 555-0142  SINCE 1987  50% OFF",
             "COME IN, WE'RE OPEN  (213) 555-0199", "MON-FRI 9-6  SUN CLOSED  $9.99"]
    unit = 9.0
    W = 1400
    H = int(len(lines) * 10 * unit) + 20
    img = np.ones((H, W), np.float32)
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    for li, line in enumerate(lines):
        base = H - 10 - (len(lines) - 1 - li) * 10 * unit - 2 * unit
        x = 2.0
        for ch in line:
            c = code(ch)
            if c and c != HASH_DIGIT:
                gstart, gcount = starts[c], counts[c]
                for u in segs[gstart:gstart + gcount]:
                    x0, y0, x1, y1 = unpack_seg(u)
                    ax, ay = (x + x0) * unit, base - y0 * unit
                    bx, by = (x + x1) * unit, base - y1 * unit
                    pax, pay = xs - ax, ys - ay
                    bax, bay = bx - ax, by - ay
                    hh = np.clip((pax * bax + pay * bay) / max(bax * bax + bay * bay, 1e-5), 0, 1)
                    d = np.hypot(pax - bax * hh, pay - bay * hh) / unit
                    img = np.minimum(img, np.clip((d - 0.48) * unit + 0.5, 0, 1))
            x += advance(c) if c != HASH_DIGIT else DIGIT_W + TRACK
    Image.fromarray((img * 255).astype(np.uint8)).save(path)
    print("preview", path)


if __name__ == "__main__":
    write()
    if "--preview" in sys.argv:
        preview(sys.argv[sys.argv.index("--preview") + 1])
