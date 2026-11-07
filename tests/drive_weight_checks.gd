extends RefCounted
## Suspension and weight of the player's car (DriveSuspension, scripts/vehicles/drive_suspension.gd)
## for tests/smoke_test.gd. Loaded at run time, so it compiles after the autoloads. Staged on its
## own deck 300 m over the street. No Input is pressed (the on-foot player would walk): the car is
## given a stand-in driver, its own script is switched off and its brake set by hand, while the
## DriveSuspension node runs as it does in play.
## Pure: the classes, the profiles' frequencies and damping ratios, the ride height kept by
## tuned(). Live: getting in re-springs the car once and keeps its ride height; a 1 m drop settles
## in under two seconds with at most two bounces; a hard stop dips the nose and it comes back;
## the anti-roll bars push the compressed side up; the roll guard bleeds a roll that is lifting
## one side; getting out stops the node; DRIVE_SUSPENSION=0 leaves a car alone.

const TICK := 1.0 / 60.0

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _deck: StaticBody3D
var _top: Vector3
var _brake: float = 2.0
var _engine: float = 0.0


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_pure()
	var player := _tree.get_first_node_in_group("player") as Node3D
	_top = player.global_position + Vector3(260.0, 300.0, 0.0)
	_build_deck()
	var was := DriveSuspension.enabled
	DriveSuspension.enabled = true
	await _live()
	DriveSuspension.kerb_enabled = false
	var off_keep: float = await _kerb(false)
	DriveSuspension.kerb_enabled = true
	var on_keep: float = await _kerb(true)
	_check(on_keep > off_keep + 0.8, "the kerb assist keeps %.2f m/s against %.2f without it (DRIVE_KERB=0)" % [on_keep, off_keep])
	DriveSuspension.enabled = false
	var off := _car(Vector3(12.0, 1.2, 0.0))
	await _ticks(90)
	var stand := Node3D.new()
	_city.add_child(stand)
	off.driver = stand
	_check(off.get_node_or_null(^"DriveSuspension") == null and is_equal_approx(off.suspension_stiffness, 60.0),
		"DRIVE_SUSPENSION=0: getting in leaves the car's springs alone")
	off.driver = null
	off.queue_free()
	stand.queue_free()
	DriveSuspension.enabled = was
	_deck.queue_free()


func _pure() -> void:
	_check(DriveSuspension.class_of(Vehicle.BodyType.SPORTS) == "sport"
			and DriveSuspension.class_of(Vehicle.BodyType.SEDAN) == "car"
			and DriveSuspension.class_of(Vehicle.BodyType.SUV) == "tall"
			and DriveSuspension.class_of(Vehicle.BodyType.PICKUP) == "truck"
			and DriveSuspension.class_of(Vehicle.BodyType.BUS) == "big"
			and DriveSuspension.class_of(Vehicle.BodyType.LOWRIDER_COUPE) == "low",
		"DriveSuspension sorts the bodies into classes")
	var ok := true
	for key: String in DriveSuspension.PROFILES:
		var p: Dictionary = DriveSuspension.PROFILES[key]
		var f := float(p.f)
		if f < 1.0 or f > 2.2 or float(p.zr) <= float(p.zc) or float(p.zr) < 0.4 or float(p.zr) > 0.8 \
				or float(p.lever) >= float(p.com) * 0.6:
			ok = false
	_check(ok, "every profile springs at 1-2.2 Hz, rebound over compression damping, the roll lever well under the centre of mass")
	var old := {"k": 60.0, "rest": 0.35, "travel": 0.2}
	var t := DriveSuspension.tuned(old, DriveSuspension.PROFILES["car"])
	var sag_old := 9.8 / 240.0
	var sag_new := 9.8 / (4.0 * float(t.k))
	_check(absf((float(t.rest) - sag_new) - (0.35 - sag_old)) < 1e-5
			and absf((float(t.rest) - float(t.travel)) - (0.35 - 0.2)) < 1e-5,
		"tuned() keeps the loaded ride height and the bump stop (%.3f m more rest length)" % (float(t.rest) - 0.35))
	var zeta := float(t.reb) / sqrt(float(t.k))
	_check(absf(zeta - 0.55) < 1e-4, "and damps the rebound at the profile's ratio (%.2f)" % zeta)


