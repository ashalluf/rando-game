extends "res://tools/crowd/life_clips.gd"
## The crowd's walks (crowd-anim-2): six gaits and a weight-shifting idle per crowd rig, written to
## assets/models/crowd_gait/<rig>_gait.res, which CrowdGait adds to the rig's AnimationPlayer as
## the "gait" library. Everyone used to share one walk clip, and a pavement of people marched.
##
## The sources are Quaternius' Universal Animation Library walks (CC0, the files life_clips.gd
## already uses: tools/crowd/fetch_life_clips.sh), retargeted the same way, then RESTYLED keyed
## (GAITS below) before they are set on the ground:
##   step   the feet's travel fore and aft scaled about each foot's mean (a shorter or longer step)
##   width  each foot moved out (+) or in (-) from the line it walks, metres
##   toe    each foot turned out, degrees
##   bob    the hips' rise and fall scaled about its mean; sway the same for the hips' side to
##          side and the pelvis's roll / yaw (the spine takes the extra roll back, 70 %)
##   lean   the spine pitched forward (degrees, over its three bones), the neck taking 60 % back;
##          head another pitch of the head alone (negative looks down)
##   arms   the arm swing scaled about its mean; arm_out the upper arms out from the body
##          (degrees); elbow more bend at the elbow (degrees)
## and then both legs are solved by two-bone IK onto the feet the restyle asks for (the source's
## feet plus step / width / toe), knees in the plane the clip bent them in, so a planted foot
## stays planted whatever the hips do.
##
## Each clip carries what the game needs as metadata, measured here on the finished keys:
## ground_speed (m/s at speed_scale 1: how fast a planted foot travels backwards, in metres),
## cycles (strides in the clip) and left_down (where the left foot lands, a fraction). The
## library itself carries the rig's phenotype (weight, age, height from crowd_config.json), which
## CrowdGait picks a gait by.
##   godot --headless --path . -s tools/crowd/gait_clips.gd      (RIGS=crowd_a,... limits it)

const GAIT_DIR := "res://assets/models/crowd_gait/"

## [source file, source clip, our name, style, repeat]. Our names are CrowdGait.GAITS'.
const GAITS := [
	["UAL1_Standard.glb", "Walk_Loop", "casual", {}],
	["UAL1_Standard.glb", "Walk_Loop", "brisk", {"step": 1.12, "lean": 4.0, "arms": 1.3, "elbow": 14.0, "bob": 1.1, "head": 2.0}],
	["UAL1_Standard.glb", "Walk_Loop", "amble", {"step": 0.8, "lean": 3.0, "arms": 0.55, "head": -7.0, "sway": 1.2, "bob": 0.75, "arm_out": 2.0}],
	["UAL1_Standard.glb", "Walk_Loop", "heavy", {"step": 0.88, "width": 0.045, "toe": 9.0, "arm_out": 10.0, "sway": 1.7, "lean": -2.5, "bob": 0.7, "arms": 0.85, "head": 3.0}],
	["UAL1_Standard.glb", "Walk_Loop", "light", {"step": 1.04, "width": -0.018, "bob": 1.25, "arms": 1.1, "lean": 1.0, "sway": 1.15}],
	["UAL1_Standard.glb", "Walk_Formal_Loop", "formal", {}],
	# The idle three times over with one slow weight shift onto each foot and back.
	["UAL1_Standard.glb", "Idle_Loop", "idle", {"settle": 0.6, "shift": 0.045, "repeat": 3}],
]

## Laid under every walk's own style (added): the library's walk stoops ~7 degrees and carries
## its forearms half raised, a cartoon's walk; on a pavement it read hunched, and the arms swung
## through the shirt at the armpit.
const WALK_BASE := {"lean": -7.0, "elbow": -16.0, "arm_out": 5.0, "shoulders": 0.85}

var _length := 1.0
var _style := {}
var _measured := {}
var _unit := 0.01


