extends Node3D
## Drive-assist probe (headless, a minute): the player's car on a flat 2 km slab, driven by
## simulated Input actions, every scenario run twice - DriveAssist off, then on - so one run is
## the A/B. Prints one line per scenario:
##   accel       full throttle from rest: speed at 2 / 4 s, time to 100 km/h
##   turn_l/r    at v0 full throttle and full lock: mean yaw rate (deg/s), lateral g, peak body
##               slip (deg), spun = the slip passed 50 degrees
##   power       at v0 full lock, throttle and nitro (boost): the spin test
##   brake       at v0 brake (S) and full left lock: stopping distance, heading change, peak slip
##   lift        at v0 full lock, throttle then lifted: lift-off oversteer
##   ai_*        a car with no driver chasing a target point on DriveAssist.ai_drive (assist on)
##               or the old pursuit law (off): a slalom and a U-turn
##   godot --headless --path . --fixed-fps 60 res://tools/drive_assist/probe.tscn
##   TYPES=0,3,8,1 (BodyType ints), ONLY=turn_r,power, FLAT=1 a flat front tyre (ChaseFlatTyres-
##   style grip cut on one rear wheel)

var driver: Node3D
var results: Array = []


## A car the AI drives: like PoliceCar, its own _physics_process (the driverless Vehicle code would
## zero the pedals each tick), the brain called each step.
class AiCar extends Vehicle:
	var brain: Callable
	func _physics_process(delta: float) -> void:
		_update_wheels(delta)
		if brain.is_valid():
			brain.call(delta)


func _ready() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	ground.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(4000, 1, 4000)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	ground.add_child(cs)
	add_child(ground)
	driver = Node3D.new()
	add_child(driver)
	_run.call_deferred()


func _types() -> Array:
	var s := OS.get_environment("TYPES")
	if s == "":
		return [Vehicle.BodyType.SEDAN, Vehicle.BodyType.SPORTS, Vehicle.BodyType.CROSSOVER, Vehicle.BodyType.PICKUP]
	var out := []
	for p in s.split(","):
		out.append(int(p))
	return out


func _want(name: String) -> bool:
	var only := OS.get_environment("ONLY")
	return only == "" or name in only.split(",")


func _run() -> void:
	var scen := [
		["accel", 0.0], ["turn_r", 15.0], ["turn_l", 15.0], ["turn_r", 28.0], ["turn_l", 28.0],
		["power", 20.0], ["brake", 28.0], ["lift", 26.0],
	]
	for type in _types():
		for s in scen:
			if not _want(s[0]):
				continue
			for on in [false, true]:
				DriveAssist.enabled = on
				var r: Dictionary = await _scenario(type, s[0], s[1])
				print("DRIVE %-10s %-7s v0=%4.1f assist=%d %s" % [Vehicle.BODY_NAMES[type], s[0], s[1], int(on), _fmt(r)])
	for s in [["ai_slalom", 22.0], ["ai_uturn", 18.0]]:
		if not _want(s[0]):
			continue
		for on in [false, true]:
			DriveAssist.enabled = on
			var r: Dictionary = await _ai(s[0], s[1])
			print("DRIVE %-10s %-7s v0=%4.1f assist=%d %s" % ["Police law", s[0], s[1], int(on), _fmt(r)])
	print("DONE")
	get_tree().quit()


func _fmt(r: Dictionary) -> String:
	var keys := r.keys()
	keys.sort()
	var parts := []
	for k in keys:
		var v = r[k]
		parts.append("%s=%s" % [k, ("%.2f" % v) if v is float else str(v)])
	return " ".join(parts)


func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "boost", "alt_fire", "jump"]:
		Input.action_release(a)


func _make(type: int, ai: bool = false) -> Vehicle:
	var car: Vehicle = AiCar.new() if ai else Vehicle.new()
	car.setup(type, Color(0.6, 0.1, 0.1), 0)
	car.position = Vector3(0, 0.9, 0)
	add_child(car)
	for i in 70:
		await get_tree().physics_frame
	if OS.get_environment("FLAT") == "1" and car.wheels.size() >= 4:
		car.wheels[3].wheel_friction_slip *= 0.35
	return car


