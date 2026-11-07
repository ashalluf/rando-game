extends RefCounted
## Driving assists and AI-car parity (DriveAssist, scripts/vehicles/drive_assist.gd), for
## tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## Checks: the pure maths (reference yaw rate signs and its tyre cap, slip angle, when stability
## control steps in, the AI's speed-limited lock); the hook lines in Vehicle and PoliceCar; then a
## sedan on a slab of its own high over the city, driven by Input actions: full lock and throttle
## at 28 m/s both ways (no rollover - which used to hand the car to _fly() and spin it - slip held
## down, the yaw rates matching within 15 %), a nitro corner on weak rear tyres, and a car the AI
## drives on ai_drive making a U-turn without spinning. DRIVE_ASSIST=0 is the A/B.

var _t: Object
var _root: Node3D
var _driver: Node3D


## A car the AI drives, like PoliceCar: its own _physics_process (the driverless Vehicle code zeroes
## the pedals every tick).
class AiCar extends Vehicle:
	var brain: Callable
	func _physics_process(delta: float) -> void:
		_update_wheels(delta)
		if brain.is_valid():
			brain.call(delta)


func run(t: Object, city: Node3D) -> void:
	_t = t
	var was := DriveAssist.enabled
	DriveAssist.enabled = true
	_maths()
	_hooks()
	await _drive(city)
	DriveAssist.enabled = was


func _maths() -> void:
	var r_left := DriveAssist.reference_yaw(10.0, 0.2, 2.7)
	var r_right := DriveAssist.reference_yaw(10.0, -0.2, 2.7)
	_t._check(r_left > 0.0 and is_equal_approx(r_left, -r_right),
		"DriveAssist: the reference yaw rate is +Y for left steering and symmetric (%.3f, %.3f)" % [r_left, r_right])
	_t._check(absf(DriveAssist.reference_yaw(40.0, 0.5, 2.7)) <= DriveAssist.LAT_LIMIT / 40.0 + 1e-4,
		"DriveAssist: the reference yaw rate is capped at the tyres' limit at speed")
	_t._check(DriveAssist.slip_angle(20.0, 0.0) == 0.0 and DriveAssist.slip_angle(20.0, 20.0) > 44.0,
		"DriveAssist: slip angle 0 going straight, 45 degrees sliding sideways as fast as forward")
	_t._check(DriveAssist.intervention(2.0, 0.5, 0.5) == 0.0 and DriveAssist.intervention(30.0, 0.5, 0.5) == 1.0,
		"DriveAssist: no intervention on a gripping car, full intervention in a 30 degree slide")
	_t._check(DriveAssist.intervention(3.0, 1.6, 0.4) > 0.5 and DriveAssist.intervention(3.0, -0.8, 0.4) > 0.3,
		"DriveAssist: yaw rate well over the steering's (or against it) steps in")
	var lo := DriveAssist.ai_steer_limit(5.0, 2.7, 0.5)
	var hi := DriveAssist.ai_steer_limit(30.0, 2.7, 0.5)
	_t._check(is_equal_approx(lo, 0.5) and hi < 0.1 and hi >= 0.08,
		"DriveAssist: the AI gets full lock at 5 m/s and a tyre-limited lock at 30 m/s (%.3f, %.3f)" % [lo, hi])


func _hooks() -> void:
	var v := FileAccess.get_file_as_string("res://scripts/vehicles/vehicle.gd")
	_t._check(v.count("DriveAssist.player_tick(") == 1, "DriveAssist: one hook line in Vehicle._physics_process")
	var p := FileAccess.get_file_as_string("res://scripts/npc/police_car.gd")
	_t._check(p.count("DriveAssist.ai_drive(") == 1 and p.contains("if DriveAssist.enabled:"),
		"DriveAssist: PoliceCar._pursue drives through ai_drive, the old law kept for DRIVE_ASSIST=0")


