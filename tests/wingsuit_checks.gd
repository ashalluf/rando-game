extends RefCounted
## The wingsuit (scripts/player/wingsuit.gd + wingsuit_fx.gd), for tests/smoke_test.gd's test-room
## part, on the real player with real physics and simulated input: the action is mapped; it will
## not open on the ground or without air under him; the key spreads it high up, and so does
## holding jump on the way down; trimmed it glides (flat speed well over the sink, a glide ratio
## over two), the hero's spread pose, the fabric and no gun; diving gains speed, pulling up trades
## it for height, a bank turns him the way it leans; the wingtips lay vapour at speed; jump folds
## it; and on the ground a slow touch-down runs out while a fast one skids to a stop. Untyped
## access throughout (the suit uses the Sfx autoload).

var _t: Node
var _tree: SceneTree


func run(t: Node, player: CharacterBody3D) -> void:
	_t = t
	_tree = t.get_tree()
	var w: Node = player.get("wingsuit")
	_check(InputMap.has_action("wingsuit"), "the wingsuit action is in the input map")
	_check(w != null, "the player has a wingsuit")
	if w == null:
		return
	var avatar: Node = player.get("avatar")
	var sk: Skeleton3D = avatar.find_child("Skeleton3D", true, false) if avatar else null
	var motion: Node = sk.find_child("HeroMotion", false, false) if sk else null
	var fx: Node = w.get_node("WingsuitFx")
	var manager: Node3D = player.get("weapon_manager")
	# The suit's camera chase turns the view; the checks after these aim along it.
	var rig: Node3D = player.get_node("CameraRig")
	var look := Vector2(rad_to_deg(rig.rotation.y), rad_to_deg(rig.rotation.x))
	var visual_yaw: float = (player.get_node("Visual") as Node3D).rotation.y
	await _ticks(10)
	_check(player.is_on_floor() and not bool(w.call("can_open")), "no wingsuit on the ground")
	await _press("wingsuit")
	_check(not bool(w.call("is_active")), "the key on the ground does nothing")

	# High over the room: the key spreads it.
	var start: Vector3 = player.global_position
	await _drop(player, Vector3(start.x, 320.0, start.z), Vector3(0.0, -6.0, -24.0))
	await _press("wingsuit")
	_check(bool(w.call("is_gliding")), "the key spreads the wingsuit in the air")
	# Trimmed for three seconds.
	w.call("force_input", Vector2.ZERO)
	await _ticks(180)
	var v: Vector3 = player.velocity
	var flat := Vector2(v.x, v.z).length()
	_check(bool(w.call("is_gliding")) and flat > 25.0 and -v.y < flat * 0.5 and -v.y > 0.5,
		"trimmed, he glides (%.1f m/s across, %.1f down: a glide ratio of %.1f)" % [flat, -v.y, flat / maxf(-v.y, 0.01)])
	var trim_speed := v.length()
	_check(motion != null and float(motion.get("glide")) > 0.95, "the hero spreads out in the glide pose (%.2f)" % (float(motion.get("glide")) if motion else -1.0))
	var head_up: float = ((avatar as Node3D).basis.orthonormalized() * Vector3.UP).y
	_check(head_up < 0.45, "gliding lays him out along the flight (head axis up %.2f)" % head_up)
	var mesh: ArrayMesh = fx.call("fabric_mesh")
	var verts := mesh.surface_get_array_len(0) if mesh.get_surface_count() > 0 else 0
	_check(bool(fx.call("fabric_shown")) and verts > 100, "the fabric is drawn between the arms, the body and the legs (%d vertices)" % verts)
	_check(not manager.visible, "the gun is put away while he glides")
	# Dive for two seconds: speed.
	w.call("force_input", Vector2(0.0, -1.0))
	await _ticks(120)
	var dive_speed: float = player.velocity.length()
	_check(dive_speed > trim_speed + 15.0, "diving gains speed (%.1f -> %.1f m/s)" % [trim_speed, dive_speed])
	_check(bool(fx.call("is_trailing")), "the wingtips lay vapour at %.0f m/s" % dive_speed)
	# Pull up: the speed buys height.
	w.call("force_input", Vector2(0.0, 1.0))
	var climbed := false
	for i in 150:
		await _tree.physics_frame
		climbed = climbed or player.velocity.y > 1.0
	_check(climbed and player.velocity.length() < dive_speed, "pulling up out of the dive climbs and bleeds the speed (%.1f m/s now)" % player.velocity.length())
	# A bank to the right turns right.
	w.call("force_input", Vector2.ZERO)
	await _ticks(90)
	var h0: float = w.get("heading")
	w.call("force_input", Vector2(1.0, 0.0))
	await _ticks(90)
	var turned := wrapf(float(w.get("heading")) - h0, -PI, PI)
	_check(turned < -0.3 and float(w.get("bank")) > 0.5, "banking right turns him right (%.0f degrees in 1.5 s)" % rad_to_deg(-turned))
	w.call("force_input", Vector2.ZERO)
	# Jump folds it.
	await _press("jump")
	_check(not bool(w.call("is_active")), "jump folds the suit away")
	await _ticks(20)
	_check(manager.visible, "the gun is back in his hand")

	# Holding jump on the way down spreads it.
	await _drop(player, Vector3(start.x, 200.0, start.z), Vector3(0.0, -10.0, -5.0))
	Input.action_press("jump")
	var opened := false
	for i in 60:
		await _tree.physics_frame
		if bool(w.call("is_gliding")):
			opened = true
			break
	Input.action_release("jump")
	_check(opened, "holding jump on the way down spreads the suit")
	await _press("wingsuit")
	_check(not bool(w.call("is_active")), "the key folds it again")

	# Landings, down a lane with nothing in it.
	var lane := _clear_lane(player, start)
	_check(lane != Vector3.ZERO, "found a clear lane in the room for the landings")
	if lane == Vector3.ZERO:
		rig.call("set_look", look.x, look.y)
		return
	# Slow and low: he runs it out.
	await _drop(player, start + Vector3.UP * 9.0, lane * 14.0 + Vector3.DOWN * 3.0)
	w.call("open")
	var ran := false
	for i in 900:
		await _tree.physics_frame
		if player.is_on_floor() and not bool(w.call("is_active")):
			ran = true
			break
	var after := Vector2(player.velocity.x, player.velocity.z).length()
	_check(ran and after <= float(w.get("run_out_keep")) + 0.5, "a slow touch-down runs out (on foot at %.1f m/s)" % after)
	await _ticks(60)
	# Fast: he skids to a stop.
	await _drop(player, start + Vector3.UP * 10.0, lane * 62.0 + Vector3.DOWN * 4.0)
	w.call("open")
	var skidded := false
	for i in 900:
		await _tree.physics_frame
		if int(w.get("state")) == 2:
			skidded = true
		if skidded and not bool(w.call("is_active")):
			break
	var left := Vector2(player.velocity.x, player.velocity.z).length()
	_check(skidded and not bool(w.call("is_active")) and left < 10.0, "a fast touch-down skids to a stop (%.1f m/s left)" % left)
	w.call("force_input", Vector2.INF)
	player.global_position = start
	player.velocity = Vector3.ZERO
	rig.call("set_look", look.x, look.y)
	(player.get_node("Visual") as Node3D).rotation.y = visual_yaw
	await _ticks(30)
	_check(not bool(w.call("is_active")) and absf(float(rig.get("camera_distance")) - 6.5) < 0.01, "the suit is off and the camera back to its own distance")


