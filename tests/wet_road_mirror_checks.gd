extends RefCounted
## The wet road's mirror (WetRoadMirror, shaders/wet_road_mirror.gdshaderinc, docs/HANDOFF.md "The
## wet road's mirror"), for tests/smoke_test.gd. Loaded at run time, not named there.
##
## Holds: road.gdshader includes the streak mirror and still carries the old mirrored_city() for the
## A/B, both only inside the wet-and-lit branch (a dry road never reaches either, so it is bit for
## bit what it was); Forward+ keeps its SSR blend (near_mirror's mirror_forward); the include has no
## sampler (the web's budget) and no screen derivative (it runs in non-uniform control flow) and
## draws nothing in the view's own frame (a pattern there is constant along each view ray: lines
## fanning from the camera); the shader parses with its tunables; the switch sets the global and
## puts it back; project.godot declares the global at 1 and Weather installs it.

var _t: Object


func run(t: Object, _city: Node3D) -> void:
	_t = t
	var road := FileAccess.get_file_as_string("res://shaders/road.gdshader")
	var inc := FileAccess.get_file_as_string("res://shaders/wet_road_mirror.gdshaderinc")
	_t._check(road.contains("#include \"res://shaders/wet_road_mirror.gdshaderinc\""), "wet road mirror: road.gdshader includes it")
	var branch := road.find("if (wet > 0.01 && lamp_factor > 0.05 && ground_detail > 0.5 && side < 0.5)")
	var new_at := road.find("wet_road_mirror_city(")
	var old_at := road.find("city = mirrored_city(r, max(standing, 0.0));")
	_t._check(branch > 0 and new_at > branch and old_at > branch and road.find("if (wet_road_mirror > 0.5)") > branch,
		"wet road mirror: both mirrors sit inside the wet, lit branch (a dry road is untouched)")
	_t._check(road.contains("vec3 mirrored_city(vec3 r, float sharp)"), "wet road mirror: the old mirror is kept for WET_ROAD_MIRROR=0")
	_t._check(road.contains("return k * mirror_forward;") and road.contains("glow += city * gain * near_mirror(length(VERTEX));"),
		"wet road mirror: Forward+ keeps the SSR blend (mirror_forward)")
	_t._check(not inc.contains("sampler") and not inc.contains("texture("), "wet road mirror: the include samples no texture")
	_t._check(not inc.contains("fwidth") and not inc.contains("dFdx") and not inc.contains("dFdy"),
		"wet road mirror: no screen derivative in the include (non-uniform control flow)")
	_t._check(not inc.contains("dot(w, vec2(-v.y"), "wet road mirror: no pattern in the view's own frame")
	_t._check(inc.contains("global uniform float wet_road_mirror;"), "wet road mirror: the switch is a shader global")
	var sh: Shader = load("res://shaders/road.gdshader")
	var names: Array = []
	for u: Dictionary in sh.get_shader_uniform_list():
		names.append(u["name"])
	for k in ["wrm_smear_min", "wrm_smear_max", "wrm_smear_puddle", "wrm_shop_gain", "wrm_glint_size", "mirror_forward", "mirror_windows"]:
		_t._check(names.has(k), "wet road mirror: road.gdshader parses with %s" % k)
	var proj := FileAccess.get_file_as_string("res://project.godot")
	_t._check(proj.contains("wet_road_mirror={\n\"type\": \"float\",\n\"value\": 1.0\n}"), "wet road mirror: project.godot declares the global at 1")
	_t._check(FileAccess.get_file_as_string("res://scripts/world/weather.gd").contains("WetRoadMirror.install()"),
		"wet road mirror: Weather installs the switch")
	# The switch. The headless dummy renderer keeps no shader globals (the get returns null), so
	# the global is only compared where a real renderer holds it.
	var was := WetRoadMirror.enabled
	WetRoadMirror.set_enabled(false)
	var off: Variant = RenderingServer.global_shader_parameter_get("wet_road_mirror")
	var off_flag := WetRoadMirror.enabled
	WetRoadMirror.set_enabled(true)
	var on: Variant = RenderingServer.global_shader_parameter_get("wet_road_mirror")
	var on_flag := WetRoadMirror.enabled
	WetRoadMirror.set_enabled(was)
	_t._check(not off_flag and on_flag, "wet road mirror: the switch turns off and on")
	if off != null and on != null:
		_t._check(float(off) == 0.0 and float(on) == 1.0, "wet road mirror: the switch sets the global (off %s, on %s)" % [off, on])
