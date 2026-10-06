extends RefCounted
## Multi-storey car parks (CarPark: where and the plan; CarParkBuild: the structure) for
## tests/smoke_test.gd. Loaded at run time (not named there), so it compiles after the autoloads.
## Checks: the car parks are pure (the same answer twice), each a site of whole lots of one
## block that no other feature claims, clear of the freeways; the plan's numbers are drivable (the
## ramp's grade, its vertical curves, the headroom, the entry's clearance, the loop fits); a car
## park's chunk builds the structure, its collision, the parked cars, the barriers and the far
## boxes; every deck and every ramp collides where the plan says; the kerb in front of the entry
## is kept clear; the switch turns them off; and a car driven by the player's own controls goes in
## past the barrier (which lifts for it) and up the ramps to the second deck.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _plan: CityPlan
var _ws: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_plan = city.plan
	_ws = _tree.root.get_node("/root/WorldState")
	var all := _pure()
	if all.is_empty():
		return
	_plan_numbers(all)
	_switch(all[0])
	var s: Dictionary = all[0]
	for c: Dictionary in all:
		if int(c.layout.decks) > int(s.layout.decks):
			s = c
	await _chunk(s)
	await _drive(s)


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


## Every car park round downtown, worked out twice.
func _pure() -> Array:
	var c := CarPark._cell_of(Vector2(2600.0, 0.0))
	var all: Array = []
	for dx in range(-5, 6):
		for dz in range(-5, 6):
			var s := CarPark.for_cell(_plan, c + Vector2i(dx, dz))
			if not s.is_empty():
				all.append(s)
	_check(all.size() >= 3, "the city has multi-storey car parks downtown and in midtown (%d in 121 cells)" % all.size())
	if all.is_empty():
		return all
	var first: Dictionary = all[0]
	CarPark._cache.clear()
	var again := CarPark.for_cell(_plan, first.cell)
	_check(not again.is_empty() and again.block == first.block and int(again.builder) == int(first.builder) and again.name == first.name
			and int(again.layout.decks) == int(first.layout.decks), "a car park is worked out the same way twice (%s)" % first.name)
	var bad := 0
	var why := ""
	for s: Dictionary in all:
		var bi: Vector2i = s.block
		var b := _plan.block(bi.x, bi.y)
		var inner := (b.rect as Rect2).grow(-_plan.sidewalk_width + 0.01)
		var site: Rect2 = s.site
		var claimed := 0
		for lot: Dictionary in _plan.lots(bi.x, bi.y):
			if CarPark.claims(_plan, bi.x, bi.y, lot):
				claimed += 1
				if not site.has_point(lot.center) or CarPark._taken(_plan, bi, lot, int(b.district)):
					bad += 1
					why = "a lot outside the site or another's"
		if claimed != (s.lots as Array).size() or claimed == 0:
			bad += 1
			why = "claims %d of %d lots" % [claimed, (s.lots as Array).size()]
		if not inner.encloses(site):
			bad += 1
			why = "the site leaves its block"
		if _plan.macro.freeway and _plan.macro.freeway.blocks_rect(site, 3.0):
			bad += 1
			why = "under a freeway"
		if not CarPark.DISTRICTS.has(int(b.district)) or not PoliceStation.station_on(_plan, bi.x, bi.y).is_empty():
			bad += 1
			why = "the wrong block"
	_check(bad == 0, "every car park is a site of whole lots in its block that nothing else claims, clear of the freeways (%s)" % why)
	return all


## The plan's numbers: a car can drive it.
func _plan_numbers(all: Array) -> void:
	var worst := 0.0
	var prev := 0.0
	var n := 400
	for i in range(1, n + 1):
		var x := CarPark.RAMP_LEN * float(i) / float(n)
		var y := CarPark.ramp_rise(x)
		worst = maxf(worst, (y - prev) / (CarPark.RAMP_LEN / float(n)))
		prev = y
	# The grade changes by at most half its value over the first metre (vertical curves).
	var first_m := CarPark.ramp_rise(1.0)
	_check(absf(CarPark.ramp_rise(0.0)) < 0.001 and absf(CarPark.ramp_rise(CarPark.RAMP_LEN) - CarPark.FLOOR) < 0.001 and worst < 0.165 and first_m < 0.04,
			"a ramp climbs one storey at most 16.5 %% with eased ends (%.1f %%, %.3f m in its first metre)" % [worst * 100.0, first_m])
	var clear := CarPark.FLOOR - CarPark.SLAB - CarPark.BEAM
	var under_ramp := CarPark.FLOOR - CarPark.SLAB - 0.03
	_check(clear >= 2.1 and CarPark.CLEARANCE <= clear and under_ramp > 2.6,
			"the decks are low but drivable (%.2f m under the beams, the bar at %.2f m)" % [clear, CarPark.CLEARANCE])
	var bad := 0
	for s: Dictionary in all:
		var lay: Dictionary = s.layout
		var ok := float(lay.r1) + 3.0 <= float(lay.m1) and float(lay.ls) <= float(lay.L) and float(lay.v0) + float(lay.ds) <= float(lay.D) \
				and int(lay.stalls) >= 8 and int(lay.decks) >= 2 and int(lay.decks) <= 6 \
				and float(lay.s1) - float(lay.s0) >= 6.5 and float(lay.m0) - float(lay.e0) >= 7.0
		var cols: Array = lay.cols
		for i in cols.size() - 1:
			if float(cols[i + 1]) - float(cols[i]) < 3.9 or float(cols[i + 1]) - float(cols[i]) > 12.2:
				ok = false
		if not ok:
			bad += 1
			printerr("CARPARK plan %s: %s" % [s.name, lay])
	_check(bad == 0, "every car park's plan fits its site: the ramp, the loop round it, the end zones, columns 4-12 m apart (%d bad)" % bad)


