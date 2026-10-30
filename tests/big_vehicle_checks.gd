extends RefCounted
## The big vehicles (BigVehicles: the bus, the box truck, the semi) for tests/smoke_test.gd.
## Loaded at run time (not named there), so it compiles after the autoloads and can name Vehicle,
## BigVehicles and TrafficManager freely. On a deck high over the street (like the car lamp
## checks) for what needs no road, on the spawn junction's roads (staged, like the street-life
## checks) for what does. Checks: each builds as a model with its glass, a driver, its truck
## wheels (duals, the trailer's on the trailer), lamps and collision, inside the traffic's build
## budget; a hit hands a traffic bus to physics on four wheels; the trailer follows its tractor
## round a snapped turn like a real one (the swing, then straightening out) and never past its
## limit; the pool hands a retired semi back; the bus lines and stops are pure (the same answer
## twice, a stop's kerb kept clear, the shelter's kerb and the bus's agree); a bus pulls in to
## its stop, opens its doors and kneels, then closes up and drives on; a car behind a semi at a
## red stops behind its TRAILER; a freeway semi rides the deck at its ride height.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _plan: CityPlan
var _traffic: TrafficManager
var _ws: Node
var _deck: StaticBody3D
var _top: Vector3
var _cars: Array = []


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_plan = city.plan
	_traffic = city.get_node("Traffic") as TrafficManager
	_ws = _tree.root.get_node("/root/WorldState")
	var player := _tree.get_first_node_in_group("player") as Player
	if player.is_driving():
		player.exit_vehicle()
	var police: Node = city.get_node_or_null("Police")
	var police_was: Variant = police.get("enabled") if police else null
	if police:
		police.set("enabled", false)
	var home: Vector3 = _ws.to_world(player.global_position)
	_top = player.global_position + Vector3(0.0, 300.0, 0.0)
	_build_deck()
	player.global_position = _top + Vector3(0.0, 1.2, 60.0)
	player.velocity = Vector3.ZERO
	await _ticks(3)

	await _builds()
	await _hit_goes_physical()
	await _trailer_follows()
	_pool()
	_lines_and_stops()

	for c in _cars:
		if is_instance_valid(c):
			c.queue_free()
	_cars.clear()
	_deck.queue_free()
	player.global_position = _ws.to_local(home)
	player.velocity = Vector3.ZERO
	await _ticks(3)

	_traffic.staged = true
	_clear_traffic()
	await _bus_at_stop(player)
	_clear_traffic()
	await _queue_behind_semi(player)
	_clear_traffic()
	await _freeway_semi()
	_clear_traffic()
	_traffic.staged = false
	player.global_position = _ws.to_local(home)
	player.velocity = Vector3.ZERO
	if police:
		police.set("enabled", police_was)
	_city.update_streaming(true)
	await _ticks(5)


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _frames(n: int) -> void:
	for i in n:
		await _tree.process_frame


func _clear_traffic() -> void:
	for c in _traffic.cars.duplicate():
		if is_instance_valid(c):
			_traffic._retire(c)
	_traffic.cars.clear()
	for c in _traffic.freeway_cars.duplicate():
		if is_instance_valid(c):
			_traffic._retire(c)
	_traffic.freeway_cars.clear()


func _build_deck() -> void:
	_deck = StaticBody3D.new()
	_deck.collision_layer = 1
	_deck.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(240.0, 1.0, 240.0)
	shape.shape = box
	_deck.add_child(shape)
	_city.add_child(_deck)
	_deck.global_position = _top - Vector3(0.0, 0.5, 0.0)


## A big vehicle at (x, z) on the deck, kinematic in traffic (heading -Z) or parked.
func _big(type: int, at: Vector2, traffic: bool = true) -> Vehicle:
	var car := BigVehicles.make(type, 11)
	if traffic:
		car.traffic = {"axis": 0, "index": 0, "dir": -1, "lane": 0.0, "speed": 8.0}
		car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		car.freeze = true
		car.traffic_speed = 8.0
	car.position = _city.to_local(_top + Vector3(at.x, car.road_lift() if traffic else 1.2, at.y))
	_city.add_child(car)
	_cars.append(car)
	return car