func _initialize() -> void:
	var only := OS.get_environment("RIGS").split(",", false)
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/crowd/crowd_config.json"))
	var srcs := {}
	for g: Array in GAITS:
		if not srcs.has(g[0]):
			var node := _load(SRC_DIR + g[0])
			if node == null:
				push_error("GAIT missing source %s: run tools/crowd/fetch_life_clips.sh" % g[0])
				quit(1)
				return
			srcs[g[0]] = node
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GAIT_DIR))
	var rigs: Array[String] = []
	for f in DirAccess.get_files_at("res://assets/models/"):
		if f.begins_with("crowd_") and f.ends_with(".glb") and (only.is_empty() or f.get_basename() in only):
			rigs.append(f.get_basename())
	rigs.sort()
	for rig in rigs:
		var inst: Node = (load("res://assets/models/%s.glb" % rig) as PackedScene).instantiate()
		inst.name = rig
		var tgt := Rig.new(inst)
		_unit = 1.0
		var n: Node = tgt.sk
		while n != null:
			if n is Node3D:
				_unit *= (n as Node3D).transform.basis.get_scale().y
			n = n.get_parent()
		var lib := AnimationLibrary.new()
		var pheno := {}
		for c: Dictionary in config.characters:
			if c.get("name", "") == rig:
				pheno = c.get("phenotype", {})
		lib.set_meta("weight", float(pheno.get("weight", 0.5)))
		lib.set_meta("age", float(pheno.get("age", 0.5)))
		lib.set_meta("height", float(pheno.get("height", 0.5)))
		lib.set_meta("muscle", float(pheno.get("muscle", 0.5)))
		for g: Array in GAITS:
			var sroot: Node = srcs[g[0]]
			var src := Rig.new(sroot)
			var ap: AnimationPlayer = sroot.find_children("*", "AnimationPlayer", true, false)[0]
			_style = (g[3] as Dictionary).duplicate()
			if String(g[1]).begins_with("Walk"):
				for k: String in WALK_BASE:
					_style[k] = float(_style.get(k, 0.0)) + float(WALK_BASE[k])
			var a := ap.get_animation(g[1])
			if _style.has("repeat"):
				a = _repeat(a, int(_style.repeat))
			_length = a.length
			var clip := _retarget(src, tgt, a, g[2], true, 20.0, 1.0, float(_style.get("settle", 0.0)))
			for k: String in _measured:
				clip.set_meta(k, _measured[k])
			print("GAIT %-8s %-7s speed %.2f m/s  cycles %d  left_down %.2f  length %.2f s" % [rig, g[2],
				float(_measured.get("ground_speed", 0.0)), int(_measured.get("cycles", 0)),
				float(_measured.get("left_down", 0.0)), clip.length])
			if OS.get_environment("COMPRESS") != "0":
				clip.compress()
			lib.add_animation(g[2], clip)
		var path := GAIT_DIR + rig + "_gait.res"
		var err := ResourceSaver.save(lib, path, ResourceSaver.FLAG_COMPRESS)
		print("GAIT wrote %s (%s), %d KB" % [path, error_string(err), FileAccess.get_file_as_bytes(path).size() / 1024])
		inst.free()
	for s in srcs.values():
		(s as Node).free()
	quit()


## `a` played `times` times over as one clip (an idle long enough for a slow weight shift).
func _repeat(a: Animation, times: int) -> Animation:
	var out := Animation.new()
	out.length = a.length * times
	for t in a.get_track_count():
		var nt := out.add_track(a.track_get_type(t))
		out.track_set_path(nt, a.track_get_path(t))
		for k in times:
			for i in a.track_get_key_count(t):
				var time := a.track_get_key_time(t, i) + a.length * k
				if k > 0 and i == 0 and is_zero_approx(a.track_get_key_time(t, i)):
					continue # the seam: the previous copy's last key stands there
				out.track_insert_key(nt, minf(time, out.length), a.track_get_key_value(t, i))
	return out


