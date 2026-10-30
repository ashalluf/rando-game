extends RefCounted
## The chase camera while driving (DriveCam, scripts/player/drive_cam.gd, made by the CameraRig)
## for tests/smoke_test.gd. Loaded at run time, so it compiles after the autoloads. Staged on its
## own deck 300 m over the street, with its own walls: nothing of the city near it.
## Pure: the heading spring and the kick spring land on the same curve at 30 and 144 fps; the road
## shake is a function of the clock, stays small, and drops what a frame rate cannot show; the
## switch and the settings key. Live: getting in blends the view behind the car; speed pulls it
## back, lowers it and opens the field of view (30, 80, 150 km/h); a corner swings it by the yaw
## rate within the cap; free look holds the player's view and eases back; look behind swings round
## and back; a crash and a landing kick it; the motion blur's terms; a jet keeps the old camera;
## and the spring arm never puts the camera inside a wall or behind it from the car (backed up to
## a wall, past a corner, under a low lid).

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _deck: StaticBody3D
var _cars: Array = []
var _top: Vector3
var _ws: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_ws = _tree.root.get_node("/root/WorldState")
	_pure()
	var player := _tree.get_first_node_in_group("player") as Player
	var rig: Node = player.get_node_or_null("CameraRig")
	var drive: DriveCam = rig.get("drive") if rig else null
	_check(drive != null, "the CameraRig makes a DriveCam")
	if drive == null or not DriveCam.enabled:
		_check(true, "DriveCam is off (DRIVE_CAM=0): only the pure checks")
		return
	if player.is_driving():
		player.exit_vehicle()
	var police: Node = city.get_node_or_null("Police")
	var police_was: Variant = police.get("enabled") if police else null
	if police:
		police.set("enabled", false)
	var home: Vector3 = _ws.to_world(player.global_position)
	_top = player.global_position + Vector3(0.0, 300.0, 0.0)
	_build_deck()
	player.global_position = _top + Vector3(0.0, 1.2, 30.0)
	player.velocity = Vector3.ZERO
	await _ticks(3)

	await _live(player, rig, drive)
	await _walls(player, rig, drive)

	if player.is_driving():
		player.exit_vehicle()
	for c in _cars:
		if is_instance_valid(c):
			c.queue_free()
	_deck.queue_free()
	player.global_position = _ws.to_local(home)
	player.velocity = Vector3.ZERO
	if police:
		police.set("enabled", police_was)
	await _wait(drive.blend_seconds + 0.2)
	_check(drive.weight == 0.0 and rig.position.is_equal_approx(Vector3(0.0, 1.6, 0.0)),
		"on foot again, the chase camera has let go (weight %.2f)" % drive.weight)


