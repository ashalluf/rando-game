extends Node3D
## Steering and grip probe (wave 9, drive-steer): the real player in a real car on a flat 4 km
## slab, driven by simulated Input actions, numbers printed. Headless, ~1 min a body.
##   godot --headless --path . res://tools/drive_steer/probe.tscn
## BODIES=0,8,1,3 (BodyType ints, default sedan, crossover, pickup, sports), TESTS=yaw,step,
## slalom,junction (default all), DRIVE_HANDLING=0 the before.
## Lines: YAW <body> <km/h> L/R yaw_rate (deg/s) lat_g, STEP (time to 90 % steer, time back to
## centre), SLALOM (peak lat g, heading swing, settle s), JUNCTION (90 deg right / left at 40 km/h:
## seconds, radius m, overshoot deg, exit speed), SPIN (beta peak).

var player: Node
var car: Node
## TRACE=1 prints a "TR <test> <t> <steering rad> <yaw deg/s> <heading deg>" line a tick in the
## slalom, the junction and the kick (tools/drive_steer/plot.py draws them).
var _trace := OS.get_environment("TRACE") == "1"
var _tt := 0.0


func _tr(tag: String) -> void:
	if not _trace:
		return
	_tt += 1.0 / Engine.physics_ticks_per_second
	print("TR %s %.3f %.4f %.2f %.2f" % [tag, _tt, car.steering, rad_to_deg(car.angular_velocity.y), rad_to_deg(_heading())])
var _floor: StaticBody3D


func _ready() -> void:
	Engine.max_physics_steps_per_frame = 64
	_floor = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6000.0, 2.0, 6000.0)
	cs.shape = box
	_floor.add_child(cs)
	_floor.position = Vector3(0.0, -1.0, 0.0)
	add_child(_floor)
	player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0.0, 1.0, 40.0)
	await _ticks(10)
	var bodies := _ints(OS.get_environment("BODIES"), [0, 8, 1, 3])
	var tests := OS.get_environment("TESTS")
	if tests == "":
		tests = "yaw,step,slalom,slalom100,junction,accel,limit,recover"
	for b: int in bodies:
		for t: String in tests.split(","):
			await _fresh_car(b)
			match t:
				"yaw":
					for kmh: float in [18.0, 54.0, 108.0]:
						for dir: float in [-1.0, 1.0]:
							await _fresh_car(b)
							await _yaw(b, kmh, dir)
				"step":
					await _step(b)
				"slalom":
					await _slalom(b, 60.0)
				"slalom100":
					await _slalom(b, 100.0)
				"accel":
					await _accel(b)
				"limit":
					await _limit(b)
				"recover":
					for g: float in [0.0, -1.0]:
						await _fresh_car(b)
						await _recover(b, g)
				"junction":
					for dir: float in [1.0, -1.0]:
						await _fresh_car(b)
						await _junction(b, dir)
	get_tree().quit()


func _ints(s: String, d: Array) -> Array:
	if s == "":
		return d
	var out: Array = []
	for p in s.split(","):
		out.append(int(p))
	return out


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "alt_fire", "boost", "jump"]:
		Input.action_release(a)


func _fresh_car(b: int) -> void:
	_release_all()
	if car and is_instance_valid(car):
		if player.get("vehicle") == car:
			player.call("exit_vehicle")
		car.queue_free()
		await _ticks(2)
	car = Vehicle.new()
	car.setup(b, Color(0.5, 0.05, 0.05), Vehicle.Addon.NONE)
	add_child(car)
	car.global_position = Vector3(0.0, 1.2, 0.0)
	car.rotation = Vector3.ZERO
	await _ticks(30)
	_tt = 0.0
	player.call("enter_vehicle", car)
	await _ticks(20)


func _speed() -> float:
	return car.linear_velocity.dot(-car.global_basis.z)


func _heading() -> float:
	var f: Vector3 = -car.global_basis.z
	return atan2(-f.x, -f.z)


## Hold the throttle on a P loop toward `v` m/s for one tick.
func _cruise(v: float) -> void:
	var e := v - _speed()
	var t := clampf(e * 0.5 + 0.15, 0.0, 1.0)
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


func _reach(v: float) -> bool:
	for i in 900:
		_cruise(v)
		await _ticks(1)
		if _speed() >= v * 0.97:
			for k in 30:
				_cruise(v)
				await _ticks(1)
			return true
	return false


func _lat_g() -> float:
	return car.linear_velocity.dot(car.global_basis.x) # placeholder, replaced by accel below


