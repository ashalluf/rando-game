# Step: make the MakeHuman sneaker a lace-up. The pack's shoes05 is a smooth closed upper - a
# slip-on - and a white slip-on reads as a hospital clog. On each shoe:
#  - a padded tongue laid on the instep, rising into the trouser cuff
#  - five pairs of eyelets along the throat (painted into the leather by prep_textures.py from
#    the 3D points written here, so they sit exactly under the lace ends)
#  - flat cotton laces criss-crossing from eyelet to eyelet, arched a little off the tongue, and a
#    bow: two loops and two tails
# Laces and tongue share one small atlas material (hero_laces): braid on the top half, tongue mesh
# on the bottom. Weights come from the shoe itself, so they bend with the foot exactly.
# Reads work/hero_jw.blend, writes work/hero_sh.blend and work/shoe_marks.json.
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

bpy.ops.wm.open_mainfile(filepath=common.work("hero_jw.blend"))
scene = bpy.context.scene
arm = bpy.data.objects["hero"]
arm.data.pose_position = 'REST'
shoes = [o for o in bpy.data.objects if o.name.startswith("hero.shoes")][0]
UVN = shoes.data.uv_layers.active.name
dg = bpy.context.evaluated_depsgraph_get()
sme = bpy.data.meshes.new_from_object(shoes.evaluated_get(dg), depsgraph=dg)
sme.transform(shoes.matrix_world)
bvh = BVHTree.FromPolygons([tuple(v.co) for v in sme.vertices], [tuple(p.vertices) for p in sme.polygons])
P = "mixamorig:"

N_EYELETS = 5
Y_FIRST, Y_LAST = -0.142, -0.066     # eyelet rows, toe to ankle (the shoe points to -Y)
LACE_W, LACE_T = 0.0062, 0.0016


def top_point(x, y, lift=0.0):
    """The upper's outer surface under (x, y), from above."""
    hit = bvh.ray_cast(Vector((x, y, 0.3)), Vector((0, 0, -1)), 1.0)
    if hit[0] is None or hit[0].z < 0.02:
        return None, None
    n = hit[1] if hit[1].z > 0 else -hit[1]
    return hit[0] + n * lift, n


def side_point(xc, x, y, z_guess):
    """A point on the upper at (x, y) seen from the side of the throat (for the eyelets, which
    sit on the slope of the quarters)."""
    d = Vector((x - xc, 0, -0.9)).normalized()
    o = Vector((x, y, z_guess)) - d * 0.05
    hit = bvh.ray_cast(o, d, 0.12)
    if hit[0] is None:
        return top_point(x, y)
    n = hit[1] if hit[1].dot(-d) > 0 else -hit[1]
    return hit[0], n


def ribbon(bm_, pts, normals, width, thick, u0=0.0, v_band=(0.5, 1.0)):
    """A flat lace along pts: a thin rounded box section, u along its length in lace widths."""
    rows = []
    s = u0
    uvs = []
    for i, (p, n) in enumerate(zip(pts, normals)):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        b = t.cross(n).normalized()
        n2 = b.cross(t).normalized()
        if i:
            s += (p - pts[i - 1]).length / (width * 2.0)
        sec = [(-0.5, 0.0), (-0.35, 0.5), (0.35, 0.5), (0.5, 0.0), (0.35, -0.5), (-0.35, -0.5)]
        rows.append([bm_.verts.new(p + b * (w * width) + n2 * (h * thick)) for w, h in sec])
        uvs.append(s)
    faces = []
    for i in range(len(rows) - 1):
        for j in range(6):
            j2 = (j + 1) % 6
            f = bm_.faces.new((rows[i][j], rows[i][j2], rows[i + 1][j2], rows[i + 1][j]))
            faces.append((f, i, j))
    return rows, uvs, faces


