extends RefCounted
## The oil_islands_dusk refcam (wave 8, tools/refcams/cameras_w8.json; docs/HANDOFF.md "The oil
## islands at dusk from the Long Beach sand"), for tests/smoke_test.gd. Loaded at run time.
##
## Checks: Long Beach's BEACH blocks are claimed by LongBeachSand (and nothing else's beach), their
## road strips count as under the sand, a FULL chunk there lays a sand mesh across the waterline at
## bay_z with palms; the sand's profile; the islands' floods
## pushed to the ocean (16 sources, none with RC5_OIL_ISLANDS=0) and the island material's dusk
## look; the shaders carry the mirror and the look; the camera row.

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_claims(plan)
	_profile(plan)
	_chunk(city, plan)
	_islands()
	_camera()


## A Long Beach block: on the bay's north shore, its centre BEACH, between the port and bay_east_x.
func _lb_block(plan: CityPlan) -> Vector2i:
	var m: MacroMap = plan.macro
	var z := m.bay_z - m.bay_beach_depth * 0.5
	var x := (m.port_rect.end.x + m.bay_east_x) * 0.5
	return plan.chunk_index_at(Vector2(x, z))


func _claims(plan: CityPlan) -> void:
	var k := _lb_block(plan)
	var r: Rect2 = plan.block(k.x, k.y).rect
	_t._check(LongBeachSand.claims_block(plan, r), "a Long Beach block (%s) is LongBeachSand's" % k)
	var north: Rect2 = plan.block(k.x, k.y - 1).rect
	_t._check(not LongBeachSand.claims_block(plan, north), "the city block behind it is not")
	var wz := 800.0
	var wk := plan.chunk_index_at(Vector2(plan.macro.coast_x(wz) + 20.0, wz))
	_t._check(not LongBeachSand.claims_block(plan, plan.block(wk.x, wk.y).rect), "a west-coast beach block is not (CityChunk._build_beach's)")
	# The waterfront road strip on the block's +Z side lies under the sand for the traffic.
	SandRoads._cache.clear()
	var own := plan.owned_rect(k.x, k.y)
	var rz := plan.road_pos(CityPlan.AXIS_Z, k.y + 1)
	_t._check(own.has_point(Vector2(own.get_center().x, rz)) and SandRoads.on_sand(plan, CityPlan.AXIS_Z, k.y + 1, own.get_center().x),
		"its waterfront road (z %.0f) counts as under the sand" % rz)
	LongBeachSand.enabled = false
	SandRoads._cache.clear()
	var off := SandRoads.on_sand(plan, CityPlan.AXIS_Z, k.y + 1, own.get_center().x)
	LongBeachSand.enabled = true
	SandRoads._cache.clear()
	_t._check(not off, "with LONG_BEACH_SAND=0 that road is open again (the A/B)")


func _profile(plan: CityPlan) -> void:
	var k := _lb_block(plan)
	var own := plan.owned_rect(k.x, k.y)
	var rows: Array = LongBeachSand.rows_at(plan, own, own.get_center().x)
	var ok := rows.size() >= 6
	for i in range(1, rows.size()):
		ok = ok and float(rows[i][0]) < float(rows[i - 1][0])
	var water_ok := false
	for r: Array in rows:
		if is_equal_approx(float(r[0]), plan.macro.bay_z):
			water_ok = is_equal_approx(float(r[1]), CityChunk.SAND_EDGE)
	_t._check(ok and water_ok, "the profile runs seaward to landward with the waterline at bay_z (%d rows)" % rows.size())
	var last: Array = rows[rows.size() - 1]
	_t._check(is_equal_approx(float(last[0]), own.position.y) and float(rows[0][1]) < 0.0,
		"it starts drowned under the sea and ends at the block's landward edge")


func _chunk(city: Node3D, plan: CityPlan) -> void:
	var k := _lb_block(plan)
	var c: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	c.build()
	var sand: MeshInstance3D = null
	for n in c.get_children():
		if n is MeshInstance3D and n.name == "LongBeachSand":
			sand = n
	var ok := sand != null and sand.mesh != null
	if ok and sand.mesh.get_aabb().size.z > 0.0:
		var a := sand.mesh.get_aabb()
		ok = a.position.z <= plan.macro.bay_z and a.end.z >= plan.macro.bay_z and a.end.y < 6.0
	_t._check(ok, "a FULL Long Beach chunk lays its sand across the waterline")
	var palms := 0
	for key in c._mm_nodes.keys():
		if String(key).begins_with("palm_"):
			palms += 1
	_t._check(palms > 0, "with palms on it (%d kinds)" % palms)
	c.queue_free()


func _islands() -> void:
	var src: Array = Rc5OilIslands.sources()
	var ok := src.size() == 16
	for s: Array in src:
		var v: Vector4 = s[0]
		var col: Color = s[1]
		ok = ok and v.z > 0.0 and v.w > col.a and col.r >= 0.0 and col.r < 3.0
	_t._check(ok, "the islands' floods are 16 lit slabs (towers, falls, walls): %d" % src.size())
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ocean.gdshader")
	Rc5OilIslands.push(mat)
	var on := int(mat.get_shader_parameter("isl_count"))
	Rc5OilIslands.enabled = false
	Rc5OilIslands.push(mat)
	var off := int(mat.get_shader_parameter("isl_count"))
	Rc5OilIslands.enabled = true
	_t._check(on == 16 and off == 0, "pushed to the ocean (%d), none with RC5_OIL_ISLANDS=0 (%d)" % [on, off])
	var ocean := FileAccess.get_file_as_string("res://shaders/ocean.gdshader")
	var inc := FileAccess.get_file_as_string("res://shaders/oil_island_mirror.gdshaderinc")
	_t._check(ocean.contains("oil_island_mirror.gdshaderinc") and ocean.contains("if (isl_count > 0 && lamp_factor > 0.01")
		and inc.contains("uniform int isl_count = 0;"), "the ocean mirrors them only after dark and only when pushed")
	var isl := FileAccess.get_file_as_string("res://shaders/oil_island.gdshader")
	_t._check(isl.contains("uniform float dusk_look = 0.0;") and isl.contains("if (dusk_look > 0.5 && v_kind != 9)"),
		"the island shader's dusk look defaults off (the old look bit for bit)")
	_t._check(float(OilIslandBuild.material().get_shader_parameter("dusk_look")) == 1.0, "the island material carries the dusk look")


func _camera() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var found := false
	if parsed is Dictionary:
		for c: Dictionary in parsed.get("cameras", []):
			found = found or (String(c.name) == "oil_islands_dusk" and float(c.hour) == 18.75 and String(c.weather) == "clear")
	_t._check(found, "cameras_w8.json has the oil_islands_dusk row at 18:45 clear")
