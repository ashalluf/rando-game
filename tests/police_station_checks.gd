extends RefCounted
## Police stations (PoliceStation, and Police's dispatch out of their gates) for
## tests/smoke_test.gd. Loaded at run time (not named there), so it compiles after the autoloads.
## Checks: the stations are pure (the same answer twice, a site of whole lots inside its block,
## clear of the freeways and of the fire station's block, a layout that fits); the headquarters
## stands across the street from City Hall; a station's chunk builds the building, the gate, the
## parked cruisers and the collision, and the far city sees it; its gate slides open; a cruiser
## dispatched near it comes out of the gate, across the pavement and onto the lane, then drives
## the lanes like any other; a recalled one drives back in through the gate and is put away; the
## street's parked cars keep off the kerb in front of the gate.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _plan: CityPlan
var _ws: Node
var _police: Police


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_plan = city.plan
	_ws = _tree.root.get_node("/root/WorldState")
	_police = city.get_node_or_null("Police") as Police
	_check(_police != null, "the city has a Police node for the stations")
	if _police == null:
		return
	var found := _pure()
	if found.is_empty():
		return
	await _chunk(found)
	await _dispatch(found)


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


## The stations round the spawn, worked out twice; the HQ by City Hall.
func _pure() -> Dictionary:
	var c := PoliceStation._cell_of(Vector2(1500.0, 0.0))
	var all: Array[Dictionary] = []
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			var s := PoliceStation.for_cell(_plan, c + Vector2i(dx, dz))
			if not s.is_empty():
				all.append(s)
	_check(all.size() >= 3, "the city has police stations (%d in 49 cells)" % all.size())
	if all.is_empty():
		return {}
	var found: Dictionary = all[0]
	PoliceStation._cache.clear()
	var again := PoliceStation.for_cell(_plan, found.cell)
	_check(not again.is_empty() and again.block == found.block and int(again.builder) == int(found.builder) and again.name == found.name,
			"a station is worked out the same way twice (%s)" % found.name)
	var bad := 0
	for s in all:
		var b := _plan.block(s.block.x, s.block.y)
		var inner := (b.rect as Rect2).grow(-_plan.sidewalk_width + 0.01)
		var site: Rect2 = s.site
		var claimed := 0
		for lot: Dictionary in _plan.lots(s.block.x, s.block.y):
			if PoliceStation.claims(_plan, s.block.x, s.block.y, lot):
				claimed += 1
				if not site.has_point(lot.center):
					bad += 1
		var fs := FireStation.for_cell(_plan, FireStation._cell_of((b.rect as Rect2).get_center()))
		var lay: Dictionary = s.layout
		if claimed != (s.lots as Array).size() or claimed == 0 or not inner.encloses(site) \
				or (not fs.is_empty() and fs.block == s.block) \
				or (_plan.macro.freeway and _plan.macro.freeway.blocks_rect(site, 3.0)) \
				or float(lay.ub1) >= float(lay.drive_u0) or float(lay.pv0) + STALL_ROW >= float(lay.pv1):
			bad += 1
	_check(bad == 0, "every station's site is its own lots inside its block, off the fire station's and the freeway, with a layout that fits (%d bad of %d)" % [bad, all.size()])
	var hq := PoliceStation.hq(_plan)
	if not hq.is_empty():
		var hall := CivicSites.anchor("ziggurat_hall")
		var d := (hq.site as Rect2).get_center().distance_to(hall)
		_check(d < 320.0 and int(hq.storeys) == PoliceStation.HQ_STOREYS and (hq.lots as Array).size() == _plan.lots(hq.block.x, hq.block.y).size(),
				"the headquarters takes the whole block across from City Hall (%.0f m, %d storeys)" % [d, int(hq.storeys)])
	else:
		_check(false, "the headquarters has a block across from City Hall")
	var near := PoliceStation.nearest(_plan, (found.front as Vector2) + Vector2(60.0, 40.0), 500.0)
	var out := PoliceStation.exit_lane(_plan, found, (found.front as Vector2) + Vector2(300.0, 0.0))
	_check(not near.is_empty() and not out.is_empty(), "a crime near it finds it, and a way out onto the street")
	_check(PoliceStation.keeps_clear(_plan, found.front) and not PoliceStation.keeps_clear(_plan, (found.front as Vector2) + Vector2(30.0, 30.0)),
			"the kerb in front of its gate is kept clear of parked cars")
	return found


const STALL_ROW := PoliceStation.STALL_D


