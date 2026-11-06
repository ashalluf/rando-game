extends RefCounted
## The memorial park at dawn under the marine layer (Rc5CemeteryDawn, the cemetery_dawn reference
## camera in tools/refcams/cameras_w8.json), for tests/smoke_test.gd. Loaded at run time, not named
## there, so it compiles after the autoloads.
##
## Checks: the camera row (06:30, marine, inside Hollycrest's site); the sun's specular under the
## deck; the photocell hold (on at 06:30 under the deck, gone by 08:00, nothing in a clear dawn);
## the mist's hours and weathers; the mist shader (depth-cut, out of the fog, nothing when off); a
## FULL chunk of the park builds its grass cells and its mist box; RC5_CEMETERY_DAWN=0 puts the
## old look back (no steps, full specular, no hold, no mist).

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var was := Rc5CemeteryDawn.enabled
	Rc5CemeteryDawn.enabled = true
	_pure()
	_shader()
	var plan: CityPlan = city.plan
	_camera(plan)
	_chunk(city, plan)
	Rc5CemeteryDawn.enabled = false
	_t._check(Rc5CemeteryDawn.sun_specular(1.0) == 1.0 and Rc5CemeteryDawn.lamp_hold(1.0, 0.1) == 0.0
		and Rc5CemeteryDawn.mist(6.5, 1.0, 0.0, 0.0) == 0.0,
		"RC5_CEMETERY_DAWN=0: full specular, no lamp hold, no mist")
	Rc5CemeteryDawn.enabled = was


func _pure() -> void:
	_t._check(Rc5CemeteryDawn.sun_specular(0.0) == 1.0 and Rc5CemeteryDawn.sun_specular(1.0) < 0.2,
		"cemetery dawn: a clear sun keeps its highlight, the deck takes it (%.2f)" % Rc5CemeteryDawn.sun_specular(1.0))
	var e630 := sin((6.5 - 6.0) / 12.0 * PI)
	var e800 := sin((8.0 - 6.0) / 12.0 * PI)
	var hold := Rc5CemeteryDawn.lamp_hold(1.0, e630)
	_t._check(hold > 0.15 and hold < Rc5CemeteryDawn.HOLD_LEVEL and Rc5CemeteryDawn.lamp_hold(1.0, e800) == 0.0
		and Rc5CemeteryDawn.lamp_hold(0.0, e630) == 0.0,
		"cemetery dawn: under the deck the lamps are going out at 06:30 (%.2f), off by 08:00, never in a clear dawn" % hold)
	var m := Rc5CemeteryDawn.mist(6.5, 1.0, 0.0, 0.0)
	_t._check(m > 0.9 and Rc5CemeteryDawn.mist(13.0, 1.0, 0.0, 0.0) == 0.0 and Rc5CemeteryDawn.mist(6.5, 0.0, 0.0, 1.0) == 0.0
		and Rc5CemeteryDawn.mist(6.5, 0.0, 0.0, 0.0) < 0.5,
		"cemetery dawn: mist on a marine morning (%.2f), none at noon or in a Santa Ana, thin on a clear dawn" % m)


func _shader() -> void:
	var s := FileAccess.get_file_as_string("res://shaders/cemetery_mist.gdshader")
	_t._check(s.contains("hint_depth_texture") and s.contains("fog_disabled") and s.contains("cull_front")
		and s.contains("amount <= 0.001") and s.contains("color_space.gdshaderinc"),
		"the mist shader: back faces, cut by the depth, out of the fog, nothing when off, linear")
	var d := FileAccess.get_file_as_string("res://scripts/world/day_night.gd")
	_t._check(d.contains("Rc5CemeteryDawn.sun_specular(marine)") and d.contains("Rc5CemeteryDawn.lamp_hold(marine, elevation)")
		and d.contains("Rc5CemeteryDawn.tick("), "DayNight carries the three hooks")


func _row() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	if not data is Dictionary:
		return {}
	for c: Dictionary in data.get("cameras", []):
		if c.name == "cemetery_dawn":
			return c
	return {}


func _camera(plan: CityPlan) -> void:
	var row := _row()
	if row.is_empty():
		_t._check(false, "the cemetery_dawn camera row is in cameras_w8.json")
		return
	var eye: Array = row.eye
	var p := Vector2(float(eye[0]), float(eye[2]))
	var k := plan.block_index_at(p)
	var pl := Cemetery.plan_for(plan, k.x, k.y)
	_t._check(not pl.is_empty() and (pl.site as Rect2).has_point(p) and String(row.weather) == "marine" and absf(float(row.hour) - 6.5) < 0.01,
		"cemetery_dawn: 06:30 marine, the eye inside a memorial park's site (%s)" % [p])


func _chunk(city: Node3D, plan: CityPlan) -> void:
	var row := _row()
	if row.is_empty():
		return
	var eye: Array = row.eye
	var k := plan.block_index_at(Vector2(float(eye[0]), float(eye[2])))
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var mist := chunk.get_node_or_null("CemeteryMist") as MeshInstance3D
	var grass := 0
	for c in chunk.get_children():
		if String(c.name).contains("cemgrass_"):
			grass += 1
	_t._check(mist != null and mist.material_override is ShaderMaterial and grass > 0,
		"cemetery dawn: the park's FULL chunk has its mist box and %d grass cells" % grass)
	chunk.get_parent().remove_child(chunk)
	chunk.free()
