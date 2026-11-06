extends SceneTree
## Seats the hero's hands on each gun by measurement, not by eye (the hand IK and finger curl
## run headless, so this needs no renderer and no screenshots).
##
##   godot --headless --path . --script tools/grip_fit.gd                  report every gun
##   WEAPON=0 FIT=1 godot --headless --path . --script tools/grip_fit.gd   fit the AK's hold
##
## Each gun's grips are described below in its own space (metres, forward -Z, from
## tools/make_weapons.py): the pistol grip or stock wrist as a raked elliptical cylinder, the
## trigger face, and what the support hand holds (the AK's lower handguard, the shotgun's pump,
## the launcher's fore grip). The score asks for what a real grip looks like: the palm flat on
## the grip's side, the middle, ring and little fingers closed round its front and touching it
## all the way, the index finger's pad on the trigger, the thumb round the far side, no finger
## inside the gun. FIT=1 walks the wrist targets, the hand directions and the per-gun finger
## curls downhill on that score and prints the numbers to paste into the gun's _init().
## AIM=0 fits the hip carry instead of the raised gun. POSE_OUT=pose_%d.json writes the final
## pose (every bone in skeleton space, rest and posed) and the gun model's place in it, for
## tools/hero/render.py --pose, which renders the same hold in Cycles.

const GRIPS := {
	# AKM: the bakelite grip raked 20 degrees; the lower handguard held from underneath.
	0: {"grip_top": Vector3(0.0, -0.030, 0.040), "grip_axis": Vector3(0.0, -0.940, 0.342), "grip_len": 0.106,
		"grip_hw": 0.0143, "grip_hd": 0.0215, "trigger": Vector3(0.0, -0.047, -0.006),
		"fore": "rail", "fore_a": Vector3(0.0, 0.004, -0.245), "fore_b": Vector3(0.0, 0.004, -0.385), "fore_hw": 0.025, "fore_hh": 0.032,
		# the butt plate's middle, seated in the pocket in front of the shoulder joint
		"butt": Vector3(0.0, -0.05, 0.33), "seat": Vector3(-0.03, -0.02, 0.06)},
	# The launcher: a pistol grip raked 14 degrees, a vertical fore grip raked 6 degrees forward.
	1: {"grip_top": Vector3(0.0, 0.030, -0.002), "grip_axis": Vector3(0.0, -0.970, 0.242), "grip_len": 0.102,
		"grip_hw": 0.014, "grip_hd": 0.021, "trigger": Vector3(0.0, 0.016, -0.026),
		"fore": "grip", "fore_top": Vector3(0.0, 0.047, -0.237), "fore_axis": Vector3(0.0, -0.9945, -0.1045), "fore_len": 0.092,
		"fore_hw": 0.0135, "fore_hd": 0.017,
		# the rear heat shield's underside (tube axis 80 mm up, shield radius 41 mm), resting on
		# top of the shoulder between the joint and the neck
		"butt": Vector3(0.0, 0.039, 0.15), "seat": Vector3(-0.04, 0.07, 0.0)},
	# The pump gun: the stock's semi-pistol grip (the wrist of the stock), and the pump.
	2: {"grip_top": Vector3(0.0, -0.012, 0.092), "grip_axis": Vector3(0.0, -0.80, 0.60), "grip_len": 0.075,
		"grip_hw": 0.015, "grip_hd": 0.021, "trigger": Vector3(0.0, -0.044, 0.010),
		"fore": "rail", "fore_a": Vector3(0.0, -0.020, -0.215), "fore_b": Vector3(0.0, -0.020, -0.420), "fore_hw": 0.0225, "fore_hh": 0.0225,
		"butt": Vector3(0.0, -0.06, 0.36), "seat": Vector3(-0.03, -0.02, 0.06)},
}
const FINGERS := ["Index", "Middle", "Ring", "Pinky"]

var player: Node3D
var manager: Node
var sk: Skeleton3D
var gun: Node3D # a Weapon; not typed as one (autoloads do not exist when a SceneTree script compiles)
var g: Dictionary