func _style_hook(tgt: Rig, poses: Array, hips_pos: Array[Vector3], _name: String) -> bool:
	var st := _style
	var changed := false
	var frames := poses.size()
	var hips := tgt.bone("Hips")
	var feet := [tgt.bone("LeftFoot"), tgt.bone("RightFoot")]
	# The feet the source puts down, before anything moves (skeleton space).
	var orig: Array = []
	for f in frames:
		orig.append([_pose_global(tgt, poses[f], hips_pos[f], feet[0]), _pose_global(tgt, poses[f], hips_pos[f], feet[1])])
	var needs_ik := false
	# Hips: bob, sway, the weight shift.
	var bob := float(st.get("bob", 1.0))
	var sway := float(st.get("sway", 1.0))
	var shift := float(st.get("shift", 0.0))
	if absf(bob - 1.0) > 0.001 or absf(sway - 1.0) > 0.001 or shift > 0.0:
		var mean := Vector3.ZERO
		for p in hips_pos:
			mean += p
		mean /= frames
		var qmean := _mean_q(poses, hips)
		for f in frames:
			var p: Vector3 = hips_pos[f]
			p.y = mean.y + (p.y - mean.y) * bob
			p.x = mean.x + (p.x - mean.x) * sway
			var extra := Quaternion.IDENTITY
			if absf(sway - 1.0) > 0.001:
				var old: Quaternion = poses[f][hips]
				var nq := qmean.slerp(old, sway)
				extra = nq * old.inverse()
				poses[f][hips] = nq
			if shift > 0.0:
				# One shift onto each foot over the clip: a slow sine, the pelvis dropping on the
				# free side (a roll about forward), the knee of the free leg softening by the IK.
				var s := sin(TAU * float(f) / float(frames - 1))
				p.x += s * shift / _unit
				p.y -= absf(s) * shift * 0.25 / _unit
				var roll := Quaternion(Vector3(0, 0, 1), -s * 0.07)
				poses[f][hips] = roll * (poses[f][hips] as Quaternion)
				extra = roll * extra
			hips_pos[f] = p
			# The spine takes most of the extra roll back, so the shoulders stay level.
			if not extra.is_equal_approx(Quaternion.IDENTITY):
				_turn_global(tgt, poses[f], hips_pos[f], tgt.bone("Spine02"), Quaternion.IDENTITY.slerp(extra.inverse(), 0.7))
		needs_ik = true
	# Spine lean and the head.
	var lean := deg_to_rad(float(st.get("lean", 0.0)))
	var head := deg_to_rad(float(st.get("head", 0.0)))
	if absf(lean) > 1e-4 or absf(head) > 1e-4:
		for f in frames:
			for b in ["Spine02", "Spine01", "Spine"]:
				_turn_global(tgt, poses[f], hips_pos[f], tgt.bone(b), Quaternion(Vector3(1, 0, 0), lean / 3.0))
			_turn_global(tgt, poses[f], hips_pos[f], tgt.bone("neck"), Quaternion(Vector3(1, 0, 0), -lean * 0.6))
			_turn_global(tgt, poses[f], hips_pos[f], tgt.bone("Head"), Quaternion(Vector3(1, 0, 0), -head))
		changed = true
	# Collarbones toward the rig's rest (Pedestrian.fix_arm_pose()'s lesson: the library hunches
	# them, and the shirt's armhole opened at the front of the shoulder).
	var shoulders := float(st.get("shoulders", 0.0))
	if shoulders > 0.0:
		for b in ["LeftShoulder", "RightShoulder"]:
			var bi := tgt.bone(b)
			var rest := tgt.sk.get_bone_rest(bi).basis.get_rotation_quaternion()
			var m := _mean_q(poses, bi)
			var arm := tgt.bone(b.replace("Shoulder", "Arm"))
			for f in frames:
				# The mean goes most of the way to rest; the clip's own motion about it stays.
				# The upper arm keeps where it points: only the shoulder joint comes down.
				var keep := _pose_global(tgt, poses[f], hips_pos[f], arm).basis.get_rotation_quaternion()
				var dev := m.inverse() * (poses[f][bi] as Quaternion)
				poses[f][bi] = (m.slerp(rest, shoulders) * dev).normalized()
				_set_global(tgt, poses[f], hips_pos[f], arm, keep)
		changed = true
	# Arms: the swing, out from the body, the elbow's bend.
	var arms := float(st.get("arms", 1.0))
	if absf(arms - 1.0) > 0.001:
		for b in ["LeftArm", "RightArm", "LeftForeArm", "RightForeArm"]:
			var bi := tgt.bone(b)
			var m := _mean_q(poses, bi)
			for f in frames:
				poses[f][bi] = m.slerp(poses[f][bi], arms)
		changed = true
	var arm_out := deg_to_rad(float(st.get("arm_out", 0.0)))
	var elbow := deg_to_rad(float(st.get("elbow", 0.0)))
	if absf(arm_out) > 1e-4 or absf(elbow) > 1e-4:
		for f in frames:
			# The rig's left is +X; a turn about +Z (backwards) takes a hanging left arm out.
			_turn_global(tgt, poses[f], hips_pos[f], tgt.bone("LeftArm"), Quaternion(Vector3(0, 0, 1), arm_out))
			_turn_global(tgt, poses[f], hips_pos[f], tgt.bone("RightArm"), Quaternion(Vector3(0, 0, 1), -arm_out))
			for b in ["LeftForeArm", "RightForeArm"]:
				var bi := tgt.bone(b)
				# Bend about the elbow's own hinge: across the upper arm and the forearm.
				var up_g := _pose_global(tgt, poses[f], hips_pos[f], tgt.sk.get_bone_parent(bi))
				var fo_g := _pose_global(tgt, poses[f], hips_pos[f], bi)
				var hand_g := _pose_global(tgt, poses[f], hips_pos[f], tgt.bone(b.replace("ForeArm", "Hand")))
				var u := (fo_g.origin - up_g.origin).normalized()
				var v := (hand_g.origin - fo_g.origin).normalized()
				var hinge := u.cross(v)
				if hinge.length() < 0.05:
					hinge = Vector3(-1, 0, 0) # straight arm: flex forward (the rig faces +Z)
				_turn_global(tgt, poses[f], hips_pos[f], bi, Quaternion(hinge.normalized(), elbow))
		changed = true
	# The feet the gait puts down, and the legs solved onto them.
	var step := float(st.get("step", 1.0))
	var width := float(st.get("width", 0.0)) / _unit
	var toe := deg_to_rad(float(st.get("toe", 0.0)))
	if absf(step - 1.0) > 0.001 or absf(width) > 1e-5 or absf(toe) > 1e-5:
		needs_ik = true
	if needs_ik:
		var zmean := [0.0, 0.0]
		for f in frames:
			for s in 2:
				zmean[s] += (orig[f][s] as Transform3D).origin.z / frames
		for f in frames:
			for s in 2:
				var o: Transform3D = orig[f][s]
				var side := 1.0 if s == 0 else -1.0 # left is +X
				var target := o.origin
				target.z = zmean[s] + (target.z - zmean[s]) * step
				target.x += side * width
				var basis := Basis(Vector3.UP, side * toe) * o.basis
				_solve_leg(tgt, poses[f], hips_pos[f], s, Transform3D(basis, target))
		changed = true
	_measure(tgt, poses, hips_pos)
	return changed


