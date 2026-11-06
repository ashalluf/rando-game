import sys, os
from PIL import Image, ImageDraw, ImageFont
# A 2x2 review sheet of stills with their names on them (what the lead sent the owner per branch).
# usage: python3 tools/fleet/sheet.py out.jpg <dir of stills> file1 file2 file3 file4
out, d, files = sys.argv[1], sys.argv[2], sys.argv[3:]
font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 22)
W = 800
ims = []
for f in files:
    im = Image.open(os.path.join(d, f)).convert("RGB")
    ims.append((f, im.resize((W, int(im.height * W / im.width)), Image.LANCZOS)))
H = max(i.height for _, i in ims)
sheet = Image.new("RGB", (W * 2, H * ((len(ims) + 1) // 2)), (20, 20, 20))
dr = ImageDraw.Draw(sheet)
for k, (f, im) in enumerate(ims):
    x, y = (k % 2) * W, (k // 2) * H
    sheet.paste(im, (x, y))
    label = f.rsplit(".", 1)[0].replace("_", " ")
    dr.rectangle([x, y, x + 12 + dr.textlength(label, font=font), y + 30], fill=(0, 0, 0))
    dr.text((x + 6, y + 3), label, fill=(255, 255, 255), font=font)
sheet.save(out, quality=86)
