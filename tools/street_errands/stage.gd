extends RefCounted
## Stages one of the street errands in front of the camera for a still (tools/glshot/still_shot.gd
## ERRAND=bus|car|jay|shop|deliver) and returns the EYE that frames it ("" if nothing could be
## staged). Loaded at run time by the still script, so it may name the game's classes:
##   bus      a bus at the stop nearest the camera, its doors open, a queue boarding and one rider
##            stepping off the rear door; EYE on the pavement ahead of its nose (ERRAND_AHEAD)
##   car      a walker at a parked car's open driver's door, getting in; EYE behind and to the left
##   jay      a jaywalker out in the road mid-block, a car braking in front of them
##   shop     somebody going in through a shop's door and somebody coming out of the next one
##   deliver  a box truck parked at the kerb, its driver wheeling a hand truck of boxes to a shop
## ERRAND_PICK=n takes the n-th nearest candidate instead of the nearest.

var _scene: Node
var _plan: CityPlan
var _traffic: TrafficManager
var _ws: Node
var _tree: SceneTree


func stage(scene: Node, kind: String, cam: Camera3D) -> String:
	_scene = scene
	_tree = scene.get_tree()
	_plan = scene.get("plan")
	_traffic = scene.get_node_or_null("Traffic") as TrafficManager
	_ws = _tree.root.get_node("/root/WorldState")
	if _plan == null or _traffic == null or cam == null:
		print("ERRAND: nothing to stage with")
		return ""
	_traffic.staged = true
	var cp: Vector3 = _ws.to_world(cam.global_position)
	var here := Vector2(cp.x, cp.z)
	match kind:
		"bus":
			return await _bus(here)
		"car":
			return await _car(here)
		"jay":
			return await _jay(here)
		"shop":
			return await _shop(here)
		"deliver":
			return await _deliver(here)
	print("ERRAND: unknown kind ", kind)
	return ""


func _pick() -> int:
	var v := OS.get_environment("ERRAND_PICK")
	return int(v) if v != "" else 0


func _envf(key: String, fallback: float) -> float:
	var v := OS.get_environment(key)
	return float(v) if v != "" else fallback


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _eye(at: Vector2, height_agl: float, look_at: Vector3) -> String:
	var h := _plan.height_at(at) + CityChunk.SIDEWALK_TOP + height_agl
	var d := look_at - Vector3(at.x, h, at.y)
	var yaw := rad_to_deg(atan2(-d.x, -d.z))
	var pitch := rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
	return "%.2f,%.2f,%.2f,%.2f,%.2f" % [at.x, h, at.y, yaw, pitch]


## The crowd's walkers near `at` (true world), nearest first, that can be borrowed for a scene.
func _walkers(at: Vector2, reach: float) -> Array:
	var out: Array = []
	for n in _tree.get_nodes_in_group("pedestrian"):
		var p := n as Pedestrian
		if p == null or not p._lives() or p._down or not p.errand.is_empty() or p._anim == null:
			continue
		var d := Vector2(p.position.x, p.position.z).distance_to(at)
		if d < reach:
			out.append([d, p])
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out.map(func(e): return e[1])


## A walker for the scene: one of the crowd moved there, or a new one on the chunk.
func _borrow(pool: Array, at: Vector2, ring: Rect2) -> Pedestrian:
	var p: Pedestrian = null
	if not pool.is_empty():
		p = pool.pop_front()
		p._end_act(true)
		p._cross = Pedestrian.Cross.NONE
		p._leave_crosswalk()
	else:
		var chunk: Node = _scene.chunks.get(_plan.chunk_index_at(ring.get_center()))
		if chunk == null:
			return null
		p = Pedestrian.new()
		p.setup(ring, _plan.sidewalk_width, hash([at, "errand stage"]))
		chunk.add_child(p)
	p.ring = ring
	p._panic_left = 0.0
	p._pause_left = 0.0
	p.position = Vector3(at.x, p._ground_y(at.x, at.y, p.position.y), at.y)
	return p


