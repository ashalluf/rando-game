# Step: turn the parts into one game mesh.
#  - bake the shape targets and the garment masks into plain geometry; drop the corneas (the eye's
#    wet look is a clearcoat on the eyeball, see hero_look.gd)
#  - hands decimated a little, then the whole visible skin subdivided once: the face, ears and
#    fingers were the silhouettes that read as polygons up close
#  - glTF-friendly materials from TEX/textures.json, everything joined into one skinned mesh
#  - a light shadow twin (hero_shadow): body, suit and shoes decimated to a few thousand
#    triangles, which the game draws SHADOWS_ONLY while the full mesh casts nothing
#  - the MPFB "mixamo" skeleton renamed to the game's rig names; bones and vertices in
#    centimetres under a 0.01 armature, facing +Z in glTF
# Reads work/hero_parts.blend, writes work/hero_rigged.blend.
import json
import os
import sys

import bmesh
import bpy
import mathutils

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

CFG = common.config()
FIN = CFG.get("finalize", {})
bpy.ops.wm.open_mainfile(filepath=common.work("hero_parts.blend"))
scene = bpy.context.scene
arm = bpy.data.objects["hero"]
arm.data.pose_position = 'REST'


def activate(o):
    for x in bpy.context.selected_objects:
        x.select_set(False)
    bpy.context.view_layer.objects.active = o
    o.select_set(True)


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


# ---- 1. bake shape keys and masks, keep only the armature modifier ------------------------------
meshes = [o for o in bpy.data.objects if o.type == 'MESH' and o.parent == arm]
for o in meshes:
    activate(o)
    if o.data.shape_keys:
        bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
    for m in list(o.modifiers):
        if m.type == 'ARMATURE':
            o.modifiers.remove(m)
    for m in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)

body = bpy.data.objects["hero.body"]
eyes = [o for o in meshes if o.name.endswith("high-poly") or o.name.endswith("low-poly")][0]
activate(eyes)
bm = bmesh.new()
bm.from_mesh(eyes.data)
uv = bm.loops.layers.uv.active
dead = [f for f in bm.faces if all(l[uv].uv.x > 0.85 and l[uv].uv.y < 0.15 for l in f.loops)]
bmesh.ops.delete(bm, geom=dead, context='FACES')
bm.to_mesh(eyes.data)
bm.free()


def select_faces(o, pick):
    activate(o)
    bpy.ops.object.mode_set(mode='EDIT')
    bmx = bmesh.from_edit_mesh(o.data)
    dl = bmx.verts.layers.deform.active
    for f in bmx.faces:
        f.select = pick(f, dl)
    bmx.select_flush_mode()
    bmesh.update_edit_mesh(o.data)


def decimate_selected(o, pick, ratio):
    select_faces(o, pick)
    bpy.ops.mesh.decimate(ratio=ratio, use_symmetry=True, symmetry_axis='X')
    bpy.ops.mesh.select_all(action='DESELECT')
    bpy.ops.object.mode_set(mode='OBJECT')


hand_groups = {g.index for g in body.vertex_groups if "Hand" in g.name}
decimate_selected(body, lambda f, dl: sum(sum(w for gi, w in v[dl].items() if gi in hand_groups) for v in f.verts) / len(f.verts) > 0.95,
                  FIN.get("hand_ratio", 0.45))
shoes_o = [o for o in meshes if ".shoes" in o.name]
for o in shoes_o:
    decimate_selected(o, lambda f, dl: True, FIN.get("shoe_ratio", 0.8))

# ---- 2. the shadow twin, from the parts before the skin is subdivided ----------------------------
twin_parts = []
for o in meshes:
    n = o.name.split(".", 1)[1]
    if n in ("body", "tracksuit") or ".shoes" in o.name or n.startswith(("ts_hem", "ts_collar", "ts_cuff_L", "ts_cuff_R", "ts_ankle")):
        c = o.copy()
        c.data = o.data.copy()
        scene.collection.objects.link(c)
        twin_parts.append(c)
activate(twin_parts[0])
for c in twin_parts:
    c.select_set(True)
bpy.ops.object.join()
twin = bpy.context.view_layer.objects.active
twin.name = "hero_shadow"
twin.data.name = "hero_shadow"
dec = twin.modifiers.new("DEC", 'DECIMATE')
dec.decimate_type = 'COLLAPSE'
dec.ratio = min(1.0, FIN.get("shadow_tris", 9000) / max(tris(twin), 1))
bpy.ops.object.modifier_apply(modifier=dec.name)
shadow_mat = bpy.data.materials.new("hero_shadow")
twin.data.materials.clear()
twin.data.materials.append(shadow_mat)
for p in twin.data.polygons:
    p.material_index = 0
    p.use_smooth = True
while len(twin.data.uv_layers) > 1:
    twin.data.uv_layers.remove(twin.data.uv_layers[-1])