func _pure() -> void:
	# The heading spring: the same second at 30 and 144 fps.
	var a := Vector2(0.0, 0.0)
	var b := Vector2(0.0, 0.0)
	for i in 30:
		a = DriveCam.spring(a.x, a.y, 1.0, 4.0, 1.0 / 30.0)
	for i in 144:
		b = DriveCam.spring(b.x, b.y, 1.0, 4.0, 1.0 / 144.0)
	_check(absf(a.x - b.x) < 1e-4 and absf(a.y - b.y) < 1e-4,
		"the follow spring is frame-rate independent (%.5f vs %.5f)" % [a.x, b.x])
	_check(a.x > 0.85 and a.x < 1.0, "and it settles without overshoot (%.3f after 1 s)" % a.x)
	var dc := DriveCam.new()
	# The kick spring: the same thump at 30 and 144 fps.
	var peaks: Array[float] = []
	for fps: float in [30.0, 144.0]:
		dc._k = Vector3.ZERO
		dc._kv = Vector3.ZERO
		dc.land(15.0)
		var lo := 0.0
		var after := 0.0
		var tt := 0.0
		while tt < 1.0:
			dc._kick_step(1.0 / fps)
			tt += 1.0 / fps
			lo = minf(lo, dc._k.y)
			if absf(tt - 0.5) < 0.5 / fps:
				after = dc._k.y
		peaks.append(lo)
		peaks.append(after)
	_check(absf(peaks[0] - peaks[2]) < 0.01 and absf(peaks[1] - peaks[3]) < 0.01 and peaks[0] < -0.1,
		"a landing's thump is the same at 30 and 144 fps (dip %.3f / %.3f m)" % [peaks[0], peaks[2]])
	_check(absf(dc._k.y) < 0.03, "and it has settled a second later (%.3f m)" % dc._k.y)
	# The road shake: a function of the clock, small, and nothing a frame rate cannot show.
	var s1 := dc.road_shake(3.21, 1.0, 1.0, 1.0 / 60.0)
	var s2 := dc.road_shake(3.21, 1.0, 1.0, 1.0 / 60.0)
	_check(s1 == s2, "the road shake is the clock's, not a random number a frame")
	var worst := 0.0
	var worst_rough := 0.0
	var tt2 := 0.0
	while tt2 < 4.0:
		worst = maxf(worst, rad_to_deg(dc.road_shake(tt2, 1.0, 1.0, 1.0 / 144.0).length()))
		worst_rough = maxf(worst_rough, rad_to_deg(dc.road_shake(tt2, 1.0, dc.rough_gain, 1.0 / 144.0).length()))
		tt2 += 0.003
	_check(worst > 0.05 and worst < 0.8, "flat out on tarmac it moves the view under a degree (%.2f deg)" % worst)
	_check(worst_rough > worst * 1.5 and worst_rough < 2.0, "off the tarmac more, still under two (%.2f deg)" % worst_rough)
	_check(dc.road_shake(1.7, 0.0, 1.0, 1.0 / 60.0).length() < 1e-6, "standing still there is no road shake")
	# At 20 fps the buzz (11-24 Hz) is gone, the sway stays.
	var fast := 0.0
	var slow := 0.0
	tt2 = 0.0
	while tt2 < 2.0:
		var h := dc.road_shake(tt2, 1.0, 1.0, 1.0 / 144.0)
		var l := dc.road_shake(tt2, 1.0, 1.0, 1.0 / 20.0)
		fast = maxf(fast, (h - l).length())
		slow = maxf(slow, l.length())
		tt2 += 0.01
	_check(fast > 0.0005 and slow > 0.0005 and slow < deg_to_rad(0.45),
		"at 20 fps the buzz a frame cannot show is dropped and the sway kept")
	dc.shake_scale = 0.0
	_check(dc.road_shake(1.2, 1.0, 2.0, 1.0 / 60.0).length() == 0.0, "the settings' shake off means none")
	dc.free()
	_check(GameSettings.DEFAULTS.has("drive_shake") and GameSettings.DEFAULTS["drive_shake"] == true,
		"the settings screen has Driving camera shake, on by default")
	_check(InputMap.has_action("look_behind"), "look_behind is an input action")
	_check(DriveCam.chased(null) == null, "no player, no chase")