func _bus(here: Vector2) -> String:
	StreetErrands._prune_stops()
	var stops: Array = StreetErrands._stops.duplicate()
	stops.sort_custom(func(a, b): return (a.kerb as Vector2).distance_to(here) < (b.kerb as Vector2).distance_to(here))
	if stops.is_empty():
		print("ERRAND bus: no stop near the camera")
		return ""
	var stop: Dictionary = stops[clampi(_pick(), 0, stops.size() - 1)]
	var axis: int = stop.axis
	var index: int = stop.index
	var dir: int = stop.dir
	for c in _traffic.cars.duplicate():
		if is_instance_valid(c) and int(c.traffic.get("axis", -1)) == axis and int(c.traffic.get("index", -99999)) == index:
			_traffic.cars.erase(c)
			_traffic._retire(c)
	var width := _plan.road_width(axis, index)
	var lanes := 2 if width > _plan.street_width + 1.0 else 1
	var bus := _traffic.place_car(axis, index, dir, lanes - 1, float(stop.stop), 0.0, false, BigVehicles.BUS)
	var t: Dictionary = bus.traffic
	t.bus = maxi(BigVehicles.route_of(_plan, axis, index), 2)
	t.v = 0.0
	t.speed = 0.0
	t.shift = BigVehicles.STOP_SHIFT
	t.dwell = 1.0
	t.dwell_need = 1e9
	await _ticks(2)
	# Its front door on the stop's first slot.
	var door: Vector2 = StreetErrands._bus_doors(bus)[0]
	var slot0: Vector2 = (stop.slots as Array)[0]
	var travel: Vector2 = stop.travel
	var shift := (slot0 - door).dot(travel)
	var lane: float = t.lane
	var lat: float = _plan.road_pos(axis, index) + lane + signf(lane) * BigVehicles.STOP_SHIFT
	var wp: Vector3 = _ws.to_world(bus.global_position)
	var al := (wp.z if axis == CityPlan.AXIS_X else wp.x) + shift
	var p2 := Vector2(lat, al) if axis == CityPlan.AXIS_X else Vector2(al, lat)
	bus.global_transform = Transform3D(bus.global_basis, _ws.to_local(Vector3(p2.x, _traffic._relief(p2) + CityChunk.ROAD_TOP + bus.road_lift(), p2.y)))
	var fit := bus.get_node_or_null("BusFittings") as BigVehicles.BusFittings
	fit.show_line(int(t.bus), BigVehicles.destination(_plan, axis, index, dir))
	fit.set_doors(true)
	for i in 70:
		await _tree.physics_frame
	var pool := _walkers(slot0, 70.0)
	var ring: Rect2 = stop.ring
	door = StreetErrands._bus_doors(bus)[0]
	# The queue: four in the slots, the first already stepping up to the door.
	for k in 4:
		var at: Vector2 = (stop.slots as Array)[k]
		var p := _borrow(pool, at, ring)
		if p == null:
			continue
		(stop.taken as Array)[k] = p
		StreetErrands._start_bus(p, stop, true)
		var step: Dictionary = (p.errand.steps as Array)[0]
		if k == 0:
			p.position = Vector3(lerpf(at.x, door.x, 0.55), p.position.y, lerpf(at.y, door.y, 0.55))
			var d := door - at
			p._visual.rotation.y = atan2(-d.x, -d.y)
			p.errand.steps[0] = {"do": "board", "bus": bus, "delay": 0.0, "stop": stop, "slot": 0}
		else:
			p._visual.rotation.y = float(step.yaw)
	# One stepping off the back.
	var off := _borrow(pool, slot0, ring)
	if off:
		StreetErrands.alight(off, bus, 0, ring)
		(off.errand.steps[0] as Dictionary).secs = 0.0
	for i in 40:
		await _tree.physics_frame
	var kerb := StreetErrands._kerb_dir(bus)
	var ahead := StreetErrands._along(bus)
	var e := door + ahead * _envf("ERRAND_AHEAD", 9.0) + kerb * _envf("ERRAND_SIDE", 1.4)
	var mid: Vector2 = (door + (StreetErrands._bus_doors(bus)[1] as Vector2)) * 0.5
	print("ERRAND bus line %d at %s" % [int(t.bus), door.round()])
	return _eye(e, 1.65, Vector3(mid.x, _plan.height_at(mid) + 1.3, mid.y))