meshes = [o for o in meshes if o not in twin_parts]

# ---- 3. subdivide the visible skin once ---------------------------------------------------------
activate(body)
ss = body.modifiers.new("SS", 'SUBSURF')
ss.levels = ss.render_levels = FIN.get("skin_subdiv", 1)
ss.uv_smooth = 'PRESERVE_CORNERS'
ss.boundary_smooth = 'PRESERVE_CORNERS'
bpy.ops.object.modifier_apply(modifier=ss.name)
print("REPORT skin tris after subdivision", tris(body))
# ... then thinned where the extra density buys nothing: the scalp under the hair shows only in
# the gaps between cards, the ears and neck are smooth shapes, and the fingers keep their round
# silhouettes after a collapse that is much finer than the subdivision made them
def weight_of(names):
    gis = {body.vertex_groups[n].index for n in names if n in body.vertex_groups}
    return lambda f, dl: sum(sum(w for gi, w in v[dl].items() if gi in gis) for v in f.verts) / len(f.verts) > 0.6


for names, ratio in ((["scalp"], FIN.get("scalp_ratio", 0.3)), (["ears"], FIN.get("ear_ratio", 0.6)),
                     (["mixamorig:Neck", "mixamorig:Spine2", "mixamorig:LeftShoulder", "mixamorig:RightShoulder"], FIN.get("neck_ratio", 0.6)),
                     ([g.name for g in body.vertex_groups if "Hand" in g.name], FIN.get("hand_after_ratio", 0.6))):
    decimate_selected(body, weight_of(names), ratio)
print("REPORT skin tris after thinning", tris(body))

# ---- 4. materials -------------------------------------------------------------------------------
tex_cfg = json.load(open(common.tex("textures.json")))


def load_img(name, non_color=False):
    img = bpy.data.images.load(common.tex(name), check_existing=True)
    if non_color:
        img.colorspace_settings.name = 'Non-Color'
    return img


