#!/usr/bin/env python3
"""Fit the wheel BAKED INTO each car body model: hub position, tyre radius and section width.

    python3 tools/wheel_fit.py [SEDAN PICKUP ...]

`tools/wheel_probe.py` finds the contact patch, which pins the hub down in x and z but tells
you nothing about the radius - it measures the flat band of geometry touching the road, so it
reported a 0.16 m radius for a 0.35 m wheel. This fits the circle instead.

Method, per quadrant, in Vehicle body space (see wheel_probe.body_space):

  1. The contact patch (the lowest band of the quadrant) gives hub_x and hub_z.
  2. Keep the points near that hub: within a section width in x, within a wheel radius in z,
     and below the waist. That is the tyre plus the arch lip above it.
  3. A tyre is a surface of revolution about the axle, so in the (z, y) plane its points lie on
     a circle through the contact patch: centre (hub_z, y_min + r), radius r. Sweep r and take
     the one whose circle the most points lie on. The arch lip sits a few centimetres OUTSIDE
     that circle and loses.
  4. Section width is the x extent of the points that landed on the winning circle.

The numbers feed Vehicle.WHEEL_POSE, which is where the generated wheel goes: it has to cover
the modelled one, so it is placed at the modelled hub and built a little larger, not at the
VehicleWheel3D slot (on the pickup the two are 44 cm apart along the car).
"""

import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wheel_probe import CARS, REPO, body_space, load_glb  # noqa: E402


def fit(name, glb, length, ride, yaw):
    js, blob = load_glb(os.path.join(REPO, "assets", "models", glb))
    pts, scale = body_space(js, blob, length, ride, yaw, None)
    rows = []
    for sz in (-1, 1):
        for sx in (-1, 1):
            q = (np.sign(pts[:, 2]) == sz) & (np.sign(pts[:, 0]) == sx)
            sel = pts[q]
            if len(sel) < 50:
                continue
            y_min = sel[:, 1].min()
            band = sel[sel[:, 1] < y_min + 0.035]
            if len(band) < 4:
                continue
            hub_x = float(np.median(band[:, 0]))
            hub_z = float(np.median(band[:, 2]))
            near = sel[(np.abs(sel[:, 0] - hub_x) < 0.20)
                       & (np.abs(sel[:, 2] - hub_z) < 0.62)
                       & (sel[:, 1] < y_min + 0.95)]
            if len(near) < 40:
                continue
            best_r, best_score, best_mask = 0.0, -1.0, None
            for r in np.arange(0.16, 0.56, 0.0025):
                cy = y_min + r
                d = np.hypot(near[:, 1] - cy, near[:, 2] - hub_z)
                mask = np.abs(d - r) < 0.014
                # Normalised by circumference so a big circle is not favoured just for being
                # long; the tyre's own shell is far denser than anything else down there.
                score = mask.sum() / r
                if score > best_score:
                    best_r, best_score, best_mask = float(r), float(score), mask
            on = near[best_mask]
            rows.append((sz, sx, hub_x, y_min + best_r, hub_z, best_r,
                         float(on[:, 0].max() - on[:, 0].min()), int(best_mask.sum())))
    print("%-7s %-24s scale %.3f" % (name, glb, scale))
    for sz, sx, hx, hy, hz, r, w, n in rows:
        print("   z%+d x%+d: hub %+.3f %+.3f %+.3f   r %.3f   width %.3f   (%d pts)"
              % (sz, sx, hx, hy, hz, r, w, n))
    if rows:
        fr = [v for v in rows if v[0] < 0]
        rr = [v for v in rows if v[0] > 0]
        hub_x = sum(abs(v[2]) for v in rows) / len(rows)
        hub_y = sum(v[3] for v in rows) / len(rows)
        r = sum(v[5] for v in rows) / len(rows)
        w = sum(v[6] for v in rows) / len(rows)
        print('   -> {"hub_x": %.3f, "hub_y": %.3f, "front_z": %+.3f, "rear_z": %+.3f,'
              ' "r": %.3f, "w": %.3f},'
              % (hub_x, hub_y,
                 sum(v[4] for v in fr) / max(len(fr), 1),
                 sum(v[4] for v in rr) / max(len(rr), 1), r, w))
    print()


if __name__ == "__main__":
    wanted = [w.lower() for w in sys.argv[1:]]
    for row in CARS:
        if not wanted or row[0].lower() in wanted:
            fit(*row)
