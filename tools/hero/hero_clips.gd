extends SceneTree
## The hero's moves: clips retargeted onto hero.glb's 54-bone rig from Quaternius' Universal
## Animation Library 1 and 2 (CC0, docs/ASSETS.md) - the take-off, the air, the landings, the roll,
## the sprint - plus four idle variants KEYED HERE over the library's idle (looking round, a
## one-arm stretch, checking the watch on his left wrist, cracking his neck): the free Standard
## files have no such clips. Writes one AnimationLibrary, assets/models/hero_moves.res, which
## Avatar adds to the hero's AnimationPlayer as "moves" (after Pedestrian.fix_arm_pose(), which
## must never see these clips).
##
## Godot-side, like tools/crowd/life_clips.gd (never Blender's glTF import, which re-orients the
## bones): the same world-delta retarget, so neither rest pose matters. Differences from the
## crowd's: the hero's finger bones are not in the library's map, so every clip carries the hero
## Idle's own finger keys (a clip without them would let the hands go flat to the bind pose);
## the air clips are not grounded (their feet are tucked up on purpose); and a clip whose hips
## travel (the roll) is put back in place, since the player's body does the travelling.
##
## A keyed idle variant is the library's idle with OVERLAYS on it: turns of a bone about a
## skeleton-space axis and aims of a bone's length at a skeleton-space direction, each with a
## weight envelope over the clip (_overlay()). The rig faces +Z, Y up, his LEFT is +X. A clip that
## needs the left arm off the gun says so in its meta "free_left" (Vector2: seconds it is free,
## ramps included), which Avatar reads to let the left hand go.
##
## Fetch the sources first (tools/crowd/fetch_life_clips.sh puts them in build/ual_src), then:
##   godot --headless --path . -s tools/hero/hero_clips.gd
## and `godot --headless --path . --import`. FPS (default 30) is the key rate written.

const SRC_DIR := "res://build/ual_src/"
const HERO := "res://assets/models/hero.glb"
const OUT := "res://assets/models/hero_moves.res"

## [source file, source clip, our name, loop, options]. Options: swing (legs about their mean),
## settle (legs back toward the rig's rest), ground (false: keep the source's hip height, for
## the air clips), inplace (true: the hips' horizontal travel taken out), from / to (seconds of
## the source kept).
const CLIPS := [
	["UAL1_Standard.glb", "Idle_Loop", "idle", true, {"settle": 0.6}],
	["UAL1_Standard.glb", "Jump_Start", "jump_start", false, {"ground": false}],
	["UAL1_Standard.glb", "Jump_Loop", "jump_air", true, {"ground": false}],
	["UAL1_Standard.glb", "Jump_Land", "land", false, {}],
	["UAL2_Standard.glb", "NinjaJump_Land", "land_hero", false, {}],
	["UAL1_Standard.glb", "Roll", "roll", false, {"inplace": true}],
	["UAL1_Standard.glb", "Sprint_Loop", "sprint", true, {}],
	["UAL1_Standard.glb", "Hit_Chest", "hit_chest", false, {}],
	["UAL1_Standard.glb", "Hit_Head", "hit_head", false, {}],
]

## The keyed idle variants: [name, length (s), free_left window or Vector2.ZERO].
const VARIANTS := [
	["idle_look", 4.6, Vector2.ZERO],
	["idle_neck", 3.4, Vector2.ZERO],
	["idle_watch", 4.2, Vector2(0.0, 4.2)],
	["idle_stretch", 4.4, Vector2(0.0, 4.4)],
]

