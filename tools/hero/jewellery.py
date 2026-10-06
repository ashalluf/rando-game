# Step: the gold. A rope chain round the neck, a watch on the left wrist, a signet ring on the
# right little finger - all real geometry, because gold is judged by where its highlights fall.
#
#  - rope chain: three helical strands twisted round the path the tracksuit step laid on the
#    skin (ts_landmarks.json), each strand beaded once per link so the twist breaks the light into
#    a row of sparks the way a real rope chain does. Only the part that shows in the V is twisted;
#    the length under the collar and jacket is a plain tube.
#  - watch: a lathed case (caseback, flank, fluted bezel, domed crystal), lugs, a knurled crown at
#    three o'clock, raised baton indices and two hands over a sunburst dial, and a three-piece
#    link bracelet round the wrist. No maker's name anywhere.
#  - signet ring: a bevelled band with a flat table on the back of the finger.
# Reads work/hero_ts.blend, writes work/hero_jw.blend.
import json
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

bpy.ops.wm.open_mainfile(filepath=common.work("hero_ts.blend"))
scene = bpy.context.scene
arm = bpy.data.objects["hero"]
body = bpy.data.objects["hero.body"]
LM = json.load(open(common.work("ts_landmarks.json")))
P = "mixamorig:"
UVN = body.data.uv_layers.active.name


def H(n):
    return arm.data.bones[P + n].head_local.copy()


def activate(o):
    for x in bpy.context.selected_objects:
        x.select_set(False)
    bpy.context.view_layer.objects.active = o
    o.select_set(True)


saved = [(m, m.show_viewport) for m in body.modifiers]
for m, _ in saved:
    m.show_viewport = False
