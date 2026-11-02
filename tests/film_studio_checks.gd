extends RefCounted
## The film studio lot (FilmStudio, FilmStudioKit), for tests/smoke_test.gd. Loaded at run time, not
## named there, so it compiles after the autoloads.
##
## The site on the grid: in MIDTOWN, snapped to whole blocks, every street inside closed and the
## perimeter open, no city lots and no other feature's grounds on its blocks. The layout, pure and
## repeatable: numbered stages (unique numbers) inside their sub-blocks, apart from each other and
## from the bungalows, fronts, offices and tower; the gate on the south wall; everything inside the
## wall. The bungalows: no garage. The chunks: FULL lays the lot mesh on the studio shader (casting)
## and its shadowless ground, collision, under a triangle budget; LOD and the far city's capture lay
## far boxes and no detail.

var _t: Node

## Triangles a FULL site chunk's lot mesh may hold (stages, walls, fronts, vehicles).
const MESH_BUDGET := 90000


func run(t: Node, city: Node3D) -> void:
	_t = t
	if not FilmStudio.enabled:
		return  # FILM_STUDIO=0, the A/B: there is no lot to check.
	var plan: CityPlan = city.plan
	var lay := FilmStudio.layout(plan)
	_t._check(not lay.is_empty(), "the film studio lot has a site on the plan")
	if lay.is_empty():
		return
	_site(plan, lay)
	_layout(plan, lay)
	_kit()
	var s: Dictionary = lay.site
	# The chunk that holds the most stages.
	var best := Vector2i(int(s.ix0), int(s.iz0))
	var most := -1
	for ix in range(int(s.ix0), int(s.ix1)):
		for iz in range(int(s.iz0), int(s.iz1)):
			var n := 0
			for sg: Dictionary in lay.stages:
				if plan.owned_rect(ix, iz).has_point(sg.c):
					n += 1
			if n > most:
				most = n
				best = Vector2i(ix, iz)
	_full_chunk(city, plan, best)
	_backlot_and_front(city, plan, lay)
	_lod_chunk(city, plan, best)
	_capture(city, plan, best)


func _site(plan: CityPlan, lay: Dictionary) -> void:
	var s: Dictionary = lay.site
	var R: Rect2 = lay.rect
	_t._check(plan.district_at(R.get_center()) == CityPlan.District.MIDTOWN, "the studio lot stands in midtown")
	_t._check(int(s.ix1) - int(s.ix0) >= 2 and int(s.iz1) - int(s.iz0) >= 2 and R.size.x > 150.0 and R.size.y > 250.0,
		"the lot takes %d x %d blocks (%.0f x %.0f m)" % [int(s.ix1) - int(s.ix0), int(s.iz1) - int(s.iz0), R.size.x, R.size.y])
	var closed := true
	for ix in range(int(s.ix0) + 1, int(s.ix1)):
		closed = closed and not plan.road_open(CityPlan.AXIS_X, ix, R.get_center().y)
	for iz in range(int(s.iz0) + 1, int(s.iz1)):
		closed = closed and not plan.road_open(CityPlan.AXIS_Z, iz, R.get_center().x)
	var perimeter := plan.road_open(CityPlan.AXIS_X, int(s.ix0), R.get_center().y) and plan.road_open(CityPlan.AXIS_X, int(s.ix1), R.get_center().y) \
		and plan.road_open(CityPlan.AXIS_Z, int(s.iz0), R.get_center().x) and plan.road_open(CityPlan.AXIS_Z, int(s.iz1), R.get_center().x)
	_t._check(closed and perimeter, "every street inside the lot is closed (%s) and the four round it open (%s)" % [closed, perimeter])
	var lots := 0
	var site := true
	var grounds := 0
	for ix in range(int(s.ix0), int(s.ix1)):
		for iz in range(int(s.iz0), int(s.iz1)):
			lots += plan.lots(ix, iz).size()
			var b := plan.block(ix, iz)
			site = site and String(b.get("site", "")) == FilmStudio.SITE_ID
			if b.has("grounds"):
				grounds += 1
	_t._check(lots == 0 and site and grounds == 0, "the lot's blocks are its site: no city lots (%d), no school or park grounds (%d)" % [lots, grounds])
	var gate: Vector2 = lay.gate.at
	_t._check(absf(gate.y - (lay.wall as Rect2).end.y) < 0.01 and gate.x > (lay.inner as Rect2).position.x and gate.x < (lay.inner as Rect2).end.x,
		"the gate is on the lot's south wall (%s)" % gate)


