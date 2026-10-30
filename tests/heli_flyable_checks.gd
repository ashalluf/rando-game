extends RefCounted
## The flyable helicopter (FlyableHeli, HeliSpot, HeliPads, HeliDownwash), for tests/smoke_test.gd.
## Loaded at run time, not named there, so it compiles after the autoloads.
##
## Static: the wash in the four plant shaders and the global, the heliport's pads on clear apron.
## Then at the airport heliport (a FULL chunk makes its two helicopters): get in, the rotor spools
## up, Space climbs, hands off holds the height, W flies it nose-down forward and letting go stops
## it, the nose follows the camera, the wash reaches the ground and the shader global, Shift brings
## it down onto the apron and it can be left there. Then the rotor strike (a box in the disc), the
## engine killed in the air (it falls, explodes, becomes debris), bullets to a smoking and a dead
## engine, and a rooftop-style spot with a stand-in waking and sleeping by the player's distance.

var _t: Node
var _tree: SceneTree


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_static()
	if not HeliPads.enabled:
		return
	var player := _tree.get_first_node_in_group("player") as Node3D
	if player == null or not player.has_method("enter_vehicle"):
		_t._check(false, "a player to fly the helicopter")
		return
	var ws := _tree.root.get_node("/root/WorldState")
	var was: Vector3 = ws.call("to_world", player.global_position)
	await _heliport(city, player, ws)
	await _spot(city, player, ws)
	if player.call("is_driving"):
		player.call("exit_vehicle")
	for h in _tree.get_nodes_in_group("flyable_heli"):
		(h as Node).queue_free()
	await _frames(2)
	player.global_position = ws.call("to_local", was)
	player.set("velocity", Vector3.ZERO)
	city.call("update_streaming", true)
	await _frames(2)


func _static() -> void:
	var inc := "heli_downwash.gdshaderinc"
	var ok := true
	for f: String in ["foliage", "foliage_tex", "la_tree", "grass"]:
		var src := FileAccess.get_file_as_string("res://shaders/%s.gdshader" % f)
		ok = ok and src.contains(inc) and src.contains("heli_wash_")
	_t._check(ok, "palms, trees, the LA trees and grass all bend in a helicopter's downwash (heli_downwash.gdshaderinc)")
	_t._check(FileAccess.get_file_as_string("res://project.godot").contains("heli_downwash={"),
		"the heli_downwash shader global is declared")
	var city := _tree.get_first_node_in_group("city")
	var macro: MacroMap = city.plan.macro if city else null
	if macro:
		var notes: Array[String] = []
		for p: Vector2 in HeliPads.airport_pads():
			var area := Rect2(p - Vector2.ONE * HeliPads.AIRPORT_PAD * 0.5, Vector2.ONE * HeliPads.AIRPORT_PAD)
			for piece: Array in Airport.ground_pieces(macro, area):
				if int(piece[2]) != Airport.G_APRON:
					notes.append("%s on ground kind %d" % [p, int(piece[2])])
			if Airport.near_gate(p, 20.0):
				notes.append("%s by a gate" % p)
			for s: Array in macro.apron_spots:
				if (s[0] as Vector2).distance_to(p) < 45.0:
					notes.append("%s by a parked jet" % p)
		_t._check(notes.is_empty(), "the airport heliport's pads are on clear apron, off the gates and the parked jets %s" % [notes])
	var m := HeliPads.pad_mesh()
	_t._check(m != null and m.get_surface_count() == 1, "the heliport pad's paint is one mesh")


