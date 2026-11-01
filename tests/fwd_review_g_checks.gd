extends RefCounted
## Forward+ review g (fleet wave 5, session fwd-review-g), for tests/smoke_test.gd: wave 4's look
## work on lavapipe Forward+ against opengl3 (docs/HANDOFF.md "Forward+ review g"). Held here:
## - Under a closed deck (rain, a storm) the Forward+ cloud volume's march gave up past 90 km, a
##   degree over the horizon, and the city's light dome showed under it in its own saturated
##   orange: a hard line along the horizon on the Mac. sky.gdshader's `far_deck` hands the deck
##   out there over as its haze (airlight), and the half-res pass runs under the horizon while the
##   deck is closed and the camera is under it. FwdReviewG.apply_sky() sets it (FWD_REVIEW_G=0).
## - The room traced behind every pane (offices, homes, shops) is written in display numbers into
##   building.gdshader's renderer-space albedo: Forward+ read it as linear, so by day every window
##   was a pale panel nearly as light as the wall. It is decoded there (fx_srgb_in()) behind the
##   `fwd_review_g` global, and the far box's stand-ins for it (building_lod.gdshader fg_room()).
## Source text and statics only, plus the city's own sky material when there is one.

var _t: Node


func _code(p: String) -> String:
	var lines := PackedStringArray()
	for line in FileAccess.get_file_as_string(p).split("\n"):
		lines.append(line.split("//")[0])
	return "\n".join(lines)


func _uniform(code: String, name: String) -> float:
	var m := RegEx.create_from_string("uniform float " + name + " = ([0-9.]+);").search(code)
	return m.get_string(1).to_float() if m != null else -1.0


func _project_global(name: String) -> float:
	var cfg := ConfigFile.new()
	if cfg.load("res://project.godot") != OK:
		return -1.0
	var v = cfg.get_value("shader_globals", name, null)
	return float((v as Dictionary).get("value", -1.0)) if v is Dictionary else -1.0


func run(t: Node, city: Node3D) -> void:
	_t = t
	_t._check(FwdReviewG.enabled, "fwd-review-g: the fixes are on (FWD_REVIEW_G unset)")
	var sky := _code("res://shaders/sky.gdshader")
	_t._check(is_equal_approx(_uniform(sky, "far_deck"), 1.0), "the sky's far deck hand-over defaults on")
	# The march's cut-off branch hands a closed deck over as its haze, only from under the deck.
	var cut := sky.find("t0 > 90.0) {")
	var branch := sky.find("if (far_deck > 0.5 && h0 > 0.0) {", cut)
	_t._check(cut > 0 and branch > cut and branch - cut < 400, "past the march's 90 km reach a deck seen from under it is handed over")
	var body := sky.substr(branch, 220)
	_t._check(body.contains("smoothstep(0.72, 0.95, coverage)") and body.contains("return vec4(airlight * s, 1.0 - s);"),
		"it is the deck's airlight at the stratus share (the volume's own strat ramp)")
	_t._check(sky.contains("smoothstep(0.72, 0.95, coverage)") and sky.find("float strat = smoothstep(0.72, 0.95, coverage);") > 0,
		"the hand-over and the volume's stratus ceiling close at the same coverage")
	_t._check(sky.contains("if (volume && (up > -0.08 || (far_deck > 0.5 && cloud_coverage > 0.72 && view_km.y < cloud_base - 0.06 * cloud_depth))) {"),
		"the half-res pass runs under the horizon only for a closed deck seen from under it")
	# Continuity: the march's own aerial haze at its 90 km reach is nearly all airlight already, so
	# handing over to airlight there draws no line.
	var haze_km := _uniform(sky, "cloud_haze_km")
	var hz := 1.0 - exp(-90.0 / maxf(haze_km, 0.01))
	_t._check(haze_km > 0.0 and hz > 0.85, "the march's far deck is %.0f %% haze where it hands over" % (hz * 100.0))
	# The switch.
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/sky.gdshader")
	FwdReviewG.apply_sky(mat)
	var on := float(mat.get_shader_parameter("far_deck"))
	FwdReviewG.enabled = false
	FwdReviewG.apply_sky(mat)
	var off := float(mat.get_shader_parameter("far_deck"))
	FwdReviewG.enabled = true
	FwdReviewG.apply_sky(mat)
	_t._check(is_equal_approx(on, 1.0) and is_equal_approx(off, 0.0), "FWD_REVIEW_G=0 puts the old cut back (%.0f / %.0f)" % [on, off])
	_t._check(_code("res://scripts/world/sky_extras.gd").contains("FwdReviewG.apply_sky(_sky)"), "SkyExtras hands the sky its far deck")
	# The room behind the pane: decoded on Forward+ in the near shader, its stand-ins in the far one.
	var b := _code("res://shaders/building.gdshader")
	var dec := b.find("room = fx_srgb_in(room);")
	_t._check(b.contains("global uniform float fwd_review_g;") and dec > b.find("room *= expose") and dec < b.find("dmg_room = room;"),
		"the near pane's room is decoded after its exposure and before the albedo takes it")
	_t._check(b.find("room_raw = room;") < dec, "the lit room's emission keeps its own numbers (room_raw is taken before the decode)")
	var fx := _code("res://shaders/facade_variety.gdshaderinc")
	_t._check(fx.contains("vec3 fx_srgb_in(vec3 c) {\n#if CURRENT_RENDERER == RENDERER_COMPATIBILITY\n\treturn c;"),
		"fx_srgb_in() is a no-op on Compatibility (the web and every opengl3 still are untouched)")
	var lod := _code("res://shaders/building_lod.gdshader")
	_t._check(lod.contains("return fwd_review_g > 0.5 ? cs_as_uniform(c) : c;") and lod.count("fg_room(") >= 5,
		"the far pane's office, shop, blind and home-cover stand-ins follow the near room (%d)" % lod.count("fg_room("))
	_t._check(_project_global("fwd_review_g") == 1.0, "project.godot declares the fwd_review_g global at 1")
	# The city's own sky material.
	var we: WorldEnvironment = city.get_node_or_null("WorldEnvironment") if city else null
	if we and we.environment and we.environment.sky and we.environment.sky.sky_material is ShaderMaterial:
		var sm := we.environment.sky.sky_material as ShaderMaterial
		_t._check(is_equal_approx(float(sm.get_shader_parameter("far_deck")), 1.0), "the city's sky hands its far deck over")