## Hero bone <- library bone (the crowd's names; the hero carries them, plus fingers).
const MAP := {
	"Hips": "pelvis", "Spine02": "spine_01", "Spine01": "spine_02", "Spine": "spine_03",
	"neck": "neck_01", "Head": "Head",
	"LeftShoulder": "clavicle_l", "LeftArm": "upperarm_l", "LeftForeArm": "lowerarm_l", "LeftHand": "hand_l",
	"RightShoulder": "clavicle_r", "RightArm": "upperarm_r", "RightForeArm": "lowerarm_r", "RightHand": "hand_r",
	"LeftUpLeg": "thigh_l", "LeftLeg": "calf_l", "LeftFoot": "foot_l", "LeftToeBase": "ball_l",
	"RightUpLeg": "thigh_r", "RightLeg": "calf_r", "RightFoot": "foot_r", "RightToeBase": "ball_r",
}
const TGT_CHAIN := {
	"Hips": "Spine02", "Spine02": "Spine01", "Spine01": "Spine", "Spine": "neck", "neck": "Head",
	"Head": "head_end",
	"LeftShoulder": "LeftArm", "LeftArm": "LeftForeArm", "LeftForeArm": "LeftHand", "LeftHand": "LeftHandMiddle1",
	"RightShoulder": "RightArm", "RightArm": "RightForeArm", "RightForeArm": "RightHand", "RightHand": "RightHandMiddle1",
	"LeftUpLeg": "LeftLeg", "LeftLeg": "LeftFoot", "LeftFoot": "LeftToeBase",
	"RightUpLeg": "RightLeg", "RightLeg": "RightFoot", "RightFoot": "RightToeBase",
}
const SRC_CHAIN := {
	"pelvis": "spine_01", "spine_01": "spine_02", "spine_02": "spine_03", "spine_03": "neck_01",
	"neck_01": "Head",
	"clavicle_l": "upperarm_l", "upperarm_l": "lowerarm_l", "lowerarm_l": "hand_l", "hand_l": "middle_01_l",
	"clavicle_r": "upperarm_r", "upperarm_r": "lowerarm_r", "lowerarm_r": "hand_r", "hand_r": "middle_01_r",
	"thigh_l": "calf_l", "calf_l": "foot_l", "foot_l": "ball_l", "ball_l": "ball_leaf_l",
	"thigh_r": "calf_r", "calf_r": "foot_r", "foot_r": "ball_r", "ball_r": "ball_leaf_r",
}
const SKEL_PATH := "Armature/Skeleton3D:"

class Rig:
	var root: Node
	var sk: Skeleton3D
	var rest_g: Array[Transform3D] = []
	var order: PackedInt32Array = PackedInt32Array()

	func _init(scene_root: Node) -> void:
		root = scene_root
		sk = root.find_children("*", "Skeleton3D", true, false)[0]
		rest_g.resize(sk.get_bone_count())
		for b in sk.get_bone_count():
			rest_g[b] = sk.get_bone_global_rest(b)
		var seen := {}
		while order.size() < sk.get_bone_count():
			for b in sk.get_bone_count():
				var p := sk.get_bone_parent(b)
				if not seen.has(b) and (p < 0 or seen.has(p)):
					seen[b] = true
					order.append(b)

	func bone(name: String) -> int:
		return sk.find_bone(name)

	func dir(name: String, chain: Dictionary) -> Vector3:
		var b := bone(name)
		var c := bone(chain.get(name, "")) if chain.has(name) else -1
		if c >= 0:
			var d := rest_g[c].origin - rest_g[b].origin
			if d.length() > 1e-5:
				return d.normalized()
		return rest_g[b].basis.y.normalized()


## One retargeted clip in memory: per frame {bone: local quat} and the hips' position.
class Take:
	var length := 0.0
	var frames := 0
	var poses: Array = []
	var hips: Array[Vector3] = []

	func time(f: int) -> float:
		return minf(length * f / frames, length)


func _load(path: String) -> Node:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), st) != OK:
		return null
	return doc.generate_scene(st)


func _src_pose(src: Rig, a: Animation, t: float) -> Array[Transform3D]:
	var g: Array[Transform3D] = []
	g.resize(src.sk.get_bone_count())
	for b in src.order:
		var rest := src.sk.get_bone_rest(b)
		var path := NodePath(SKEL_PATH + src.sk.get_bone_name(b))
		var basis := rest.basis
		var origin := rest.origin
		var rt := a.find_track(path, Animation.TYPE_ROTATION_3D)
		if rt >= 0:
			basis = Basis(a.rotation_track_interpolate(rt, t))
		var pt := a.find_track(path, Animation.TYPE_POSITION_3D)
		if pt >= 0:
			origin = a.position_track_interpolate(pt, t)
		var local := Transform3D(basis, origin)
		var p := src.sk.get_bone_parent(b)
		g[b] = local if p < 0 else g[p] * local
	return g