## A bone's rotation turned by `q` in skeleton space (its children follow).
func _turn_global(tgt: Rig, local: Dictionary, hips: Vector3, bone: int, q: Quaternion) -> void:
	var g := _pose_global(tgt, local, hips, bone)
	var p := tgt.sk.get_bone_parent(bone)
	var pg := _pose_global(tgt, local, hips, p).basis.get_rotation_quaternion() if p >= 0 else Quaternion.IDENTITY
	local[bone] = (pg.inverse() * q * g.basis.get_rotation_quaternion()).normalized()


func _set_global(tgt: Rig, local: Dictionary, hips: Vector3, bone: int, q: Quaternion) -> void:
	var p := tgt.sk.get_bone_parent(bone)
	var pg := _pose_global(tgt, local, hips, p).basis.get_rotation_quaternion() if p >= 0 else Quaternion.IDENTITY
	local[bone] = (pg.inverse() * q).normalized()


## Two-bone IK of one leg (0 left, 1 right) onto `goal` (the foot's skeleton-space transform).
func _solve_leg(tgt: Rig, local: Dictionary, hips: Vector3, side: int, goal: Transform3D) -> void:
	var pre := "Left" if side == 0 else "Right"
	var up := tgt.bone(pre + "UpLeg")
	var knee := tgt.bone(pre + "Leg")
	var foot := tgt.bone(pre + "Foot")
	var a := _pose_global(tgt, local, hips, up)
	var k := _pose_global(tgt, local, hips, knee)
	var f := _pose_global(tgt, local, hips, foot)
	var l1 := a.origin.distance_to(k.origin)
	var l2 := k.origin.distance_to(f.origin)
	var to := goal.origin - a.origin
	var d := clampf(to.length(), absf(l1 - l2) + 0.01, (l1 + l2) * 0.9995)
	var dir := to.normalized()
	var pole := (k.origin - a.origin) - dir * (k.origin - a.origin).dot(dir)
	if pole.length_squared() < 1e-6:
		pole = Vector3(0, 0, 1)
	pole = pole.normalized()
	var ca := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var k_new := a.origin + (dir * ca + pole * sqrt(1.0 - ca * ca)) * l1
	_turn_global(tgt, local, hips, up, Quaternion((k.origin - a.origin).normalized(), (k_new - a.origin).normalized()))
	var k2 := _pose_global(tgt, local, hips, knee)
	var f2 := _pose_global(tgt, local, hips, foot)
	_turn_global(tgt, local, hips, knee, Quaternion((f2.origin - k2.origin).normalized(), (a.origin + dir * d - k2.origin).normalized()))
	_set_global(tgt, local, hips, foot, goal.basis.get_rotation_quaternion())


