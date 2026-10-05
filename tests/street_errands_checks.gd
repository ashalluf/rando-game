extends RefCounted
## Street errands checks for tests/smoke_test.gd (StreetErrands, scripts/npc/street_errands.gd):
## the shop doors are where the storefront puts them, a bus queue boards an open bus and a rider
## gets off the rear door, a walker gets into a parked car that pulls out into the traffic, a
## traffic car pulls into a kerb space and its driver gets out, a jaywalker crosses and traffic
## brakes for them, a walker goes into a shop and comes out of it, and a fright calls an errand
## off. Loaded at run time (not named there), so it compiles after the autoloads.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _plan: CityPlan
var _traffic: TrafficManager
var _ws: Node
var _chunk: Node3D
var _rect: Rect2


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_plan = city.plan
	_traffic = city.get_node("Traffic") as TrafficManager
	_ws = _tree.root.get_node("/root/WorldState")
	_chunk = _city.chunks.get(Vector2i(0, 0))
	_check(_chunk != null, "errands: the spawn block's chunk is loaded")
	if _chunk == null:
		return
	_rect = _plan.block(0, 0).rect
	var player := _tree.get_first_node_in_group("player") as Player
	if player.is_driving():
		player.exit_vehicle()
	var home: Vector3 = _ws.to_world(player.global_position)
	# The player in the middle of the block, so everything here is within the life range.
	var mid := _rect.get_center()
	# Held in the air over each scene, out of the way (nothing brakes for a player 12 m up).
	player.set_physics_process(false)
	_player_to(mid)
	_traffic.staged = true
	_clear_traffic()
	_doors()
	await _bus()
	await _shop()
	await _jaywalk()
	await _car_in()
	_clear_traffic()
	await _park_in()
	await _panic()
	_traffic.staged = false
	player.set_physics_process(true)
	player.global_position = _ws.to_local(home)
	player.velocity = Vector3.ZERO
	_city.update_streaming(true)
	await _ticks(5)


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _clear_traffic() -> void:
	for c in _traffic.cars.duplicate():
		if is_instance_valid(c):
			_traffic._retire(c)
	_traffic.cars.clear()


## A walker of our own on this block, standing at `at` (true world XZ), the player hovering
## over them (an errand only runs within the life range).
func _walker(at: Vector2, seed_value: int) -> Pedestrian:
	_player_to(at)
	var ped := Pedestrian.new()
	ped.setup(_rect, _plan.sidewalk_width, seed_value)
	ped.cross_chance = 0.0
	ped.life_chance = 0.0
	ped.position = Vector3(at.x, _chunk.ground_y(at.x, at.y) + 0.1, at.y)
	_chunk.add_child(ped)
	return ped


func _player_to(at: Vector2) -> void:
	var player := _tree.get_first_node_in_group("player") as Player
	player.global_position = _ws.to_local(Vector3(at.x, _chunk.ground_y(at.x, at.y) + 12.0, at.y))
	player.velocity = Vector3.ZERO


func _hidden(p: Pedestrian) -> bool:
	return StreetErrands._hidden.has(p.get_instance_id()) and not p.visible and p.collision_layer == 0


func _step(p: Pedestrian) -> String:
	if p.errand.is_empty():
		return ""
	return String(((p.errand.steps as Array)[int(p.errand.i)] as Dictionary).do)


## The doors the buildings note sit on their block, one per shop, where ShopfrontKit's door is.
func _doors() -> void:
	var doors := StreetErrands._doors(_chunk)
	var inside := true
	for d: Dictionary in doors:
		inside = inside and _rect.has_point(d.p) and (d.out as Vector2).is_normalized() and _rect.grow(0.01).has_point(d.front)
	_check(not doors.is_empty() and inside, "errands: the shop doors of the spawn block are noted, on the block, facing out (%d)" % doors.size())
	var b: Building = null
	for c in _chunk.get_children():
		if c is Building and c.has_meta("shop_doors") and not (c.get_meta("shop_doors") as Array).is_empty():
			b = c
			break
	if b == null:
		return
	var first: Array = (b.get_meta("shop_doors") as Array)[0]
	var key: int = first[2]
	_check(ShopfrontKit.door_index(key, 3) == Building.shop_byte(key, ShopfrontKit.SALT_DOOR) % 3,
		"errands: a noted door is the storefront's door bay (the same shop roll)")