func _builds() -> void:
	# Warm each model once (the first load of a .glb is the importer's), then time a second build.
	var worst := 0.0
	var ok := true
	var why := ""
	var want_rigs := {BigVehicles.BUS: 4, BigVehicles.BOX_TRUCK: 4, BigVehicles.SEMI: 10}
	var x := -60.0
	for type: int in [BigVehicles.BUS, BigVehicles.BOX_TRUCK, BigVehicles.SEMI]:
		_big(type, Vector2(x, -80.0))
		var t0 := Time.get_ticks_usec()
		var car := _big(type, Vector2(x, 0.0))
		worst = maxf(worst, float(Time.get_ticks_usec() - t0) / 1000.0)
		x += 30.0
		var rigs := car._wheel_rigs.size()
		var good := car._has_model and rigs == int(want_rigs[type]) and car.get_node_or_null("NightLights") != null \
				and car.cabin_seats() & 1 == 1 and not car._glass_slots.is_empty()
		if type == BigVehicles.SEMI:
			var hitch := car.get_node_or_null("Hitch") as BigVehicles.Hitch
			good = good and hitch != null and hitch.pivot.find_children("Wheel*", "Node3D", false, false).size() == 4
		if type == BigVehicles.BUS:
			good = good and car.get_node_or_null("BusFittings") != null and car.cabin_seats() == 1
		if not good:
			ok = false
			why += " %s(model %s rigs %d seats %d glass %d)" % [Vehicle.BODY_NAMES[type], car._has_model, rigs, car.cabin_seats(), car._glass_slots.size()]
	await _ticks(2)
	_check(ok, "the bus, the box truck and the semi build as models with their glass, a driver, lamps and truck wheels (duals; the trailer's on the trailer)%s" % why)
	_check(worst < 120.0, "a big vehicle builds inside the traffic's one-a-frame budget (worst %.1f ms)" % worst)
	# Dual wheels are one mesh a pair, and every truck wheel has a far LOD.
	var semi: Vehicle = _cars[_cars.size() - 1]
	var rig: Array = semi._wheel_rigs[2]
	_check(rig.size() > 7 and rig[6] != rig[7] and (rig[6] as Mesh).get_surface_count() == 1, "a dual pair is one wheel mesh with a far LOD of its own")


func _hit_goes_physical() -> void:
	var bus := _big(BigVehicles.BUS, Vector2(-60.0, 50.0))
	await _ticks(2)
	bus.take_hit(-1, 12.0, Vector3.LEFT, bus.global_position + Vector3(1.4, 1.2, 0.0), Vehicle.HIT_BULLET)
	await _ticks(20)
	_check(not bus.is_traffic() and not bus.freeze and bus.wheels.size() == 4,
			"a round into a traffic bus hands it to physics on four wheels (traffic %s, wheels %d)" % [bus.is_traffic(), bus.wheels.size()])
	_check(bus.mass > 5000.0, "and it is as heavy as a bus (%.0f kg)" % bus.mass)


## A kinematic semi driven straight, snapped through a right angle (the way a street car turns at
## a junction's centre) and driven on: the trailer starts at the old heading and swings round
## behind it as a trailer does, straight again within a couple of its own lengths.
func _trailer_follows() -> void:
	var semi := _big(BigVehicles.SEMI, Vector2(40.0, 60.0))
	var hitch := semi.get_node("Hitch") as BigVehicles.Hitch
	var pos := semi.global_position
	var heading := Vector3.FORWARD
	for i in 40:
		pos += heading * 0.2
		semi.global_transform = Transform3D(Basis.looking_at(heading), pos)
		await _tree.physics_frame
	var straight := absf(hitch.angle)
	heading = Vector3.LEFT
	semi.global_transform = Transform3D(Basis.looking_at(heading), pos)
	await _ticks(2)
	var swung := absf(hitch.angle)
	var worst := swung
	for i in 300:
		pos += heading * 0.15
		semi.global_transform = Transform3D(Basis.looking_at(heading), pos)
		await _tree.physics_frame
		worst = maxf(worst, absf(hitch.angle))
	var after := absf(hitch.angle)
	_check(straight < 0.02 and swung > 1.2 and after < 0.12 and worst <= BigVehicles.Hitch.MAX_ANGLE + 0.001,
			"the trailer follows the tractor round a snapped turn (straight %.2f, just after %.2f, 45 m on %.2f rad)" % [straight, swung, after])


func _pool() -> void:
	var semi := BigVehicles.make(BigVehicles.SEMI, 3)
	semi.traffic = {"axis": 0, "index": 0, "dir": 1, "lane": 0.0, "speed": 0.0}
	semi.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	semi.freeze = true
	_traffic.add_child(semi)
	_traffic._retire(semi)
	var car := _traffic._new_car()
	var back := _traffic._new_car(BigVehicles.SEMI)
	_check(back == semi and car != semi and not BigVehicles.is_big(car.body_type),
			"the pool hands a retired semi back for a semi, never for a car")
	if is_instance_valid(car) and car != semi:
		_traffic._retire(car)
	semi.free()