## CAR_PARKS=0: none anywhere.
func _switch(s: Dictionary) -> void:
	CarPark.enabled = false
	CarPark._cache.clear()
	var off := CarPark.for_cell(_plan, s.cell)
	var claims := false
	for lot: Dictionary in _plan.lots((s.block as Vector2i).x, (s.block as Vector2i).y):
		claims = claims or CarPark.claims(_plan, (s.block as Vector2i).x, (s.block as Vector2i).y, lot)
	CarPark.enabled = true
	CarPark._cache.clear()
	_check(off.is_empty() and not claims and not CarPark.for_cell(_plan, s.cell).is_empty(), "CAR_PARKS=0 turns the car parks off")


## The block's chunk at FULL: the structure, its collision, cars, barriers; at LOD: the far boxes.
func _chunk(s: Dictionary) -> void:
	var bi: Vector2i = s.block
	var chunk: CityChunk = _city._new_chunk(bi, CityChunk.Level.FULL)
	chunk.build()
	var node: Node3D = null
	for n in chunk.get_children():
		if n.is_in_group("car_park"):
			node = n
	_check(node != null and node.has_node("Structure") and node.has_node("Body") and node.has_node("GateIn") and node.has_node("GateOut"),
			"its block's chunk builds the car park, its collision and its two barriers")
	if node == null:
		chunk.queue_free()
		return
	var tris := 0
	var m := (node.get_node("Structure") as MeshInstance3D).mesh
	for si in m.get_surface_count():
		tris += m.surface_get_array_len(si) / 3
	var lay: Dictionary = s.layout
	_check(tris > 4000 and tris < 90000, "the structure is real geometry inside its budget (%d triangles, %d decks)" % [tris, int(lay.decks)])
	var cars := 0
	for c in node.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("Cars"):
			cars += (c as MultiMeshInstance3D).multimesh.instance_count
	var stalls := int(lay.stalls) * 2 * int(lay.modules) * (int(lay.decks) + 1)
	_check(cars > stalls / 4 and cars < stalls, "cars are parked on the decks (%d of %d stalls)" % [cars, stalls])
	_check(float(node.get_meta("build_us", 0)) < 250000.0, "it builds in one chunk step (%.1f ms)" % (float(node.get_meta("build_us", 0)) / 1000.0))
	# Collision: down through every deck at an aisle and at the ramp's middle.
	await _ticks(2)
	var space := node.get_world_3d().direct_space_state
	var xf := node.global_transform
	var aisle_v := CarPark.WALL + CarPark.STALL_D + CarPark.AISLE * 0.5
	var mid_u := (float(lay.m0) + float(lay.m1)) * 0.5
	var strip_v := (float(lay.s0) + float(lay.s1)) * 0.5
	var bad := 0
	var report := ""
	for k in int(lay.decks) + 1:
		var y := CarPark.FLOOR * float(k)
		var probes: Array[Vector3] = [Vector3(mid_u, y, aisle_v)]
		if k < int(lay.decks):
			probes.append(Vector3(float(lay.r0) + CarPark.RAMP_LEN * 0.5, y + CarPark.ramp_rise(CarPark.RAMP_LEN * 0.5), strip_v))
		for probe: Vector3 in probes:
			var from := xf * (probe + Vector3.UP * 1.2)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, xf * (probe - Vector3.UP * 1.0), 1))
			var got: float = (xf.affine_inverse() * (hit.position as Vector3)).y if not hit.is_empty() else -99.0
			if absf(got - probe.y) > 0.05:
				bad += 1
				report = "level %d at %s: hit %.2f" % [k, probe, got]
	_check(bad == 0, "every deck and every ramp collides where the plan puts it (%s)" % report)
	# The kerb in front of the entry is kept clear of parked cars; the next block's kerb is not.
	var kerb := CarPark.world_xz(s, float(lay.entry_u), -_plan.sidewalk_width - 1.2)
	var far := CarPark.world_xz(s, float(lay.entry_u) + 70.0, -_plan.sidewalk_width - 1.2)
	_check(CarPark.keeps_clear(_plan, kerb) and not CarPark.keeps_clear(_plan, far), "no car parks across its entry")
	chunk.queue_free()
	var lod := CityChunk.new()
	lod.plan = _plan
	lod.ix = bi.x
	lod.iz = bi.y
	lod.level = CityChunk.Level.LOD
	lod.style = _city.chunk_style()
	lod.capturing = true
	lod.build()
	var boxes: Dictionary = lod.captured.batch.get("lod_box", {"xforms": []})
	var high := 0.0
	for b: Transform3D in boxes.xforms:
		high = maxf(high, b.origin.y + b.basis.y.length() * 0.5)
	_check((boxes.xforms as Array).size() > 2 and high > float(lay.height) - 0.5 + CarPark.ground_y(_plan, s) - _plan.macro.relief_at((s.site as Rect2).get_center()) - 1.0,
			"the far city sees it at its height (%d boxes, top %.1f m)" % [(boxes.xforms as Array).size(), high])
	lod.free()
	await _ticks(2)