func _initialize() -> void:
	var stage := Node3D.new()
	get_root().add_child(stage)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	stage.add_child(player)
	for i in 6:
		await process_frame
	manager = player.get("weapon_manager")
	sk = player.find_child("Skeleton3D", true, false)
	sk.skeleton_updated.connect(_capture)
	var only := OS.get_environment("WEAPON")
	for w in [0, 1, 2]:
		if only != "" and not (str(w) in only.split(",")): # WEAPON=2 or WEAPON=1,2
			continue
		manager.equip(w)
		gun = manager.get("current")
		g = GRIPS[w]
		if OS.get_environment("AIM") != "0":
			player.set("aim_hold_time", 1.0e6)
			player.notify_fired()
		# Long enough for the raise (Avatar.raise_speed) to finish: three frames measured the
		# gun a third of the way up, and every report read as if the fit had not been pasted.
		await _settle(int(OS.get_environment("SETTLE")) if OS.get_environment("SETTLE") != "" else 30)
		print("== ", gun.display_name, " (", "aimed" if OS.get_environment("AIM") != "0" else "hip", ")")
		if OS.get_environment("TRACE") != "":
			# TRACE=frames: how far each wrist is from its target and from its shoulder, over time
			# (WALK=1 walks him forward meanwhile, BOOST=1 runs)
			if OS.get_environment("WALK") == "1":
				Input.action_press("move_forward")
				if OS.get_environment("BOOST") == "1":
					Input.action_press("boost")
			for i in int(OS.get_environment("TRACE")):
				await _settle(1)
				if i % 5 == 0:
					var line := "   t %3d" % i
					for side in ["Right", "Left"]:
						var target: Node3D = manager.get_node("Grip" + side)
						var hand := _local(side + "Hand")
						var aim := _cap_gun.affine_inverse() * (_cap_targets.get("Grip" + side, target.global_position) as Vector3)
						line += "  %s miss %5.1f mm, shoulder-target %5.1f cm" % [side, (hand - aim).length() * 1000.0, (_local(side + "Arm") - aim).length() * 100.0]
					var sh: Vector3 = _final.get(sk.find_bone("LeftArm"), Vector3.ZERO) - _final.get(sk.find_bone("RightArm"), Vector3.ZERO)
					var hp: Vector3 = _final.get(sk.find_bone("LeftUpLeg"), Vector3.ZERO) - _final.get(sk.find_bone("RightUpLeg"), Vector3.ZERO)
					line += "  shoulders yaw %.1f tilt %.1f hips yaw %.1f" % [rad_to_deg(atan2(sh.z, sh.x)), rad_to_deg(atan2(sh.y, Vector2(sh.x, sh.z).length())), rad_to_deg(atan2(hp.z, hp.x))]
					var av: Node = player.get("avatar")
					line += "  body yaw %.1f cam yaw %.1f twist %.1f hips %s" % [rad_to_deg((player.get("visual") as Node3D).rotation.y),
						rad_to_deg((player.get("camera_rig") as Node3D).global_rotation.y), rad_to_deg(av.get("_twist").angle),
						str(sk.to_global(sk.get_bone_global_pose(0).origin).snapped(Vector3.ONE * 0.01))]
					print(line)
		_report()
		if OS.get_environment("FIT") == "1":
			# NUDGE_R=dx starts the right hand dx metres across the grip (a fit that reaches
			# round with the fingertips from the wrong side has to be started nearer the palm)
			if OS.get_environment("NUDGE_R") != "":
				_put("grip_right", 0, (gun.get("grip_right") as Vector3).x + float(OS.get_environment("NUDGE_R")))
				await _settle(4)
			await _fit()
			_report()
			_print_values()
		if OS.get_environment("POSE_OUT") != "":
			await _settle()
			_dump(OS.get_environment("POSE_OUT").replace("%d", str(w)), w)
	quit()


