extends RefCounted
## The player's car turns both ways and pulls (wave 9 drive-fix, docs/HANDOFF.md "The car that
## would not turn right") for tests/smoke_test.gd. Loaded at run time, so it compiles after the
## autoloads. Staged on its own deck 300 m over the street: nothing of the city near it.
## Pure: steer_lock() is max_steer at a crawl, falls with speed, and keeps the sideways pull full
## lock asks for under steer_lateral_limit. Live, the real Player at the wheel of a sedan: 0-100
## km/h in a sane time, W + D keeps the full throttle, and move_left / move_right at 15 and 30 m/s
## turn at the same rate (within 10 %) with the car on its wheels (on today's main full lock at
## 30 m/s rolled it past 100 degrees and flight mode took it: that is what fails there).

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _deck: StaticBody3D
var _top: Vector3
var _player: Player
var _cars: Array = []


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	var ws: Node = _tree.root.get_node("/root/WorldState")
	_player = _tree.get_first_node_in_group("player") as Player
	if _player == null:
		_check(false, "drive-fix: a player")
		return
	if not Vehicle.drive_fix:
		_check(true, "drive-fix: off (DRIVE_FIX=0), nothing to check")
		return
	_pure()
	if _player.is_driving():
		_player.exit_vehicle()
	var police: Node = city.get_node_or_null("Police")
	var police_was: Variant = police.get("enabled") if police else null
	if police:
		police.set("enabled", false)
	var home: Vector3 = ws.to_world(_player.global_position)
	_top = _player.global_position + Vector3(0.0, 300.0, 0.0)
	_deck = StaticBody3D.new()
	_deck.collision_layer = 1
	_deck.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(600.0, 1.0, 600.0)
	shape.shape = box
	_deck.add_child(shape)
	_city.add_child(_deck)
	_deck.global_position = _top - Vector3(0.0, 0.5, 0.0)

	await _accel()
	await _yaw()

	_release()
	if _player.is_driving():
		_player.exit_vehicle()
	for c in _cars:
		if is_instance_valid(c):
			c.queue_free()
	_deck.queue_free()
	_player.global_position = ws.to_local(home)
	_player.velocity = Vector3.ZERO
	if police:
		police.set("enabled", police_was)
	await _ticks(2)


func _pure() -> void:
	var car := Vehicle.new()
	car.setup(Vehicle.BodyType.SEDAN, Color(0.5, 0.1, 0.1), Vehicle.Addon.NONE)
	car.wheelbase = 3.0
	_check(is_equal_approx(car.steer_lock(0.0), car.max_steer) and is_equal_approx(car.steer_lock(3.0), car.max_steer),
			"drive-fix: full lock at a crawl")
	var ok := true
	var last := INF
	for v: float in [5.0, 10.0, 15.0, 20.0, 30.0, 40.0]:
		var lock := car.steer_lock(v)
		if lock > last + 0.0001:
			ok = false
		last = lock
		# Sideways pull of the turn full lock asks for: v^2 tan(lock) / wheelbase.
		var pull := v * v * tan(lock) / car.wheelbase
		if lock > car.steer_floor + 0.0001 and pull > car.steer_lateral_limit * 1.01:
			ok = false
	_check(ok, "drive-fix: lock falls with speed and asks no more than steer_lateral_limit of grip")
	car.free()


func _spawn() -> Vehicle:
	var car := Vehicle.new()
	car.setup(Vehicle.BodyType.SEDAN, Color(0.5, 0.1, 0.1), Vehicle.Addon.NONE)
	_city.add_child(car)
	_cars.append(car)
	car.global_transform = Transform3D(Basis(), _top + Vector3(0.0, 1.0, 200.0))
	_player.enter_vehicle(car)
	await _ticks(60)
	return car


func _done(car: Vehicle) -> void:
	_release()
	if _player.is_driving():
		_player.exit_vehicle()
	car.queue_free()
	await _ticks(2)


func _accel() -> void:
	var car := await _spawn()
	Input.action_press("move_forward")
	var t := 0.0
	var dt := 1.0 / Engine.physics_ticks_per_second
	var t100 := -1.0
	while t < 8.0 and t100 < 0.0:
		await _tree.physics_frame
		t += dt
		if car.linear_velocity.dot(-car.global_basis.z) >= 27.78:
			t100 = t
	_check(t100 > 0.0 and t100 < 6.0, "drive-fix: 0-100 km/h in %.2f s (under 6)" % t100)
	# W + D (a keyboard diagonal): the throttle stays full, not 71 % of it.
	var ef := car.engine_force
	Input.action_press("move_right")
	await _ticks(2)
	_check(absf(car.engine_force) >= absf(ef) * 0.97 and absf(ef) > 0.0,
			"drive-fix: W + D keeps the full throttle (%.0f N vs %.0f N)" % [car.engine_force, ef])
	await _done(car)


func _yaw() -> void:
	for v0: float in [15.0, 30.0]:
		var rates: Array[float] = []
		var tilt := 0.0
		var flew := 0
		for act: String in ["move_left", "move_right"]:
			var car := await _spawn()
			car.hold_crash_watch(3)
			car.linear_velocity = -car.global_basis.z * v0
			await _tree.physics_frame
			Input.action_press(act)
			var sum := 0.0
			var n := 0
			for i in 90:
				await _tree.physics_frame
				tilt = maxf(tilt, rad_to_deg(acos(clampf(car.global_basis.y.y, -1.0, 1.0))))
				if car.get("_was_airborne"):
					flew += 1
				if i >= 45:
					sum += car.angular_velocity.y
					n += 1
			rates.append(sum / maxf(n, 1))
			await _done(car)
		var l := absf(rates[0])
		var r := absf(rates[1])
		_check(rates[0] > 0.05 and rates[1] < -0.05 and absf(l - r) <= 0.1 * maxf(l, r),
				"drive-fix: at %.0f m/s left and right turn alike (yaw %.3f / %.3f rad/s)" % [v0, rates[0], rates[1]])
		_check(tilt < 35.0 and flew == 0, "drive-fix: full lock at %.0f m/s keeps the car on its wheels (tilt %.0f deg, %d ticks in flight)" % [v0, tilt, flew])


func _release() -> void:
	for a in ["move_left", "move_right", "move_forward", "move_back", "boost", "alt_fire", "jump"]:
		Input.action_release(a)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)
