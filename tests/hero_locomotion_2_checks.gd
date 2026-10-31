extends RefCounted
## The hero's locomotion (HeroLoco + Avatar._drive_loco), for tests/smoke_test.gd's room part:
## the gait modifier runs first in the stack; its sync table matches the clips' own feet; and,
## staged on the real player (its physics paused, Avatar driven a tick at a time): a start fades
## the gait in over the idle (no pop), the walk hands over to the run and the run to the sprint
## by weights that move a little a frame, a stop runs the stride on to a foot down and then fades
## out, a small turn on the spot keeps the feet planted and a big one steps round, the strafe
## turns the hips toward the way he goes with the chest on the aim, a backpedal runs the gait
## backward, a running turn leans into it, a landing at a run dips and runs on (no stop clip),
## and through all of it the right hand stays on the gun's grip. Untyped access, like the rest.

var _t: Node


## Last in the stack: where the right hand ended up against its grip target, each pass.
class HandProbe:
	extends SkeletonModifier3D
	var hand := -1
	var grip: Node3D
	var worst := 0.0
	var live := false

	func _process_modification_with_delta(_d: float) -> void:
		var sk := get_skeleton()
		if not live or sk == null or grip == null or hand < 0:
			return
		var at := sk.to_global(GripHands._chain(sk, hand).origin)
		worst = maxf(worst, at.distance_to(grip.global_position))


