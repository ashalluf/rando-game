extends RefCounted
## The beach refcam's fixes (wave 4, rc-beach), for tests/smoke_test.gd. Loaded at run time, not
## named there, so it compiles after the autoloads.
##
## SandRoads: the grid streets the sand and the sea cover read closed to the traffic (and only
## those), with the switch off nothing does. Waders: planned on a full afternoon, none with the
## switch off, the sand under the water is the sand mesh's own foreshore, the deepest stand is
## inside the depth they keep to. Pure: nothing here leans on what an earlier check left.

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.get("plan")
	if plan == null or plan.macro == null:
		_t._check(false, "rc_beach: the city has a plan")
		return
	_sand_roads(plan, city)
	_waders(plan)


func _sand_roads(plan: CityPlan, city: Node3D) -> void:
	var z := 800.0
	var cx := plan.macro.coast_x(z)
	# Every north-south street from 250 m out at sea to the waterline lies under the sea or the sand.
	var under: Array = []
	var k := plan.block_index_at(Vector2(cx - 250.0, z)).x
	while plan.road_pos(CityPlan.AXIS_X, k) < cx - 2.0:
		if plan.road_pos(CityPlan.AXIS_X, k) > cx - 250.0:
			under.append(k)
		k += 1
	var all_sand := not under.is_empty()
	for i: int in under:
		all_sand = all_sand and SandRoads.on_sand(plan, CityPlan.AXIS_X, i, z)
	_t._check(all_sand, "SandRoads: the streets at sea off z %.0f read under the sand (%s)" % [z, str(under)])
	# Flower St at Olympic (the street refcam) is a street.
	var flower := plan.block_index_at(Vector2(2359.4, 880.0))
	_t._check(not SandRoads.on_sand(plan, CityPlan.AXIS_X, flower.x, 880.0) and not SandRoads.on_sand(plan, CityPlan.AXIS_Z, flower.y, 2359.4),
		"SandRoads: the downtown streets are not under the sand")
	# A street running inland from the beach is open past the sand's landward edge.
	var inland := cx + plan.macro.beach_width_at(z) + 400.0
	var zr := plan.block_index_at(Vector2(inland, z)).y
	_t._check(not SandRoads.on_sand(plan, CityPlan.AXIS_Z, zr, inland), "SandRoads: an east-west street 400 m inland of the sand is open")
	var traffic := city.get_node_or_null("Traffic")
	if traffic and not under.is_empty():
		_t._check(not bool(traffic.call("_road_open", CityPlan.AXIS_X, under[under.size() - 1], z)),
			"the traffic treats the street along the waterline as closed")
	var was := SandRoads.enabled
	SandRoads.enabled = false
	var off := false
	for i: int in under:
		off = off or SandRoads.on_sand(plan, CityPlan.AXIS_X, i, z)
	SandRoads.enabled = was
	_t._check(not off, "SAND_ROADS=0 closes nothing")


func _waders(plan: CityPlan) -> void:
	var act := BeachLife.plan_activity(plan, 613.0, 816.0, 1.0)
	var n := int(act.get("waders", -1))
	_t._check(n >= 0 and n <= BeachLife.WADERS and (n > 0 or not Waders.enabled),
		"a full afternoon's stretch plans waders (%d of at most %d)" % [n, BeachLife.WADERS])
	var was := Waders.enabled
	Waders.enabled = false
	var off := int(BeachLife.plan_activity(plan, 613.0, 816.0, 1.0).get("waders", -1))
	Waders.enabled = was
	_t._check(off == 0, "WADERS=0 plans none (%d)" % off)
	# The sand under the water is the sand mesh's foreshore (CityChunk's rows).
	var e := 0.001
	_t._check(absf(Waders.bed_y(null, 0.0001, 0.0) - CityChunk.SAND_EDGE) < 0.01
		and absf(Waders.bed_y(null, CityChunk.SAND_STEEP_AT, 0.0) - CityChunk.SAND_STEEP_Y) < e
		and absf(Waders.bed_y(null, CityChunk.SAND_WET, 0.0) - CityChunk.SAND_LOW) < e,
		"Waders.bed_y is the sand mesh's foreshore (edge, steep step, bar)")
	_t._check(Waders.bed_y(null, Waders.S_MAX, 0.0) >= Waders.SEA_Y - Waders.MAX_DEPTH,
		"the farthest wader stands inside the depth they keep to (%.2f m of water)" % (Waders.SEA_Y - Waders.bed_y(null, Waders.S_MAX, 0.0)))