## Puts him somewhere with a velocity, his physics running.
func _drop(player: CharacterBody3D, at: Vector3, vel: Vector3) -> void:
	for i in 2:
		player.global_position = at
		player.velocity = vel
		await _tree.physics_frame


## A level heading from `start` where a man-sized sphere 2-16 m up meets nothing for 140 m.
func _clear_lane(player: CharacterBody3D, start: Vector3) -> Vector3:
	var space := player.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 1.5
	for k in 24:
		var a := TAU * k / 24.0
		var dir := Vector3(sin(a), 0.0, cos(a))
		var clear := true
		for h in [2.0, 9.0, 16.0, 22.0]:
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = shape
			q.transform = Transform3D(Basis(), start + Vector3.UP * h)
			q.motion = dir * 140.0
			q.collision_mask = 1 | 4
			q.exclude = [player.get_rid()]
			var r := space.cast_motion(q)
			if r.is_empty() or r[0] < 1.0:
				clear = false
				break
		if clear:
			return dir
	return Vector3.ZERO


func _press(action: String) -> void:
	Input.action_press(action)
	await _tree.physics_frame
	await _tree.physics_frame
	Input.action_release(action)
	await _tree.physics_frame


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _check(ok: bool, what: String) -> void:
	_t.call("_check", ok, what)
