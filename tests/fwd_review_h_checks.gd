extends RefCounted
## Forward+ review h (fleet wave 8, session fwd-review-h), for tests/smoke_test.gd: waves 6-7's look
## work on lavapipe Forward+ against opengl3 (docs/HANDOFF.md "Forward+ review h"). Held here:
## - CloudShadows (Forward+ desktop only) read the sky's cloud parameters as float(...) while
##   SkyExtras had not set them yet: null, a script error every frame until it had. It reads them
##   through FwdReviewH.param() now.
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