## The real thing: the player drives a car in off the street and up to the second deck.
func _drive(s: Dictionary) -> void:
	var player := _tree.get_first_node_in_group("player") as Player
	if player.is_driving():
		player.exit_vehicle()
	var home: Vector3 = _ws.to_world(player.global_position)
	var traffic := _city.get_node_or_null("Traffic") as TrafficManager
	if traffic:
		traffic.staged = true
		for c in traffic.cars.duplicate():
			if is_instance_valid(c):
				traffic._retire(c)
		traffic.cars.clear()
	var ap = load("res://tools/car_park/autopilot.gd").new()
	var path: PackedVector3Array = ap.local_path(_plan, s, _ws, 2)
	player.global_position = path[0] + Vector3.UP * 1.5
	player.velocity = Vector3.ZERO
	var node: Node3D = null
	for i in 300:
		_city.update_streaming(true)
		await _ticks(1)
		for n in _tree.get_nodes_in_group("car_park"):
			if n.is_inside_tree() and (n.get_meta("car_park") as Dictionary).get("cell") == s.cell:
				node = n
		if node and i > 4:
			break
	_check(node != null, "the streamed city builds the car park where the player is")
	if node == null:
		return
	# The car's own path, re-made from the city's offset now the streamer has re-centred.
	path = ap.local_path(_plan, s, _ws, 2)
	var car := Vehicle.new()
	car.setup(Vehicle.BodyType.SEDAN, Vehicle.PAINTS[0], Vehicle.Addon.NONE)
	_city.add_child(car)
	var d0 := path[1] - path[0]
	d0.y = 0.0
	car.global_transform = Transform3D(Basis.looking_at(d0.normalized(), Vector3.UP), path[0] + Vector3.UP * 0.6)
	for i in 20:
		car.hold_crash_watch(3)
		await _ticks(1)
	player.enter_vehicle(car)
	ap.setup(path)
	var gate := node.get_node("GateIn") as CarParkGate
	var lifted := 0.0
	var gy0: float = (_ws.to_local(Vector3(0.0, CarPark.ground_y(_plan, s), 0.0)) as Vector3).y
	var top := 0.0
	var t := 0.0
	while t < 150.0 and not ap.done:
		ap.step(car)
		await _ticks(1)
		t += 1.0 / float(Engine.physics_ticks_per_second)
		lifted = maxf(lifted, gate.openness())
		top = maxf(top, car.global_position.y - gy0)
	ap.release()
	if not ap.done:
		printerr("CARPARK stuck at %s heading %s: %s" % [_ws.to_world(car.global_position), -car.global_basis.z, ap.blocker(car)])
	_check(lifted > 0.9, "the entry's barrier lifts for the car (%.2f)" % lifted)
	_check(ap.done and absf(car.global_position.y - gy0 - CarPark.FLOOR * 2.0) < 0.6,
			"a car driven up off the street reaches the second deck (point %d of %d, %.2f m up, %.0f s)" % [ap.reached, path.size() - 1, car.global_position.y - gy0, t])
	player.exit_vehicle()
	car.queue_free()
	if traffic:
		traffic.staged = false
	player.global_position = _ws.to_local(home)
	player.velocity = Vector3.ZERO
	_city.update_streaming(true)
	await _ticks(5)