func _chunk(found: Dictionary) -> void:
	var chunk: CityChunk = _city._new_chunk(found.block, CityChunk.Level.FULL)
	chunk.build()
	var st: Node3D = null
	for n in chunk.get_children():
		if n.is_in_group("police_station"):
			st = n
	var cars := 0
	if st and st.has_node("Cruisers"):
		cars = (st.get_node("Cruisers") as MultiMeshInstance3D).multimesh.instance_count
	_check(st != null and st.has_node("Building") and st.has_node("Body") and st.has_node("Gate") and st.has_node("Gate/GateBody"),
			"its block's chunk builds the station, its gate and its collision")
	_check(cars >= 3 and cars <= PoliceStation.HQ_MAX_CARS, "cruisers are parked in its car park (%d)" % cars)
	var tris := 0
	if st:
		var m := (st.get_node("Building") as MeshInstance3D).mesh
		for si in m.get_surface_count():
			tris += m.surface_get_array_len(si) / 3
	_check(tris > 2000 and tris < 60000, "the station's own mesh is real geometry inside its budget (%d triangles)" % tris)
	if st:
		PoliceStation.open_gate(_tree, found, 1.0)
		await _ticks(int(PoliceStation.GATE_TIME * 60.0) + 12)
		var open := PoliceStation.gate_open_amount(_tree, found)
		_check(open > 0.9, "its gate slides open for a cruiser (%.2f)" % open)
	var lod := CityChunk.new()
	lod.plan = _plan
	lod.ix = found.block.x
	lod.iz = found.block.y
	lod.level = CityChunk.Level.LOD
	lod.style = _city.chunk_style()
	lod.capturing = true
	lod.build()
	var boxes: Dictionary = lod.captured.batch.get("lod_box", {"xforms": []})
	_check((boxes.xforms as Array).size() > 0, "the far city sees it too")
	chunk.queue_free()
	lod.free()
	await _ticks(2)


## A two-star crime near the station: a cruiser comes out of its gate onto the lane, and once the
## stars are gone one drives back in.
func _dispatch(found: Dictionary) -> void:
	var player := _tree.get_first_node_in_group("player") as Player
	if player.is_driving():
		player.exit_vehicle()
	var home: Vector3 = _ws.to_world(player.global_position)
	var front: Vector2 = found.front
	var spot := front + Vector2(90.0, 70.0)
	player.global_position = _ws.to_local(Vector3(spot.x, _plan.height_at(spot) + 1.5, spot.y))
	player.velocity = Vector3.ZERO
	_city.update_streaming(true)
	await _ticks(10)
	_police.clear()
	_police.enabled = true
	_police.set_wanted(2)
	_police.last_seen = _ws.to_world(player.global_position)
	# No dispatch of its own while this one is watched.
	_police._dispatch_t = 1e9
	var ok: bool = _police._dispatch_from_station(found, spot)
	var car: PoliceCar = _police.cruisers.back() if not _police.cruisers.is_empty() else null
	_check(ok and car != null and car.scripted and car.station.get("key") == found.key, "a cruiser sent near the station starts in its car park")
	if car == null:
		_police.enabled = false
		return
	var start := _ws.to_world(car.global_position) as Vector3
	var site: Rect2 = found.site
	_check(site.grow(0.5).has_point(Vector2(start.x, start.z)), "it starts inside the station's fence")
	var gate_max := 0.0
	var left_at := -1
	for i in 60 * 30:
		await _tree.physics_frame
		gate_max = maxf(gate_max, PoliceStation.gate_open_amount(_tree, found))
		if not car.scripted:
			left_at = i
			break
	var wp := _ws.to_world(car.global_position) as Vector3
	var t: Dictionary = car.traffic
	var axis := int(found.road[0])
	var lane_line := _plan.road_pos(axis, int(found.road[1])) + float(t.get("lane", 0.0))
	var lat := (wp.x if axis == CityPlan.AXIS_X else wp.z) - lane_line
	_check(left_at > 0 and gate_max > 0.5 and car.is_traffic() and car.mode == PoliceCar.Mode.DISPATCH and absf(lat) < 0.6,
			"the gate opens and it drives out onto its lane (%.1f s, gate %.2f, %.2f m off the lane)" % [left_at / 60.0, gate_max, lat])
	var p0 := wp
	await _ticks(60)
	var moved := (_ws.to_world(car.global_position) as Vector3).distance_to(p0)
	_check(moved > 4.0 and car.siren_running(), "then drives the lanes with its siren going (%.1f m in a second)" % moved)
	# The stars go; the cruiser is sent home: it routes to the gate and drives in.
	_police.set_wanted(0)
	car.mode = PoliceCar.Mode.LEAVING
	car.goal = _police._home_for(car)
	_check(car.station.get("key") == found.key, "a recalled cruiser heads for the nearest station")
	# Put it on the station's road, short of the gate, heading for it.
	var dir := 1 if float(t.dir) > 0.0 else -1
	var road_along := front.y if axis == CityPlan.AXIS_X else front.x
	var start_along := road_along - float(dir) * 40.0
	car.begin_dispatch(_plan, axis, int(found.road[1]), dir, 8.0)
	car.mode = PoliceCar.Mode.LEAVING
	car.goal = front
	var lane: float = car.traffic.lane
	var p2 := Vector2(_plan.road_pos(axis, int(found.road[1])) + lane, start_along) if axis == CityPlan.AXIS_X else Vector2(start_along, _plan.road_pos(axis, int(found.road[1])) + lane)
	car._place(Vector3(p2.x, _plan.height_at(p2) + CityChunk.ROAD_TOP + car.road_lift(), p2.y), car._heading(axis, dir), 0.0)
	var entered := false
	var gone := false
	for i in 60 * 30:
		await _tree.physics_frame
		car.unseen_time = 0.0
		if is_instance_valid(car) and car.scripted:
			entered = true
		if not _police.cruisers.has(car):
			gone = true
			break
	_check(entered and gone, "it turns in through the gate and is put away (entered %s, gone %s)" % [entered, gone])
	_police.clear()
	_police.enabled = false
	player.global_position = _ws.to_local(home)
	player.velocity = Vector3.ZERO
	_city.update_streaming(true)
	await _ticks(5)
