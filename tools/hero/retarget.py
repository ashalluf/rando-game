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
import fixarms  # noqa: E402

argv = common.blender_args()
SRC = next((a for a in argv if a.endswith(".glb")), common.ANIM_SOURCE)
FIX_ARMS = "--keep-arms" not in argv

bpy.ops.wm.open_mainfile(filepath=common.work("hero_rigged.blend"))
scene = bpy.context.scene
scene.render.fps = 30  # the source keys are 1/30 s apart, so every key lands on an integer frame
tgt = bpy.data.objects["Armature"]
tgt_meshes = [bpy.data.objects["hero_mesh"], bpy.data.objects["hero_shadow"]]
tgt.name = "HeroArmature"  # avoid a clash with the imported one

before = set(bpy.data.objects)
before_actions = set(bpy.data.actions)
bpy.ops.import_scene.gltf(filepath=SRC)
new = [o for o in bpy.data.objects if o not in before]
src = [o for o in new if o.type == 'ARMATURE'][0]
src_actions = [a for a in bpy.data.actions if a not in before_actions]
tgt.name = "Armature"

CHAIN = {  # bone -> the child whose head gives the bone's direction
    "Hips": "Spine02", "Spine02": "Spine01", "Spine01": "Spine", "Spine": "neck", "neck": "Head", "Head": "head_end",
}
for s in ("Left", "Right"):
    CHAIN.update({s + "Shoulder": s + "Arm", s + "Arm": s + "ForeArm", s + "ForeArm": s + "Hand",
                  s + "UpLeg": s + "Leg", s + "Leg": s + "Foot", s + "Foot": s + "ToeBase"})
INHERIT = {s + k: s + p for s in ("Left", "Right") for k, p in (("Hand", "ForeArm"), ("ToeBase", "Foot"))}
MAPPED = list(CHAIN) + list(INHERIT)

sb = src.data.bones; tb = tgt.data.bones
S_rest = {n: sb[n].matrix_local.to_quaternion() for n in MAPPED}
T_rest = {b.name: b.matrix_local.copy() for b in tb}
align = {}
for n, c in CHAIN.items():
    s_dir = (sb[c].head_local - sb[n].head_local).normalized()
    t_dir = (tb[c].head_local - tb[n].head_local).normalized()
    align[n] = t_dir.rotation_difference(s_dir)
for n, p in INHERIT.items():
    align[n] = align[p]
src_hip_h = sb["Hips"].head_local.z
tgt_hip_h = tb["Hips"].head_local.z
k = tgt_hip_h / src_hip_h
print("RETARGET hip heights src %.1f tgt %.1f -> translation scale %.3f" % (src_hip_h, tgt_hip_h, k))
for n in ("Hips", "LeftArm", "LeftForeArm", "LeftUpLeg", "Spine"):
    print("RETARGET rest alignment %-12s %.1f deg" % (n, math.degrees(align[n].angle)))

order = []  # parents first
def walk(b):
    order.append(b.name)
    for c in b.children:
        walk(c)
for b in tb:
    if b.parent is None:
        walk(b)


def solve_frame():
    """Target pose-bone basis (loc, quat) for the source's currently evaluated pose."""
    pose = {}
    basis = {}
    for n in order:
        b = tb[n]
        if n in MAPPED:
            spb = src.pose.bones[n]
            D = spb.matrix.to_quaternion() @ S_rest[n].inverted()
            R = D @ align[n] @ T_rest[n].to_quaternion()
        else:
            R = None
        if b.parent is None:
            head = T_rest[n].translation.copy()
            if n == "Hips":
                off = src.pose.bones["Hips"].head - sb["Hips"].head_local
                head = head + off * k
            M = Matrix.Translation(head) @ (R if R else T_rest[n].to_quaternion()).to_matrix().to_4x4()
            B = T_rest[n].inverted() @ M
            basis[n] = (B.translation.copy(), B.to_quaternion())
            pose[n] = M
        else:
            L = pose[b.parent.name] @ T_rest[b.parent.name].inverted() @ T_rest[n]
            q = (L.to_quaternion().inverted() @ R) if R else Quaternion()
            basis[n] = (Vector(), q)
            pose[n] = L @ q.to_matrix().to_4x4()
    return basis, pose