## A bone's skeleton-space transform from the local rotations in `local` (rest for the rest).
func _pose_global(tgt: Rig, local: Dictionary, hips: Vector3, bone: int) -> Transform3D:
	var chain: Array[int] = []
	var b := bone
	while b >= 0:
		chain.push_front(b)
		b = tgt.sk.get_bone_parent(b)
	var g := Transform3D.IDENTITY
	for c in chain:
		var rest := tgt.sk.get_bone_rest(c)
		var q: Quaternion = local.get(c, rest.basis.get_rotation_quaternion())
		g = g * Transform3D(Basis(q), hips if c == tgt.bone("Hips") else rest.origin)
	return g


func _retarget(src: Rig, tgt: Rig, a: Animation, fps: float, opt: Dictionary) -> Take:
	var tsk := tgt.sk
	var settle: float = opt.get("settle", 0.0)
	var align := {}
	for tn: String in MAP:
		align[tn] = Quaternion(tgt.dir(tn, TGT_CHAIN), src.dir(MAP[tn], SRC_CHAIN))
	var src_hips := src.bone("pelvis")
	var tgt_hips := tgt.bone("Hips")
	var k := tgt.rest_g[tgt_hips].origin.y / src.rest_g[src_hips].origin.y
	var t0: float = opt.get("from", 0.0)
	var t1: float = opt.get("to", a.length)
	var take := Take.new()
	take.length = t1 - t0
	take.frames = maxi(int(round(take.length * fps)), 1)
	for f in take.frames + 1:
		var t := t0 + take.time(f)
		var sg := _src_pose(src, a, t)
		var tg: Array[Transform3D] = []
		tg.resize(tsk.get_bone_count())
		var local := {}
		var hips_at := tgt.rest_g[tgt_hips].origin + (sg[src_hips].origin - src.rest_g[src_hips].origin) * k
		for b in tgt.order:
			var bn := tsk.get_bone_name(b)
			var p := tsk.get_bone_parent(b)
			var rest_local := tsk.get_bone_rest(b)
			var parent_g := tg[p] if p >= 0 else Transform3D.IDENTITY
			var origin := hips_at if b == tgt_hips else rest_local.origin
			var q := rest_local.basis.get_rotation_quaternion()
			if MAP.has(bn):
				var sb := src.bone(MAP[bn])
				var d := sg[sb].basis.get_rotation_quaternion() * src.rest_g[sb].basis.get_rotation_quaternion().inverse()
				var world := (d * (align[bn] as Quaternion) * tgt.rest_g[b].basis.get_rotation_quaternion()).normalized()
				q = (parent_g.basis.get_rotation_quaternion().inverse() * world).normalized()
				if settle > 0.0 and (bn.ends_with("Leg") or bn.ends_with("Foot") or bn.ends_with("ToeBase")):
					q = q.slerp(rest_local.basis.get_rotation_quaternion(), settle)
				local[b] = q
			tg[b] = parent_g * Transform3D(Basis(q), origin)
		take.poses.append(local)
		take.hips.append(hips_at)
	if opt.get("inplace", false):
		# The hips' horizontal travel over the clip comes out: start to end along a line.
		var a0 := take.hips[0]
		var a1 := take.hips[take.frames]
		for f in take.frames + 1:
			var drift := a0.lerp(a1, float(f) / take.frames) - tgt.rest_g[tgt_hips].origin
			take.hips[f] -= Vector3(drift.x, 0.0, drift.z)
	if opt.get("ground", true):
		var toes := [tgt.bone("LeftToeBase"), tgt.bone("RightToeBase")]
		var low := INF
		for f in take.frames + 1:
			for toe in toes:
				low = minf(low, _pose_global(tgt, take.poses[f], take.hips[f], toe).origin.y)
		var rest_toe := minf(tgt.rest_g[toes[0]].origin.y, tgt.rest_g[toes[1]].origin.y)
		for f in take.frames + 1:
			take.hips[f].y += rest_toe - low
	return take


