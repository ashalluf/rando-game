extends RefCounted
## Spring St at 16:00 (the historic_core reference camera in tools/refcams/cameras_w8.json;
## HistoricCore.look2), for tests/smoke_test.gd. Loaded at run time, not named there, so it compiles
## after the autoloads.
##
## Checks: the camera row (16:00 clear, on Spring St's pavement inside the historic stretch);
## building.gdshader's wall_detail path (off by default); a historic block built FULL: every front
## in the plaster or brick set with the texture as detail (flat ones), weathering capped, fewer
## window units, the darker brick, and the fronts along the avenue closing the street wall (no gap
## between two neighbouring fronts) with no fire escape on a party wall; the far boxes take a
## detail wall at its colour (set 15); RC5_HISTORIC=0 builds the old fronts.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_camera()
	_shader()
	var was := HistoricCore.look2
	HistoricCore.look2 = true
	var k := _block(plan)
	if k == Vector2i(-9999, -9999):
		_t._check(false, "rc5 historic core: a Spring St block with fronts in a column")
		HistoricCore.look2 = was
		return
	_full(city, plan, k)
	HistoricCore.look2 = false
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var old_ok := true
	var n := 0
	for c in chunk.get_children():
		if c is Building and (c as Node).has_meta("historic"):
			var b := c as Building
			n += 1
			old_ok = old_ok and b.wall_set_force.is_empty() and b.wall_detail_force < 0.0 and b.escape_faces_off.is_empty()
	_t._check(old_ok and n > 0, "RC5_HISTORIC=0: the old fronts (%d, no forced wall, detail or party walls)" % n)
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	HistoricCore.look2 = was


func _camera() -> void:
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row: Dictionary = {}
	for c: Dictionary in table.get("cameras", []):
		if String(c.get("name", "")) == "historic_core":
			row = c
	var ok := not row.is_empty()
	if ok:
		var eye: Array = row.eye
		var spring := HistoricCore.avenue("SPRING ST")
		var zr := HistoricCore.z_range()
		ok = absf(float(row.hour) - 16.0) < 0.01 and String(row.weather) == "clear" and not spring.is_empty() \
			and absf(float(eye[0]) - float(spring[0])) < float(spring[1]) * 0.5 + 6.0 and float(eye[2]) > zr.x and float(eye[2]) < zr.y
	_t._check(ok, "historic_core camera: 16:00 clear on Spring St's pavement in the historic stretch")


func _shader() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/building.gdshader")
	_t._check(src.contains("uniform float wall_detail = -1.0") and src.contains("wall_detail >= 0.0 && use_wall_texture"),
		"building.gdshader: a FLAT wall's texture as detail round its colour, off by default")
	var sw := FileAccess.get_file_as_string("res://shaders/street_wear.gdshader")
	var swg := FileAccess.get_file_as_string("res://scripts/world/street_wear.gd")
	_t._check(sw.contains("uniform float stain_soft = 0.0") and sw.contains("if (stain_soft > 0.0)") and swg.contains("\"stain_soft\""),
		"street_wear.gdshader: the pavement's stains soak in (stain_soft), the old stain at 0")


## A Spring St block whose plan has two fronts touching in one column (the stretch's middle first).
func _block(plan: CityPlan) -> Vector2i:
	var av := HistoricCore.avenue("SPRING ST")
	var zr := HistoricCore.z_range()
	var z := (zr.x + zr.y) * 0.5
	for dz: float in [0.0, -200.0, 200.0, -400.0, 400.0]:
		for side: float in [1.0, -1.0]:
			var bi := plan.block_index_at(Vector2(float(av[0]) + side * 30.0, z + dz))
			var fronts := 0
			for lot: Dictionary in plan.lots(bi.x, bi.y):
				if HistoricCore.closes_wall(plan, bi.x, bi.y, lot):
					fronts += 1
			if fronts >= 2:
				return bi
	return Vector2i(-9999, -9999)


func _full(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var hist: Array[Building] = []
	for c in chunk.get_children():
		if c is Building and (c as Node).has_meta("historic"):
			hist.append(c as Building)
	var ok := not hist.is_empty()
	var why := ""
	var bricks := 0
	var flats := 0
	for b in hist:
		var spec: Dictionary = b.get_meta("historic")
		var set_ok := b.wall_set_force.size() == 2 and String(b.wall_set_force[0]) == ("brick_red" if spec.brick else "plaster_white")
		var detail_ok := b.wall_detail_force == (HistoricCore.WALL_DETAIL_BRICK if spec.brick else HistoricCore.WALL_DETAIL_2) and b.weathering_cap == HistoricCore.WEATHERING_2 \
			and b.kit_ac_chance == HistoricCore.AC_CHANCE_2
		if spec.brick:
			bricks += 1
			set_ok = set_ok and HistoricCore.PRESSED_BRICK_2.has(b.palette_override[0]) and b.palette_override.size() == HistoricCore.PRESSED_BRICK_2.size()
		else:
			flats += 1
		var mat := b._part_mat
		set_ok = set_ok and mat != null and absf(float(mat.get_shader_parameter("wall_detail")) - b.wall_detail_force) < 0.001
		# Its far boxes take the wall at the facade colour (set 15 in the code).
		var boxes := FarBuilding.boxes(b, b.plan_only(), 0.0)
		if not boxes.is_empty():
			var xf: Transform3D = boxes[0][0]
			set_ok = set_ok and int(FarBuilding.decode(xf.basis).wall_set) == 15
		if not (set_ok and detail_ok) and why == "":
			why = "%s set %s detail %.2f cap %.2f ac %.3f" % [spec.name, str(b.wall_set_force), b.wall_detail_force, b.weathering_cap, b.kit_ac_chance]
		ok = ok and set_ok and detail_ok
	_t._check(ok, "rc5 historic core: %d fronts (%d brick, %d stone) in the ornament's stone or the darker brick, fewer window units %s" % [hist.size(), bricks, flats, why])
	# The street wall: two fronts whose cells touch stand wall to wall.
	var pairs := 0
	var gaps := 0
	var escapes_ok := true
	for a in hist:
		var ra := _rect(a)
		for b in hist:
			if a == b:
				continue
			var rb := _rect(b)
			if absf(ra.get_center().x - rb.get_center().x) > 0.5 or rb.position.y < ra.position.y:
				continue
			var gap := rb.position.y - ra.end.y
			if gap < 6.0:
				pairs += 1
				if gap > 0.2:
					gaps += 1
		for i in a.escape_faces_off:
			escapes_ok = escapes_ok and (i == 2 or i == 3)
	_t._check(pairs >= 1 and gaps == 0 and escapes_ok,
		"rc5 historic core: the street wall is closed (%d neighbouring fronts, %d with a gap), no fire escape on a party wall" % [pairs, gaps])
	chunk.get_parent().remove_child(chunk)
	chunk.free()


## A front's footprint in the plan (x, z).
func _rect(b: Building) -> Rect2:
	var p: Vector3 = b.parts[0].center
	var s: Vector3 = b.parts[0].size
	return Rect2(Vector2(b.position.x + p.x - s.x * 0.5, b.position.z + p.z - s.z * 0.5), Vector2(s.x, s.z))
