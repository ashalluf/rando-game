extends RefCounted
## The rail_crossing refcam's review (RcRailCrossing, docs/HANDOFF.md "The rail crossing from the
## waiting car"), for tests/smoke_test.gd. Loaded at run time, not named there, so it compiles
## after the autoloads.
##
## The flashers' red held under AgX and their glows following the lamps; the switch putting the
## old gate back; the catenary as camera-facing ribbons; the LRV glass's look5 (default off in the
## shader, on through the train's material); the crossbuck legend; the camera row and its staging
## key. Touches no live system (gates and materials made here and freed).

var _t: Object


func run(t: Object) -> void:
	_t = t
	var was := RcRailCrossing.enabled
	RcRailCrossing.enabled = true
	_lens()
	_gate(true)
	RcRailCrossing.enabled = false
	_gate(false)
	RcRailCrossing.enabled = true
	_wires()
	_glass()
	_camera()
	RcRailCrossing.enabled = was


func _lens() -> void:
	var m := RcRailCrossing.lens_material()
	var e := m.emission
	_t._check(e.g <= 0.15 * e.r and e.b <= e.g and m.emission_energy_multiplier <= 3.0,
		"rc5 rail crossing: a lit flasher is held red (g/r %.2f, energy %.1f): AgX burned the old one white" % [e.g / e.r, m.emission_energy_multiplier])
	var src := FileAccess.get_file_as_string("res://shaders/rc5_flasher_glow.gdshader")
	_t._check(src.contains("af_cover(") and src.contains("blend_add") and src.contains("pow(max(1.0 - r, 0.0)"),
		"rc5 rail crossing: the flasher glow is additive with a coverage alpha and reaches zero at its edge")


func _gate(on: bool) -> void:
	var g := {"base": Vector3.ZERO, "heading": Vector2(0, 1), "right": Vector2(-1, 0), "length": 12.4,
		"node": Vector2i(0, 0), "axis": 0}
	var gate := RailGate.make(g, true)
	var glows: Array = gate.get("_glows")
	var arm_glows: Array = gate.get("_arm_glows")
	if not on:
		_t._check(glows.is_empty() and arm_glows.is_empty() and RailGate.lamp_material(true) != RcRailCrossing.lens_material(),
			"rc5 rail crossing: RC5_RAIL_CROSSING=0 builds the old gate (no glows, the old lens)")
		gate.free()
		return
	_t._check(glows.size() == 2 and arm_glows.size() == 3, "rc5 rail crossing: a glow on each flasher and each arm lamp")
	gate.pose_at(10.0, true)
	_t._check((glows[0] as Node3D).visible and not (glows[1] as Node3D).visible and (arm_glows[0] as Node3D).visible,
		"rc5 rail crossing: closed, the glows follow the alternating lamps and the arm lamps")
	gate.pose_at(10.0, false)
	_t._check(not (glows[0] as Node3D).visible and (glows[1] as Node3D).visible, "rc5 rail crossing: the other lamp's turn")
	gate.pose_at(-120.0, true)
	var any := false
	for n: Node3D in glows + arm_glows:
		any = any or n.visible
	_t._check(not any and gate.lowered < 0.01, "rc5 rail crossing: open, the arm is up and nothing glows")
	gate.free()


func _wires() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/world/light_rail_kit.gd")
	_t._check(src.contains("_ribbons.append(") and src.contains("UtilityPoles.ribbon_mesh(_ribbons)"),
		"rc5 rail crossing: the catenary goes into camera-facing ribbons (tubes broke into dashes)")
	var m := UtilityPoles.ribbon_mesh([[PackedVector3Array([Vector3.ZERO, Vector3(10, 0, 0)]), 0.0065, RcRailCrossing.KIND_CONTACT]])
	_t._check(m != null and m.get_surface_count() == 1, "rc5 rail crossing: a two-point wire makes a ribbon")
	_t._check(RcRailCrossing.crossbuck_words(1.0) == "RAILROAD" and RcRailCrossing.crossbuck_words(-1.0) == "CROSSING",
		"rc5 rail crossing: the crossbuck's legend")


func _glass() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/lrv_glass.gdshader")
	_t._check(src.contains("uniform float look5 = 0.0;") and src.contains("if (look5 > 0.5)"),
		"rc5 rail crossing: lrv_glass's look5 defaults off (the old glass exactly)")
	var mat := LightRailTrain.glass_material()
	_t._check(float(mat.get_shader_parameter("look5")) == 1.0, "rc5 rail crossing: the trains' glass wears look5")


func _camera() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row: Dictionary = {}
	if data is Dictionary:
		for c: Dictionary in data.get("cameras", []):
			if c.get("name", "") == "rail_crossing":
				row = c
	_t._check(not row.is_empty() and String(row.get("rail_cross", "")) != "" and is_equal_approx(float(row.get("hour", 0.0)), 17.5),
		"rc5 rail crossing: the camera row with its rail_cross staging at 17:30")
	var shot := FileAccess.get_file_as_string("res://tools/refcams/refcams_shot.gd")
	_t._check(shot.contains("func _stage_rail_cross("), "rc5 rail crossing: refcams_shot stages rail_cross")