dg = bpy.context.evaluated_depsgraph_get()
src_me = bpy.data.meshes.new_from_object(body.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
for m, s in saved:
    m.show_viewport = s
body_src = bpy.data.objects.new("body_src_jw", src_me)
scene.collection.objects.link(body_src)
for g in body.vertex_groups:
    body_src.vertex_groups.new(name=g.name)
V = [v.co.copy() for v in src_me.vertices]
_bg = body.vertex_groups["body"].index
_is_body = [any(g.group == _bg and g.weight > 0.5 for g in v.groups) for v in src_me.vertices]
# skin only: the MPFB base mesh also carries its helper geometry (tights, skirt, hair helpers)
body_bvh = BVHTree.FromPolygons([tuple(v) for v in V], [tuple(p.vertices) for p in src_me.polygons if all(_is_body[i] for i in p.vertices)])


def skin_radius(c, d, extra, reach=0.06):  # short: the thigh hangs a hand's width from the wrist
    hit = body_bvh.ray_cast(c + d * reach, -d, reach)
    if hit[0] is None:
        return 0.05 + extra
    return (hit[0] - c).length + extra


def new_object(name, me):
    o = bpy.data.objects.new("hero." + name, me)
    scene.collection.objects.link(o)
    o.parent = arm
    return o


def finish(o, smooth=True):
    me = o.data
    if not me.uv_layers:
        me.uv_layers.new(name=UVN)
    for p in me.polygons:
        p.use_smooth = smooth
    activate(o)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    return o


def weights_from_body(o):
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


def rigid_weights(o, groups):
    for g in body.vertex_groups:
        if g.name not in o.vertex_groups:
            o.vertex_groups.new(name=g.name)
    idx = list(range(len(o.data.vertices)))
    for n, w in groups.items():
        o.vertex_groups[n].add(idx, w, 'REPLACE')


def avg_weights_near(p, radius):
    acc = {}
    for vi, co in enumerate(V):
        if (co - p).length < radius:
            for g in src_me.vertices[vi].groups:
                n = body.vertex_groups[g.group].name
                if n.startswith(P):
                    acc[n] = acc.get(n, 0.0) + g.weight
    tot = sum(acc.values()) or 1.0
    return {n: w / tot for n, w in acc.items() if w / tot > 0.02}


# ---- rope chain ---------------------------------------------------------------------------------
path = [Vector(p) for p in LM["chain"]]
CH_R = LM["chain_radius"]
NECK = H("Neck")
# resample the closed loop evenly
seg_len = [(path[(i + 1) % len(path)] - path[i]).length for i in range(len(path))]
total = sum(seg_len)


def at(s):
    s %= total
    acc = 0.0
    for i, L in enumerate(seg_len):
        if s <= acc + L:
            return path[i].lerp(path[(i + 1) % len(path)], (s - acc) / L)
        acc += L
    return path[0]


PITCH = 0.0068      # one full twist of the rope
STEPS_TWIST = 8     # samples per twist on the visible front
cy = NECK.y + 0.005
# The chain shows in the V between these azimuths (0 = front): twisted there, plain under cloth.
SHOW = math.radians(46)


def azimuth(p):
    return math.atan2(p.x, -(p.y - cy))


n_fine = int(total / PITCH * STEPS_TWIST)
samples = [at(total * k / n_fine) for k in range(n_fine)]
tang = [(samples[(k + 1) % n_fine] - samples[k - 1]).normalized() for k in range(n_fine)]
show = [abs(azimuth(p)) < SHOW for p in samples]
# Walk the loop from a point at the back (hidden), so the visible run never crosses the seam
# where the transported frames close up with a twist.
k0 = max(range(n_fine), key=lambda i: abs(azimuth(samples[i])))
order = [(k0 + i) % n_fine for i in range(n_fine)]
frames = [None] * n_fine
n = samples[k0] - Vector((0, cy, samples[k0].z))
frames[k0] = (n - tang[k0] * n.dot(tang[k0])).normalized()
for a_, b_ in zip(order, order[1:]):
    n = frames[a_] - tang[b_] * frames[a_].dot(tang[b_])
    frames[b_] = n.normalized()
bm = bmesh.new()
STRANDS, SIDES = 3, 4
R_H, R_S = CH_R * 0.46, CH_R * 0.50
runs = []
cur = []
for k in order:
    if show[k]:
        cur.append(k)
    elif cur:
        runs.append(cur)
        cur = []
if cur:
    runs.append(cur)
fine = max(runs, key=len)
pad = STEPS_TWIST * 2  # start the twist a little under the cloth on both sides
fine = [(fine[0] - i) % n_fine for i in range(pad, 0, -1)] + fine + [(fine[-1] + i) % n_fine for i in range(1, pad + 1)]
fine_set = set(fine)
arc_s = {k: i * total / n_fine for i, k in enumerate(fine)}
for st in range(STRANDS):
    centres, radii = [], []
    for k in fine:
        s_ = arc_s[k]
        ph = 2 * math.pi * (s_ / PITCH + st / STRANDS)
        n = frames[k]
        b = tang[k].cross(n)
        centres.append(samples[k] + (n * math.cos(ph) + b * math.sin(ph)) * R_H)
        # beaded: each link swells once per third of a twist
        radii.append(R_S * (1.0 + 0.16 * math.cos(2 * math.pi * s_ / (PITCH / STRANDS))))
    rings = []
    for i, c in enumerate(centres):
        # the strand's cross-section is square to its own helix, not to the chain's path
        th = (centres[min(i + 1, len(centres) - 1)] - centres[max(i - 1, 0)]).normalized()
        k = fine[i]
        radial = c - samples[k]
        u1 = (radial - th * radial.dot(th)).normalized()
        u2 = th.cross(u1)
        rings.append([bm.verts.new(c + (u1 * math.cos(2 * math.pi * j / SIDES) + u2 * math.sin(2 * math.pi * j / SIDES)) * radii[i]) for j in range(SIDES)])
    for i in range(len(rings) - 1):
        for j in range(SIDES):
            j2 = (j + 1) % SIDES
            bm.faces.new((rings[i][j], rings[i][j2], rings[i + 1][j2], rings[i + 1][j]))
    for ring in (rings[0], rings[-1]):
        bm.faces.new(ring if ring is rings[-1] else list(reversed(ring)))
# the rest of the loop: a plain tube under the collar, overlapping the twisted ends
pos = {k: i for i, k in enumerate(order)}
coarse = order[pos[fine[-pad]]:] + order[:pos[fine[pad - 1]] + 1]  # round the back, overlapping both ends
coarse_keep = coarse[::3] + ([coarse[-1]] if (len(coarse) - 1) % 3 else [])
rings = []
for k in coarse_keep:
    n = frames[k]
    b = tang[k].cross(n)
    rings.append([bm.verts.new(samples[k] + (n * math.cos(2 * math.pi * j / 6) + b * math.sin(2 * math.pi * j / 6)) * CH_R * 0.9) for j in range(6)])
for i in range(len(rings) - 1):
    for j in range(6):
        bm.faces.new((rings[i][j], rings[i][(j + 1) % 6], rings[i + 1][(j + 1) % 6], rings[i + 1][j]))
cme = bpy.data.meshes.new("ts_chain")
bm.to_mesh(cme)
bm.free()
chain_o = finish(new_object("ts_chain", cme))
weights_from_body(chain_o)
print("JW chain %d tris (%d twisted samples of %d)" % (sum(len(p.vertices) - 2 for p in cme.polygons), len(fine), n_fine))

# ---- watch -----------------------------------------------------------------------------------------
LEL, LWR = H("LeftForeArm"), H("LeftHand")
fore_ax = (LWR - LEL).normalized()
wpos = LWR - fore_ax * 0.035
d_mid = (H("LeftHandMiddle2") - H("LeftHandMiddle1")).normalized()
s_fing = (H("LeftHandPinky1") - H("LeftHandIndex1")).normalized()
palm = s_fing.cross(d_mid).normalized()
dors = -palm
dors = (dors - fore_ax * dors.dot(fore_ax)).normalized()
lat = fore_ax.cross(dors).normalized()
top_r = skin_radius(wpos, dors, 0.0)
CASE_R = 0.0200
case_base = wpos + dors * (top_r + 0.0012)
# frame: z out of the dial (dors), x toward 12 o'clock (along the band), and so - seen from the
# front, 12 up - three o'clock is -y, toward the hand, where the crown goes
M = Matrix((-lat, -fore_ax, dors)).transposed().to_4x4()
M.translation = case_base


def lathe(bm_, profile, seg, flutes=0, flute_amp=0.0, flute_range=(1e9, -1e9)):
    """Revolve (radius, height) points round the case axis; returns the rings."""
    rings = []
    for (r, h) in profile:
        ring = []
        for k in range(seg):
            a = 2 * math.pi * k / seg
            rr = r
            if flutes and flute_range[0] <= h <= flute_range[1]:
                rr = r - flute_amp * (0.5 + 0.5 * math.cos(a * flutes))
            ring.append(bm_.verts.new(M @ Vector((rr * math.cos(a), rr * math.sin(a), h))))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(seg):
            k2 = (k + 1) % seg
            bm_.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
    return rings


bm = bmesh.new()
case = lathe(bm, [(0.0, -0.0004), (0.0150, 0.0), (0.0172, 0.0012), (CASE_R, 0.0034), (CASE_R + 0.0003, 0.0060),
                  (CASE_R, 0.0078)], 48)
bm.faces.new(list(reversed(case[0])))
bez = lathe(bm, [(CASE_R - 0.0002, 0.0078), (CASE_R - 0.0004, 0.0092), (0.0185, 0.0104), (0.0172, 0.0106), (0.0168, 0.0098)],
            120, flutes=60, flute_amp=0.0007, flute_range=(0.0080, 0.0105))
# lugs, two a side along the band
for sx in (-1, 1):
    for sy in (-1, 1):
        lb = bmesh.ops.create_cube(bm, size=1.0)
        for v in lb["verts"]:
            v.co = M @ Vector((sx * (CASE_R + 0.0025) + v.co.x * 0.0070, sy * 0.0098 + v.co.y * 0.0030, 0.0036 + v.co.z * 0.0046))
# crown at three o'clock
cr = bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=0.0026, radius2=0.0026, depth=0.0036)
for v in cr["verts"]:
    k = Vector((v.co.x, v.co.y, v.co.z))
    ang = math.atan2(k.y, k.x)
    knurl = 1.0 + 0.06 * math.cos(ang * 16) if abs(k.z) < 0.0017 else 1.0
    v.co = M @ Vector((k.x * knurl, -(CASE_R + 0.0017 + k.z), 0.0048 + k.y * knurl))
