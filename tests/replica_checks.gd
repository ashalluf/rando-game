extends RefCounted
## Replica area checks for tests/smoke_test.gd (the Esplanade, ReplicaAreas). Loaded at run time,
## so it compiles after the autoloads and can name CityChunk, ReplicaBuilder and ReplicaTraffic.
## All maths on the plan's own data except one replica chunk built at full detail and a car
## driven round the roundabout by hand - a couple of seconds in all.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var macro: MacroMap = plan.macro
	var rep: ReplicaAreas = macro.replica if macro else null
	t._check(rep != null, "the map carries the Esplanade replica")
	if rep == null:
		return
	_road(rep)
	_coast(rep, macro)
	_lots(rep, plan)
	await _chunk(rep, plan, city)
	await _traffic(rep, city)


## The road: continuous, the lengths the data says, the heights the photos need.
func _road(rep: ReplicaAreas) -> void:
	var worst_gap := 0.0
	var worst_turn := 0.0
	for i in rep.pts.size() - 1:
		worst_gap = maxf(worst_gap, rep.pts[i].distance_to(rep.pts[i + 1]))
		var near_ring := false
		for ra in rep.roundabouts:
			if rep.pts[i].distance_to(ra.center) < float(ra.r_out) + 2.0:
				near_ring = true
		if not near_ring:
			worst_turn = maxf(worst_turn, rad_to_deg(absf(rep.dirs[i].angle_to(rep.dirs[i + 1]))))
	_t._check(worst_gap <= ReplicaAreas.STEP * 1.05 and worst_turn < 4.0,
		"the Esplanade route is continuous (largest step %.2f m, sharpest bend %.1f deg a sample)" % [worst_gap, worst_turn])
	# 1:1 where it counts: the straight Esplanade itself is 1880 m, and the whole run to the top
	# of the hill road is what the legs add up to.
	var legs: Array = rep.data.legs
	var south_start := -1.0
	for i in rep.pts.size():
		if rep.leg[i] == 1:
			south_start = rep.run[i]
			break
	_t._check(absf(south_start - float(legs[0].length)) < ReplicaAreas.STEP + 0.5,
		"the straight Esplanade is %.0f m long (data %.0f)" % [south_start, float(legs[0].length)])
	_t._check(rep.length > 4000.0 and rep.length < 5200.0 and rep.s_city_end > 2500.0 and rep.s_city_end < rep.length,
		"the route runs %.0f m, %.0f of it town" % [rep.length, rep.s_city_end])
	var at := rep.at_s(1850.0)
	_t._check(float(at[2]) > 9.0 and float(at[2]) < 18.0, "the Esplanade rides the bluff top (%.1f m at 1718 Esplanade)" % float(at[2]))
	var grade := 0.0
	for i in rep.pts.size() - 1:
		grade = maxf(grade, absf(rep.top[i + 1] - rep.top[i]) / maxf(rep.run[i + 1] - rep.run[i], 0.01))
	_t._check(grade <= float(rep.data.hill_grade) + 0.01, "no grade on the route steeper than %.0f %% (%.1f %%)" % [float(rep.data.hill_grade) * 100.0, grade * 100.0])
	_t._check(rep.roundabouts.size() == 1 and absf(float(rep.roundabouts[0].s) - 2111.0) < 25.0,
		"the Avenue I roundabout is where the curve ends (%s)" % [str(rep.roundabouts[0].s) if not rep.roundabouts.is_empty() else "none"])
	# The hill part is carved into the terrain, not floating over it or buried in it.
	var worst := 0.0
	var i := rep._index_of_s(rep.s_city_end + 40.0)
	while i < rep.pts.size():
		var g := rep.macro.height_at(rep.pts[i])
		worst = maxf(worst, absf(g - rep.top[i]))
		i += 6
	_t._check(worst < 1.2, "the hill road sits in its cut (worst %.2f m from the carved ground)" % worst)


