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

info = HumanService._create_default_human_info_dict()
ph = {"gender": 0.5, "age": 0.5, "muscle": 0.5, "weight": 0.5, "proportions": 0.5, "height": 0.5,
      "cupsize": 0.5, "firmness": 0.5}
ph.update(CFG["phenotype"])
info.update({
    "name": NAME, "phenotype": ph, "rig": CFG["rig"], "eyes": CFG["eyes"],
    "eyebrows": CFG.get("eyebrows", ""), "eyelashes": CFG.get("eyelashes", ""), "hair": CFG.get("hair", ""),
    "teeth": "", "tongue": "", "clothes": CFG["clothes"], "skin_mhmat": CFG["skin"][0] + ".mhmat",
    "skin_material_type": CFG["skin_material_type"], "eyes_material_type": CFG["eyes_material_type"],
    "targets": [{"target": t, "value": v} for t, v in CFG.get("targets", [])],
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
        mine = []
        for i, s in enumerate(isl):
            part = k
            if k == "skin" and sum(1 for fi in s["faces"] if fi in head_faces) > 0.5 * len(s["faces"]):
                part = "skin_head"
            mine.append({"obj": o.name, "island": i, "part": part, "src": src, "src_size": [sw, sh],
                         "bbox": list(s["bbox"]), "faces": list(s["faces"]), "normal": IMAGES[o.name]["normal"],
                         "ao": IMAGES[o.name]["ao"]})
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
                    if mine[a]["part"] == mine[b]["part"] and A[0] - margin < B[2] and B[0] - margin < A[2] \
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
                c = (1.0, 0.0, 0.0, 0.0) if rg == "top" else ((0.0, 0.0, 0.0, 0.0) if rg == "keep" else (0.0, 1.0, 0.0, 0.0))
            elif k in ("hair", "brows", "lashes"):
                c = (0.0, 0.0, 1.0, 0.0)
            else:
                c = (0.0, 0.0, 0.0, 0.0)
            data[li].color = c

apply_uvs(body_rects, ATL["size"])
if hair_rects:
    apply_uvs(hair_rects, ATL["hair_size"])

# the scalp painted into the atlas for the looks that keep the model's own hair (crowd_atlas.py)
scalp_tris = []
uvl = body.data.uv_layers.active.data
body.data.calc_loop_triangles()
for t in body.data.loop_triangles:
    w = [scalp[body.data.loops[li].vertex_index] for li in t.loops]
    if max(w) > 0.02:
        scalp_tris.append([[list(uvl[li].uv) for li in t.loops], w])

plan = {"name": NAME, "size": ATL["size"], "normal_size": ATL["normal_size"], "hair_size": ATL["hair_size"],
        "pad": ATL["pad"], "hair_rgb": CFG.get("hair_rgb"), "skin": CFG["skin"], "skin_blend": CFG.get("skin_blend"),
        "skin_normal_strength": CFG.get("skin_normal_strength", 2.0), "garment_ao": CFG.get("garment_ao", 0.5),
        "garments": CFG["garments"], "scalp_tris": scalp_tris, "dye": CFG.get("dye", {}), "skin_tone": CFG.get("skin_tone"),
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
    for a in [a for a in o.data.attributes if a.name == "crowd_scalp"]:
        o.data.attributes.remove(a)
    while len(o.data.uv_layers) > 1:
        o.data.uv_layers.remove(o.data.uv_layers[-1])
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