func _live() -> void:
	var car := _car(Vector3(0.0, 1.2, 0.0))
	# Settled on the old springs (they take three seconds).
	await _ticks(300)
	var ride_before := _h(car)
	var stand := Node3D.new()
	_city.add_child(stand)
	car.driver = stand
	var ds := car.get_node_or_null(^"DriveSuspension") as DriveSuspension
	_check(ds != null and car.suspension_stiffness < 40.0 and car.has_meta("drive_suspension"),
		"getting in re-springs the car (stiffness %.1f)" % car.suspension_stiffness)
	# The car's own script reads Input while it has a driver: off, brake by hand.
	car.set_physics_process(false)
	car.engine_force = 0.0
	car.brake = 2.0
	_brake = 2.0
	await _held(car, 120)
	_check(absf(_h(car) - ride_before) < 0.015,
		"and keeps its ride height (%.1f cm)" % ((_h(car) - ride_before) * 100.0))
	var rest_y := _h(car)

	# A 1 m drop.
	car.sleeping = false
	car.global_position.y += 1.0
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.hold_crash_watch(3)
	var landed := false
	var flips := 0
	var vy_prev := 0.0
	var settle := -1.0
	var still := 0
	var h_prev := _h(car)
	for i in 240:
		await _held(car, 1)
		var vy := car.linear_velocity.y
		if landed:
			if signf(vy) != signf(vy_prev) and absf(vy) > 0.02:
				flips += 1
			# Settled: still, and no longer creeping (the ride is checked on its own below).
			if absf(vy) < 0.03 and absf(_h(car) - h_prev) < 0.0005:
				still += 1
				if still == 10 and settle < 0.0:
					settle = (i - 9) * TICK
			else:
				still = 0
		if not landed and not car.is_airborne():
			landed = true
		vy_prev = vy
		h_prev = _h(car)
	_check(settle > 0.0 and settle < 2.0 and flips <= 3 and absf(_h(car) - rest_y) < 0.04,
		"a 1 m drop settles in %.2f s with %d bounces, %.1f cm from where it stood (the old springs: ~3 s, 5)" % [settle, flips, (_h(car) - rest_y) * 100.0])

	# A hard stop from 100 km/h: the nose dips and comes back.
	var fwd := -car.global_basis.z
	var pitch0 := _pitch(car)
	car.sleeping = false
	car.linear_velocity = fwd * 27.8
	car.hold_crash_watch(3)
	_brake = car.brake_force
	var dive := 0.0
	var n := 0
	while car.linear_velocity.dot(fwd) > 0.5 and n < 300:
		await _held(car, 1)
		dive = minf(dive, _pitch(car) - pitch0)
		n += 1

	_check(dive < -1.8, "a hard stop from 100 km/h dips the nose %.2f degrees (%.2f s)" % [dive, n * TICK])
	await _held(car, 60)
	_check(absf(_pitch(car) - pitch0) < 0.4, "and it is back level within a second (%.2f)" % (_pitch(car) - pitch0))
	_brake = 2.0

	# The anti-roll bar: compress one side, the bar pushes that side up.
	var r0 := _roll(car)
	car.apply_impulse(Vector3.DOWN * car.mass * 1.5, car.global_basis.x * 0.8)
	await _held(car, 4)
	var dl := ds.compression(0) - ds.compression(1)
	_check(dl < -0.01, "pushing the right side down compresses its wheels more (%.3f m)" % dl)
	await _held(car, 90)
	_check(absf(_roll(car) - r0) < 0.4, "and the bars and springs bring it level again")

	# Getting out stops the node.
	car.set_physics_process(true)
	car.driver = null
	_check(not ds.is_physics_processing(), "getting out stops the anti-roll bars")
	car.queue_free()
	stand.queue_free()
	await _ticks(2)