func _yaw(b: int, kmh: float, dir: float) -> void:
	var v := kmh / 3.6
	var ok := await _reach(v)
	_steer(dir)
	var yaw_sum := 0.0
	var lat_sum := 0.0
	var beta_max := 0.0
	var n := 0
	var prev: Vector3 = car.linear_velocity
	for i in 150:
		_cruise(v)
		await _ticks(1)
		var vel: Vector3 = car.linear_velocity
		if i >= 60:
			yaw_sum += car.angular_velocity.y
			var acc := (vel - prev) * Engine.physics_ticks_per_second
			lat_sum += absf(acc.dot(car.global_basis.x)) / 9.8
			n += 1
		var flat := Vector3(vel.x, 0.0, vel.z)
		if flat.length() > 2.0:
			beta_max = maxf(beta_max, rad_to_deg((-car.global_basis.z).signed_angle_to(flat, Vector3.UP)) * signf(1.0))
		prev = vel
	print("YAW body=%d %3.0f km/h %s yaw=%6.1f deg/s lat=%.2f g spd=%.1f beta=%.1f reached=%s" % [b, kmh,
		"R" if dir > 0.0 else "L", rad_to_deg(yaw_sum / maxf(n, 1)), lat_sum / maxf(n, 1), _speed() * 3.6, beta_max, ok])
	_steer(0.0)


func _step(b: int) -> void:
	await _reach(30.0 / 3.6)
	var steer0: float = car.steering
	_steer(1.0)
	var t90 := -1.0
	var full := 0.0
	for i in 60:
		_cruise(30.0 / 3.6)
		await _ticks(1)
		full = minf(full, car.steering) if car.steering < 0.0 else full
	for i in 1:
		pass
	var target: float = car.steering
	_steer(0.0)
	await _ticks(1)
	await _reach(30.0 / 3.6)
	_steer(1.0)
	for i in 120:
		_cruise(30.0 / 3.6)
		await _ticks(1)
		if t90 < 0.0 and absf(car.steering) >= absf(target) * 0.9:
			t90 = (i + 1) / float(Engine.physics_ticks_per_second)
	_steer(0.0)
	var back := -1.0
	var yaw_settle := -1.0
	for i in 240:
		_cruise(30.0 / 3.6)
		await _ticks(1)
		if back < 0.0 and absf(car.steering) <= absf(target) * 0.1:
			back = (i + 1) / float(Engine.physics_ticks_per_second)
		if yaw_settle < 0.0 and absf(car.angular_velocity.y) < 0.05:
			yaw_settle = (i + 1) / float(Engine.physics_ticks_per_second)
	print("STEP body=%d full_steer=%.3f rad t90=%.2fs centre=%.2fs yaw_settle=%.2fs (start %.3f)" % [b, absf(target), t90, back, yaw_settle, steer0])


func _slalom(b: int, kmh: float) -> void:
	var v := kmh / 3.6
	await _reach(v)
	var lat_max := 0.0
	var h0 := _heading()
	var hmin := 0.0
	var hmax := 0.0
	var prev: Vector3 = car.linear_velocity
	var beta_max := 0.0
	for k in 6:
		_steer(1.0 if k % 2 == 0 else -1.0)
		for i in 60:
			_cruise(v)
			await _ticks(1)
			var vel: Vector3 = car.linear_velocity
			var acc := (vel - prev) * Engine.physics_ticks_per_second
			lat_max = maxf(lat_max, absf(acc.dot(car.global_basis.x)) / 9.8)
			prev = vel
			_tr("slalom%.0f" % kmh)
			var dh := wrapf(_heading() - h0, -PI, PI)
			hmin = minf(hmin, dh)
			hmax = maxf(hmax, dh)
			var flat := Vector3(vel.x, 0.0, vel.z)
			beta_max = maxf(beta_max, absf(rad_to_deg((-car.global_basis.z).signed_angle_to(flat, Vector3.UP))))
	_steer(0.0)
	var settle := -1.0
	for i in 300:
		_cruise(v)
		await _ticks(1)
		_tr("slalom%.0f" % kmh)
		if settle < 0.0 and absf(car.angular_velocity.y) < 0.03:
			settle = (i + 1) / float(Engine.physics_ticks_per_second)
	print("SLALOM body=%d %.0f km/h lat_peak=%.2f g swing=%.1f..%.1f deg beta_max=%.1f settle=%.2fs spd=%.1f up=%.2f" % [b, kmh,
		lat_max, rad_to_deg(hmin), rad_to_deg(hmax), beta_max, settle, _speed() * 3.6, car.global_basis.y.y])


