#!/usr/bin/env python3
"""Compares the near and far frames of tools/glshot/far_landmark_shot.gd landmark by landmark.

    python3 tools/glshot/far_landmark_pair.py /tmp/fl_*_near.png

Each landmark's silhouette in each frame is where that frame differs from <stem>_empty.png (the
background alone). Prints the share of the near silhouette the far copy covers and the far
silhouette's spill outside it (IoU), the mean LINEAR luminance of each copy over the pixels both
cover and their ratio (far / near: 1.00 is the far copy as bright as the detailed one), the mean
chroma shift, and the mean |difference| in sRGB there. Writes <stem>_side.png (near | far |
difference x4, the near outline in red, the far outline in cyan on the difference).
"""
import sys

import numpy as np
from PIL import Image

LUM = np.array([0.2126, 0.7152, 0.0722])


def lin(a):
    a = a / 255.0
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def load(p):
    return np.asarray(Image.open(p).convert("RGB")).astype(float)


def edge(m):
    e = np.zeros_like(m)
    e[1:, :] |= m[1:, :] != m[:-1, :]
    e[:, 1:] |= m[:, 1:] != m[:, :-1]
    return e


def main(path):
    stem = path[: -len("_near.png")] if path.endswith("_near.png") else path
    near, far, empty = load(stem + "_near.png"), load(stem + "_far.png"), load(stem + "_empty.png")
    mn = np.abs(near - empty).max(axis=2) > 6
    mf = np.abs(far - empty).max(axis=2) > 6
    both = mn & mf
    nn, nf, nb = mn.sum(), mf.sum(), both.sum()
    iou = nb / max((mn | mf).sum(), 1)
    cover = nb / max(nn, 1)
    spill = (mf & ~mn).sum() / max(nn, 1)
    row = {"id": stem.split("_", 1)[-1], "near_px": int(nn), "far_px": int(nf), "iou": iou, "cover": cover, "spill": spill}
    if nb > 30:
        ln_rgb = lin(near[both]).mean(axis=0)
        lf_rgb = lin(far[both]).mean(axis=0)
        ln, lf = float(ln_rgb @ LUM), float(lf_rgb @ LUM)
        cn = ln_rgb / max(ln_rgb.sum(), 1e-6)
        cf = lf_rgb / max(lf_rgb.sum(), 1e-6)
        row.update(ratio=lf / max(ln, 1e-6), chroma=float(np.abs(cn - cf).sum()), d=float(np.abs(near[both] - far[both]).mean()),
                   near_lum=ln, far_lum=lf)
    else:
        row.update(ratio=float("nan"), chroma=float("nan"), d=float("nan"), near_lum=0.0, far_lum=0.0)
    diff = np.clip(np.abs(near - far) * 4.0, 0, 255)
    n2, f2 = near.copy(), far.copy()
    en, ef = edge(mn), edge(mf)
    n2[en] = [255, 40, 40]
    f2[ef] = [40, 230, 255]
    diff[en] = [255, 40, 40]
    diff[ef] = [40, 230, 255]
    side = np.concatenate([n2, f2, diff], axis=1).astype(np.uint8)
    Image.fromarray(side).save(stem + "_side.png")
    return row


if __name__ == "__main__":
    rows = [main(p) for p in sys.argv[1:]]
    print("%-22s %8s %8s  %5s %6s %6s  %6s %6s  %5s %6s" % ("landmark", "near px", "far px", "IoU", "cover", "spill", "lum n", "far/n", "chrom", "|d|"))
    for r in rows:
        print("%-22s %8d %8d  %5.2f %6.2f %6.2f  %6.3f %6.2f  %5.3f %6.1f" % (
            r["id"], r["near_px"], r["far_px"], r["iou"], r["cover"], r["spill"], r["near_lum"], r["ratio"], r["chroma"], r["d"]))