## A queue at a stop boards a bus standing there with its doors open; a rider gets off the back.
func _bus() -> void:
	# A road on the block's east side, the kerb lane heading the way of its pavement's traffic.
	var axis := CityPlan.AXIS_X
	var index := 1
	var road := _plan.road_pos(axis, index)
	var width := _plan.road_width(axis, index)
	var lanes := 2 if width > _plan.street_width + 1.0 else 1
	# The east road's west side: traffic there drives -z (dir -1 on an AXIS_X road west of centre).
	var dir := 1
	var along := _rect.get_center().y
	var bus := _traffic.place_car(axis, index, dir, lanes - 1, along, 0.0, false, BigVehicles.BUS)
	await _ticks(2)
	var side := signf(float(bus.traffic.lane))
	bus.traffic.bus = 7
	bus.traffic.v = 0.0
	bus.traffic.speed = 0.0
	bus.traffic.dwell = 1.0
	bus.traffic.dwell_need = 1e9
	var fit := bus.get_node_or_null("BusFittings") as BigVehicles.BusFittings
	_check(fit != null, "errands: the bus has its doors (BusFittings)")
	if fit == null:
		return
	var door: Vector2 = StreetErrands._bus_doors(bus)[0]
	var kerb_x := road + side * width * 0.5
	var inward := Vector2(side, 0.0)
	var shelter := Vector2(kerb_x, door.y) + inward * 2.0
	var ring_rect: Rect2 = _plan.block(1 if side > 0.0 else 0, 0).rect
	StreetErrands.add_stop(_chunk, ring_rect, shelter, inward, Vector2(0.0, 1.0), axis, index, dir, along)
	var stop: Dictionary = StreetErrands._stops.back()
	var riders: Array[Pedestrian] = []
	for k in 2:
		var p := _walker(shelter, 4100 + k)
		riders.append(p)
	await _ticks(2)
	for p in riders:
		StreetErrands._start_bus(p, stop, true)
	await _ticks(20)
	var waiting := riders.all(func(p: Pedestrian) -> bool: return _step(p) == "wait_bus" and p.visible)
	_check(waiting, "errands: two walkers stand in the bus stop's queue")
	fit.set_doors(true)
	var boarded := false
	for i in 60 * 12:
		await _tree.physics_frame
		if riders.all(func(p: Pedestrian) -> bool: return _hidden(p) and _step(p) == "ride"):
			boarded = true
			break
	_check(boarded, "errands: the queue boards the bus through its front door when the doors open (steps %s %s)" % [_step(riders[0]), _step(riders[1])])
	_check(float(bus.traffic.dwell_need) > 1.0, "errands: the bus is held at the stop while people get on")
	# One gets off the rear door at the next stop and walks onto the pavement.
	var rider := riders[0]
	StreetErrands.alight(rider, bus, 0, ring_rect)
	var off := false
	for i in 60 * 6:
		await _tree.physics_frame
		if rider.errand.is_empty() and rider.visible:
			off = true
			break
	var here := Vector2(rider.position.x, rider.position.z)
	_check(off and rider.ring == ring_rect and not StreetErrands.on_carriageway(_plan, here),
		"errands: a rider gets off the rear door and walks onto the pavement (at %s)" % here.round())
	var rear: Vector2 = StreetErrands._bus_doors(bus)[1]
	_check(here.distance_to(rear) < 5.0, "errands: they came off by the rear door (%.1f m from it)" % here.distance_to(rear))
	for p in riders:
		p.queue_free()
	fit.set_doors(false)
	_traffic.cars.erase(bus)
	_traffic._retire(bus)
	StreetErrands._stops.erase(stop)
	await _ticks(2)


## Into a shop by its door, out of it again.
func _shop() -> void:
	var doors := StreetErrands._doors(_chunk)
	if doors.is_empty():
		return
	var door: Dictionary = doors[0]
	var p := _walker(door.front, 4200)
	await _ticks(2)
	StreetErrands._start_shop(p, door)
	var went_in := false
	for i in 60 * 15:
		await _tree.physics_frame
		if _hidden(p):
			went_in = true
			break
	var here := Vector2(p.position.x, p.position.z)
	_check(went_in and here.distance_to(door.p) < 0.6, "errands: a walker goes in through a shop's door (%.2f m from it)" % here.distance_to(door.p))
	var step: Dictionary = (p.errand.steps as Array)[int(p.errand.i)]
	step.until = 0
	var out := false
	for i in 60 * 8:
		await _tree.physics_frame
		if p.errand.is_empty() and p.visible:
			out = true
			break
	here = Vector2(p.position.x, p.position.z)
	_check(out and p.ring == door.ring and here.distance_to(door.front) < 1.5, "errands: and comes back out of it onto the pavement (%.1f m from the front)" % here.distance_to(door.front))
	p.queue_free()
	await _ticks(1)