def write_action(name, frames):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    act.id_root = "OBJECT"  # the glTF exporter only gathers OBJECT-rooted actions
    prev = {}
    for n in order:
        pb = f'pose.bones["{n}"]'
        qs = []
        for i, (basis, _) in enumerate(frames):
            q = basis[n][1].normalized()
            if n in prev and prev[n].dot(q) < 0:
                q = -q
            prev[n] = q
            qs.append(q)
        for c in range(4):
            fc = act.fcurves.new(pb + ".rotation_quaternion", index=c, action_group=n)
            fc.keyframe_points.add(len(qs))
            fc.keyframe_points.foreach_set("co", [v for i, q in enumerate(qs) for v in (float(i), q[c])])
            for kp in fc.keyframe_points:
                kp.interpolation = 'LINEAR'
        if n == "Hips":
            for c in range(3):
                fc = act.fcurves.new(pb + ".location", index=c, action_group=n)
                fc.keyframe_points.add(len(frames))
                fc.keyframe_points.foreach_set("co", [v for i, (basis, _) in enumerate(frames) for v in (float(i), basis[n][0][c])])
                for kp in fc.keyframe_points:
                    kp.interpolation = 'LINEAR'
    return act


src.animation_data_create()
for tr in list(src.animation_data.nla_tracks):
    src.animation_data.nla_tracks.remove(tr)
baked = []
for a in src_actions:
    clip = a.name.replace("_" + src.name, "").replace("_Armature", "")
    times = sorted(set(round(kp.co.x, 4) for fc in a.fcurves for kp in fc.keyframe_points))
    src.animation_data.action = a
    frames = []
    toe_min = 1e9
    for t in times:
        scene.frame_set(int(math.floor(t)), subframe=t - math.floor(t))
        basis, pose = solve_frame()
        frames.append((basis, pose))
        toe_min = min(toe_min, min(pose[n].translation.z for n in ("LeftToeBase", "RightToeBase", "LeftFoot", "RightFoot")))
    # Ground the clip: the source rigs' rest pose has the legs apart and bent, so their idle and walk
    # carry the hips 4-9 cm above rest and the source walk even hovers ~8 cm. Shift the hips so the
    # lowest the ball of a foot gets over the clip is its rest height (a planted foot).
    toes = [min(p[n].translation.z for n in ("LeftToeBase", "RightToeBase")) for _, p in frames]
    tgt_toe = min(tb[n].head_local.z for n in ("LeftToeBase", "RightToeBase"))
    dz = tgt_toe - min(toes)
    for basis, pose in frames:
        loc, q = basis["Hips"]
        # basis location is in the Hips bone's rest frame: move along armature Z expressed in it
        up = T_rest["Hips"].to_quaternion().inverted() @ Vector((0, 0, dz))
        basis["Hips"] = (loc + up, q)
    toe_min = min(toes) + dz
    act = write_action(clip, frames)
    baked.append(act)
    print("RETARGET clip %-22s keys %3d  %.3f s  grounding shift %+.1f cm, lowest ball-of-foot %.1f cm (rest %.1f)" % (clip, len(times), (len(times) - 1) / 30.0, dz, toe_min, tgt_toe))

if FIX_ARMS:
    for act in baked:
        fixarms.fix_arms(tgt, act)
        print("RETARGET arms rebuilt (fix_arm_pose port) on", act.name)
    for act in baked:
        print("RETARGET relaxed finger keys on", act.name, fixarms.add_finger_keys(tgt, act), "bones")

# Remove the imported source and its actions; keep ours.
src.animation_data.action = None
for o in new:
    bpy.data.objects.remove(o, do_unlink=True)
for a in src_actions:
    bpy.data.actions.remove(a)
tgt.name = "Armature"; tgt.data.name = "Armature"
tgt.animation_data_create()
tgt.animation_data.action = bpy.data.actions.get("Idle")
bpy.ops.wm.save_as_mainfile(filepath=common.work("hero_anim.blend"))

# ---- export ------------------------------------------------------------------------------------
for o in bpy.context.selected_objects:
    o.select_set(False)
tgt.select_set(True)
for o in tgt_meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = tgt
bpy.ops.export_scene.gltf(
    filepath=common.GLB, export_format='GLB', use_selection=True,
    export_yup=True, export_apply=False, export_texcoords=True, export_normals=True, export_tangents=False,
    export_materials='EXPORT', export_image_format='AUTO', export_skins=True, export_all_influences=False,
    export_def_bones=False, export_rest_position_armature=True, export_morph=False,
    export_animations=True, export_animation_mode='ACTIONS', export_force_sampling=True, export_frame_step=1,
    export_anim_single_armature=True, export_reset_pose_bones=True, export_optimize_animation_size=False,
    export_leaf_bone=False)
print("EXPORTED", common.GLB, os.path.getsize(common.GLB) // 1024, "KB")
