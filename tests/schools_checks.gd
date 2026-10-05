extends RefCounted
## Public schools (Schools, SchoolKit, the school bus), for tests/smoke_test.gd. Loaded at run time,
## not named there, so it compiles after the autoloads.
##
## Placement over the basin: schools in the suburbs, midtown and the beach town, on plain city
## blocks no one else claimed, elementary and high schools, every school block SCHOOL with no lots;
## pure (a fresh plan of the same seed decides the same blocks), the plans' facilities inside their
## sites, nothing on anything, regulation courts and a track no longer than 400 m. A high school's
## street is closed between its blocks and open at the crossings and round the outside. A FULL
## chunk: one school mesh on the school shader, the ground in the Parks ground mesh, no Building, a
## triangle budget. The far city's capture: the ground as slabs that never overlap, the buildings as
## far boxes. The shaders handle every kind. The school bus: built from its model, a big vehicle,
## its length the model's; parked on the road in the loading zone where no parked car stands; in
## traffic only near a school at the bell.

var _t: Node

## Triangles the school mesh may hold for one chunk (a big elementary school is ~60k).
const KIT_BUDGET := 160000


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_kinds()
	var found := _placement(plan)
	_purity(plan)
	_roads(plan, found)
	if found.has("elem"):
		_full_chunk(city, plan, found.elem)
		_capture(city, plan, found.elem)
	if found.has("high"):
		var d: Dictionary = Schools.decide(plan, plan.block(found.high.x, found.high.y).school)
		for k: Vector2i in d.blocks:
			_full_chunk(city, plan, k)
	await _bus(city, plan, found)


func _kinds() -> void:
	var src: String = (load("res://shaders/school_walls.gdshader") as Shader).code
	var ok := true
	for k in SchoolKit.KIND_COUNT:
		if not (src.contains("k == %d)" % k) or src.contains("k == %d ||" % k) or src.contains("|| k == %d" % k)):
			ok = false
	_t._check(ok, "the school walls shader draws each of the kit's %d kinds" % SchoolKit.KIND_COUNT)
	var g: String = (load("res://shaders/park_ground.gdshader") as Shader).code
	_t._check(g.contains("k == %d)" % Schools.G_MAP), "the park ground shader draws the schools' painted map (kind %d)" % Schools.G_MAP)


## Every school over the basin. Returns {"elem": a block of an elementary school, "high": the first
## block of a high school}.
func _placement(plan: CityPlan) -> Dictionary:
	var bad: Array = []
	var n := {"elem": 0, "high": 0}
	var out := {}
	var box := Rect2(-6000.0, -6000.0, 12000.0, 12000.0)
	var c0 := Schools._cell_of(box.position)
	var c1 := Schools._cell_of(box.end)
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var d := Schools.decide(plan, Vector2i(cx, cz))
			if d.is_empty():
				continue
			n["high" if d.high else "elem"] += 1
			for k: Vector2i in d.blocks:
				var b := plan.block(k.x, k.y)
				if int(b.kind) != CityPlan.BlockKind.SCHOOL or b.get("grounds", "") != ("school_h" if d.high else "school_e"):
					bad.append("block %s not a school" % [k])
				if not plan.lots(k.x, k.y).is_empty():
					bad.append("lots on %s" % [k])
				if not (int(b.district) in Schools.SCHOOL_DISTRICTS):
					bad.append("district %d at %s" % [int(b.district), k])
				if plan.zone_at((b.rect as Rect2).get_center()) != MacroMap.Zone.CITY:
					bad.append("off city ground %s" % [k])
				if Landmarks.claims(b.rect) or b.has("site"):
					bad.append("on a landmark's block %s" % [k])
			var pl := Schools.plan_for_school(plan, d)
			var site: Rect2 = pl.site
			var fac: Array = pl.fac
			for i in fac.size():
				var f: Dictionary = fac[i]
				var r: Rect2 = f.r
				if not site.grow(0.05).encloses(r):
					bad.append("%s outside its site at %s" % [f.t, d.cell])
				for j in range(i + 1, fac.size()):
					var g: Dictionary = fac[j]
					if (f.t == "track" and g.t == "bleachers") or (f.t == "bleachers" and g.t == "track"):
						continue
					if r.intersection(g.r).get_area() > 0.05:
						bad.append("%s on %s at %s" % [f.t, g.t, d.cell])
				match f.t:
					"basketball":
						if (f.W as float) / float(f.n) < Parks.BB_COURT.y:
							bad.append("short court %s" % [d.cell])
					"tennis":
						if absf(float(f.L) - Parks.TEN_ENCLOSURE.x) > 0.01:
							bad.append("tennis enclosure %s" % [d.cell])
					"track":
						if float(f.lap) > 400.01 or float(f.lap) < 200.0:
							bad.append("track lap %.1f" % float(f.lap))
			if d.high and not out.has("high"):
				out.high = d.blocks[0]
			if not d.high and not out.has("elem"):
				out.elem = d.blocks[0]
	_t._check(bad.is_empty(), "school placement: SCHOOL blocks with no lots, in their districts, on city ground, facilities inside their sites, nothing on anything, regulation sizes (%s)" % [bad.slice(0, 4)])
	_t._check(n.elem >= 8 and n.high >= 2, "schools across the basin (%s)" % [n])
	return out


