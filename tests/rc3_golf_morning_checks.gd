extends RefCounted
## The golf course at 08:30 (fleet wave 6, rc3-golf-morning; docs/HANDOFF.md "The golf course at
## 08:30"): checks for tests/smoke_test.gd. CPU and source only (no pixel is read headless):
##   * the golf_morning row is in tools/refcams/cameras_w6.json with its staged group;
##   * GolfLife.force_group puts a group on a hole whatever its roll, and nowhere else;
##   * golf_turf.gdshader's new passes (divots, dew, stripes, bunkers, tone) are all behind the
##     golf_morning global, which project.godot declares; the dew's hours match GolfMorning.dew();
##   * a FULL course chunk plants sycamores and eucalyptus where the firs stood.
## GOLF_MORNING=0 is the A/B: the shader global goes to 0 and the firs come back.

var _t: Node

const EYE := Vector2(39.6, -2858.2)


func run(t: Node, city: Node3D) -> void:
	_t = t
	_camera_row()
	_shader()
	var plan: CityPlan = city.get("plan") if city else null
	var lay := GolfCourse.layout(plan) if plan else {}
	if lay.is_empty():
		_t._check(true, "rc3-golf-morning: no course on this plan (GOLF=0)")
		return
	_group(lay)
	if not GolfMorning.enabled:
		_t._check(true, "rc3-golf-morning: off (GOLF_MORNING=0)")
		return
	_trees(city, plan, lay)


func _camera_row() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w6.json"))
	var found := false
	if data is Dictionary:
		for c: Dictionary in (data as Dictionary).get("cameras", []):
			if String(c.get("name", "")) == "golf_morning":
				found = absf(float(c.eye[0]) - EYE.x) < 0.01 and absf(float(c.eye[2]) - EYE.y) < 0.01 \
					and String(c.get("golf_group", "")).begins_with("9:0") and absf(float(c.hour) - 8.5) < 0.01
	_t._check(found, "rc3-golf-morning: the golf_morning row is in cameras_w6.json behind the 9th tee at 08:30, its group staged")


func _shader() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/golf_turf.gdshader")
	var gated := src.contains("if (golf_morning > 0.5) {\n\t\t\ttc = tee_divots(") and src.contains("golf_morning > 0.5 ? dew_amount(") \
		and src.contains("if (golf_morning > 0.5) {\n\t\tsheen =") and src.contains("if (golf_morning > 0.5) {\n\t\t\tsc = bunker_morning(") \
		and src.contains("if (golf_morning > 0.5) {\n\t\t// golf_morning: no two patches")
	_t._check(gated, "rc3-golf-morning: every new turf pass (divots, dew, stripes, bunkers, tone) is behind golf_morning")
	var proj := FileAccess.get_file_as_string("res://project.godot")
	_t._check(proj.contains("golf_morning={"), "rc3-golf-morning: project.godot declares the golf_morning shader global")
	var d := GolfMorning.DEW_GONE
	var b := GolfMorning.DEW_BACK
	_t._check(src.contains("smoothstep(%.1f, %.1f, h)) * step(3.0, h) + smoothstep(%.1f, %.1f, h)" % [d.x, d.y, b.x, b.y]),
		"rc3-golf-morning: the shader's dew hours are GolfMorning.dew()'s")
	_t._check(GolfMorning.dew(6.0) > 0.99 and GolfMorning.dew(8.5) > 0.9 and GolfMorning.dew(12.0) < 0.01 and GolfMorning.dew(15.0) < 0.01,
		"rc3-golf-morning: dew at dawn and 08:30, none by noon or in the afternoon (%.2f %.2f %.2f)" % [GolfMorning.dew(6.0), GolfMorning.dew(8.5), GolfMorning.dew(12.0)])
	var mg := FileAccess.get_file_as_string("res://shaders/golf_turf.gdshader")
	_t._check(not mg.contains("fwidth(g.x)"), "rc3-golf-morning: the divots' footprint is taken outside the tee's branch")


func _group(lay: Dictionary) -> void:
	var was := GolfLife.force_group
	GolfLife.force_group = ""
	var plain := GolfLife.groups(lay)
	var on9 := false
	for g: Dictionary in plain:
		on9 = on9 or int(g.hole) == 9
	GolfLife.force_group = "9:0:0:3"
	var forced := GolfLife.groups(lay)
	var g9: Dictionary = {}
	for g: Dictionary in forced:
		if int(g.hole) == 9:
			g9 = g
	GolfLife.force_group = was
	var tee: Vector2 = ((((lay.holes as Array)[8] as Dictionary).tees as Array)[0] as Dictionary).c
	var ok := not g9.is_empty() and int(g9.stage) == 0 and (g9.members as Array).size() == 3 \
		and ((g9.members as Array)[0][0] as Vector2).distance_to(tee) < 0.01
	_t._check(ok and forced.size() == plain.size() + (0 if on9 else 1),
		"rc3-golf-morning: GOLF_GROUP=9:0:0:3 puts three golfers on the 9th's back tee and changes no other hole")


func _trees(city: Node3D, plan: CityPlan, lay: Dictionary) -> void:
	var at := Vector2.INF
	for t: Array in lay.trees:
		if int(t[1]) == 4:
			at = t[0]
			break
	if at == Vector2.INF:
		_t._check(true, "rc3-golf-morning: no fir stands on this layout")
		return
	var chunk: CityChunk = city._new_chunk(plan.chunk_index_at(at), CityChunk.Level.FULL)
	chunk.build()
	var la := 0
	for e: Array in chunk.get_meta("la_at", []):
		if int(e[0]) == LaTrees.Species.SYCAMORE or int(e[0]) == LaTrees.Species.EUCALYPTUS:
			la += 1
	var firs := chunk.find_children("Batch_hill_tree_0", "", true, false).size()
	_t._check(la > 0 and firs == 0, "rc3-golf-morning: the course's fir stands are sycamores and eucalyptus (%d planted, %d fir batches)" % [la, firs])
	chunk.get_parent().remove_child(chunk)
	chunk.free()