func _heliport(city: Node3D, player: Node3D, ws: Node) -> void:
	var p0: Vector2 = HeliPads.airport_pads()[0]
	player.global_position = ws.call("to_local", Vector3(p0.x + 14.0, 1.5, p0.y + 14.0))
	player.set("velocity", Vector3.ZERO)
	city.call("update_streaming", true)
	await _frames(4)
	var heli: FlyableHeli = null
	var found := 0
	for i in 30:
		found = 0
		heli = null
		for n in _tree.get_nodes_in_group("flyable_heli"):
			var h := n as FlyableHeli
			for p: Vector2 in HeliPads.airport_pads():
				var w: Vector3 = ws.call("to_world", h.global_position)
				if Vector2(w.x, w.z).distance_to(p) < 3.0:
					found += 1
					if p == p0:
						heli = h
		if found >= 2:
			break
		await _frames(1)
	_t._check(found >= 2 and heli != null, "the airport heliport has a helicopter on each pad (%d)" % found)
	if heli == null:
		return
	_t._check(heli.freeze and heli.spool == 0.0, "a waiting helicopter sits frozen on its pad, rotor stopped")
	# Look along its nose, so it has no reason to turn while the checks fly it.
	player.camera_rig.set_look(rad_to_deg(heli.global_rotation.y), -12.0)
	player.call("enter_vehicle", heli)
	_t._check(player.call("is_driving") and heli.driver == player and not heli.freeze, "the player gets into the helicopter")
	var rig: Node = player.get_node("CameraRig")
	_t._check(is_equal_approx(float(rig.camera_distance), heli.camera_distance) or (await _wait_cam(rig, heli)),
		"the chase camera pulls back to %.0f m while flying" % heli.camera_distance)
	var ground_y := heli.global_position.y
	await _ticks(int(heli.spool_time * 60.0) + 30)
	_t._check(heli.spool > 0.97 and absf(heli.global_position.y - ground_y) < 0.6 and not heli.is_airborne(),
		"the rotor spools up and it idles on its skids (spool %.2f, %.2f m off)" % [heli.spool, heli.global_position.y - ground_y])
	_t._check(heli._main_disc != null and heli._main_disc.visible, "at speed the blades are the rotor disc")
	# Collective up.
	Input.action_press("jump")
	var worst := 0.0
	for i in 80:
		await _tree.physics_frame
		worst = maxf(worst, 1.0 - heli.global_basis.y.y)
	Input.action_release("jump")
	var climbed := heli.global_position.y - ground_y
	_t._check(climbed > 7.0 and worst < 0.08, "Space climbs (%.1f m in 1.3 s, worst tilt %.3f)" % [climbed, worst])
	# Hands off: it holds the height.
	await _ticks(90)
	var y0 := heli.global_position.y
	var vmax := 0.0
	for i in 150:
		await _tree.physics_frame
		vmax = maxf(vmax, absf(heli.linear_velocity.y))
	_t._check(absf(heli.global_position.y - y0) < 2.5 and vmax < 2.5 and heli.global_basis.y.y > 0.97,
		"hands off it hovers (drift %.2f m, |vy| <= %.2f)" % [heli.global_position.y - y0, vmax])
	_t._check(heli.wash_strength > 0.8 and heli._wash.ground_strength > 0.2 and heli._wash.ground_point != Vector3.INF,
		"the downwash reaches the apron from %.0f m (%.2f)" % [heli.global_position.y - ground_y, heli._wash.ground_strength])
	_t._check(HeliDownwash._owner_id == heli._wash.get_instance_id() and HeliDownwash._owner_k > 0.2,
		"the hovering helicopter owns the heli_downwash shader global")
	# Cyclic forward: nose down, flies forward.
	var start := heli.global_position
	var nose := -heli.global_basis.z
	nose = Vector3(nose.x, 0.0, nose.z).normalized()
	Input.action_press("move_forward")
	var min_pitch := 0.0
	for i in 150:
		await _tree.physics_frame
		min_pitch = minf(min_pitch, heli.global_basis.z.y * -1.0)
	Input.action_release("move_forward")
	var ahead := (heli.global_position - start).dot(nose)
	var speed := Vector2(heli.linear_velocity.x, heli.linear_velocity.z).length()
	_t._check(ahead > 18.0 and min_pitch < -0.2 and speed > 15.0,
		"W tilts the nose down and it flies forward (%.1f m, %.1f m/s, nose %.2f)" % [ahead, speed, min_pitch])
	_t._check(absf(heli.global_position.y - start.y) < 6.0, "it holds its height flying forward (%.1f m)" % (heli.global_position.y - start.y))
	await _ticks(300)
	var after := Vector2(heli.linear_velocity.x, heli.linear_velocity.z).length()
	_t._check(after < speed * 0.35, "let go, it tilts back against its drift and stops (%.1f -> %.1f m/s)" % [speed, after])
	# Yaw: the nose follows the camera.
	var yaw0 := heli.global_rotation.y
	player.camera_rig.set_look(rad_to_deg(yaw0) + 90.0, -12.0)
	await _ticks(100)
	var turned := wrapf(heli.global_rotation.y - yaw0, -PI, PI)
	_t._check(absf(turned - PI * 0.5) < 0.3, "the nose turns to where the camera looks (%.0f of 90 degrees)" % rad_to_deg(turned))
	# Collective down: back onto the apron.
	Input.action_press("boost")
	var landed := false
	for i in 600:
		await _tree.physics_frame
		if heli.global_position.y - ground_y < 1.2 and not heli.is_airborne():
			landed = true
			break
	Input.action_release("boost")
	await _ticks(40)
	_t._check(landed and heli.hp >= heli.max_hp and not heli.engine_dead,
		"Shift sets it down on the apron unhurt (hp %.0f)" % heli.hp)
	player.call("exit_vehicle")
	await _ticks(2)
	_t._check(not player.call("is_driving") and player.visible and player.global_position.distance_to(heli.global_position) < 11.0,
		"the player gets out beside it")
	_t._check(is_equal_approx(float(rig.camera_distance), heli._cam_keep) or float(rig.camera_distance) < heli.camera_distance,
		"the camera comes back in once out (%.1f m)" % float(rig.camera_distance))
	await _ticks(int(heli.spool_time * 60.0) + 20)
	_t._check(heli.spool < 0.05 and heli.wash_strength < 0.01, "left alone, its rotor winds down and the wash stops")
	await _strike(heli)
	await _crash(city, player, ws)