func _live(player: Player, rig: Node, drive: DriveCam) -> void:
	var car := _car(Vehicle.BodyType.SEDAN, Vector3(0.0, 0.0, 0.0), 0.0)
	await _ticks(20)
	_check(DriveCam.chased(player) == null, "on foot nothing is chased")
	player.enter_vehicle(car)
	await _wait(drive.blend_seconds + 0.17)
	_check(DriveCam.chased(player) == car and drive.weight >= 1.0, "in the car the chase camera is in force (%.2f)" % drive.weight)
	# Settled behind the car.
	await _wait(drive.recenter_seconds + 0.5)
	var cam := rig.get_node("SpringArm3D/Camera3D") as Camera3D
	var back := _behind(car, cam)
	_check(back > 0.9, "parked, the camera sits behind the car (%.2f)" % back)
	var arm := rig.get_node("SpringArm3D") as SpringArm3D
	_check(arm.shape is SphereShape3D, "the spring arm sweeps a sphere while driving")

	# Speed: 30, 80, 150 km/h along the deck.
	var rows: Array = []
	for kmh: float in [30.0, 80.0, 150.0]:
		await _place(car, Vector3(0.0, 0.0, 80.0), 0.0)
		var st := await _drive(car, kmh / 3.6, 0.0, 1.6)
		rows.append([kmh, drive.distance, rad_to_deg(rig.rotation.x), drive.fov_add, drive.speed_t, cam.fov])
		_check(st, "driving at %d km/h" % int(kmh))
	print("DRIVECAM speed rows [kmh, distance, pitch, fov_add, speed_t, fov]: ", rows)
	_check(rows[0][1] < rows[1][1] and rows[1][1] < rows[2][1], "faster pulls the camera back (%.1f, %.1f, %.1f m)" % [rows[0][1], rows[1][1], rows[2][1]])
	_check(rows[0][2] < rows[2][2] - 2.0, "and lower (pitch %.1f -> %.1f deg)" % [rows[0][2], rows[2][2]])
	_check(rows[0][3] < 1.0 and rows[2][3] > 5.0 and rows[2][3] < 12.0,
		"and opens the field of view a little (+%.1f, +%.1f deg)" % [rows[0][3], rows[2][3]])
	var terms := drive.blur_terms()
	_check(terms.x > 1.5 and terms.y > 0.0, "the motion blur streaks more at speed (x%.2f, knee +%.1f px)" % [terms.x, terms.y])
	var still_behind := _behind(car, cam)
	_check(still_behind > 0.95, "at 150 km/h in a straight line it stays square behind (%.2f)" % still_behind)

	# A corner: the view lags the turn, the way the car turns, within the cap.
	await _place(car, Vector3(0.0, 0.0, 80.0), 0.0)
	await _drive(car, 60.0 / 3.6, 0.0, 1.0)
	await _drive(car, 60.0 / 3.6, -0.45, 0.9) # turning right (0.8 g)
	var lag_r := -drive.lag_deg
	print("DRIVECAM corner lag at 60 km/h, 0.45 rad/s: %.1f deg" % lag_r)
	_check(lag_r > 4.0 and lag_r <= drive.max_corner_lag_deg + 0.01,
		"turning right the view lags the car into the corner (%.1f deg, cap %.0f)" % [lag_r, drive.max_corner_lag_deg])
	await _place(car, Vector3(0.0, 0.0, 80.0), 0.0)
	await _drive(car, 60.0 / 3.6, 0.0, 1.0)
	await _drive(car, 60.0 / 3.6, 0.45, 0.9)
	_check(drive.lag_deg > 4.0, "turning left the other way (%.1f deg)" % drive.lag_deg)
	await _drive(car, 60.0 / 3.6, 0.0, 2.0)
	_check(absf(drive.lag_deg) < 3.0, "and it comes back behind on the straight (%.1f deg)" % drive.lag_deg)

	# Free look: the player's view holds, then eases back.
	await _place(car, Vector3(0.0, 0.0, 80.0), 0.0)
	await _wait(0.5)
	var yaw0: float = rig.rotation.y
	rig.set("_yaw", wrapf(yaw0 + 1.6, -PI, PI))
	drive.note_look()
	await _wait(drive.free_look_hold * 0.6)
	_check(absf(angle_difference(rig.rotation.y, yaw0 + 1.6)) < 0.08, "free look holds the player's view for a moment")
	await _wait(drive.free_look_hold * 0.4 + drive.recenter_seconds + 0.6)
	_check(_behind(car, cam) > 0.9, "then eases back behind the car (%.2f)" % _behind(car, cam))

	# Look behind.
	Input.action_press("look_behind")
	await _wait(drive.look_behind_seconds + 0.20)
	_check(_behind(car, cam) < -0.85, "look behind swings the view round to face back (%.2f)" % _behind(car, cam))
	Input.action_release("look_behind")
	await _wait(drive.look_behind_seconds + 0.33)
	_check(_behind(car, cam) > 0.9, "and back on release (%.2f)" % _behind(car, cam))

	# Kicks: a crash and a landing.
	await _place(car, Vector3(0.0, 0.0, 80.0), 0.0)
	var c0 := drive.crashes
	await _drive(car, 25.0, 0.0, 0.5)
	car.linear_velocity = Vector3.ZERO
	await _ticks(3)
	_check(drive.crashes > c0, "stopping dead from 90 km/h kicks the camera as a crash")
	var l0 := drive.landings
	await _place(car, Vector3(0.0, 9.0, 80.0), 0.0)
	await _until_ticks(func() -> bool: return drive.landings > l0, 160)
	_check(drive.landings > l0, "dropping 9 m kicks it as a landing")
	player.exit_vehicle()
	await _wait(drive.blend_seconds + 0.10)
	_check(drive.weight == 0.0 and arm.shape == null, "getting out lets go of the car and the arm's sphere")


