extends RefCounted
## The construction site at dusk (refcam5 construction_dusk; docs/HANDOFF.md "The construction site
## at dusk", ConstructionDusk): checks for tests/smoke_test.gd. CPU only (no pixel is read headless):
##   * the construction_dusk row is in tools/refcams/cameras_w8.json at 18:45 clear, looking at the
##     tower site of the block it frames;
##   * the late shift: the crews work at 18:45 and are gone at 22:00, and with the switch off the
##     day's hours are exactly as before;
##   * the site material carries the dusk glass and the printed posters (the paper atlas set);
##   * a FULL build of the site: two more hands at the gate (on the ground, no paddle), workers
##     really spawned at 18:45, the work lights' glow billboards on the lights mesh, and (desktop)
##     the deck's OmniLights in `lamp_light`.
## CONSTRUCTION_DUSK=0 is the A/B.

var _t: Node

## The tower the camera frames (block 30,0 on the default seed).
const SITE_AT := Vector2(3357.6, 100.1)


func run(t: Node, city: Node3D) -> void:
	_t = t
	_camera_row()
	if not ConstructionDusk.enabled:
		_t._check(not ConstructionDusk.late(18.75), "rc5-construction-dusk: off (CONSTRUCTION_DUSK=0), no late shift")
		return
	_hours()
	var mat := ConstructionKit.material()
	_t._check(bool(mat.get_shader_parameter("dusk_glass")) and bool(mat.get_shader_parameter("printed_posters"))
		and mat.get_shader_parameter("paper_atlas") is Texture2D,
		"rc5-construction-dusk: the site material has the dusk glass and the printed posters (paper atlas set)")
	var plan: CityPlan = city.get("plan") if city else null
	if plan == null:
		return
	var k := plan.block_index_at(SITE_AT)
	if Construction.tower_site(plan, k.x, k.y).is_empty():
		_t._check(true, "rc5-construction-dusk: no tower site at the camera on this seed")
		return
	_full_chunk(city, k)


func _camera_row() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var found := false
	if data is Dictionary:
		for c: Dictionary in (data as Dictionary).get("cameras", []):
			if String(c.get("name", "")) == "construction_dusk":
				var eye := Vector2(float(c.eye[0]), float(c.eye[2]))
				var to := SITE_AT - eye
				var yaw := rad_to_deg(atan2(-to.x, -to.y))
				found = absf(float(c.hour) - 18.75) < 0.01 and String(c.get("weather", "")) == "clear" \
					and eye.distance_to(SITE_AT) < 120.0 and absf(wrapf(yaw - float(c.eye[3]), -180.0, 180.0)) < 25.0
	_t._check(found, "rc5-construction-dusk: the construction_dusk row is in cameras_w8.json at 18:45 clear, aimed at the site")


func _hours() -> void:
	var saved: float = Construction.force_hour
	Construction.force_hour = 18.75
	var dusk := Construction.working(null)
	Construction.force_hour = 22.0
	var night := Construction.working(null)
	Construction.force_hour = 12.0
	var noon := Construction.working(null)
	ConstructionDusk.enabled = false
	Construction.force_hour = 18.75
	var off := Construction.working(null)
	ConstructionDusk.enabled = true
	Construction.force_hour = saved
	_t._check(dusk and noon and not night and not off,
		"rc5-construction-dusk: the late shift works at 18:45 (noon %s, 22:00 %s, the switch off %s)" % [noon, night, off])


func _full_chunk(city: Node3D, k: Vector2i) -> void:
	var saved_hour: float = Construction.force_hour
	Construction.force_hour = 18.75
	var cap: int = city.get("max_pedestrians")
	city.set("max_pedestrians", maxi(cap, -CityChunk.count_crowd_room(city.get_tree(), 0)) + 200)
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	city.set("max_pedestrians", cap)
	Construction.force_hour = saved_hour
	var crew: Array = (chunk.get_meta("construction") as Dictionary).workers
	var gate_hands := crew.filter(func(w: Dictionary) -> bool: return float(w.lift) < 0.5 and not bool(w.paddle) and not bool(w.deck))
	_t._check(gate_hands.size() >= 2, "rc5-construction-dusk: two more of the crew stand at the gate (%d)" % gate_hands.size())
	var spawned := chunk.get_children().filter(func(n: Node) -> bool: return n is ConstructionWorker).size()
	_t._check(spawned >= 3, "rc5-construction-dusk: the late crew is out at 18:45 (%d workers)" % spawned)
	var lights := chunk.get_node_or_null("ConstructionLights") as MeshInstance3D
	var glows := 0
	if lights and lights.mesh:
		var cols: PackedColorArray = lights.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		for i in range(0, cols.size(), 6):
			if cols[i].g > 0.5:
				glows += 1
	_t._check(glows >= 8, "rc5-construction-dusk: the work lights glow on the lights mesh (%d warm billboards)" % glows)
	var omnis := chunk.get_children().filter(func(n: Node) -> bool: return n is OmniLight3D and n.name.begins_with("DuskWorkLight") and n.is_in_group("lamp_light"))
	_t._check(OS.has_feature("web") or omnis.size() >= 1, "rc5-construction-dusk: the deck's work lights are lamp_light omnis (%d)" % omnis.size())
	chunk.get_parent().remove_child(chunk)
	chunk.free()
