extends RefCounted
## The player's drive train (DriveTrain, scripts/vehicles/drive_train.gd) for tests/smoke_test.gd.
## Loaded at run time, so it compiles after the autoloads. Pure: every class has a spec and a
## gearbox, the classes rank (hyper < super < muscle < sedan < van < heavy trucks to 100 km/h),
## each tops out at its own speed (the solved drag), nitro is quicker and faster, the torque curve
## and the gearbox are EngineAudio's. Live, on its own deck 300 m over the street: a sedan driven
## by a stand-in driver reaches 100 km/h in a sane time and shifts up, coasts down without stopping
## dead, reverses at its class speed, and gives its engine power back when the driver gets out.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _deck: StaticBody3D
var _top: Vector3


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_pure()
	if not DriveTrain.enabled:
		_check(true, "DriveTrain is off (DRIVETRAIN=0): only the pure checks")
		return
	await _live()


func _pure() -> void:
	var probe := Vehicle.new()
	var missing := []
	for ty in Vehicle.BodyType.values():
		probe.body_type = ty
		if not DriveTrain.SPECS.has(DriveTrain.class_of(probe)):
			missing.append(ty)
	probe.free()
	_check(missing.is_empty(), "every body type has a drive-train class (%s missing)" % str(missing))
	var bad := []
	for cls: String in DriveTrain.SPECS:
		var spec: Dictionary = DriveTrain.SPECS[cls]
		if not EngineAudio.PROFILES.has(spec.prof):
			bad.append(cls)
	_check(bad.is_empty(), "every class's gearbox is an EngineAudio profile (%s)" % str(bad))
	var r := {}
	for cls: String in DriveTrain.SPECS:
		r[cls] = DriveTrain.simulate(cls, 40.0)
	var t100 := func(c: String) -> float: return float(r[c].t100) if float(r[c].t100) > 0.0 else 99.0
	_check(t100.call("hyper") < t100.call("super") and t100.call("super") < t100.call("muscle")
		and t100.call("muscle") < t100.call("sedan") and t100.call("sedan") < t100.call("van")
		and t100.call("van") < t100.call("heavy"),
		"the classes rank to 100 km/h: hyper %.2f, super %.2f, muscle %.2f, sedan %.2f, van %.2f, heavy %.2f s" % [
			t100.call("hyper"), t100.call("super"), t100.call("muscle"), t100.call("sedan"), t100.call("van"), t100.call("heavy")])
	_check(t100.call("sedan") > 3.5 and t100.call("sedan") < 6.0, "a sedan does 0-100 in 3.5-6 s (%.2f)" % t100.call("sedan"))
	_check(t100.call("hyper") > 1.8 and t100.call("hyper") < 3.0, "a hypercar in 1.8-3 s (%.2f)" % t100.call("hyper"))
	_check(t100.call("heavy") > 9.0 and t100.call("heavy") < 22.0, "a truck in 9-22 s (%.2f)" % t100.call("heavy"))
	var tops := []
	for cls: String in DriveTrain.SPECS:
		var want: float = DriveTrain.SPECS[cls].top
		if absf(float(r[cls].top) - want) > want * 0.04:
			tops.append("%s %.1f/%.1f" % [cls, float(r[cls].top), want])
	_check(tops.is_empty(), "each class tops out at its own speed within 4 %% (%s)" % str(tops))
	_check(float(r.sedan.shifts) >= 3, "a sedan's run to the top goes up through the gears (%d shifts)" % int(r.sedan.shifts))
	var b := DriveTrain.simulate("sedan", 40.0, true)
	_check(float(b.t100) < float(r.sedan.t100) * 0.75 and float(b.top) > float(r.sedan.top) * 1.2,
		"nitro is quicker and faster (0-100 %.2f s, top %.0f km/h)" % [float(b.t100), float(b.top) * 3.6])
	var x_peak: float = DriveTrain.SPECS.sedan.xp
	_check(is_equal_approx(DriveTrain.torque(x_peak, x_peak), 1.0) and DriveTrain.torque(0.1, x_peak) < 0.7
		and DriveTrain.torque(1.0, x_peak) < 0.85, "the torque curve rises to its peak and falls toward the redline")
	var spec: Dictionary = DriveTrain.SPECS.sedan
	var prof := DriveTrain.profile(spec)
	var n := int(prof.gears)
	_check(DriveTrain.pull(spec, prof, n - 1, float(spec.top) * 1.3) == 0.0
		and DriveTrain.pull(spec, prof, n - 1, float(spec.top) * 1.2, true) > 0.0,
		"the limiter cuts top gear past the redline, nitro runs on past it")
	_check(is_equal_approx(EngineAudio.gear_k(prof, 0), EngineAudio.PROFILES.four.redline * 0.9 / float(spec.first)),
		"the gear ratios are EngineAudio's gear_k on the class's first / top gear speeds")