## Over the road mid-block, and a car in that lane stops short of them.
func _jaywalk() -> void:
	var p: Pedestrian = null
	var started := false
	# Along the block's south kerb, the first stretch with a gap in the parked cars.
	for k in 8:
		var x := lerpf(_rect.position.x + 16.0, _rect.end.x - 16.0, float(k) / 7.0)
		var at := Vector2(x, _rect.position.y + 1.5)
		p = _walker(at, 4300 + k)
		await _ticks(2)
		if StreetErrands._start_jay(p, _plan, at):
			started = true
			break
		p.queue_free()
	_check(started, "errands: a walker finds a gap in the parked cars to jaywalk through")
	if not started:
		return
	var look: Dictionary = (p.errand.steps as Array)[2]
	var crossed := false
	var in_road := false
	for i in 60 * 30:
		await _tree.physics_frame
		in_road = in_road or StreetErrands._jay.has(p.get_instance_id())
		if p.errand.is_empty():
			crossed = true
			break
	var here := Vector2(p.position.x, p.position.z)
	var next: Rect2 = _plan.block(0, -1).rect
	_check(crossed and in_road and p.ring == next and next.grow(0.5).has_point(here) and not StreetErrands.on_carriageway(_plan, here),
		"errands: the jaywalker crosses to the block opposite (at %s, ring %s)" % [here.round(), p.ring == next])
	p.queue_free()
	# Traffic: a walker standing in a lane 30 m ahead of a car; the car stops short of them.
	var axis := int(look.axis)
	var index := int(look.index)
	var along := float(look.along)
	var car := _traffic.place_car(axis, index, 1, 0, along - 30.0, 9.0, false)
	var lane_x: float = _plan.road_pos(axis, index) + float(car.traffic.lane)
	var id := 99999999
	StreetErrands._jay[id] = [axis, index, along, lane_x]
	for i in 60 * 6:
		await _tree.physics_frame
	var nose := float(car.traffic.along) + car_half(car)
	StreetErrands._jay.erase(id)
	_check(nose < along and float(car.traffic.v) < 0.3, "errands: a car brakes and stops short of a jaywalker in its lane (nose %.1f m short)" % (along - nose))
	_traffic.cars.erase(car)
	_traffic._retire(car)


func car_half(car: Vehicle) -> float:
	return float(car.traffic.get("half", 2.4))


## A walker gets into a parked car, which pulls out into the traffic with its lamps on.
func _car_in() -> void:
	var car: Vehicle = null
	for c in _tree.get_nodes_in_group("vehicle"):
		var v := c as Vehicle
		if v == null or v.is_traffic() or v.has_meta("errand") or v.has_meta("driven") or BigVehicles.is_big(v.body_type) or v._damage != null:
			continue
		var wp: Vector3 = _ws.to_world(v.global_position)
		if Vector2(wp.x, wp.z).distance_to(_rect.get_center()) > 160.0 or StreetErrands._parked_road(_plan, v).is_empty():
			continue
		car = v
		break
	_check(car != null, "errands: a parked car in a kerb space near the spawn block")
	if car == null:
		return
	var geo := StreetErrands._car_frame(car)
	var ring := StreetErrands._kerb_ring(_plan, geo)
	var p := _walker(geo.kerb, 4400)
	p.ring = ring
	await _ticks(2)
	# Near the player, wherever the car is.
	var player := _tree.get_first_node_in_group("player") as Node3D
	_player_to(geo.kerb)
	var ok := StreetErrands._start_car_in(p, _plan, car)
	var door_seen := false
	var left := false
	for i in 60 * 40:
		await _tree.physics_frame
		var ec := car.get_node_or_null("ErrandCar") as ErrandCar
		if ec and ec.door and ec.door.visible:
			door_seen = true
		if car.is_traffic():
			left = true
			break
	_check(ok and door_seen and _hidden(p), "errands: a walker opens a parked car's driver door and gets in (door %s, hidden %s, step %s)" % [door_seen, _hidden(p), _step(p)])
	_check(left and car.freeze and car.wheels.is_empty() and _traffic.cars.has(car),
		"errands: the car pulls out into the traffic: kinematic, no physics wheels, the traffic's own")
	_check(car.lights_running(), "errands: its lamps come on with somebody at the wheel")
	var start: Vector3 = _ws.to_world(car.global_position)
	for i in 60 * 4:
		await _tree.physics_frame
	var moved := Vector2(start.x, start.z).distance_to(Vector2(_ws.to_world(car.global_position).x, _ws.to_world(car.global_position).z))
	_check(moved > 1.0 and absf(float(car.traffic.get("shift", 0.0))) < CityPlan.parking_offset(_plan.road_width(int(car.traffic.axis), int(car.traffic.index))),
		"errands: and drives off, easing out of the kerb space (%.1f m)" % moved)
	_traffic.cars.erase(car)
	_traffic._retire(car)
	p.queue_free()