func _layout(plan: CityPlan, lay: Dictionary) -> void:
	var inner: Rect2 = lay.inner
	var stages: Array = lay.stages
	_t._check(stages.size() >= 5, "the lot has %d sound stages" % stages.size())
	var numbers := {}
	var feet: Array[Rect2] = []
	var inside := true
	for sg: Dictionary in stages:
		numbers[int(sg.number)] = true
		var sz: Vector3 = sg.size
		var e := Vector2(sz.x, sz.z) if is_zero_approx(float(sg.yaw)) else Vector2(sz.z, sz.x)
		var foot := Rect2((sg.c as Vector2) - e * 0.5, e)
		inside = inside and inner.encloses(foot)
		feet.append(foot)
	_t._check(numbers.size() == stages.size(), "every stage has its own number (%d numbers, %d stages)" % [numbers.size(), stages.size()])
	var apart := true
	for i in feet.size():
		for j in range(i + 1, feet.size()):
			if feet[i].grow(-0.5).intersects(feet[j]):
				apart = false
	_t._check(inside and apart, "the stages stand inside the wall (%s) and apart from each other (%s)" % [inside, apart])
	var others: Array[Rect2] = []
	for lot: Dictionary in lay.lots:
		others.append(lot.cell)
	if not (lay.offices as Dictionary).is_empty():
		var oc: Vector2 = lay.offices.c
		var osz: Vector3 = lay.offices.size
		others.append(Rect2(oc - Vector2(osz.x, osz.z) * 0.5, Vector2(osz.x, osz.z)))
	if lay.tower != Vector2.INF:
		others.append(Rect2((lay.tower as Vector2) - Vector2(7.0, 7.0), Vector2(14.0, 14.0)))
	others.append(lay.backlot_street)
	var clash := 0
	for f in feet:
		for o in others:
			if o.has_area() and f.intersects(o):
				clash += 1
	_t._check(clash == 0, "no stage stands on a bungalow, the offices, the tower or the backlot (%d clashes)" % clash)
	_t._check((lay.fronts as Array).size() >= 8 and (lay.backlot_street as Rect2).has_area(), "the backlot has a street of %d false fronts" % (lay.fronts as Array).size())
	var off := 0
	for f: Dictionary in lay.fronts:
		if not inner.has_point(f.at):
			off += 1
	for p: Dictionary in lay.parking:
		if not inner.has_point(p.at):
			off += 1
		for ft in feet:
			if ft.has_point(p.at):
				off += 1
	_t._check(off == 0 and (lay.parking as Array).size() >= 10, "%d trailers and trucks parked inside the wall, none in a stage (%d off)" % [(lay.parking as Array).size(), off])
	_t._check(lay.tower != Vector2.INF and inner.has_point(lay.tower), "the water tower stands inside the lot")
	var garages := 0
	for lot: Dictionary in lay.lots:
		var h := FilmStudio.house_for(plan, lot)
		if not (h.garage as Dictionary).is_empty():
			garages += 1
	_t._check((lay.lots as Array).size() >= 4 and garages == 0, "%d office bungalows, none with a garage" % (lay.lots as Array).size())
	# Pure: planned again from scratch, the same lot.
	FilmStudio._layouts.clear()
	var again := FilmStudio.layout(plan)
	var same: bool = again.stages.size() == stages.size() and again.fronts.size() == lay.fronts.size() and again.parking.size() == lay.parking.size()
	if same:
		for i in stages.size():
			same = same and (again.stages[i].c as Vector2).is_equal_approx(stages[i].c) and int(again.stages[i].number) == int(stages[i].number)
	_t._check(same, "the lot plans the same twice (a pure layout)")