marks = {"eyelets": [], "tongue": []}
lace_bm = bmesh.new()
lace_uv = []  # (face, [(u, v) per loop])
for side, sg in (("Left", 1.0), ("Right", -1.0)):
    foot = arm.data.bones[P + side + "Foot"]
    toe = arm.data.bones[P + side + "ToeBase"]
    xc = (foot.head_local.x + toe.head_local.x) * 0.5
    eyelets = []
    for i in range(N_EYELETS):
        t = i / (N_EYELETS - 1)
        y = Y_FIRST + (Y_LAST - Y_FIRST) * t
        half = 0.0105 + 0.0045 * t
        row = []
        for s in (-1.0, 1.0):
            top, _ = top_point(xc + s * half, y)
            z_guess = top.z if top is not None else 0.07
            p, n = side_point(xc, xc + s * half, y, z_guess)
            row.append((p, n))
            marks["eyelets"].append(list(p))
        eyelets.append(row)
    # tongue: a padded strip between the eyelet rows, from below the first pair into the cuff
    tv, tf, tuv = [], [], []
    cols = 7
    ys = [Y_FIRST - 0.016 + (Y_LAST + 0.012 - Y_FIRST + 0.016) * k / 13 for k in range(14)]
    grid = []
    for k, y in enumerate(ys):
        t = min(1.0, max(0.0, (y - Y_FIRST) / (Y_LAST - Y_FIRST)))
        half = 0.0125 + 0.0045 * t
        row = []
        for c in range(cols):
            xx = xc + (c / (cols - 1) * 2 - 1) * half
            p, n = top_point(xx, min(y, Y_LAST + 0.004), 0.0022 + 0.0012 * math.sin(math.pi * c / (cols - 1)))
            if p is None:
                p, n = top_point(xx, Y_LAST, 0.003)
            if y > Y_LAST + 0.004:  # the top of the tongue rises up the shin into the cuff
                p = p + Vector((0, (y - Y_LAST) * 0.35, (y - Y_LAST) * 1.6))
            row.append(p)
            tuv.append((c / (cols - 1), 0.02 + 0.46 * k / (len(ys) - 1)))
        grid.append(row)
    base = len(lace_bm.verts)
    vv = [lace_bm.verts.new(p) for row in grid for p in row]
    for k in range(len(ys) - 1):
        for c in range(cols - 1):
            a = k * cols + c
            f = lace_bm.faces.new((vv[a], vv[a + 1], vv[a + cols + 1], vv[a + cols]))
            lace_uv.append((f, [tuv[a], tuv[a + 1], tuv[a + cols + 1], tuv[a + cols]]))
    marks["tongue"].append([xc, Y_FIRST - 0.016, Y_LAST + 0.012])

    # laces: a straight bar across the first pair, then criss-cross, each crossing arched
    def lace(pa, na, pb, nb, lift):
        pts, nrs = [], []
        for k in range(9):
            t = k / 8
            q = pa.lerp(pb, t)
            top, n = top_point(q.x, q.y, 0.0)
            if top is None:
                top, n = q, na.lerp(nb, t).normalized()
            arch = math.sin(math.pi * t)
            # the ends dip into the eyelets; the middle rides over the tongue
            h = (0.0026 + lift) * arch + 0.0006
            pts.append(top + n * (h + 0.0022 * arch))
            nrs.append(n)
        return pts, nrs
    segs = [(eyelets[0][0], eyelets[0][1], 0.0)]
    for i in range(N_EYELETS - 1):
        segs.append((eyelets[i][0], eyelets[i + 1][1], 0.0012 * (i % 2)))
        segs.append((eyelets[i][1], eyelets[i + 1][0], 0.0012 * ((i + 1) % 2)))
    for (pa, na), (pb, nb), lift in segs:
        pts, nrs = lace(pa, na, pb, nb, lift)
        rows, us, faces = ribbon(lace_bm, pts, nrs, LACE_W, LACE_T)
        for f, i, j in faces:
            v0, v1 = 0.5 + 0.5 * j / 6, 0.5 + 0.5 * (j + 1) / 6
            lace_uv.append((f, [(us[i], v0), (us[i], v1), (us[i + 1], v1), (us[i + 1], v0)]))
    # the bow over the top pair: two loops lying back over the tongue and two tails
    kp = (eyelets[-1][0][0] + eyelets[-1][1][0]) * 0.5
    kn = (eyelets[-1][0][1] + eyelets[-1][1][1]).normalized()
    knot = kp + kn * 0.006
    fwd = Vector((0, -1, 0))
    for s in (-1.0, 1.0):
        lat = Vector((s * sg, 0, 0))
        loop = []
        for k in range(15):
            a = 2 * math.pi * k / 14
            # a flattened teardrop out to the side, lying back toward the toe
            q = knot + lat * (0.016 * (0.5 - 0.5 * math.cos(a))) + fwd * (0.011 * math.sin(a) + 0.004 * (0.5 - 0.5 * math.cos(a))) + kn * (0.004 * (0.5 - 0.5 * math.cos(a)))
            loop.append(q)
        nrs = [kn] * len(loop)
        rows, us, faces = ribbon(lace_bm, loop, nrs, LACE_W, LACE_T)
        for f, i, j in faces:
            v0, v1 = 0.5 + 0.5 * j / 6, 0.5 + 0.5 * (j + 1) / 6
            lace_uv.append((f, [(us[i], v0), (us[i], v1), (us[i + 1], v1), (us[i + 1], v0)]))
        tail = []
        for k in range(8):
            t = k / 7
            q = knot + lat * (0.006 + 0.012 * t) + fwd * (-0.004 - 0.02 * t) - kn * (0.0 + 0.012 * t * t)
            hit, n = top_point(q.x, q.y, 0.0017)
            if hit is not None and hit.z > q.z:
                q = hit
            tail.append(q)
        rows, us, faces = ribbon(lace_bm, tail, [kn] * len(tail), LACE_W, LACE_T)
        for f, i, j in faces:
            v0, v1 = 0.5 + 0.5 * j / 6, 0.5 + 0.5 * (j + 1) / 6
            lace_uv.append((f, [(us[i], v0), (us[i], v1), (us[i + 1], v1), (us[i + 1], v0)]))
    marks.setdefault("knots", []).append(list(knot))
