extends RefCounted
## Forward+ review i (fleet wave 8, session fwd-review-i), for tests/smoke_test.gd: waves 7-8's look
## work on lavapipe Forward+ against opengl3 (docs/HANDOFF.md "Forward+ review i"). Held here:
## - The jet's landing-light beams (jet_beam.gdshader, unshaded blend_add, ALPHA 1) wrote
##   ALBEDO = tint x level raw: added in display numbers on Compatibility, in linear HDR on Forward+,
##   where the 0.07 faint shaft tuned on the opengl3 stills was a solid cream rod. fi_add()
##   (shaders/fwd_review_i.gdshaderinc, the `fwd_review_i` global) hands it over on Forward+.
## - The runway's edge-light glows (JetTakeoff.infield(): 16 m light_pool quads every edge light)
##   were on light_pool's default linear add: bright blue and cream discs down both edges on the Mac.
##   FwdReviewI.display_pool() puts them on fwd-review-h's display_add_fwd path.
## - The rule for the next one: every wave 7-8 additive quad reviewed hands its amount over on
##   Forward+ (a CURRENT_RENDERER branch, cs_out(), cs_as_uniform() or fi_add()).
## Source text and statics only.

var _t: Node


func _code(p: String) -> String:
	var lines := PackedStringArray()
	for line in FileAccess.get_file_as_string(p).split("\n"):
		lines.append(line.split("//")[0])
	return "\n".join(lines)


func _project_global(name: String) -> float:
	var cfg := ConfigFile.new()
	if cfg.load("res://project.godot") != OK:
		return -1.0
	var v = cfg.get_value("shader_globals", name, null)
	return float((v as Dictionary).get("value", -1.0)) if v is Dictionary else -1.0


func run(t: Node, _city: Node3D) -> void:
	_t = t
	_t._check(FwdReviewI.enabled, "fwd-review-i: the fixes are on (FWD_REVIEW_I unset)")
	_t._check(is_equal_approx(_project_global("fwd_review_i"), 1.0), "the fwd_review_i global defaults on in project.godot")
	_t._check(_code("res://scripts/world/sky_extras.gd").contains("FwdReviewI.apply()"), "SkyExtras sets the fwd_review_i global at load")
	FwdReviewI.apply()
	var inc := _code("res://shaders/fwd_review_i.gdshaderinc")
	_t._check(inc.contains("vec3 fi_add(vec3 c) {\n#if CURRENT_RENDERER == RENDERER_COMPATIBILITY\n\treturn c;")
		and inc.contains("if (fwd_review_i < 0.5) {\n\t\treturn c;") and inc.contains("pow((c + 0.055) / 1.055, vec3(2.4))"),
		"fi_add() is a no-op on Compatibility and with the switch off, the sRGB decode on Forward+")
	var jb := _code("res://shaders/jet_beam.gdshader")
	_t._check(FileAccess.get_file_as_string("res://shaders/jet_beam.gdshader").contains('#include "res://shaders/fwd_review_i.gdshaderinc"')
		and jb.contains("ALBEDO = fi_add(tint * a);") and not jb.contains("ALBEDO = tint * a;"),
		"the jet's landing-light beam is handed over in display numbers on Forward+")
	# The runway's edge-light pools.
	_t._check(_code("res://scripts/vehicles/jet_takeoff.gd").contains("var white := FwdReviewI.display_pool(PropFactory.light_pool(")
		and _code("res://scripts/vehicles/jet_takeoff.gd").contains("var blue := FwdReviewI.display_pool(PropFactory.light_pool("),
		"the runway's edge-light pools (white and blue) go through FwdReviewI.display_pool()")
	var pool := PropFactory.light_pool(Color(1.0, 0.9, 0.72), JetTakeoff.EDGE_POOL_STRENGTH, 3.0)
	FwdReviewI.display_pool(pool)
	var pm := pool.surface_get_material(0) as ShaderMaterial
	_t._check(pm != null and pm.get_shader_parameter("display_add_fwd") == true and pm.get_shader_parameter("display_add") != true,
		"the edge pool adds in display numbers on Forward+ (and keeps the freeway's air ease off)")
	var spare := PropFactory.light_pool(Color(0.29, 0.61, 0.97), 0.73, 1.07)
	FwdReviewI.enabled = false
	FwdReviewI.display_pool(spare)
	var off_v = (spare.surface_get_material(0) as ShaderMaterial).get_shader_parameter("display_add_fwd")
	FwdReviewI.enabled = true
	FwdReviewI.display_pool(spare)
	var on_v = (spare.surface_get_material(0) as ShaderMaterial).get_shader_parameter("display_add_fwd")
	_t._check(off_v != true and on_v == true, "FWD_REVIEW_I=0 leaves the pools on the old linear add")
	# Every wave 7-8 additive quad this review rendered hands its amount over on Forward+.
	var handed := 0
	var adds := ["arena_spill", "suburb_spill", "house_glow", "rc5_hill_spill", "jet_beam", "blast_hot_core",
		"police_wash", "fireworks", "night_wet", "fire_glow", "light_pool"]
	for n: String in adds:
		var c := _code("res://shaders/%s.gdshader" % n)
		if c.contains("blend_add") and (c.contains("CURRENT_RENDERER") or c.contains("cs_linear_renderer()") or c.contains("cs_out(") or c.contains("fi_add(") or c.contains("cs_as_uniform(")):
			handed += 1
		else:
			_t._check(false, "fwd-review-i: %s.gdshader is additive and hands nothing over on Forward+" % n)
	_t._check(handed == adds.size(), "the wave 7-8 additive quads hand their amount over on Forward+ (%d of %d)" % [handed, adds.size()])
