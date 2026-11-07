extends RefCounted
## Handbrake and drift (DriveDrift, scripts/vehicles/drive_drift.gd) for tests/smoke_test.gd.
## Loaded at run time, so it compiles after the autoloads. Staged on its own deck 300 m over the
## street, the player at the wheel, the controls fed as Input actions.
## Pure: the target angle follows the stick (into the slide more, counter-steer back to none), the
## yaw controller pushes the slip toward its target, the A/B switch, the smoke share.
## Live (sedan and the RWD sports car): a handbrake flick at 80 km/h swings the tail out to a real
## slip angle and stops short of a spin, the same left and right; released with the throttle in
## the drift holds; counter-steer grips it back up and the tyres' grip comes back; a handbrake 180
## turns the car round and stops there, a J-turn swings it round and drives off; full throttle
## and lock steps the RWD car's rear out and the AWD sedan's not; out of the car every tyre has
## its own grip again.

const ACTIONS := ["move_left", "move_right", "move_forward", "move_back", "alt_fire", "boost"]

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _deck: StaticBody3D
var _top: Vector3
var _ws: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_ws = _tree.root.get_node("/root/WorldState")
	_pure()
	if not DriveDrift.enabled:
		_check(true, "DriveDrift is off (DRIVE_DRIFT=0): only the pure checks")
		return
	var player := _tree.get_first_node_in_group("player") as Player
	if player == null:
		_check(false, "drive drift: no player")
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
	player.global_position = _top + Vector3(30.0, 1.2, 60.0)
	player.velocity = Vector3.ZERO
	await _ticks(3)

	await _live(player)

	_release()
	if player.is_driving():
		player.exit_vehicle()
	_deck.queue_free()
	player.global_position = _ws.to_local(home)
	player.velocity = Vector3.ZERO
	if police:
		police.set("enabled", police_was)
	await _ticks(2)


func _pure() -> void:
	var M := DriveDrift.Mode
	var base := DriveDrift.target_angle(M.HOLD, 1.0, 0.0)
	var into := DriveDrift.target_angle(M.HOLD, 1.0, 1.0)
	var counter := DriveDrift.target_angle(M.HOLD, 1.0, -1.0)
	_check(base > deg_to_rad(15.0) and into > base and counter < deg_to_rad(2.0),
		"a held drift's angle follows the stick (%.0f / %.0f / %.0f deg: centred, into, counter)"
			% [rad_to_deg(base), rad_to_deg(into), rad_to_deg(counter)])
	_check(is_equal_approx(DriveDrift.target_angle(M.HOLD, -1.0, -1.0), -into),
		"and a left drift is the mirror of a right one")
	_check(DriveDrift.target_angle(M.GRIP, 1.0, 1.0) == 0.0, "gripping, there is no target slip")
	# The controller: under its target the nose is turned clockwise (yaw -), over it back.
	var under := DriveDrift.angle_acc(0.1, 0.6, 0.0, 0.0)
	var over := DriveDrift.angle_acc(0.9, 0.6, 0.0, 0.0)
	_check(under < 0.0 and over > 0.0, "the slip controller turns the nose toward its target (%.1f, %.1f)" % [under, over])
	_check(absf(DriveDrift.angle_acc(5.0, -5.0, 0.0, 0.0)) <= DriveDrift.YAW_MAX_ACC,
		"and never harder than YAW_MAX_ACC")
	_check(DriveDrift.HB_GRIP < DriveDrift.FRONT_GRIP and DriveDrift.FRONT_GRIP < 1.0,
		"the handbrake takes more grip off the trailing axle than the leading one")
	_check(DriveDrift.RWD.has(Vehicle.BodyType.SPORTS) and not DriveDrift.RWD.has(Vehicle.BodyType.SEDAN),
		"the sports car is rear-driven, the sedan is not")
	_check(OS.get_environment("DRIVE_DRIFT") != "0" or not DriveDrift.enabled, "DRIVE_DRIFT=0 turns it off")