## The final pose as JSON: bone transforms in skeleton space (posed and rest, 12 floats each,
## basis columns then origin) and the gun model's transform in the same space.
func _dump(path: String, w: int) -> void:
	var bones := {}
	for b in sk.get_bone_count():
		bones[sk.get_bone_name(b)] = {"pose": _xf(_final_xf.get(b, sk.get_bone_global_pose(b))),
			"rest": _xf(sk.get_bone_global_rest(b))}
	var model: Node3D = gun.get_node_or_null("Model")
	var to_sk := sk.global_transform.affine_inverse()
	var out := {"weapon": w, "glb": ["weapon_ak47", "weapon_rocket_launcher", "weapon_shotgun"][w],
		"bones": bones, "gun": _xf(to_sk * (model.global_transform if model else gun.global_transform)),
		"skeleton_scale": sk.global_transform.basis.get_scale().x}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("wrote ", path)


static func _xf(t: Transform3D) -> Array:
	return [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z,
		t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z]


func _settle(frames: int = 3) -> void:
	for i in frames:
		await physics_frame
		await process_frame


## The final pose, after the IK and GripHands: a modifier's result only exists while the
## skeleton is being skinned, so it is copied out when the skeleton says it is done. Read after
## the frame, get_bone_pose() hands back the animation clip's pose with the arms hanging.
var _final: Dictionary = {}
var _final_xf: Dictionary = {}
## The gun and the wrist targets as they stood at that moment: measured against where they are a
## frame later, a hero walking at 12 m/s missed both grips by 20 cm.
var _cap_gun := Transform3D.IDENTITY
var _cap_targets: Dictionary = {}


func _capture() -> void:
	for b in sk.get_bone_count():
		var t := sk.get_bone_global_pose(b)
		_final_xf[b] = t
		_final[b] = sk.global_transform * t.origin
	if gun and is_instance_valid(gun):
		_cap_gun = gun.global_transform
	for n in ["GripRight", "GripLeft"]:
		var target: Node3D = manager.get_node_or_null(n) if manager else null
		if target:
			_cap_targets[n] = target.global_position


func _local(bone_name: String) -> Vector3:
	var b := sk.find_bone(bone_name)
	var world: Vector3 = _final.get(b, sk.global_transform * _chain(b).origin)
	return _cap_gun.affine_inverse() * world


static func _chain_of(skel: Skeleton3D, bone: int) -> Transform3D:
	var t := skel.get_bone_pose(bone)
	var p := skel.get_bone_parent(bone)
	while p >= 0:
		t = skel.get_bone_pose(p) * t
		p = skel.get_bone_parent(p)
	return t


func _chain(bone: int) -> Transform3D:
	return _chain_of(sk, bone)


func _tip(side: String, finger: String) -> Vector3:
	var a := _local("%sHand%s2" % [side, finger])
	var b := _local("%sHand%s3" % [side, finger])
	return b + (b - a) * 0.85


## Distance from a point to the surface of a raked elliptical cylinder (negative inside) and
## where round it the point is (x: + right side, f: + front).
func _cyl(q: Vector3, top: Vector3, axis: Vector3, length: float, hw: float, hd: float) -> Dictionary:
	var a := axis.normalized()
	var fwd := Vector3.RIGHT.cross(a).normalized() # front of the grip, perpendicular to its axis
	if fwd.z > 0.0:
		fwd = -fwd
	var rel := q - top
	var s := clampf(rel.dot(a), 0.0, length)
	var r := rel - a * rel.dot(a)
	var rx := r.x
	var rf := r.dot(fwd)
	var norm := sqrt((rx / hw) * (rx / hw) + (rf / hd) * (rf / hd))
	var radial := sqrt(rx * rx + rf * rf)
	var d := radial * (1.0 - 1.0 / maxf(norm, 1e-4)) if norm > 1e-4 else -minf(hw, hd)
	var over := rel.dot(a) - s # beyond either end
	if absf(over) > 0.0:
		d = sqrt(d * d + over * over) if d > 0.0 else absf(over)
	return {"d": d, "x": rx, "f": rf, "s": rel.dot(a)}


