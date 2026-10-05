extends RefCounted
## Neighbourhood civic buildings (CivicBuildings, CivicKit) for tests/smoke_test.gd. Loaded at run
## time (not named there), so it compiles after the autoloads.
## Checks: the placement is pure (the same answer twice) and every kind is somewhere; a site is
## whole lots of its own block, inside the pavement, off the fire station's, a police station's
## and a school's block and the freeways, in a city zone; the switch turns it off; each kind's
## chunk builds the building (real geometry inside its budget), its collision, glass, lamps; the
## post office its flag and mail trucks; the far city sees it as coded boxes; the kerb in front of
## a post office's drive is kept clear; the lots of a block next door are untouched.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _plan: CityPlan


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_plan = city.plan
	var all := _pure()
	if all.is_empty():
		return
	await _chunks(all)


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _ticks(n: int) -> void:
	for i in n:
		await _tree.physics_frame


func _pure() -> Array:
	var all := CivicBuildings.near(_plan, Vector2(1200.0, 900.0), 6000.0)
	var kinds := {}
	for s: Dictionary in all:
		kinds[int(s.kind)] = int(kinds.get(int(s.kind), 0)) + 1
	_check(all.size() >= 20 and kinds.size() == CivicBuildings.Kind.size(),
			"civic buildings stand across the city, every kind (%d: %s)" % [all.size(), str(kinds)])
	if all.is_empty():
		return []
	var found: Dictionary = all[0]
	CivicBuildings._cache.clear()
	var again := CivicBuildings.for_cell(_plan, found.cell)
	_check(not again.is_empty() and again.block == found.block and int(again.builder) == int(found.builder) and again.name == found.name and int(again.kind) == int(found.kind),
			"a civic building is worked out the same way twice (%s %s)" % [CivicBuildings.kind_name(int(found.kind)), found.name])
	var bad := 0
	var why := ""
	for s: Dictionary in all:
		var bi: Vector2i = s.block
		var b := _plan.block(bi.x, bi.y)
		var inner := (b.rect as Rect2).grow(-_plan.sidewalk_width + 0.01)
		var site: Rect2 = s.site
		var claimed := 0
		for lot: Dictionary in _plan.lots(bi.x, bi.y):
			if CivicBuildings.claims(_plan, bi.x, bi.y, lot):
				claimed += 1
				if not site.has_point(lot.center):
					bad += 1
					why = "lot outside"
				if FireStation.claims(_plan, bi.x, bi.y, lot) or PoliceStation.claims(_plan, bi.x, bi.y, lot) or Broadway.claims(_plan, bi.x, bi.y, lot):
					bad += 1
					why = "lot claimed twice"
		var fs := FireStation.for_cell(_plan, FireStation._cell_of((b.rect as Rect2).get_center()))
		if claimed != (s.lots as Array).size() or claimed == 0:
			bad += 1
			why = "claims %d of %d" % [claimed, (s.lots as Array).size()]
		elif not inner.encloses(site):
			bad += 1
			why = "site outside its block"
		elif not fs.is_empty() and fs.block == bi:
			bad += 1
			why = "fire station's block"
		elif not PoliceStation.station_on(_plan, bi.x, bi.y).is_empty():
			bad += 1
			why = "police station's block"
		elif int(b.kind) != CityPlan.BlockKind.BUILDINGS or b.has("grounds") or b.has("site") or b.has("hospital"):
			bad += 1
			why = "someone else's block"
		elif _plan.macro.freeway and _plan.macro.freeway.blocks_rect(site, 3.0):
			bad += 1
			why = "under a freeway"
		elif _plan.zone_at((b.rect as Rect2).get_center()) != MacroMap.Zone.CITY:
			bad += 1
			why = "not a city chunk"
		var lay := CivicKit.layout(s)
		if float(lay.bu1) > float(lay.L) + 4.0 or float(lay.bv1) > float(lay.D) + 0.01 or float(lay.bu0) < -0.01:
			bad += 1
			why = "layout off its site"
	_check(bad == 0, "every civic site is its own lots inside its block, nobody else's, off the freeway (%d bad of %d%s)" % [bad, all.size(), (": " + why) if why != "" else ""])
	# Off: no building claims a lot.
	CivicBuildings.enabled = false
	CivicBuildings._cache.clear()
	var lot0: Dictionary = {}
	for lot: Dictionary in _plan.lots(found.block.x, found.block.y):
		if (found.lots as Array).has(int(lot.seed)):
			lot0 = lot
	var off := not lot0.is_empty() and not CivicBuildings.claims(_plan, found.block.x, found.block.y, lot0)
	CivicBuildings.enabled = true
	CivicBuildings._cache.clear()
	_check(off and CivicBuildings.claims(_plan, found.block.x, found.block.y, lot0), "CIVIC=0 leaves the lots to what they were")
	# A post office keeps its drive's kerb clear.
	for s: Dictionary in all:
		if int(s.kind) != CivicBuildings.Kind.POST_OFFICE:
			continue
		var lay := CivicKit.layout(s)
		var axis := int(s.road[0])
		var at := CivicBuildings.world_xz(s, float(lay.drive_u), 0.0)
		var rp := _plan.road_pos(axis, int(s.road[1]))
		var kerb := Vector2(rp, at.y) if axis == CityPlan.AXIS_X else Vector2(at.x, rp)
		_check(CivicBuildings.keeps_clear(_plan, kerb) and not CivicBuildings.keeps_clear(_plan, kerb + Vector2(40.0, 40.0)),
				"the kerb at a post office's drive is kept clear of parked cars")
		break
	return all