## The keyed idle variants: the idle take with overlays (see the header).
func _variant(tgt: Rig, idle: Take, name: String, length: float, fps: float) -> Take:
	var take := Take.new()
	take.length = length
	take.frames = maxi(int(round(length * fps)), 1)
	for f in take.frames + 1:
		var t := take.time(f)
		# The idle runs underneath, looped.
		var fi := int(round(fmod(t, idle.length) / idle.length * idle.frames)) % (idle.frames + 1)
		var local: Dictionary = (idle.poses[fi] as Dictionary).duplicate()
		_overlay(tgt, local, idle.hips[fi], _ops(name, t, length))
		take.poses.append(local)
		take.hips.append(idle.hips[fi])
	return take


## A weight envelope through keys [[t, value], ...], eased between them.
static func _env(t: float, keys: Array) -> float:
	if t <= keys[0][0]:
		return keys[0][1]
	for i in range(1, keys.size()):
		if t <= keys[i][0]:
			var u: float = (t - keys[i - 1][0]) / maxf(keys[i][0] - keys[i - 1][0], 1e-5)
			return lerpf(keys[i - 1][1], keys[i][1], smoothstep(0.0, 1.0, u))
	return keys[keys.size() - 1][1]


## The overlay operations for one variant at time t. ["turn", bone, axis, degrees] turns a bone
## about a skeleton-space axis (its children follow); ["aim", bone, direction, weight] swings the
## bone's length toward a skeleton-space direction; ["roll", bone, degrees] turns it about its
## own length. Applied parents first.
func _ops(name: String, t: float, length: float) -> Array:
	var ops := []
	match name:
		"idle_look":
			# A glance over his left shoulder, a longer look right, back.
			var yaw := _env(t, [[0.3, 0.0], [0.9, 38.0], [1.9, 38.0], [2.7, -44.0], [3.8, -44.0], [4.4, 0.0]])
			var pitch := _env(t, [[0.3, 0.0], [0.9, -6.0], [1.9, 4.0], [2.7, -4.0], [3.8, -8.0], [4.4, 0.0]])
			ops.append(["turn", "Spine02", Vector3.UP, yaw * 0.12])
			ops.append(["turn", "Spine", Vector3.UP, yaw * 0.13])
			ops.append(["turn", "neck", Vector3.UP, yaw * 0.35])
			ops.append(["turn", "Head", Vector3.UP, yaw * 0.4])
			ops.append(["turn", "Head", Vector3.RIGHT, pitch])
		"idle_neck":
			# Head over to the right, a snap past it, over to the left, a snap, a roll of the shoulders.
			var roll := _env(t, [[0.2, 0.0], [0.8, -24.0], [0.95, -31.0], [1.3, -22.0], [1.9, 24.0], [2.05, 31.0], [2.4, 22.0], [3.0, 0.0]])
			var shrug := _env(t, [[2.4, 0.0], [2.8, 1.0], [3.3, 0.0]])
			ops.append(["turn", "neck", Vector3.BACK, roll * 0.45])
			ops.append(["turn", "Head", Vector3.BACK, roll * 0.55])
			ops.append(["turn", "Head", Vector3.RIGHT, _env(t, [[0.2, 0.0], [0.8, -10.0], [2.4, -10.0], [3.0, 0.0]])])
			ops.append(["turn", "LeftShoulder", Vector3.BACK, -9.0 * shrug])
			ops.append(["turn", "RightShoulder", Vector3.BACK, 9.0 * shrug])
		"idle_watch":
			# The left wrist comes up in front of the chest, face up; he looks down at it.
			var w := _env(t, [[0.0, 0.0], [0.7, 1.0], [3.2, 1.0], [4.0, 0.0]])
			ops.append(["aim", "LeftArm", Vector3(0.45, -0.72, 0.52), w])
			ops.append(["aim", "LeftForeArm", Vector3(-0.78, 0.22, 0.58), w])
			ops.append(["aim", "LeftHand", Vector3(-0.82, 0.08, 0.56), w])
			ops.append(["roll", "LeftForeArm", -70.0 * w])
			ops.append(["turn", "neck", Vector3.RIGHT, 14.0 * w])
			ops.append(["turn", "Head", Vector3.RIGHT, 20.0 * w])
			ops.append(["turn", "Head", Vector3.UP, 12.0 * w])
		"idle_stretch":
			# The left arm goes up over his head and he leans over to the right with it.
			var w := _env(t, [[0.1, 0.0], [1.0, 1.0], [2.9, 1.0], [3.9, 0.0]])
			var lean := _env(t, [[0.6, 0.0], [1.5, 1.0], [2.6, 1.0], [3.4, 0.0]])
			ops.append(["aim", "LeftArm", Vector3(0.18, 0.98, 0.05), w])
			ops.append(["aim", "LeftForeArm", Vector3(-0.35, 0.94, 0.0), w])
			ops.append(["aim", "LeftHand", Vector3(-0.6, 0.8, 0.0), w])
			ops.append(["turn", "Spine02", Vector3.BACK, 6.0 * lean])
			ops.append(["turn", "Spine01", Vector3.BACK, 7.0 * lean])
			ops.append(["turn", "Spine", Vector3.BACK, 6.0 * lean])
			ops.append(["turn", "Head", Vector3.BACK, -8.0 * lean])
			ops.append(["turn", "Head", Vector3.RIGHT, -10.0 * w])
	return ops


