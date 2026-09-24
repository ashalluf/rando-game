# Step: model the tracksuit on the MPFB body, by script.
#
#  - jacket + trousers: one shell grown off the body's own faces (so it inherits the body's UVs
#    and skin weights), offset for a loose fit, smoothed so the anatomy does not print through,
#    then given the low-frequency drape of the fold field (folds.py). The fine folds - cuff and
#    ankle stacking, the crook of the elbow, behind the knee, both for a straight and for a
#    closed joint - are normal maps made from the same field (prep_textures.py), not a bake.
#  - every garment edge is CUT, not picked face by face: the neckline is a plane through the
#    back and front of the neck, the V of the half zip two planes, the sleeve and trouser ends
#    planes across the limb. Picking whole faces is what left the collar ragged.
#  - ribbed collar, cuffs, hem band and ankle cuffs are bands with a real cross-section: an outer
#    face tucked under the garment edge, a rolled lip, an inner face. The collar stands clear of
#    the neck so the chain can run under it.
#  - two cream piping cords down each sleeve and each outer leg, zip tapes along the V, the zip
#    teeth, a bevelled slider and pull, and the white ribbed tank as its own mesh with a bound
#    scoop neckline (the old one was a patch of skin faces with a staircase for an edge).
#  - the body under the garments is masked away, one ring inside every edge.
# Writes work/hero_ts.blend and work/ts_landmarks.json.
import json
import math
import os
import sys

import bmesh
import bpy
import mathutils.kdtree
import numpy as np
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import folds  # noqa: E402

cfg = common.config()
TS = cfg.get("tracksuit", {})
bpy.ops.wm.open_mainfile(filepath=common.work("hero_mpfb.blend"))
scene = bpy.context.scene
arm = bpy.data.objects["hero"]
body = bpy.data.objects["hero.body"]
P = "mixamorig:"
GARMENT_TRIS = TS.get("garment_tris", 18000)


def bone(n):
    return arm.data.bones[P + n]


def H(n):
    return bone(n).head_local.copy()


def activate(o):
    for x in bpy.context.selected_objects:
        x.select_set(False)
    bpy.context.view_layer.objects.active = o
    o.select_set(True)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


# ---- body with targets applied, all vertices kept (indices = original) --------------------------
saved = [(m, m.show_viewport) for m in body.modifiers]
for m, _ in saved:
    m.show_viewport = False
