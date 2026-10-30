# Crowd step 3 (Blender): the character's atlases on its two meshes, idle / walk / run baked on
# (the hero's retarget, tools/hero/retarget_lib.py, arms rebuilt the way the game does it), and
# the .glb written to assets/models/<name>.glb.
#
#   blender -b --python tools/crowd/crowd_export.py -- crowd_a
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import crowd_common as C  # noqa: E402
import retarget_lib  # noqa: E402  (tools/hero)

NAME = C.blender_args()[0]
bpy.ops.wm.open_mainfile(filepath=C.work(NAME, "rigged.blend"))
arm = bpy.data.objects["Armature"]
body = bpy.data.objects["Body"]
hair = bpy.data.objects.get("Hair")


def image(file, name, non_color=False):
    img = bpy.data.images.load(C.work(NAME, file), check_existing=False)
    img.name = name
    if non_color:
        img.colorspace_settings.name = 'Non-Color'
    return img


def dress(o, base, normal=None, alpha=False, roughness=0.8):
    m = o.data.materials[0]
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Specular IOR Level"].default_value = 0.5
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = base
    nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    if alpha:
        # alpha clip the way the glTF exporter recognises it (as in tools/hero/finalize.py)
        gt = nt.nodes.new("ShaderNodeMath")
        gt.operation = 'GREATER_THAN'
        gt.inputs[1].default_value = 0.4
        nt.links.new(t.outputs["Alpha"], gt.inputs[0])
        nt.links.new(gt.outputs[0], bsdf.inputs["Alpha"])
        m.surface_render_method = 'DITHERED'
        m.use_backface_culling = False
    if normal is not None:
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = normal
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(n.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])


dress(body, image("body.jpg", "body"), image("body_nrm.jpg", "body_nrm", True))
if hair:
    dress(hair, image("hair.png", "hair"), alpha=True, roughness=0.55)

# The idle is copied from a rig bound with its legs apart and bent; settled most of the way back
# to this body's own straight stance, a pause on the pavement is standing, not a crouch.
baked = retarget_lib.retarget_clips(arm, C.ANIM_SOURCE, True, settle_legs={"Idle": 0.65})
arm.name = "Armature"
arm.data.name = "Armature"
arm.animation_data_create()
arm.animation_data.action = bpy.data.actions.get("Idle")
meshes = [body] + ([hair] if hair else [])
retarget_lib.export_glb(arm, meshes, os.path.join(C.ASSETS, NAME + ".glb"), vertex_colors=True)
