extends RefCounted
## The coast highway under the bluffs (CoastHighway, CoastHighwayBuild), for tests/smoke_test.gd.
## Loaded at run time, not named there, so it compiles after the autoloads.
##
## Geography: north of the beach town where the mountains meet the sea, never on a city block,
## a freeway, a landmark or the replica. The land: the sand low under the seawall, the bench flat
## across all four lanes at ROAD_Y, the coast highway's own profile on it, a bluff behind; nothing
## outside the corridor moves. The plan: houses in a row on the sand side of the wall, not
## overlapping, decks clear of the water; parked cars on the shoulders and never across a garage;
## surfers' cars among them; towers and stairs. A FULL chunk: the road, paint, houses, one
## collision body you stand on at the asphalt's height, the cars; LOD: the road and no collision;
## the far city: the houses as boxes and no nodes.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var macro: MacroMap = plan.macro
	var ch: CoastHighway = macro.coast_highway if macro else null
	_t._check(ch != null, "the coast highway is planned on this seed")
	if ch == null:
		return
	_geography(ch, plan, macro)
	_land(ch, macro)
	_plan(ch)
	_t._check(BeachLife.kept_off(plan, (ch.z_north + ch.z_full) * 0.5) and not BeachLife.kept_off(plan, (ch.z_north + ch.z_full) * 0.5, true),
		"the beach under the houses has people but no bike path or court")
	await _chunks(city, plan, ch)


func _geography(ch: CoastHighway, plan: CityPlan, macro: MacroMap) -> void:
	var pch_z := INF
	for r: Dictionary in macro.hill_roads.roads:
		if r.name == "Pacific Coast Highway":
			pch_z = (r.points as PackedVector2Array)[0].y
	_t._check(absf(pch_z - ch.z_north) < 0.5, "the stretch starts where the coast highway does (z %.0f, road %.0f)" % [ch.z_north, pch_z])
	# North of the beach town: the beach town's first block and the pier are south of it.
	var pier_z := INF
	for lm: Dictionary in Landmarks.all():
		if lm.id == "pier":
			pier_z = (lm.anchor as Vector2).y
	_t._check(ch.z_south < pier_z - 300.0, "the stretch ends north of the pier (z %.0f, pier %.0f)" % [ch.z_south, pier_z])
	var city_hits := 0
	var fw_hits := 0
	var lm_hits := 0
	var z := ch.z_north
	while z < ch.z_full:
		for d: float in [5.0, CoastHighway.WALL - 6.0, CoastHighway.CENTRE, CoastHighway.TOE]:
			var p := ch.at(d, z)
			if macro.zone_at(p) == MacroMap.Zone.CITY:
				city_hits += 1
			if macro.freeway.blocks(p, 0.0):
				fw_hits += 1
			if Landmarks.covers(plan, p, 0.0):
				lm_hits += 1
		z += 10.0
	_t._check(city_hits == 0 and fw_hits == 0 and lm_hits == 0,
		"the stretch cuts no city block, freeway or landmark (city %d, freeway %d, landmark %d)" % [city_hits, fw_hits, lm_hits])
	if macro.replica:
		var cr: Vector2 = macro.replica.coast_range()
		_t._check(ch.z_south < cr.x - 500.0, "the stretch is far from the replica's coast")