func _live() -> void:
	var player := _tree.get_first_node_in_group("player") as Node3D
	_top = player.global_position + Vector3(0.0, 300.0, 0.0)
	_deck = StaticBody3D.new()
	_deck.collision_layer = 1
	_deck.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 900.0)
	shape.shape = box
	_deck.add_child(shape)
	_city.add_child(_deck)
	_deck.global_position = _top + Vector3(200.0, -0.5, -400.0)
	var car := Vehicle.new()
	car.setup(Vehicle.BodyType.SEDAN, Color(0.2, 0.3, 0.6), Vehicle.Addon.NONE)
	_city.add_child(car)
	car.global_position = _top + Vector3(200.0, 1.2, 0.0)
	var power_was := car.engine_power
	await _ticks(40)
	var stand_in := Node3D.new()
	_city.add_child(stand_in)
	car.set_meta("drive_train_test", true)
	car.driver = stand_in
	Input.action_press("move_forward")
	var t := 0.0
	var t100 := -1.0
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	while t < 9.0:
		await _tree.physics_frame
		t += dt
		if t100 < 0.0 and car.linear_velocity.dot(-car.global_basis.z) * 3.6 >= 100.0:
			t100 = t
	var st: Variant = DriveTrain.state_of(car)
	var v_lift := car.linear_velocity.length()
	_check(t100 > 0.0 and t100 < 6.5, "a sedan on the deck reaches 100 km/h in %.2f s (under 6.5)" % t100)
	_check(st != null and int(st.gear) >= 2 and int(st.shifts) >= 2,
		"and it has shifted up (gear %s, %s shifts)" % [str(int(st.gear) + 1) if st else "-", str(st.shifts) if st else "-"])
	_check(st != null and DriveTrain.feeds(car), "the engine voice reads the drive train's gear and revs")
	Input.action_release("move_forward")
	await _ticks(Engine.physics_ticks_per_second * 2)
	var v_coast := car.linear_velocity.length()
	var decel := (v_lift - v_coast) / 2.0
	_check(decel > 0.8 and decel < 5.0, "lifting off it slows on engine braking and drag, not like a brake (%.2f m/s2)" % decel)
	Input.action_press("move_back")
	await _ticks(Engine.physics_ticks_per_second * 9)
	var rev := car.linear_velocity.dot(-car.global_basis.z)
	Input.action_release("move_back")
	var rev_top: float = DriveTrain.SPECS.sedan.rev_top
	_check(rev < -rev_top * 0.6 and rev > -rev_top * 1.15,
		"it brakes, then reverses at its class speed (%.1f m/s, %.0f wanted)" % [-rev, rev_top])
	car.driver = null
	_check(not car.has_meta("drive_train") and is_equal_approx(car.engine_power, power_was),
		"out of the car, its engine power is its own again (%.0f)" % car.engine_power)
	car.queue_free()
	stand_in.queue_free()
	_deck.queue_free()
	await _ticks(2)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)
