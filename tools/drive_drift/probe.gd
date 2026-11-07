extends Node
## Drift probe: a car on a flat 2 km slab, the driver's controls fed through Input actions, numbers
## printed per scenario (max slip angle, seconds sliding, heading turned, speed kept, spun or not).
## Headless, a minute:
##   godot --headless --path . --fixed-fps 60 tools/drive_drift/probe.tscn
## TYPES=0,3,36 (Vehicle.BodyType ints) picks bodies; SCEN=drift_r,drift_l,u180,jturn,power,launch.
## DRIVE_DRIFT=0 is the before.

const ACTIONS := ["move_left", "move_right", "move_forward", "move_back", "alt_fire", "boost"]
var car: Vehicle
var dummy: Node3D
var rows: Array = []


func _ready() -> void:
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2400, 2, 2400)
	cs.shape = box
	cs.position = Vector3(0, -1, 0)
	ground.add_child(cs)
	add_child(ground)
	dummy = Node3D.new()
	add_child(dummy)
	_run.call_deferred()


func _types() -> Array:
	var s := OS.get_environment("TYPES")
	if s == "":
		return [Vehicle.BodyType.SEDAN, Vehicle.BodyType.SPORTS, Vehicle.BodyType.MUSCLE, Vehicle.BodyType.PICKUP]
	var out := []
	for p in s.split(","):
		out.append(int(p))
	return out


func _scens() -> Array:
	var s := OS.get_environment("SCEN")
	if s == "":
		return ["drift_r", "drift_l", "u180", "jturn", "power", "launch"]
	return Array(s.split(","))


func _run() -> void:
	for t in _types():
		for sc in _scens():
			await _scenario(int(t), str(sc))
	print("DRIFT_PROBE done (DRIVE_DRIFT=%s)" % OS.get_environment("DRIVE_DRIFT"))
	get_tree().quit()


func _new_car(t: int) -> void:
	if car and is_instance_valid(car):
		car.driver = null
		car.queue_free()
		await get_tree().physics_frame
	car = Vehicle.new()
	car.setup(t as Vehicle.BodyType, Color(0.6, 0.1, 0.1), Vehicle.Addon.NONE)
	add_child(car)
	car.global_position = Vector3(0, 1.0, 0)
	for i in 40:
		await get_tree().physics_frame
	car.driver = dummy


func _release() -> void:
	for a in ACTIONS:
		Input.action_release(a)


func _press(a: String, s: float = 1.0) -> void:
	if s <= 0.0:
		Input.action_release(a)
	else:
		Input.action_press(a, s)


func _steer(x: float) -> void:
	_press("move_right", x)
	_press("move_left", -x)


func _slip() -> float:
	var v := car.linear_velocity
	v.y = 0.0
	if v.length() < 1.0:
		return 0.0
	var f := -car.global_basis.z
	f.y = 0.0
	var a := f.signed_angle_to(v, Vector3.UP)
	return rad_to_deg(a)


func _speed() -> float:
	var v := car.linear_velocity
	v.y = 0.0
	return v.length()


func _heading() -> float:
	return rad_to_deg(car.global_rotation.y)


## Accelerate straight to `target` m/s (forward, or backward when target < 0).
func _get_to(target: float) -> float:
	var t := 0.0
	var fwd := target > 0.0
	_press("move_forward" if fwd else "move_back")
	while t < 12.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		var sp := car.linear_velocity.dot(-car.global_basis.z)
		if (fwd and sp >= target) or (not fwd and sp <= target):
			break
	return t