func _frame(car: Vehicle) -> Array:
	var b := car.global_basis
	var v := car.linear_velocity
	var fwd := -b.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0, fwd.x)
	var vl := v.dot(fwd)
	var vs := v.dot(right)
	# Slip means nothing at a crawl (the last metre of a stop): only measured over 3 m/s.
	var beta := rad_to_deg(atan2(vs, maxf(absf(vl), 0.5))) if Vector2(vl, vs).length() > 3.0 else 0.0
	return [vl, vs, beta, fwd]


func _scenario(type: int, kind: String, v0: float) -> Dictionary:
	_release_all()
	var car: Vehicle = await _make(type)
	var r := {}
	if v0 > 0.0:
		car.linear_velocity = -car.global_basis.z * v0
	car.driver = driver
	var dt := 1.0 / 60.0
	var t := 0.0
	var start := car.global_position
	var yaw0 := car.global_rotation.y
	var max_beta := 0.0
	var yaw_sum := 0.0
	var lat_sum := 0.0
	var n := 0
	var prev_v := car.linear_velocity
	match kind:
		"accel":
			Input.action_press("move_forward")
			var t100 := -1.0
			while t < 12.0:
				await get_tree().physics_frame
				t += dt
				var spd: float = _frame(car)[0]
				if is_equal_approx(t, 2.0) or absf(t - 2.0) < dt * 0.5:
					r.v2 = spd
				if absf(t - 4.0) < dt * 0.5:
					r.v4 = spd
				if t100 < 0.0 and spd >= 27.78:
					t100 = t
			r.t100 = t100
			r.vmax = _frame(car)[0]
		"turn_r", "turn_l", "power", "lift":
			Input.action_press("move_forward")
			Input.action_press("move_left" if kind == "turn_l" else "move_right")
			if kind == "power":
				Input.action_press("boost")
			var dur := 3.0
			while t < dur:
				await get_tree().physics_frame
				t += dt
				if kind == "lift" and t > 1.2:
					Input.action_release("move_forward")
				var f := _frame(car)
				max_beta = maxf(max_beta, absf(f[2]))
				if OS.get_environment("TRAJ") == "1" and Engine.get_physics_frames() % 3 == 0:
					_traj(car, "%s_%s_%d_%d" % [Vehicle.BODY_NAMES[type], kind, int(v0), int(DriveAssist.enabled)])
				if OS.get_environment("TRACE") == "1" and Engine.get_physics_frames() % 6 == 0:
					print("TR t=%.2f v=%.1f beta=%.1f yaw=%.2f steer=%.3f ef=%.0f k=%.2f y=%.2f vy=%.2f roll=%.2f grav=%.2f contact=%s skid=%s" % [t, f[0], f[2], car.angular_velocity.y, car.steering, car.engine_force, float(car.get_meta("da_k", 0.0)), car.global_position.y, car.linear_velocity.y, car.global_basis.x.y, car.gravity_scale, str(car.wheels.map(func(w): return int(w.is_in_contact()))), str(car.wheels.map(func(w): return snappedf(w.get_skidinfo(), 0.01)))])
				if t > 1.0:
					var acc := (car.linear_velocity - prev_v) / dt
					var right := Vector3(-f[3].z, 0, f[3].x)
					yaw_sum += rad_to_deg(car.angular_velocity.y)
					lat_sum += acc.dot(right) / 9.8
					n += 1
				prev_v = car.linear_velocity
			r.yaw = yaw_sum / maxf(n, 1)
			r.lat_g = lat_sum / maxf(n, 1)
			r.beta = max_beta
			r.spun = int(max_beta > 50.0)
			r.v_end = _frame(car)[0]
		"brake":
			Input.action_press("move_back")
			Input.action_press("move_left")
			while t < 6.0:
				await get_tree().physics_frame
				t += dt
				var f := _frame(car)
				max_beta = maxf(max_beta, absf(f[2]))
				if OS.get_environment("TRACE") == "1" and Engine.get_physics_frames() % 6 == 0:
					print("TR t=%.2f v=%.1f beta=%.1f yaw=%.2f steer=%.3f br=%s k=%.2f roll=%.2f contact=%s skid=%s" % [t, f[0], f[2], car.angular_velocity.y, car.steering, str(car.wheels.map(func(w): return int(w.brake))), float(car.get_meta("da_k", 0.0)), car.global_basis.x.y, str(car.wheels.map(func(w): return int(w.is_in_contact()))), str(car.wheels.map(func(w): return snappedf(w.get_skidinfo(), 0.01)))])
				if f[0] < 1.0:
					break
			r.t_stop = t
			r.dist = (car.global_position - start).length()
			r.turned = rad_to_deg(absf(wrapf(car.global_rotation.y - yaw0, -PI, PI)))
			r.beta = max_beta
	_release_all()
	car.driver = null
	car.queue_free()
	await get_tree().physics_frame
	return r