func _overlay(tgt: Rig, local: Dictionary, hips: Vector3, ops: Array) -> void:
	var sk := tgt.sk
	var by_bone := {}
	for op: Array in ops:
		var b := sk.find_bone(op[1])
		if not by_bone.has(b):
			by_bone[b] = []
		by_bone[b].append(op)
	var glob := {}
	for b in tgt.order:
		var p := sk.get_bone_parent(b)
		var rest := sk.get_bone_rest(b)
		var q: Quaternion = local.get(b, rest.basis.get_rotation_quaternion())
		var pg: Transform3D = glob[p] if p >= 0 else Transform3D.IDENTITY
		var g := pg * Transform3D(Basis(q), hips if b == tgt.bone("Hips") else rest.origin)
		if by_bone.has(b):
			for op: Array in by_bone[b]:
				match op[0]:
					"turn":
						g.basis = Basis(op[2] as Vector3, deg_to_rad(op[3])) * g.basis
					"aim":
						var c := sk.find_bone(TGT_CHAIN[op[1]])
						var cur := (g.basis * sk.get_bone_rest(c).origin).normalized()
						var want := (op[2] as Vector3).normalized()
						var full := Basis(Quaternion(cur, want)) * g.basis
						g.basis = Basis(g.basis.get_rotation_quaternion().slerp(full.get_rotation_quaternion(), op[3]))
					"roll":
						var c := sk.find_bone(TGT_CHAIN[op[1]])
						var along := (g.basis * sk.get_bone_rest(c).origin).normalized()
						g.basis = Basis(along, deg_to_rad(op[2])) * g.basis
			local[b] = (pg.basis.get_rotation_quaternion().inverse() * g.basis.get_rotation_quaternion()).normalized()
		glob[b] = g


func _to_animation(tgt: Rig, take: Take, loop: bool, fingers: Dictionary) -> Animation:
	var out := Animation.new()
	out.length = take.length
	out.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var pt := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(pt, NodePath(SKEL_PATH + "Hips"))
	for f in take.frames + 1:
		out.position_track_insert_key(pt, take.time(f), take.hips[f])
	for tn: String in MAP:
		var b := tgt.bone(tn)
		var rt := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(rt, NodePath(SKEL_PATH + tn))
		var prev := Quaternion.IDENTITY
		for f in take.frames + 1:
			var q: Quaternion = take.poses[f][b]
			if f > 0 and prev.dot(q) < 0.0:
				q = -q
			prev = q
			out.rotation_track_insert_key(rt, take.time(f), q)
	# The hero Idle's own hands, held: these clips do not move the fingers.
	for bone_name: String in fingers:
		var rt := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(rt, NodePath(SKEL_PATH + bone_name))
		out.rotation_track_insert_key(rt, 0.0, fingers[bone_name])
		out.rotation_track_insert_key(rt, take.length, fingers[bone_name])
	return out


## The finger keys of the hero's own Idle at its first frame (name -> local rotation).
func _hero_fingers(hero: Node, tgt: Rig) -> Dictionary:
	var out := {}
	var ap: AnimationPlayer = hero.find_children("*", "AnimationPlayer", true, false)[0]
	var idle := ap.get_animation("Idle")
	for b in tgt.sk.get_bone_count():
		var bn := tgt.sk.get_bone_name(b)
		if not ("Hand" in bn and bn.right(1).is_valid_int()):
			continue
		var rt := idle.find_track(NodePath(SKEL_PATH + bn), Animation.TYPE_ROTATION_3D) if idle else -1
		out[bn] = idle.rotation_track_interpolate(rt, 0.0) if rt >= 0 else tgt.sk.get_bone_rest(b).basis.get_rotation_quaternion()
	return out