func _car(here: Vector2) -> String:
	var found: Array = []
	for c in _tree.get_nodes_in_group("vehicle"):
		var v := c as Vehicle
		if v == null or v.is_traffic() or v.has_meta("errand") or v.has_meta("driven") or BigVehicles.is_big(v.body_type) or v._damage != null:
			continue
		var wp: Vector3 = _ws.to_world(v.global_position)
		var d := Vector2(wp.x, wp.z).distance_to(here)
		if d < 150.0 and not StreetErrands._parked_road(_plan, v).is_empty():
			found.append([d, v])
	found.sort_custom(func(a, b): return a[0] < b[0])
	if found.is_empty():
		print("ERRAND car: no parked car near the camera")
		return ""
	var car: Vehicle = found[clampi(_pick(), 0, found.size() - 1)][1]
	var geo := StreetErrands._car_frame(car)
	var ring := StreetErrands._kerb_ring(_plan, geo)
	var p := _borrow(_walkers(geo.pos, 80.0), geo.door_out, ring)
	if p == null:
		return ""
	StreetErrands._start_car_in(p, _plan, car)
	p.errand.i = 2
	p._visual.rotation.y = float(geo.yaw) - PI * 0.5
	var ec := ErrandCar.on(car)
	await _ticks(2)
	ec.request_open()
	ec._open = _envf("ERRAND_DOOR", 0.95)
	ErrandProps.swing(ec.door, ec._open)
	await _ticks(3)
	# Held at the open door, one foot in: the rest of the errand waits.
	var at_door: Vector2 = (geo.door_out as Vector2).lerp(geo.door_in, _envf("ERRAND_IN", 0.3))
	p.position = Vector3(at_door.x, StreetErrands._floor(p, at_door), at_door.y)
	p.errand.steps = [{"do": "face", "yaw": float(geo.yaw) - PI * 0.5, "secs": 1e9, "road": true}]
	p.errand.i = 0
	for i in 10:
		await _tree.physics_frame
	var fwd := StreetErrands._along(car)
	var right := geo.right as Vector2
	var e: Vector2 = (geo.pos as Vector2) - fwd * _envf("ERRAND_BACK", 6.5) - right * _envf("ERRAND_SIDE", 3.6)
	var at: Vector2 = geo.door_out
	print("ERRAND car %s at %s" % [car.display_name(), (geo.pos as Vector2).round()])
	return _eye(e, 1.6, Vector3(at.x, _plan.height_at(at) + 1.0, at.y))


func _jay(here: Vector2) -> String:
	var pool := _walkers(here, 160.0)
	for p: Pedestrian in pool.duplicate():
		var at := Vector2(p.position.x, p.position.z)
		if not StreetErrands._start_jay(p, _plan, at):
			continue
		var steps: Array = p.errand.steps
		var look: Dictionary = steps[2]
		var cross: Dictionary = steps[3]
		var far: Vector2 = (cross.pts as Array)[0]
		var start: Vector2 = (steps[1].pts as Array)[0]
		var s := _envf("ERRAND_PROGRESS", 0.45)
		var mid := start.lerp(far, s)
		p.position = Vector3(mid.x, StreetErrands._floor(p, mid), mid.y)
		var d := far - start
		p._visual.rotation.y = atan2(-d.x, -d.y)
		cross.pace = p.run_speed * 0.8
		p.errand.i = 3
		p._speed = cross.pace
		# A car in the lane they are crossing, braking hard short of them.
		var axis := int(look.axis)
		var index := int(look.index)
		var along := float(look.along)
		var road := _plan.road_pos(axis, index)
		var lat := mid.x if axis == CityPlan.AXIS_X else mid.y
		var dir := 1
		for dd: int in [1, -1]:
			var off: float = _traffic._lane_offset(axis, index, dd)
			if signf(off) == signf(lat - road):
				dir = dd
		var width := _plan.road_width(axis, index)
		var lanes := 2 if width > _plan.street_width + 1.0 else 1
		var car := _traffic.place_car(axis, index, dir, lanes - 1, along - float(dir) * _envf("ERRAND_CAR", 9.0), 3.0, false)
		car.traffic.v = 3.0
		for i in 12:
			await _tree.physics_frame
		var side := Vector2(1.0, 0.0) if axis == CityPlan.AXIS_X else Vector2(0.0, 1.0)
		# ERRAND_EYE_LAT: metres out from the road's middle (default on the far pavement, past the
		# kerb); ERRAND_EYE_AHEAD: metres along the road ahead of the walker, the car's way.
		var e := mid + side * signf(road - lat) * _envf("ERRAND_EYE_LAT", width * 0.5 + 2.2) + (Vector2(0.0, 1.0) if axis == CityPlan.AXIS_X else Vector2(1.0, 0.0)) * float(dir) * _envf("ERRAND_EYE_AHEAD", 11.0)
		print("ERRAND jay at %s, car %s" % [mid.round(), car.display_name()])
		return _eye(e, 1.6, Vector3(mid.x, _plan.height_at(mid) + 0.9, mid.y))
	print("ERRAND jay: nobody near could jaywalk")
	return ""


