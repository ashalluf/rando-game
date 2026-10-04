#!/usr/bin/env python3
"""Compares the near and far frames of tools/glshot/far_building_shot.gd building by building.

    python3 tools/glshot/far_pair.py <stem> [<stem> ...]

For each building (its region in <stem>_mask.png) prints the mean colour of the near frame and of
the far frame in LINEAR light, their luminance ratio (far / near: 1.00 means the far copy is as
bright as the building it stands in for), the mean absolute difference per pixel (in 0..255 sRGB),
and the share of the region where the two differ by more than 24/255. Also writes
<stem>_side.png (near | far | difference x4).
"""
import sys

import numpy as np
from PIL import Image


def lin(a):
    a = a / 255.0
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def main(stem):
    near = np.asarray(Image.open(stem + "_near.png").convert("RGB")).astype(float)
    far = np.asarray(Image.open(stem + "_far.png").convert("RGB")).astype(float)
    mask = np.asarray(Image.open(stem + "_mask.png").convert("L")).astype(int)
    ids = sorted(set((mask[mask > 8] + 10) // 20))
    print("%s: building  near lin rgb            far lin rgb             lum far/near  |d| sRGB  >24" % stem)
    lums = []
    for k in ids:
        m = (mask + 10) // 20 == k
        m &= mask > 8
        if m.sum() < 50:
            continue
        nl = lin(near[m]).mean(axis=0)
        fl = lin(far[m]).mean(axis=0)
        ln = float(nl @ [0.2126, 0.7152, 0.0722])
        lf = float(fl @ [0.2126, 0.7152, 0.0722])
        d = np.abs(near[m] - far[m]).mean()
        big = (np.abs(near[m] - far[m]).max(axis=1) > 24).mean()
        lums.append(lf / max(ln, 1e-6))
        print("  %2d (%6d px)  %.3f %.3f %.3f      %.3f %.3f %.3f      %.2f          %5.1f    %4.0f %%" % (
            k, m.sum(), nl[0], nl[1], nl[2], fl[0], fl[1], fl[2], lf / max(ln, 1e-6), d, big * 100.0))
    if lums:
        print("  mean ratio %.2f, range %.2f .. %.2f" % (np.mean(lums), min(lums), max(lums)))
    diff = np.clip(np.abs(near - far) * 4.0, 0, 255)
    side = np.concatenate([near, far, diff], axis=1).astype(np.uint8)
    Image.fromarray(side).save(stem + "_side.png")


if __name__ == "__main__":
    for s in sys.argv[1:]:
        main(s)