## A traffic car pulls into a free kerb space and its driver gets out.
func _park_in() -> void:
	var player := _tree.get_first_node_in_group("player") as Node3D
	var car: Vehicle = null
	var spot := NAN
	for axis: int in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
		for index in [0, 1, 2, -1]:
			for dir: int in [1, -1]:
				var width := _plan.road_width(axis, index)
				var lanes := 2 if width > _plan.street_width + 1.0 else 1
				# Just into the block, heading along it.
				var lo := _rect.position.y if axis == CityPlan.AXIS_X else _rect.position.x
				var hi := _rect.end.y if axis == CityPlan.AXIS_X else _rect.end.x
				var along := lo + 3.0 if dir > 0 else hi - 3.0
				var road := _plan.road_pos(axis, index)
				_player_to(Vector2(road, along) if axis == CityPlan.AXIS_X else Vector2(along, road))
				var c := _traffic.place_car(axis, index, dir, lanes - 1, along, 6.0, false)
				await _ticks(3)
				if not is_instance_valid(c) or not c.is_inside_tree() or not _traffic.cars.has(c):
					continue
				spot = StreetErrands.free_space(_traffic, c)
				if not is_nan(spot):
					car = c
					break
				_traffic.cars.erase(c)
				_traffic._retire(c)
			if car:
				break
		if car:
			break
	_check(car != null, "errands: a free kerb space ahead of a car in a kerb lane")
	if car == null:
		return
	var at: Vector3 = car.traffic.wp
	_player_to(Vector2(at.x, at.z))
	StreetErrands.start_parking(car, spot)
	var parked := false
	for i in 60 * 30:
		await _tree.physics_frame
		if not car.is_traffic():
			parked = true
			break
	var wp: Vector3 = _ws.to_world(car.global_position)
	_check(parked and not car.freeze and car.wheels.size() == 4 and not _traffic.cars.has(car),
		"errands: a traffic car pulls into a kerb space and is parked there (a physics car on its wheels)")
	_check(not StreetErrands._parked_road(_plan, car).is_empty(), "errands: it stands in the kerb space, nose the traffic's way (at %s)" % wp.round())
	var driver: Pedestrian = null
	for i in 60 * 6:
		await _tree.physics_frame
		for n in _tree.get_nodes_in_group("pedestrian"):
			var q := n as Pedestrian
			if q and q.visible and not q.errand.is_empty() and (q.global_position.distance_to(car.global_position) < 4.0):
				driver = q
		if driver:
			break
	_check(driver != null, "errands: its driver gets out by the driver's door")
	_check(not car.lights_running(), "errands: and the parked car's lamps go off")
	for i in 60 * 10:
		await _tree.physics_frame
		if driver == null or not is_instance_valid(driver) or driver.errand.is_empty() or _step(driver) == "goto":
			break
	if driver and is_instance_valid(driver):
		var here := Vector2(driver.position.x, driver.position.z)
		_check(not StreetErrands.on_carriageway(_plan, here), "errands: the driver walks round onto the pavement (at %s)" % here.round())
		driver.queue_free()


## A fright calls off a queue at a stop, and hidden people cannot be hit.
func _panic() -> void:
	var p := _walker(_rect.position + Vector2(2.0, 20.0), 4500)
	await _ticks(2)
	var stop := {"chunk": weakref(_chunk), "ring": _rect, "kerb": _rect.position + Vector2(0.0, 20.0), "inward": Vector2.RIGHT,
		"travel": Vector2.UP, "axis": 0, "index": 0, "dir": -1, "stop": 0.0,
		"slots": [_rect.position + Vector2(1.2, 20.0)], "taken": [null]}
	StreetErrands._start_bus(p, stop, true)
	await _ticks(5)
	Pedestrian.alarm(_tree, p.global_position + Vector3(4.0, 0.0, 0.0), 30.0, 0, true, "")
	await _ticks(3)
	_check(p.errand.is_empty() and stop.taken[0] == null, "errands: a gunshot breaks up the bus queue")
	StreetErrands._hide(p)
	_check(p.collision_layer == 0 and not p.visible, "errands: somebody inside is out of reach of rounds and blasts")
	var id := p.get_instance_id()
	p.queue_free()
	await _ticks(1)
	_check(not StreetErrands._hidden.has(id), "errands: a walker freed while inside leaves the hidden pool")