cme = bpy.data.meshes.new("ts_watchcase")
bm.to_mesh(cme)
bm.free()
case_o = finish(new_object("ts_watchcase", cme))
# dial: a disc under the crystal, its own textured material
bm = bmesh.new()
DIAL_R, DIAL_H = 0.0168, 0.0086
centre = bm.verts.new(M @ Vector((0, 0, DIAL_H)))
ring = [bm.verts.new(M @ Vector((DIAL_R * math.cos(2 * math.pi * k / 48), DIAL_R * math.sin(2 * math.pi * k / 48), DIAL_H))) for k in range(48)]
for k in range(48):
    bm.faces.new((centre, ring[k], ring[(k + 1) % 48]))
dme = bpy.data.meshes.new("ts_dial")
bm.to_mesh(dme)
bm.free()
uvl = dme.uv_layers.new(name=UVN)
inv = M.inverted()
for poly in dme.polygons:
    for li, vi in zip(poly.loop_indices, poly.vertices):
        q = inv @ dme.vertices[vi].co
        # u to 3 o'clock, v to 12 o'clock (the texture is drawn with 12 at the top)
        uvl.data[li].uv = (0.5 - q.y / (2 * DIAL_R), 0.5 + q.x / (2 * DIAL_R))
dial_o = finish(new_object("ts_dial", dme), smooth=False)
# raised indices and the hands (gold), over the dial
bm = bmesh.new()
for h_ in range(12):
    a = h_ / 12 * 2 * math.pi
    long_ = h_ % 3 == 0
    L0, L1 = (0.0108, 0.0150) if long_ else (0.0120, 0.0150)
    w = 0.0013 if long_ else 0.0008
    c = (L0 + L1) / 2
    ib = bmesh.ops.create_cube(bm, size=1.0)
    rot = Matrix.Rotation(-a, 4, 'Z')
    for v in ib["verts"]:
        q = Vector((c + v.co.x * (L1 - L0), v.co.y * w, DIAL_H + 0.0003 + v.co.z * 0.0005))
        v.co = M @ (rot @ q)
