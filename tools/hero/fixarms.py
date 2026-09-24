# A Blender port of the game's Pedestrian.fix_arm_pose() (scripts/npc/pedestrian.gd), so the baked
# clips already carry the arms the game would build at load time (and look right in any viewer).
# The game computes in glTF/Godot skeleton space (Y up, +Z forward). Blender armature space is
# Z up, -Y forward; the map is a proper rotation, and the glTF exporter keeps bone-local frames
# as they are (+Y along the bone, verified in both rigs), so local rotations carry over unchanged
# and global directions/rotations just use the mapped axis constants below.
import math
from mathutils import Matrix, Quaternion, Vector

# Game constants (pedestrian.gd), degrees.
ARM_GAIT = {
    "run": [34.0, 8.0, 78.0, 14.0, 12.0, 4.0],
    "walk": [15.0, 4.0, 15.0, 15.0, 9.0, 7.0],
    "idle": [0.0, 3.0, 12.0, 0.0, 8.0, 7.0],
}
FOREARM_TWIST = 32.0
WRIST_TWIST = 28.0

UP = Vector((0, 0, 1)); DOWN = Vector((0, 0, -1)); LEFT = Vector((-1, 0, 0)); BACK = Vector((0, -1, 0))  # BACK = rig front


def basis_from_cols(a, b, c):
    m = Matrix((a, b, c)).transposed()  # rows -> columns
    return m


def fix_arms(arm_obj, act):
    bones = arm_obj.data.bones
    names = [b.name for b in bones]
    parent = {b.name: (b.parent.name if b.parent else None) for b in bones}
    rest_q = {b.name: b.matrix_local.to_quaternion() for b in bones}
    head = {b.name: b.matrix_local.translation.copy() for b in bones}

    # Read the baked basis rotations (keys on integer frames 0..n-1).
    fcs = {}
    for fc in act.fcurves:
        if fc.data_path.endswith("rotation_quaternion"):
            n = fc.data_path.split('"')[1]
            fcs.setdefault(n, [None] * 4)[fc.array_index] = fc
    # Key times: those of the densest rotation curve (importers drop keys from constant channels).
    times = max(([kp.co[0] for kp in fc.keyframe_points] for q in fcs.values() for fc in q if fc), key=len)
    nkeys = len(times)
    basis = {n: [Quaternion([fcs[n][c].evaluate(t) if fcs[n][c] else (1.0 if c == 0 else 0.0) for c in range(4)]) for t in times]
             for n in fcs}
    changed = set()

    def rest_local(n):
        p = parent[n]
        return rest_q[n] if p is None else rest_q[p].inverted() @ rest_q[n]

    def origin(child):  # child's rest offset in its parent's local frame (Godot get_bone_rest(child).origin)
        p = parent[child]
        return rest_q[p].inverted() @ (head[child] - head[p])

    def local(n, i):  # Godot-style local pose rotation (relative to parent)
        return rest_local(n) @ basis[n][i] if n in basis else rest_local(n)

    def pose_rot(n, i):
        q = Quaternion()
        b = n
        chain = []
        while b is not None:
            chain.append(b); b = parent[b]
        for b in reversed(chain):
            q = q @ local(b, i)
        return q

    def set_local(n, i, q_local):
        if n not in basis:
            basis[n] = [Quaternion() for _ in range(nkeys)]
        basis[n][i] = (rest_local(n).inverted() @ q_local).normalized()
        changed.add(n)

    def rrot(n):  # global rest rotation
        return rest_q[n]

    kind = "idle"
    for k in ARM_GAIT:
        if k in act.name.lower():
            kind = k
            break
    gait = ARM_GAIT[kind]

    def thigh_angle(thigh, knee, i):
        d = pose_rot(thigh, i) @ origin(knee)
        return math.atan2(-d.y, -d.z)  # Godot atan2(d.z, -d.y) with z_g = -y_b, y_g = z_b

    for side in (1.0, -1.0):
        pre = "Left" if side > 0 else "Right"
        arm, fore, hand = pre + "Arm", pre + "ForeArm", pre + "Hand"
        shoulder = parent[arm]; chest = parent[shoulder]
        # collarbone levelled onto its rest direction (mean over the clip)
        reach = origin(arm).normalized()
        mean = Vector()
        for i in range(nkeys):
            mean += local(shoulder, i) @ reach
        if mean.length > 0.001:
            level = mean.normalized().rotation_difference(rest_local(shoulder) @ reach)
            for i in range(nkeys):
                set_local(shoulder, i, level @ local(shoulder, i))
        arm_rest = rrot(arm); fore_rest = rrot(fore); chest_rest_inv = rrot(chest).inverted()
        u0 = (arm_rest @ origin(fore)).normalized()
        f0 = (fore_rest @ origin(hand)).normalized()
        h0 = u0.cross(f0)
        if h0.length < 0.1:
            h0 = u0.cross(BACK)
        h0.normalize()
        rest_u = basis_from_cols(u0, h0, u0.cross(h0)).transposed()
        rest_f = basis_from_cols(f0, h0, f0.cross(h0)).transposed()
        thigh, knee = pre + "UpLeg", pre + "Leg"
        leg_mid = leg_amp = 0.0
        if gait[0] > 0.0:
            angs = [thigh_angle(thigh, knee, i) for i in range(nkeys)]
            lo, hi = min(angs), max(angs)
            leg_mid = (lo + hi) * 0.5; leg_amp = (hi - lo) * 0.5
        spread = math.radians(gait[4]) * side
        for i in range(nkeys):
            swing = 0.0
            if leg_amp > math.radians(2.0):
                swing = -(thigh_angle(thigh, knee, i) - leg_mid) / leg_amp
            elbow = math.radians(gait[2] + gait[3] * min(max(swing, 0.0), 1.0))
            chest_fwd = (pose_rot(chest, i) @ chest_rest_inv) @ BACK
            turn = Quaternion(UP, math.atan2(chest_fwd.x, -chest_fwd.y))
            frame = turn @ Quaternion(LEFT, math.radians(gait[1] + gait[0] * swing)) @ Quaternion(BACK, spread)
            u1 = frame @ DOWN; h1 = frame @ LEFT
            f1 = Quaternion(turn @ BACK, -math.radians(gait[5]) * side) @ (Quaternion(h1, elbow) @ u1)
            hf = (h1 - f1 * h1.dot(f1)).normalized()
            g_arm = ((basis_from_cols(u1, h1, u1.cross(h1)) @ rest_u).to_quaternion() @ arm_rest).normalized()
            g_fore = (Quaternion(f1, math.radians(FOREARM_TWIST) * side)
                      @ (basis_from_cols(f1, hf, f1.cross(hf)) @ rest_f).to_quaternion() @ fore_rest).normalized()
            par = pose_rot(shoulder, i)
            set_local(arm, i, par.inverted() @ g_arm)
            set_local(fore, i, g_arm.inverted() @ g_fore)
        # wrist straightened onto the forearm's axis, then the rest of the palm turn
        hand_rest = rest_local(hand)
        axis = origin(hand).normalized()
        q = Quaternion(axis, math.radians(WRIST_TWIST) * side) @ (hand_rest @ Vector((0, 1, 0))).rotation_difference(axis) @ hand_rest
        for i in range(nkeys):
            set_local(hand, i, q.normalized())

    # write back the bones we changed, keyed at every time (with sign continuity)
    for n in changed:
        qs = basis[n]
        path = f'pose.bones["{n}"].rotation_quaternion'
        vals = []
        prev = None
        for q in qs:
            if prev is not None and prev.dot(q) < 0:
                q = -q
            prev = q
            vals.append(q)
        for c in range(4):
            fc = act.fcurves.find(path, index=c) or act.fcurves.new(path, index=c, action_group=n)
            fc.keyframe_points.clear()
            fc.keyframe_points.add(nkeys)
            fc.keyframe_points.foreach_set("co", [v for t, q in zip(times, vals) for v in (t, q[c])])
            for kp in fc.keyframe_points:
                kp.interpolation = 'LINEAR'
            fc.update()


