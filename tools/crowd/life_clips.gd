extends SceneTree
## Retargets the crowd's everyday clips (talking, the phone, sitting down on a bench, folded arms,
## a drink, a nod, a jog, ...) from Quaternius' Universal Animation Library 1 and 2 (CC0, see
## docs/ASSETS.md) onto each crowd rig, and writes one AnimationLibrary per rig to
## assets/models/crowd_life/<rig>_life.res. Pedestrian adds it to the rig's AnimationPlayer as the
## "life" library (CrowdLife.library()).
##
## Done here in Godot rather than in Blender (tools/hero/retarget_lib.py) because the glTF
## importer in Blender re-orients bones, and a clip exported from that skeleton is relative to
## different bone frames than the ones the game imported. Here both skeletons are exactly what
## the game sees.
##
## The method is retarget_lib's, in skeleton space (both rigs face +Z, Y up; the crowd is in cm,
## the library in m): for every mapped bone, the source's change of world rotation from its own
## rest, applied to the target's rest turned so its bone points where the source's did at rest:
##   R = (src_pose * src_rest^-1) * align * tgt_rest,  align = arc(tgt rest dir -> src rest dir)
## then handed down the chain as local rotations. So neither rest pose has to match the other:
## the library's T-pose and the crowd's lowered-arm bind both come out as the motion the
## animator keyed (the lesson of Pedestrian.fix_arm_pose(), which this never needs). The hips
## move by the source's pelvis offset scaled by the ratio of hip heights, and each clip is set
## on the ground: lowered so the lowest a ball of the foot gets over the clip is its rest height.
##
## Fetch the sources first (tools/crowd/fetch_life_clips.sh puts them in build/ual_src), then:
##   godot --headless --path . -s tools/crowd/life_clips.gd
## RIGS=crowd_a,crowd_b limits it; FPS (default 20) is the key rate written.

const SRC_DIR := "res://build/ual_src/"
const OUT_DIR := "res://assets/models/crowd_life/"

## [source file, source clip, our name, loop, leg swing, leg settle]. Our names are CrowdLife's. The leg swing
## scales the legs' rotation about their mean over the clip: the library's jog is authored at
## ~5.7 m/s (a 2.6 m step), so a 3 m/s jogger's legs turned over in slow motion; at 0.55 the
## stride is a jogger's and the clip's own speed is ~3.2 m/s (tools/crowd/clip_probe.tscn).
## The settle turns the standing clips' legs that far back toward the rig's own rest (as
## retarget_lib's settle_legs does for the crowd's idle): the library stands every idle in a
## wide, knee-bent stance with one foot forward, a game character's ready stance, which on a
## pavement read as somebody about to fight.
const CLIPS := [
	["UAL1_Standard.glb", "Idle_Loop", "idle", true, 1.0, 0.6],
	["UAL1_Standard.glb", "Idle_Talking_Loop", "talk", true, 1.0, 0.6],
	["UAL1_Standard.glb", "Sitting_Enter", "sit_down", false],
	["UAL1_Standard.glb", "Sitting_Idle_Loop", "sit", true],
	["UAL1_Standard.glb", "Sitting_Talking_Loop", "sit_talk", true],
	["UAL1_Standard.glb", "Sitting_Exit", "stand_up", false],
	["UAL1_Standard.glb", "Jog_Fwd_Loop", "jog", true, 0.55],
	["UAL1_Standard.glb", "Idle_Torch_Loop", "hold", true],
	["UAL2_Standard.glb", "Idle_TalkingPhone_Loop", "phone", true, 1.0, 0.6],
	["UAL2_Standard.glb", "Idle_FoldArms_Loop", "fold", true, 1.0, 0.6],
	["UAL2_Standard.glb", "Consume", "drink", false, 1.0, 0.6],
	["UAL2_Standard.glb", "Yes", "nod", false, 1.0, 0.6],
	["UAL2_Standard.glb", "Idle_No_Loop", "shake", true, 1.0, 0.6],
	["UAL2_Standard.glb", "Idle_Rail_Loop", "rail", true],
]