func _grip(q: Vector3) -> Dictionary:
	return _cyl(q, g.grip_top, g.grip_axis, g.grip_len, g.grip_hw, g.grip_hd)


func _fore(q: Vector3) -> Dictionary:
	if g.fore == "grip":
		return _cyl(q, g.fore_top, g.fore_axis, g.fore_len, g.fore_hw, g.fore_hd)
	# a horizontal rail along -Z: a rounded box section
	var a: Vector3 = g.fore_a
	var b: Vector3 = g.fore_b
	var t := clampf((q.z - a.z) / (b.z - a.z), 0.0, 1.0)
	var c := a.lerp(b, t)
	var rx := q.x - c.x
	var ry := q.y - c.y
	var norm := sqrt((rx / g.fore_hw) * (rx / g.fore_hw) + (ry / g.fore_hh) * (ry / g.fore_hh))
	var radial := sqrt(rx * rx + ry * ry)
	var d := radial * (1.0 - 1.0 / maxf(norm, 1e-4))
	var along := (q.z - a.z) / (b.z - a.z)
	if along < 0.0 or along > 1.0:
		var over := minf(absf(q.z - a.z), absf(q.z - b.z))
		d = sqrt(maxf(d, 0.0) * maxf(d, 0.0) + over * over)
	return {"d": d, "x": rx, "f": ry, "s": along}


## Lower is better. Contact means the finger's bone line sits one finger-radius off the surface.
func score(verbose: bool = false) -> float:
	var e := 0.0
	var notes := []
	const FR := 0.0085 # finger half-thickness round its bones
	# right hand on the pistol grip
	var palm := _local("RightHand").lerp(_local("RightHandMiddle1"), 0.6)
	var pg := _grip(palm)
	# (weighted over the fingers: at 4 the fit reached round the grip with the fingertips and
	# left the palm floating 4 cm off its side)
	e += 12.0 * pow(pg.d - 0.013, 2) + 40.0 * pow(maxf(0.0, 0.008 - pg.d), 2) + 2.0 * pow(maxf(0.0, 0.004 - pg.x), 2)
	notes.append("R palm %.1f mm off the grip, x %+.1f" % [pg.d * 1000.0, pg.x * 1000.0])
	for f in ["Middle", "Ring", "Pinky"]:
		for j in [2, 3]:
			var q := _grip(_local("RightHand%s%d" % [f, j]))
			e += pow(q.d - FR, 2) + 30.0 * pow(maxf(0.0, 0.003 - q.d), 2)
		var t := _grip(_tip("Right", f))
		e += pow(t.d - FR * 0.8, 2) + 2.0 * pow(maxf(0.0, t.x + 0.004), 2) + 30.0 * pow(maxf(0.0, 0.003 - t.d), 2)
		notes.append("R %s tip %.1f mm, x %+.1f" % [f, t.d * 1000.0, t.x * 1000.0])
	# the index pad on the trigger
	var it := _tip("Right", "Index")
	var tt: Vector3 = g.trigger
	e += 3.0 * (it - tt).length_squared()
	notes.append("R index tip %.1f mm from the trigger" % ((it - tt).length() * 1000.0))
	var th := _grip(_tip("Right", "Thumb"))
	e += 4.0 * pow(th.d - FR, 2) + 1.0 * pow(maxf(0.0, th.x + 0.002), 2) + 30.0 * pow(maxf(0.0, 0.003 - th.d), 2)
	notes.append("R thumb tip %.1f mm, x %+.1f" % [th.d * 1000.0, th.x * 1000.0])
	# left hand on the fore end
	var lp := _local("LeftHand").lerp(_local("LeftHandMiddle1"), 0.6)
	var lf := _fore(lp)
	e += 3.0 * pow(lf.d - 0.013, 2) + 40.0 * pow(maxf(0.0, 0.008 - lf.d), 2)
	notes.append("L palm %.1f mm off the fore end" % (lf.d * 1000.0))
	for f in FINGERS:
		for j in [2, 3]:
			var q := _fore(_local("LeftHand%s%d" % [f, j]))
			e += pow(q.d - FR, 2) + 30.0 * pow(maxf(0.0, 0.003 - q.d), 2)
		var t := _fore(_tip("Left", f))
		e += pow(t.d - FR * 0.8, 2) + 30.0 * pow(maxf(0.0, 0.003 - t.d), 2)
		notes.append("L %s tip %.1f mm" % [f, t.d * 1000.0])
	var lt := _fore(_tip("Left", "Thumb"))
	e += 4.0 * pow(lt.d - FR, 2) + 30.0 * pow(maxf(0.0, 0.003 - lt.d), 2)
	notes.append("L thumb tip %.1f mm" % (lt.d * 1000.0))
	# the gun on the body: the butt in the pocket in front of the shoulder joint, the launcher's
	# tube resting on top of the shoulder - measured in the chest's own (bladed) frame
	var bm := _butt_miss() if OS.get_environment("AIM") != "0" else Vector3.ZERO
	e += 8.0 * bm.length_squared()
	notes.append("butt off its seat %s cm (chest right, up, forward)" % str((bm * 100.0).snapped(Vector3.ONE * 0.1)))
	# the wrists must reach: an IK chain that ran out of arm leaves the hand short of its target
	for pair in [["RightHand", "GripRight"], ["LeftHand", "GripLeft"]]:
		var target: Node3D = manager.get_node_or_null(pair[1])
		if target:
			var aim_at := _cap_gun.affine_inverse() * (_cap_targets.get(pair[1], target.global_position) as Vector3)
			var miss := (_local(pair[0]) - aim_at).length()
			# and keep some arm in hand: the walk bobs the shoulders, and a target set at the
			# end of the reach standing still is out of it every other step
			var reach := (_local(str(pair[0]).replace("Hand", "Arm")) - aim_at).length()
			e += 20.0 * pow(maxf(0.0, reach - 0.47), 2)
			e += 2.0 * miss * miss
			notes.append("%s reaches its target within %.1f mm" % [pair[0], miss * 1000.0])
	if verbose:
		for n in notes:
			print("   ", n)
	return e


