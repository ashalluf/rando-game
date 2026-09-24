# Step: rasterise UV maps into "texture space" arrays for prep_textures.py.
#
# For the skin, the tracksuit shell and the shoes, every texel of the map is given the rest-pose
# point it lands on (P), the surface normal there (N), the directions of increasing u and v on
# the surface (T, B - what a tangent-space normal map is measured against), per-vertex
# attributes (vertex-group weights, ambient occlusion) and whether any triangle covers it at all.
# The texture step then paints and derives maps as functions of the 3D body - wrinkles where a
# forehead is, pores that do not stretch across a UV seam, folds that follow an arm - instead of
# guessing at the UV layout, and with no ray-cast bake to go wrong (the old fold bake put
# inverted normals in both armpits: the dark patch on the shoulder).
#
# Writes work/txs_<set>.npz and work/landmarks.json (bones, garment and face landmarks).
import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

bpy.ops.wm.open_mainfile(filepath=common.work("hero_parts.blend"))
arm = bpy.data.objects["hero"]
arm.data.pose_position = 'REST'
P_ = "mixamorig:"


def evaluated(o, keep_masks=True):
    saved = []
    for m in o.modifiers:
        saved.append((m, m.show_viewport))
        if m.type == 'MASK' and not keep_masks and m.name.startswith("Delete"):
            m.show_viewport = False
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    for m, s in saved:
        m.show_viewport = s
    me.transform(o.matrix_world)
    me.calc_loop_triangles()
    return me


def vertex_group_weights(o, me, names):
    """Per-vertex weights of the named groups on the evaluated mesh (0 when missing)."""
    out = {}
    for n in names:
        out[n] = np.zeros(len(me.vertices), np.float32)
    idx = {g.index: g.name for g in o.vertex_groups if g.name in names}
    for v in me.vertices:
        for g in v.groups:
            n = idx.get(g.group)
            if n:
                out[n][v.index] = g.weight
    return out


def body_part(bone):
    """Which piece of the body a bone moves: head, torso, arm_L/R or leg_L/R."""
    n = bone.replace(P_, "")
    if n in ("Neck", "Head", "neck") or n.startswith("Head"):
        return "head"
    side = "L" if n.startswith("Left") else ("R" if n.startswith("Right") else "")
    if side and ("Arm" in n or "Hand" in n):
        return "arm_" + side
    if side and ("Leg" in n or "Foot" in n or "Toe" in n):
        return "leg_" + side
    return "torso"


def vertex_parts(o, me):
    names = {g.index: g.name for g in o.vertex_groups if g.name.startswith(P_)}
    out = []
    for v in me.vertices:
        best, bw = "torso", -1.0
        for g in v.groups:
            if g.group in names and g.weight > bw:
                best, bw = body_part(names[g.group]), g.weight
        out.append(best)
    return out


def face_parts(me, vparts):
    return [vparts[p.vertices[0]] for p in me.polygons]


def vertex_ao(me, vparts, occluders, reach, rays=24, seed=3):
    """Hemisphere occlusion per vertex: the share of `rays` directions that escape `reach`.
    Only a hit on the same piece of the body counts (and the neck on the head, the armpit on
    the torso near the shoulder, the crotch near the hip): the arms are bound hanging a hand's
    width from the thighs, and occlusion baked from THAT would leave a dark print of the arm
    on the hip and of the hip on the palm wherever the arms go in play."""
    rng = np.random.default_rng(seed)
    d = rng.normal(size=(rays, 3))
    d /= np.linalg.norm(d, axis=1, keepdims=True)
    shoulders = [arm.data.bones[P_ + n].head_local for n in ("LeftArm", "RightArm")]
    hips = [arm.data.bones[P_ + n].head_local for n in ("LeftUpLeg", "RightUpLeg")]
    ao = np.ones(len(me.vertices), np.float32)
    for i, v in enumerate(me.vertices):
        p, n = v.co, v.normal
        mine = vparts[i]
        near_sh = min((p - q).length for q in shoulders) < 0.10
        near_hip = min((p - q).length for q in hips) < 0.12
        o = p + n * 0.0015
        hit = tot = 0.0
        for k in range(rays):
            dv = Vector(d[k])
            c = dv.dot(n)
            if c < 0:
                dv, c = -dv, -c
            if c < 0.05:
                continue
            tot += c
            for bvh, fparts in occluders:
                h = bvh.ray_cast(o, dv, reach)
                if h[0] is None:
                    continue
                other = fparts[h[2]] if fparts is not None else mine
                ok = other == mine or {other, mine} == {"head", "torso"} \
                    or (near_sh and {other, mine} <= {"torso", "arm_L", "arm_R"} and "torso" in (other, mine)) \
                    or (near_hip and {other, mine} <= {"torso", "leg_L", "leg_R"})
                if ok:
                    hit += c
                    break
        ao[i] = 1.0 - hit / max(tot, 1e-6)
    return np.clip(ao, 0.0, 1.0)