## The spring arm: the camera never ends up inside or on the far side of a wall.
func _walls(player: Player, rig: Node, drive: DriveCam) -> void:
	var car := _car(Vehicle.BodyType.CROSSOVER, Vector3(60.0, 0.0, -40.0), 0.0)
	await _ticks(20)
	var base := car.global_position
	var walls: Array[StaticBody3D] = []
	# A wall 2.2 m behind the bumper, a pillar off the rear corner, a low lid over the car.
	walls.append(_wall(base + Vector3(0.0, 2.0, 4.6), Vector3(12.0, 5.0, 0.4)))
	walls.append(_wall(base + Vector3(-2.2, 2.0, 3.2), Vector3(0.6, 5.0, 0.6)))
	walls.append(_wall(base + Vector3(0.0, 3.4, 1.0), Vector3(8.0, 0.3, 8.0)))
	await _ticks(4)
	player.enter_vehicle(car)
	var cam := rig.get_node("SpringArm3D/Camera3D") as Camera3D
	var worst_in := 0
	var worst_cross := 0
	var samples := 0
	var space := car.get_world_3d().direct_space_state
	var arm := rig.get_node("SpringArm3D") as SpringArm3D
	# Spin the view all the way round (free look) and sample every frame.
	for i in 240:
		rig.set("_yaw", wrapf(float(rig.get("_yaw")) + TAU / 120.0, -PI, PI))
		rig.set("_pitch", deg_to_rad(-25.0 + 30.0 * sin(float(i) * 0.11)))
		drive.note_look()
		await _tree.process_frame
		await _tree.physics_frame
		if i < 10:
			continue
		samples += 1
		var p := cam.global_position
		var q := PhysicsPointQueryParameters3D.new()
		q.position = p
		q.collision_mask = 1
		var hit := space.intersect_point(q, 4)
		for h: Dictionary in hit:
			if walls.has(h.collider):
				worst_in += 1
		var rq := PhysicsRayQueryParameters3D.create(arm.global_position, p, 1)
		var rh := space.intersect_ray(rq)
		if not rh.is_empty() and walls.has(rh.collider):
			worst_cross += 1
	_check(samples > 200 and worst_in == 0, "the camera is never inside a wall, pillar or lid (%d of %d frames)" % [worst_in, samples])
	_check(worst_cross == 0, "and never on the far side of one from the car (%d of %d frames)" % [worst_cross, samples])
	player.exit_vehicle()
	for w in walls:
		w.queue_free()
	await _wait(drive.blend_seconds + 0.10)


func _car(type: Vehicle.BodyType, at: Vector3, yaw: float) -> Vehicle:
	var car := Vehicle.new()
	car.setup(type, Color(0.6, 0.1, 0.1), Vehicle.Addon.NONE)
	car.position = _city.to_local(_top + at + Vector3(0.0, 1.2, 0.0))
	car.rotation.y = yaw
	_city.add_child(car)
	_cars.append(car)
	return car


func _place(car: Vehicle, at: Vector3, yaw: float) -> void:
	car.hold_crash_watch(4)
	car.global_transform = Transform3D(Basis(Vector3.UP, yaw), _top + at + Vector3(0.0, 1.2, 0.0))
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	await _ticks(12)


## Drives `car` at `speed` m/s turning at `yaw_rate` rad/s for `seconds` (velocity set each tick).
func _drive(car: Vehicle, speed: float, yaw_rate: float, seconds: float) -> bool:
	var n := int(seconds * Engine.physics_ticks_per_second)
	for i in n:
		var f := -car.global_basis.z
		f.y = 0.0
		f = f.normalized()
		car.linear_velocity = Vector3(f.x * speed, car.linear_velocity.y, f.z * speed)
		car.angular_velocity = Vector3(0.0, yaw_rate, 0.0)
		car.hold_crash_watch(2)
		await _tree.physics_frame
	return is_instance_valid(car)


## How far behind the car the camera is: 1 straight behind, -1 straight in front.
func _behind(car: Vehicle, cam: Camera3D) -> float:
	var f := -car.global_basis.z
	f.y = 0.0
	var d := cam.global_position - car.global_position
	d.y = 0.0
	if d.length() < 0.01:
		return 0.0
	return -f.normalized().dot(d.normalized())


func _wall(at: Vector3, size: Vector3) -> StaticBody3D:
	var w := StaticBody3D.new()
	w.collision_layer = 1
	w.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	w.add_child(cs)
	_city.add_child(w)
	w.global_position = at
	return w


func _build_deck() -> void:
	_deck = StaticBody3D.new()
	_deck.collision_layer = 1
	_deck.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 600.0)
	shape.shape = box
	_deck.add_child(shape)
	_city.add_child(_deck)
	_deck.global_position = _top - Vector3(0.0, 0.5, 0.0) + Vector3(0.0, 0.0, -150.0)


func _until_ticks(cond: Callable, max_ticks: int) -> bool:
	for i in max_ticks:
		if cond.call():
			return true
		await _tree.physics_frame
	return cond.call()


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


## Waits `seconds` of game time (process frames; headless runs them as fast as it can).
func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await _tree.process_frame
		t += _tree.root.get_process_delta_time()


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)
