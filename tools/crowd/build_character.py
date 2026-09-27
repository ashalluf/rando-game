# Crowd step 1 (Blender): one character of crowd_config.json as a game rig, ready for its textures.
#
#   blender -b --python tools/crowd/build_character.py -- crowd_a
#
#  - the MPFB human (phenotype, shape targets, skin, eyes, brows, lashes) dressed in CC0 MakeHuman
#    clothes, shoes and hair, on MPFB's "mixamo" skeleton renamed to the game's rig names
#  - bound like the hero (tools/hero/build_body.py): upper arms lowered and elbows opened from
#    MakeHuman's A-pose, so the hanging arms of idle / walk / run skin cleanly - plus the fingers
#    curled into a relaxed hand, baked into the mesh. The finger bones are then folded into the
#    hands: 24 bones, the crowd's contract (Pedestrian, Ragdoll, the police and the camp figures)
#  - every masked and hidden bit of skin deleted (MakeHuman's own delete groups, then whatever a
#    garment covers along the skin's normal, one ring kept inside every garment edge)
#  - cut to a triangle budget per part (the head and hands keep the most), under 20k in all
#  - ONE body mesh (skin, eyes, clothes, shoes) on one 2K atlas and ONE hair mesh (hair, brows,
#    lashes) on one 1K alpha atlas: every source texture's used islands are cropped and packed
#    (atlas.json, which crowd_atlas.py composes). The vertex colour says what each vertex is -
#    R top garment, G bottom garment, B hair (the scalp under the hair), A skin - so the game's
#    character shader recolours a look exactly, never by guessing from the texture
#  - soles on y 0, centimetres under a 0.01 armature, facing +Z in glTF (the crowd contract)
# Writes WORK/<name>/rigged.blend and WORK/<name>/atlas.json.
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import crowd_common as C  # noqa: E402
import fixarms  # noqa: E402  (tools/hero, on the path through crowd_common)

NAME = C.blender_args()[0]
CFG = C.character(NAME)
BUDGET = CFG["budget"]
ATL = CFG["atlas"]

bpy.ops.wm.read_factory_settings(use_empty=True)
import addon_utils  # noqa: E402

addon_utils.enable("bl_ext.user_default.mpfb", default_set=True)
from bl_ext.user_default.mpfb.services.humanservice import HumanService  # noqa: E402

# ---- the face: MPFB's own face targets, rolled per character ----------------------------------------
# Every MakeHuman head starts from the same average face; with only the phenotype sliders set, a
# crowd of them read as siblings. Each pair is one signed modifier (the first name is its negative
# side); "{s}" pairs are set the same on the left and the right. The ones that pushed a face into
# caricature at any size (eye spacing, head height, brow angle) are left out. `face_var` scales the roll,
# `face_seed` picks another face, and anything in "targets" overrides a rolled value.
FACE_PAIRS = [
    ("nose-scale-horiz-decr", "nose-scale-horiz-incr"), ("nose-scale-vert-decr", "nose-scale-vert-incr"),
    ("nose-scale-depth-decr", "nose-scale-depth-incr"), ("nose-hump-decr", "nose-hump-incr"),
    ("nose-point-width-decr", "nose-point-width-incr"), ("nose-nostrils-width-decr", "nose-nostrils-width-incr"),
    ("nose-trans-down", "nose-trans-up"), ("nose-volume-decr", "nose-volume-incr"), ("nose-point-down", "nose-point-up"),
    ("chin-width-decr", "chin-width-incr"), ("chin-prominent-decr", "chin-prominent-incr"),
    ("chin-height-decr", "chin-height-incr"), ("chin-bones-decr", "chin-bones-incr"), ("chin-jaw-drop-decr", "chin-jaw-drop-incr"),
    ("head-scale-horiz-decr", "head-scale-horiz-incr"),
    ("head-fat-decr", "head-fat-incr"), ("head-oval", "head-square"),
    ("{s}-cheek-bones-decr", "{s}-cheek-bones-incr"), ("{s}-cheek-volume-decr", "{s}-cheek-volume-incr"),
    ("{s}-cheek-inner-decr", "{s}-cheek-inner-incr"),
    ("{s}-eye-scale-decr", "{s}-eye-scale-incr"), ("{s}-eye-height2-decr", "{s}-eye-height2-incr"),
    ("{s}-eye-bag-decr", "{s}-eye-bag-incr"),
    ("{s}-eye-corner1-down", "{s}-eye-corner1-up"), ("{s}-eye-eyefold-down", "{s}-eye-eyefold-up"),
    ("mouth-scale-horiz-decr", "mouth-scale-horiz-incr"), ("mouth-lowerlip-volume-decr", "mouth-lowerlip-volume-incr"),
    ("mouth-upperlip-volume-decr", "mouth-upperlip-volume-incr"), ("mouth-angles-down", "mouth-angles-up"),
    ("mouth-trans-down", "mouth-trans-up"), ("mouth-cupidsbow-decr", "mouth-cupidsbow-incr"),
    ("{s}-ear-scale-decr", "{s}-ear-scale-incr"), ("{s}-ear-flap-decr", "{s}-ear-flap-incr"),
    ("{s}-ear-lobe-decr", "{s}-ear-lobe-incr"),
    ("eyebrows-trans-down", "eyebrows-trans-up"), ("forehead-trans-backward", "forehead-trans-forward"),
]


def face_targets():
    import random
    import bl_ext.user_default.mpfb as mpfb_mod
    tdir = os.path.join(os.path.dirname(mpfb_mod.__file__), "data", "targets")
    have = set()
    for root, _dirs, files in os.walk(tdir):
        have.update(f[:-len(".target.gz")] for f in files if f.endswith(".target.gz"))
    rng = random.Random(str(CFG.get("face_seed", NAME)))
    var = CFG.get("face_var", 0.35)
    out = {}
    for lo, hi in FACE_PAIRS:
        v = rng.uniform(-1.0, 1.0) * var
        for sd in (("l", "r") if "{s}" in lo else ("",)):
            name = (hi if v > 0 else lo).format(s=sd)
            if name in have:
                out[name] = abs(v)
            else:
                print("CROWD no face target", name)
    for t, v in CFG.get("targets", []):
        out[t] = v
    return out


info = HumanService._create_default_human_info_dict()
ph = {"gender": 0.5, "age": 0.5, "muscle": 0.5, "weight": 0.5, "proportions": 0.5, "height": 0.5,
      "cupsize": 0.5, "firmness": 0.5}