## A driverless car steering at moving target points: the slalom weaves gates 30 m apart, 6 m
## either side; the U-turn aims at a point behind it.
func _ai(kind: String, v0: float) -> Dictionary:
	_release_all()
	var car: AiCar = await _make(Vehicle.BodyType.SEDAN, true)
	car.engine_power = 8200.0
	car.mass = 1500.0
	car.linear_velocity = -car.global_basis.z * v0
	var start := car.global_position
	var dt := 1.0 / 60.0
	var t := 0.0
	var max_beta := 0.0
	var miss := 0.0
	var gates := 0
	var r := {}
	var fwd0 := -car.global_basis.z
	var side0 := Vector3(-fwd0.z, 0, fwd0.x)
	var st := {"aim": Vector3.ZERO, "want": v0}
	car.brain = func(d: float) -> void:
		var f := _frame(car)
		var to: Vector3 = st.aim - car.global_position
		to.y = 0
		var dir := to.normalized()
		var fwd: Vector3 = f[3]
		var ang := atan2(fwd.cross(dir).y, fwd.dot(dir))
		st.ang = ang
		var spd: float = f[0]
		var want: float = st.want
		if DriveAssist.enabled:
			DriveAssist.ai_drive(car, ang, want, d)
		else:
			# PoliceCar._pursue's law as it was.
			car.steering = lerpf(car.steering, clampf(ang * 1.8, -car.max_steer, car.max_steer), 1.0 - exp(-car.steer_speed * d))
			if spd < want:
				car.engine_force = -car.engine_power * clampf((want - spd) / 6.0, 0.25, 1.0)
				car.brake = 0.0
			else:
				car.engine_force = 0.0
				car.brake = car.brake_force * clampf((spd - want) / 8.0, 0.1, 1.0)
	var gate_hits := 0
	var last_k := 0
	while t < (12.0 if kind == "ai_slalom" else 8.0):
		if kind == "ai_slalom":
			var along := (car.global_position - start).dot(fwd0)
			var k := floori(along / 30.0) + 1
			st.aim = start + fwd0 * (k * 30.0) + side0 * (6.0 if k % 2 == 0 else -6.0)
			if k != last_k and k > 1:
				var lat := (car.global_position - start).dot(side0)
				var gate := 6.0 if (k - 1) % 2 == 0 else -6.0
				miss = maxf(miss, absf(lat - gate))
				if absf(lat - gate) < 3.0:
					gate_hits += 1
			last_k = k
		else:
			st.aim = start - fwd0 * 40.0
			st.want = 14.0
		await get_tree().physics_frame
		t += dt
		var f := _frame(car)
		max_beta = maxf(max_beta, absf(f[2]))
		if OS.get_environment("TRAJ") == "1" and Engine.get_physics_frames() % 3 == 0:
			_traj(car, "police_%s_%d" % [kind, int(DriveAssist.enabled)], start)
		if OS.get_environment("AI_TRACE") == "1" and Engine.get_physics_frames() % 15 == 0:
			print("AI t=%.2f ang=%.2f spd=%.1f steer=%.2f yaw=%.2f ef=%.0f br=%.0f" % [t, float(st.get("ang", 0.0)), f[0], car.steering, car.angular_velocity.y, car.engine_force, car.brake])
		if kind == "ai_uturn" and absf(float(st.get("ang", 9.0))) < 0.2 and not r.has("t_turn") and t > 0.5:
			r.t_turn = t
	r.gates = gate_hits
	r.miss = miss
	r.beta = max_beta
	r.spun = int(max_beta > 50.0)
	if kind == "ai_slalom":
		r.dist = (car.global_position - start).dot(fwd0)
	car.queue_free()
	await get_tree().physics_frame
	return r


## TRAJ=1: one line per few ticks - the car's centre and heading relative to where it started.
func _traj(car: Vehicle, label: String, origin: Vector3 = Vector3(0, 0, 0)) -> void:
	var p := car.global_position - origin
	print("TJ %s %.2f %.2f %.3f %.2f" % [label, p.x, p.z, car.global_rotation.y, car.global_basis.x.y])
