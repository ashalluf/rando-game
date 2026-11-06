extends RefCounted
## The canal neighbourhood (Canals, CanalKit), for tests/smoke_test.gd. Loaded at run time, not
## named there, so it compiles after the autoloads.
##
## The site on the grid: snapped to whole blocks, every street inside closed and the perimeter
## open, no city lots on its blocks. The layout, pure: canals at their width, every lot outside
## every canal's band and inside the site, walks clear of the water, bridges in the middle of a
## stretch, the water's floor above under_city_ground()'s reach and under the city's ground box.
## The houses: fronted on their canal, no garage, inside their yard. The chunks: FULL lays one mesh
## per material, the water and the banks, one collision body, the water volume, the bridges and
## boats as batches, under a triangle budget; LOD lays the water and the houses' far boxes; the
## far city's capture records the ground and the houses.

var _t: Node

## Triangles a FULL site chunk's own meshes may hold (ground, banks, water, fences, railings).
const MESH_BUDGET := 260000


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var lay := Canals.layout(plan)
	_t._check(not lay.is_empty(), "the canal neighbourhood has a site on the plan")
	if lay.is_empty():
		return
	_site(plan, lay)
	_layout(plan, lay)
	_houses(plan, lay)
	var s: Dictionary = lay.site
	var k := Vector2i(int(s.ix0), int(s.iz0))
	_full_chunk(city, plan, k)
	_lod_chunk(city, plan, k)
	_capture(city, plan, k)


func _site(plan: CityPlan, lay: Dictionary) -> void:
	var s: Dictionary = lay.site
	var R: Rect2 = lay.rect
	_t._check(int(s.ix1) - int(s.ix0) >= 2 and int(s.iz1) - int(s.iz0) >= 2 and R.size.x > 120.0 and R.size.y > 250.0,
		"the canals take %d x %d blocks (%.0f x %.0f m)" % [int(s.ix1) - int(s.ix0), int(s.iz1) - int(s.iz0), R.size.x, R.size.y])
	var closed := true
	for ix in range(int(s.ix0) + 1, int(s.ix1)):
		closed = closed and not plan.road_open(CityPlan.AXIS_X, ix, R.get_center().y)
	for iz in range(int(s.iz0) + 1, int(s.iz1)):
		closed = closed and not plan.road_open(CityPlan.AXIS_Z, iz, R.get_center().x)
	var perimeter := plan.road_open(CityPlan.AXIS_X, int(s.ix0), R.get_center().y) and plan.road_open(CityPlan.AXIS_X, int(s.ix1), R.get_center().y) \
		and plan.road_open(CityPlan.AXIS_Z, int(s.iz0), R.get_center().x) and plan.road_open(CityPlan.AXIS_Z, int(s.iz1), R.get_center().x)
	_t._check(closed and perimeter, "every street inside the canals is closed (%s) and the four round them open (%s)" % [closed, perimeter])
	var lots := 0
	var site := true
	for ix in range(int(s.ix0), int(s.ix1)):
		for iz in range(int(s.iz0), int(s.iz1)):
			lots += plan.lots(ix, iz).size()
			site = site and String(plan.block(ix, iz).get("site", "")) == Canals.SITE_ID
	_t._check(lots == 0 and site, "the canals' blocks are its site with no city lots on them (%d lots)" % lots)
	_t._check(plan.in_site(R.get_center()), "the middle of the canals is site ground")