## The coast: bluff over the sand, the sand over the sea, the headland where the photo has it.
func _coast(rep: ReplicaAreas, macro: MacroMap) -> void:
	var low := INF
	var sand_ok := true
	for s in [300.0, 800.0, 1300.0, 1800.0]:
		var at := rep.at_s(s)
		var sd: Dictionary = at[3]
		var l := ReplicaAreas.left_of(at[1])
		var edge: Vector2 = (at[0] as Vector2) + l * float(sd.edge)
		var beach: Vector2 = (at[0] as Vector2) + l * lerpf(float(sd.toe), float(sd.water), 0.4)
		low = minf(low, macro.height_at(edge) - macro.height_at(beach))
		if macro.zone_at(beach) != MacroMap.Zone.BEACH:
			sand_ok = false
	_t._check(low > 8.0, "the bluff stands over the sand (at least %.1f m)" % low)
	_t._check(sand_ok, "the foot of the bluff is beach")
	# The coast is one ordered line from Redondo to Malaga Cove, where the shore turns west along
	# the peninsula's north face (and stops being a function of z): no reversal, no jump.
	var worst := 0.0
	var prev := macro.coast_x(1200.0)
	var z := 1250.0
	var z_end: float = rep.coast_range().y
	while z <= z_end:
		var x := macro.coast_x(z)
		worst = maxf(worst, absf(x - prev))
		prev = x
		z += 50.0
	_t._check(worst < 60.0, "the coast runs continuously from Redondo to Malaga Cove (worst %.0f m per 50 m, to z %.0f)" % [worst, z_end])
	var pv := Vector2(-100.0, 5700.0)
	_t._check(macro.zone_at(pv) == MacroMap.Zone.HILLS and macro.height_at(pv) > 150.0, "the Palos Verdes hills stand south of the bay (%.0f m)" % macro.height_at(pv))
	var west := Vector2(macro.headland_west_x(5200.0) - 60.0, 5200.0)
	_t._check(macro.zone_at(west) == MacroMap.Zone.OCEAN, "the sea runs round the headland's west face")
	for id: String in ["redondo_pier", "manhattan_pier"]:
		var a: Vector2 = _t._landmark_anchor(id)
		_t._check(absf(macro.coast_x(a.y) - a.x) < 160.0, "%s still meets the coast (%.0f m off it)" % [id, absf(macro.coast_x(a.y) - a.x)])


