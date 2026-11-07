extends RefCounted
## The player's car hitting things (DriveImpacts, scripts/vehicles/drive_impacts.gd) for
## tests/smoke_test.gd. Loaded at run time, so it compiles after the autoloads. Staged on its own
## deck 300 m over the street with its own walls, posts and cars: nothing of the city near it.
## Live: 50 km/h into a stationary traffic car drops it out of the traffic and shoves it (it moves
## off, the player keeps moving, a crash for both); a traffic bus barely moves and the player
## bounces; a 30-degree wall hit at 50 km/h keeps most of the speed along the wall and turns the
## nose onto it, a head-on one still stops; throttle against a post gets free; a lamp post at
## 80 km/h falls and the player keeps most of his speed. The switches each turn their part off.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _deck: StaticBody3D
var _top: Vector3
var _items: Array[Node] = []
var _drv: Node3D


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_pure()
	if not DriveImpacts.enabled:
		_check(true, "DriveImpacts is off (DRIVE_IMPACTS=0): only the pure checks")
		return
	var ws: Node = _tree.root.get_node("/root/WorldState")
	var player := _tree.get_first_node_in_group("player") as Player
	if player.is_driving():
		player.exit_vehicle()
	var police: Node = city.get_node_or_null("Police")
	var police_was: Variant = police.get("enabled") if police else null
	if police:
		police.set("enabled", false)
	var home: Vector3 = ws.to_world(player.global_position)
	_top = player.global_position + Vector3(0.0, 300.0, 0.0)
	_deck = _static_box(Vector3(600.0, 1.0, 600.0), _top - Vector3(0.0, 0.5, 0.0))
	# The player waits on the deck, out of the way.
	player.global_position = _top + Vector3(150.0, 1.2, 150.0)
	player.velocity = Vector3.ZERO
	_drv = Node3D.new()
	_city.add_child(_drv)
	await _ticks(3)

	await _traffic_shove()
	await _bus()
	await _walls()
	await _wedge()
	await _lamp()

	Input.action_release("move_forward")
	_clear()
	_drv.queue_free()
	_deck.queue_free()
	player.global_position = ws.to_local(home)
	player.velocity = Vector3.ZERO
	if police:
		police.set("enabled", police_was)
	await _ticks(3)


func _pure() -> void:
	var car := Vehicle.new()
	_check(is_equal_approx(DriveImpacts.prop_slow(car, 0.2), 0.2), "an empty car loses PropBreak's whole share of its speed to a prop")
	car.driver = Node3D.new()
	var kept := DriveImpacts.prop_slow(car, 0.2)
	_check(kept < 0.2 and kept > 0.0, "the player's car loses less (%.3f of 0.2)" % kept)
	DriveImpacts.prop_keep_on = false
	_check(is_equal_approx(DriveImpacts.prop_slow(car, 0.2), 0.2), "DRIVE_PROP_KEEP=0 gives the old share back")
	DriveImpacts.prop_keep_on = true
	car.driver.free()
	car.free()
	_check(DriveImpacts.RESTITUTION > 0.0 and DriveImpacts.RESTITUTION < 1.0, "car-to-car hits bounce a little, never elastic")
	_check(DriveImpacts.GLANCE_MAX < 0.8, "only shallow hits glance (sin %.2f)" % DriveImpacts.GLANCE_MAX)


# --- live --------------------------------------------------------------------------------------

func _traffic_shove() -> void:
	var other := _traffic(Vehicle.BodyType.SEDAN, Vector3(0.0, 0.6, -25.0))
	var car := await _driven(Vector3(0.0, 0.6, 0.0), 0.0, 13.9)
	var n0 := DriveImpacts.shoves
	var r := await _run(car, 2.5)
	_check(DriveImpacts.shoves > n0 and not other.is_traffic(), "50 km/h into a traffic car shoves it out of the traffic")
	var moved := (other.global_position - _at(Vector3(0.0, 0.6, -25.0))).length()
	_check(moved > 3.0, "and it is pushed away (%.1f m)" % moved)
	_check(r.min > 1.0, "the player's car never stops dead on it (slowest %.1f m/s)" % r.min)
	_check(other.damage_state() != null and other.damage_state().health < other.damage_state().max_health,
			"the shoved car takes a crash")
	_clear()
	# The A/B: off, the solver stops the car on the kinematic body and the traffic car stays put.
	DriveImpacts.shove_on = false
	other = _traffic(Vehicle.BodyType.SEDAN, Vector3(0.0, 0.6, -25.0))
	car = await _driven(Vector3(0.0, 0.6, 0.0), 0.0, 13.9)
	await _run(car, 2.0)
	_check(other.is_traffic(), "DRIVE_SHOVE=0: the traffic car stays in the traffic (a wall)")
	DriveImpacts.shove_on = true
	_clear()


func _bus() -> void:
	var other := _traffic(BigVehicles.BUS, Vector3(0.0, 0.6, -28.0))
	var car := await _driven(Vector3(0.0, 0.6, 0.0), 0.0, 13.9)
	await _run(car, 2.0)
	var dv: float = DriveImpacts.last_shove.get("dv_other", 99.0)
	var dvp: float = DriveImpacts.last_shove.get("dv_player", 0.0)
	_check(not other.is_traffic() and dv < dvp, "a bus is shoved less than the car that hits it (%.1f vs %.1f m/s)" % [dv, dvp])
	_clear()