func _report() -> void:
	print("   score %.6f" % score(true))


## How far the gun's seat point (GRIPS butt: the butt plate, or the launcher's rear heat shield
## underneath) is from where it belongs on the body (GRIPS seat, from the right shoulder joint),
## in the chest's frame: x to his right, y up, z forward. The chest frame comes from the line
## between the shoulder joints, so it turns with the bladed stance.
func _butt_miss() -> Vector3:
	if not g.has("butt"):
		return Vector3.ZERO
	var r: Vector3 = _final.get(sk.find_bone("RightArm"), Vector3.ZERO)
	var l: Vector3 = _final.get(sk.find_bone("LeftArm"), Vector3.ZERO)
	var right := Vector3(r.x - l.x, 0.0, r.z - l.z).normalized()
	var fwd := Vector3.UP.cross(right)
	var p: Vector3 = _cap_gun * (g.butt as Vector3)
	var seat: Vector3 = g.seat
	var want := r + right * seat.x + Vector3.UP * seat.y + fwd * seat.z
	var d := p - want
	return Vector3(d.dot(right), d.y, d.dot(fwd))


# --- the fit: coordinate descent over the gun's hold numbers ---------------------------------------
var params := [
	["grip_right", 0], ["grip_right", 1], ["grip_right", 2],
	["grip_right_fingers", 0], ["grip_right_fingers", 1], ["grip_right_fingers", 2],
	["grip_right_palm", 0], ["grip_right_palm", 1], ["grip_right_palm", 2],
	["grip_left", 0], ["grip_left", 1], ["grip_left", 2],
	["grip_left_fingers", 0], ["grip_left_fingers", 1], ["grip_left_fingers", 2],
	["grip_left_palm", 0], ["grip_left_palm", 1], ["grip_left_palm", 2],
	["curl_right", 0], ["curl_right", 1], ["curl_right", 2],
	["curl_trigger", 0], ["curl_trigger", 1], ["curl_trigger", 2],
	["curl_thumb", 0], ["curl_thumb", 1], ["curl_thumb", 2],
	["curl_left", 0], ["curl_left", 1], ["curl_left", 2],
	["curl_left_thumb", 0], ["curl_left_thumb", 1],
	["thumb_wrap", 0], ["thumb_wrap", 1],
	["hold_twist", 1],
	["hold_aim", 0], ["hold_aim", 1], ["hold_aim", 2],
]
## AIM=0 fits only where the gun is carried, so the grips and curls fitted aimed stay put.
var hip_params := [
	["hold_hip", 0], ["hold_hip", 1], ["hold_hip", 2],
	["hold_hip_rot", 0], ["hold_hip_rot", 1], ["hold_hip_rot", 2],
	["hold_twist", 0],
]


