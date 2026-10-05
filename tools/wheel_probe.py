#!/usr/bin/env python3
"""Measure where the wheels sit in every car body model, in the game's body space.

    python3 tools/wheel_probe.py

Vehicle._add_body_model() scales each .glb so its longest horizontal axis matches the body
type's `length` and drops the model's AABB bottom onto `ride`, so a model's geometry has one
fixed place in body space. This walks that same transform and reports, per quadrant, the hub
position and the tyre's radius and section width of the wheel BAKED INTO the model.

Those numbers are what `Vehicle.WHEEL_POSE` holds. They are not the same as `_dims()`'s
`wheel_z` / `track`, which are where the VehicleWheel3D physics wheels go: on several models
(the pickup worst, 43 cm) the modelled rear axle is a long way forward of the physics one, so
a generated wheel hung off the physics wheel sits outside the arch. The generated wheel goes
where the arch is; the physics wheel stays where it is.

Method: the lowest band of geometry in a quadrant is the contact patch - except on the
exotics, whose flat underbody pan is exactly as low. Those carry a `tyre` material, so when
one exists only its triangles are used; the Meshy cars are one unnamed surface and fall back
to the lowest band. The hub is then the centre of the tyre's own bounding box, the radius half
its vertical extent and the section width its extent along the axle.
"""

import json
import math
import os
import struct
import sys

import numpy as np

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# body type -> (.glb, length, ride, extra model yaw). Mirrors Vehicle.BODY_MODELS, _dims()
# and MODEL_YAW; a model whose长 axis is +X gets the yaw, one already along Z gets none.
CARS = [
    ("SEDAN", "car_sedan.glb", 4.80, -0.24, -math.pi / 2),
    ("PICKUP", "car_pickup.glb", 5.40, -0.16, -math.pi / 2),
    ("VAN", "car_van.glb", 5.20, -0.18, -math.pi / 2),
    ("SPORTS", "car_sports.glb", 4.60, -0.30, -math.pi / 2),
    ("SUPER", "hifi_super_coupe.glb", 4.55, -0.34, 0.0),
    ("SPIDER", "exo_super_spider.glb", 4.55, -0.34, 0.0),
    ("HYPER", "hifi_hyper_coupe.glb", 4.60, -0.35, 0.0),
    ("TRACK", "exo_hyper_b.glb", 4.60, -0.35, 0.0),
]

_CT = {5120: (np.int8, 1), 5121: (np.uint8, 1), 5122: (np.int16, 2),
       5123: (np.uint16, 2), 5125: (np.uint32, 4), 5126: (np.float32, 4)}
_NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load_glb(path):
    data = open(path, "rb").read()
    total = struct.unpack_from("<I", data, 8)[0]
    off, js, blob = 12, None, None
    while off < total:
        clen, ctype = struct.unpack_from("<II", data, off)
        off += 8
        if ctype == 0x4E4F534A:
            js = json.loads(data[off:off + clen].decode())
        elif ctype == 0x004E4942:
            blob = data[off:off + clen]
        off += clen
    return js, blob


def accessor(js, blob, index):
    a = js["accessors"][index]
    bv = js["bufferViews"][a["bufferView"]]
    dtype, size = _CT[a["componentType"]]
    n = _NC[a["type"]]
    stride = bv.get("byteStride") or size * n
    base = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    if stride == size * n:
        return np.frombuffer(blob, dtype=dtype, count=a["count"] * n, offset=base).reshape(a["count"], n)
    raw = np.frombuffer(blob, dtype=np.uint8, count=a["count"] * stride, offset=base).reshape(a["count"], stride)
    return raw[:, :size * n].copy().view(dtype).reshape(a["count"], n)


def body_space(js, blob, length, ride, yaw, only_material=None):
    """Every vertex of the model, in Vehicle body space."""
    whole, picked = [], []
    for mesh in js["meshes"]:
        for prim in mesh["primitives"]:
            pos = accessor(js, blob, prim["attributes"]["POSITION"]).astype(np.float64)
            whole.append(pos)
            mat = prim.get("material")
            name = js["materials"][mat].get("name") if mat is not None else None
            if only_material is None or name == only_material:
                picked.append(pos)
    allv = np.vstack(whole)
    lo, hi = allv.min(0), allv.max(0)
    size = hi - lo
    along_x = size[0] >= size[2]
    scale = length / (size[0] if along_x else size[2])
    turn = yaw if along_x else 0.0
    c, s = math.cos(turn), math.sin(turn)
    cx, cz = (lo[0] + hi[0]) / 2, (lo[2] + hi[2]) / 2
    sel = np.vstack(picked) if picked else allv
    px, py, pz = sel[:, 0] - cx, sel[:, 1] - lo[1], sel[:, 2] - cz
    return np.column_stack([(px * c + pz * s) * scale, py * scale + ride, (-px * s + pz * c) * scale]), scale


def materials(js):
    return {m.get("name") for m in js.get("materials", []) if m.get("name")}


def probe(name, glb, length, ride, yaw):
    js, blob = load_glb(os.path.join(REPO, "assets", "models", glb))
    has_tyre = "tyre" in materials(js)
    pts, scale = body_space(js, blob, length, ride, yaw, "tyre" if has_tyre else None)
    print("%-7s %-24s scale %.3f  source %s" % (name, glb, scale, "tyre surface" if has_tyre else "lowest band"))
    out = {}
    for sz in (-1, 1):
        for sx in (-1, 1):
            q = (np.sign(pts[:, 2]) == sz) & (np.sign(pts[:, 0]) == sx)
            if not has_tyre:
                q &= pts[:, 1] < ride + 0.05  # contact patch only
            sel = pts[q]
            if len(sel) < 6:
                print("   z%+d x%+d: nothing" % (sz, sx))
                continue
            lo, hi = sel.min(0), sel.max(0)
            if has_tyre:
                hub_y = (lo[1] + hi[1]) / 2
                radius = (hi[1] - lo[1]) / 2
            else:
                hub_y = ride + (hi[1] - lo[1])  # band is flat; radius comes from the z extent
                radius = (hi[2] - lo[2]) / 2
                hub_y = ride + radius
            out[(sz, sx)] = (abs(lo[0] + hi[0]) / 2, hub_y, (lo[2] + hi[2]) / 2, radius, hi[0] - lo[0])
            print("   z%+d x%+d: hub_x %.3f  hub_y %.3f  hub_z %+.3f  r %.3f  width %.3f" % (
                sz, sx, out[(sz, sx)][0], hub_y, out[(sz, sx)][2], radius, out[(sz, sx)][4]))
    if out:
        fr = [v for k, v in out.items() if k[0] < 0]
        rr = [v for k, v in out.items() if k[0] > 0]
        hub_x = sum(v[0] for v in out.values()) / len(out)
        width = sum(v[4] for v in out.values()) / len(out)
        r = max(v[3] for v in out.values())
        print("   -> %s: hub_x %.3f, front_z %+.3f, rear_z %+.3f, r %.3f, width %.3f" % (
            name, hub_x, sum(v[2] for v in fr) / max(len(fr), 1), sum(v[2] for v in rr) / max(len(rr), 1), r, width))
    print()


if __name__ == "__main__":
    wanted = sys.argv[1:]
    for row in CARS:
        if not wanted or row[0].lower() in [w.lower() for w in wanted]:
            probe(*row)