func _land(ch: CoastHighway, macro: MacroMap) -> void:
	var worst_bench := 0.0 # against the bed (the profile on the bench)
	var worst_sand := 0.0
	var low_bluff := 0
	var n := 0
	var z := ch.z_north + 20.0
	while z < ch.z_full - 10.0:
		var y := ch.bed_y(z)
		for d: float in [CoastHighway.ROAD_IN + 0.5, CoastHighway.CENTRE, CoastHighway.ROAD_OUT - 0.5]:
			worst_bench = maxf(worst_bench, absf(macro.height_at(ch.at(d, z)) - y))
		worst_sand = maxf(worst_sand, macro.height_at(ch.at(CoastHighway.WALL - 4.0, z)))
		if macro.height_at(ch.at(CoastHighway.TOE + 25.0, z)) < y + 8.0:
			low_bluff += 1
		n += 1
		z += 16.0
	_t._check(worst_bench < 0.35 and worst_sand < 0.4, "the bench is flat at %.1f m across the four lanes (worst %.2f) and the sand low under the wall (highest %.2f)" % [CoastHighway.ROAD_Y, worst_bench, worst_sand])
	_t._check(low_bluff <= n / 5, "a bluff stands behind the road (%d of %d samples low)" % [low_bluff, n])
	var worst_pch := 0.0
	for r: Dictionary in macro.hill_roads.roads:
		if r.name != "Pacific Coast Highway":
			continue
		var pts: PackedVector2Array = r.points
		for i in pts.size():
			if pts[i].y > ch.z_north + 30.0 and pts[i].y < ch.z_full - 80.0:
				worst_pch = maxf(worst_pch, absf(float(r.heights[i]) - ch.bench_y(pts[i].y)))
	_t._check(worst_pch < 0.3, "the coast highway's profile lies on the bench over the full stretch (worst %.2f m)" % worst_pch)
	# Nothing outside the corridor moves: the same heights with the stretch taken away.
	var keep := macro.coast_highway
	var probes: Array[Vector2] = []
	for k in 40:
		var zz := lerpf(ch.z_north - 400.0, ch.z_south + 400.0, float(k) / 39.0)
		probes.append(Vector2(macro.coast_x(zz) + CoastHighway.REACH + CoastHighway.REACH_FADE + 5.0 + float(k % 4) * 60.0, zz))
		probes.append(Vector2(macro.coast_x(zz) + 40.0, ch.z_south + 5.0 + float(k) * 9.0))
	var with := PackedFloat32Array()
	for p in probes:
		with.append(macro.raw_height_at(p) + macro.relief_at(p))
	macro.coast_highway = null
	var moved := 0
	for i in probes.size():
		if absf(macro.raw_height_at(probes[i]) + macro.relief_at(probes[i]) - with[i]) > 0.001:
			moved += 1
	macro.coast_highway = keep
	_t._check(moved == 0, "the land outside the stretch's corridor does not move (%d of %d probes)" % [moved, probes.size()])


func _plan(ch: CoastHighway) -> void:
	_t._check(ch.houses.size() >= 8 and ch.towers.size() >= 1 and ch.stairs.size() >= 1,
		"beach houses, lifeguard towers and beach stairs are planned (%d, %d, %d)" % [ch.houses.size(), ch.towers.size(), ch.stairs.size()])
	var overlap := 0
	var wet := 0
	for i in ch.houses.size():
		var hs: Dictionary = ch.houses[i]
		if i > 0 and float(hs.z0) < float(ch.houses[i - 1].z1) - 0.01:
			overlap += 1
		var reach := CoastHighway.WALL - float(hs.depth) - float(hs.deck)
		if reach < 6.0:
			wet += 1
	_t._check(overlap == 0 and wet == 0, "the houses stand in a row without overlapping and their decks stay over dry sand (overlap %d, wet %d)" % [overlap, wet])
	var surf := 0
	var bad := 0
	for st: Dictionary in ch.stalls:
		surf += 1 if st.surf else 0
		var hs := ch.house_at(float(st.z), 1.5)
		if float(st.side) < 0.0 and not hs.is_empty() and bool(hs.garage) and absf(float(st.z) - ch.garage_z(hs)) < 4.0:
			bad += 1
	_t._check(ch.stalls.size() >= 20 and surf >= 4 and bad == 0,
		"cars park along both shoulders (%d stalls, %d surfers'), never across a garage door (%d)" % [ch.stalls.size(), surf, bad])