func _layout(plan: CityPlan, lay: Dictionary) -> void:
	var I: Rect2 = lay.inner
	var bad_lots := 0
	for lot: Dictionary in lay.lots:
		var cell: Rect2 = lot.cell
		if not I.grow(0.05).encloses(cell):
			bad_lots += 1
		for b: Rect2 in lay.bands:
			if b.grow(-0.05).intersects(cell):
				bad_lots += 1
	_t._check((lay.lots as Array).size() >= 60 and bad_lots == 0,
		"%d canal lots, every one inside the site and off every canal and walk (%d bad)" % [(lay.lots as Array).size(), bad_lots])
	var bad_walks := 0
	for w: Rect2 in lay.walks:
		for c: Rect2 in lay.corridors:
			if c.grow(-0.05).intersects(w):
				bad_walks += 1
	_t._check((lay.walks as Array).size() >= 10 and bad_walks == 0, "the walks run beside the water, never over it (%d bad)" % bad_walks)
	var widths := true
	for c: Rect2 in lay.corridors:
		widths = widths and (is_equal_approx(c.size.x, Canals.CANAL_W) or is_equal_approx(c.size.y, Canals.CANAL_W))
	_t._check(widths and (lay.canals as Array).size() == Canals.NS_COUNT + Canals.EW_COUNT, "%d canals, each %.0f m between its bank tops" % [(lay.canals as Array).size(), Canals.CANAL_W])
	var on_water := 0
	for b: Dictionary in lay.bridges:
		if Canals.canal_offset(lay, b.at) < 0.01:
			on_water += 1
	_t._check((lay.bridges as Array).size() >= 8 and on_water == (lay.bridges as Array).size(),
		"%d footbridges, each across the middle of a canal" % (lay.bridges as Array).size())
	_t._check(Canals.FLOOR_Y > -1.5 and Canals.FLOOR_Y < Canals.WATER_Y and Canals.WATER_Y < 0.0 and Canals.WALL_BOTTOM < Canals.FLOOR_Y,
		"the canal bed (%.2f) is under the water (%.2f), under the ground box's top and above under_city_ground()'s 1.5 m" % [Canals.FLOOR_Y, Canals.WATER_Y])
	var mono := true
	var prev := -INF
	for i in 80:
		var y := Canals.bank_y(float(i) * 0.1)
		mono = mono and y >= prev - 1e-5
		prev = y
	_t._check(mono and is_equal_approx(Canals.bank_y(0.0), Canals.FLOOR_Y) and Canals.bank_y(Canals.HALF) > Canals.WATER_Y,
		"the bank rises from the bed to the coping without a dip")
	Canals._layouts.erase(plan.get_instance_id())
	var again := Canals.layout(plan)
	_t._check((again.lots as Array).size() == (lay.lots as Array).size() and (again.lots[0] as Dictionary).seed == (lay.lots[0] as Dictionary).seed,
		"the canal layout is pure: built again it is the same")


func _houses(plan: CityPlan, lay: Dictionary) -> void:
	var garages := 0
	var outside := 0
	var wrong := 0
	var styles := {}
	for lot: Dictionary in lay.lots:
		var h := Canals.house_for(plan, lot)
		styles[int(h.style)] = true
		if not (h.garage as Dictionary).is_empty():
			garages += 1
		var yard: Rect2 = lot.yard
		for r: Rect2 in HouseKit.ground_parts(h):
			if not yard.grow(0.05).encloses(r):
				outside += 1
		# The door is on the canal side of the house's middle.
		var door := YardFill._fp(h.f, float(h.door_u), float(h.door_v))
		if (door.x - (lot.cell as Rect2).get_center().x) * float(lot.dir) <= 0.0:
			wrong += 1
	_t._check(garages == 0 and outside == 0 and wrong == 0 and styles.size() >= 4,
		"the canal houses face their canal (%d wrong), have no garage (%d), stay in their yards (%d out), %d types" % [wrong, garages, outside, styles.size()])


func _full_chunk(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var names := {}
	var tris := 0
	for c in chunk.get_children():
		names[String(c.name)] = c
		if String(c.name).begins_with("Canal_") and c is MeshInstance3D:
			tris += CityChunk._mesh_tris((c as MeshInstance3D).mesh)
	var water: MeshInstance3D = names.get("Canal_water")
	_t._check(water != null and water.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and names.has("Canal_bank") and names.has("Canal_walk") and names.has("Canal_lawn"),
		"a FULL canal chunk lays the water (shadowless), the banks, the walks and the lawns")
	var body: StaticBody3D = names.get("CanalGround")
	var zone: Area3D = names.get("CanalWater")
	_t._check(body != null and body.collision_mask == 0 and zone != null and zone.get_child_count() >= 1 and not zone.monitorable,
		"its ground is one collision body (mask 0) and its water one volume that lets bodies down to the bed")
	var batches := 0
	for key: String in ["Batch_canal_bridge", "Batch_canal_dock", "Batch_canal_boat_0", "Batch_canal_boat_1", "Batch_canal_boat_2", "Batch_canal_lantern"]:
		if names.has(key):
			batches += 1
	var buildings := 0
	for c in chunk.get_children():
		if c is Building:
			buildings += 1
	_t._check(batches >= 3 and buildings == 0 and names.has("House_h_wall"),
		"its bridges, docks, boats and lanterns are batches (%d kinds), its houses HouseKit's meshes, no Building" % batches)
	_t._check(tris > 1000 and tris < MESH_BUDGET, "its own meshes are %d triangles (budget %d)" % [tris, MESH_BUDGET])
	chunk.get_parent().remove_child(chunk)
	chunk.free()


func _lod_chunk(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.LOD)
	chunk.build()
	var ok := chunk.get_node_or_null("Canal_bank") == null and chunk.get_node_or_null("Canal_water") != null \
		and chunk.get_node_or_null("CanalWater") == null and chunk.get_node_or_null("Batch_canal_bridge") == null
	_t._check(ok, "a LOD canal chunk lays the water and no banks, volume or bridges")
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
	_t._check(ground >= 10 and (boxes.get("xforms", []) as Array).size() >= 10,
		"the far city records the canals' ground (%d slabs) and houses (%d far boxes)" % [ground, (boxes.get("xforms", []) as Array).size()])
	cap.free()