func run(t: Node, player: Node3D) -> void:
	_t = t
	var avatar: Node3D = player.get("avatar")
	if avatar == null:
		_check(false, "the hero avatar is there for the locomotion checks")
		return
	var sk: Skeleton3D = avatar.find_child("Skeleton3D", true, false)
	var anim: AnimationPlayer = avatar.find_child("AnimationPlayer", true, false)
	var loco: Node = sk.find_child("HeroLoco", false, false)
	if OS.get_environment("HERO_LOCO") == "0":
		_check(loco == null, "HERO_LOCO=0 builds no locomotion layer")
		return
	_check(loco != null, "the hero has his locomotion layer (HeroLoco)")
	if loco == null:
		return
	_check_stack(sk)
	_check_table(anim, sk)
	player.set_physics_process(false)
	var visual: Node3D = player.get("visual")
	var manager: Node = player.get("weapon_manager")
	var gun: Node = manager.get("current")
	var grip: Node3D = manager.find_child("GripRight", true, false)
	var hand := sk.find_bone("RightHand")
	var dt := 1.0 / 60.0
	visual.rotation.y = 0.0
	avatar.call("debug_reset")
	var probe := HandProbe.new()
	probe.hand = hand
	probe.grip = grip
	sk.add_child(probe)
	var worst_jerk := 0.0
	var worst_w := 0.0
	var worst_at := ""
	var prev_head := Vector3.INF
	var prev_step := Vector3.ZERO
	var head := sk.find_bone("Head")
	var prev_w := PackedFloat32Array([1.0, 0.0, 0.0])
	var w_at := {}
	var weight_early := -1.0
	var weight_settled := 0.0
	# A start, a ramp through walk, run and sprint (3 s), a second at the top, then a stop.
	var speed := 0.0
	var stop_frame := -1
	var stop_phase_weight := 1.0
	var weight_after_stop := 1.0
	var frames := 60 * 6
	for i in frames:
		var tt := i * dt
		if tt < 0.2:
			speed = 0.0
		elif tt < 3.2:
			speed = 12.0 * (tt - 0.2) / 3.0
		elif tt < 4.2:
			speed = 12.0
		else:
			if stop_frame < 0:
				stop_frame = i
			speed = move_toward(speed, 0.0, 70.0 * dt)
		var vel := visual.global_basis * Vector3(0, 0, -speed)
		avatar.call("drive", dt, speed, true, 0.0, false, vel)
		avatar.call("hold_gun", gun, false, dt)
		await _t.get_tree().process_frame
		var w: PackedFloat32Array = loco.get("gait_w")
		for k in 3:
			# What shows: a change in the mix counts as much as the gait is on screen (once it has
			# faded out the gait's speed drops back to standing unseen).
			var seen := absf(w[k] - prev_w[k]) * float(loco.get("weight"))
			if seen > worst_w:
				worst_w = seen
				worst_at = "frame %d speed %.2f %s -> %s" % [i, speed, prev_w, w]
		prev_w = w
		if i == 23: # 0.08 s after the speed passes 0.4 m/s
			weight_early = float(loco.get("weight"))
		if tt > 0.6 and tt < 4.2:
			weight_settled = maxf(weight_settled, float(loco.get("weight")))
		for at_speed in [1.0, 4.0, 10.0]:
			if not w_at.has(at_speed) and speed >= at_speed and tt > 0.2:
				w_at[at_speed] = w
		if stop_frame >= 0 and i == stop_frame + 9:
			stop_phase_weight = float(loco.get("weight"))
		weight_after_stop = float(loco.get("weight"))
		var at := sk.get_bone_global_pose(head).origin * 0.01
		if prev_head != Vector3.INF:
			var step := at - prev_head
			if i > 2:
				worst_jerk = maxf(worst_jerk, (step - prev_step).length())
			prev_step = step
		prev_head = at
		probe.live = i > 20
	_check(weight_early > 0.0 and weight_early < 0.9 and weight_settled > 0.99, "a start fades the gait in over the idle (weight %.2f 0.08 s in, %.2f running)" % [weight_early, weight_settled])
	_check(worst_w < 0.12, "walk, run and sprint hand over by weights that move a little a frame (most %.3f, %s)" % [worst_w, worst_at])
	var ok_bands: bool = w_at.has(1.0) and w_at.has(4.0) and w_at.has(10.0)
	if ok_bands:
		ok_bands = (w_at[1.0] as PackedFloat32Array)[0] > 0.5 and (w_at[4.0] as PackedFloat32Array)[1] > 0.5 and (w_at[10.0] as PackedFloat32Array)[2] > 0.5
	_check(ok_bands, "the walk leads at 1 m/s, the run at 4, the sprint at 10 (%s)" % str(w_at))
	_check(stop_phase_weight > 0.5 and weight_after_stop < 0.01, "a stop finishes the stride and then fades the gait out (%.2f after 0.15 s, %.3f at the end)" % [stop_phase_weight, weight_after_stop])
	_check(worst_jerk < 0.03, "the head moves smoothly through start, gait changes and stop: no pop (worst frame-to-frame change %.3f m)" % worst_jerk)
	var worst_hand := probe.worst
	probe.queue_free()
	_check(grip != null and worst_hand < 0.04, "the right hand stays on the gun's grip through all of it (worst %.3f m)" % worst_hand)
	# The stop ends on a foot down.
	var phase: float = loco.get("phase")
	var right: float = loco.call("_right_share")
	var off := minf(minf(absf(fposmod(phase, 1.0)), absf(fposmod(phase, 1.0) - 1.0)), absf(fposmod(phase, 1.0) - right))
	_check(off < 0.02, "the stop's stride ends with a foot on the ground (phase %.3f)" % fposmod(phase, 1.0))
	# Turning on the spot: a little turn keeps the feet planted, a big one steps round.
	avatar.call("debug_reset")
	await _drive(avatar, gun, 10, 0.0, Vector3.ZERO)
	visual.rotation.y = 0.4
	await _drive(avatar, gun, 6, 0.0, Vector3.ZERO)
	var planted_yaw: float = loco.get("hips_yaw")
	var stepped_small: bool = avatar.get("_stepping")
	visual.rotation.y = 1.6
	await _drive(avatar, gun, 3, 0.0, Vector3.ZERO)
	var stepping: bool = avatar.get("_stepping")
	await _drive(avatar, gun, 90, 0.0, Vector3.ZERO)
	var settled_yaw: float = loco.get("hips_yaw")
	_check(not stepped_small and absf(planted_yaw + 0.4) < 0.08, "a small turn on the spot keeps the feet where they were (hips %.2f rad against the body)" % planted_yaw)
	_check(stepping and absf(settled_yaw) < 0.05 and float(loco.get("weight")) < 0.05, "a big turn steps round and settles (stepping %s, hips %.3f after 1.5 s)" % [stepping, settled_yaw])
	# The strafe and the backpedal, facing held on the aim.
	visual.rotation.y = 0.0
	avatar.call("debug_reset")
	var aim_hold: float = player.get("aim_hold_time")
	player.set("aim_hold_time", 1.0e6)
	player.call("notify_fired")
	await _drive(avatar, gun, 40, 5.0, visual.global_basis * Vector3(5, 0, 0))
	var strafe_yaw: float = loco.get("hips_yaw")
	_check(strafe_yaw < -0.8 and not bool(avatar.get("_back")), "strafing right turns the hips right toward the way he goes (%.2f rad)" % strafe_yaw)
	var p0: float = loco.get("phase")
	await _drive(avatar, gun, 40, 5.0, visual.global_basis * Vector3(0, 0, 5))
	var p1: float = loco.get("phase")
	await _drive(avatar, gun, 6, 5.0, visual.global_basis * Vector3(0, 0, 5))
	var p2: float = loco.get("phase")
	_check(bool(avatar.get("_back")) and absf(float(loco.get("hips_yaw"))) < 0.3 and wrapf(p2 - p1, -0.5, 0.5) < 0.0, "moving away from the aim backpedals: the gait runs backward (phase %.2f -> %.2f -> %.2f)" % [p0, p1, p2])
	player.set("aim_hold_time", aim_hold)
	player.set("_aim_timer", 0.0)
	# A running turn leans into it (left turn: the top goes to his left, +roll).
	avatar.call("debug_reset")
	var heading := 0.0
	for i in 60:
		heading += 2.5 * dt
		visual.rotation.y = heading
		avatar.call("drive", dt, 12.0, true, 0.0, false, Basis(Vector3.UP, heading) * Vector3(0, 0, -12))
		avatar.call("hold_gun", gun, false, dt)
	var roll: float = avatar.get("_roll")
	_check(roll > 0.1, "a running turn leans him into it (%.2f rad)" % roll)
	# The land-and-run: no stop clip, a dip, the gait runs on.
	visual.rotation.y = 0.0
	avatar.call("debug_reset")
	await _drive(avatar, gun, 20, 12.0, Vector3(0, 0, -12))
	for i in 15:
		avatar.call("drive", dt, 12.0, false, -40.0, false, Vector3(0, -40, -12))
	avatar.call("landed", 40.0, 12.0)
	var deepest := 0.0
	for i in 12:
		avatar.call("drive", dt, 12.0, true, 0.0, false, Vector3(0, 0, -12))
		deepest = maxf(deepest, float(avatar.get("_dip")))
	_check(not anim.current_animation.begins_with("moves/land") and deepest > 0.02 and float(loco.get("weight")) > 0.8, "a landing at a run dips and runs on (clip %s, dip %.3f m, gait %.2f)" % [anim.current_animation, deepest, loco.get("weight")])
	avatar.call("debug_reset")
	visual.rotation.y = 0.0
	for i in 20:
		avatar.call("hold_gun", gun, false, dt)
	player.set_physics_process(true)