def raster(me, size, attrs):
    """UV-space rasteriser. attrs: name -> per-vertex array (N,) or (N, k)."""
    uv = me.uv_layers.active.data
    V = np.array([v.co[:] for v in me.vertices], np.float64)
    VN = np.array([v.normal[:] for v in me.vertices], np.float64)
    tris = me.loop_triangles
    ntri = len(tris)
    tv = np.zeros((ntri, 3), np.int64)
    tl = np.zeros((ntri, 3), np.int64)
    tris.foreach_get("vertices", tv.ravel())
    tris.foreach_get("loops", tl.ravel())
    UV = np.zeros((len(uv), 2), np.float64)
    uv.foreach_get("uv", UV.ravel())
    cov = np.zeros((size, size), bool)
    P = np.zeros((size, size, 3), np.float32)
    N = np.zeros((size, size, 3), np.float32)
    T = np.zeros((size, size, 3), np.float32)
    B = np.zeros((size, size, 3), np.float32)
    A = {k: np.zeros((size, size) + np.shape(a)[1:], np.float32) for k, a in attrs.items()}
    for t in range(ntri):
        q = UV[tl[t]] * size
        q[:, 1] = size - q[:, 1]  # image rows run down
        x0, y0 = np.floor(q.min(0)).astype(int)
        x1, y1 = np.ceil(q.max(0)).astype(int)
        x0 = max(x0, 0); y0 = max(y0, 0); x1 = min(x1, size - 1); y1 = min(y1, size - 1)
        if x1 < x0 or y1 < y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        (ax, ay), (bx, by), (cx, cy) = q
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-12:
            continue
        w0 = ((by - cy) * (xs - cx) + (cx - bx) * (ys - cy)) / den
        w1 = ((cy - ay) * (xs - cx) + (ax - cx) * (ys - cy)) / den
        w2 = 1.0 - w0 - w1
        inside = (w0 >= -1e-4) & (w1 >= -1e-4) & (w2 >= -1e-4)
        if not inside.any():
            continue
        yy = (ys[inside] - 0.5).astype(int)
        xx = (xs[inside] - 0.5).astype(int)
        w = np.stack([w0[inside], w1[inside], w2[inside]], 1)
        vi = tv[t]
        P[yy, xx] = w @ V[vi]
        n = w @ VN[vi]
        N[yy, xx] = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
        # dP/du and dP/dv of this triangle (Blender UV: v up)
        uvt = UV[tl[t]]
        e1, e2 = V[vi[1]] - V[vi[0]], V[vi[2]] - V[vi[0]]
        d1, d2 = uvt[1] - uvt[0], uvt[2] - uvt[0]
        det = d1[0] * d2[1] - d2[0] * d1[1]
        if abs(det) > 1e-14:
            T[yy, xx] = (e1 * d2[1] - e2 * d1[1]) / det
            B[yy, xx] = (e2 * d1[0] - e1 * d2[0]) / det
        cov[yy, xx] = True
        for k, a in attrs.items():
            A[k][yy, xx] = w @ np.asarray(a)[vi] if np.ndim(a) == 1 else w @ np.asarray(a)[vi]
    return cov, P, N, T, B, A


def save(name, size, me, attrs):
    cov, P, N, T, B, A = raster(me, size, attrs)
    np.savez(common.work("txs_%s.npz" % name), cov=cov, P=P, N=N, T=T, B=B, **{"a_" + k: v for k, v in A.items()})
    print("TXS %s %dpx covered %.1f%%" % (name, size, 100.0 * cov.mean()))