for a_deg, L_, w_, hgt in ((-300.0, 0.0105, 0.0016, 0.0009), (-60.0, 0.0150, 0.0011, 0.0012)):  # ten past ten
    a = math.radians(a_deg)
    hb = bmesh.ops.create_cube(bm, size=1.0)
    rot = Matrix.Rotation(a, 4, 'Z')
    for v in hb["verts"]:
        taper = 1.0 - 0.55 * (v.co.x + 0.5)
        q = Vector((L_ * (v.co.x + 0.5) - 0.002, v.co.y * w_ * taper, DIAL_H + hgt + v.co.z * 0.0004))
        v.co = M @ (rot @ q)
pin = bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.0011, radius2=0.0011, depth=0.0008)
for v in pin["verts"]:
    v.co = M @ Vector((v.co.x, v.co.y, DIAL_H + 0.0013 + v.co.z))
ime = bpy.data.meshes.new("ts_watchhands")
bm.to_mesh(ime)
bm.free()
hands_o = finish(new_object("ts_watchhands", ime), smooth=False)
# crystal: a shallow dome, glass
bm = bmesh.new()
cr_rings = []
for i, (r, h) in enumerate([(0.0, 0.0112), (0.006, 0.01115), (0.011, 0.0110), (0.0150, 0.01075), (0.0170, 0.0104)]):
    if r == 0.0:
        top = bm.verts.new(M @ Vector((0, 0, h)))
        continue
    cr_rings.append([bm.verts.new(M @ Vector((r * math.cos(2 * math.pi * k / 48), r * math.sin(2 * math.pi * k / 48), h))) for k in range(48)])
for k in range(48):
    bm.faces.new((top, cr_rings[0][k], cr_rings[0][(k + 1) % 48]))
for i in range(len(cr_rings) - 1):
    for k in range(48):
        k2 = (k + 1) % 48
        bm.faces.new((cr_rings[i][k], cr_rings[i + 1][k], cr_rings[i + 1][k2], cr_rings[i][k2]))
gme = bpy.data.meshes.new("ts_crystal")
bm.to_mesh(gme)
bm.free()
crystal_o = finish(new_object("ts_crystal", gme))


# bracelet: rows of three bevelled links round the wrist, from lug to lug under the wrist
def wrist_point(ang):
    d = (dors * math.cos(ang) + lat * math.sin(ang)).normalized()
    return wpos + d * (skin_radius(wpos, d, 0.0) + 0.0026), d