func _mean_q(poses: Array, bone: int) -> Quaternion:
	var first: Quaternion = poses[0][bone]
	var sum := Vector4.ZERO
	for p: Dictionary in poses:
		var q: Quaternion = p[bone]
		if first.dot(q) < 0.0:
			q = -q
		sum += Vector4(q.x, q.y, q.z, q.w)
	sum = sum.normalized()
	return Quaternion(sum.x, sum.y, sum.z, sum.w)


## The finished keys' ground speed, strides and left footfall (into _measured).
func _measure(tgt: Rig, poses: Array, hips_pos: Array[Vector3]) -> void:
	var frames := poses.size()
	var dt := _length / float(frames - 1)
	var bones := [tgt.bone("LeftToeBase"), tgt.bone("RightToeBase")]
	var tot := 0.0
	var time := 0.0
	var left_down := 0.0
	var onsets := 0
	for s in 2:
		var ys := PackedFloat32Array()
		var zs := PackedFloat32Array()
		for f in frames:
			var g := _pose_global(tgt, poses[f], hips_pos[f], bones[s])
			ys.append(g.origin.y)
			zs.append(g.origin.z)
		var ymin: float = Array(ys).min()
		var was := ys[frames - 2] < ymin + 1.5 / (_unit * 100.0)
		for f in frames - 1:
			var low := ys[f] < ymin + 1.5 / (_unit * 100.0)
			if low and ys[f + 1] < ymin + 1.5 / (_unit * 100.0) and zs[f + 1] < zs[f]:
				tot += zs[f] - zs[f + 1]
				time += dt
			if low and not was and s == 0:
				onsets += 1
				if onsets == 1:
					left_down = float(f) / float(frames - 1)
			was = low
	_measured = {
		"ground_speed": (tot / time) * _unit if time > 0.0 else 0.0,
		# The UAL loops hold one stride each (a footfall each foot); the onset count above
		# flickers on a foot that hovers at the threshold, so it is only printed.
		"cycles": 1,
		"onsets": onsets,
		"left_down": left_down,
	}
