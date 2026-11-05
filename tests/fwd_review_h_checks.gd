extends RefCounted
## Forward+ review h (fleet wave 8, session fwd-review-h), for tests/smoke_test.gd: waves 6-7's look
## work on lavapipe Forward+ against opengl3 (docs/HANDOFF.md "Forward+ review h"). Held here:
## - CloudShadows (Forward+ desktop only) read the sky's cloud parameters as float(...) while
##   SkyExtras had not set them yet: null, a script error every frame until it had. It reads them
##   through FwdReviewH.param() now.
## - The bonfires' firelight pool and the landing lights' pool on the runway are broad additive
##   pools on light_pool.gdshader's default path, which adds the tint in linear HDR on Forward+: the
##   pool's faint tail, a few % of its centre, showed several times stronger on the Mac than in the
##   opengl3 stills, and the fire's pool spread into an orange carpet over the whole beach. They take
##   `display_add_fwd` (FwdReviewH.display_pool()): the display-number add on Forward+ only.
## Source text and statics only.

var _t: Node


func _code(p: String) -> String:
	var lines := PackedStringArray()
	for line in FileAccess.get_file_as_string(p).split("\n"):
		lines.append(line.split("//")[0])
	return "\n".join(lines)


func run(t: Node, _city: Node3D) -> void:
	_t = t
	_t._check(FwdReviewH.enabled, "fwd-review-h: the fixes are on (FWD_REVIEW_H unset)")
	# An unset shader parameter reads null; param() hands back the fallback, a set one its number.
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/sky.gdshader")
	var unset := FwdReviewH.param(mat, "cloud_volume", -7.0)
	mat.set_shader_parameter("cloud_volume", 1.0)
	var set_v := FwdReviewH.param(mat, "cloud_volume", -7.0)
	_t._check(is_equal_approx(set_v, 1.0) and (is_equal_approx(unset, -7.0) or is_equal_approx(unset, 0.0)),
		"FwdReviewH.param() reads a set parameter (%.1f) and survives an unset one (%.1f)" % [set_v, unset])
	_t._check(is_equal_approx(FwdReviewH.param(null, "x", 3.0), 3.0), "FwdReviewH.param() survives no material")
	var cs := _code("res://scripts/world/cloud_shadows.gd")
	_t._check(not cs.contains("float(_sky.get_shader_parameter(\"cloud_volume\"))")
		and not cs.contains("float(_sky.get_shader_parameter(\"cloud_coverage\"))")
		and cs.contains("FwdReviewH.param(_sky, \"cloud_volume\")"),
		"CloudShadows reads the sky's cloud parameters through FwdReviewH.param() (no float(null) errors)")
	# The pools: added in display numbers on Forward+ only, the switch, the hooks.
	var lp := _code("res://shaders/light_pool.gdshader")
	_t._check(lp.contains("uniform bool display_add_fwd = false;") and lp.contains("} else if (display_add || display_add_fwd) {"),
		"light_pool.gdshader: display_add_fwd takes the display-number add")
	var fwd_at := lp.find("#if CURRENT_RENDERER != RENDERER_COMPATIBILITY", lp.find("void fragment()"))
	_t._check(fwd_at > 0 and lp.find("display_add_fwd", fwd_at) > fwd_at and lp.count("display_add_fwd") == 2,
		"display_add_fwd is read only in the Forward+ branch (Compatibility, the web and the stills untouched)")
	var m := Bonfires.pool_mesh()
	var pm := m.surface_get_material(0) as ShaderMaterial
	_t._check(pm != null and pm.get_shader_parameter("display_add_fwd") == true and pm.get_shader_parameter("display_add") != true,
		"the bonfire's pool adds in display numbers on Forward+ (and keeps the freeway's air ease off)")
	var lod := (Bonfires.pool_mesh(false).surface_get_material(0) as ShaderMaterial)
	_t._check(lod != null and lod.get_shader_parameter("display_add_fwd") == true, "so does the far pool a LOD chunk lays")
	_t._check(_code("res://scripts/world/airport_night.gd").contains("FwdReviewH.display_pool(PropFactory.light_pool(Color(1.0, 0.95, 0.84), LANDING_POOL_STRENGTH"),
		"the landing lights' pool goes through FwdReviewH.display_pool()")
	var spare := PropFactory.light_pool(Color(0.31, 0.62, 0.93), 0.77, 1.11)
	FwdReviewH.enabled = false
	FwdReviewH.display_pool(spare)
	var off_v = (spare.surface_get_material(0) as ShaderMaterial).get_shader_parameter("display_add_fwd")
	FwdReviewH.enabled = true
	FwdReviewH.display_pool(spare)
	var on_v = (spare.surface_get_material(0) as ShaderMaterial).get_shader_parameter("display_add_fwd")
	_t._check(off_v != true and on_v == true, "FWD_REVIEW_H=0 leaves the pools on the old linear add")