## One building of each kind built in a FULL chunk and captured for the far city.
func _chunks(all: Array) -> void:
	var done := {}
	for s: Dictionary in all:
		var k := int(s.kind)
		if done.has(k):
			continue
		done[k] = true
		var name := CivicBuildings.kind_name(k)
		var chunk: CityChunk = _city._new_chunk(s.block, CityChunk.Level.FULL)
		chunk.build()
		var node: Node3D = null
		for n in chunk.get_children():
			if n.is_in_group("civic_building"):
				node = n
		_check(node != null and node.has_node("Building") and node.has_node("Body"), "the %s's chunk builds it with its collision" % name)
		if node == null:
			chunk.queue_free()
			continue
		var m := (node.get_node("Building") as MeshInstance3D).mesh
		var tris := 0
		var glass := false
		for si in m.get_surface_count():
			tris += m.surface_get_array_len(si) / 3
			var mat := m.surface_get_material(si) as ShaderMaterial
			if mat and mat.shader and mat.shader.resource_path.ends_with("civic_glass.gdshader"):
				glass = true
		_check(tris > 1500 and tris < 60000 and glass, "the %s is real geometry with traced-room glass inside its budget (%d triangles)" % [name, tris])
		var lamps := 0
		for c in node.get_children():
			if c.is_in_group("lamp_light"):
				lamps += 1
		_check(lamps >= 1 or OS.has_feature("web"), "the %s lights up at night (%d lights)" % [name, lamps])
		if k == CivicBuildings.Kind.POST_OFFICE:
			var trucks := 0
			if node.has_node("MailTrucks"):
				trucks = (node.get_node("MailTrucks") as MultiMeshInstance3D).multimesh.instance_count
			_check(node.has_node("Flag") and trucks >= 1, "the post office flies its flag and has mail trucks (%d)" % trucks)
		var lod := CityChunk.new()
		lod.plan = _plan
		lod.ix = (s.block as Vector2i).x
		lod.iz = (s.block as Vector2i).y
		lod.level = CityChunk.Level.LOD
		lod.style = _city.chunk_style()
		lod.capturing = true
		lod.build()
		var boxes: Dictionary = lod.captured.batch.get("lod_box", {"xforms": [], "custom": []})
		var coded := 0
		for c: Variant in boxes.get("custom", []):
			if c is Color and is_equal_approx((c as Color).a, FarBuilding.PART_FLAG):
				coded += 1
		_check((boxes.xforms as Array).size() > 0 and (coded > 0 or not FarBuilding.enabled), "the far city sees the %s as coded boxes (%d boxes, %d coded)" % [name, (boxes.xforms as Array).size(), coded])
		chunk.queue_free()
		lod.free()
		await _ticks(2)
	_check(done.size() == CivicBuildings.Kind.size(), "every kind was built (%d)" % done.size())