ph.update(CFG["phenotype"])
info.update({
    "name": NAME, "phenotype": ph, "rig": CFG["rig"], "eyes": CFG["eyes"],
    "eyebrows": CFG.get("eyebrows", ""), "eyelashes": CFG.get("eyelashes", ""), "hair": CFG.get("hair", ""),
    "teeth": "", "tongue": "", "clothes": CFG["clothes"], "skin_mhmat": CFG["skin"][0] + ".mhmat",
    "skin_material_type": CFG["skin_material_type"], "eyes_material_type": CFG["eyes_material_type"],
    "targets": [{"target": t, "value": v} for t, v in face_targets().items()],
})
settings = HumanService.get_default_deserialization_settings()
settings["subdiv_levels"] = 0
settings["override_skin_model"] = "MAKESKIN"
body = HumanService.deserialize_from_dict(info, settings)
arm = body.parent
scene = bpy.context.scene


def activate(o):
    for x in bpy.context.selected_objects:
        x.select_set(False)
    bpy.context.view_layer.objects.active = o
    o.select_set(True)


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


meshes = [o for o in bpy.data.objects if o.type == 'MESH' and o.parent == arm]

# ---- the game's rig names -------------------------------------------------------------------------
RENAME = {"Spine": "Spine02", "Spine1": "Spine01", "Spine2": "Spine", "Neck": "neck"}
for b in arm.data.bones:
    short = b.name.replace("mixamorig:", "")
    b.name = RENAME.get(short, short)
for o in meshes:
    for g in o.vertex_groups:
        if g.name.startswith("mixamorig:"):
            short = g.name.replace("mixamorig:", "")
            g.name = RENAME.get(short, short)

# ---- bind pose: arms lowered, elbows opened, fingers relaxed ----------------------------------------
for o in meshes:
    activate(o)
    if o.data.shape_keys:
        bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
RP = CFG.get("rest_pose", {})
# A hand at rest: the MakeHuman rest hand is flat with the fingers fanned wide, so the crowd's
# fingers close up more than the hero's clip keys do (these are baked in; there are no finger
# bones left to key).
fixarms.FINGER_CURL.update({"Index": (26, 36, 20), "Middle": (30, 40, 22), "Ring": (34, 44, 24), "Pinky": (38, 46, 26)})
fixarms.FINGER_TOGETHER.update({"Index": 10, "Ring": 7, "Pinky": 15})
fixarms.THUMB_CURL = (14, 20, 18)
curl = fixarms.finger_curl(arm)
activate(arm)
bpy.ops.object.mode_set(mode='POSE')
for side, sg in (("Left", 1.0), ("Right", -1.0)):
    pb = arm.pose.bones[side + "Arm"]
    head = pb.matrix.translation.copy()
    pb.matrix = Matrix.Translation(head) @ Matrix.Rotation(math.radians(RP.get("arm_down_deg", 0.0)) * sg, 4, 'Y') @ Matrix.Translation(-head) @ pb.matrix
    bpy.context.view_layer.update()
    fa = arm.pose.bones[side + "ForeArm"]
    up = arm.pose.bones[side + "Arm"]
    u = (fa.head - up.head).normalized()
    f = (fa.tail - fa.head).normalized()
    axis = f.cross(u)
    if axis.length > 1e-4:
        head = fa.matrix.translation.copy()
        fa.matrix = Matrix.Translation(head) @ Matrix.Rotation(math.radians(RP.get("elbow_open_deg", 0.0)), 4, axis.normalized()) @ Matrix.Translation(-head) @ fa.matrix
        bpy.context.view_layer.update()
for n, q in curl.items():
    pb = arm.pose.bones[n]
    pb.rotation_mode = 'QUATERNION'
    pb.rotation_quaternion = q
bpy.context.view_layer.update()
bpy.ops.object.mode_set(mode='OBJECT')
for o in meshes:
    for m in [m for m in o.modifiers if m.type == 'ARMATURE']:
        activate(o)
        bpy.ops.object.modifier_apply(modifier=m.name)
activate(arm)
bpy.ops.object.mode_set(mode='POSE')
bpy.ops.pose.select_all(action='SELECT')
bpy.ops.pose.armature_apply(selected=False)
bpy.ops.object.mode_set(mode='OBJECT')
# the masks (helpers, what the clothes' own delete groups hide), applied for good
for o in meshes:
    activate(o)
    for m in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)

# ---- fingers folded into the hands ----------------------------------------------------------------
fingers = [b.name for b in arm.data.bones if "Hand" in b.name and b.name not in ("LeftHand", "RightHand")]
for o in meshes:
    hand = {s: o.vertex_groups.get(s + "Hand") for s in ("Left", "Right")}
    fidx = {o.vertex_groups[n].index: n for n in fingers if n in o.vertex_groups}
    if not fidx:
        continue
    for s in ("Left", "Right"):
        if hand[s] is None:
            hand[s] = o.vertex_groups.new(name=s + "Hand")
    for v in o.data.vertices:
        add = {"Left": 0.0, "Right": 0.0}
        for g in v.groups:
            if g.group in fidx:
                add["Left" if fidx[g.group].startswith("Left") else "Right"] += g.weight
        for s, w in add.items():
            if w > 0.0:
                cur = 0.0
                for g in v.groups:
                    if g.group == hand[s].index:
                        cur = g.weight
                hand[s].add([v.index], cur + w, 'REPLACE')
    for gi in sorted(fidx, reverse=True):
        o.vertex_groups.remove(o.vertex_groups[fidx[gi]])
activate(arm)
bpy.ops.object.mode_set(mode='EDIT')
eb = arm.data.edit_bones
for n in fingers:
    eb.remove(eb[n])
head = eb["Head"]
he = eb.new("head_end")
he.head = head.tail.copy()
he.tail = head.tail + Vector((0, 0, 0.08))
he.parent = head
hf = eb.new("headfront")
hf.head = Vector((head.head.x, -0.13, head.head.z))
hf.tail = hf.head + Vector((0, -0.08, 0))
hf.parent = head
bpy.ops.object.mode_set(mode='OBJECT')
print("CROWD bones", len(arm.data.bones))

# ---- what each object is ----------------------------------------------------------------------------
def kind_of(o):
    n = o.name.split(".", 1)[1] if "." in o.name else o.name
    if o == body:
        return "skin", n
    if n in ("low-poly", "high-poly"):
        return "eyes", n
    if n.startswith("eyebrow"):
        return "brows", n
    if n.startswith("eyelash"):
        return "lashes", n
    if CFG.get("hair") and n == CFG["hair"].replace(".mhclo", ""):
        return "hair", n
    if n.startswith("shoes"):
        return "shoes", n
    if n.startswith("fedora"):
        return "hat", n
    return "garment", n