func _kit() -> void:
	var name := FilmStudioKit.text2d(FilmStudioKit.STUDIO_NAME, 1.0)
	_t._check((name[0] as PackedVector2Array).size() > 60 and float(name[1]) > 4.0, "the studio's name sets as lettering (%.1f m wide)" % float(name[1]))
	_t._check(FilmStudioKit.emblem(1.0).size() >= 90, "the studio's mark is drawn (%d points)" % FilmStudioKit.emblem(1.0).size())


func _full_chunk(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var lot: MeshInstance3D = chunk.get_node_or_null("StudioLot")
	var ground: MeshInstance3D = chunk.get_node_or_null("StudioGround")
	var shader_ok := lot != null and lot.material_override is ShaderMaterial and (lot.material_override as ShaderMaterial).shader.resource_path.ends_with("film_studio.gdshader")
	_t._check(shader_ok and lot.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "a FULL studio chunk lays its lot as one casting mesh on the studio shader")
	_t._check(ground != null and ground.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "its ground is one shadowless mesh")
	var tris := CityChunk._mesh_tris(lot.mesh) if lot else 0
	_t._check(tris > 2000 and tris < MESH_BUDGET, "its lot mesh is %d triangles (budget %d)" % [tris, MESH_BUDGET])
	var shapes := 0
	for c in chunk.get_children():
		if c is StaticBody3D:
			shapes += c.get_child_count()
	_t._check(shapes >= 10, "its stages, walls and ground collide (%d shapes)" % shapes)
	var buildings := 0
	for c in chunk.get_children():
		if c is Building:
			buildings += 1
	_t._check(buildings == 0, "no city Building on the lot")
	chunk.get_parent().remove_child(chunk)
	chunk.free()


func _lod_chunk(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.LOD)
	chunk.build()
	var boxes := chunk.get_node_or_null("Batch_lod_box") as MultiMeshInstance3D
	_t._check(chunk.get_node_or_null("StudioLot") == null and boxes != null, "a LOD studio chunk lays far boxes and no detail")
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
	var ground := (cap.captured.get("ground", []) as Array).size()
	var boxes: Dictionary = (cap.captured.get("batch", {}) as Dictionary).get("lod_box", {})
	_t._check(ground >= 1 and (boxes.get("xforms", []) as Array).size() >= 2,
		"the far city records the lot's ground (%d slabs) and its stages (%d far boxes)" % [ground, (boxes.get("xforms", []) as Array).size()])
	cap.free()


func _backlot_and_front(city: Node3D, plan: CityPlan, lay: Dictionary) -> void:
	var k := plan.chunk_index_at((lay.backlot_street as Rect2).get_center())
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var real := 0
	for car in chunk._cars:
		if car is Vehicle:
			real += 1
	_t._check(real >= 2, "the backlot street's parked cars are real Vehicle bodies (%d)" % real)
	for car in chunk._cars:
		if is_instance_valid(car):
			car.free()
	chunk._cars.clear()
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	var kf := plan.chunk_index_at(lay.offices.c)
	var front: CityChunk = city._new_chunk(kf, CityChunk.Level.FULL)
	front.build()
	var glass: MeshInstance3D = front.get_node_or_null("StudioGlass")
	_t._check(glass != null and (glass.material_override as ShaderMaterial).shader.resource_path.ends_with("curtain_glass.gdshader"),
		"the office block's windows are curtain glass with its traced offices")
	for car in front._cars:
		if is_instance_valid(car):
			car.free()
	front.get_parent().remove_child(front)
	front.free()