## A road with a bus line and a block on it with a stop for `dir` near the spawn, or [].
func _find_stop() -> Array:
	for r in 16:
		for axis: int in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
			for index: int in [r, -r]:
				if BigVehicles.route_of(_plan, axis, index) == 0:
					continue
				for k in range(-2, 3):
					for dir: int in [1, -1]:
						var stop := BigVehicles.block_stop(_plan, axis, index, k, dir)
						if is_nan(stop):
							continue
						var road := _plan.road_pos(axis, index)
						var q := Vector2(road, stop) if axis == CityPlan.AXIS_X else Vector2(stop, road)
						if _plan.zone_at(q) == MacroMap.Zone.CITY and _plan.road_open(axis, index, stop):
							return [axis, index, k, dir, stop]
	return []


func _lines_and_stops() -> void:
	var lines := 0
	var avenues := 0
	var same := true
	for i in range(-40, 40):
		for axis: int in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
			var a := BigVehicles.route_of(_plan, axis, i)
			same = same and a == BigVehicles.route_of(_plan, axis, i)
			if _plan.road_width(axis, i) > _plan.street_width + 1.0:
				avenues += 1
				if a != 0:
					lines += 1
			elif a != 0:
				same = false
	_check(same and lines > 0 and lines < avenues, "bus lines run on some avenues and only avenues, the same every time asked (%d of %d)" % [lines, avenues])
	var s := _find_stop()
	if s.is_empty():
		_check(false, "a bus stop near the spawn to check")
		return
	var axis: int = s[0]
	var index: int = s[1]
	var dir: int = s[3]
	var stop: float = s[4]
	var width := _plan.road_width(axis, index)
	var side := (-1.0 if axis == CityPlan.AXIS_X else 1.0) * float(dir)
	var kerb := _plan.road_pos(axis, index) + side * CityPlan.parking_offset(width)
	var at := func(along: float) -> Vector2:
		return Vector2(kerb, along) if axis == CityPlan.AXIS_X else Vector2(along, kerb)
	var inside: bool = BigVehicles.in_stop_zone(_plan, at.call(stop - float(dir) * 8.0))
	var far: bool = BigVehicles.in_stop_zone(_plan, at.call(stop + float(dir) * 30.0))
	var other: bool = BigVehicles.in_stop_zone(_plan, (at.call(stop - float(dir) * 8.0) as Vector2) + (Vector2(-2.0 * side * CityPlan.parking_offset(width), 0.0) if axis == CityPlan.AXIS_X else Vector2(0.0, -2.0 * side * CityPlan.parking_offset(width))))
	_check(inside and not far, "a stop's kerb is kept clear of parked cars behind the bus's nose, and only there (in %s, 30 m on %s, across the road %s)" % [inside, far, other])


