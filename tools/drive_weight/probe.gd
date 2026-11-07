extends Node3D
## Suspension and weight probe (docs/HANDOFF.md "Suspension and weight"): one car on a bare
## ground box, driven by simulated Input actions, headless, a few seconds a scenario.
##
##   godot --headless --path . res://tools/drive_weight/probe.tscn -- --types=0,8,1,3 \
##       --scen=drop,stop,lane,corner,kerb
##
## DRIVE_SUSPENSION=0 is the before. Prints one line per (type, scenario) with the numbers:
##   drop:   a 1 m drop onto the wheels - peak g, bounces (vertical velocity sign flips), settle s
##   stop:   a full stop from 100 km/h - stopping distance, peak nose-down pitch, pitch settle s
##   launch: full throttle from rest for 2 s - peak squat (nose-up pitch)
##   lane:   a lane change at 80 km/h - peak roll, peak lateral g, roll settle s, final heading
##   corner: full lock at 15 m/s for 3 s - steady roll, lateral g, wheels lifted
##   kerb:   a 15 cm kerb at 30 km/h and 20 degrees - speed kept 1 s after, peak vertical g, yaw kick

const TICK := 1.0 / 60.0

var _types: Array = [0, 8, 1, 3]
var _scens: Array = ["drop", "stop", "launch", "lane", "corner", "kerb"]
var _ground: StaticBody3D
var _driver: Node3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--types="):
			_types = Array(a.substr(8).split(",")).map(func(s): return int(s))
		elif a.begins_with("--scen="):
			_scens = Array(a.substr(7).split(","))
	_ground = StaticBody3D.new()
	_ground.collision_layer = 1
	_ground.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2000, 2, 2000)
	cs.shape = box
	cs.position = Vector3(0, -1, 0)
	_ground.add_child(cs)
	add_child(_ground)
	_driver = Node3D.new()
	_driver.name = "ProbeDriver"
	add_child(_driver)
	_run.call_deferred()


func _run() -> void:
	print("DRIVE_WEIGHT probe, DRIVE_SUSPENSION=", OS.get_environment("DRIVE_SUSPENSION"))
	for t: int in _types:
		for s: String in _scens:
			await _scenario(t, s)
	get_tree().quit()


func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "boost", "alt_fire", "jump"]:
		Input.action_release(a)


func _make_car(type: int, at: Vector3, yaw: float) -> Vehicle:
	var car := Vehicle.new()
	car.setup(type, Color(0.5, 0.5, 0.55), Vehicle.Addon.NONE)
	car.position = at
	car.rotation.y = yaw
	add_child(car)
	return car


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _pitch(car: Vehicle) -> float:
	return rad_to_deg(asin(clampf((-car.global_basis.z).y, -1.0, 1.0)))


func _roll(car: Vehicle) -> float:
	return rad_to_deg(asin(clampf(car.global_basis.x.y, -1.0, 1.0)))


## The drawn body's extra lean (DriveSuspension), degrees (roll, pitch).
func _lean(car: Vehicle) -> Vector2:
	var ds := car.get_node_or_null(^"DriveSuspension")
	return ds.lean if ds != null else Vector2.ZERO


## Settles the car on its wheels, seats the probe driver. Returns the rest height.
func _settle(car: Vehicle) -> float:
	await _ticks(150)
	car.driver = _driver
	await _ticks(30)
	return car.global_position.y