## Crowd bone <- library bone.
const MAP := {
	"Hips": "pelvis", "Spine02": "spine_01", "Spine01": "spine_02", "Spine": "spine_03",
	"neck": "neck_01", "Head": "Head",
	"LeftShoulder": "clavicle_l", "LeftArm": "upperarm_l", "LeftForeArm": "lowerarm_l", "LeftHand": "hand_l",
	"RightShoulder": "clavicle_r", "RightArm": "upperarm_r", "RightForeArm": "lowerarm_r", "RightHand": "hand_r",
	"LeftUpLeg": "thigh_l", "LeftLeg": "calf_l", "LeftFoot": "foot_l", "LeftToeBase": "ball_l",
	"RightUpLeg": "thigh_r", "RightLeg": "calf_r", "RightFoot": "foot_r", "RightToeBase": "ball_r",
}
## The child whose head gives a bone's direction, per rig (a bone missing here uses its own +Y,
## which is how both rigs' Blender exports lay a bone along its length).
const TGT_CHAIN := {
	"Hips": "Spine02", "Spine02": "Spine01", "Spine01": "Spine", "Spine": "neck", "neck": "Head",
	"Head": "head_end",
	"LeftShoulder": "LeftArm", "LeftArm": "LeftForeArm", "LeftForeArm": "LeftHand",
	"RightShoulder": "RightArm", "RightArm": "RightForeArm", "RightForeArm": "RightHand",
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


func _load(path: String) -> Node:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), st) != OK:
		return null
	return doc.generate_scene(st)


## The source skeleton's global pose for every bone at time t of `a`.
func _src_pose(src: Rig, a: Animation, t: float) -> Array[Transform3D]:
	var g: Array[Transform3D] = []
	g.resize(src.sk.get_bone_count())
	for b in src.order:
		var rest := src.sk.get_bone_rest(b)
		var name := src.sk.get_bone_name(b)
		var path := NodePath("Armature/Skeleton3D:" + name)
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


func _retarget(src: Rig, tgt: Rig, a: Animation, name: String, loop: bool, fps: float, swing: float, settle: float) -> Animation:
	var tsk := tgt.sk
	var align := {}
	for tn: String in MAP:
		var sn: String = MAP[tn]
		align[tn] = Quaternion(tgt.dir(tn, TGT_CHAIN), src.dir(sn, SRC_CHAIN))
	var src_hips := src.bone("pelvis")
	var tgt_hips := tgt.bone("Hips")
	var k := tgt.rest_g[tgt_hips].origin.y / src.rest_g[src_hips].origin.y
	var frames := maxi(int(round(a.length * fps)), 1)
	var poses: Array = [] # per frame: {bone: local quat}, hips origin
	var hips_pos: Array[Vector3] = []
	var toe_low := INF
	var toes := [tgt.bone("LeftToeBase"), tgt.bone("RightToeBase")]
	for f in frames + 1:
		var t := minf(a.length * f / frames, a.length)
		var sg := _src_pose(src, a, t)
		var tg: Array[Transform3D] = []
		tg.resize(tsk.get_bone_count())
		var local := {}
		for b in tgt.order:
			var bn := tsk.get_bone_name(b)
			var p := tsk.get_bone_parent(b)
			var rest_local := tsk.get_bone_rest(b)
			var parent_g := tg[p] if p >= 0 else Transform3D.IDENTITY
			var origin := rest_local.origin
			if b == tgt_hips:
				var off := sg[src_hips].origin - src.rest_g[src_hips].origin
				origin = tgt.rest_g[b].origin + off * k
			var q := rest_local.basis.get_rotation_quaternion()
			if MAP.has(bn):
				var sb := src.bone(MAP[bn])
				var d := sg[sb].basis.get_rotation_quaternion() * src.rest_g[sb].basis.get_rotation_quaternion().inverse()
				var world := (d * (align[bn] as Quaternion) * tgt.rest_g[b].basis.get_rotation_quaternion()).normalized()
				q = (parent_g.basis.get_rotation_quaternion().inverse() * world).normalized()
				if settle > 0.0 and bn.ends_with("Leg") or settle > 0.0 and bn.ends_with("Foot") or settle > 0.0 and bn.ends_with("ToeBase"):
					q = q.slerp(rest_local.basis.get_rotation_quaternion(), settle)
				local[b] = q
			tg[b] = parent_g * Transform3D(Basis(q), origin)
		if OS.get_environment("DEBUG") != "" and f == frames / 2:
			for pair in [["LeftArm", "LeftForeArm", "upperarm_l", "lowerarm_l"], ["LeftForeArm", "LeftHand", "lowerarm_l", "hand_l"], ["LeftShoulder", "LeftArm", "clavicle_l", "upperarm_l"], ["Spine", "neck", "spine_03", "neck_01"], ["RightUpLeg", "RightLeg", "thigh_r", "calf_r"]]:
				var td := (tg[tgt.bone(pair[1])].origin - tg[tgt.bone(pair[0])].origin).normalized()
				var sd := (sg[src.bone(pair[3])].origin - sg[src.bone(pair[2])].origin).normalized()
				print("  DBG %s %s tgt %s src %s" % [name, pair[0], td.snapped(Vector3.ONE * 0.01), sd.snapped(Vector3.ONE * 0.01)])
		for toe in toes:
			toe_low = minf(toe_low, tg[toe].origin.y)
		poses.append(local)
		hips_pos.append(tgt.rest_g[tgt_hips].origin + (sg[src_hips].origin - src.rest_g[src_hips].origin) * k)
	if swing < 1.0:
		_scale_legs(tgt, poses, hips_pos, swing)
		toe_low = INF
		for f in frames + 1:
			for toe in toes:
				toe_low = minf(toe_low, _pose_global(tgt, poses[f], hips_pos[f], toe).origin.y)
	var rest_toe := minf(tgt.rest_g[toes[0]].origin.y, tgt.rest_g[toes[1]].origin.y)
	var dz := rest_toe - toe_low
	var out := Animation.new()
	out.length = a.length
	out.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var hips_path := NodePath("Armature/Skeleton3D:Hips")
	var pt := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(pt, hips_path)
	for f in frames + 1:
		out.position_track_insert_key(pt, minf(a.length * f / frames, a.length), hips_pos[f] + Vector3(0.0, dz, 0.0))
	for tn: String in MAP:
		var b := tgt.bone(tn)
		var rt := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(rt, NodePath("Armature/Skeleton3D:" + tn))
		var prev := Quaternion.IDENTITY
		for f in frames + 1:
			var q: Quaternion = poses[f][b]
			if f > 0 and prev.dot(q) < 0.0:
				q = -q
			prev = q
			out.rotation_track_insert_key(rt, minf(a.length * f / frames, a.length), q)
	print("LIFE %-8s %-10s %5.2f s %3d keys  hips %.0f cm (rest %.0f), grounding %+.1f cm" % [
		tgt.root.name, name, a.length, frames + 1, (hips_pos[frames / 2] + Vector3(0, dz, 0)).y,
		tgt.rest_g[tgt_hips].origin.y, dz])
	return out