func _junction(b: int, dir: float) -> void:
	var v := 40.0 / 3.6
	await _reach(v)
	var p0: Vector3 = car.global_position
	var h0 := _heading()
	_steer(dir)
	var t := 0.0
	var turned := 0.0
	var pmid := p0
	for i in 600:
		_cruise(v)
		await _ticks(1)
		t += 1.0 / Engine.physics_ticks_per_second
		_tr("junction" + ("R" if dir > 0.0 else "L"))
		turned = absf(wrapf(_heading() - h0, -PI, PI))
		if turned >= PI * 0.25 and pmid == p0:
			pmid = car.global_position
		if turned >= PI * 0.5:
			break
	_steer(0.0)
	var p1: Vector3 = car.global_position
	var radius := Vector2(p1.x - p0.x, p1.z - p0.z).length() / sqrt(2.0)
	var over := 0.0
	for i in 120:
		_cruise(v)
		await _ticks(1)
		_tr("junction" + ("R" if dir > 0.0 else "L"))
		over = maxf(over, absf(wrapf(_heading() - h0, -PI, PI)) - PI * 0.5)
	print("JUNCTION body=%d %s 40 km/h t=%.2fs radius=%.1f m overshoot=%.1f deg exit=%.1f km/h" % [b,
		"R" if dir > 0.0 else "L", t, radius, rad_to_deg(over), _speed() * 3.6])


## 0-100 km/h, then a stop from 100 (both on the throttle / brake keys alone).
func _accel(b: int) -> void:
	var t := 0.0
	var t60 := -1.0
	while _speed() < 100.0 / 3.6 and t < 30.0:
		Input.action_press("move_forward", 1.0)
		await _ticks(1)
		t += 1.0 / Engine.physics_ticks_per_second
		if t60 < 0.0 and _speed() >= 60.0 / 3.6:
			t60 = t
	Input.action_release("move_forward")
	var p0: Vector3 = car.global_position
	var tb := 0.0
	while _speed() > 0.5 and tb < 20.0:
		Input.action_press("move_back", 1.0)
		await _ticks(1)
		tb += 1.0 / Engine.physics_ticks_per_second
	Input.action_release("move_back")
	print("ACCEL body=%d 0-60=%.2fs 0-100=%.2fs stop_100=%.1f m in %.2fs" % [b, t60, t, car.global_position.distance_to(p0), tb])


## Full lock forced at 70 km/h (past what the speed-sensitive lock gives): at the limit, does the
## car push wide (understeer, front slip) or spin (beta grows)?
func _limit(b: int) -> void:
	await _reach(70.0 / 3.6)
	var keep: float = DriveHandling.high_lock
	DriveHandling.high_lock = 0.6
	_steer(1.0)
	var beta_max := 0.0
	var yaw_sum := 0.0
	var n := 0
	for i in 150:
		_cruise(70.0 / 3.6)
		await _ticks(1)
		var vel: Vector3 = car.linear_velocity
		var flat := Vector3(vel.x, 0.0, vel.z)
		if flat.length() > 2.0:
			beta_max = maxf(beta_max, absf(rad_to_deg((-car.global_basis.z).signed_angle_to(flat, Vector3.UP))))
		if i >= 60:
			yaw_sum += absf(car.angular_velocity.y)
			n += 1
	DriveHandling.high_lock = keep
	_steer(0.0)
	print("LIMIT body=%d 70 km/h full lock: yaw=%.1f deg/s beta_max=%.1f spd=%.1f up=%.2f" % [b,
		rad_to_deg(yaw_sum / maxf(n, 1)), beta_max, _speed() * 3.6, car.global_basis.y.y])


## A rear kick at 80 km/h (a yaw impulse of 1.6 rad/s, the hands off): with the counter-steer
## assist (gain -1 = the class default) and without (0). Prints the slip peak, the heading change
## and the seconds back under 3 degrees of slip.
func _recover(b: int, gain: float) -> void:
	var keep: float = DriveHandling.assist_gain
	if gain >= 0.0:
		DriveHandling.assist_gain = gain
	await _reach(80.0 / 3.6)
	var h0 := _heading()
	var av: Vector3 = car.angular_velocity
	av.y += float(OS.get_environment("KICK")) if OS.get_environment("KICK") != "" else 4.0
	car.angular_velocity = av
	var beta_max := 0.0
	var back := -1.0
	for i in 300:
		_cruise(80.0 / 3.6)
		await _ticks(1)
		_tr("kick")
		var vel: Vector3 = car.linear_velocity
		var flat := Vector3(vel.x, 0.0, vel.z)
		var beta := absf(rad_to_deg((-car.global_basis.z).signed_angle_to(flat, Vector3.UP))) if flat.length() > 2.0 else 0.0
		beta_max = maxf(beta_max, beta)
		if back < 0.0 and i > 20 and beta < 3.0 and absf(car.angular_velocity.y) < 0.1:
			back = (i + 1) / float(Engine.physics_ticks_per_second)
	DriveHandling.assist_gain = keep
	print("RECOVER body=%d gain=%s beta_max=%.1f heading=%.1f deg back=%.2fs spd=%.1f" % [b,
		"default" if gain < 0.0 else str(gain), beta_max, rad_to_deg(wrapf(_heading() - h0, -PI, PI)), back, _speed() * 3.6])