KIND = {o.name: kind_of(o) for o in meshes}
for o in meshes:
    print("CROWD part", o.name, KIND[o.name], "tris", tris(o))


def images_of(o):
    """(diffuse, normal, ao) image paths of the object's MakeHuman material."""
    out = {"diffuse": None, "normal": None, "ao": None}
    for m in o.data.materials:
        if not m or not m.use_nodes:
            continue
        for nd in m.node_tree.nodes:
            if nd.type != 'TEX_IMAGE' or not nd.image:
                continue
            p = bpy.path.abspath(nd.image.filepath)
            b = os.path.basename(p).lower()
            if "normal" in b or "_nrm" in b:
                out["normal"] = out["normal"] or p
            elif "_ao" in b:
                out["ao"] = out["ao"] or p
            else:
                out["diffuse"] = out["diffuse"] or p
    return out


IMAGES = {o.name: images_of(o) for o in meshes}
if CFG.get("eye_color"):
    for o in meshes:
        if KIND[o.name][0] == "eyes":
            IMAGES[o.name]["diffuse"] = os.path.join(C.MPFB_DATA, "eyes", "materials", CFG["eye_color"] + "_eye.png")

# ---- hidden skin: whatever a garment covers along the skin's normal ---------------------------------
dg = bpy.context.evaluated_depsgraph_get()
cover = [o for o in meshes if KIND[o.name][0] in ("garment", "shoes", "hat")]
if cover:
    verts, polys = [], []
    for o in cover:
        base = len(verts)
        verts += [o.matrix_world @ v.co for v in o.data.vertices]
        polys += [tuple(base + i for i in p.vertices) for p in o.data.polygons]
    bvh = BVHTree.FromPolygons(verts, polys)
    reach = CFG.get("cover_reach", 0.07)
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.normal_update()
    bm.verts.ensure_lookup_table()
    covered = [False] * len(bm.verts)
    for v in bm.verts:
        w = body.matrix_world @ v.co
        n = (body.matrix_world.to_3x3() @ v.normal).normalized()
        hit = bvh.ray_cast(w + n * 0.0005, n, reach)
        covered[v.index] = hit[0] is not None
    # keep every face with a visible corner, then one more ring round those
    keep_v = set()
    for f in bm.faces:
        if not all(covered[v.index] for v in f.verts):
            keep_v.update(v.index for v in f.verts)
    ring = set(keep_v)
    for f in bm.faces:
        if any(v.index in keep_v for v in f.verts):
            ring.update(v.index for v in f.verts)
    kill = [f for f in bm.faces if not any(v.index in ring for v in f.verts)]
    before = len(bm.faces)
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bm.to_mesh(body.data)
    bm.free()
    print("CROWD hidden skin removed: %d of %d faces (%d of %d vertices covered)" % (len(kill), before, sum(covered), len(covered)))

# ---- the scalp under the hair (B in the vertex colour) ---------------------------------------------
def dominant_groups(o):
    """Per vertex, the name of its heaviest vertex group among the bones."""
    bones = {b.name for b in arm.data.bones}
    names = {g.index: g.name for g in o.vertex_groups if g.name in bones}
    out = []
    for v in o.data.vertices:
        best, bw = None, -1.0
        for g in v.groups:
            if g.group in names and g.weight > bw:
                best, bw = names[g.group], g.weight
        out.append(best)
    return out


HEAD_BONES = {"Head", "neck", "head_end", "headfront"}
hair_obj = next((o for o in meshes if KIND[o.name][0] == "hair"), None)
scalp = [0.0] * len(body.data.vertices)
if hair_obj is not None:
    hv = [hair_obj.matrix_world @ v.co for v in hair_obj.data.vertices]
    hbvh = BVHTree.FromPolygons(hv, [tuple(p.vertices) for p in hair_obj.data.polygons])
    dom = dominant_groups(body)
    for v in body.data.vertices:
        if dom[v.index] not in HEAD_BONES:
            continue
        w = body.matrix_world @ v.co
        n = (body.matrix_world.to_3x3() @ v.normal).normalized()
        if hbvh.ray_cast(w + n * 0.0005, n, CFG.get("scalp_reach", 0.05))[0] is not None:
            scalp[v.index] = 1.0
elif CFG.get("buzz"):
    # A close crop, painted: everything on the head above a hairline that runs from the forehead
    # down past the temples and over the ears to the nape (heights above the eyes, metres, by the
    # angle round from the front; "hairline" in the config moves the front, for a receding one).
    eyes_o = next(o for o in meshes if KIND[o.name][0] == "eyes")
    ev = [eyes_o.matrix_world @ v.co for v in eyes_o.data.vertices]
    eye = sum(ev, Vector()) / len(ev)
    centre = eye + Vector((0.0, 0.085, 0.0))
    front = CFG.get("hairline", 0.075)
    AZ = [0.0, 50.0, 85.0, 115.0, 150.0, 180.0]
    HL = [front, front - 0.012, 0.03, 0.025, -0.035, -0.06]
    ears = body.vertex_groups.get("ears")
    dom = dominant_groups(body)
    for v in body.data.vertices:
        if dom[v.index] not in HEAD_BONES:
            continue
        if ears is not None and any(g.group == ears.index and g.weight > 0.3 for g in v.groups):
            continue
        w = body.matrix_world @ v.co
        rel = w - centre
        az = math.degrees(math.atan2(abs(rel.x), -rel.y))
        i = next(k for k in range(1, len(AZ)) if az <= AZ[k] or k == len(AZ) - 1)
        t = min(max((az - AZ[i - 1]) / (AZ[i] - AZ[i - 1]), 0.0), 1.0)
        hl = eye.z + HL[i - 1] + (HL[i] - HL[i - 1]) * t
        scalp[v.index] = min(max((w.z - hl + 0.004) / 0.012, 0.0), 1.0)
# soften the hairline over a couple of edge rings
nbr = [[] for _ in body.data.vertices]
for e in body.data.edges:
    a, b = e.vertices
    nbr[a].append(b)
    nbr[b].append(a)
for _ in range(CFG.get("hairline_soften", 2)):
    scalp = [0.5 * s + 0.5 * (sum(scalp[j] for j in nbr[i]) / len(nbr[i]) if nbr[i] else s) for i, s in enumerate(scalp)]