## Each leg bone's rotation pulled toward its mean over the clip, by 1 - `swing`.
func _scale_legs(tgt: Rig, poses: Array, hips_pos: Array[Vector3], swing: float) -> void:
	for side in ["Left", "Right"]:
		for part in ["UpLeg", "Leg", "Foot", "ToeBase"]:
			var b := tgt.bone(side + part)
			var sum := Vector4.ZERO
			var first: Quaternion = poses[0][b]
			for f in poses.size():
				var q: Quaternion = poses[f][b]
				if first.dot(q) < 0.0:
					q = -q
				sum += Vector4(q.x, q.y, q.z, q.w)
			sum = sum.normalized()
			var mean := Quaternion(sum.x, sum.y, sum.z, sum.w)
			for f in poses.size():
				poses[f][b] = mean.slerp(poses[f][b], swing)


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


func _initialize() -> void:
	var fps := float(OS.get_environment("FPS")) if OS.get_environment("FPS") != "" else 20.0
	var only := OS.get_environment("RIGS").split(",", false)
	var srcs := {}
	for c: Array in CLIPS:
		if not srcs.has(c[0]):
			var node := _load(SRC_DIR + c[0])
			if node == null:
				push_error("LIFE missing source %s: run tools/crowd/fetch_life_clips.sh" % c[0])
				quit(1)
				return
			srcs[c[0]] = node
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var rigs: Array[String] = []
	for f in DirAccess.get_files_at("res://assets/models/"):
		if f.begins_with("crowd_") and f.ends_with(".glb") and (only.is_empty() or f.get_basename() in only):
			rigs.append(f.get_basename())
	rigs.sort()
	for rig in rigs:
		var inst: Node = (load("res://assets/models/%s.glb" % rig) as PackedScene).instantiate()
		inst.name = rig
		var tgt := Rig.new(inst)
		var lib := AnimationLibrary.new()
		for c: Array in CLIPS:
			var sroot: Node = srcs[c[0]]
			var src := Rig.new(sroot)
			var ap: AnimationPlayer = sroot.find_children("*", "AnimationPlayer", true, false)[0]
			var clip := _retarget(src, tgt, ap.get_animation(c[1]), c[2], c[3], fps, c[4] if c.size() > 4 else 1.0, c[5] if c.size() > 5 else 0.0)
			# Godot's own compression (quantised, paged): a third of the memory (6.2 -> 2.0 MB for the twelve rigs), and playback
			# and *_track_interpolate() read it the same. COMPRESS=0 keeps the plain keys.
			if OS.get_environment("COMPRESS") != "0":
				clip.compress()
			lib.add_animation(c[2], clip)
		var path := OUT_DIR + rig + "_life.res"
		var err := ResourceSaver.save(lib, path, ResourceSaver.FLAG_COMPRESS)
		print("LIFE wrote %s (%s), %d KB" % [path, error_string(err), FileAccess.get_file_as_bytes(path).size() / 1024])
		inst.free()
	for n in srcs.values():
		(n as Node).free()
	quit()
