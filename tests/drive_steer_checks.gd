extends RefCounted
## Steering and grip for the player's car (scripts/vehicles/drive_handling.gd, DriveHandling), for
## tests/smoke_test.gd's test-room part: the real player in a real sedan on a flat slab far from the
## room, driven by simulated Input actions. Checks: the keyboard ramp eases in, comes back faster
## and is symmetric; the stick curve; the lock falls with speed and never below its floor; the
## counter-steer is odd and dead under its threshold; on the slab left and right turn alike, the
## car corners at a real-world-ish lateral g instead of 2-3 g, full lock at 70 km/h pushes wide
## instead of spinning, a kicked tail is caught (and is not without the assist), getting out puts
## the tyres back, and DRIVE_HANDLING off is the old steering line. Untyped where the Sfx-using
## classes are touched.

var _t: Node
var _tree: SceneTree
var _player: Node
var _car: Vehicle
var _slab: StaticBody3D
const AT := Vector3(4000.0, 300.0, 4000.0)


func run(t: Node, player: Node) -> void:
	_t = t
	_tree = t.get_tree()
	_player = player
	_pure()
	if not DriveHandling.enabled:
		_check(true, "DRIVE_HANDLING=0: the handling checks on the slab are skipped")
		return
	var home: Vector3 = player.global_position
	_slab = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1600.0, 2.0, 1600.0)
	cs.shape = box
	_slab.add_child(cs)
	_t.add_child(_slab)
	_slab.global_position = AT - Vector3(0.0, 1.0, 0.0)

	# Left and right alike at 54 km/h, and a sane lateral g.
	var yl := await _yaw(15.0, -1.0)
	var yr := await _yaw(15.0, 1.0)
	_check(yl.x > 0.0 and yr.x < 0.0 and absf(yl.x + yr.x) < 0.05 * absf(yl.x),
		"left and right lock turn alike at 54 km/h (%.1f vs %.1f deg/s)" % [yl.x, -yr.x])
	_check(yr.y > 0.8 and yr.y < 1.7, "full lock at 54 km/h corners at %.2f g (was 2.7 g on endless grip)" % yr.y)
	_check(yr.z < 12.0, "and the car does not slide doing it (%.1f deg of slip)" % yr.z)
	var yf := await _yaw(30.0, 1.0)
	_check(yf.y < 1.7 and yf.z < 12.0 and _car.global_basis.y.y > 0.9,
		"full lock at 108 km/h is a %.2f g bend, not a spin (slip %.1f deg; it spun round on main)" % [yf.y, yf.z])

	# At the limit: full lock forced at 70 km/h pushes wide.
	var keep_lock := DriveHandling.high_lock
	DriveHandling.high_lock = DriveHandling.low_lock
	var lim := await _yaw(70.0 / 3.6, 1.0)
	DriveHandling.high_lock = keep_lock
	_check(lim.z < 15.0 and lim.y < 1.6, "full lock at 70 km/h at the limit pushes wide (%.2f g, %.1f deg slip)" % [lim.y, lim.z])

	# A kicked tail at 80 km/h: caught with the assist, a big slide without it.
	var with := await _kick(-1.0)
	var without := await _kick(0.0)
	_check(absf(with) < 30.0, "the counter-steer assist catches a kicked tail at 80 km/h (heading moved %.1f deg)" % with)
	_check(absf(without) > absf(with) + 15.0, "without the assist the same kick slides it round (%.1f deg)" % without)

	# Getting out puts the tyres back.
	var grip_in: float = _car.wheels[0].wheel_friction_slip
	_player.call("exit_vehicle")
	await _ticks(2)
	var grip_out: float = _car.wheels[0].wheel_friction_slip
	_check(grip_in < _car.wheel_grip * 0.5 and absf(grip_out - _car.wheel_grip) < 0.01,
		"the player's tyres (%.2f) go back to the car's own (%.2f) when he gets out" % [grip_in, grip_out])

	# The A/B: off, the old steering line.
	DriveHandling.enabled = false
	await _fresh()
	await _reach(10.0)
	_steer(1.0)
	await _ticks(30)
	var old: float = -1.0 * (_car.steer_lock(_speed()) if Vehicle.drive_fix else _car.max_steer * lerpf(1.0, _car.steer_min_factor,
		clampf(absf(_speed()) / (_car.steer_full_speed * 3.0), 0.0, 1.0)))
	_check(absf(_car._steer_target - old) < 0.02, "DRIVE_HANDLING off steers by the old line (%.3f vs %.3f)" % [_car._steer_target, old])
	DriveHandling.enabled = true
	_release_all()
	_player.call("exit_vehicle")
	await _ticks(2)
	_car.queue_free()
	_slab.queue_free()
	_player.global_position = home
	_player.set("velocity", Vector3.ZERO)
	await _ticks(4)


