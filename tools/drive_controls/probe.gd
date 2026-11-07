extends Node3D
## Headless probe of the player car's INPUT paths (drive-controls, wave 9).
##   godot --headless --path . res://tools/drive_controls/probe.tscn
##   DRIVE_INPUT=0 ... (the A/B)   BODY=<BodyType index> (default sedan)   MOTO=1 a motorcycle
## A 4 km concrete slab, the player in a car, driven by Input.action_press and parsed joypad /
## mouse events. Prints one PROBE line per measurement: keyboard 0-100 km/h, W+D diagonal
## throttle and steer, a hold-S brake to stop and the gap before reverse engages, the reverse
## to forward change, the pad's triggers (RT / LT) and the handbrake buttons, and the yaw rate
## left vs right at 15 m/s.

var car: Vehicle
var player: Node


func _ready() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	ground.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000.0, 2.0, 4000.0)
	cs.shape = box
	cs.position.y = -1.0
	ground.add_child(cs)
	add_child(ground)
	player = load("res://scenes/player/player.tscn").instantiate()
	add_child(player)
	player.global_position = Vector3(30.0, 1.0, 0.0)
	if OS.get_environment("MOTO") == "1":
		car = Motorcycle.make(Vehicle.BodyType.MOTO_SPORT, 3)
	if car == null:
		car = Vehicle.new()
		var bt := int(OS.get_environment("BODY")) if OS.get_environment("BODY") != "" else int(Vehicle.BodyType.SEDAN)
		car.setup(bt, Color(0.5, 0.05, 0.05), Vehicle.Addon.NONE)
	add_child(car)
	car.global_position = Vector3(0.0, 0.8, 1800.0)
	await _frames(30)
	player.enter_vehicle(car)
	await _frames(20)
	await _run()
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "alt_fire", "boost"]:
		Input.action_release(a)
	for ax in [4, 5]:
		_axis(ax, 0.0)
	_mouse(MOUSE_BUTTON_RIGHT, false)
	_button(JOY_BUTTON_RIGHT_SHOULDER, false)


func _axis(axis: int, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = axis
	e.axis_value = v
	Input.parse_input_event(e)


func _button(b: int, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = b
	e.pressed = down
	Input.parse_input_event(e)


func _mouse(b: int, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = b
	e.pressed = down
	Input.parse_input_event(e)


## Put the car back on the slab, nose down -Z, at `v` m/s.
func _reset(v: float) -> void:
	_release_all()
	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.75, 1800.0))
	car.angular_velocity = Vector3.ZERO
	car.linear_velocity = Vector3(0.0, 0.0, -v)
	if car.has_method("hold_crash_watch"):
		car.hold_crash_watch(5)
	await _frames(4)
	car.linear_velocity = Vector3(0.0, 0.0, -v)


func _fwd() -> float:
	return car.linear_velocity.dot(-car.global_basis.z)


func _p(s: String) -> void:
	print("PROBE ", s)


func _run() -> void:
	_p("input %s body %d mass %.0f engine_power %.0f" % ["drive_input" if _di() else "old", car.body_type, car.mass, car.engine_power])
	# 1. Keyboard 0-100.
	await _reset(0.0)
	Input.action_press("move_forward")
	var t := 0.0
	var t60 := -1.0
	var t100 := -1.0
	while t < 20.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		var kmh := _fwd() * 3.6
		if t60 < 0.0 and kmh >= 60.0:
			t60 = t
		if kmh >= 100.0:
			t100 = t
			break
	_p("kb_accel t60 %.2f t100 %.2f" % [t60, t100])
	# 2. W vs W+D at 10 m/s: engine force and the steer target.
	await _reset(10.0)
	Input.action_press("move_forward")
	await _frames(6)
	var ef_w := car.engine_force
	Input.action_press("move_right")
	await _frames(30)
	_p("kb_diag ef_W %.0f ef_WD %.0f ratio %.2f steer_WD %.3f (max %.3f)" % [ef_w, car.engine_force, car.engine_force / minf(ef_w, -0.001), car.steering, car.max_steer])
	# 3. Hold S from 60 km/h: time to stop, then how long until reverse drive engages.
	await _reset(60.0 / 3.6)
	Input.action_press("move_back")
	t = 0.0
	var t_stop := -1.0
	var t_rev := -1.0
	var brake_seen := 0.0
	while t < 8.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		brake_seen = maxf(brake_seen, car.brake)
		if t_stop < 0.0 and _fwd() < 0.3:
			t_stop = t
		if t_rev < 0.0 and car.engine_force > 0.0:
			t_rev = t
	_p("kb_brake brake %.0f t_stop %.2f t_reverse %.2f gap %.2f rev_speed_end %.1f" % [brake_seen, t_stop, t_rev, t_rev - t_stop, _fwd()])
	# 4. Reversing at 6 m/s, press W: brake first or throttle against the roll?
	await _reset(-6.0)
	Input.action_press("move_forward")
	await _frames(3)
	_p("rev_then_W engine_force %.0f brake %.1f" % [car.engine_force, car.brake])
	# 5. The pad's triggers: RT half and full, LT half (stick centred).
	await _reset(5.0)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.5)
	await _frames(4)
	var rt_half := car.engine_force
	_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await _frames(4)
	var rt_full := car.engine_force
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await _reset(15.0)
	_axis(JOY_AXIS_TRIGGER_LEFT, 0.4)
	await _frames(4)
	var lt_brake := car.brake
	var lt_ef := car.engine_force
	_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await _frames(4)
	_p("pad_triggers RT0.5 ef %.0f RT1.0 ef %.0f | LT0.4 brake %.1f ef %.0f LT1.0 brake %.1f" % [rt_half, rt_full, lt_brake, lt_ef, car.brake])
	# 6. Handbrake: right mouse, pad RB.
	await _reset(15.0)
	_mouse(MOUSE_BUTTON_RIGHT, true)
	await _frames(3)
	var hb_mouse := car.brake
	_mouse(MOUSE_BUTTON_RIGHT, false)
	_button(JOY_BUTTON_RIGHT_SHOULDER, true)
	await _frames(3)
	_p("handbrake mouseR brake %.1f padRB brake %.1f (handbrake_force %.0f)" % [hb_mouse, car.brake, car.handbrake_force])
	# 7. Yaw rate at 15 m/s, A vs D, full lock held 1.5 s with the throttle on.
	for dir in ["move_left", "move_right"]:
		await _reset(15.0)
		Input.action_press("move_forward")
		Input.action_press(dir)
		var peak := 0.0
		var lat := 0.0
		for i in 90:
			await get_tree().physics_frame
			if i > 40:
				peak = maxf(peak, absf(car.angular_velocity.y))
				lat = maxf(lat, absf(car.linear_velocity.dot(car.global_basis.x)))
		_p("yaw %s 15m/s peak %.3f rad/s sign %+.0f speed_end %.1f" % [dir, peak, signf(car.angular_velocity.y), _fwd()])
	# 8. Steer return: full D for 1 s at 10 m/s, release, time for steering to fall under 10 %.
	await _reset(10.0)
	Input.action_press("move_forward")
	Input.action_press("move_right")
	await _frames(60)
	var s0 := absf(car.steering)
	Input.action_release("move_right")
	t = 0.0
	while absf(car.steering) > s0 * 0.1 and t < 3.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	_p("steer_return from %.3f to 10%% in %.2f s" % [s0, t])
	_release_all()


func _di() -> bool:
	return ResourceLoader.exists("res://scripts/vehicles/drive_input.gd") and OS.get_environment("DRIVE_INPUT") != "0"