func _live(player: Player) -> void:
	# Handbrake flicks, both ways, on both bodies.
	var slips := {}
	for t: int in [Vehicle.BodyType.SEDAN, Vehicle.BodyType.SPORTS]:
		for side: float in [1.0, -1.0]:
			var car := await _car(t)
			player.enter_vehicle(car)
			await _ticks(3)
			var r: Dictionary = await _flick(car, side)
			var name: String = Vehicle.BODY_NAMES[t]
			slips[[t, side]] = r
			_check(r.max_slip > 20.0 and r.max_slip < 75.0,
				"%s: a handbrake flick at 80 km/h swings the tail out (%.0f deg of slip, %s)" % [name, r.max_slip, "right" if side > 0 else "left"])
			_check(not r.spun, "%s: and it does not spin out" % name)
			_check(r.held > 0.8, "%s: the drift holds on the throttle (%.1f s over 15 deg)" % [name, r.held])
			_check(r.kept > 0.45, "%s: and keeps its speed (%.0f %% of it)" % [name, r.kept * 100.0])
			_check(r.end_slip < 10.0, "%s: counter-steer grips it back up (%.1f deg)" % [name, r.end_slip])
			var st := DriveDrift.state_of(car)
			await _ticks(40)
			var back := st != null and st.grip[2] > 0.95 and st.grip[3] > 0.95
			_check(back, "%s: and the rear tyres' grip comes back" % name)
			player.exit_vehicle()
			await _ticks(2)
			var own := true
			for w in car.wheels:
				own = own and is_equal_approx(w.wheel_friction_slip, car.wheel_grip)
			_check(own, "%s: out of the car every tyre has its own grip again" % name)
			car.queue_free()
			await _ticks(2)
		var a: Dictionary = slips[[t, 1.0]]
		var b: Dictionary = slips[[t, -1.0]]
		_check(absf(a.max_slip - b.max_slip) < maxf(a.max_slip, b.max_slip) * 0.15,
			"%s: a left drift is as big as a right one (%.0f vs %.0f deg)" % [Vehicle.BODY_NAMES[t], b.max_slip, a.max_slip])
	# The handbrake 180.
	var car2 := await _car(Vehicle.BodyType.SEDAN)
	player.enter_vehicle(car2)
	await _ticks(3)
	_set_speed(car2, 15.0)
	var h0 := car2.global_rotation.y
	var turned := 0.0
	var last := h0
	_steer(1.0)
	Input.action_press("alt_fire")
	for i in 120:
		await _tree.physics_frame
		turned += wrapf(car2.global_rotation.y - last, -PI, PI)
		last = car2.global_rotation.y
	_release()
	_check(absf(rad_to_deg(turned)) > 150.0 and absf(rad_to_deg(turned)) < 215.0,
		"a handbrake turn at full lock from 54 km/h turns the car round (%.0f deg)" % rad_to_deg(turned))
	# The J-turn: reversing at 40 km/h, a flick of lock and the handbrake, then drive.
	await _ticks(20) # let go of everything between the two moves
	_set_speed(car2, -11.0)
	turned = 0.0
	last = car2.global_rotation.y
	_steer(1.0)
	Input.action_press("alt_fire")
	for i in 30:
		await _tree.physics_frame
		turned += wrapf(car2.global_rotation.y - last, -PI, PI)
		last = car2.global_rotation.y
	_release()
	Input.action_press("move_forward")
	for i in 90:
		await _tree.physics_frame
		turned += wrapf(car2.global_rotation.y - last, -PI, PI)
		last = car2.global_rotation.y
	_release()
	var fwd := car2.linear_velocity.dot(-car2.global_basis.z)
	_check(absf(rad_to_deg(turned)) > 160.0 and absf(rad_to_deg(turned)) < 220.0 and fwd > 5.0,
		"a J-turn swings the car round (%.0f deg) and drives off forward (%.0f m/s)" % [rad_to_deg(turned), fwd])
	player.exit_vehicle()
	car2.queue_free()
	await _ticks(2)
	# Power oversteer: the RWD car steps out on full throttle and lock, the AWD sedan does not.
	var power := {}
	for t: int in [Vehicle.BodyType.SPORTS, Vehicle.BodyType.SEDAN]:
		var car3 := await _car(t)
		player.enter_vehicle(car3)
		await _ticks(3)
		_set_speed(car3, 9.0)
		Input.action_press("move_forward")
		_steer(1.0)
		var mx := 0.0
		for i in 100:
			await _tree.physics_frame
			mx = maxf(mx, absf(rad_to_deg(DriveDrift.slip_angle(car3))))
		_release()
		power[t] = mx
		player.exit_vehicle()
		car3.queue_free()
		await _ticks(2)
	_check(power[Vehicle.BodyType.SPORTS] > 15.0 and power[Vehicle.BodyType.SEDAN] < 12.0,
		"full throttle and lock steps an RWD car's rear out (%.0f deg; the AWD sedan %.0f)"
			% [power[Vehicle.BodyType.SPORTS], power[Vehicle.BodyType.SEDAN]])