func _pure() -> void:
	var dt := 1.0 / 60.0
	# Keyboard: time to full lock, back to centre, both sides.
	var x := 0.0
	var held := 0.0
	var t_in := 0.0
	while x < 0.999 and t_in < 2.0:
		held += dt
		x = DriveHandling.shape(x, 1.0, true, held, dt)
		t_in += dt
	var t_out := 0.0
	while x > 0.001 and t_out < 2.0:
		x = DriveHandling.shape(x, 0.0, true, 0.0, dt)
		t_out += dt
	_check(t_in > 0.12 and t_in < 0.4, "a held steering key eases to full lock in %.2f s" % t_in)
	_check(t_out < t_in, "letting go comes back to centre faster (%.2f s)" % t_out)
	var a := DriveHandling.shape(0.0, 1.0, true, dt, dt)
	var b := DriveHandling.shape(0.0, -1.0, true, dt, dt)
	_check(is_equal_approx(a, -b) and a > 0.0 and a < 0.2, "the keyboard ramp is the same both ways and starts gently (%.3f a tick)" % a)
	# Stick: fine near centre, full at the edge.
	var s_half := 0.0
	var s_full := 0.0
	for i in 120:
		s_half = DriveHandling.shape(s_half, 0.5, false, 0.0, dt)
		s_full = DriveHandling.shape(s_full, -1.0, false, 0.0, dt)
	_check(s_half > 0.2 and s_half < 0.5 and absf(s_full + 1.0) < 0.01,
		"the stick curve: half deflection %.2f, full %.2f" % [s_half, s_full])
	# The lock by speed.
	var prev := 9.0
	var mono := true
	for v in [0.0, 5.0, 10.0, 15.0, 20.0, 30.0, 45.0, 60.0]:
		var l := DriveHandling.lock_at(v, 2.7, 0.5)
		mono = mono and l <= prev + 1e-6 and l >= DriveHandling.high_lock - 1e-6
		prev = l
	_check(mono and is_equal_approx(DriveHandling.lock_at(0.0, 2.7, 0.5), DriveHandling.low_lock)
		and DriveHandling.lock_at(30.0, 2.7, 0.5) < DriveHandling.low_lock * 0.3,
		"the lock falls with speed (%.2f rad at rest, %.3f at 108 km/h, never under %.3f)" % [
			DriveHandling.lock_at(0.0, 2.7, 0.5), DriveHandling.lock_at(30.0, 2.7, 0.5), DriveHandling.high_lock])
	# The counter-steer.
	var c := DriveHandling.counter_steer(deg_to_rad(20.0), 1.0)
	_check(c > 0.0 and is_equal_approx(c, -DriveHandling.counter_steer(deg_to_rad(-20.0), 1.0))
		and is_zero_approx(DriveHandling.counter_steer(deg_to_rad(DriveHandling.assist_from * 0.9), 1.0)),
		"the counter-steer turns toward the slide, both ways alike, and not under %.0f deg" % DriveHandling.assist_from)


func _fresh() -> void:
	_release_all()
	if _car and is_instance_valid(_car):
		if _player.get("vehicle") == _car:
			_player.call("exit_vehicle")
		_car.queue_free()
		await _ticks(2)
	_car = Vehicle.new()
	_car.setup(Vehicle.BodyType.SEDAN, Color(0.5, 0.05, 0.05), Vehicle.Addon.NONE)
	_t.add_child(_car)
	_car.global_position = AT + Vector3(0.0, 1.2, 0.0)
	_car.rotation = Vector3.ZERO
	await _ticks(30)
	_player.call("enter_vehicle", _car)
	await _ticks(10)


## Full lock at `v` m/s: Vector3(mean yaw rate deg/s, mean lateral g, peak rear-axle-ish slip deg).
func _yaw(v: float, dir: float) -> Vector3:
	await _fresh()
	await _reach(v)
	_steer(dir)
	var yaw := 0.0
	var lat := 0.0
	var slip := 0.0
	var n := 0
	var prev: Vector3 = _car.linear_velocity
	for i in 130:
		_cruise(v)
		await _ticks(1)
		var vel: Vector3 = _car.linear_velocity
		if i >= 50:
			yaw += _car.angular_velocity.y
			lat += absf(((vel - prev) * Engine.physics_ticks_per_second).dot(_car.global_basis.x)) / 9.8
			n += 1
			var h: DriveHandling = DriveHandling.of(_car)
			slip = maxf(slip, absf(h.slip_deg))
		prev = vel
	_steer(0.0)
	return Vector3(rad_to_deg(yaw / maxf(n, 1)), lat / maxf(n, 1), slip)


## A rear kick at 80 km/h, hands off; gain < 0 keeps the default. The heading change in degrees.
func _kick(gain: float) -> float:
	var keep := DriveHandling.assist_gain
	if gain >= 0.0:
		DriveHandling.assist_gain = gain
	await _fresh()
	await _reach(80.0 / 3.6)
	var h0 := _heading()
	var av: Vector3 = _car.angular_velocity
	av.y += 4.0
	_car.angular_velocity = av
	for i in 150:
		_cruise(80.0 / 3.6)
		await _ticks(1)
	DriveHandling.assist_gain = keep
	return rad_to_deg(wrapf(_heading() - h0, -PI, PI))


func _speed() -> float:
	return _car.linear_velocity.dot(-_car.global_basis.z)


func _heading() -> float:
	var f: Vector3 = -_car.global_basis.z
	return atan2(-f.x, -f.z)


func _cruise(v: float) -> void:
	var t := clampf((v - _speed()) * 0.5 + 0.15, 0.0, 1.0)
	if t > 0.01:
		Input.action_press("move_forward", t)
	else:
		Input.action_release("move_forward")


func _steer(x: float) -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	if x > 0.0:
		Input.action_press("move_right", x)
	elif x < 0.0:
		Input.action_press("move_left", -x)


func _reach(v: float) -> void:
	for i in 600:
		_cruise(v)
		await _ticks(1)
		if _speed() >= v * 0.97:
			break
	for k in 20:
		_cruise(v)
		await _ticks(1)


func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "alt_fire", "boost", "jump"]:
		Input.action_release(a)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _check(ok: bool, what: String) -> void:
	_t.call("_check", ok, what)