## A fresh plan of the same seed, with the caches cleared, places the same schools.
func _purity(plan: CityPlan) -> void:
	var before := {}
	for key: Vector3i in Schools._cells:
		var d: Dictionary = Schools._cells[key]
		if not d.is_empty() and key.x == plan.seed:
			before[Vector2i(key.y, key.z)] = str(d.blocks)
	var saved_cells := Schools._cells
	var saved_plans := Schools._plans
	var saved_closed := Schools._closed
	Schools._cells = {}
	Schools._plans = {}
	Schools._closed = {}
	var fresh := CityPlan.new()
	fresh.seed = plan.seed
	fresh.block_size_range = plan.block_size_range
	fresh.street_width = plan.street_width
	fresh.avenue_width = plan.avenue_width
	fresh.sidewalk_width = plan.sidewalk_width
	fresh.downtown_radius = plan.downtown_radius
	fresh.midtown_radius = plan.midtown_radius
	fresh.macro = plan.macro
	var diff := 0
	var keys := before.keys()
	for i in mini(keys.size(), 12):
		var cell: Vector2i = keys[i]
		var d := Schools.decide(fresh, cell)
		if d.is_empty() or str(d.blocks) != before[cell]:
			diff += 1
	Schools._cells = saved_cells
	Schools._plans = saved_plans
	Schools._closed = saved_closed
	_t._check(diff == 0 and keys.size() > 0, "a fresh plan of the seed places the same schools (%d of %d differ)" % [diff, mini(keys.size(), 12)])


## A high school's street: closed along its blocks, open at the crossings at both ends and round
## the outside; no parked car on it.
func _roads(plan: CityPlan, found: Dictionary) -> void:
	if not found.has("high"):
		_t._check(false, "a high school to check the closed street on")
		return
	var d: Dictionary = Schools.decide(plan, plan.block(found.high.x, found.high.y).school)
	var axis: int = d.axis
	var ok := true
	var why := ""
	for i in (d.roads as Array).size():
		var index: int = d.roads[i]
		var k: Vector2i = d.blocks[i]
		var r: Rect2 = plan.block(k.x, k.y).rect
		var mid := r.get_center().y if axis == CityPlan.AXIS_X else r.get_center().x
		var lo := r.position.y if axis == CityPlan.AXIS_X else r.position.x
		var hi := r.end.y if axis == CityPlan.AXIS_X else r.end.x
		if plan.road_open(axis, index, mid):
			ok = false
			why = "open in the middle"
		if not plan.road_open(axis, index, lo - 4.0) or not plan.road_open(axis, index, hi + 4.0):
			ok = false
			why = "closed at a crossing"
		var p := Vector2(plan.road_pos(axis, index), mid) if axis == CityPlan.AXIS_X else Vector2(mid, plan.road_pos(axis, index))
		if not Schools.keeps_clear(plan, p):
			ok = false
			why = "a parked car may stand on it"
	# The outer roads of the first block stay open.
	var k0: Vector2i = d.blocks[0]
	var r0: Rect2 = plan.block(k0.x, k0.y).rect
	if not plan.road_open(CityPlan.AXIS_X, k0.x, r0.get_center().y) or not plan.road_open(CityPlan.AXIS_Z, k0.y, r0.get_center().x):
		ok = false
		why = "an outer road closed"
	_t._check(ok, "a high school's street is closed between its blocks, open at its crossings and round it, no parking on it (%s)" % why)


