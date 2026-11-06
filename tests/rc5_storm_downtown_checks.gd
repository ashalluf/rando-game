extends RefCounted
## The storm_downtown refcam's review (RcStorm, docs/HANDOFF.md "The thunderstorm downtown"), for
## tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## The switch and what it puts back; the night flash's light, the sky's flash in its cubemap pass,
## its colour and spread; the storm curtain's night veil, sheets and thin streaks; the lamp streaks'
## storm break-up; the litter; every new shader uniform's default being the old look; the camera
## row and its staging key. Touches no live system (materials made here, Weather's read only).

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	var was := RcStorm.enabled
	RcStorm.enabled = true
	_numbers()
	_switch()
	_shaders(city)
	_camera()
	RcStorm.enabled = was


func _numbers() -> void:
	var R := RcStorm
	_t._check(R.light_gain(0.0) == 1.0 and R.cube_gain(0.0) == 1.0,
		"rc5 storm: a day flash keeps its light and its sky")
	_t._check(R.light_gain(1.0) < 0.5 and R.light_gain(1.0) > 0.05 and R.cube_gain(1.0) < 0.5,
		"rc5 storm: a night flash lights the street at %.2f and the cubemap at %.2f of before" % [R.light_gain(1.0), R.cube_gain(1.0)])
	var sky := ShaderMaterial.new()
	sky.shader = load("res://shaders/sky.gdshader")
	sky.set_shader_parameter("flash_spread", 0.3)
	R.dress_sky(sky, 1.0)
	var col: Vector3 = sky.get_shader_parameter("flash_color")
	_t._check(float(sky.get_shader_parameter("flash_spread")) < 0.3 and col.x < col.z and col.x < R.DAY_FLASH_COLOR.x,
		"rc5 storm: the night sky's flash is tighter round the strike and colder")
	var cur := ShaderMaterial.new()
	R.dress_curtain(cur, 1.0, true)
	_t._check(float(cur.get_shader_parameter("night_veil")) < 1.0 and float(cur.get_shader_parameter("night_sheets")) < 1.0
		and float(cur.get_shader_parameter("thin")) > 0.5, "rc5 storm: the inner curtain at night: less veil, softer sheets, thin streaks")
	R.dress_curtain(cur, 1.0, false)
	_t._check(float(cur.get_shader_parameter("thin")) == 0.0, "rc5 storm: the outer curtain keeps its streak width")
	R.dress_curtain(cur, 0.0, true)
	_t._check(float(cur.get_shader_parameter("night_veil")) == 1.0 and float(cur.get_shader_parameter("night_sheets")) == 1.0
		and float(cur.get_shader_parameter("thin")) == 0.0, "rc5 storm: plain rain (storm weight 0) keeps the curtain as it was")
	_t._check(R.litter_rise(0.3) < 0.3 and R.litter_size(0.24) < 0.24, "rc5 storm: the litter skitters low and small")


func _switch() -> void:
	var R := RcStorm
	R.enabled = false
	var sky := ShaderMaterial.new()
	sky.shader = load("res://shaders/sky.gdshader")
	sky.set_shader_parameter("flash_spread", 0.3)
	R.dress_sky(sky, 1.0)
	var cur := ShaderMaterial.new()
	R.dress_curtain(cur, 1.0, true)
	_t._check(R.light_gain(1.0) == 1.0 and R.cube_gain(1.0) == 1.0 and float(sky.get_shader_parameter("flash_cube")) == 1.0
		and sky.get_shader_parameter("flash_color") == R.DAY_FLASH_COLOR and is_equal_approx(float(sky.get_shader_parameter("flash_spread")), 0.3)
		and float(cur.get_shader_parameter("night_veil")) == 1.0 and float(cur.get_shader_parameter("night_sheets")) == 1.0
		and float(cur.get_shader_parameter("thin")) == 0.0 and R.litter_rise(0.3) == 0.3 and R.litter_size(0.24) == 0.24,
		"rc5 storm: off, every number is the old one")
	R.dress_streaks(1.0)
	_t._check(float(NightAtmos.atmos_material("wet").get_shader_parameter("storm")) == 0.0,
		"rc5 storm: off, the lamp streaks are not broken up")
	R.enabled = true
	R.dress_streaks(1.0)
	_t._check(float(NightAtmos.atmos_material("wet").get_shader_parameter("storm")) == 1.0,
		"rc5 storm: on, a storm breaks the lamp streaks")
	R.dress_streaks(0.0)


func _shaders(city: Node3D) -> void:
	var sky := FileAccess.get_file_as_string("res://shaders/sky.gdshader")
	_t._check(sky.contains("uniform float flash_cube = 1.0;") and sky.contains("uniform vec3 flash_color = vec3(0.8, 0.85, 1.0);")
		and sky.contains("(AT_CUBEMAP_PASS ? flash_cube : 1.0)"), "rc5 storm: the sky's flash is the old one by default")
	var wet := FileAccess.get_file_as_string("res://shaders/night_wet.gdshader")
	_t._check(wet.contains("uniform float storm = 0.0;") and wet.contains("if (storm > 0.0)"),
		"rc5 storm: the lamp streak is the old one by default (storm 0)")
	var weather := city.get_node_or_null("Weather") if city else null
	var mat: ShaderMaterial = weather.get("_curtain_mat") if weather else null
	if mat == null:
		_t._check(true, "rc5 storm: no curtain in this build (curtain checks skipped)")
		return
	var code := mat.shader.code
	_t._check(code.contains("uniform float night_veil = 1.0;") and code.contains("uniform float night_sheets = 1.0;")
		and code.contains("uniform float thin = 0.0;"), "rc5 storm: Weather's curtain keeps the old look by default")


func _camera() -> void:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row: Dictionary = {}
	if d is Dictionary:
		for c: Dictionary in d.get("cameras", []):
			if String(c.get("name", "")) == "storm_downtown":
				row = c
	_t._check(not row.is_empty() and String(row.get("weather", "")) == "storm" and row.get("storm_flash") is Dictionary
		and row.get("street_cars") is Dictionary, "rc5 storm: the storm_downtown camera row (storm, a held strike, staged traffic)")
	var shot := FileAccess.get_file_as_string("res://tools/refcams/refcams_shot.gd")
	_t._check(shot.contains("func _stage_storm_flash(") and shot.contains("func _release_storm_flash("),
		"rc5 storm: refcams_shot stages and releases the held strike")
