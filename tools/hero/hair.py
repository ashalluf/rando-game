# Step: the hair. Slicked back, grown as layered alpha cards along a combed flow on the scalp.
#
# The MakeHuman short04 proxy is a shell of wide flat cards whose sides caught one big grey
# highlight: a helmet. Here every card follows a strand path traced over the head:
#  - roots are scattered over the hair region (a hairline drawn round the head from the brow,
#    the temples, a sideburn in front of each ear, an arc over the ear and down to the nape) and
#    packed along the hairline itself, where short fine cards keep the edge soft
#  - each strand combs back from its root and, past the crown, turns down toward the nape,
#    riding a little higher over the scalp the further it goes (it lies over the hair behind it)
#  - three layers: a dense under-layer that hides the scalp, the main layer, and a thin top
#    layer of narrow cards with separated strands and a few fly-aways that lift at the crown
# UV: u picks one of eight strand-clump columns in the hair atlas (prep_textures.py), v runs
# from the root (v = 1) to the tip (v = 0). UV2 carries (occlusion, per-card tint): the layer a
# card is in and how deep under the others its root sits, for shaders/hero_hair.gdshader.
# Reads work/hero_sh.blend; writes work/hero_parts.blend and work/hairline.json.
import json
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

cfg = common.config()
HC = cfg.get("hair", {})
rng = np.random.default_rng(HC.get("seed", 11))
bpy.ops.wm.open_mainfile(filepath=common.work("hero_sh.blend"))
scene = bpy.context.scene
arm = bpy.data.objects["hero"]
arm.data.pose_position = 'REST'
body = bpy.data.objects["hero.body"]
UVN = body.data.uv_layers.active.name
P = "mixamorig:"

saved = [(m, m.show_viewport) for m in body.modifiers]
for m, _ in saved:
    m.show_viewport = False