func _step_for(name: String) -> float:
	if name == "hold_hip_rot":
		return 4.0
	if name.begins_with("curl") or name == "hold_twist" or name == "thumb_wrap":
		return 8.0
	if name.ends_with("fingers") or name.ends_with("palm"):
		return 0.15
	return 0.012


func _put(name: String, axis: int, value: float) -> void:
	if name.begins_with("curl"):
		# a joint closes, it does not bend backwards: left free, the launcher's thumbs came out
		# hyperextended 50 degrees
		value = clampf(value, 0.0, 70.0 if name.ends_with("thumb") else 95.0)
	if name == "thumb_wrap":
		value = clampf(value, -70.0, 70.0)
	var v = gun.get(name)
	v[axis] = value
	gun.set(name, v)
	if name == "grip_left" and gun.get("_grip_left_rest") != null:
		gun.set("_grip_left_rest", v) # the shotgun rebuilds grip_left from it every frame (the pump)


func _eval() -> float:
	await _settle(2)
	return score()


func _fit() -> void:
	var best: float = await _eval()
	var scale := 1.0
	for round in (int(OS.get_environment("ROUNDS")) if OS.get_environment("ROUNDS") != "" else 10):
		var improved := false
		for p in (hip_params if OS.get_environment("AIM") == "0" else params):
			var name: String = p[0]
			var axis: int = p[1]
			if gun.get(name) == null:
				continue
			var step := _step_for(name) * scale
			var v0: float = gun.get(name)[axis]
			for dirn in [1.0, -1.0]:
				_put(name, axis, v0 + dirn * step)
				var s: float = await _eval()
				if s < best - 1e-9:
					best = s
					improved = true
					v0 = v0 + dirn * step
					# keep going while it pays: one step a round took ten rounds to move the gun
					# a hand's width
					for k in 8:
						_put(name, axis, v0 + dirn * step)
						s = await _eval()
						if s >= best - 1e-9:
							break
						best = s
						v0 = v0 + dirn * step
					_put(name, axis, v0)
					break
				_put(name, axis, v0)
		print("   round %d score %.6f (step x%.2f)" % [round, best, scale])
		if not improved:
			scale *= 0.5


func _print_values() -> void:
	print("   paste into %s._init():" % gun.get_script().get_global_name())
	for name in ["grip_right", "grip_right_fingers", "grip_right_palm", "grip_left", "grip_left_fingers", "grip_left_palm",
			"curl_right", "curl_trigger", "curl_thumb", "curl_left", "curl_left_thumb", "thumb_wrap", "hold_twist", "hold_aim", "hold_hip", "hold_hip_rot"]:
		var v = gun.get(name)
		if v is Vector2:
			print("\t%s = Vector2(%.0f, %.0f)" % [name, v.x, v.y])
		elif name.begins_with("curl"):
			print("\t%s = Vector3(%.0f, %.0f, %.0f)" % [name, v.x, v.y, v.z])
		else:
			print("\t%s = Vector3(%.3f, %.3f, %.3f)" % [name, v.x, v.y, v.z])