# ---- landmarks --------------------------------------------------------------------------------
L = json.load(open(common.work("ts_landmarks.json")))
for b in arm.data.bones:
    if b.name.startswith(P_):
        L.setdefault(b.name[len(P_):], list(b.head_local))
        L[b.name[len(P_):] + "_tail"] = list(b.tail_local)

body = bpy.data.objects["hero.body"]
body_me = evaluated(body, keep_masks=False)
groups = vertex_group_weights(body, body_me, ["lips", "fingernails", "toenails", "scalp", "ears", "helper-l-eye", "helper-r-eye"])
V = np.array([v.co[:] for v in body_me.vertices])
lips = V[groups["lips"] > 0.5]
ears = V[groups["ears"] > 0.5]
L["lips_center"] = list(lips.mean(0))
L["lips_top"] = float(lips[:, 2].max())
L["lips_bottom"] = float(lips[:, 2].min())
L["lips_halfwidth"] = float(np.abs(lips[:, 0]).max())
L["ear_center"] = [float(np.abs(ears[:, 0]).mean()), float(ears[:, 1].mean()), float(ears[:, 2].mean())]
L["ear_inner_x"] = float(np.abs(ears[:, 0]).min())
L["ear_top"] = float(ears[:, 2].max())
eyes_o = [o for o in bpy.data.objects if o.type == 'MESH' and (o.name.endswith("high-poly") or o.name.endswith("low-poly"))][0]
eye_me = evaluated(eyes_o)
EV = np.array([v.co[:] for v in eye_me.vertices])
for side, sg in (("l", 1.0), ("r", -1.0)):
    e = EV[EV[:, 0] * sg > 0]
    L["eye_" + side] = list(e.mean(0))
    L["eye_radius"] = float((e.max(0) - e.min(0)).mean() / 2)
bpy.data.meshes.remove(eye_me)
# the top of the head and its front
L["head_top"] = float(V[:, 2].max())
head_v = V[V[:, 2] > L["lips_top"]]
L["face_front_y"] = float(head_v[:, 1].min())
json.dump(L, open(common.work("landmarks.json"), "w"), indent=1)
print("TXS landmarks lips %.3f ears %s eyes %s top %.3f" % (L["lips_center"][2], np.round(L["ear_center"], 3), np.round(L["eye_l"], 3), L["head_top"]))

# ---- occluders for the AO: each piece of the body by itself (see vertex_ao) ---------------------------
def bvh_of(me):
    return BVHTree.FromPolygons([v.co[:] for v in me.vertices], [tuple(p.vertices) for p in me.polygons])


# ---- skin ---------------------------------------------------------------------------------------
body_parts = vertex_parts(body, body_me)
occ = [(bvh_of(body_me), face_parts(body_me, body_parts))]
for o in bpy.data.objects:  # the eyes and the hair shade the head
    if o.type == 'MESH' and o.parent == arm and (o.name.endswith(("high-poly", "low-poly")) or o.name == "hero.hair"):
        m = evaluated(o)
        occ.append((bvh_of(m), ["head"] * len(m.polygons)))
ao = vertex_ao(body_me, body_parts, occ, reach=0.06)
attrs = {k.replace("helper-", "").replace("-", "_"): v for k, v in groups.items()}
attrs["ao"] = ao
save("skin", 2048, body_me, attrs)

# ---- tracksuit shell -------------------------------------------------------------------------------
suit = bpy.data.objects["hero.tracksuit"]
suit_me = evaluated(suit)
jac = vertex_group_weights(suit, suit_me, ["ts_jacket"])["ts_jacket"]
suit_parts = vertex_parts(suit, suit_me)
ao = vertex_ao(suit_me, suit_parts, [(bvh_of(suit_me), face_parts(suit_me, suit_parts))], reach=0.12)
save("suit", 2048, suit_me, {"jacket": jac, "ao": ao})

# ---- shoes --------------------------------------------------------------------------------------
shoes = [o for o in bpy.data.objects if o.name.startswith("hero.shoes")][0]
shoe_me = evaluated(shoes)
save("shoes", 1024, shoe_me, {"ao": vertex_ao(shoe_me, ["leg_L"] * len(shoe_me.vertices), [(bvh_of(shoe_me), None)], reach=0.05)})