func _full_chunk(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var before := SchoolKit.tris
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var kit := SchoolKit.tris - before
	var walls := chunk.find_children("SchoolWalls", "MeshInstance3D", false, false)
	var grounds := chunk.find_children("ParkGround", "MeshInstance3D", false, false)
	var buildings := 0
	for c in chunk.get_children():
		if c is Building:
			buildings += 1
	var role: String = plan.block(k.x, k.y).grounds
	_t._check(walls.size() <= 1 and grounds.size() == 1 and (grounds[0] as MeshInstance3D).material_override == Parks.ground_material(),
		"%s %s: its ground is in the one Parks ground mesh, its buildings in at most one school mesh (%d, %d)" % [role, k, grounds.size(), walls.size()])
	if walls.size() == 1:
		_t._check((walls[0] as MeshInstance3D).material_override == Schools.walls_material() and buildings == 0 and kit > 300 and kit < KIT_BUDGET,
			"%s %s: the school mesh on the school shader, no Building, %d triangles (budget %d)" % [role, k, kit, KIT_BUDGET])
	chunk.get_parent().remove_child(chunk)
	chunk.free()


func _capture(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var cap := CityChunk.new()
	cap.plan = plan
	cap.ix = k.x
	cap.iz = k.y
	cap.level = CityChunk.Level.LOD
	cap.style = city.chunk_style()
	cap.capturing = true
	cap.build()
	var site: Rect2 = Schools.plan_for(plan, k.x, k.y).site
	var mine: Array[Rect2] = []
	for g: Array in cap.captured.get("ground", []):
		var r: Rect2 = g[0]
		if site.grow(0.1).encloses(r) and absf(float(g[2]) - (CityChunk.SIDEWALK_TOP + Parks.LIFT)) < 0.005:
			mine.append(r)
	var overlap := 0
	var area := 0.0
	for i in mine.size():
		area += mine[i].get_area()
		for j in range(i + 1, mine.size()):
			if mine[i].intersection(mine[j]).get_area() > 0.05:
				overlap += 1
	var boxes: Dictionary = (cap.captured.get("batch", {}) as Dictionary).get("lod_box", {})
	_t._check(mine.size() >= 3 and overlap == 0 and area > site.get_area() * 0.5,
		"the far city captures school %s's ground as %d slabs, none on another (%d overlaps), %.0f %% of the site" % [k, mine.size(), overlap, 100.0 * area / maxf(site.get_area(), 1.0)])
	_t._check((boxes.get("xforms", []) as Array).size() >= 3, "the far city captures school %s's buildings as far boxes (%d)" % [k, (boxes.get("xforms", []) as Array).size()])
	cap.free()


func _bus(city: Node3D, plan: CityPlan, found: Dictionary) -> void:
	var bus := BigVehicles.make(Vehicle.BodyType.SCHOOL_BUS, 7)
	city.add_child(bus)
	await _t.get_tree().process_frame
	var d := bus._dims()
	_t._check(BigVehicles.is_big(bus.body_type) and bus._has_model and absf(float(d.length) - 12.795) < 0.3,
		"the school bus builds from its model, a big vehicle, %.2f m long" % float(d.length))
	bus.queue_free()
	if not found.has("elem"):
		return
	var pl := Schools.plan_for(plan, found.elem.x, found.elem.y)
	var spots := Schools.bus_spots(plan, pl)
	var ok := spots.size() >= 1
	var site: Rect2 = pl.site
	for s: Array in spots:
		var p: Vector2 = s[0]
		if site.grow(plan.sidewalk_width - 0.2).has_point(p) or not Schools.keeps_clear(plan, p):
			ok = false
	_t._check(ok, "the school's buses park on the road in its loading zone, where no parked car stands (%d)" % spots.size())
	var near: Vector2 = site.get_center() + Vector2(site.size.x * 0.5 + 30.0, 0.0)
	var far_away := Vector2(-20000.0, -20000.0)
	_t._check(Schools.traffic_bus(plan, near, 0.01, 7.5) and not Schools.traffic_bus(plan, near, 0.01, 11.0)
		and not Schools.traffic_bus(plan, near, 0.5, 7.5) and not Schools.traffic_bus(plan, far_away, 0.01, 7.5),
		"school buses join the traffic near a school at the bell only")