func _drive(avatar: Node, gun: Node, n: int, speed: float, vel: Vector3) -> void:
	for i in n:
		avatar.call("drive", 1.0 / 60.0, speed, true, 0.0, false, vel)
		avatar.call("hold_gun", gun, false, 1.0 / 60.0)
	await _t.get_tree().process_frame


func _check_stack(sk: Skeleton3D) -> void:
	var order := []
	for c in sk.get_children():
		if c is SkeletonModifier3D:
			order.append(str(c.name))
	var a := order.find("HeroLoco")
	var b := order.find("HeroMotion")
	var c := order.find("GunHandsIK")
	_check(a >= 0 and a < b and b < c, "the gait runs first, then HeroMotion, then the gun hands (%s)" % str(order))


## GAITS holds each clip's length and both toes' touchdowns (as shares of the cycle).
func _check_table(anim: AnimationPlayer, sk: Skeleton3D) -> void:
	var bad := []
	for g in HeroLoco.GAITS:
		if not anim.has_animation(g[0]):
			bad.append("%s missing" % g[0])
			continue
		var a := anim.get_animation(g[0])
		var downs: Array = HeroLoco.touchdowns(anim, sk, g[0], 0.01)
		if absf(a.length - float(g[1])) > 0.01:
			bad.append("%s length %.3f" % [g[0], a.length])
		var lefts: Array = g[2]
		var cycle: float = a.length / lefts.size()
		for k in lefts.size():
			# Each left touchdown, and the right one the share later.
			for f in 2:
				var want: float = float(lefts[k]) + (float(g[3]) * cycle if f == 1 else 0.0)
				var near := INF
				for d: float in downs[f]:
					near = minf(near, absf(wrapf(d - want, -a.length * 0.5, a.length * 0.5)))
				if near > (0.04 if f == 0 else 0.12):
					bad.append("%s %s down near %.3f: %s" % [g[0], ["left", "right"][f], want, downs[f]])
	anim.play("Idle", 0.0)
	_check(bad.is_empty(), "HeroLoco's sync table matches the gait clips' own feet %s" % str(bad))


func _check(ok: bool, label: String) -> void:
	_t.call("_check", ok, label)