dg = bpy.context.evaluated_depsgraph_get()
me = bpy.data.meshes.new_from_object(body.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
for m, s in saved:
    m.show_viewport = s
V = np.array([v.co[:] for v in me.vertices])
gi = {g.name: g.index for g in body.vertex_groups}


def group(name):
    w = np.zeros(len(V))
    for v in me.vertices:
        for g in v.groups:
            if g.group == gi[name]:
                w[v.index] = g.weight
    return w


ears = V[group("ears") > 0.5]
ear_z = float(ears[:, 2].mean())
ear_top = float(ears[:, 2].max())
ear_y = float(ears[:, 1].mean())
ear_x = float(np.abs(ears[:, 0]).mean())
eyes_o = [o for o in bpy.data.objects if o.type == 'MESH' and (o.name.endswith("high-poly") or o.name.endswith("low-poly"))][0]
eye_z = float(np.mean([(eyes_o.matrix_world @ v.co).z for v in eyes_o.data.vertices]))
C = Vector((0.0, ear_y + 0.02, ear_z + 0.02))
theta_ear = math.degrees(math.atan2(ear_x, -(ear_y - C.y)))
front_z = eye_z + HC.get("hairline_above_eyes", 0.080)
# (azimuth in degrees from the front, height of the hairline), symmetric left and right
HAIRLINE = [
    (0.0, front_z), (theta_ear - 38, front_z - 0.004), (theta_ear - 26, eye_z + 0.058),
    (theta_ear - 17, eye_z + 0.034), (theta_ear - 12.5, ear_z + 0.004), (theta_ear - 9, ear_top + 0.004),
    (theta_ear, ear_top + 0.013), (theta_ear + 13, ear_top + 0.003), (theta_ear + 22, ear_z - 0.012),
    (theta_ear + 45, ear_z - 0.048), (180.0, ear_z - 0.068),
]
HL_A = np.array([a for a, _ in HAIRLINE])
HL_Z = np.array([z for _, z in HAIRLINE])
json.dump({"centre": list(C), "hairline": HAIRLINE, "ear_z": ear_z}, open(common.work("hairline.json"), "w"), indent=1)
print("HAIR ear azimuth %.1f deg, hairline front %.3f nape %.3f" % (theta_ear, front_z, HL_Z[-1]))


def azimuth(p):
    return math.degrees(math.atan2(p[0], -(p[1] - C.y)))


def hairline_z(a):
    return float(np.interp(abs(a), HL_A, HL_Z))


def hair_amount(p):
    return (p[2] - hairline_z(azimuth(p))) / 0.004


# ---- the head surface ------------------------------------------------------------------------------
is_body = group("body") > 0.5
# skin faces only: the base mesh also carries MPFB's helper geometry (a hair helper among them)
tris = [tuple(p.vertices) for p in me.polygons if is_body[list(p.vertices)].all()]
head_faces = [f for f in tris if V[list(f)].mean(0)[2] > ear_z - 0.11]
bvh = BVHTree.FromPolygons([tuple(v) for v in V], head_faces)


def surface(p):
    loc, n, _, _ = bvh.find_nearest(Vector(p))
    if n.dot(Vector(loc) - C) < 0:
        n = -n
    return loc, n


# ---- roots -------------------------------------------------------------------------------------------
cent, area = [], []
for f in head_faces:
    q = V[list(f)]
    c = q.mean(0)
    if hair_amount(c) < 0.5 or c[2] < ear_z - 0.09:
        continue
    a = 0.0
    for k in range(1, len(f) - 1):
        a += 0.5 * np.linalg.norm(np.cross(q[k] - q[0], q[k + 1] - q[0]))
    cent.append(f)
    area.append(a)
area = np.array(area)
print("HAIR region %.4f m2 over %d faces" % (area.sum(), len(cent)))


def sample_roots(n):
    pick = rng.choice(len(cent), n, p=area / area.sum())
    out = []
    for i in pick:
        q = V[list(cent[i])]
        w = rng.dirichlet(np.ones(len(q)))
        out.append(w @ q)
    return out


def flow(p, n):
    """Combed back; past the crown the comb turns down toward the nape."""
    a = abs(azimuth(p))
    back = Vector((0, 1, 0))
    down = Vector((0, 0, -1))
    phi = math.radians(78.0) * min(1.0, max(0.0, (a - 55.0) / 105.0)) ** 1.1
    # the top of the head carries the comb straight back until well behind the crown
    top = max(0.0, (p[2] - (C.z + 0.07)) / 0.04)
    phi *= max(0.0, 1.0 - 0.8 * min(top, 1.0))
    d = back * math.cos(phi) + down * math.sin(phi)
    # at the back, sweep a little toward the middle of the nape
    if a > 120:
        d += Vector((-math.copysign(1.0, p[0]) * 0.18 * (a - 120) / 60, 0, 0))
    d = d - n * d.dot(n)
    return d.normalized()


def grow(root, length, rise, h0, step=0.007):
    loc, n = surface(root)
    pts, nrs = [], []
    p = Vector(loc)
    s = 0.0
    wob = rng.normal() * 0.25
    while s <= length + 1e-6:
        loc, n = surface(p)
        h = h0 + rise * (s / max(length, 1e-3)) ** 0.8
        pts.append(Vector(loc) + n * h)
        nrs.append(n)
        d = flow(loc, n)
        # a slow lateral drift so neighbouring strands do not run exactly parallel
        side = d.cross(n).normalized()
        d = (d + side * wob * 0.35 * math.sin(s / max(length, 1e-3) * math.pi)).normalized()
        p = Vector(loc) + d * step
        s += step
    return pts, nrs


def strand_length(root):
    a = abs(azimuth(root))
    top = root[2] > C.z + 0.06
    if a < 40 and top:
        base = 0.125          # the front: combed right back over the top
    elif top:
        base = 0.10
    elif a < 110:
        base = 0.062          # the sides, back over the ears
    else:
        base = 0.050 + 0.02 * (root[2] - hairline_z(a)) / 0.1
    return base * (0.8 + 0.4 * rng.random())


LAYERS = [
    # name, count, width, rise, lift, columns, occlusion
    ("under", HC.get("under_cards", 180), 0.018, 0.0030, 0.0006, (0, 1, 2), 0.42),
    ("main", HC.get("main_cards", 230), 0.014, 0.0060, 0.0024, (1, 2, 3, 4), 0.72),
    ("top", HC.get("top_cards", 120), 0.009, 0.0080, 0.0048, (4, 5, 6), 1.0),
]
COLS = 8
cards = []  # (points, normals, width, column, occlusion, tint, twist)
for name, count, width, rise, lift, cols, occ in LAYERS:
    for root in sample_roots(count):
        L = strand_length(root)
        if name == "under":
            L *= 0.7
        pts, nrs = grow(root, L, rise, lift)
        if len(pts) < 3:
            continue
        cards.append((pts, nrs, width * (0.8 + 0.4 * rng.random()), int(rng.choice(cols)), occ, float(rng.random()), rng.normal() * 0.25))
# the hairline: short fine cards packed along the edge, from the front round to the nape
edge = 0
for a in np.linspace(-178, 178, HC.get("hairline_cards", 150)):
    if abs(abs(a) - theta_ear) < 9:   # no hair over the ear itself
        continue
    z = hairline_z(a) + 0.003
    r = 0.12
    d = Vector((math.sin(math.radians(a)), -math.cos(math.radians(a)), 0))
    hit = bvh.ray_cast(C + d * r + Vector((0, 0, z - C.z)), -d, r)
    if hit[0] is None:
        continue
    pts, nrs = grow(hit[0], 0.028 + 0.02 * rng.random(), 0.0025, 0.0004)
    if len(pts) >= 3:
        cards.append((pts, nrs, 0.008, 6 + int(rng.random() < 0.3), 0.8, float(rng.random()), rng.normal() * 0.2))
        edge += 1
# fly-aways at the crown and behind the ears: a few strands that lift off the rest
fly = 0
for root in sample_roots(HC.get("flyaway_cards", 36)):
    a = abs(azimuth(root))
    if root[2] < C.z + 0.04 and a < 100:
        continue
    pts, nrs = grow(root, 0.07 + 0.04 * rng.random(), 0.011, 0.006)
    if len(pts) >= 3:
        cards.append((pts, nrs, 0.006, 7, 1.0, float(rng.random()), rng.normal() * 0.6))
        fly += 1

bm = bmesh.new()
uvl = bm.loops.layers.uv.new(UVN)
uv2 = bm.loops.layers.uv.new("hairdata")
for pts, nrs, width, col, occ, tint, twist in cards:
    n_ = len(pts)
    rows = []
    u0 = (col + 0.06) / COLS
    u1 = (col + 0.94) / COLS
    for i, (p, n) in enumerate(zip(pts, nrs)):
        t = (pts[min(i + 1, n_ - 1)] - pts[max(i - 1, 0)]).normalized()
        b = t.cross(n).normalized()
        s = i / (n_ - 1)
        # a little twist along the card, so no card is a flat plank
        ang = twist * s
        b = (b * math.cos(ang) + n * math.sin(ang)).normalized()
        w = width * (1.0 - 0.55 * s ** 1.6)
        rows.append((bm.verts.new(p - b * (w / 2)), bm.verts.new(p + b * (w / 2)), s))
    for i in range(n_ - 1):
        a0, a1, s0 = rows[i]
        b0, b1, s1 = rows[i + 1]
        f = bm.faces.new((a0, a1, b1, b0))
        for l, (u, v) in zip(f.loops, ((u0, 1 - s0), (u1, 1 - s0), (u1, 1 - s1), (u0, 1 - s1))):
            l[uvl].uv = (u, v)
            # occlusion: the layer, and darker toward a root buried under the hair in front of it
            depth = occ * (0.62 + 0.38 * min(1.0, (1 - v) / 0.45))
            l[uv2].uv = (depth, tint)
hme = bpy.data.meshes.new("hero_hair")
bm.to_mesh(hme)
bm.free()
for p in hme.polygons:
    p.use_smooth = True
hair = bpy.data.objects.new("hero.hair", hme)
scene.collection.objects.link(hair)
hair.parent = arm
vg = hair.vertex_groups.new(name=P + "Head")
vg.add(list(range(len(hme.vertices))), 1.0, 'REPLACE')
for g in body.vertex_groups:
    if g.name.startswith(P) and g.name not in hair.vertex_groups:
        hair.vertex_groups.new(name=g.name)
hair.modifiers.new("Armature", 'ARMATURE').object = arm
arm.data.pose_position = 'POSE'
print("HAIR %d cards (%d hairline, %d fly-away), %d tris" % (len(cards), edge, fly, sum(len(p.vertices) - 2 for p in hme.polygons)))
bpy.ops.wm.save_as_mainfile(filepath=common.work("hero_parts.blend"))