def make_material(name, spec):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = spec.get("roughness", 0.6)
    bsdf.inputs["Specular IOR Level"].default_value = spec.get("specular", 0.5)
    bsdf.inputs["Metallic"].default_value = spec.get("metallic", 0.0)
    base = None
    if "base" in spec:
        base = nt.nodes.new("ShaderNodeTexImage")
        base.image = load_img(spec["base"])
        base.location = (-700, 300)
        col_out = base.outputs["Color"]
        if "color_factor" in spec:
            # texture x constant: exported as the glTF baseColorFactor, so the colour is one
            # material parameter (albedo_color in Godot) and the texture only the detail
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = 'RGBA'
            mix.blend_type = 'MULTIPLY'
            mix.inputs["Factor"].default_value = 1.0
            mix.inputs[7].default_value = (*spec["color_factor"], 1.0)
            mix.location = (-350, 300)
            nt.links.new(base.outputs["Color"], mix.inputs[6])
            col_out = mix.outputs[2]
        nt.links.new(col_out, bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = (*spec["color"], 1.0)
    if spec.get("alpha_clip") and base is not None:
        gt = nt.nodes.new("ShaderNodeMath")
        gt.operation = 'GREATER_THAN'
        gt.inputs[1].default_value = spec["alpha_clip"]
        nt.links.new(base.outputs["Alpha"], gt.inputs[0])
        nt.links.new(gt.outputs[0], bsdf.inputs["Alpha"])
        m.surface_render_method = 'DITHERED'
    if spec.get("alpha") is not None:
        bsdf.inputs["Alpha"].default_value = spec["alpha"]
        m.surface_render_method = 'BLENDED'
    if spec.get("rough_map"):
        r = nt.nodes.new("ShaderNodeTexImage")
        r.image = load_img(spec["rough_map"], True)
        r.location = (-700, -50)
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(r.outputs["Color"], sep.inputs[0])
        nt.links.new(sep.outputs[1], bsdf.inputs["Roughness"])
    if spec.get("normal"):
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = load_img(spec["normal"], True)
        n.location = (-700, -350)
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = spec.get("normal_strength", 1.0)
        nt.links.new(n.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if spec.get("sheen"):
        sh = spec["sheen"]
        bsdf.inputs["Sheen Weight"].default_value = sh["weight"]
        bsdf.inputs["Sheen Tint"].default_value = (*sh["tint"], 1.0)
        bsdf.inputs["Sheen Roughness"].default_value = sh["roughness"]
    if spec.get("clearcoat"):
        bsdf.inputs["Coat Weight"].default_value = spec["clearcoat"]
        bsdf.inputs["Coat Roughness"].default_value = 0.03
    if spec.get("sss"):
        # Cycles previews only (not exported): the game's hero skin shader does its own
        bsdf.inputs["Subsurface Weight"].default_value = spec["sss"]
        bsdf.inputs["Subsurface Radius"].default_value = (1.0, 0.35, 0.2)
        bsdf.inputs["Subsurface Scale"].default_value = 0.005
    m.use_backface_culling = not spec.get("double_sided", False)
    return m


PREFIX = (("ts_cuff", "ts_rib"), ("ts_ankle", "ts_rib"), ("ts_hem", "ts_rib"), ("ts_collar", "ts_rib"),
          ("ts_pipe", "ts_pipe"), ("ts_zipper", "ts_metal"), ("ts_slider", "ts_metal"),
          ("ts_watchcase", "ts_gold"), ("ts_watchhands", "ts_gold"), ("ts_ring", "ts_gold"), ("ts_watch", "ts_gold"),
          ("ts_chain", "ts_gold"), ("ts_dial", "ts_dial"), ("ts_crystal", "ts_crystal"), ("ts_tank", "ts_tank"))


def spec_key(key):
    for pre, k in PREFIX:
        if key.startswith(pre):
            return k
    return key


mat_cache = {}
for o in meshes:
    key = spec_key(o.name.split(".", 1)[1])
    spec = tex_cfg["materials"][key]
    if key not in mat_cache:
        mat_cache[key] = make_material(spec["name"], spec)
    o.data.materials.clear()
    o.data.materials.append(mat_cache[key])

# ---- 5. join into one mesh ---------------------------------------------------------------------
activate(body)
for o in meshes:
    o.select_set(True)
bpy.ops.object.join()
hero = bpy.context.view_layer.objects.active
hero.name = "hero_mesh"
hero.data.name = "hero_mesh"
for p in hero.data.polygons:
    p.use_smooth = True
bone_names = {b.name for b in arm.data.bones}
for o in (hero, twin):
    for g in list(o.vertex_groups):
        if g.name not in bone_names:
            o.vertex_groups.remove(g)

# ---- 6. the game's rig names -------------------------------------------------------------------
RENAME = {"Spine": "Spine02", "Spine1": "Spine01", "Spine2": "Spine", "Neck": "neck"}
for b in arm.data.bones:
    short = b.name.replace("mixamorig:", "")
    b.name = RENAME.get(short, short)
for o in (hero, twin):
    for g in o.vertex_groups:
        short = g.name.replace("mixamorig:", "")
        g.name = RENAME.get(short, short)
activate(arm)
bpy.ops.object.mode_set(mode='EDIT')
eb = arm.data.edit_bones
head = eb["Head"]
he = eb.new("head_end")
he.head = head.tail.copy()
he.tail = head.tail + mathutils.Vector((0, 0, 0.08))
he.parent = head
hf = eb.new("headfront")
hf.head = mathutils.Vector((head.head.x, -0.13, head.head.z))
hf.tail = hf.head + mathutils.Vector((0, -0.08, 0))
hf.parent = head
bpy.ops.object.mode_set(mode='OBJECT')
for o in (hero, twin):
    o.parent = arm
    o.matrix_parent_inverse = mathutils.Matrix.Identity(4)
    o.modifiers.new("Armature", 'ARMATURE').object = arm

# ---- 7. soles on y = 0, centimetres under a 0.01 armature -----------------------------------------
lowest = min((hero.matrix_world @ v.co).z for v in hero.data.vertices)
for loc, scl in (((0.0, 0.0, -lowest), (1.0, 1.0, 1.0)), ((0.0, 0.0, 0.0), (100.0, 100.0, 100.0))):
    activate(arm)
    arm.location = loc
    arm.scale = scl
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True, properties=False)
    for o in (hero, twin):
        activate(o)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True, properties=False)
        o.matrix_parent_inverse = mathutils.Matrix.Identity(4)
arm.scale = (0.01, 0.01, 0.01)
bpy.context.view_layer.update()
arm.name = "Armature"
arm.data.name = "Armature"
arm.data.pose_position = 'POSE'
for b in arm.pose.bones:
    b.rotation_mode = 'QUATERNION'

# ---- report ------------------------------------------------------------------------------------
dg = bpy.context.evaluated_depsgraph_get()
eo = hero.evaluated_get(dg)
m2 = eo.to_mesh()
m2.calc_loop_triangles()
ws = [eo.matrix_world @ v.co for v in m2.vertices]
print("REPORT tris", len(m2.loop_triangles), "verts", len(m2.vertices), "height_m", round(max(w.z for w in ws) - min(w.z for w in ws), 3),
      "shadow twin tris", tris(twin), "uv layers", [u.name for u in hero.data.uv_layers])
per = {}
for t in m2.loop_triangles:
    per[t.material_index] = per.get(t.material_index, 0) + 1
for i, s in enumerate(hero.material_slots):
    print("REPORT material", i, s.material.name, "tris", per.get(i, 0))
print("REPORT bones", len(arm.data.bones))
eo.to_mesh_clear()
bpy.ops.wm.save_as_mainfile(filepath=common.work("hero_rigged.blend"))
