# Step 3: retarget the game's idle / walk / run clips (from the current hero's Meshy rig) onto the
# new MPFB-based rig, bake them as actions with the game's clip names, and export the .glb.
#
# Method: both rigs are Z-up in Blender and face -Y (glTF +Z). For every source frame and every
# mapped bone, the source bone's armature-space rotation relative to its own rest, D, is applied to
# the target bone's rest after first swinging the target's rest direction onto the source's rest
# direction (A). So the target bone points exactly where the source bone points, whatever the two
# rest poses are. Hips translation is carried over in armature space, scaled by the hip-height
# ratio. Bones the source does not have (fingers, head_end, headfront) keep their rest.
# Optional (--fix-arms): the arms are then rebuilt the way the game's Pedestrian.fix_arm_pose()
# does it (see fixarms.py), because the source clips' arm keys only look right on their own rig's
# odd bind pose.
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import retarget_lib  # noqa: E402

argv = common.blender_args()
SRC = next((a for a in argv if a.endswith(".glb")), common.ANIM_SOURCE)
FIX_ARMS = "--keep-arms" not in argv

bpy.ops.wm.open_mainfile(filepath=common.work("hero_rigged.blend"))
scene = bpy.context.scene
scene.render.fps = 30  # the source keys are 1/30 s apart, so every key lands on an integer frame
tgt = bpy.data.objects["Armature"]
tgt_meshes = [bpy.data.objects["hero_mesh"], bpy.data.objects["hero_shadow"]]
baked = retarget_lib.retarget_clips(tgt, SRC, FIX_ARMS)
tgt.name = "Armature"; tgt.data.name = "Armature"
tgt.animation_data_create()
tgt.animation_data.action = bpy.data.actions.get("Idle")
bpy.ops.wm.save_as_mainfile(filepath=common.work("hero_anim.blend"))

# ---- export ------------------------------------------------------------------------------------
retarget_lib.export_glb(tgt, tgt_meshes, common.GLB)