## How fast an in-place clip's feet move backward while planted (m/s at speed 1): the median of
## the lower foot's backward speed over the frames where it is within 4 cm of the ground.
func _gait_speed(tgt: Rig, take: Take) -> float:
	var speeds := PackedFloat32Array()
	var feet := [tgt.bone("LeftFoot"), tgt.bone("RightFoot")]
	var dt := take.length / take.frames
	var floor_y := INF
	for f in take.frames + 1:
		for foot in feet:
			floor_y = minf(floor_y, _pose_global(tgt, take.poses[f], take.hips[f], foot).origin.y)
	for f in take.frames:
		for foot in feet:
			var a := _pose_global(tgt, take.poses[f], take.hips[f], foot).origin
			if a.y > floor_y + 4.0:
				continue
			var b := _pose_global(tgt, take.poses[f + 1], take.hips[f + 1], foot).origin
			speeds.append(-(b.z - a.z) / dt)
	if speeds.is_empty():
		return 0.0
	speeds.sort()
	return speeds[speeds.size() / 2] * 0.01 # the rig is in centimetres


func _initialize() -> void:
	var fps := float(OS.get_environment("FPS")) if OS.get_environment("FPS") != "" else 30.0
	var srcs := {}
	for c: Array in CLIPS:
		if not srcs.has(c[0]):
			var node := _load(SRC_DIR + c[0])
			if node == null:
				push_error("HERO_CLIPS missing source %s: run tools/crowd/fetch_life_clips.sh" % c[0])
				quit(1)
				return
			srcs[c[0]] = node
	var hero: Node = (load(HERO) as PackedScene).instantiate()
	var tgt := Rig.new(hero)
	var fingers := _hero_fingers(hero, tgt)
	var lib := AnimationLibrary.new()
	var idle: Take = null
	for c: Array in CLIPS:
		var sroot: Node = srcs[c[0]]
		var src := Rig.new(sroot)
		var ap: AnimationPlayer = sroot.find_children("*", "AnimationPlayer", true, false)[0]
		var take := _retarget(src, tgt, ap.get_animation(c[1]), fps, c[4])
		if c[2] == "idle":
			idle = take
		var clip := _to_animation(tgt, take, c[3], fingers)
		var hy := INF
		var hy_max := -INF
		for h in take.hips:
			hy = minf(hy, h.y)
			hy_max = maxf(hy_max, h.y)
		var gait := ""
		if c[2] == "sprint":
			gait = "  gait %.2f m/s" % _gait_speed(tgt, take)
			clip.set_meta("gait_speed", _gait_speed(tgt, take))
		print("HERO_CLIPS %-11s %5.2f s %3d keys  hips %.0f..%.0f cm (rest %.0f)%s" % [c[2], take.length,
			take.frames + 1, hy, hy_max, tgt.rest_g[tgt.bone("Hips")].origin.y, gait])
		lib.add_animation(c[2], clip)
	for v: Array in VARIANTS:
		var take := _variant(tgt, idle, v[0], v[1], fps)
		var clip := _to_animation(tgt, take, false, fingers)
		if v[2] != Vector2.ZERO:
			clip.set_meta("free_left", v[2])
		print("HERO_CLIPS %-11s %5.2f s %3d keys  (keyed over the idle)" % [v[0], take.length, take.frames + 1])
		lib.add_animation(v[0], clip)
	for name in lib.get_animation_list():
		if OS.get_environment("COMPRESS") != "0":
			lib.get_animation(name).compress()
	var err := ResourceSaver.save(lib, OUT, ResourceSaver.FLAG_COMPRESS)
	print("HERO_CLIPS wrote %s (%s), %d KB, %d finger bones held" % [OUT, error_string(err),
		FileAccess.get_file_as_bytes(OUT).size() / 1024, fingers.size()])
	hero.free()
	for n in srcs.values():
		(n as Node).free()
	quit()