func _drive(city: Node3D) -> void:
	_root = Node3D.new()
	_root.name = "DriveAssistCheck"
	city.add_child(_root)
	_root.global_position = Vector3(city.global_position.x + 9000.0, 2600.0, city.global_position.z + 9000.0)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	ground.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(900, 1, 900)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	ground.add_child(cs)
	_root.add_child(ground)
	_driver = Node3D.new()
	_root.add_child(_driver)
	var right: Dictionary = await _corner(false, "move_right", false)
	var left: Dictionary = await _corner(false, "move_left", false)
	var ok := right.has("yaw") and left.has("yaw")
	_t._check(ok and right.yaw < -0.2 and left.yaw > 0.2,
		"DriveAssist: full right lock turns right, full left turns left (%.2f, %.2f rad/s)" % [right.get("yaw", 0.0), left.get("yaw", 0.0)])
	_t._check(ok and absf(absf(right.yaw) - absf(left.yaw)) <= 0.15 * maxf(absf(right.yaw), absf(left.yaw)),
		"DriveAssist: left and right yaw rates match within 15 %")
	_t._check(ok and right.beta < 25.0 and left.beta < 25.0,
		"DriveAssist: full lock at 28 m/s stays under 25 degrees of slip (%.1f, %.1f)" % [right.get("beta", 0.0), left.get("beta", 0.0)])
	var weak: Dictionary = await _corner(true, "move_right", true)
	_t._check(weak.has("beta") and weak.beta < 30.0,
		"DriveAssist: a nitro corner on weak rear tyres does not spin (%.1f degrees)" % weak.get("beta", 99.0))
	var ai: Dictionary = await _ai_uturn()
	_t._check(ai.get("beta", 99.0) < 30.0 and ai.get("turned", false),
		"DriveAssist: an AI car on ai_drive turns round without spinning (slip %.1f, under 30)" % ai.get("beta", 99.0))
	for a in ["move_forward", "move_left", "move_right", "boost"]:
		Input.action_release(a)
	_root.queue_free()


func _car(ai: bool = false) -> Vehicle:
	var car: Vehicle = AiCar.new() if ai else Vehicle.new()
	car.setup(Vehicle.BodyType.SEDAN, Color(0.5, 0.1, 0.1), 0)
	car.position = Vector3(0, 0.9, 0)
	_root.add_child(car)
	# Out of PhysicsBudget's hands: it switches a far car's script off and sleeps one at rest.
	car.remove_from_group("physics_prop")
	for i in 60:
		await _t.get_tree().physics_frame
	return car


func _slip(car: Vehicle) -> float:
	var m := DriveAssist.motion(car)
	return absf(DriveAssist.slip_angle(m.x, m.y))


func _corner(weak_rear: bool, action: String, nitro: bool) -> Dictionary:
	var car: Vehicle = await _car()
	if car.wheels.size() < 4:
		car.queue_free()
		return {}
	if weak_rear:
		for w in car.wheels:
			if not w.use_as_steering:
				w.wheel_friction_slip *= 0.3
	car.sleeping = false
	car.linear_velocity = -car.global_basis.z * (24.0 if nitro else 28.0)
	car.driver = _driver
	Input.action_press("move_forward")
	Input.action_press(action)
	if nitro:
		Input.action_press("boost")
	var beta := 0.0
	var yaw := 0.0
	var n := 0
	for i in 150:
		await _t.get_tree().physics_frame
		beta = maxf(beta, _slip(car))
		if i >= 60:
			yaw += car.angular_velocity.y
			n += 1
	for a in ["move_forward", action, "boost"]:
		Input.action_release(a)
	car.driver = null
	car.queue_free()
	return {"beta": beta, "yaw": yaw / maxf(n, 1)}


func _ai_uturn() -> Dictionary:
	var car: AiCar = await _car(true)
	car.engine_power = 8200.0
	car.mass = 1500.0
	car.sleeping = false
	car.linear_velocity = -car.global_basis.z * 18.0
	var aim := car.global_position + car.global_basis.z * 40.0
	var st := {"ang": PI}
	car.brain = func(d: float) -> void:
		var fwd := -car.global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var to := aim - car.global_position
		to.y = 0.0
		var dir := to.normalized()
		st.ang = atan2(fwd.cross(dir).y, fwd.dot(dir))
		DriveAssist.ai_drive(car, st.ang, 14.0, d)
	var beta := 0.0
	var turned := false
	for i in 480:
		await _t.get_tree().physics_frame
		var m := DriveAssist.motion(car)
		if absf(m.x) > 3.0:
			beta = maxf(beta, absf(DriveAssist.slip_angle(m.x, m.y)))
		if absf(float(st.ang)) < 0.25:
			turned = true
			break
	car.brain = Callable()
	car.queue_free()
	return {"beta": beta, "turned": turned}