func _shop(here: Vector2) -> String:
	var doors: Array = []
	for key in _scene.chunks:
		var chunk: Node = _scene.chunks[key]
		if chunk == null or int(chunk.get("level")) != CityChunk.Level.FULL:
			continue
		for d: Dictionary in StreetErrands._doors(chunk):
			doors.append([(d.p as Vector2).distance_to(here), d])
	doors.sort_custom(func(a, b): return a[0] < b[0])
	if doors.is_empty():
		print("ERRAND shop: no shop door near the camera")
		return ""
	var door: Dictionary = doors[clampi(_pick(), 0, doors.size() - 1)][1]
	var pool := _walkers(door.p, 80.0)
	var out: Vector2 = door.out
	var p := _borrow(pool, (door.p as Vector2) + out * 0.5, door.ring)
	# Held at the door, reaching for it.
	var at_door: Vector2 = (door.p as Vector2) + out * _envf("ERRAND_IN", 0.75)
	p.position = Vector3(at_door.x, StreetErrands._floor(p, at_door), at_door.y)
	p.errand = {"steps": [{"do": "face", "yaw": atan2(out.x, out.y), "secs": 1e9}], "i": 0}
	p._visual.rotation.y = atan2(out.x, out.y)
	# Somebody else just out of the same door, with a bag, on their way.
	var q := _borrow(pool, (door.p as Vector2) + out * 1.3, door.ring)
	if q:
		q.errand = {"steps": [{"do": "bag", "on": true}, {"do": "path", "pts": [door.front, (door.front as Vector2) + Vector2(-out.y, out.x) * 6.0]}], "i": 0}
		q._visual.rotation.y = atan2(-out.x - out.y * 0.6, -out.y + out.x * 0.6)
	for i in 10:
		await _tree.physics_frame
	var along := Vector2(-out.y, out.x)
	var e := (door.p as Vector2) + out * _envf("ERRAND_OUT", 5.5) + along * _envf("ERRAND_SIDE", 3.0)
	print("ERRAND shop door at %s" % (door.p as Vector2).round())
	return _eye(e, 1.65, Vector3(door.p.x, _plan.height_at(door.p) + 1.2, door.p.y))


