#!/usr/bin/env python3
"""Bus bench ad backs for StreetFurniture (scripts/world/street_furniture.gd).

Writes assets/textures/street_furniture/bench_ads.jpg: an atlas of BENCH_ADS rows, each
1024 x ROW_H px, the painted ad on a Los Angeles bus bench's back rest (1.80 x 0.56 m). Every
advertiser, name and number is INVENTED (realtors, injury lawyers, bail bonds, a dentist, a
taco stand, the bench company's own "your ad here"); phone numbers are 555 numbers. The art is
drawn flat like a sign painter's or a vinyl print: a field colour, a band, big lettering, a
small line of fine print. Weathering is the shader's job (street_furniture.gdshader).

Run: python3 tools/make_bench_ads.py, then godot --headless --path . --import and switch the
new .import to compress/mode=2, mipmaps on (CLAUDE.md, textures).
The row order is a contract with StreetFurniture.BENCH_ADS (its count) and the shader's
`ad_rows` uniform.
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W = 1024
ROW_H = 320
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "textures", "street_furniture", "bench_ads.jpg")
FONT_DIRS = ["/usr/share/fonts/truetype/dejavu", "/usr/share/fonts/truetype/liberation", "/usr/share/fonts/truetype/freefont"]


def font(name, size):
    for d in FONT_DIRS:
        p = os.path.join(d, name)
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


SANS_B = "DejaVuSans-Bold.ttf"
COND_B = "LiberationSans-Bold.ttf"
SERIF_B = "DejaVuSerif-Bold.ttf"
SERIF_I = "LiberationSerif-BoldItalic.ttf"
SANS = "LiberationSans-Regular.ttf"


def fit(draw, text, fname, size, max_w):
    """The biggest size up to `size` at which `text` fits in `max_w` px."""
    while size > 10:
        f = font(fname, size)
        if draw.textlength(text, font=f) <= max_w:
            return f
        size -= 2
    return font(fname, size)


def text_c(draw, cx, y, text, fname, size, fill, max_w=W - 60):
    f = fit(draw, text, fname, size, max_w)
    w = draw.textlength(text, font=f)
    draw.text((cx - w / 2, y), text, font=f, fill=fill)
    return f


def text_l(draw, x, y, text, fname, size, fill, max_w):
    f = fit(draw, text, fname, size, max_w)
    draw.text((x, y), text, font=f, fill=fill)
    return f


def house_icon(draw, x, y, s, fill):
    draw.polygon([(x, y + s * 0.45), (x + s * 0.5, y), (x + s, y + s * 0.45)], fill=fill)
    draw.rectangle([x + s * 0.15, y + s * 0.42, x + s * 0.85, y + s], fill=fill)
    draw.rectangle([x + s * 0.42, y + s * 0.62, x + s * 0.58, y + s], fill=(255, 255, 255))


def scales_icon(draw, x, y, s, fill):
    draw.rectangle([x + s * 0.47, y, x + s * 0.53, y + s * 0.9], fill=fill)
    draw.rectangle([x + s * 0.25, y + s * 0.9, x + s * 0.75, y + s], fill=fill)
    draw.line([(x + s * 0.05, y + s * 0.2), (x + s * 0.95, y + s * 0.2)], fill=fill, width=max(3, int(s * 0.05)))
    for cx in (x + s * 0.15, x + s * 0.85):
        draw.pieslice([cx - s * 0.15, y + s * 0.3, cx + s * 0.15, y + s * 0.6], 0, 180, fill=fill)


def tooth_icon(draw, x, y, s, fill):
    draw.ellipse([x, y, x + s, y + s * 0.6], fill=fill)
    draw.polygon([(x + s * 0.05, y + s * 0.35), (x + s * 0.3, y + s), (x + s * 0.5, y + s * 0.55), (x + s * 0.7, y + s), (x + s * 0.95, y + s * 0.35)], fill=fill)


def ad_realtor_a(d):
    d.rectangle([0, 0, W, ROW_H], fill=(242, 238, 228))
    d.rectangle([0, 0, 300, ROW_H], fill=(150, 26, 38))
    house_icon(d, 70, 52, 160, (255, 255, 255))
    text_c(d, 150, 236, "SOLD!", SANS_B, 46, (255, 255, 255), 260)
    text_l(d, 330, 22, "MARISELA ONTIVEROS", COND_B, 64, (150, 26, 38), 670)
    text_l(d, 332, 98, "YOUR NEIGHBORHOOD REALTOR", SANS_B, 34, (40, 40, 44), 660)
    text_l(d, 332, 150, "SE HABLA ESPAÑOL  ·  FREE HOME VALUE", SANS, 28, (60, 60, 64), 660)
    text_l(d, 330, 200, "323-555-0142", SANS_B, 92, (20, 22, 30), 670)


def ad_lawyer_a(d):
    d.rectangle([0, 0, W, ROW_H], fill=(16, 32, 86))
    d.rectangle([0, ROW_H - 70, W, ROW_H], fill=(250, 196, 30))
    text_c(d, W / 2, 14, "HURT IN A CRASH?", SANS_B, 74, (255, 255, 255))
    text_c(d, W / 2, 104, "ROLAND & PIKE  INJURY ATTORNEYS", SERIF_B, 50, (250, 196, 30))
    text_c(d, W / 2, 172, "NO FEE UNLESS WE WIN  ·  HABLAMOS ESPAÑOL", SANS_B, 30, (220, 226, 240))
    text_c(d, W / 2, ROW_H - 64, "1-800-555-0199", SANS_B, 58, (16, 32, 86))


def ad_bail(d):
    d.rectangle([0, 0, W, ROW_H], fill=(250, 214, 20))
    d.rectangle([0, 0, W, 86], fill=(18, 18, 18))
    text_c(d, W / 2, 10, "SECOND CHANCE BAIL BONDS", SANS_B, 60, (250, 214, 20))
    text_c(d, W / 2, 100, "24 HRS", SANS_B, 96, (18, 18, 18))
    text_c(d, W / 2, 206, "213-555-0187  ·  FAST · CONFIDENTIAL · LOW DOWN", SANS_B, 34, (18, 18, 18))
    text_c(d, W / 2, 262, "PAYMENT PLANS  ·  SE HABLA ESPAÑOL", SANS, 28, (40, 40, 40))


def ad_abogados(d):
    d.rectangle([0, 0, W, ROW_H], fill=(255, 255, 255))
    d.rectangle([0, 0, W, 18], fill=(196, 22, 28))
    d.rectangle([0, ROW_H - 18, W, ROW_H], fill=(196, 22, 28))
    scales_icon(d, 40, 70, 180, (20, 60, 140))
    text_l(d, 250, 34, "¿ACCIDENTE DE AUTO?", SANS_B, 60, (196, 22, 28), 740)
    text_l(d, 252, 112, "GARZA & BELLWOOD  ABOGADOS", SERIF_B, 46, (20, 60, 140), 740)
    text_l(d, 252, 176, "CONSULTA GRATIS · 7 DÍAS", SANS_B, 30, (50, 50, 56), 740)
    text_l(d, 250, 214, "(562) 555-0170", SANS_B, 76, (20, 20, 26), 740)


def ad_realtor_b(d):
    d.rectangle([0, 0, W, ROW_H], fill=(10, 72, 66))
    d.rectangle([24, 24, W - 24, ROW_H - 24], outline=(232, 214, 160), width=6)
    text_c(d, W / 2, 46, "THE HOME TEAM", SERIF_I, 82, (232, 214, 160))
    text_c(d, W / 2, 140, "DARNELL & JUNE PRICEWOOD  ·  REALTORS", SANS_B, 38, (255, 255, 255))
    text_c(d, W / 2, 196, "BUYING · SELLING · 30 YEARS ON THIS STREET", SANS, 28, (200, 222, 214))
    text_c(d, W / 2, 238, "310-555-0116", SANS_B, 52, (232, 214, 160))


def ad_dental(d):
    d.rectangle([0, 0, W, ROW_H], fill=(226, 244, 250))
    d.rectangle([0, 0, 22, ROW_H], fill=(0, 130, 190))
    tooth_icon(d, 56, 70, 170, (0, 130, 190))
    text_l(d, 260, 30, "BRIGHT SMILE FAMILY DENTAL", SANS_B, 56, (0, 96, 150), 730)
    text_l(d, 262, 104, "DR. ELENA FENWICK-SATO, DDS", SERIF_B, 38, (30, 40, 50), 730)
    text_l(d, 262, 160, "KIDS · ADULTS · MOST INSURANCE · OPEN SATURDAYS", SANS, 28, (50, 60, 70), 730)
    text_l(d, 260, 206, "818-555-0123", SANS_B, 86, (0, 96, 150), 730)


def ad_tacos(d):
    d.rectangle([0, 0, W, ROW_H], fill=(232, 92, 28))
    for i in range(0, W, 64):
        d.polygon([(i, ROW_H), (i + 32, ROW_H - 40), (i + 64, ROW_H)], fill=(250, 200, 50))
    text_c(d, W / 2, 16, "TACOS EL FARO DORADO", SANS_B, 72, (255, 255, 255))
    text_c(d, W / 2, 112, "AL PASTOR · ASADA · BIRRIA", SERIF_B, 48, (255, 236, 180))
    text_c(d, W / 2, 182, "2 BLOCKS AHEAD  ·  OPEN LATE  ·  555-0161", SANS_B, 34, (255, 255, 255))


def ad_your_ad(d):
    d.rectangle([0, 0, W, ROW_H], fill=(246, 246, 240))
    d.rectangle([0, 0, W, ROW_H], outline=(30, 90, 170), width=14)
    text_c(d, W / 2, 34, "YOUR AD HERE", SANS_B, 108, (30, 90, 170))
    text_c(d, W / 2, 168, "BASIN BENCH ADVERTISING", SANS_B, 46, (30, 30, 34))
    text_c(d, W / 2, 228, "213-555-0101  ·  BENCHES ACROSS THE BASIN", SANS, 32, (60, 60, 66))


ADS = [ad_realtor_a, ad_lawyer_a, ad_bail, ad_abogados, ad_realtor_b, ad_dental, ad_tacos, ad_your_ad]


def main():
    atlas = Image.new("RGB", (W, ROW_H * len(ADS)), (255, 255, 255))
    for i, fn in enumerate(ADS):
        row = Image.new("RGB", (W, ROW_H), (255, 255, 255))
        fn(ImageDraw.Draw(row))
        # A brush or a vinyl print, not a font render: a hair of softening.
        row = row.filter(ImageFilter.GaussianBlur(0.6))
        atlas.paste(row, (0, i * ROW_H))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    atlas.save(OUT, quality=90)
    print("wrote", os.path.normpath(OUT), atlas.size, len(ADS), "ads")


if __name__ == "__main__":
    main()
