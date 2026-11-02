extends RefCounted
## The rainy night street's refcam review (RainStreetNight, docs/HANDOFF.md "The rainy night street,
## refcam review"), for tests/smoke_test.gd. Loaded at run time, not named there, so it compiles
## after the autoloads.
##
## The switch and what it puts back (every new shader path behind a uniform whose default is the old
## look); the lamp streak and the lit rain in the cones on NightAtmos' materials; the rain curtain's
## night look baked into Weather's shader; the refracting lens drops; the drops' night glow; the
## overcast night sky's numbers; and WetCarGlints: four lamps a car where the body's lamps are, a
## head lamp mirrored only toward the eye in front of it and a tail lamp only behind, nothing by day
## or on a dry road. Stages its own car and puts everything back.

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	var was := RainStreetNight.enabled
	RainStreetNight.enabled = true
	_switch()
	_shaders()
	_weather(city)
	_sky()
	await _glints(city)
	RainStreetNight.enabled = was


func _switch() -> void:
	var R := RainStreetNight
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/night_wet.gdshader")
	R.dress_wet(m)
	_t._check(float(m.get_shader_parameter("look2")) == 1.0, "rain night: the lamp streak's new look is on")
	R.enabled = false
	R.dress_wet(m)
	_t._check(float(m.get_shader_parameter("look2")) == 0.0 and R.curtain_night_code() == "0.0" and R.lens_shader() == null
		and R.drop_glow(1.0) == R.DROP_GLOW_DAY and R.storm_glow_gain() == 1.0 and R.overcast_cloud_light() == R.OVERCAST_CLOUD_OLD
		and R.storm_top(Color(0.1, 0.2, 0.3), 1.0) == Color(0.1, 0.2, 0.3),
		"rain night: off, every number and shader is the old one")
	R.enabled = true
	_t._check(R.drop_glow(0.0) == R.DROP_GLOW_DAY and R.drop_glow(1.0) < R.DROP_GLOW_DAY and R.drop_glow(1.0) > 0.0,
		"rain night: the drops keep their day glow and lose most of it at night (%.2f)" % R.drop_glow(1.0))
	var mat := NightAtmos.atmos_material("wet")
	_t._check(float(mat.get_shader_parameter("look2")) == 1.0, "rain night: NightAtmos' wet material wears the new streak")
	var sh := NightAtmos.atmos_material("shaft")
	_t._check(float(sh.get_shader_parameter("look2")) == 1.0, "rain night: NightAtmos' shaft material draws the lit rain")


func _shaders() -> void:
	for path: String in ["res://shaders/night_wet.gdshader", "res://shaders/night_shaft.gdshader"]:
		var src := FileAccess.get_file_as_string(path)
		_t._check(src.contains("uniform float look2 = 0.0;") and src.contains("if (look2 > 0.5)"),
			"rain night: %s keeps the old look by default (look2 0)" % path.get_file())
	var shaft := FileAccess.get_file_as_string("res://shaders/night_shaft.gdshader")
	# The lit rain stays where the cone's glow is Forward+'s volumetric fog's (night_atmos.y 0).
	_t._check(shaft.contains("float amp = amp0 * night_atmos.y;") and shaft.contains("v_ramp * rain2"),
		"rain night: the cone's lit rain does not need the drawn shaft")
	var lens := FileAccess.get_file_as_string("res://shaders/rain_lens.gdshader")
	_t._check(lens.contains("hint_screen_texture") and lens.contains("uniform float strength") and not lens.contains("instance uniform"),
		"rain night: the lens drops refract the frame (strength driven by Weather)")


func _weather(city: Node3D) -> void:
	var w: Node = city.get_node_or_null("Weather")
	if w == null:
		_t._check(false, "rain night: the city has a Weather")
		return
	var cm: ShaderMaterial = w.get("_curtain_mat")
	_t._check(cm != null and cm.shader.code.contains("uniform float night_look = 1.0;") and cm.shader.code.contains("global uniform float lamp_factor;"),
		"rain night: the rain curtain fades to the city's light at night")
	var lm: ShaderMaterial = w.get("_lens_mat")
	_t._check(lm != null and lm.shader != null and lm.shader.resource_path == "res://shaders/rain_lens.gdshader",
		"rain night: the lens drops are the refracting ones")


func _sky() -> void:
	var R := RainStreetNight
	var top := Color(0.045, 0.042, 0.045)
	var lit := R.storm_top(top, 1.0)
	_t._check(is_equal_approx(lit.r, top.r * R.STORM_TOP_GAIN) and R.storm_top(top, 0.0) == top,
		"rain night: the overcast night zenith takes the city's light, by day untouched")
	_t._check(R.OVERCAST_CLOUD > R.OVERCAST_CLOUD_OLD and R.OVERCAST_CLOUD < 0.12 and R.STORM_GLOW_GAIN > 1.0 and R.STORM_GLOW_GAIN < 2.0,
		"rain night: the deck lighter, still darker than a moonlit cloud")


func _glints(city: Node3D) -> void:
	_t._check(WetCarGlints.wanted(1.0, 0.6) and not WetCarGlints.wanted(0.0, 0.6) and not WetCarGlints.wanted(1.0, 0.0),
		"rain night: car reflections only with the lamps on and the road wet")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4141
	var car := Vehicle.random_car(rng)
	city.add_child(car)
	car.global_position = Vector3(0.0, -400.0, 0.0)
	await city.get_tree().process_frame
	car.seat_waiting_driver(9)
	var lamps := WetCarGlints.lamps(car)
	var heads := 0
	var front_ok := true
	for l: Array in lamps:
		if l[2]:
			heads += 1
			front_ok = front_ok and (l[0] as Vector3).z < 0.0
		else:
			front_ok = front_ok and (l[0] as Vector3).z > 0.0
		front_ok = front_ok and float(l[1]) > 0.2 and float(l[1]) < 2.0
	_t._check(lamps.size() == 4 and heads == 2 and front_ok, "rain night: four lamps a car, the heads at the nose (-z), the tails at the back, at lamp height")
	var g := WetCarGlints.new()
	g.max_cars = 4
	city.add_child(g)
	await city.get_tree().process_frame
	var xf := car.global_transform
	var ahead := xf.origin - xf.basis.z.normalized() * 20.0 + Vector3(0.0, 2.0, 0.0)
	var behind := xf.origin + xf.basis.z.normalized() * 20.0 + Vector3(0.0, 2.0, 0.0)
	g.set_process(false)
	g._cars = [car]
	g._place(ahead)
	var n_ahead := g._mm.visible_instance_count
	var head_lit := g.last_heads == 2 and g.last_tails == 0
	g._place(behind)
	var n_behind := g._mm.visible_instance_count
	var tail_lit := g.last_tails == 2 and g.last_heads == 0
	_t._check(n_ahead == 2 and head_lit and n_behind == 2 and tail_lit,
		"rain night: the head lamps mirror toward an eye ahead, the tails toward one behind (%d, %d)" % [n_ahead, n_behind])
	g.queue_free()
	car.queue_free()
	await city.get_tree().process_frame
