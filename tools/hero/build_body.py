# Step 1: build the MPFB human (base mesh + shape targets + eyes, brows, lashes, shoes + the
# "mixamo" rig) from hero_config.json and save work/hero_mpfb.blend.
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

cfg = common.config()
bpy.ops.wm.read_factory_settings(use_empty=True)
import addon_utils  # noqa: E402

addon_utils.enable("bl_ext.user_default.mpfb", default_set=True)
from bl_ext.user_default.mpfb.services.humanservice import HumanService  # noqa: E402

info = HumanService._create_default_human_info_dict()
human = dict(cfg["human"])
# The hair is our own cards (hair.py), not a MakeHuman proxy.
human["hair"] = ""
info.update(human)
settings = HumanService.get_default_deserialization_settings()
settings["subdiv_levels"] = 0  # finalize.py subdivides what shows, after the garments mask the rest
settings["override_skin_model"] = "MAKESKIN"
basemesh = HumanService.deserialize_from_dict(info, settings)
basemesh.name = "hero.body"

# ---- bind pose: arms lower and elbows straighter than MakeHuman's A-pose -------------------------
# The game spends most of its time with the arms hanging (idle, walk, run). Bound in the A-pose
# (upper arms 48 degrees below level, elbows bent 46), every one of those frames swung the arm
# 40 degrees about the shoulder under linear-blend skinning, which is what squared the shoulders
# off into pads. Bound closer to the hanging arm, the skinning has less to do where it is seen
# most. The tracksuit, folds and hair are all built afterwards on this pose.
import math  # noqa: E402

from mathutils import Matrix, Vector  # noqa: E402

RP = cfg.get("rest_pose", {})
arm = basemesh.parent
P = "mixamorig:"
if RP.get("arm_down_deg", 0.0) or RP.get("elbow_open_deg", 0.0):
    for o in list(bpy.data.objects):
        if o.type == 'MESH' and o.parent == arm:
            bpy.context.view_layer.objects.active = o
            for x in bpy.context.selected_objects:
                x.select_set(False)
            o.select_set(True)
            if o.data.shape_keys:
                bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='POSE')
    for side, sg in (("Left", 1.0), ("Right", -1.0)):
        for name, deg in (("Arm", RP.get("arm_down_deg", 0.0)),):
            pb = arm.pose.bones[P + side + name]
            head = pb.matrix.translation.copy()
            rot = Matrix.Translation(head) @ Matrix.Rotation(math.radians(deg) * sg, 4, 'Y') @ Matrix.Translation(-head)
            pb.matrix = rot @ pb.matrix
            bpy.context.view_layer.update()
        fa = arm.pose.bones[P + side + "ForeArm"]
        up = arm.pose.bones[P + side + "Arm"]
        u = (fa.head - up.head).normalized()
        f = (fa.tail - fa.head).normalized()
        axis = f.cross(u)
        if axis.length > 1e-4:
            head = fa.matrix.translation.copy()
            rot = Matrix.Translation(head) @ Matrix.Rotation(math.radians(RP.get("elbow_open_deg", 0.0)), 4, axis.normalized()) @ Matrix.Translation(-head)
            fa.matrix = rot @ fa.matrix
            bpy.context.view_layer.update()
    bpy.ops.object.mode_set(mode='OBJECT')
    # bake the pose into every mesh, then make it the rest pose
    for o in list(bpy.data.objects):
        if o.type == 'MESH' and o.parent == arm:
            mods = [m for m in o.modifiers if m.type == 'ARMATURE']
            for m in mods:
                bpy.context.view_layer.objects.active = o
                with bpy.context.temp_override(object=o):
                    bpy.ops.object.modifier_apply(modifier=m.name)
                nm = o.modifiers.new("Armature", 'ARMATURE')
                nm.object = arm
                with bpy.context.temp_override(object=o):
                    bpy.ops.object.modifier_move_to_index(modifier=nm.name, index=0)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='POSE')
    bpy.ops.pose.select_all(action='SELECT')
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    la, le, lw = (arm.data.bones[P + n].head_local for n in ("LeftArm", "LeftForeArm", "LeftHand"))
    print("BODY bind pose: upper arm %.1f deg below level, elbow bent %.1f deg" % (
        math.degrees(math.asin(-(le - la).normalized().z)), math.degrees((le - la).angle(lw - le))))
dg = bpy.context.evaluated_depsgraph_get()
for o in bpy.data.objects:
    extra = ""
    if o.type == 'MESH':
        me = o.evaluated_get(dg).to_mesh()
        me.calc_loop_triangles()
        extra = "tris=%d verts=%d" % (len(me.loop_triangles), len(me.vertices))
    print("BODY", o.name, o.type, "parent=", o.parent.name if o.parent else None, extra)
bpy.ops.wm.save_as_mainfile(filepath=common.work("hero_mpfb.blend"))