func _chunks(city: Node3D, plan: CityPlan, ch: CoastHighway) -> void:
	# The chunk with the most houses.
	var counts := {}
	for hs: Dictionary in ch.houses:
		var k := plan.chunk_index_at(ch.at(CoastHighway.WALL - float(hs.depth) * 0.5, float(hs.zc)))
		counts[k] = int(counts.get(k, 0)) + 1
	var best := Vector2i.ZERO
	var most := -1
	for k: Vector2i in counts:
		if int(counts[k]) > most:
			most = int(counts[k])
			best = k
	var chunk: CityChunk = city._new_chunk(best, CityChunk.Level.FULL)
	chunk.build()
	if OS.get_environment("COAST_DEBUG") != "":
		var names := []
		for ch2 in chunk.get_children():
			names.append(str(ch2.name))
		printerr("COAST chunk ", best, " zone ", chunk.zone, " rect ", chunk.owned_rect(), " children ", names)
		printerr("COAST batches ", chunk._batch.data().keys())
		for k2 in [Vector2i(best.x - 1, best.y), Vector2i(best.x + 1, best.y), Vector2i(best.x, best.y - 1), Vector2i(best.x, best.y + 1)]:
			printerr("COAST neighbour ", k2, " rect ", plan.owned_rect(k2.x, k2.y), " zone ", plan.zone_at((plan.block(k2.x, k2.y).rect as Rect2).get_center()), " block rect ", plan.block(k2.x, k2.y).rect)
	var road := chunk.get_node_or_null("Coast_road") as MeshInstance3D
	var glass := chunk.get_node_or_null("Coast_glass") as MeshInstance3D
	var body := chunk.get_node_or_null("CoastBody") as StaticBody3D
	var walls := chunk.get_node_or_null("Coast_h_wall") != null or chunk.get_node_or_null("Coast_h_siding") != null
	var drawn_pch := 0
	for seg: Dictionary in chunk._hill_segments():
		var mid: Vector2 = (seg.a as Vector2).lerp(seg.b, 0.5)
		if absf(mid.x - ch.macro.coast_x(mid.y) - CoastHighway.CENTRE) < 2.0 and mid.y > ch.z_north and mid.y < ch.z_south and seg.get("draw", true):
			drawn_pch += 1
	_t._check(road != null and glass != null and walls and body != null and body.collision_mask == 0 and drawn_pch == 0,
		"the coast highway's chunk %s: four lanes, %d houses in walls and glass, one collision body, the hill strip not drawn (road %s glass %s walls %s body %s strip %d)" % [best, most, road != null, glass != null, walls, body != null, drawn_pch])
	var cars := 0
	var boards := 0
	for car in chunk._cars:
		if is_instance_valid(car):
			cars += 1
			if (car as Node).get_node_or_null("SurfBoards") != null:
				boards += 1
	var stalls := 0
	var r := chunk.owned_rect()
	for st: Dictionary in ch.stalls:
		if r.has_point(ch.at(CoastHighway.CENTRE, float(st.z))):
			stalls += 1
	_t._check(stalls == 0 or cars > 0, "cars stand parked on the chunk's shoulders (%d of %d stalls, %d with boards)" % [cars, stalls, boards])
	# You stand on the asphalt: a ray down onto the road finds the road's own height.
	await _t.get_tree().physics_frame
	await _t.get_tree().physics_frame
	var hit_ok := true
	var tested := 0
	var space := (chunk as Node3D).get_world_3d().direct_space_state
	var zz := r.position.y + 6.0
	while zz < r.end.y - 6.0 and tested < 6:
		var p := ch.at(CoastHighway.CENTRE + CoastHighway.LANE, zz)
		if r.has_point(p) and zz > ch.z_north + CoastHighway.CLOSURE + 5.0 and zz < ch.z_full:
			var from := WorldState.to_local(Vector3(p.x, ch.road_y(zz) + 5.0, p.y))
			var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 12.0, 1)
			var hit := space.intersect_ray(q)
			tested += 1
			if hit.is_empty() or absf(WorldState.to_world(hit.position).y - ch.road_y(zz)) > 0.15:
				hit_ok = false
		zz += 17.0
	_t._check(tested == 0 or hit_ok, "the road's collision is at the asphalt's height (%d rays)" % tested)
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	var lod: CityChunk = city._new_chunk(best, CityChunk.Level.LOD)
	lod.build()
	var lod_ok := lod.get_node_or_null("Coast_road") != null and lod.get_node_or_null("CoastBody") == null and lod._cars.is_empty()
	lod.get_parent().remove_child(lod)
	lod.free()
	var cap := CityChunk.new()
	cap.plan = plan
	cap.ix = best.x
	cap.iz = best.y
	cap.level = CityChunk.Level.LOD
	cap.capturing = true
	cap.style = city.chunk_style()
	cap.build()
	var lb: Dictionary = (cap.captured.batch as Dictionary).get("lod_box", {})
	var boxes := (lb.get("xforms", []) as Array).size()
	var nodes := cap.get_child_count()
	cap.free()
	_t._check(lod_ok and nodes == 0, "LOD builds the road with no collision or cars; the far city records the houses and no nodes (%d records)" % boxes)