# Relaxed hands. The clips have no finger keys and the MakeHuman rest hand is flat with the
# fingers fanned, which reads as a mannequin. Degrees of flexion per joint (knuckle, middle, tip);
# the pinky side curls a little more than the index, as a hand at rest does.
FINGER_CURL = {"Index": (14, 24, 16), "Middle": (18, 30, 18), "Ring": (22, 34, 20), "Pinky": (26, 38, 22)}
THUMB_CURL = (6, 12, 14)
FINGER_TOGETHER = {"Index": 4, "Ring": 3, "Pinky": 7}  # adduction toward the middle finger (degrees)


def finger_curl(arm_obj):
    """Constant basis rotations for the finger bones (bone name -> Quaternion)."""
    bones = arm_obj.data.bones
    out = {}
    for side, pre in ((1.0, "Left"), (-1.0, "Right")):
        h = pre + "Hand"
        if pre + "HandMiddle1" not in bones:
            continue
        d = (bones[pre + "HandMiddle2"].head_local - bones[pre + "HandMiddle1"].head_local).normalized()
        s = (bones[pre + "HandPinky1"].head_local - bones[pre + "HandIndex1"].head_local).normalized()
        palm = (s.cross(d) * side).normalized()  # palm side of the hand, from the finger order
        for f, angs in list(FINGER_CURL.items()) + [("Thumb", THUMB_CURL)]:
            for j in (1, 2, 3):
                n = f"{pre}Hand{f}{j}"
                if n not in bones:
                    continue
                b = bones[n]
                fd = (b.tail_local - b.head_local).normalized()
                axis = fd.cross(palm).normalized()
                q = Quaternion(axis, math.radians(angs[j - 1]))
                if j == 1 and f in FINGER_TOGETHER:
                    toward = fd.cross(d)  # swings this finger toward the middle finger
                    if toward.length > 1e-3:
                        q = q @ Quaternion(toward.normalized(), math.radians(FINGER_TOGETHER[f]))
                rest = b.matrix_local.to_quaternion()
                out[n] = (rest.inverted() @ q @ rest).normalized()  # same rotation, in the bone's frame
    return out


def add_finger_keys(arm_obj, act):
    curl = finger_curl(arm_obj)
    frames = [kp.co[0] for kp in next(fc for fc in act.fcurves if fc.data_path.endswith("rotation_quaternion")).keyframe_points]
    for n, q in curl.items():
        path = f'pose.bones["{n}"].rotation_quaternion'
        for c in range(4):
            fc = act.fcurves.find(path, index=c) or act.fcurves.new(path, index=c, action_group=n)
            fc.keyframe_points.clear()
            fc.keyframe_points.add(2)
            fc.keyframe_points.foreach_set("co", [frames[0], q[c], frames[-1], q[c]])
    return len(curl)