## A bus 40 m short of its stop: it pulls in and stops with its nose at the stop, opens its doors
## and kneels, then closes up and drives on.
func _bus_at_stop(player: Player) -> void:
	var s := _find_stop()
	if s.is_empty():
		return
	var axis: int = s[0]
	var index: int = s[1]
	var dir: int = s[3]
	var stop: float = s[4]
	var cross := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
	# Every junction near it green for this road.
	var k0 := _plan._index_at(cross, stop)
	for k in range(k0 - 2, k0 + 3):
		var node := Vector2i(index, k) if axis == CityPlan.AXIS_X else Vector2i(k, index)
		if TrafficSignals.is_signal(_plan, node.x, node.y):
			TrafficSignals.force(_plan, node.x, node.y, axis, TrafficSignals.Light.GREEN, 0.2)
	var road := _plan.road_pos(axis, index)
	var off := _plan.road_width(axis, index) * 0.5 + 6.0
	var stand := Vector2(road + off, stop) if axis == CityPlan.AXIS_X else Vector2(stop, road + off)
	player.global_position = _ws.to_local(Vector3(stand.x, _plan.height_at(stand) + 1.0, stand.y))
	player.velocity = Vector3.ZERO
	var width := _plan.road_width(axis, index)
	var lanes := 2 if width > _plan.street_width + 1.0 else 1
	var bus := _traffic.place_car(axis, index, dir, lanes - 1, stop - float(dir) * 26.0, 8.0, false, BigVehicles.BUS)
	var fit := bus.get_node("BusFittings") as BigVehicles.BusFittings
	var stopped_at := INF
	var opened := 0.0
	var knelt := 0.0
	var shifted := 0.0
	var left := false
	for i in 60 * 30:
		await _tree.physics_frame
		var t: Dictionary = bus.traffic
		if not t.has("along"):
			continue
		var nose := float(t.along) + float(dir) * float(t.half)
		if float(t.get("v", 1.0)) < 0.05 and float(t.get("dwell", 0.0)) > 0.0 and stopped_at == INF:
			stopped_at = (stop - nose) * float(dir)
		opened = maxf(opened, fit.open)
		knelt = maxf(knelt, fit.kneel)
		shifted = maxf(shifted, float(t.get("shift", 0.0)))
		if stopped_at != INF and (nose - stop) * float(dir) > 6.0:
			left = true
			break
	await _frames(3)
	_check(stopped_at != INF and absf(stopped_at) < 1.5 and shifted > 1.0,
			"a bus pulls in to its stop and stands with its nose at it (%.2f m short, %.1f m toward the kerb)" % [stopped_at, shifted])
	_check(opened > 0.95 and knelt > 0.9, "it opens its doors and kneels there (doors %.2f, kneel %.2f)" % [opened, knelt])
	_check(left and fit.want_open == false, "then closes up and drives on (left %s)" % left)
	var lit := false
	var sm := (fit._sign_slots[0][0] as MeshInstance3D).get_surface_override_material(fit._sign_slots[0][1]) as ShaderMaterial if not fit._sign_slots.is_empty() else null
	if sm:
		lit = float(sm.get_shader_parameter("lit")) > 0.5
	_check(lit and fit.line == BigVehicles.route_of(_plan, axis, index), "its signs show its line (%d)" % fit.line)


## A semi and a fast car behind it up to the spawn junction's red: the car stops behind the end
## of the TRAILER, not the tractor.
func _queue_behind_semi(player: Player) -> void:
	var node := Vector2i(0, 0)
	var cross_pos := _plan.road_pos(CityPlan.AXIS_Z, 0)
	TrafficSignals.force(_plan, node.x, node.y, CityPlan.AXIS_X, TrafficSignals.Light.RED, 0.5)
	var off := _plan.road_width(CityPlan.AXIS_X, 0) * 0.5 + 6.0
	var road := _plan.road_pos(CityPlan.AXIS_X, 0)
	player.global_position = _ws.to_local(Vector3(road + off, _plan.height_at(Vector2(road + off, cross_pos - 30.0)) + 1.0, cross_pos - 30.0))
	var semi := _traffic.place_car(CityPlan.AXIS_X, 0, 1, 0, cross_pos - 40.0, 8.0, false, BigVehicles.SEMI)
	var car := _traffic.place_car(CityPlan.AXIS_X, 0, 1, 0, cross_pos - 95.0, 15.0, false)
	var worst := INF
	for i in 60 * 10:
		await _tree.physics_frame
		var a: Dictionary = semi.traffic
		var b: Dictionary = car.traffic
		if not a.has("along") or not b.has("along"):
			continue
		worst = minf(worst, (float(a.along) - float(a.rear)) - (float(b.along) + float(b.half)))
		if i > 120 and float(a.get("v", 1.0)) < 0.05 and float(b.get("v", 1.0)) < 0.05:
			break
	_check(worst > 0.3 and worst < 8.0 and float(car.traffic.get("v", 1.0)) < 0.05,
			"a car queues behind a semi's trailer, not inside it (gap to the trailer's end %.2f m)" % worst)


## A semi placed on a freeway deck stands on it at its ride height and drives on along it.
func _freeway_semi() -> void:
	var fw: Freeway = _plan.macro.freeway if _plan.macro else null
	if fw == null or fw.routes.is_empty():
		return
	var ri := 0
	var t := fw.length_of(ri) * 0.5
	var semi := _traffic.place_freeway_car(ri, t, 1, BigVehicles.SEMI, 20.0)
	var p := semi.global_position
	var deck: Vector3 = fw.point_at(ri, t)[0]
	var lift: float = (p.y - (_ws.to_local(deck) as Vector3).y) - semi.road_lift()
	await _ticks(30)
	var moved := float(semi.traffic.t) - t
	_check(absf(lift) < 0.05 and moved > 5.0 and semi.has_node("Hitch"), "a semi rides a freeway deck at its ride height and drives on (%.3f m off, %.1f m on)" % [lift, moved])