func _deliver(here: Vector2) -> String:
	var doors: Array = []
	for key in _scene.chunks:
		var chunk: Node = _scene.chunks[key]
		if chunk == null or int(chunk.get("level")) != CityChunk.Level.FULL:
			continue
		for d: Dictionary in StreetErrands._doors(chunk):
			var dist := (d.p as Vector2).distance_to(here)
			if dist < 200.0:
				doors.append([dist, d])
	doors.sort_custom(func(a, b): return a[0] < b[0])
	var skip := _pick()
	for entry: Array in doors:
		var door: Dictionary = entry[1]
		var out: Vector2 = door.out
		var ring: Rect2 = door.ring
		# The road the door faces: the kerb out along `out`.
		var axis := CityPlan.AXIS_X if absf(out.x) > 0.5 else CityPlan.AXIS_Z
		var kerb_c: float = (ring.end.x if out.x > 0.0 else ring.position.x) if axis == CityPlan.AXIS_X else (ring.end.y if out.y > 0.0 else ring.position.y)
		var index := _plan._index_at(axis, kerb_c + signf(out.x + out.y) * 2.0)
		for i: int in [index - 1, index, index + 1, index + 2]:
			if absf(absf(_plan.road_pos(axis, i) - kerb_c) - _plan.road_width(axis, i) * 0.5) < 1.0:
				index = i
		var road := _plan.road_pos(axis, index)
		var width := _plan.road_width(axis, index)
		if absf(absf(road - kerb_c) - width * 0.5) > 1.0 or not _plan.road_open(axis, index, (door.p as Vector2).y if axis == CityPlan.AXIS_X else (door.p as Vector2).x):
			continue
		var s := signf(kerb_c - road)
		var dir := int(-s) if axis == CityPlan.AXIS_X else int(s)
		var lanes := 2 if width > _plan.street_width + 1.0 else 1
		var door_along: float = (door.p as Vector2).y if axis == CityPlan.AXIS_X else (door.p as Vector2).x
		# The truck's back a few metres past the door, the way the traffic goes.
		var along := door_along + float(dir) * 7.5
		var lat := road + s * CityPlan.parking_offset(width)
		var spot := Vector2(lat, along) if axis == CityPlan.AXIS_X else Vector2(along, lat)
		var lo := ring.position.y if axis == CityPlan.AXIS_X else ring.position.x
		var hi := ring.end.y if axis == CityPlan.AXIS_X else ring.end.x
		if along < lo + 8.0 or along > hi - 8.0:
			continue
		if skip > 0:
			skip -= 1
			continue
		# Clear the space of parked cars for it.
		for c in _tree.get_nodes_in_group("vehicle"):
			var v := c as Vehicle
			if v == null or v.is_traffic():
				continue
			var wp: Vector3 = _ws.to_world(v.global_position)
			if Vector2(wp.x, wp.z).distance_to(spot) < 9.0:
				v.queue_free()
		for c in _traffic.cars.duplicate():
			if is_instance_valid(c) and int(c.traffic.get("axis", -1)) == axis and int(c.traffic.get("index", -99999)) == index:
				_traffic.cars.erase(c)
				_traffic._retire(c)
		var truck := _traffic.place_car(axis, index, dir, lanes - 1, along, 0.0, false, BigVehicles.BOX_TRUCK)
		truck.traffic.shift = CityPlan.parking_offset(width) - absf(float(truck.traffic.lane))
		truck.traffic.v = 0.0
		truck.traffic.speed = 0.0
		truck.traffic.deliver = StreetErrands.DELIVER_TRUCK
		await _ticks(3)
		# Parked, without the walk-out: the driver is put straight on the pavement with the boxes.
		_traffic.cars.erase(truck)
		truck.traffic = {}
		truck.collision_mask = truck._mask()
		truck._add_real_wheels()
		truck.freeze = false
		truck._npc_driver = false
		truck._update_occupant(true)
		var ec := ErrandCar.on(truck)
		ec.mode = ErrandCar.Mode.KEEP
		await _ticks(2)
		var geo := StreetErrands._car_frame(truck)
		if geo.is_empty():
			print("ERRAND deliver: the truck is not in a kerb space")
			return ""
		var p := StreetErrands.spawn_driver(truck, StreetErrands.DELIVER_TRUCK)
		if p == null:
			p = _borrow(_walkers(spot, 80.0), geo.tail_kerb, ring)
			truck.set_meta("errand", true)
		if p == null:
			return ""
		await _ticks(2)
		# Straight to the hand truck on the pavement, loaded, part way to the door.
		var steps: Array = p.errand.steps
		var k := 0
		for j in steps.size():
			if String(steps[j].do) == "goto" and k == 0:
				k = j
		StreetErrands._set_truck(p, 3)
		p.errand.i = k + 1
		var front: Vector2 = door.front
		var tail: Vector2 = geo.tail_kerb
		var at := tail.lerp(front, _envf("ERRAND_PROGRESS", 0.5))
		_show_at(p, at)
		var d := front - tail
		p._visual.rotation.y = atan2(-d.x, -d.y)
		steps[k + 1] = {"do": "path", "pts": [front, (door.p as Vector2) + out * 0.95], "keep_truck": true}
		for i in 6:
			await _tree.physics_frame
		var e := at + out * _envf("ERRAND_OUT", 2.5) - (Vector2(0.0, 1.0) if axis == CityPlan.AXIS_X else Vector2(1.0, 0.0)) * float(dir) * _envf("ERRAND_BACK", 8.0)
		print("ERRAND deliver box truck at %s, door %s" % [spot.round(), (door.p as Vector2).round()])
		return _eye(e, 1.65, Vector3(at.x, _plan.height_at(at) + 1.0, at.y))
	print("ERRAND deliver: no shop door with kerb room near the camera")
	return ""


func _show_at(p: Pedestrian, at: Vector2) -> void:
	StreetErrands._hidden.erase(p.get_instance_id())
	p.visible = true
	p.collision_layer = 8
	p.position = Vector3(at.x, StreetErrands._floor(p, at), at.y)