## A box in the rotor disc is a rotor strike: the blades go, the engine dies.
func _strike(heli: FlyableHeli) -> void:
	heli.spool = 1.0
	var hub := heli.global_transform * heli._hub_local
	var box := StaticBody3D.new()
	box.collision_layer = 1
	box.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.6, 1.0, 0.6)
	cs.shape = bs
	box.add_child(cs)
	heli.get_parent().add_child(box)
	box.global_position = hub + heli.global_basis.x * (heli._main_radius * 0.7)
	await _ticks(2)
	_t._check(heli.rotor_hits_something(), "a mast inside the rotor disc is found by the strike query")
	box.global_position += Vector3.UP * 40.0
	await _ticks(2)
	_t._check(not heli.rotor_hits_something(), "and nothing is found with the disc clear")
	box.queue_free()
	heli.rotor_strike()
	_t._check(heli.rotor_lost and heli.engine_dead and heli.hp < heli.max_hp * 0.6, "a rotor strike throws the blades and kills the engine")
	_t._check(not heli._main_disc.visible or heli.rotor_lost, "the struck rotor draws no disc")


## Engine dead in the air: it falls, explodes on the ground and is left as debris.
func _crash(_city: Node3D, player: Node3D, ws: Node) -> void:
	var p1: Vector2 = HeliPads.airport_pads()[1]
	var heli: FlyableHeli = null
	for n in _tree.get_nodes_in_group("flyable_heli"):
		var h := n as FlyableHeli
		var w: Vector3 = ws.call("to_world", h.global_position)
		if Vector2(w.x, w.z).distance_to(p1) < 3.0:
			heli = h
	if heli == null:
		_t._check(false, "the second heliport helicopter for the crash checks")
		return
	# Bullets first: smoke at half, the engine at none.
	for i in 9:
		heli.take_hit(0, 10.0, Vector3.FORWARD, heli.global_position, Vehicle.HIT_BULLET)
	_t._check(heli._smoke != null and not heli.engine_dead, "rounds make it smoke at half health (hp %.0f)" % heli.hp)
	heli.freeze = false
	heli.global_position += Vector3.UP * 45.0
	heli.linear_velocity = Vector3.ZERO
	heli.sleeping = false
	PhysicsServer3D.body_set_state(heli.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, false)
	heli.hold_crash_watch(4)
	for i in 8:
		heli.take_hit(0, 10.0, Vector3.FORWARD, heli.global_position, Vehicle.HIT_BULLET)
	_t._check(heli.engine_dead and heli._fire != null, "more rounds kill the engine and it catches fire")
	var spun := 0.0
	for i in 600:
		await _tree.physics_frame
		spun = maxf(spun, absf(heli.angular_velocity.y))
		if heli.exploded:
			break
	_t._check(heli.exploded, "a dead helicopter falls and explodes on the ground")
	_t._check(spun > 1.5, "it spins round the mast as it falls (%.1f rad/s)" % spun)
	_t._check(heli.is_in_group("debris") and not heli.is_in_group("vehicle"), "the wreck is debris and nobody can get in")
	_t._check(player.global_position.distance_to(heli.global_position) > 0.0, "the player is untouched by a wreck he was not in")


## A spot with a stand-in (a rooftop's parked helicopter): a real body only while the player is near.
func _spot(city: Node3D, player: Node3D, ws: Node) -> void:
	var holder := Node3D.new()
	holder.name = "HeliSpotCheck"
	city.add_child(holder)
	var at: Vector3 = player.global_position + Vector3(200.0, 60.0, 0.0)
	var stand := Node3D.new()
	holder.add_child(stand)
	var spot := HeliSpot.new()
	spot.stand_in = stand
	holder.add_child(spot)
	spot.global_position = at
	spot._tick()
	_t._check(spot.heli == null and stand.visible, "a parked helicopter far from the player stays a stand-in")
	var keep: Vector3 = player.global_position
	player.global_position = at + Vector3(20.0, 0.0, 0.0)
	spot._tick()
	_t._check(spot.heli != null and not stand.visible and spot.heli.global_position.distance_to(at) < 0.5,
		"near it the stand-in becomes a real helicopter on the same spot")
	var h := spot.heli
	player.global_position = keep
	spot._tick()
	await _frames(1)
	_t._check(spot.heli == null and stand.visible and not is_instance_valid(h), "walked away from, it goes back to the stand-in")
	holder.queue_free()
	await _frames(1)


func _wait_cam(rig: Node, heli: FlyableHeli) -> bool:
	for i in 3:
		await _tree.physics_frame
		if is_equal_approx(float(rig.camera_distance), heli.camera_distance):
			return true
	return false


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _frames(n: int) -> void:
	for i in n:
		await _tree.process_frame
