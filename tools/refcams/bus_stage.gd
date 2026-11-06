extends RefCounted
## A camera row's `"stage": "bus"` (cameras_w8.json's bus_stop_rain): a city bus at the stop nearest
## the row's `bus.at` (BigVehicles.block_stop()), its doors open and kneeling at the kerb with its
## destination sign lit, the lane behind it emptied, and the stop's queue filled with people
## (StreetErrands' own bus queue, so they stand where the game stands its riders and get the rain
## gear RainCrowd gives them). Loaded at run time by refcams_shot.gd (after the autoloads).
##
##   {"at": [x, z] TRUE world (the stop nearest it), "dir": 1 / -1 (only that direction's stops),
##    "pull": metres short of the stop the bus's nose stands (0: at the stop), "doors": false keeps
##    them shut, "queue": how many people wait (default 4, at most the stop's 6 slots),
##    "seed": the queue's first seed}
## Every field is optional. The log prints REFCAM bus lines.

static var hero_at := Vector3.INF
static var hero_yaw := 0.0
static var _made: Array = []
static var _bus: Node = null
static var _traffic: Node = null


static func stage(tree: SceneTree, scene: Node, _cam: Camera3D, place: Callable, row: Dictionary) -> void:
	var spec: Dictionary = row.get("bus", {}) if row.get("bus", null) is Dictionary else {}
	var plan: Variant = scene.get("plan")
	_traffic = scene.get_node_or_null("Traffic")
	if plan == null or _traffic == null:
		print("REFCAM bus: nothing to stage with")
		return
	var bv: GDScript = load("res://scripts/vehicles/big_vehicles.gd")
	var at := Vector2.ZERO
	if spec.get("at", null) is Array:
		at = Vector2(float(spec.at[0]), float(spec.at[1]))
	else:
		var e: Array = row.eye
		at = Vector2(float(e[0]), float(e[2]))
	var want_dir := int(spec.get("dir", 0))
	var bi: Vector2i = plan.block_index_at(at)
	var best: Array = []
	var best_d := INF
	for axis: int in [0, 1]:
		var base: int = bi.x if axis == 0 else bi.y
		var base_k: int = bi.y if axis == 0 else bi.x
		for di in range(-3, 4):
			for dk in range(-3, 4):
				for dir: int in [1, -1]:
					if want_dir != 0 and dir != want_dir:
						continue
					var index: int = base + di
					var stop: float = bv.call("block_stop", plan, axis, index, base_k + dk, dir)
					if is_nan(stop):
						continue
					var road: float = plan.road_pos(axis, index)
					var q := Vector2(road, stop) if axis == 0 else Vector2(stop, road)
					if q.distance_to(at) < best_d:
						best_d = q.distance_to(at)
						best = [axis, index, dir, stop]
	if best.is_empty():
		print("REFCAM bus: no stop near %s" % str(at))
		return
	var axis: int = best[0]
	var index: int = best[1]
	var dir: int = best[2]
	var stop: float = best[3]
	_traffic.set("staged", true)
	var cars: Array = _traffic.get("cars")
	for c in cars.duplicate():
		if is_instance_valid(c) and int(c.traffic.get("axis", -1)) == axis and int(c.traffic.get("index", -99999)) == index \
				and int(c.traffic.get("dir", 0)) == dir:
			cars.erase(c)
			_traffic.call("_retire", c)
	var width: float = plan.road_width(axis, index)
	var lanes := 2 if width > float(plan.street_width) + 1.0 else 1
	var nose := stop - float(dir) * float(spec.get("pull", 0.0))
	_bus = _traffic.call("place_car", axis, index, dir, lanes - 1, nose, 0.0, false, 9)
	if _bus == null:
		print("REFCAM bus: place_car refused")
		return
	var t: Dictionary = _bus.traffic
	t.v = 0.0
	t.speed = 0.0
	t.shift = float(bv.get("STOP_SHIFT"))
	t.dwell = 1.0
	t.dwell_need = 1e9
	_bus.set("traffic_speed", 0.0)
	var half: float = t.half
	var along := nose - float(dir) * half
	var lane: float = t.lane
	var lat: float = plan.road_pos(axis, index) + lane + signf(lane) * float(t.shift)
	var p2 := Vector2(lat, along) if axis == 0 else Vector2(along, lat)
	var h: float = _traffic.call("_relief", p2)
	var yaw_b: float = _traffic.call("_heading", axis, dir)
	(_bus as Node3D).global_transform = Transform3D(Basis(Vector3.UP, yaw_b),
		WorldState.to_local(Vector3(p2.x, 0.1 + float(_bus.call("road_lift")) + h, p2.y)))
	var fit := _bus.get_node_or_null("BusFittings")
	if fit and bool(spec.get("doors", true)):
		fit.call("set_doors", true)
	print("REFCAM bus: line %d on %s heading %d, nose at %.1f (stop %.1f), body at %s" % [int(bv.call("route_of", plan, axis, index)),
		plan.road_name(axis, index), dir, nose, stop, str(p2)])
	# The queue: the stop's own slots (StreetErrands), filled with new plain walkers of this chunk.
	var se: GDScript = load("res://scripts/npc/street_errands.gd")
	var stops: Array = se.get("_stops")
	var mine: Dictionary = {}
	for s: Dictionary in stops:
		if int(s.axis) == axis and int(s.index) == index and int(s.dir) == dir and absf(float(s.stop) - stop) < 0.5:
			mine = s
	if mine.is_empty():
		print("REFCAM bus: the stop's queue is not streamed in")
		return
	var chunk: Node = (mine.chunk as WeakRef).get_ref()
	var want := clampi(int(spec.get("queue", 4)), 0, 6)
	var seed0 := int(spec.get("seed", 730411))
	var queue: Array = []
	for k in want:
		var ped := Pedestrian.new()
		ped.setup(mine.ring, 4.0, seed0 + 7919 * k)
		ped.cross_chance = 0.0
		ped.life_chance = 0.0
		ped.life_spawn_chance = 0.0
		ped.jogger_share = Vector2.ZERO
		ped.dog_share = Vector2.ZERO
		ped.set_meta("no_trim", true)
		var slot: Vector2 = (mine.slots as Array)[k]
		ped.position = Vector3(slot.x, float(plan.height_at(slot)) + 0.15, slot.y)
		chunk.add_child(ped)
		_made.append(ped)
		queue.append(ped)
	for i in 4:
		await tree.process_frame
		place.call()
	var placed := 0
	for ped: Pedestrian in queue:
		var taken: Array = mine.taken
		for j in taken.size():
			if taken[j] != null and not is_instance_valid(taken[j]):
				taken[j] = null
		if se.call("_start_bus", ped, mine, true):
			placed += 1
		if ped.get("rain") != null:
			ped.rain.call("settle_now")
	for i in 6:
		await tree.process_frame
		place.call()
	print("REFCAM bus: %d of %d in the queue at %s, rain %.2f" % [placed, want, str(mine.kerb), RainCrowd.rain_now()])
	for ped: Pedestrian in queue:
		var r: Variant = ped.get("rain")
		print("REFCAM bus: queue %s near %s gear %s open %s" % [ped._model_path.get_file(), ped._life_near,
			r.gear if r else -1, r.open if r else -1.0])


static func unstage() -> void:
	for p in _made:
		if is_instance_valid(p):
			p.queue_free()
	_made.clear()
	if is_instance_valid(_bus) and _traffic:
		var cars: Array = _traffic.get("cars")
		cars.erase(_bus)
		_traffic.call("_retire", _bus)
	_bus = null
	if _traffic:
		_traffic.set("staged", false)