## Nothing overlaps: the frontage houses clear each other and the road, and no seeded lot stands
## in the corridor.
func _lots(rep: ReplicaAreas, plan: CityPlan) -> void:
	var lots := rep.frontage_lots(plan)
	_t._check(lots.size() > 100, "the Esplanade frontage is lined with houses (%d lots)" % lots.size())
	var polys: Array[PackedVector2Array] = []
	var on_road := 0
	for lot in lots:
		var f := ReplicaHouses.frame(lot)
		var fr: Vector2 = (lot.front as Vector2).normalized()
		var al := Vector2(-fr.y, fr.x)
		var c: Vector2 = lot.center
		var poly := PackedVector2Array()
		for q: Vector2 in [Vector2(f.u0, f.v0), Vector2(f.u1, f.v0), Vector2(f.u1, f.v1), Vector2(f.u0, f.v1)]:
			poly.append(c + al * q.x + fr * q.y)
		polys.append(poly)
		for p in poly:
			var hit := rep.nearest(p, 200.0)
			if not hit.is_empty():
				var sd: Dictionary = rep.sec[int(hit.i)]
				var o: float = hit.o
				if o > float(sd.kerb_w) - 0.5 and o < float(sd.kerb_e) + 0.5:
					on_road += 1
	var overlaps := 0
	for a in polys.size():
		for b in range(a + 1, polys.size()):
			if polys[a][0].distance_to(polys[b][0]) > 80.0:
				continue
			for q in Geometry2D.intersect_polygons(polys[a], polys[b]):
				if absf(_area(q)) > 0.5:
					overlaps += 1
	_t._check(overlaps == 0 and on_road == 0, "frontage houses clear each other and the road (%d overlaps, %d corners on the road)" % [overlaps, on_road])
	# Seeded lots on the blocks round the replica keep out of the corridor.
	var bad := 0
	var checked := 0
	for s in [400.0, 1200.0, 1850.0, 2300.0]:
		var k := plan.block_index_at(rep.at_s(s)[0])
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				var kk := Vector2i(k.x + dx, k.y + dz)
				if rep.block_role(plan, kk.x, kk.y) != 0:
					continue
				for lot in plan.lots(kk.x, kk.y):
					checked += 1
					var half: Vector2 = (lot.size as Vector2) * 0.5
					for cq: Vector2 in [Vector2.ZERO, Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
						if rep.blocks_grid((lot.center as Vector2) + cq * half, 0.0):
							bad += 1
							break
	_t._check(checked > 0 and bad == 0, "no seeded building stands in the replica corridor (%d lots checked, %d in it)" % [checked, bad])


static func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		a += p[i].cross(p[(i + 1) % p.size()])
	return a * 0.5


## One replica chunk at full detail: it builds the replica (road, houses, lamps, collision) and
## nothing of the seeded block.
func _chunk(rep: ReplicaAreas, plan: CityPlan, city: Node3D) -> void:
	var at := rep.at_s(1850.0)
	var p: Vector2 = (at[0] as Vector2) + ReplicaAreas.left_of(at[1]) * 20.0
	var k := plan.block_index_at(p)
	var t0 := Time.get_ticks_msec()
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var ms := Time.get_ticks_msec() - t0
	var meshes := {}
	var buildings := 0
	var body := false
	for c in chunk.get_children():
		if c is MeshInstance3D and str(c.name).begins_with("Replica_"):
			meshes[str(c.name).trim_prefix("Replica_")] = true
		elif c is Building:
			buildings += 1
		elif c.name == "ReplicaBody":
			body = (c as Node).get_child_count() > 0
	var lamps := 0
	for r in chunk.prop_records:
		if r.kind == "lamp":
			lamps += 1
	_t._check(chunk._replica != null and meshes.has("asphalt") and meshes.has("h_wall") and meshes.has("h_roof") and meshes.has("glass") and body and lamps > 0 and buildings == 0,
		"a replica chunk builds the road, houses, lamps and collision and no seeded buildings (%d ms; %s; %d lamps, %d buildings)" % [ms, ",".join(meshes.keys()), lamps, buildings])
	chunk.queue_free()
	await _t.get_tree().process_frame


## A car on the Esplanade drives south through the roundabout the right way round and on up the
## Paseo, keeping clear of the island.
func _traffic(rep: ReplicaAreas, city: Node3D) -> void:
	var rt: ReplicaTraffic = city.get_node_or_null("ReplicaTraffic") as ReplicaTraffic
	_t._check(rt != null, "the city has the replica's own traffic")
	if rt == null:
		return
	var ra: Dictionary = rep.roundabouts[0]
	var c: Vector2 = ra.center
	var s := float(ra.s) - 70.0
	var closest := INF
	var swept := 0.0
	var prev := Vector2.ZERO
	var had_prev := false
	var off_road := 0
	while s < float(ra.s) + 70.0:
		var p := rt.lane_point(s, 1, 0)
		var q := Vector2(p.x, p.z)
		closest = minf(closest, q.distance_to(c))
		if had_prev and q.distance_to(c) < float(ra.r_out) + 3.0 and prev.distance_to(c) < float(ra.r_out) + 3.0:
			swept += (prev - c).angle_to(q - c)
		if q.distance_to(c) > float(ra.r_out) + 3.0:
			var hit := rep.nearest(q, 50.0)
			var sd: Dictionary = rep.sec[int(hit.i)] if not hit.is_empty() else {}
			if hit.is_empty() or float(hit.o) > 0.0 or float(hit.o) < float(sd.kerb_w):
				off_road += 1
		prev = q
		had_prev = true
		s += 1.0
	# angle_to is positive clockwise-from-x toward z; anticlockwise on the map is negative.
	_t._check(closest > float(ra.r_island) + 1.5 and swept < -0.5 and off_road == 0,
		"southbound traffic goes round the roundabout anticlockwise, clear of the island (%.1f m from its centre, swept %.0f deg, %d points off its half of the road)" % [closest, rad_to_deg(swept), off_road])
	# And a real car, driven by hand for a few simulated seconds, moves along its lane.
	rt._spawn(600.0, -1, 1)
	var car: Vehicle = rt.cars.back() if not rt.cars.is_empty() else null
	_t._check(car != null, "replica traffic spawns a car")
	if car == null:
		return
	for i in 60:
		rt._drive(1.0 / 30.0)
	var s_now: float = car.traffic.s
	var wp := WorldState.to_world(car.global_position)
	var hit := rep.nearest(Vector2(wp.x, wp.z), 50.0)
	_t._check(s_now < 600.0 - 15.0 and not hit.is_empty() and float(hit.o) > 0.0 and float(hit.o) < float((rep.sec[int(hit.i)] as Dictionary).kerb_e),
		"a northbound replica car drives its own half of the Esplanade (s %.0f, %.1f m east of the centre line)" % [s_now, float(hit.o) if not hit.is_empty() else -1.0])
	rt.cars.erase(car)
	car.queue_free()
