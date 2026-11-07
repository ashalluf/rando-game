extends Node3D
## Drive-collide probe (scripts/vehicles/drive_impacts.gd): a flat deck far from any city, the
## player's car (a stand-in driver, simulated move_forward), and one scenario at a time:
##   traffic   50 km/h into a stationary kinematic traffic car (a sedan), straight and offset
##   bus       50 km/h into a stationary traffic bus
##   wall      a 30-degree glancing hit on a long wall at 50 and 80 km/h
##   headon    50 km/h square into the wall
##   parked    50 km/h into a parked (physical, empty) car
##   wedge     nose against a post with throttle held: how long until it is free
## Prints one PROBE line per scenario (speeds before / 1 s after, the other car's speed, how far
## the heading turned). Run, headless, from the repo:
##   godot --headless --path . res://tools/drive_collide/probe.tscn
##   DRIVE_IMPACTS=0 godot ... (the before)       SCEN=wall,traffic (a subset)

var _deck: StaticBody3D
var _items: Array[Node] = []


func _ready() -> void:
	_deck = _static_box(Vector3(800, 1, 800), Vector3(0, -0.5, 0))
	await get_tree().physics_frame
	var only := OS.get_environment("SCEN")
	var all := ["traffic", "offset", "bus", "moving", "wall50", "wall80", "headon", "parked", "wedge"]
	for s: String in all:
		if only != "" and not (s in only.split(",")):
			continue
		await call("_s_" + s)
		_clear()
	print("PROBE done impacts=%s shoves=%d glances=%d nudges=%d" % [DriveImpacts.enabled, DriveImpacts.shoves, DriveImpacts.glances, DriveImpacts.nudges])
	get_tree().quit()


func _static_box(size: Vector3, at: Vector3, yaw: float = 0.0) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	b.add_child(cs)
	add_child(b)
	b.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	return b


func _car(type: int, at: Vector3, yaw: float) -> Vehicle:
	var car: Vehicle
	if BigVehicles.is_big(type):
		car = BigVehicles.make(type, 7)
	else:
		car = Vehicle.new()
		car.setup(type, Color(0.6, 0.1, 0.1), Vehicle.Addon.NONE)
	car.transform = Transform3D(Basis(Vector3.UP, yaw), at)
	add_child(car)
	_items.append(car)
	return car


func _traffic(type: int, at: Vector3, yaw: float, speed: float = 0.0) -> Vehicle:
	var car: Vehicle
	if BigVehicles.is_big(type):
		car = BigVehicles.make(type, 9)
	else:
		car = Vehicle.new()
		car.setup(type, Color(0.1, 0.3, 0.6), Vehicle.Addon.NONE)
	car.traffic = {"axis": 0, "index": 0, "dir": 1, "lane": 0.0, "speed": speed, "v": speed, "half": 2.2, "rear": 2.2, "placed": true}
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.freeze = true
	car.transform = Transform3D(Basis(Vector3.UP, yaw), at)
	car.traffic_speed = speed
	add_child(car)
	_items.append(car)
	return car


func _clear() -> void:
	Input.action_release("move_forward")
	for n in _items:
		if is_instance_valid(n):
			n.queue_free()
	_items.clear()
	await get_tree().physics_frame
	await get_tree().physics_frame


## The player's car, driven, rolling at `speed` m/s along its nose with the throttle held.
func _driven(at: Vector3, yaw: float, speed: float) -> Vehicle:
	var car := _car(Vehicle.BodyType.SEDAN, at, yaw)
	var drv := Node3D.new()
	add_child(drv)
	_items.append(drv)
	await _ticks(20) # settle on its wheels
	car.driver = drv
	car.linear_velocity = -car.global_basis.z * speed
	car.hold_crash_watch(3)
	DriveImpacts.reset(car)
	Input.action_press("move_forward")
	return car


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _fwd_speed(c: Vehicle) -> float:
	return c.linear_velocity.dot(-c.global_basis.z)


## Runs `car` until something stops it or `seconds`, returns [min speed seen after the first big
## drop, speed after `seconds`].
func _run(car: Vehicle, seconds: float) -> Dictionary:
	var t := 0.0
	var minv := INF
	var peak_dv := 0.0
	var prev := car.linear_velocity
	while t < seconds:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		var v := car.linear_velocity
		peak_dv = maxf(peak_dv, (v - prev).length())
		prev = v
		minv = minf(minv, Vector3(v.x, 0, v.z).length())
		if OS.get_environment("TRACE") == "1":
			print("  t %.2f v %.1f (%.1f,%.1f) yaw %.0f w %.2f contact %d" % [t, v.length(), v.x, v.z, rad_to_deg(car.global_rotation.y), car.angular_velocity.y, car.wheels.filter(func(w): return w.is_in_contact()).size()])
	return {"min": minv, "end": Vector3(car.linear_velocity.x, 0, car.linear_velocity.z).length(), "peak_dv": peak_dv}