## 22 m/s straight, handbrake + lock for half a second, then throttle with the stick centred for
## 1.5 s, then counter-steer for 1 s.
func _flick(car: Vehicle, side: float) -> Dictionary:
	_set_speed(car, 22.0)
	Input.action_press("move_forward")
	var v0 := 22.0
	var r := {"max_slip": 0.0, "spun": false, "held": 0.0, "kept": 0.0, "end_slip": 0.0}
	_steer(side)
	Input.action_press("alt_fire")
	for i in 30:
		await _tree.physics_frame
		_note(car, r)
	Input.action_release("alt_fire")
	for i in 90:
		_steer(0.0)
		await _tree.physics_frame
		_note(car, r)
		if absf(rad_to_deg(DriveDrift.slip_angle(car))) > 15.0:
			r.held += 1.0 / Engine.physics_ticks_per_second
	r.kept = _hspeed(car) / v0
	for i in 60:
		_steer(clampf(-rad_to_deg(DriveDrift.slip_angle(car)) / 25.0, -1.0, 1.0))
		await _tree.physics_frame
	r.end_slip = absf(rad_to_deg(DriveDrift.slip_angle(car)))
	_release()
	return r


func _note(car: Vehicle, r: Dictionary) -> void:
	var s := absf(rad_to_deg(DriveDrift.slip_angle(car)))
	r.max_slip = maxf(r.max_slip, s)
	if s > 120.0 and _hspeed(car) > 4.0:
		r.spun = true


func _hspeed(car: Vehicle) -> float:
	var v := car.linear_velocity
	v.y = 0.0
	return v.length()


func _set_speed(car: Vehicle, mps: float) -> void:
	car.hold_crash_watch(3)
	car.linear_velocity = -car.global_basis.z * mps
	car.angular_velocity = Vector3.ZERO


func _car(t: int) -> Vehicle:
	var car := Vehicle.new()
	car.setup(t as Vehicle.BodyType, Color(0.55, 0.1, 0.1), Vehicle.Addon.NONE)
	_city.add_child(car)
	car.global_position = _top + Vector3(0.0, 0.9, 120.0)
	car.global_rotation = Vector3.ZERO
	await _ticks(30)
	return car


func _steer(x: float) -> void:
	if x > 0.0:
		Input.action_press("move_right", x)
		Input.action_release("move_left")
	elif x < 0.0:
		Input.action_press("move_left", -x)
		Input.action_release("move_right")
	else:
		Input.action_release("move_left")
		Input.action_release("move_right")


func _release() -> void:
	for a in ACTIONS:
		Input.action_release(a)


func _build_deck() -> void:
	_deck = StaticBody3D.new()
	_deck.collision_layer = 1
	_deck.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 700.0)
	shape.shape = box
	_deck.add_child(shape)
	_city.add_child(_deck)
	_deck.global_position = _top - Vector3(0.0, 0.5, 0.0) + Vector3(0.0, 0.0, -150.0)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)