bm = bmesh.new()
a_start = math.atan2(CASE_R + 0.006, top_r + 0.004)
rows_n = 23
for i in range(rows_n):
    ang = a_start + (2 * math.pi - 2 * a_start) * (i + 0.5) / rows_n
    p, d = wrist_point(ang)
    p2, _ = wrist_point(ang + 0.01)
    t = (p2 - p).normalized()
    for (off, width, hgt) in ((-0.0068, 0.0060, 0.0026), (0.0, 0.0068, 0.0030), (0.0068, 0.0060, 0.0026)):
        lk = bmesh.ops.create_cube(bm, size=1.0)
        pitch = (2 * math.pi - 2 * a_start) / rows_n * (skin_radius(wpos, d, 0.0) + 0.0026)
        for v in lk["verts"]:
            v.co = p + t * (v.co.x * pitch * 0.88) + fore_ax * (off + v.co.y * width) + d * (v.co.z * hgt)
        bmesh.ops.bevel(bm, geom=list({e for v in lk["verts"] for e in v.link_edges}), offset=0.0007, segments=1, affect='EDGES', profile=0.5)
lme = bpy.data.meshes.new("ts_watch")
bm.to_mesh(lme)
bm.free()
band_o = finish(new_object("ts_watch", lme))
ww = avg_weights_near(wpos, 0.03)
for o in (case_o, dial_o, hands_o, crystal_o):
    rigid_weights(o, ww)
weights_from_body(band_o)
print("JW watch weights", {k.replace(P, ""): round(v, 2) for k, v in ww.items()},
      "tris", {o.name: len(o.data.polygons) for o in (case_o, dial_o, hands_o, crystal_o, band_o)})

# ---- signet ring, right little finger -----------------------------------------------------------------
p1 = arm.data.bones[P + "RightHandPinky1"]
pa, pb = p1.head_local, p1.tail_local
pax = (pb - pa).normalized()
rc = pa + (pb - pa) * 0.42
ref = Vector((0, 0, 1))
ref = (ref - pax * ref.dot(pax)).normalized()
ref2 = pax.cross(ref)
rads = [skin_radius(rc, ref * math.cos(a) + ref2 * math.sin(a), 0.0, 0.016) for a in np.linspace(0, 2 * math.pi, 12, endpoint=False)]
rads = [r_ for r_ in rads if r_ < 0.014] or [0.008]
R0 = float(np.mean(rads)) + 0.0009
d_mid_r = (H("RightHandMiddle2") - H("RightHandMiddle1")).normalized()
s_fing_r = (H("RightHandPinky1") - H("RightHandIndex1")).normalized()
palm_r = (s_fing_r.cross(d_mid_r) * -1.0).normalized()
back = -palm_r
back = (back - pax * back.dot(pax)).normalized()
side_ax = pax.cross(back)
bm = bmesh.new()
RS, TSG = 28, 8
rv = []
for i in range(RS):
    a = 2 * math.pi * i / RS
    dirv = back * math.cos(a) + side_ax * math.sin(a)
    table = max(0.0, math.cos(a)) ** 6  # the band thickens into the signet's shoulders
    for j in range(TSG):
        b = 2 * math.pi * j / TSG
        thick = 0.0012 + 0.0016 * table
        width = 0.0021 + 0.0022 * table
        rv.append(bm.verts.new(rc + dirv * (R0 + thick + thick * math.cos(b)) + pax * (width * math.sin(b))))
for i in range(RS):
    for j in range(TSG):
        bm.faces.new((rv[i * TSG + j], rv[((i + 1) % RS) * TSG + j], rv[((i + 1) % RS) * TSG + (j + 1) % TSG], rv[i * TSG + (j + 1) % TSG]))
sg = bmesh.ops.create_cube(bm, size=1.0)
for v in sg["verts"]:
    v.co = rc + back * (R0 + 0.0030 + v.co.z * 0.0022) + pax * (v.co.x * 0.0088) + side_ax * (v.co.y * 0.0080)
bmesh.ops.bevel(bm, geom=list({e for v in sg["verts"] for e in v.link_edges}), offset=0.0008, segments=2, affect='EDGES', profile=0.5)
rme = bpy.data.meshes.new("ts_ring")
bm.to_mesh(rme)
bm.free()
ring_o = finish(new_object("ts_ring", rme))
rigid_weights(ring_o, {P + "RightHandPinky1": 1.0})

bpy.data.objects.remove(body_src, do_unlink=True)
for o in (chain_o, case_o, dial_o, hands_o, crystal_o, band_o, ring_o):
    o.modifiers.new("Armature", 'ARMATURE').object = arm
bpy.ops.wm.save_as_mainfile(filepath=common.work("hero_jw.blend"))