func _scenario(type: int, scen: String) -> void:
	_release_all()
	var ground_extra: Array = []
	if scen == "kerb":
		# A kerb along x at z = -20: a 0.15 m step up to a pavement 8 m wide.
		var kb := StaticBody3D.new()
		kb.collision_mask = 0
		var c := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(200, 0.15, 8)
		c.shape = b
		c.position = Vector3(0, 0.075, -24)
		kb.add_child(c)
		add_child(kb)
		ground_extra.append(kb)
	var yaw := 0.0
	if scen == "kerb":
		yaw = deg_to_rad(70.0) # nose -Z turned 70 deg: meets the kerb at 20 degrees
	var car := _make_car(type, Vector3(0, 1.2, -13.0 if scen == "kerb" else 0.0), yaw)
	var rest_y := await _settle(car)
	var rest_pitch := _pitch(car)
	var out := ""
	match scen:
		"drop":
			if OS.get_environment("DW_OFF") == "1":
				for i in 120:
					car.set_physics_process(false)
					car.brake = 2.0
					await _ticks(1)
				rest_y = car.global_position.y
			var rest_hubs: Array = car.wheels.map(func(w): return snappedf(w.position.y, 0.001))
			car.global_position.y = rest_y + 1.0
			car.linear_velocity = Vector3.ZERO
			car.angular_velocity = Vector3.ZERO
			car.hold_crash_watch(3)
			var peak_g := 0.0
			var vy_prev := 0.0
			var flips := 0
			var landed := false
			var settle_t := -1.0
			var still := 0
			for i in 300:
				if OS.get_environment("DW_OFF") == "1":
					car.set_physics_process(false)
					car.brake = 2.0
				await _ticks(1)
				var vy := car.linear_velocity.y
				var g := (vy - vy_prev) / TICK / 9.8
				if landed:
					peak_g = maxf(peak_g, g)
					if signf(vy) != signf(vy_prev) and absf(vy) > 0.02:
						flips += 1
					if absf(vy) < 0.03 and absf(car.global_position.y - rest_y) < 0.015:
						still += 1
						if still == 10 and settle_t < 0.0:
							settle_t = (i - 9) * TICK
					else:
						still = 0
				if not landed and not car.is_airborne():
					landed = true
				vy_prev = vy
			out = "peak_g=%.2f bounces=%d settle_s=%.2f after_dy_cm=%.1f" % [peak_g, flips, settle_t, (car.global_position.y - rest_y) * 100.0]
			if OS.get_environment("DW_DEBUG") == "1":
				print("DWDBG hubs ", car.wheels.map(func(w): return snappedf(w.position.y, 0.001)), " pitch ", _pitch(car), " roll ", _roll(car), " rest ", rest_hubs)
		"stop":
			var fwd := -car.global_basis.z
			car.linear_velocity = fwd * 27.78
			car.hold_crash_watch(3)
			Input.action_press("move_forward")
			await _ticks(20)
			Input.action_release("move_forward")
			var p0 := car.global_position
			Input.action_press("move_back")
			var peak := 0.0
			var vis := 0.0
			var t := 0
			while car.linear_velocity.dot(fwd) > 0.5 and t < 600:
				await _ticks(1)
				peak = minf(peak, _pitch(car) - rest_pitch)
				vis = minf(vis, _lean(car).y)
				t += 1
			Input.action_release("move_back")
			var dist := (car.global_position - p0).dot(fwd)
			var settle := await _settle_angle(car, rest_pitch, true)
			out = "dist_m=%.1f stop_s=%.2f nose_dive_deg=%.2f drawn_extra=%.2f settle_s=%.2f" % [dist, t * TICK, peak, vis, settle]
		"launch":
			Input.action_press("move_forward")
			var peak := 0.0
			var vis := 0.0
			for i in 120:
				await _ticks(1)
				peak = maxf(peak, _pitch(car) - rest_pitch)
				vis = maxf(vis, _lean(car).y)
			Input.action_release("move_forward")
			out = "squat_deg=%.2f drawn_extra=%.2f speed_2s=%.1f" % [peak, vis, car.linear_velocity.length()]
		"lane":
			var fwd := -car.global_basis.z
			car.linear_velocity = fwd * 22.2
			car.hold_crash_watch(3)
			Input.action_press("move_forward")
			await _ticks(10)
			var peak_roll := 0.0
			var peak_lat := 0.0
			var lift := 0
			var vprev := car.linear_velocity
			for phase in [["move_right", 30], ["move_left", 30], ["", 20]]:
				if phase[0] != "":
					Input.action_press(phase[0])
				for i in int(phase[1]):
					await _ticks(1)
					peak_roll = maxf(peak_roll, absf(_roll(car)))
					var acc := (car.linear_velocity - vprev) / TICK
					vprev = car.linear_velocity
					peak_lat = maxf(peak_lat, absf(acc.dot(car.global_basis.x)) / 9.8)
					for w in car.wheels:
						if not w.is_in_contact():
							lift += 1
				if phase[0] != "":
					Input.action_release(phase[0])
			var settle := await _settle_angle(car, 0.0, false)
			Input.action_release("move_forward")
			var head := rad_to_deg(car.global_basis.z.signed_angle_to(-fwd * -1.0, Vector3.UP))
			out = "peak_roll_deg=%.2f peak_lat_g=%.2f roll_settle_s=%.2f wheel_lift_ticks=%d speed=%.1f" % [peak_roll, peak_lat, settle, lift, car.linear_velocity.length()]
		"corner":
			var fwd := -car.global_basis.z
			car.linear_velocity = fwd * 15.0
			car.hold_crash_watch(3)
			Input.action_press("move_forward")
			Input.action_press("move_right")
			var rolls := 0.0
			var lats := 0.0
			var n := 0
			var lift := 0
			var maxroll := 0.0
			var visr := 0.0
			for i in 180:
				await _ticks(1)
				maxroll = maxf(maxroll, absf(_roll(car)))
				visr = maxf(visr, absf(_lean(car).x))
				for w in car.wheels:
					if not w.is_in_contact():
						lift += 1
				if i >= 90:
					rolls += _roll(car)
					var v := car.linear_velocity
					lats += v.length() * car.angular_velocity.y / 9.8
					n += 1
			Input.action_release("move_right")
			Input.action_release("move_forward")
			out = "steady_roll_deg=%.2f max_roll_deg=%.2f drawn_extra=%.2f lat_g=%.2f wheel_lift_ticks=%d speed=%.1f upright=%.2f" % [rolls / n, maxroll, visr, lats / n, lift, car.linear_velocity.length(), car.global_basis.y.y]
		"kerb":
			var fwd := -car.global_basis.z
			car.linear_velocity = fwd * 8.33
			car.hold_crash_watch(3)
			Input.action_press("move_forward")
			# Hold 30 km/h: throttle off once over.
			var v0 := 8.33
			var peak_g := 0.0
			var vyp := 0.0
			var t_hit := -1
			var min_v := 99.0
			var yaw0 := car.rotation.y
			var yawkick := 0.0
			for i in 360:
				await _ticks(1)
				if car.linear_velocity.dot(fwd) > 8.4:
					Input.action_release("move_forward")
				elif not Input.is_action_pressed("move_forward"):
					Input.action_press("move_forward")
				var vy := car.linear_velocity.y
				peak_g = maxf(peak_g, absf(vy - vyp) / TICK / 9.8)
				vyp = vy
				if t_hit < 0 and car.global_position.z < -18.0:
					t_hit = i
				if t_hit >= 0 and i < t_hit + 60:
					min_v = minf(min_v, car.linear_velocity.length())
					yawkick = maxf(yawkick, absf(rad_to_deg(wrapf(car.rotation.y - yaw0, -PI, PI))))
				if t_hit >= 0 and i >= t_hit + 60:
					break
			Input.action_release("move_forward")
			var on_top := car.global_position.y > rest_y + 0.1
			out = "min_speed_after=%.2f (of %.2f) peak_vert_g=%.2f yaw_kick_deg=%.2f on_pavement=%s z=%.1f" % [min_v, v0, peak_g, yawkick, on_top, car.global_position.z]
	print("DW %-8s type=%-2d %s  %s" % [scen, type, Vehicle.BODY_NAMES[type], out])
	car.driver = null
	car.queue_free()
	for n in ground_extra:
		n.queue_free()
	await _ticks(2)


## Seconds until the pitch (or roll) stays within 0.25 deg of `target` for 0.3 s.
func _settle_angle(car: Vehicle, target: float, pitch: bool) -> float:
	var still := 0
	for i in 300:
		await _ticks(1)
		var a := _pitch(car) if pitch else _roll(car)
		if absf(a - target) < 0.25 and absf(car.angular_velocity.length()) < 0.05:
			still += 1
			if still >= 18:
				return (i - 17) * TICK
		else:
			still = 0
	return 5.0