print("CROWD scalp under the hair: %d vertices" % sum(1 for s in scalp if s > 0.5))

# ---- where a beard grows (painted into the atlas by crowd_atlas.py: stubble or a beard) ------------
# In the head's own frame round the eyes, scaled by the eye-to-chin distance: the moustache under
# the nose, the lips left clear, a cheek line from the mouth corners up to the sideburns in front
# of the ears, and under the jaw down the front of the neck. Soft-edged by a few millimetres.
def smooth01(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


beard = [0.0] * len(body.data.vertices)
if CFG.get("stubble", 0.0) > 0.0 or CFG.get("beard", 0.0) > 0.0:
    eyes_o = next(o for o in meshes if KIND[o.name][0] == "eyes")
    ev = [eyes_o.matrix_world @ v.co for v in eyes_o.data.vertices]
    E = sum(ev, Vector()) / len(ev)
    dom = dominant_groups(body)
    pts = [(v.index, body.matrix_world @ v.co) for v in body.data.vertices]
    mid = [w.z for i, w in pts if dom[i] in HEAD_BONES and abs(w.x - E.x) < 0.012 and w.y < E.y + 0.01]
    chin_z = min(mid) if mid else E.z - 0.125
    hs = max((E.z - chin_z) / 0.125, 0.7)
    UP = [(0.0, -0.050), (0.018, -0.054), (0.030, -0.078), (0.046, -0.066), (0.058, -0.040), (0.068, -0.010), (0.085, 0.012)]
    ears = body.vertex_groups.get("ears")
    # MPFB's own "lips" group: kept clear, and where the mouth really is after the face targets
    # moved it (the table above is for the average face, mouth 71 mm under the eyes)
    lips = body.vertex_groups.get("lips")
    lipw = [0.0] * len(body.data.vertices)
    if lips is not None:
        for v in body.data.vertices:
            for g in v.groups:
                if g.group == lips.index:
                    lipw[v.index] = g.weight
    lp = [w for i, w in pts if lipw[i] > 0.5]
    mouth_dz = ((sum(lp, Vector()) / len(lp)).z - E.z) / hs + 0.071 if lp else 0.0
    UP = [(ax_, z_ + (mouth_dz if ax_ < 0.05 else mouth_dz * 0.5)) for ax_, z_ in UP]
    for i, w in pts:
        d = dom[i]
        if d not in HEAD_BONES and d != "neck":
            continue
        v = body.data.vertices[i]
        if ears is not None and any(g.group == ears.index and g.weight > 0.2 for g in v.groups):
            continue
        rel = (w - E) / hs
        ax, z, y = abs(rel.x), rel.z, rel.y
        k = next((j for j in range(1, len(UP)) if ax <= UP[j][0]), len(UP) - 1)
        t = min(max((ax - UP[k - 1][0]) / max(UP[k][0] - UP[k - 1][0], 1e-6), 0.0), 1.0)
        zu = UP[k - 1][1] + (UP[k][1] - UP[k - 1][1]) * t
        wv = 1.0 - smooth01(zu - 0.004, zu + 0.004, z)
        # not behind the sideburns, not low down the neck, not its back
        wv *= 1.0 - smooth01(0.045, 0.06, y)
        wv *= smooth01(-0.215, -0.19, z)
        if d == "neck":
            wv *= 1.0 - smooth01(-0.01, 0.02, y)
        # the lips stay clear
        lx, lz = ax / 0.027, (z + 0.071 - mouth_dz) / 0.0125
        wv *= smooth01(0.85, 1.15, math.sqrt(lx * lx + lz * lz))
        wv *= 1.0 - min(lipw[i] * 1.5, 1.0)
        beard[i] = wv
    print("CROWD beard zone: %d vertices (eye-to-chin %.3f m)" % (sum(1 for b in beard if b > 0.5), E.z - chin_z))

# ---- triangle budgets --------------------------------------------------------------------------------
def decimate_faces(o, pick, ratio):
    if ratio >= 0.999:
        return
    activate(o)
    bpy.ops.object.mode_set(mode='EDIT')
    bmx = bmesh.from_edit_mesh(o.data)
    dl = bmx.verts.layers.deform.active
    for f in bmx.faces:
        f.select = pick(f, dl)
    bmx.select_flush_mode()
    bmesh.update_edit_mesh(o.data)
    bpy.ops.mesh.decimate(ratio=max(ratio, 0.02), use_symmetry=True, symmetry_axis='X')
    bpy.ops.mesh.select_all(action='DESELECT')
    bpy.ops.object.mode_set(mode='OBJECT')


# The scalp weight rides along as a vertex attribute so the decimation interpolates it.
att = body.data.attributes.new("crowd_scalp", 'FLOAT', 'POINT')
att.data.foreach_set("value", scalp)
att = body.data.attributes.new("crowd_beard", 'FLOAT', 'POINT')
att.data.foreach_set("value", beard)

BONE_NAMES = {b.name for b in arm.data.bones}
group_names = {g.index: g.name for g in body.vertex_groups if g.name in BONE_NAMES}
def region_of(f, dl):
    tot = {}
    for v in f.verts:
        for gi, w in v[dl].items():
            n = group_names.get(gi)
            if n:
                tot[n] = tot.get(n, 0.0) + w
    if not tot:
        return "rest"
    head = sum(tot.get(n, 0.0) for n in HEAD_BONES)
    hand = tot.get("LeftHand", 0.0) + tot.get("RightHand", 0.0)
    total = sum(tot.values())
    return "head" if head > 0.5 * total else ("hand" if hand > 0.5 * total else "rest")


activate(body)
bm = bmesh.new()
bm.from_mesh(body.data)
dl = bm.verts.layers.deform.active
counts = {"head": 0, "hand": 0, "rest": 0}
for f in bm.faces:
    counts[region_of(f, dl)] += len(f.verts) - 2
bm.free()
b_skin = BUDGET["skin"]
want = {"hand": min(counts["hand"], 0.16 * b_skin)}
want["head"] = min(counts["head"], 0.56 * b_skin)
want["rest"] = max(b_skin - want["hand"] - want["head"], 0.3 * counts["rest"])
print("CROWD skin tris by region", counts, "->", {k: int(v) for k, v in want.items()})
for reg in ("hand", "rest", "head"):
    if counts[reg] > 0:
        decimate_faces(body, lambda f, dl, r=reg: region_of(f, dl) == r, want[reg] / counts[reg])
for o in meshes:
    k = KIND[o.name][0]
    if k in ("skin", "eyes"):
        continue
    b = BUDGET.get(k)
    if k == "garment":
        b = BUDGET["garment"] / max(1, sum(1 for x in meshes if KIND[x.name][0] == "garment"))
    if b and tris(o) > b:
        decimate_faces(o, lambda f, dl: True, b / tris(o))
for o in meshes:
    print("CROWD budget", o.name, tris(o))
scalp = [0.0] * len(body.data.vertices)
body.data.attributes["crowd_scalp"].data.foreach_get("value", scalp)
beard = [0.0] * len(body.data.vertices)
body.data.attributes["crowd_beard"].data.foreach_get("value", beard)

# ---- UV islands and the atlas plan ---------------------------------------------------------------------
def islands(o):
    """Faces grouped by UV island: two faces join across an edge whose two corners share UVs."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    uv = bm.loops.layers.uv.active
    parent = list(range(len(bm.faces)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    bm.faces.ensure_lookup_table()
    for e in bm.edges:
        if len(e.link_faces) != 2:
            continue
        f0, f1 = e.link_faces
        def uvs(f):
            d = {}
            for l in f.loops:
                d[l.vert.index] = l[uv].uv.copy()
            return d
        a, b = uvs(f0), uvs(f1)
        if all((a[v.index] - b[v.index]).length < 1e-5 for v in e.verts):
            ra, rb = find(f0.index), find(f1.index)
            if ra != rb:
                parent[ra] = rb
    groups = {}
    for f in bm.faces:
        groups.setdefault(find(f.index), []).append(f.index)
    out = []
    for fl in groups.values():
        us, vs = [], []
        for fi in fl:
            for l in bm.faces[fi].loops:
                us.append(l[uv].uv.x)
                vs.append(l[uv].uv.y)
        out.append({"faces": fl, "bbox": [min(us), min(vs), max(us), max(vs)]})
    bm.free()
    return out


def island_side(o, faces, dom):
    """Top or bottom for one garment island, by the same vote garment_regions() makes."""
    gcfg = CFG["garments"].get(KIND[o.name][1], {})
    rule = gcfg.get("regions", "auto")
    if rule in ("keep", "top", "bottom"):
        return rule
    top = bottom = hips = 0
    for fi in faces:
        for vi in o.data.polygons[fi].vertices:
            d = dom[vi] or ""
            if d == "Hips":
                hips += 1
            elif d.endswith(("UpLeg", "Leg", "Foot", "ToeBase")):
                bottom += 1
            elif d.startswith(("Spine", "Shoulder", "Arm", "ForeArm", "Hand", "neck", "Head")) or d.endswith(("Spine", "Shoulder", "Arm", "ForeArm", "Hand", "neck", "Head")):
                top += 1
    if gcfg.get("hips", "bottom") == "top":
        return "bottom" if bottom > top + hips else "top"
    return "bottom" if bottom + hips > top else "top"


def image_size(path):
    img = bpy.data.images.load(path, check_existing=True)
    return img.size[0], img.size[1]


def skyline_pack(rects, size):
    """Bottom-left skyline packing (tallest first): each rect goes where it leaves the lowest top
    edge. Sets r["dest"]; False when the set does not fit."""
    sky = [[0, 0, size]]  # segments [x, y, width], left to right
    for r in sorted(rects, key=lambda r: (-r["h"], -r["w"])):
        w, h = r["w"], r["h"]
        best = None
        for i in range(len(sky)):
            x = sky[i][0]
            if x + w > size:
                break
            # the rect's floor is the highest segment it spans
            y, span, j = 0, 0, i
            while span < w:
                y = max(y, sky[j][1])
                span += sky[j][2]
                j += 1
            if y + h <= size and (best is None or (y + h, x) < (best[0] + h, best[1])):
                best = (y, x)
        if best is None:
            return False
        y, x = best
        r["dest"] = [x, y]
        # raise the skyline under the rect
        new, placed = [], False
        for sx, sy, sw in sky:
            if sx + sw <= x or sx >= x + w:
                new.append([sx, sy, sw])
                continue
            if sx < x:
                new.append([sx, sy, x - sx])
            if not placed:
                new.append([x, y + h, w])
                placed = True
            if sx + sw > x + w:
                new.append([x + w, sy, sx + sw - (x + w)])
        new.sort()
        merged = []
        for seg in new:
            if merged and merged[-1][1] == seg[1] and merged[-1][0] + merged[-1][2] == seg[0]:
                merged[-1][2] += seg[2]
            else:
                merged.append(seg)
        sky = merged
    return True


def plan_atlas(objs, size, which):
    """Packs every island of `objs` into a size x size atlas, shelf by shelf, scaling the whole
    set down until it fits. Returns the rects and rewrites nothing yet."""
    rects = []
    for o in objs:
        k, n = KIND[o.name]
        src = IMAGES[o.name]["diffuse"]
        sw, sh = image_size(src)
        isl = islands(o)
        head_faces = None
        if k == "skin":
            bm = bmesh.new()
            bm.from_mesh(o.data)
            dl = bm.verts.layers.deform.active
            bm.faces.ensure_lookup_table()
            head_faces = {f.index for f in bm.faces if region_of(f, dl) == "head"}
            bm.free()
        gdom = dominant_groups(o) if k == "garment" else None
        mine = []
        for i, s in enumerate(isl):
            part = k
            if k == "skin" and sum(1 for fi in s["faces"] if fi in head_faces) > 0.5 * len(s["faces"]):
                part = "skin_head"
            mine.append({"obj": o.name, "island": i, "part": part, "src": src, "src_size": [sw, sh],
                         "bbox": list(s["bbox"]), "faces": list(s["faces"]), "normal": IMAGES[o.name]["normal"],
                         "ao": IMAGES[o.name]["ao"], "side": island_side(o, s["faces"], gdom) if gdom else ""})
        # Islands that share texture (hair cards reuse strips of one photo, mirrored sleeves and
        # shoes share a side) are one rect: copying the texture once per island only wasted atlas.
        # Islands whose rects touch merge too, so one garment piece is never cut in two.
        margin = 4.0 / max(sw, sh)
        merged = True
        while merged:
            merged = False
            for a in range(len(mine)):
                for b in range(a + 1, len(mine)):
                    A, B = mine[a]["bbox"], mine[b]["bbox"]
                    # never across the top / bottom split: a tee touching its shorts in the
                    # texture would take the shorts' colour
                    if mine[a]["part"] == mine[b]["part"] and mine[a]["side"] == mine[b]["side"] \
                            and A[0] - margin < B[2] and B[0] - margin < A[2] \
                            and A[1] - margin < B[3] and B[1] - margin < A[3]:
                        mine[a]["bbox"] = [min(A[0], B[0]), min(A[1], B[1]), max(A[2], B[2]), max(A[3], B[3])]
                        mine[a]["faces"] += mine[b]["faces"]
                        del mine[b]
                        merged = True
                        break
                if merged:
                    break
        rects += mine
    pad = ATL["pad"]
    # Start large and come down until the set fits, so the atlas is filled; no part is ever
    # taken above its source's own texel density.
    g = 1.8
    for attempt in range(80):
        for r in rects:
            s = min(ATL["scale"].get(r["part"], 0.5) * g, 1.0)
            nw = max(8, int(round(r["src_size"][0] * s)))
            nh = max(8, int(round(r["src_size"][1] * s)))
            bx0, by0, bx1, by1 = r["bbox"]
            cx0 = math.floor(bx0 * nw)
            cx1 = math.ceil(bx1 * nw)
            cy0 = math.floor((1.0 - by1) * nh)
            cy1 = math.ceil((1.0 - by0) * nh)
            r.update(scaled=[nw, nh], crop=[cx0, cy0, cx1, cy1], w=cx1 - cx0 + 2 * pad, h=cy1 - cy0 + 2 * pad)
        ok = skyline_pack(rects, size)
        if ok:
            print("CROWD %s atlas: %d islands at %.3f of the configured scale, %d%% of it used" % (
                which, len(rects), g, 100 * sum(r["w"] * r["h"] for r in rects) / (size * size)))
            return rects
        g *= 0.97
    raise RuntimeError("atlas does not pack")


def apply_uvs(rects, size):
    pad = ATL["pad"]
    by_obj = {}
    for r in rects:
        by_obj.setdefault(r["obj"], []).append(r)
    for on, rs in by_obj.items():
        o = bpy.data.objects[on]
        me = o.data
        uv = me.uv_layers.active.data
        for r in rs:
            nw, nh = r["scaled"]
            cx0, cy0 = r["crop"][0], r["crop"][1]
            dx, dy = r["dest"]
            for fi in r["faces"]:
                p = me.polygons[fi]
                for li in p.loop_indices:
                    u, v = uv[li].uv
                    ax = dx + pad + (u * nw - cx0)
                    ay = dy + pad + ((1.0 - v) * nh - cy0)
                    uv[li].uv = (ax / size, 1.0 - ay / size)


body_parts = [o for o in meshes if KIND[o.name][0] in ("skin", "eyes", "garment", "shoes", "hat")]
hair_parts = [o for o in meshes if KIND[o.name][0] in ("hair", "brows", "lashes")]
body_rects = plan_atlas(body_parts, ATL["size"], "body")
# brows and lashes alone (a painted crop) need a fraction of the hair atlas
if not any(KIND[o.name][0] == "hair" for o in hair_parts):
    ATL["hair_size"] = min(ATL["hair_size"], 512)
hair_rects = plan_atlas(hair_parts, ATL["hair_size"], "hair") if hair_parts else []

# ---- the vertex colour: R top, G bottom, B hair, A skin -----------------------------------------------
LEG_BONES = ("UpLeg", "Leg", "Foot", "ToeBase")
TOP_BONES = ("Spine", "Shoulder", "Arm", "ForeArm", "Hand", "neck", "Head")


def garment_regions(o, rects):
    """Top or bottom per face: each island by the bones its faces follow (legs -> bottom)."""
    gcfg = CFG["garments"].get(KIND[o.name][1], {})
    rule = gcfg.get("regions", "auto")
    # Parts that follow the hips alone (a waistband, a jacket's pocket flaps) go with the trousers
    # unless the garment says its hips are the top's (a jacket worn over the jeans).
    hips_top = gcfg.get("hips", "bottom") == "top"
    dom = dominant_groups(o)
    region = {}
    for r in rects:
        if r["obj"] != o.name:
            continue
        top = bottom = hips = 0
        for fi in r["faces"]:
            for vi in o.data.polygons[fi].vertices:
                d = dom[vi] or ""
                if d == "Hips":
                    hips += 1
                elif d.endswith(LEG_BONES):
                    bottom += 1
                elif d.startswith(TOP_BONES) or d.endswith(TOP_BONES):
                    top += 1
        if rule == "keep":
            for fi in r["faces"]:
                region[fi] = "keep"
            continue
        if rule == "top":
            is_bottom = False
        elif rule == "bottom":
            is_bottom = True
        elif hips_top:
            is_bottom = bottom > top + hips
        else:
            is_bottom = bottom + hips > top
        for fi in r["faces"]:
            region[fi] = "bottom" if is_bottom else "top"
    return region


# What each garment is woven from, which the character shader's tiling detail follows. It rides
# in the region channel's level (R for the top, G for the bottom): 1.0 jersey, 0.85 denim, 0.70
# woven (shirting, suiting, canvas); a garment the looks must not recolour ("keep") sits 0.45
# lower (0.55 / 0.40 / 0.25) in R. Eyes are B and A both full (nothing else can be: the scalp
# blend has B + A = 1). See region_mask in shaders/character.gdshader.
FABRIC_LEVEL = {"jersey": 1.0, "denim": 0.85, "woven": 0.70}
FABRIC_DEFAULT = {
    "male_casualsuit01": ("woven", "denim"), "male_casualsuit02": ("jersey", "denim"),
    "male_casualsuit03": ("woven", "denim"), "male_casualsuit04": ("jersey", "denim"),
    "male_casualsuit05": ("woven", "denim"), "male_casualsuit06": ("jersey", "denim"),
    "male_elegantsuit01": ("woven", "woven"), "male_worksuit01": ("denim", "denim", "denim"),
    "female_casualsuit01": ("jersey", "denim"), "female_casualsuit02": ("jersey", "denim"),
    "female_elegantsuit01": ("woven", "woven"), "female_sportsuit01": ("jersey", "jersey"),
}


def fabric_of(asset, side):
    g = CFG["garments"].get(asset, {}).get("fabric", {})
    d = FABRIC_DEFAULT.get(asset, ("jersey", "denim"))
    return g.get(side, d[0] if side == "top" else (d[1] if side == "bottom" else d[-1]))


REGIONS = {o.name: garment_regions(o, body_rects) for o in body_parts if KIND[o.name][0] == "garment"}
for r in body_rects:
    if r["obj"] in REGIONS:
        r["region"] = REGIONS[r["obj"]].get(r["faces"][0], "top")
for o in body_parts + hair_parts:
    me = o.data
    col = me.color_attributes.new("Col", 'BYTE_COLOR', 'CORNER')
    k = KIND[o.name][0]
    region = REGIONS.get(o.name, {})
    data = col.data
    for p in me.polygons:
        for li in p.loop_indices:
            vi = me.loops[li].vertex_index
            if k == "skin":
                s = min(max(scalp[vi], 0.0), 1.0)
                c = (0.0, 0.0, s, 1.0 - s)
            elif k == "garment":
                rg = region.get(p.index)
                asset = KIND[o.name][1]
                if rg == "keep":
                    c = (FABRIC_LEVEL[fabric_of(asset, "keep")] - 0.45, 0.0, 0.0, 0.0)
                elif rg == "top":
                    c = (FABRIC_LEVEL[fabric_of(asset, "top")], 0.0, 0.0, 0.0)
                else:
                    c = (0.0, FABRIC_LEVEL[fabric_of(asset, "bottom")], 0.0, 0.0)
            elif k in ("hair", "brows", "lashes"):
                c = (0.0, 0.0, 1.0, 0.0)
            elif k == "eyes":
                c = (0.0, 0.0, 1.0, 1.0)
            else:
                c = (0.0, 0.0, 0.0, 0.0)
            data[li].color = c

apply_uvs(body_rects, ATL["size"])
if hair_rects:
    apply_uvs(hair_rects, ATL["hair_size"])

# ---- UV2: metric detail coordinates (1 unit = 1 m of surface) --------------------------------------
# The character shader tiles skin pores and fabric weave on these, so a pore or a denim twill is
# the same size on the face (which has four times the atlas density) as on a hand or a leg. Per
# atlas rect: the rect's atlas UV scaled by sqrt(surface area / UV area), plus a random offset so
# neighbouring rects do not line up. Same orientation as UV1, so the tangents serve both.
import random as _random  # noqa: E402

_r = _random.Random(NAME)
by_obj = {}
for r in body_rects:
    by_obj.setdefault(r["obj"], []).append(r)
for on, rs in by_obj.items():
    o = bpy.data.objects[on]
    me = o.data
    uv1 = me.uv_layers[0].data
    det = me.uv_layers.new(name="detail")
    uv2 = det.data
    mw = o.matrix_world
    for r in rs:
        a3 = a2 = 0.0
        for fi in r["faces"]:
            pl = me.polygons[fi]
            vs = [mw @ me.vertices[vi].co for vi in pl.vertices]
            us = [uv1[li].uv.copy() for li in pl.loop_indices]
            for j in range(1, len(vs) - 1):
                a3 += ((vs[j] - vs[0]).cross(vs[j + 1] - vs[0])).length * 0.5
                e1, e2 = us[j] - us[0], us[j + 1] - us[0]
                a2 += abs(e1.x * e2.y - e1.y * e2.x) * 0.5
        k = math.sqrt(a3 / a2) if a2 > 1e-12 else 1.0
        ox, oy = _r.random(), _r.random()
        for fi in r["faces"]:
            for li in me.polygons[fi].loop_indices:
                u, v = uv1[li].uv
                uv2[li].uv = (u * k + ox, v * k + oy)
    me.uv_layers.active_index = 0
    me.uv_layers[0].active_render = True

# ---- the garments' fold field data (crowd_atlas.py turns it into fold normals) ----------------------
# Every garment triangle's atlas UVs, rest-pose corners and normals (metres, Blender space, the
# figure facing -Y), whether it hangs off the arms and torso (the fold field's "jacket") or the
# legs, and its garment's fold gain; plus the landmarks tools/hero/folds.py measures from.
import numpy as np  # noqa: E402

F_uv, F_p, F_n, F_j, F_g = [], [], [], [], []
LEGS = ("UpLeg", "Leg", "Foot", "ToeBase")
for o in body_parts:
    if KIND[o.name][0] != "garment":
        continue
    me = o.data
    me.calc_loop_triangles()
    uv1 = me.uv_layers[0].data
    mw = o.matrix_world
    nm = mw.to_3x3()
    region = REGIONS.get(o.name, {})
    dom = dominant_groups(o)
    gain = CFG["garments"].get(KIND[o.name][1], {}).get("fold_gain", 1.0) * CFG.get("fold_gain", 1.0)
    for t in me.loop_triangles:
        rg = region.get(t.polygon_index, "top")
        if rg == "keep":
            legs = sum(1 for vi in t.vertices if (dom[vi] or "").endswith(LEGS)) >= 2
            jacket = not legs
        else:
            jacket = rg == "top"
        F_uv.append([list(uv1[li].uv) for li in t.loops])
        F_p.append([list(mw @ me.vertices[vi].co) for vi in t.vertices])
        F_n.append([list((nm @ me.vertices[vi].normal).normalized()) for vi in t.vertices])
        F_j.append(jacket)
        F_g.append(gain)
if F_uv:
    P_all = np.array(F_p)
    Jm = np.array(F_j)

    def bone_head(n):
        return list(arm.matrix_world @ arm.data.bones[n].head_local)
    L = {n: bone_head(n) for n in ("LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand",
                                    "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot", "Hips")}
    L["Spine2"] = bone_head("Spine")  # the chest (MPFB's Spine2 is the game's "Spine")
    top_pts = P_all[Jm].reshape(-1, 3) if Jm.any() else np.zeros((0, 3))
    bot_pts = P_all[~Jm].reshape(-1, 3) if (~Jm).any() else np.zeros((0, 3))
    # the top's hem: the lowest point of it on the torso (not the hanging sleeves)
    sh_x = abs(L["LeftArm"][0])
    torso = top_pts[np.abs(top_pts[:, 0]) < sh_x * 0.75] if len(top_pts) else top_pts
    L["z_hem"] = float(torso[:, 2].min()) if len(torso) else L["Hips"][2]
    # sleeves: stacking above the cuff only when the sleeve runs past the elbow
    ends = []
    for sd in ("Left", "Right"):
        sh, el, wr = (np.array(L[sd + n]) for n in ("Arm", "ForeArm", "Hand"))
        same = top_pts[(top_pts[:, 0] > 0) == (sh[0] > 0)] if len(top_pts) else top_pts
        ax = (wr - el) / np.linalg.norm(wr - el)
        u = (same - el) @ ax if len(same) else np.array([-1.0])
        reach = float(u.max()) if len(u) else -1.0
        L1, L2 = np.linalg.norm(el - sh), np.linalg.norm(wr - el)
        # folds.py stacks from (arm length - sleeve_end) to the cuff and past it, so a sleeve that
        # stops above the elbow gets a sleeve_end far negative: no stacking anywhere on it
        ends.append(L2 - reach if reach > 0.08 else -10.0)
    L["sleeve_end"] = float(max(ends)) if min(ends) < -5.0 and max(ends) < -5.0 else float(min(e for e in ends if e > -5.0) if any(e > -5.0 for e in ends) else -10.0)
    # trousers: ankle stacking only on long ones
    knee_z = min(L["LeftLeg"][2], L["RightLeg"][2])
    low = float(bot_pts[:, 2].min()) if len(bot_pts) else 0.0
    L["z_pants_end"] = low if (len(bot_pts) and low < knee_z - 0.25) else -10.0
    np.savez_compressed(C.work(NAME, "folds.npz"), uv=np.array(F_uv, np.float32), p=P_all.astype(np.float32),
                        n=np.array(F_n, np.float32), jacket=Jm, gain=np.array(F_g, np.float32))
    with open(C.work(NAME, "fold_landmarks.json"), "w") as f:
        json.dump(L, f)
    print("CROWD folds: %d garment triangles, hem z %.2f, sleeve end %.2f, trouser end %.2f" % (
        len(F_uv), L["z_hem"], L["sleeve_end"], L["z_pants_end"]))

# the scalp painted into the atlas for the looks that keep the model's own hair (crowd_atlas.py)
scalp_tris = []
uvl = body.data.uv_layers.active.data
body.data.calc_loop_triangles()
beard_tris = []
for t in body.data.loop_triangles:
    w = [scalp[body.data.loops[li].vertex_index] for li in t.loops]
    if max(w) > 0.02:
        scalp_tris.append([[list(uvl[li].uv) for li in t.loops], w])
    wb = [beard[body.data.loops[li].vertex_index] for li in t.loops]
    if max(wb) > 0.02:
        beard_tris.append([[list(uvl[li].uv) for li in t.loops], wb])

plan = {"name": NAME, "size": ATL["size"], "normal_size": ATL["normal_size"], "hair_size": ATL["hair_size"],
        "pad": ATL["pad"], "hair_rgb": CFG.get("hair_rgb"), "skin": CFG["skin"], "skin_blend": CFG.get("skin_blend"),
        "skin_normal_strength": CFG.get("skin_normal_strength", 2.0), "garment_ao": CFG.get("garment_ao", 0.5),
        "garments": CFG["garments"], "scalp_tris": scalp_tris, "dye": CFG.get("dye", {}), "skin_tone": CFG.get("skin_tone"),
        "beard_tris": beard_tris, "stubble": CFG.get("stubble", 0.0), "beard": CFG.get("beard", 0.0),
        "beard_rgb": CFG.get("beard_rgb"), "dye_contrast": CFG.get("dye_contrast", {}),
        "body": [{k: v for k, v in r.items() if k != "faces"} | {"kind": KIND[r["obj"]][0], "asset": KIND[r["obj"]][1]} for r in body_rects],
        "hair": [{k: v for k, v in r.items() if k != "faces"} | {"kind": KIND[r["obj"]][0], "asset": KIND[r["obj"]][1]} for r in hair_rects]}
with open(C.work(NAME, "atlas.json"), "w") as f:
    json.dump(plan, f)

# ---- one body mesh, one hair mesh ---------------------------------------------------------------------
def join(objs, name):
    activate(objs[0])
    for o in objs[1:]:
        o.select_set(True)
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    o.data.name = name
    o.data.materials.clear()
    mat = bpy.data.materials.new("%s_%s" % (NAME, name.lower()))
    o.data.materials.append(mat)
    for p in o.data.polygons:
        p.material_index = 0
        p.use_smooth = True
    for an in ("crowd_scalp", "crowd_beard"):
        a = o.data.attributes.get(an)
        if a is not None:
            o.data.attributes.remove(a)
    keep = 2 if "detail" in o.data.uv_layers else 1
    while len(o.data.uv_layers) > keep:
        o.data.uv_layers.remove(o.data.uv_layers[-1])
    o.data.uv_layers.active_index = 0
    bones = {b.name for b in arm.data.bones}
    for g in list(o.vertex_groups):
        if g.name not in bones:
            o.vertex_groups.remove(g)
    return o


body_o = join(body_parts, "Body")
hair_o = join(hair_parts, "Hair") if hair_parts else None
finals = [body_o] + ([hair_o] if hair_o else [])

# ---- soles on y = 0, centimetres under a 0.01 armature ---------------------------------------------
lowest = min((body_o.matrix_world @ v.co).z for v in body_o.data.vertices)
for loc, scl in (((0.0, 0.0, -lowest), (1.0, 1.0, 1.0)), ((0.0, 0.0, 0.0), (100.0, 100.0, 100.0))):
    activate(arm)
    arm.location = loc
    arm.scale = scl
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True, properties=False)
    for o in finals:
        activate(o)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True, properties=False)
for o in finals:
    o.parent = arm
    o.matrix_parent_inverse = Matrix.Identity(4)
    o.modifiers.new("Armature", 'ARMATURE').object = arm
arm.scale = (0.01, 0.01, 0.01)
bpy.context.view_layer.update()
arm.name = "Armature"
arm.data.name = "Armature"
arm.data.pose_position = 'POSE'
for b in arm.pose.bones:
    b.rotation_mode = 'QUATERNION'
for o in [o for o in bpy.data.objects if o.type == 'MESH' and o not in finals]:
    bpy.data.objects.remove(o, do_unlink=True)
height = max((o.matrix_world @ v.co).z for o in finals for v in o.data.vertices) - min((o.matrix_world @ v.co).z for o in finals for v in o.data.vertices)
body_h = max((body_o.matrix_world @ v.co).z for v in body_o.data.vertices)
print("CROWD body height without hair %.3f m" % body_h)
print("CROWD done %s: body %d tris, hair %d tris, %.2f m tall, %d bones" % (
    NAME, tris(body_o), tris(hair_o) if hair_o else 0, height, len(arm.data.bones)))
bpy.ops.wm.save_as_mainfile(filepath=C.work(NAME, "rigged.blend"))