func _s_traffic(offset: float = 0.0, type: int = Vehicle.BodyType.SEDAN, label: String = "traffic") -> void:
	var other := _traffic(type, Vector3(offset, 0.6, -25.0), 0.0)
	var car := await _driven(Vector3(0, 0.6, 0), 0.0, 13.9)
	var yaw0 := car.global_rotation.y
	var r := await _run(car, 2.5)
	var ov := other.linear_velocity.length() if is_instance_valid(other) else -1.0
	print("PROBE %s: 50 km/h -> player min %.1f end %.1f m/s, peak dv %.1f; other traffic=%s speed %.1f m/s moved %.1f m spin %.2f rad/s; heading %.0f deg" % [label,
		r.min, r.end, r.peak_dv, other.is_traffic(), ov, other.global_position.distance_to(Vector3(offset, 0.6, -25.0)), other.angular_velocity.length(), rad_to_deg(car.global_rotation.y - yaw0)])


func _s_offset() -> void:
	await _s_traffic(1.2, Vehicle.BodyType.SEDAN, "offset")


func _s_bus() -> void:
	await _s_traffic(0.0, BigVehicles.BUS, "bus")


## A traffic car driving away at 8 m/s, rear-ended at 50 km/h (it moves by its traffic speed: a
## stand-in for TrafficManager placing it).
func _s_moving() -> void:
	var other := _traffic(Vehicle.BodyType.SEDAN, Vector3(0, 0.6, -25.0), 0.0, 8.0)
	var car := await _driven(Vector3(0, 0.6, 0), 0.0, 13.9)
	var t := 0.0
	while t < 2.5:
		await get_tree().physics_frame
		var dt := 1.0 / Engine.physics_ticks_per_second
		t += dt
		if other.is_traffic():
			other.global_position += -other.global_basis.z * other.traffic_speed * dt
	print("PROBE moving: rear-end at 50 km/h into 8 m/s -> player %.1f m/s, other traffic=%s %.1f m/s" % [car.linear_velocity.length(), other.is_traffic(), other.linear_velocity.length()])


func _wall(speed: float, angle_deg: float, label: String) -> void:
	# A wall along z at x = -4; the car heads -z turned `angle` toward it.
	_items.append(_static_box(Vector3(1.0, 4.0, 300.0), Vector3(-6.0, 2.0, -100.0)))
	var car := await _driven(Vector3(0, 0.6, 0), deg_to_rad(angle_deg), speed)
	var r := await _run(car, 2.0)
	print("PROBE %s: %.0f km/h at %.0f deg -> min %.1f end %.1f m/s (kept %.0f%%), heading now %.0f deg, x %.1f" % [label, speed * 3.6, angle_deg,
		r.min, r.end, 100.0 * r.end / speed, rad_to_deg(car.global_rotation.y), car.global_position.x])


func _s_wall50() -> void:
	await _wall(13.9, 30.0, "wall50")


func _s_wall80() -> void:
	await _wall(22.2, 30.0, "wall80")


func _s_headon() -> void:
	_items.append(_static_box(Vector3(20.0, 4.0, 1.0), Vector3(0.0, 2.0, -20.0)))
	var car := await _driven(Vector3(0, 0.6, 0), 0.0, 13.9)
	var r := await _run(car, 1.5)
	print("PROBE headon: 50 km/h square into a wall -> min %.1f end %.1f m/s, peak dv %.1f" % [r.min, r.end, r.peak_dv])


func _s_parked() -> void:
	var other := _car(Vehicle.BodyType.SEDAN, Vector3(0.0, 0.6, -25.0), 0.0)
	await _ticks(20)
	var car := await _driven(Vector3(0, 0.6, 0), 0.0, 13.9)
	var r := await _run(car, 2.5)
	print("PROBE parked: 50 km/h into a parked car -> player min %.1f end %.1f, other %.1f m/s moved %.1f m" % [r.min, r.end,
		other.linear_velocity.length(), other.global_position.distance_to(Vector3(0.0, 0.6, -25.0))])


func _s_wedge() -> void:
	# A post 0.4 m wide right at the nose, a little off centre: the car leans on it.
	_items.append(_static_box(Vector3(0.4, 2.0, 0.4), Vector3(0.5, 1.0, -3.2)))
	var car := await _driven(Vector3(0, 0.6, 0), 0.0, 0.0)
	var t := 0.0
	var start := car.global_position
	var freed := -1.0
	while t < 6.0:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		if OS.get_environment("TRACE") == "1" and Engine.get_physics_frames() % 10 == 0:
			print("  t %.2f pos %s v %s yaw %.0f nudges %d" % [t, car.global_position, car.linear_velocity, rad_to_deg(car.global_rotation.y), DriveImpacts.nudges])
		if freed < 0.0 and car.global_position.z < start.z - 4.0:
			freed = t
	print("PROBE wedge: throttle against a post -> free after %s s, moved %.1f m" % ["%.1f" % freed if freed >= 0.0 else "never", car.global_position.distance_to(start)])