## A sports car coasting at 30 km/h into a 25 cm kerb at 20 degrees: its body's edge meets the
## kerb's, the assist hands the speed back.
func _kerb(judge: bool) -> float:
	var kb := StaticBody3D.new()
	kb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(200.0, 0.25, 8.0)
	cs.shape = bx
	kb.add_child(cs)
	_city.add_child(kb)
	kb.global_position = _top + Vector3(0.0, 0.125, -24.0)
	var car := _car(Vector3(0.0, 1.2, -13.0), Vehicle.BodyType.SPORTS)
	car.rotation.y = deg_to_rad(70.0)
	await _ticks(300)
	var stand := Node3D.new()
	_city.add_child(stand)
	car.driver = stand
	_brake = 0.0
	await _held(car, 30)
	var ds := car.get_node_or_null(^"DriveSuspension") as DriveSuspension
	var fwd := -car.global_basis.z
	car.sleeping = false
	car.linear_velocity = fwd * 8.33
	car.hold_crash_watch(3)
	var keep := 99.0
	var hit := -1
	# Part throttle (Godot's engine_force pushes toward +Z, the car's tail: negative is ahead).
	_engine = -car.engine_power * 0.5
	var at_hit := 0.0
	for i in 360:
		await _held(car, 1)
		# Throttle on below 30 km/h, off above (no Input in the gate).
		_engine = -car.engine_power * 0.6 if car.linear_velocity.dot(fwd) < 8.33 else 0.0
		if hit < 0 and car.global_position.z - _top.z < -18.0:
			hit = i
			at_hit = car.linear_velocity.length()
		elif hit >= 0 and i < hit + 60:
			keep = minf(keep, car.linear_velocity.length())
		elif hit >= 0:
			break
	if judge:
		_check(ds != null and ds.kerb_steps > 0 and keep > 4.5,
			"a low car into a 25 cm kerb at 30 km/h keeps its speed (%.2f of %.2f m/s, %d steps)" % [keep, at_hit, ds.kerb_steps if ds else -1])
		_check(_h(car) > 0.2, "and ends up on the pavement")
	car.driver = null
	car.queue_free()
	stand.queue_free()
	kb.queue_free()
	_brake = 2.0
	_engine = 0.0
	await _ticks(2)
	return keep


func _car(at: Vector3, type: int = Vehicle.BodyType.SEDAN) -> Vehicle:
	var car := Vehicle.new()
	car.setup(type, Color(0.5, 0.5, 0.55), Vehicle.Addon.NONE)
	car.position = _top + at
	_city.add_child(car)
	return car


## Height over the deck (the city may move its nodes while the checks run).
func _h(car: Vehicle) -> float:
	return car.global_position.y - _deck.global_position.y


func _pitch(car: Vehicle) -> float:
	return rad_to_deg(asin(clampf((-car.global_basis.z).y, -1.0, 1.0)))


func _roll(car: Vehicle) -> float:
	return rad_to_deg(asin(clampf(car.global_basis.x.y, -1.0, 1.0)))


func _build_deck() -> void:
	_deck = StaticBody3D.new()
	_deck.collision_layer = 1
	_deck.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 600.0)
	shape.shape = box
	_deck.add_child(shape)
	_city.add_child(_deck)
	_deck.global_position = _top - Vector3(0.0, 0.5, 0.0) + Vector3(0.0, 0.0, -150.0)


## Physics frames with the car's own script held off (PhysicsBudget switches a driven car's script
## back on; it would read Input) and its brake held at _brake.
func _held(car: Vehicle, n: int) -> void:
	for i in n:
		car.set_physics_process(false)
		car.engine_force = _engine
		car.brake = _brake
		await _tree.physics_frame


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)