lme = bpy.data.meshes.new("shoe_laces")
uvl = lace_bm.loops.layers.uv.new(UVN)
for f, uvs in lace_uv:
    for l, uv in zip(f.loops, uvs):
        l[uvl].uv = uv
lace_bm.to_mesh(lme)
lace_bm.free()
for p in lme.polygons:
    p.use_smooth = True
laces = bpy.data.objects.new("hero.shoe_laces", lme)
scene.collection.objects.link(laces)
laces.parent = arm
bpy.context.view_layer.objects.active = laces
for x in bpy.context.selected_objects:
    x.select_set(False)
laces.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.object.mode_set(mode='OBJECT')
# weights from the shoe itself
for g in shoes.vertex_groups:
    laces.vertex_groups.new(name=g.name)
m = laces.modifiers.new("DT", 'DATA_TRANSFER')
m.object = shoes
m.use_vert_data = True
m.data_types_verts = {'VGROUP_WEIGHTS'}
m.vert_mapping = 'POLYINTERP_NEAREST'
m.layers_vgroup_select_src = 'ALL'
m.layers_vgroup_select_dst = 'NAME'
bpy.ops.object.modifier_apply(modifier=m.name)
laces.modifiers.new("Armature", 'ARMATURE').object = arm
arm.data.pose_position = 'POSE'
json.dump(marks, open(common.work("shoe_marks.json"), "w"), indent=1)
print("SH laces and tongues %d tris, %d eyelets" % (sum(len(p.vertices) - 2 for p in lme.polygons), len(marks["eyelets"])))
bpy.ops.wm.save_as_mainfile(filepath=common.work("hero_sh.blend"))