dg = bpy.context.evaluated_depsgraph_get()
src_me = bpy.data.meshes.new_from_object(body.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
for m, s in saved:
    m.show_viewport = s
body_src = bpy.data.objects.new("body_src", src_me)
scene.collection.objects.link(body_src)
for g in body.vertex_groups:
    body_src.vertex_groups.new(name=g.name)
V = np.array([v.co[:] for v in src_me.vertices])
NV = len(V)
W = {}
for v in src_me.vertices:
    for g in v.groups:
        n = body.vertex_groups[g.group].name
        if n.startswith(P) or n in ("body", "scalp", "lips", "fingernails"):
            W.setdefault(n, np.zeros(NV))[v.index] = g.weight
is_body = W["body"] > 0.5
bone_names = [n for n in W if n.startswith(P)]
bone_w = np.stack([W[n] for n in bone_names], 1)

# Landmarks (metres, Z up, the figure faces -Y).
LSH, LEL, LWR = H("LeftArm"), H("LeftForeArm"), H("LeftHand")
RSH, REL, RWR = H("RightArm"), H("RightForeArm"), H("RightHand")
LHIP, LKN, LAN = H("LeftUpLeg"), H("LeftLeg"), H("LeftFoot")
RHIP, RKN, RAN = H("RightUpLeg"), H("RightLeg"), H("RightFoot")
NECK, HEAD, HIPS, CHEST = H("Neck"), H("Head"), H("Hips"), H("Spine2")
z_hem = HIPS.z - 0.075            # jacket bottom (the rib band hangs below it)
z_nb = NECK.z + 0.005             # neckline at the back of the neck
z_nf = NECK.z - 0.065             # neckline at the front (sternal notch)
z_stop = z_nf - 0.17              # zipper stop: half-zipped
z_tank_top = z_nf - 0.10          # tank-top scoop neckline (centre)
z_pants_end = LAN.z + 0.05        # trousers end just above the ankle; rib cuff below
SLEEVE_END = 0.095                # sleeve stops this far above the wrist joint (shows the watch)
V_TOP_W = 0.056                   # half-width of the V where it meets the neckline
z_vtop = z_nf + 0.012
Y_BACK, Y_FRONT = NECK.y + 0.06, NECK.y - 0.07
print("TS landmarks hem %.3f neck back %.3f front %.3f zip stop %.3f trousers end %.3f" % (z_hem, z_nb, z_nf, z_stop, z_pants_end))


def neck_cut(y):
    """The neckline plane: z at the back of the neck to z at the front, linear in y."""
    return z_nb + (y - Y_BACK) / (Y_FRONT - Y_BACK) * (z_nf - z_nb)


def v_halfwidth(z):
    """The real (cut) V: straight edges from the zipper stop to the neckline."""
    return 0.004 + np.clip((z - z_stop) / (z_vtop - z_stop), 0, 1.5) * (V_TOP_W - 0.004)


def seg_param(p, a, b):
    ab = b - a
    return ((np.asarray(p) - np.array(a)) @ np.array(ab)) / ab.length_squared


def _seg_dist(p, a, b):
    ab = b - a
    t = min(1.0, max(0.0, (Vector(p) - a).dot(ab) / ab.length_squared))
    return (Vector(p) - (a + ab * t)).length


def _off_axis(p, a, b):
    """Distance from p to the line through a and b."""
    ax = (b - a).normalized()
    d = Vector(p) - a
    return (d - ax * d.dot(ax)).length


# ---- face classification ------------------------------------------------------------------------
F = [list(p.vertices) for p in src_me.polygons]
cent = np.array([V[f].mean(0) for f in F])
fbody = np.array([is_body[f].all() for f in F])
fdom = []
for f in F:
    s = bone_w[f].sum(0)
    fdom.append(bone_names[int(s.argmax())].replace(P, ""))
fdom = np.array(fdom)
x, y, z = cent[:, 0], cent[:, 1], cent[:, 2]


def classify(margin):
    """Garment faces. margin > 0 reaches past every edge (the shell is then cut back to the
    edge exactly); margin < 0 stays inside it (the body faces the garment really covers)."""
    cls = np.array([""] * len(F), dtype=object)
    for i in range(len(F)):
        if not fbody[i]:
            continue
        d = fdom[i]
        base = d.replace("Left", "").replace("Right", "")
        p = cent[i]
        if base in ("Arm", "ForeArm"):
            sh, el, wr = (LSH, LEL, LWR) if d.startswith("Left") else (RSH, REL, RWR)
            t = seg_param(p, el, wr)
            if base == "Arm" or t < 1 - (SLEEVE_END - margin) / (wr - el).length:
                cls[i] = "jacket"
        elif base in ("Spine", "Spine1", "Spine2", "Shoulder", "Neck", "Hips"):
            if base == "Hips" and p[2] < z_hem:
                cls[i] = "pants"
            elif p[2] < neck_cut(p[1]) + margin:
                cls[i] = "jacket" if p[2] >= z_hem else "pants"
        elif base in ("UpLeg", "Leg"):
            if p[2] > z_pants_end - margin:
                cls[i] = "pants"
    for i in range(len(F)):
        if cls[i] == "pants" and cent[i][2] >= z_hem:
            cls[i] = "jacket"
    return cls


cls = classify(0.03)
front = y < CHEST.y - 0.02
# The body under the V, and under the tank (which is its own mesh now), stays skin.
vopen = (cls == "jacket") & front & (z > z_stop - 0.02) & (np.abs(x) < v_halfwidth(z) + 0.02)
cls[vopen] = "vskin"
cover = classify(-0.012)
vcover = (cover == "jacket") & front & (z > z_stop - 0.03) & (np.abs(x) < v_halfwidth(z) + 0.004)
cover[vcover] = ""
print("TS faces jacket %d trousers %d vskin %d" % ((cls == "jacket").sum(), (cls == "pants").sum(), (cls == "vskin").sum()))


# ---- helpers to build objects --------------------------------------------------------------------
def new_object(name, me):
    o = bpy.data.objects.new("hero." + name, me)
    scene.collection.objects.link(o)
    o.parent = arm
    return o


def shell_from_faces(name, face_mask):
    """Copy the selected body faces into a new object (keeps UVs and deform weights)."""
    me = src_me.copy()
    o = new_object(name, me)
    for g in body.vertex_groups:
        o.vertex_groups.new(name=g.name)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    kill = [f for f in bm.faces if not face_mask[f.index]]
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bm.to_mesh(me)
    bm.free()
    return o


def add_weights_from_body(o):
    """Skin weights for a new mesh: interpolated from the nearest body faces."""
    for g in body.vertex_groups:
        if g.name not in o.vertex_groups:
            o.vertex_groups.new(name=g.name)
    m = o.modifiers.new("DT", 'DATA_TRANSFER')
    m.object = body_src
    m.use_vert_data = True
    m.data_types_verts = {'VGROUP_WEIGHTS'}
    m.vert_mapping = 'POLYINTERP_NEAREST'
    m.layers_vgroup_select_src = 'ALL'
    m.layers_vgroup_select_dst = 'NAME'
    activate(o)
    bpy.ops.object.modifier_apply(modifier=m.name)


def mesh_from(name, verts, faces, uvs=None, smooth=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.update()
    uvl = me.uv_layers.new(name=src_me.uv_layers.active.name)
    if uvs is not None:
        for poly in me.polygons:
            for li, vi in zip(poly.loop_indices, poly.vertices):
                uvl.data[li].uv = uvs[vi]
    for p in me.polygons:
        p.use_smooth = smooth
    return me


def outward(me, centre_fn):
    """Flip a whole mesh so its first face points away from centre_fn(face centre)."""
    me.update()
    if not me.polygons:
        return
    p0 = me.polygons[len(me.polygons) // 2]
    if p0.normal.dot(p0.center - centre_fn(p0.center)) < 0:
        bm2 = bmesh.new()
        bm2.from_mesh(me)
        bmesh.ops.reverse_faces(bm2, faces=bm2.faces[:])
        bm2.to_mesh(me)
        bm2.free()


body_bvh = BVHTree.FromPolygons([tuple(v) for v in V], [f for f, b in zip(F, fbody) if b])


def skin_radius(c, d, extra, reach=0.1):
    hit = body_bvh.ray_cast(c + d * reach, -d, reach)
    if hit[0] is None:
        return 0.05 + extra
    return (hit[0] - c).length + extra


# The chain runs on the skin round the neck; the jacket and collar are kept clear of it.
CH_R = TS.get("chain_radius", 0.0028)
chain_pts = []
z_cback = z_nb - 0.030
z_cfront = z_nf - 0.07
axis_y = NECK.y + 0.005
for k in range(96):
    th = 2 * math.pi * k / 96
    # hangs low on the chest at the front, rides the base of the neck at the sides and back
    zz = z_cfront + (z_cback - z_cfront) * ((1 - math.cos(th)) / 2) ** 0.45
    d = Vector((math.sin(th), -math.cos(th), 0))
    r_lim = 0.078 + 0.05 * ((1 + math.cos(th)) / 2) ** 3
    for _ in range(40):  # climb until it sits on the neck, not out on the shoulder
        hit = body_bvh.ray_cast(Vector((0, axis_y, zz)), d, 0.3)
        if hit[0] is None or (hit[0] - Vector((0, axis_y, zz))).length <= r_lim:
            break
        zz += 0.002
    if hit[0] is None:
        continue
    nrm = hit[1] if hit[1].dot(d) > 0 else -hit[1]
    chain_pts.append(hit[0] + nrm * (CH_R + 0.0008))
for it in range(6):
    chain_pts = [(chain_pts[i - 1] + chain_pts[i] * 2 + chain_pts[(i + 1) % len(chain_pts)]) / 4 for i in range(len(chain_pts))]
chain_kd = mathutils.kdtree.KDTree(len(chain_pts) * 4)
for k in range(len(chain_pts)):
    for f_ in range(4):
        chain_kd.insert(chain_pts[k].lerp(chain_pts[(k + 1) % len(chain_pts)], f_ / 4.0), k * 4 + f_)
chain_kd.balance()

# ---- jacket + trousers shell -------------------------------------------------------------------------
garment = shell_from_faces("tracksuit", (cls == "jacket") | (cls == "pants") | (cls == "vskin"))
gme = garment.data
bm = bmesh.new()
bm.from_mesh(gme)
bm.verts.ensure_lookup_table()
bm.normal_update()
GV = np.array([v.co[:] for v in bm.verts])
GN = np.array([v.normal[:] for v in bm.verts])
jac_face = {f.index: (f.calc_center_median().z >= z_hem) for f in bm.faces}
isj = np.array([np.mean([jac_face[f.index] for f in v.link_faces]) >= 0.5 for v in bm.verts])
SHOULDER_EASE = TS.get("shoulder_ease", 0.010)


def fit_offset(p, jacket):
    """Loose-fit distance off the body (metres): a track suit hangs, it does not cling."""
    x_, y_, z_ = p
    pv = Vector(p)
    if jacket:
        for (sh, el, wr) in ((LSH, LEL, LWR), (RSH, REL, RWR)):
            t_up = seg_param(p, sh, el)
            t_fo = seg_param(p, el, wr)
            if (x_ > 0) == (sh.x > 0) and min(_seg_dist(pv, sh, el), _seg_dist(pv, el, wr)) < 0.085 and (t_up > -0.05):
                ax = (el - sh).normalized()
                r = pv - sh - ax * (pv - sh).dot(ax)
                inward = max(0.0, r.normalized().dot(Vector((-math.copysign(1, sh.x), 0, 0)))) if r.length > 1e-4 else 0.0
                if t_up <= 1.0:
                    # the sleeve cap sits on the shoulder; the sleeve loosens toward the elbow
                    return (SHOULDER_EASE + 0.013 * min(1.0, t_up * 1.4)) * (1 - 0.5 * inward * (1 - t_up))
                return 0.024 + 0.007 * min(max(t_fo, 0), 1)
        o = 0.028 if y_ < CHEST.y else 0.031
        o -= 0.004 * float(smoothstep(z_hem + 0.08, z_hem, z_))
        # the yoke lies on the shoulders; the neckline stands a little off the neck
        o *= 1 - 0.55 * float(smoothstep(CHEST.z - 0.02, CHEST.z + 0.12, z_)) * float(smoothstep(0.05, 0.16, abs(x_)))
        o = o * (1 - 0.45 * float(smoothstep(neck_cut(y_) - 0.07, neck_cut(y_), z_)))
        return o
    kn = LKN if x_ > 0 else RKN
    hip = LHIP if x_ > 0 else RHIP
    an = LAN if x_ > 0 else RAN
    if z_ < kn.z:
        t = (kn.z - z_) / (kn.z - an.z)
        o = 0.028 + 0.010 * t
    else:
        o = 0.022 + 0.006 * float(smoothstep(HIPS.z, kn.z, z_))
        # inner thighs and crotch: the two legs would run into each other
        o *= 0.5 + 0.5 * float(smoothstep(0.015, abs(hip.x) * 0.9, abs(x_)))
    return o


off = np.array([fit_offset(GV[i], isj[i]) for i in range(len(GV))])
P0 = GV + GN * off[:, None]
bound = np.array([v.is_boundary for v in bm.verts])
nbr = [[e.other_vert(v).index for e in v.link_edges] for v in bm.verts]
Pm = P0.copy()
for it in range(18):  # Taubin: smooth, then un-shrink
    for lam in (0.6, -0.63):
        avg = np.array([Pm[n].mean(0) if n else Pm[i] for i, n in enumerate(nbr)])
        Pm = np.where(bound[:, None], Pm, Pm + lam * (avg - Pm))
# Extra smoothing on the torso so the chest and back hang as fabric, faded in from the sleeves
# rather than stopped dead at them (a hard edge there was a crease across every shoulder).
sleeve_w = np.zeros(len(GV))
for sh, el in ((LSH, LEL), (RSH, REL)):
    ax = (el - sh).normalized()
    s = (GV - np.array(sh)) @ np.array(ax)
    side = (GV[:, 0] > 0) == (sh.x > 0)
    sleeve_w = np.maximum(sleeve_w, np.where(side & isj, smoothstep(-0.07, 0.02, s), 0.0))
tors_w = np.where(isj, 1.0 - sleeve_w, 0.0) * (~bound)
for it in range(25):
    avg = np.array([Pm[n].mean(0) if n else Pm[i] for i, n in enumerate(nbr)])
    Pm = Pm + (0.5 * tors_w)[:, None] * (avg - Pm)


def push_out(pts, clearance_fn):
    out = pts.copy()
    for i, p in enumerate(pts):
        loc, nrm, idx, dist = body_bvh.find_nearest(Vector(p))
        if loc is None:
            continue
        c = clearance_fn(p)
        d = Vector(p) - loc
        if d.dot(nrm) < 0 or dist < c:
            out[i] = np.array(loc + nrm * c)
    return out


# 8 mm off the body everywhere; 13.5 mm round the neckline, where the collar stands inside it
Pm = push_out(Pm, lambda p: 0.008 + 0.0055 * float(smoothstep(neck_cut(p[1]) - 0.06, neck_cut(p[1]) - 0.01, p[2])) * float(abs(p[0]) < 0.12))
for i in range(len(Pm)):
    co, idx, dist = chain_kd.find(Vector(Pm[i]))
    if dist < 0.013:
        loc, nrm, _, _ = body_bvh.find_nearest(Vector(Pm[i]))
        Pm[i] = np.array(Vector(Pm[i]) + nrm * (0.013 - dist))
for v, p in zip(bm.verts, Pm):
    v.co = Vector(p)
bm.to_mesh(gme)
bm.free()
gj = garment.vertex_groups.new(name="ts_jacket")
gj.add([i for i in range(len(GV)) if isj[i]], 1.0, 'REPLACE')


def smooth_shoulder_weights(o, iters=10, reach=0.13):
    """Blur the skin weights round each shoulder over the cloth. The body's weights change from
    collarbone to upper arm within a couple of faces, which is right for skin over a joint and
    wrong for a jacket, whose cap then folds along one crease when the arm drops."""
    names = [P + n for n in ("LeftShoulder", "RightShoulder", "LeftArm", "RightArm", "Spine2", "Spine1", "Neck")]
    idx = {o.vertex_groups[n].index: n for n in names if n in o.vertex_groups}
    bmx = bmesh.new()
    bmx.from_mesh(o.data)
    dl = bmx.verts.layers.deform.active
    bmx.verts.ensure_lookup_table()
    near = [min((v.co - LSH).length, (v.co - RSH).length) < reach for v in bmx.verts]
    W0 = np.array([[v[dl].get(g, 0.0) for g in idx] for v in bmx.verts])
    W = W0.copy()
    nb = [[e.other_vert(v).index for e in v.link_edges] for v in bmx.verts]
    for _ in range(iters):
        avg = np.array([W[n].mean(0) if n else W[i] for i, n in enumerate(nb)])
        W = np.where(np.array(near)[:, None], 0.5 * W + 0.5 * avg, W)
    for i, v in enumerate(bmx.verts):
        if not near[i]:
            continue
        # keep the vertex's total weight on these bones; the others (e.g. none) are untouched
        tot0, tot = W0[i].sum(), W[i].sum()
        scale = tot0 / tot if tot > 1e-6 else 0.0
        for k, g in enumerate(idx):
            w = W[i, k] * scale
            if w > 1e-4:
                v[dl][g] = w
            elif g in v[dl]:
                del v[dl][g]
    bmx.to_mesh(o.data)
    bmx.free()


smooth_shoulder_weights(garment)


# ---- cut every edge: the V, the neckline, the sleeve and trouser ends ------------------------------
def cut(bmx, plane_co, plane_no, region, kill_side):
    """Bisect `region` faces by a plane and delete what lies on kill_side(centre) of it."""
    faces = [f for f in bmx.faces if region(f.calc_center_median())]
    geom = list({v for f in faces for v in f.verts}) + list({e for f in faces for e in f.edges}) + faces
    bmesh.ops.bisect_plane(bmx, geom=geom, plane_co=plane_co, plane_no=plane_no, dist=0.0002)
    kill = [f for f in bmx.faces if region(f.calc_center_median()) and kill_side(f.calc_center_median())]
    bmesh.ops.delete(bmx, geom=kill, context='FACES')
    loose = [v for v in bmx.verts if not v.link_faces]
    bmesh.ops.delete(bmx, geom=loose, context='VERTS')


bm = bmesh.new()
bm.from_mesh(gme)
planes = []
for sg in (1, -1):
    S = Vector((0.004 * sg, 0, z_stop))
    T = Vector((V_TOP_W * sg, 0, z_vtop))
    n = (T - S).cross(Vector((0, 1, 0))).normalized()
    if n.dot(Vector((-sg, 0, 0.3))) < 0:
        n = -n
    planes.append((S, n))
near_v = lambda c: c.y < CHEST.y and c.z > z_stop - 0.05 and abs(c.x) < 0.16  # noqa: E731
for S, n in planes:
    faces = [f for f in bm.faces if near_v(f.calc_center_median())]
    geom = list({v for f in faces for v in f.verts}) + list({e for f in faces for e in f.edges}) + faces
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=S, plane_no=n, dist=0.0002)
kill = [f for f in bm.faces if f.calc_center_median().y < CHEST.y and f.calc_center_median().z > z_stop - 0.001
        and all(n.dot(f.calc_center_median() - S) > 0 for S, n in planes)]
bmesh.ops.delete(bm, geom=kill, context='FACES')
# neckline: the plane through (y_back, z_nb) and (y_front, z_nf), containing the X axis
ncut_co = Vector((0, Y_BACK, z_nb))
ncut_no = Vector((1, 0, 0)).cross(Vector((0, Y_FRONT - Y_BACK, z_nf - z_nb))).normalized()
if ncut_no.dot(Vector((0, 0, 1))) < 0:
    ncut_no = -ncut_no
cut(bm, ncut_co, ncut_no, lambda c: c.z > CHEST.z and abs(c.x) < 0.11, lambda c: ncut_no.dot(c - ncut_co) > 0)
# sleeve ends: a plane across the forearm SLEEVE_END above the wrist
for sh, el, wr in ((LSH, LEL, LWR), (RSH, REL, RWR)):
    ax = (wr - el).normalized()
    co = wr - ax * SLEEVE_END
    # only faces round the forearm itself: with the arms bound hanging, the hip is "beyond the
    # cuff" along the forearm too, and a region by side and distance along alone ate it
    cut(bm, co, ax, lambda c, el=el, wr=wr: (c.x > 0) == (el.x > 0) and seg_param(c, el, wr) > 0.3 and _off_axis(c, el, wr) < 0.08,
        lambda c, co=co, ax=ax: ax.dot(c - co) > 0)
# trouser ends: a plane across the shin at z_pants_end
for hip, kn, an in ((LHIP, LKN, LAN), (RHIP, RKN, RAN)):
    ax = (an - kn).normalized()
    t = (z_pants_end - kn.z) / (an.z - kn.z)
    co = kn + (an - kn) * t
    cut(bm, co, ax, lambda c, kn=kn: (c.x > 0) == (kn.x > 0) and c.z < kn.z - 0.1,
        lambda c, co=co, ax=ax: ax.dot(c - co) > 0)
bm.to_mesh(gme)
bm.free()


# ---- drape (geometry part of the fold field) --------------------------------------------------------
def landmarks():
    L = {"z_hem": z_hem, "z_nb": z_nb, "z_nf": z_nf, "z_stop": z_stop, "z_vtop": z_vtop, "v_top_w": V_TOP_W,
         "z_tank_top": z_tank_top, "z_pants_end": z_pants_end, "sleeve_end": SLEEVE_END, "y_back": Y_BACK,
         "y_front": Y_FRONT, "chain_radius": CH_R}
    for b in arm.data.bones:
        L[b.name.replace(P, "")] = list(b.head_local)
    L["chain"] = [list(p) for p in chain_pts]
    return L


LM = landmarks()


def apply_subdiv(o, levels):
    m = o.modifiers.new("SS", 'SUBSURF')
    m.levels = levels
    m.render_levels = levels
    m.uv_smooth = 'PRESERVE_BOUNDARIES'
    m.boundary_smooth = 'PRESERVE_CORNERS'
    activate(o)
    bpy.ops.object.modifier_apply(modifier=m.name)


apply_subdiv(garment, 1)
bm = bmesh.new()
bm.from_mesh(garment.data)
bm.normal_update()
dvl = bm.verts.layers.deform.active
gi = garment.vertex_groups["ts_jacket"].index
pts = np.array([v.co[:] for v in bm.verts])
jj = np.array([v[dvl].get(gi, 0.0) >= 0.5 for v in bm.verts])
geo = folds.fields(pts, jj, LM, which=("geom",))["geom"] * TS.get("drape_gain", 1.35)
for v, h in zip(bm.verts, geo):
    v.co = v.co + v.normal * float(h)
bm.to_mesh(garment.data)
bm.free()
activate(garment)
dec = garment.modifiers.new("DEC", 'DECIMATE')
dec.decimate_type = 'COLLAPSE'
tri_now = sum(len(p.vertices) - 2 for p in garment.data.polygons)
dec.ratio = min(1.0, GARMENT_TRIS / tri_now)
dec.use_symmetry = True
dec.symmetry_axis = 'X'
bpy.ops.object.modifier_apply(modifier=dec.name)
print("TS garment tris before %d after %d" % (tri_now, sum(len(p.vertices) - 2 for p in garment.data.polygons)))
for p in garment.data.polygons:
    p.use_smooth = True
gbvh = BVHTree.FromObject(garment, bpy.context.evaluated_depsgraph_get())


def surf_point(origin, direction, bvh=None, offset=0.0):
    hit = (bvh or gbvh).ray_cast(Vector(origin), Vector(direction).normalized(), 1.0)
    if hit[0] is None:
        return None, None
    return hit[0] + hit[1] * offset, hit[1]


def garment_radius(c, d, extra, reach=0.12):
    hit = gbvh.ray_cast(c + d * reach, -d, reach)
    if hit[0] is None:
        return None
    return (hit[0] - c).length + extra


# ---- ribbed bands with a cross-section ----------------------------------------------------------------
RIB_PERIOD = 0.0045  # one rib every 4.5 mm; the rib texture has 8 across one U


def section_band(name, frame_fn, a_list, profile_fn, closed, caps=False):
    """A band swept round an axis. frame_fn(a) -> (centre, radial dir, axial dir); profile_fn(a)
    -> list of (radial offset from the centre, axial offset) from the tucked outer edge, over the
    lip, to the inner edge. u runs round (in ribs), v along the profile."""
    verts, uvs, rows = [], [], []
    arcs = []
    prev = None
    arc = 0.0
    for a in a_list:
        c, d, ax = frame_fn(a)
        prof = profile_fn(a)
        mid = c + d * prof[len(prof) // 3][0] + ax * prof[len(prof) // 3][1]
        if prev is not None:
            arc += (mid - prev).length
        prev = mid
        arcs.append(arc)
        row = []
        plen = [0.0]
        for k in range(1, len(prof)):
            plen.append(plen[-1] + math.hypot(prof[k][0] - prof[k - 1][0], prof[k][1] - prof[k - 1][1]))
        for k, (r, h) in enumerate(prof):
            row.append(len(verts))
            verts.append(c + d * r + ax * h)
            uvs.append((arc / RIB_PERIOD / 8.0, plen[k] / max(plen[-1], 1e-6)))
        rows.append(row)
    faces = []
    n = len(rows)
    for i in range(n if closed else n - 1):
        a_, b_ = rows[i], rows[(i + 1) % n]
        for k in range(len(a_) - 1):
            faces.append((a_[k], a_[k + 1], b_[k + 1], b_[k]))
    if caps and not closed:
        for row in (rows[0], rows[-1]):
            faces.append(tuple(row) if row is rows[-1] else tuple(reversed(row)))
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.update()
    uvl = me.uv_layers.new(name=src_me.uv_layers.active.name)
    total = arcs[-1] + (rows and (verts[rows[0][0]] - verts[rows[-1][0]]).length or 0)
    for poly in me.polygons:
        us = [uvs[vi][0] for vi in poly.vertices]
        for li, vi in zip(poly.loop_indices, poly.vertices):
            u, v = uvs[vi]
            if closed and max(us) - u > 2.0:  # the far side of the wrap-around seam
                u += total / RIB_PERIOD / 8.0
            uvl.data[li].uv = (u, v)
    for p in me.polygons:
        p.use_smooth = True
    o = new_object(name, me)
    return o


def fix_winding(o, centre_fn):
    """Faces of an outer band surface point away from its axis."""
    me = o.data
    me.update()
    bm2 = bmesh.new()
    bm2.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm2, faces=bm2.faces[:])
    bm2.faces.ensure_lookup_table()
    f0 = bm2.faces[0]
    c = f0.calc_center_median()
    if f0.normal.dot(c - centre_fn(c)) < 0:
        bmesh.ops.reverse_faces(bm2, faces=bm2.faces[:])
    bm2.to_mesh(me)
    bm2.free()


def limb_frame_fn(a_pt, b_pt, s):
    ax = (b_pt - a_pt).normalized()
    fwd = Vector((0, -1, 0))
    fwd = (fwd - ax * fwd.dot(ax)).normalized()
    lat = ax.cross(fwd)
    c = a_pt + ax * s

    def fn(a):
        d = (fwd * math.cos(a) + lat * math.sin(a)).normalized()
        return c, d, ax
    return fn


def cuff_band(name, a_pt, b_pt, s_top, length, seg, skin_extra, top_overlap, reach=0.12):
    """A rib cuff round the limb a->b: starts tucked `top_overlap` inside the garment end at
    s_top, runs `length` toward b snug on the skin, rolls over its end and comes back inside."""
    frames = {}

    def prof(a):
        ax = (b_pt - a_pt).normalized()
        out = []
        for s, tag in ((s_top - top_overlap, "tuck"), (s_top, "edge"), (s_top + length * 0.35, "mid"), (s_top + length - 0.004, "end")):
            c, d, _ = limb_frame_fn(a_pt, b_pt, s)(a)
            skin = skin_radius(c, d, 0.0, reach)
            g = garment_radius(c, d, 0.0, reach + 0.01)
            if tag == "tuck":
                r = (g - 0.004) if g is not None else skin + 0.008
            elif tag == "edge":
                r = (g - 0.0015) if g is not None else skin + 0.009
            else:
                r = skin + skin_extra
            out.append((r, s - s_top))
        r_end = out[-1][0]
        out.append((r_end - 0.0022, length - 0.0006))       # the rolled lip
        out.append((r_end - 0.0045, length - 0.004))        # inner face
        out.append((r_end - 0.0048, length - 0.016))
        frames[a] = out
        return out
    fn0 = limb_frame_fn(a_pt, b_pt, s_top)
    o = section_band(name, fn0, [2 * math.pi * k / seg for k in range(seg)], prof, closed=True)
    ax = (b_pt - a_pt).normalized()
    fix_winding(o, lambda c: a_pt + ax * (c - a_pt).dot(ax))
    return o


bands = []
for tag, (sh, el, wr) in (("L", (LSH, LEL, LWR)), ("R", (RSH, REL, RWR))):
    s_end = (wr - el).length - SLEEVE_END
    bands.append(cuff_band("ts_cuff_" + tag, el, wr, s_end, 0.052, 28, 0.0045, 0.014, reach=0.065))
for tag, (hip, kn, an) in (("L", (LHIP, LKN, LAN)), ("R", (RHIP, RKN, RAN))):
    s_end = (kn.z - z_pants_end) / (kn.z - an.z) * (an - kn).length
    bands.append(cuff_band("ts_ankle_" + tag, kn, an, s_end, 0.040, 30, 0.006, 0.014))


# hem band: round the torso, tucked up inside the jacket, snug on the hips, rolled at the bottom
def hem_band():
    top = Vector((0, HIPS.y, z_hem))
    down = Vector((0, 0, -1))

    def fn(a):
        d = Vector((math.sin(a), -math.cos(a), 0))
        return top, d, down

    def prof(a):
        d = Vector((math.sin(a), -math.cos(a), 0))
        out = []
        for s, tag in ((-0.014, "tuck"), (0.0, "edge"), (0.02, "mid"), (0.051, "end")):
            c = top + down * s
            skin = skin_radius(c, d, 0.0, 0.3)
            g = garment_radius(c, d, 0.0, 0.32)
            if tag in ("tuck", "edge"):
                r = (g - (0.004 if tag == "tuck" else 0.0015)) if g is not None else skin + 0.012
            else:
                r = skin + 0.011
            out.append((r, s))
        r_end = out[-1][0]
        out += [(r_end - 0.0022, 0.0549), (r_end - 0.0045, 0.051), (r_end - 0.0048, 0.038)]
        return out
    o = section_band("ts_hem", fn, [2 * math.pi * k / 56 for k in range(56)], prof, closed=True)
    fix_winding(o, lambda c: Vector((0, HIPS.y, c.z)))
    return o


bands.append(hem_band())


# collar: a stand collar round the back and sides of the neck, open at the V
def collar():
    r_n = skin_radius(Vector((0, NECK.y + 0.005, z_vtop)), Vector((0, -1, 0)), 0.013, 0.13)
    open_half = math.asin(min(0.98, V_TOP_W / r_n))
    cy = NECK.y + 0.005

    def base(a):
        d = Vector((math.sin(a), -math.cos(a), 0))
        zb = neck_cut(cy - math.cos(a) * 0.065)
        for _ in range(2):  # the plane's height where the jacket really is at this azimuth
            g = garment_radius(Vector((0, cy, zb - 0.004)), d, 0.0, 0.16)
            if g is None:
                break
            zb = neck_cut(cy - math.cos(a) * g)
        return d, zb, g

    def fn(a):
        d, zb, _ = base(a)
        return Vector((0, cy, zb)), d, Vector((0, 0, 1))

    def prof(a):
        d, zb, g = base(a)
        c = Vector((0, cy, zb))
        back = (1 - math.cos(a)) / 2  # 0 at the front ends, 1 at the back
        h = 0.031 + 0.011 * back
        s_lo = skin_radius(c, d, 0.0, 0.13)
        s_hi = skin_radius(c + Vector((0, 0, h)), d, 0.0, 0.13)
        rj = (g if g is not None else s_lo + 0.0135)
        r_out_lo = max(rj - 0.0015, s_lo + 0.012)
        r_out_hi = s_hi + 0.0125
        r_in_hi = r_out_hi - 0.0052
        r_in_lo = max(s_lo + 0.0072, r_out_lo - 0.0055)
        return [(r_out_lo - 0.0025, -0.016), (r_out_lo, -0.002), (r_out_lo + (r_out_hi - r_out_lo) * 0.4, h * 0.4),
                (r_out_hi, h - 0.0035), (r_out_hi - 0.0026, h), (r_in_hi, h - 0.0035),
                (r_in_lo + (r_in_hi - r_in_lo) * 0.5, h * 0.4), (r_in_lo, -0.004)]
    seg = 44
    a_list = [open_half + (2 * math.pi - 2 * open_half) * k / seg for k in range(seg + 1)]
    o = section_band("ts_collar", fn, a_list, prof, closed=False, caps=True)
    fix_winding(o, lambda c: Vector((0, cy, c.z)))
    return o


bands.append(collar())


# zip tapes: the two edges of the V, a folded strip of the jacket's own velour
def build_vtape(name, sg):
    rows = []
    for zz in np.linspace(z_stop + 0.002, z_vtop - 0.002, 18):
        xe = float(v_halfwidth(zz)) * sg
        hit, nrm = surf_point(Vector((xe + sg * 0.007, -0.5, zz)), Vector((0, 1, 0)))
        if hit is None:
            continue
        t = Vector((-sg, 0, 0))
        t = (t - nrm * t.dot(nrm)).normalized()
        a_ = hit + nrm * 0.0012
        rows.append([a_ - t * 0.005, a_ + t * 0.004 + nrm * 0.0022, a_ + t * 0.0072 + nrm * 0.0008, a_ + t * 0.0074 - nrm * 0.008])
    V2, F2, UV2 = [], [], []
    for k, r in enumerate(rows):
        base = len(V2)
        V2.extend(r)
        UV2 += [(0.0, k * 0.4), (0.4, k * 0.4), (0.7, k * 0.4), (1.0, k * 0.4)]
        if k:
            for j in range(3):
                F2.append((base - 4 + j, base - 4 + j + 1, base + j + 1, base + j))
    me = mesh_from(name, V2, F2, uvs=UV2)
    o = new_object(name, me)
    fix_winding(o, lambda c: c + Vector((0, 0.05, 0)))
    return o


bands.append(build_vtape("ts_cuff_vL", 1))   # "ts_cuff" prefix: shares the rib material
bands.append(build_vtape("ts_cuff_vR", -1))
print("TS bands", [(b.name, len(b.data.polygons)) for b in bands])

# ---- piping: two cream cords down each sleeve and each outer leg ------------------------------------
PIPE_W, PIPE_GAP, PIPE_H = 0.0045, 0.006, 0.0018
PIPE_REACH = 0.11  # rays start this far out from the limb axis: past the cloth, short of the arm


def piping_path(chain, side_sign, start_s, end_s, step=0.02):
    pts_ = []
    total = sum((b - a).length for a, b in chain)
    s = start_s
    while s <= min(end_s, total):
        acc = 0.0
        for a, b in chain:
            Lseg = (b - a).length
            if s <= acc + Lseg or (a, b) == chain[-1]:
                t = (s - acc) / Lseg
                c = a + (b - a) * t
                ax = (b - a).normalized()
                break
            acc += Lseg
        lat = Vector((side_sign, 0, 0))
        lat = (lat - ax * lat.dot(ax)).normalized()
        pts_.append((c, ax, lat))
        s += step
    return pts_


def build_piping(name, path):
    verts = []
    for k, (c, ax, lat) in enumerate(path):
        row = []
        for off_sign in (-1, 1):
            hit, nrm = surf_point(c + lat * PIPE_REACH, -lat)
            if hit is None:
                continue
            r = (hit - c).length
            ang = off_sign * (PIPE_GAP * 0.5 + PIPE_W * 0.5) / max(r, 0.02)
            d = Quaternion(ax, ang) @ lat
            hit, nrm = surf_point(c + d * PIPE_REACH, -d)
            if hit is None:
                continue
            tang = ax.cross(nrm).normalized()
            for j, (w, hgt) in enumerate(((-0.5, 0.15), (-0.25, 0.8), (0.25, 0.8), (0.5, 0.15))):
                row.append(hit + nrm * (0.0006 + PIPE_H * hgt) + tang * (w * PIPE_W))
        verts.append(row)
    rows = [r for r in verts if len(r) == 8]
    V2, F2 = [], []
    for k, r in enumerate(rows):
        base = len(V2)
        V2.extend(r)
        if k:
            pb = base - 8
            for cord in (0, 4):
                for j in (0, 1, 2):
                    F2.append((pb + cord + j, pb + cord + j + 1, base + cord + j + 1, base + cord + j))
    me = mesh_from(name, V2, F2)
    uvl = me.uv_layers.active
    for poly in me.polygons:
        for li, vi in zip(poly.loop_indices, poly.vertices):
            uvl.data[li].uv = ((vi % 4) / 3.0, (vi // 8) * 0.5)
    o = new_object(name, me)
    me.update()
    p0 = me.polygons[len(me.polygons) // 2] if me.polygons else None
    if p0 is not None:
        hit = gbvh.find_nearest(p0.center)
        if hit[0] is not None and p0.normal.dot(hit[1]) < 0:
            bm2 = bmesh.new()
            bm2.from_mesh(me)
            bmesh.ops.reverse_faces(bm2, faces=bm2.faces[:])
            bm2.to_mesh(me)
            bm2.free()
    return o


pipes = []
for tag, sgn, (sh, el, wr) in (("L", 1, (LSH, LEL, LWR)), ("R", -1, (RSH, REL, RWR))):
    shoulder_top = Vector((sh.x * 0.62, sh.y, sh.z + 0.055))
    ch = [(shoulder_top, sh), (sh, el), (el, wr)]
    tot = sum((b - a).length for a, b in ch)
    pipes.append(build_piping("ts_pipe_arm_" + tag, piping_path(ch, sgn, 0.0, tot - SLEEVE_END - 0.004)))
for tag, sgn, (hip, kn, an) in (("L", 1, (LHIP, LKN, LAN)), ("R", -1, (RHIP, RKN, RAN))):
    top = Vector((hip.x * 1.1, hip.y, z_hem - 0.01))
    ch = [(top, kn), (kn, an)]
    tot = sum((b - a).length for a, b in ch)
    s_end = (top.z - z_pants_end) / (top.z - an.z) * tot
    pipes.append(build_piping("ts_pipe_leg_" + tag, piping_path(ch, sgn, 0.0, s_end - 0.004)))
print("TS piping", [(p.name, len(p.data.polygons)) for p in pipes])

# ---- zip: teeth from the hem band to the stop, a bevelled slider and pull ------------------------------
zs = np.arange(z_hem - 0.045, z_stop + 0.0001, 0.006)
rows = []
for zz in zs:
    hit, nrm = surf_point(Vector((0, -0.5, zz)), Vector((0, 1, 0)))
    if hit is None:
        continue
    tang = Vector((1, 0, 0))
    rows.append([hit + nrm * 0.0006 + tang * -0.0048, hit + nrm * 0.0019 + tang * -0.0028, hit + nrm * 0.0024,
                 hit + nrm * 0.0019 + tang * 0.0028, hit + nrm * 0.0006 + tang * 0.0048])
ZV, ZF, ZU = [], [], []
for k, r in enumerate(rows):
    base = len(ZV)
    ZV.extend(r)
    ZU += [(j / 4.0, k * 1.5) for j in range(5)]
    if k:
        for j in range(4):
            ZF.append((base - 5 + j, base - 5 + j + 1, base + j + 1, base + j))
zipper = new_object("ts_zipper", mesh_from("ts_zipper", ZV, ZF, uvs=ZU))
fix_winding(zipper, lambda c: c + Vector((0, 0.05, 0)))
top_hit, top_n = surf_point(Vector((0, -0.5, z_stop - 0.004)), Vector((0, 1, 0)))
bm = bmesh.new()
body_ = bmesh.ops.create_cube(bm, size=1.0)
for v in body_["verts"]:
    v.co = Vector((v.co.x * 0.012, v.co.y * 0.0055, v.co.z * 0.017))
pull = bmesh.ops.create_cube(bm, size=1.0)
for v in pull["verts"]:
    v.co = Vector((v.co.x * (0.0085 if v.co.z < 0 else 0.0065), v.co.y * 0.0018 - 0.0045, v.co.z * 0.028 - 0.023))
bmesh.ops.bevel(bm, geom=bm.edges[:], offset=0.0012, segments=2, affect='EDGES', profile=0.5)
bmesh.ops.transform(bm, matrix=Matrix.Translation(top_hit + top_n * 0.0032), verts=bm.verts[:])
sme = bpy.data.meshes.new("ts_slider")
bm.to_mesh(sme)
bm.free()
sme.uv_layers.new(name=src_me.uv_layers.active.name)
for p in sme.polygons:
    p.use_smooth = True
slider = new_object("ts_slider", sme)


# ---- white ribbed tank: its own mesh, scoop neckline with a bound edge -------------------------------
def tank_mesh():
    xs_ = np.linspace(-0.105, 0.105, 29)
    zs_ = np.linspace(z_stop - 0.05, z_tank_top + 0.05, 20)
    grid = {}
    for i, xx in enumerate(xs_):
        top = z_tank_top + 0.036 * (abs(xx) / 0.09) ** 2
        for j, zz in enumerate(zs_):
            zc = min(zz, top)
            hit = body_bvh.ray_cast(Vector((xx, -0.5, zc)), Vector((0, 1, 0)), 1.0)
            if hit[0] is None:
                continue
            n = hit[1] if hit[1].y < 0 else -hit[1]
            grid[(i, j)] = (hit[0] + n * 0.0032, (xx / (RIB_PERIOD * 0.8) / 8.0, zc / 0.05))
    verts, uvs, idx = [], [], {}
    for k, (p, uv) in grid.items():
        idx[k] = len(verts)
        verts.append(p)
        uvs.append(uv)
    faces = []
    for i in range(len(xs_) - 1):
        for j in range(len(zs_) - 1):
            q = [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]
            if all(k in idx for k in q):
                pts_ = [verts[idx[k]] for k in q]
                if max((pts_[a] - pts_[b]).length for a in range(4) for b in range(a)) < 0.03:
                    faces.append(tuple(idx[k] for k in q))
    me = mesh_from("ts_tank", verts, faces, uvs=uvs)
    o = new_object("ts_tank", me)
    fix_winding(o, lambda c: c + Vector((0, 0.05, 0)))
    # the binding: a small rolled cord along the scoop
    path = []
    for xx in np.linspace(-0.105, 0.105, 43):
        zc = z_tank_top + 0.036 * (abs(xx) / 0.09) ** 2
        hit = body_bvh.ray_cast(Vector((xx, -0.5, zc)), Vector((0, 1, 0)), 1.0)
        if hit[0] is not None:
            n = hit[1] if hit[1].y < 0 else -hit[1]
            path.append((hit[0] + n * 0.0042, n))
    bv, bf, bu = [], [], []
    R, S = 0.0021, 6
    for k, (p, n) in enumerate(path):
        t = (path[min(k + 1, len(path) - 1)][0] - path[max(k - 1, 0)][0]).normalized()
        b = t.cross(n).normalized()
        for s in range(S):
            a = 2 * math.pi * s / S
            bv.append(p + (n * math.cos(a) + b * math.sin(a)) * R)
            bu.append((s / S, k * 0.25))
        if k:
            for s in range(S):
                a0, a1 = (k - 1) * S + s, (k - 1) * S + (s + 1) % S
                bf.append((a0, a1, a1 + S, a0 + S))
    bme = mesh_from("ts_tank_binding", bv, bf, uvs=bu)
    bo = new_object("ts_tank_binding", bme)
    return o, bo


tank_o, tank_bind = tank_mesh()
activate(tank_bind)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.object.mode_set(mode='OBJECT')
for o in (slider,):
    activate(o)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode='OBJECT')

# ---- skin weights for everything new -------------------------------------------------------------------
for o in bands + pipes + [zipper, slider, tank_o, tank_bind]:
    add_weights_from_body(o)


def off_the_head(o, keep_neck):
    """A collar does not turn with the head. Weights from the nearest skin gave the collar's top
    the neck's, and some of the head's, so the idle - which looks round 60 degrees each way -
    wrung it into shards against the jacket it stands on. The head's share and most of the
    neck's go to the top of the spine instead."""
    chest = o.vertex_groups[P + "Spine2"]
    neck = o.vertex_groups.get(P + "Neck")
    head = o.vertex_groups.get(P + "Head")
    moved = 0
    for v in o.data.vertices:
        wn = wh = 0.0
        for g in v.groups:
            if neck is not None and g.group == neck.index:
                wn = g.weight
            if head is not None and g.group == head.index:
                wh = g.weight
        move = wn * (1.0 - keep_neck) + wh
        if move <= 1e-4:
            continue
        if neck is not None and wn > 0:
            neck.add([v.index], wn * keep_neck, 'REPLACE')
        if head is not None and wh > 0:
            head.remove([v.index])
        chest.add([v.index], move, 'ADD')
        moved += 1
    return moved


def smooth_weights(o, iters=3):
    """Blur every weight over the mesh's own edges: weights taken from different skin faces
    either side of a 2 mm edge put the tank's binding and the collar's lip in two places at once
    (edges nine times their length in the idle)."""
    bmx = bmesh.new()
    bmx.from_mesh(o.data)
    dl = bmx.verts.layers.deform.active
    if dl is None:
        bmx.free()
        return
    bmx.verts.ensure_lookup_table()
    gids = sorted({g for v in bmx.verts for g in v[dl].keys()})
    W = np.array([[v[dl].get(g, 0.0) for g in gids] for v in bmx.verts])
    nb = [[e.other_vert(v).index for e in v.link_edges] for v in bmx.verts]
    for _ in range(iters):
        W = np.array([0.5 * W[i] + 0.5 * W[n].mean(0) if n else W[i] for i, n in enumerate(nb)])
    W /= np.maximum(W.sum(1, keepdims=True), 1e-6)
    for i, v in enumerate(bmx.verts):
        for k, g in enumerate(gids):
            if W[i, k] > 1e-4:
                v[dl][g] = float(W[i, k])
            elif g in v[dl]:
                del v[dl][g]
    bmx.to_mesh(o.data)
    bmx.free()


collar_o = [b for b in bands if "ts_collar" in b.name or "ts_cuff_v" in b.name]
print("TS weights off the head:", {o.name: off_the_head(o, 0.2) for o in collar_o + [tank_o, tank_bind]},
      "garment", off_the_head(garment, 0.35))
for o in collar_o + [tank_o, tank_bind, zipper]:
    smooth_weights(o)

# ---- hide the body under the garments, one ring inside every edge ---------------------------------------
covered = (cover == "jacket") | (cover == "pants")
vcount = np.zeros(NV)
vcov = np.zeros(NV)
for i, f in enumerate(F):
    for vi in f:
        vcount[vi] += 1
        vcov[vi] += covered[i]
vert_cover = (vcount > 0) & (vcov == vcount)
g = body.vertex_groups.new(name="Delete.tracksuit")
g.add([int(i) for i in np.where(vert_cover)[0]], 1.0, 'REPLACE')
mm = body.modifiers.new("Delete.tracksuit", 'MASK')
mm.vertex_group = "Delete.tracksuit"
mm.invert_vertex_group = True

# ---- cleanup + save ------------------------------------------------------------------------------------
bpy.data.objects.remove(body_src, do_unlink=True)
for o in [garment] + bands + pipes + [zipper, slider, tank_o, tank_bind]:
    o.modifiers.new("Armature", 'ARMATURE').object = arm
json.dump(LM, open(common.work("ts_landmarks.json"), "w"), indent=1)
tris = {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in bpy.data.objects if o.name.startswith("hero.ts") or o.name == "hero.tracksuit"}
print("TS tris", tris, "total", sum(tris.values()))
bpy.ops.wm.save_as_mainfile(filepath=common.work("hero_ts.blend"))