func _scenario(t: int, sc: String) -> void:
	await _new_car(t)
	_release()
	var r := {"type": Vehicle.BODY_NAMES[t], "scen": sc}
	var dt := 1.0 / 60.0
	# Lambdas capture locals by value: the accumulators live in a dictionary.
	var m := {"max_slip": 0.0, "slide_s": 0.0, "spun": false, "peak_yaw": 0.0, "lat_g": 0.0}
	var h0 := 0.0
	var v0 := 0.0
	var turned := 0.0
	var last_h := 0.0
	var acc := func() -> void:
		var s := absf(_slip())
		m.max_slip = maxf(m.max_slip, s)
		m.peak_yaw = maxf(m.peak_yaw, absf(rad_to_deg(car.angular_velocity.y)))
		if s > 15.0 and _speed() > 2.0:
			m.slide_s += dt
		if s > 120.0 and _speed() > 4.0:
			m.spun = true
		if OS.get_environment("TRACE") != "" and Engine.get_physics_frames() % 4 == 0:
			var st: Variant = DriveDrift.state_of(car)
			print("  T beta=%.1f yaw=%.0f spd=%.1f mode=%s amt=%.2f g=%s" % [_slip(), rad_to_deg(car.angular_velocity.y),
					_speed(), str(st.mode) if st else "-", st.amount if st else 0.0, str(st.grip) if st else "-"])
	match sc:
		"launch":
			_press("move_forward")
			var tt := 0.0
			var t100 := -1.0
			while tt < 15.0:
				await get_tree().physics_frame
				tt += dt
				if t100 < 0.0 and _speed() * 3.6 >= 100.0:
					t100 = tt
			r["t100"] = t100
			r["top_kmh"] = _speed() * 3.6
		"drift_r", "drift_l":
			var side := 1.0 if sc == "drift_r" else -1.0
			await _get_to(22.0)
			v0 = _speed()
			h0 = _heading()
			last_h = h0
			# kick: steer + handbrake 0.5 s, throttle held
			_steer(side)
			_press("alt_fire")
			for i in 30:
				await get_tree().physics_frame
				acc.call()
				turned += wrapf(_heading() - last_h, -180, 180)
				last_h = _heading()
			Input.action_release("alt_fire")
			# hold: throttle in, stick centred for 2 s (the drift holds itself), then counter-steer
			# for 1 s (it should grip back up).
			var held := 0.0
			for i in 120:
				_steer(0.0)
				await get_tree().physics_frame
				acc.call()
				if absf(_slip()) > 15.0:
					held += dt
				turned += wrapf(_heading() - last_h, -180, 180)
				last_h = _heading()
			r["held_s"] = held
			r["mid_slip"] = absf(_slip())
			r["mid_kept"] = _speed() / maxf(v0, 0.1)
			for i in 60:
				_steer(clampf(-_slip() / 25.0, -1.0, 1.0))
				await get_tree().physics_frame
				acc.call()
				turned += wrapf(_heading() - last_h, -180, 180)
				last_h = _heading()
			r["kept"] = _speed() / maxf(v0, 0.1)
			r["end_slip"] = absf(_slip())
		"u180":
			await _get_to(15.0)
			h0 = _heading()
			last_h = h0
			Input.action_release("move_forward")
			_steer(1.0)
			_press("alt_fire")
			for i in 120:
				await get_tree().physics_frame
				acc.call()
				turned += wrapf(_heading() - last_h, -180, 180)
				last_h = _heading()
			r["end_speed"] = _speed()
		"jturn":
			await _get_to(-11.0)
			h0 = _heading()
			last_h = h0
			Input.action_release("move_back")
			_steer(1.0)
			_press("alt_fire")
			for i in 30:
				await get_tree().physics_frame
				acc.call()
				turned += wrapf(_heading() - last_h, -180, 180)
				last_h = _heading()
			Input.action_release("alt_fire")
			_steer(0.0)
			_press("move_forward")
			for i in 90:
				await get_tree().physics_frame
				acc.call()
				turned += wrapf(_heading() - last_h, -180, 180)
				last_h = _heading()
			r["fwd_speed"] = car.linear_velocity.dot(-car.global_basis.z)
		"power":
			await _get_to(9.0)
			h0 = _heading()
			last_h = h0
			_steer(1.0)
			_press("move_forward")
			for i in 150:
				await get_tree().physics_frame
				acc.call()
				turned += wrapf(_heading() - last_h, -180, 180)
				last_h = _heading()
	_release()
	for k in m:
		r[k] = m[k]
	r["turned"] = turned
	var line := "DRIFT_PROBE"
	for k in r:
		var v: Variant = r[k]
		line += " %s=%s" % [k, ("%.2f" % v) if v is float else str(v)]
	print(line)