func _walls() -> void:
	_items.append(_static_box(Vector3(1.0, 4.0, 300.0), _at(Vector3(-6.0, 2.0, -100.0))))
	var car := await _driven(Vector3(0.0, 0.6, 0.0), deg_to_rad(30.0), 13.9)
	var n0 := DriveImpacts.glances
	var r := await _run(car, 2.0)
	var yaw := rad_to_deg(wrapf(car.global_rotation.y, -PI, PI))
	_check(DriveImpacts.glances > n0, "a 30-degree wall hit at 50 km/h glances")
	_check(r.end > 13.9 * 0.4, "and keeps going along it (%.1f of 13.9 m/s after 2 s of coasting, which alone leaves ~10)" % r.end)
	_check(absf(yaw) < 22.0, "with the nose turned onto the wall line (%.0f deg off it)" % yaw)
	_clear()
	_items.append(_static_box(Vector3(20.0, 4.0, 1.0), _at(Vector3(0.0, 2.0, -12.0))))
	car = await _driven(Vector3(0.0, 0.6, 0.0), 0.0, 13.9)
	n0 = DriveImpacts.glances
	r = await _run(car, 2.5)
	_check(DriveImpacts.glances == n0 and r.min < 5.0, "a head-on wall hit is no glance and stops the car (%.1f m/s)" % r.min)
	_clear()


func _wedge() -> void:
	_items.append(_static_box(Vector3(0.4, 2.0, 0.4), _at(Vector3(0.5, 1.0, -3.2))))
	var car := await _driven(Vector3(0.0, 0.6, 0.0), 0.0, 0.0, true)
	var start := car.global_position
	var n0 := DriveImpacts.nudges
	await _run(car, 5.0)
	var moved := car.global_position.distance_to(start)
	_check(moved > 4.0, "throttle against a post gets the car free (%.1f m, %d nudges)" % [moved, DriveImpacts.nudges - n0])
	_clear()


func _lamp() -> void:
	var ch := CityChunk.new()
	ch.key = "dc_check_%d" % Time.get_ticks_usec()
	ch.name = "DriveCollideCheck"
	ch._statics = StreetProps.new()
	ch._statics.chunk = ch
	ch.add_child(ch._statics)
	_deck.add_child(ch)
	ch.global_position = _top
	_items.append(ch)
	var at := Vector3(0.0, 0.0, -18.0)
	var lp := StreetLamps.place(null, at, Vector2(1.0, 0.0), 0)
	ch._add_prop("lamp", at, Color(0.28, 0.29, 0.32), [[lp.key, lp.mesh, lp.xform, lp.paint, lp.custom]],
			[[lp.box, at + Vector3(0.0, (lp.box as Vector3).y * 0.5, 0.0), 0.0]])
	var rec: Dictionary = ch.prop_records.back()
	ch._mm_nodes = ch._batch.build(ch)
	var was := PropBreak.enabled
	PropBreak.enabled = true
	var car := await _driven(Vector3(0.0, 0.6, 0.0), 0.0, 22.2)
	# The speed the step before it went down and a few steps after.
	var before := 0.0
	var after := 0.0
	for i in 150:
		var sp := car.linear_velocity.length()
		await _tree.physics_frame
		if rec.dead:
			before = sp
			await _ticks(6)
			after = car.linear_velocity.length()
			break
	PropBreak.enabled = was
	_check(rec.dead, "a lamp post at 80 km/h goes down")
	_check(before > 0.0 and after > before * 0.8, "and the player keeps most of his speed through it (%.1f -> %.1f m/s)" % [before, after])
	_clear()


# --- helpers -----------------------------------------------------------------------------------

func _at(local: Vector3) -> Vector3:
	return _top + local


func _static_box(size: Vector3, at: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	b.add_child(cs)
	_city.add_child(b)
	b.global_position = at
	return b


func _traffic(type: int, local: Vector3) -> Vehicle:
	var car: Vehicle
	if BigVehicles.is_big(type):
		car = BigVehicles.make(type, 9)
	else:
		car = Vehicle.new()
		car.setup(type, Color(0.1, 0.3, 0.6), Vehicle.Addon.NONE)
	car.traffic = {"axis": 0, "index": 0, "dir": 1, "lane": 0.0, "speed": 0.0, "v": 0.0, "half": 2.2, "rear": 2.2, "placed": true, "dc_check": true}
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.freeze = true
	car.position = _city.to_local(_at(local))
	car.traffic_speed = 0.0
	_city.add_child(car)
	_items.append(car)
	return car


func _driven(local: Vector3, yaw: float, speed: float, throttle: bool = false) -> Vehicle:
	var car := Vehicle.new()
	car.setup(Vehicle.BodyType.SEDAN, Color(0.6, 0.1, 0.1), Vehicle.Addon.NONE)
	car.transform = Transform3D(Basis(Vector3.UP, yaw), _city.to_local(_at(local)))
	_city.add_child(car)
	_items.append(car)
	await _ticks(20)
	car.driver = _drv
	car.linear_velocity = -car.global_basis.z * speed
	car.hold_crash_watch(3)
	DriveImpacts.reset(car)
	if throttle:
		Input.action_press("move_forward")
	return car


func _run(car: Vehicle, seconds: float) -> Dictionary:
	var t := 0.0
	var minv := INF
	while t < seconds:
		await _tree.physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		var v := car.linear_velocity
		minv = minf(minv, Vector3(v.x, 0.0, v.z).length())
	var e := car.linear_velocity
	return {"min": minv, "end": Vector3(e.x, 0.0, e.z).length()}


func _clear() -> void:
	Input.action_release("move_forward")
	for n in _items:
		if is_instance_valid(n):
			if n is Vehicle:
				(n as Vehicle).driver = null
			n.queue_free()
	_items.clear()


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)
