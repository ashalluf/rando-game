extends RefCounted
## The rainy day (RainDay, docs/HANDOFF.md "The rainy day", refcam rain_day in
## tools/refcams/cameras_w5.json), for tests/smoke_test.gd. Loaded at run time, not named there, so
## it compiles after the autoloads.
##
## The switch puts every number back; nothing changes at night or in the clear (so every other
## refcam is bit for bit); the shaders' day paths sit behind the `rain_day` global (0 by default);
## and the live city at 14:00 in the rain: the sun's key and shadows mostly gone, the after-dark
## lamp level 0 while the weather's lamps are on, the road's day weight up. Puts the hour and the
## weather back.

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	var was := RainDay.enabled
	RainDay.enabled = true
	_pure()
	_switch()
	_shaders()
	await _live(city)
	RainDay.enabled = was


func _pure() -> void:
	var R := RainDay
	# Rain by day: weather_darken 0.5, no moonlight.
	_t._check(is_equal_approx(R.overcast(0.5, 0.0), 0.8) and is_equal_approx(R.overcast(0.72, 0.0), 1.0)
		and is_equal_approx(R.overcast(0.25, 0.0), 0.4),
		"rain day: overcast is the sky's 1.6 ramp of the weather's darkening (%.2f)" % R.overcast(0.5, 0.0))
	_t._check(R.sun_gain(0.5, 0.0) < 0.5 and R.shadow_gain(0.5, 0.0) < 0.5 and R.ambient_gain(0.5, 0.0) > 1.5,
		"rain day: under rain the sun keeps under half its key, its shadows fade and the sky fill rises (%.2f, %.2f, %.2f)"
		% [R.sun_gain(0.5, 0.0), R.shadow_gain(0.5, 0.0), R.ambient_gain(0.5, 0.0)])
	_t._check(R.sun_gain(0.0, 0.0) == 1.0 and R.shadow_gain(0.0, 0.0) == 1.0 and R.ambient_gain(0.0, 0.0) == 1.0,
		"rain day: a clear day is untouched")
	_t._check(R.sun_gain(0.5, 1.0) == 1.0 and R.shadow_gain(0.72, 1.0) == 1.0 and R.ambient_gain(0.5, 1.0) == 1.0
		and R.day_weight(1.0) == 0.0,
		"rain day: a rainy night is untouched (RainStreetNight's look stays bit for bit)")
	_t._check(R.rain_deck(0.5, 0.0) == 1.0 and R.rain_deck(0.25, 0.0) == 0.0 and R.rain_deck(0.72, 1.0) == 0.0,
		"rain day: the sky's rain deck is rain and storm by day, not plain overcast, never at night")
	_t._check(R.lens_gain(0.0) == 1.0 and R.lens_gain(1.0) < 0.5,
		"rain day: the lens drops thin out by day only (%.2f)" % R.lens_gain(1.0))
	_t._check(is_equal_approx(R.day_weight(0.0), 1.0) and is_equal_approx(R.day_weight(0.25), 0.75),
		"rain day: the road's day weight is the lamps' night level turned over")


func _switch() -> void:
	var R := RainDay
	R.enabled = false
	R.night_lamp = 0.0
	_t._check(R.overcast(0.5, 0.0) == 0.0 and R.sun_gain(0.72, 0.0) == 1.0 and R.shadow_gain(0.72, 0.0) == 1.0
		and R.ambient_gain(0.72, 0.0) == 1.0 and R.lens_gain(1.0) == 1.0 and R.day_weight(0.0) == 0.0
		and R.after_dark_lamp(0.6) == 0.6 and R.rain_deck(0.72, 0.0) == 0.0,
		"rain day: RAIN_DAY=0 puts every number back (the old sun, shadows, fill, lens, lamps)")
	R.enabled = true
	_t._check(R.after_dark_lamp(0.6) == 0.0, "rain day: a searchlight sees the night's lamp level, not the weather's")


func _shaders() -> void:
	var road := FileAccess.get_file_as_string("res://shaders/road.gdshader")
	_t._check(road.contains("#include \"res://shaders/rain_day_mirror.gdshaderinc\"")
		and road.contains("if (wet > 0.01 && rain_day > 0.001 && side < 0.5) {")
		and road.contains("float night_k = lamp_factor * (1.0 - rain_day);"),
		"rain day: the road's day mirror is in the wet branch behind rain_day, the night mirror only after dark")
	var inc := FileAccess.get_file_as_string("res://shaders/rain_day_mirror.gdshaderinc")
	_t._check(inc.contains("global uniform float rain_day;") and inc.contains("float rdm_cover(") and not inc.contains("texture("),
		"rain day: the canyon is pure maths (no sampler)")
	for path: String in ["res://shaders/lawn.gdshader", "res://shaders/park_ground.gdshader"]:
		var src := FileAccess.get_file_as_string(path)
		_t._check(src.contains("global uniform float rain_day;") and src.contains("* rain_day"),
			"rain day: %s soaks only through rain_day" % path.get_file())
	var proj := FileAccess.get_file_as_string("res://project.godot")
	var at := proj.find("rain_day={")
	_t._check(at >= 0 and proj.substr(at, 60).contains("\"value\": 0.0"),
		"rain day: the rain_day global defaults to 0 (the old look until DayNight publishes it)")
	var sky_src := FileAccess.get_file_as_string("res://shaders/sky.gdshader")
	_t._check(sky_src.contains("uniform float rain_deck = 0.0;") and sky_src.contains("if (rain_deck > 0.0 && up > 0.0) {"),
		"rain day: the sky's rain deck is 0 by default and its block gated on it")


func _live(city: Node3D) -> void:
	var day: Node = city.get_node_or_null("DayNight")
	var weather: Node = city.get_node_or_null("Weather")
	if day == null or weather == null:
		_t._check(false, "rain day: the city has a DayNight and a Weather")
		return
	var sun: DirectionalLight3D = day.get("_sun")
	var spray: Node = weather.get("_spray")
	_t._check(spray != null and is_equal_approx(float(spray.get("reach")), RainDay.SPRAY_REACH)
		and is_equal_approx(float(spray.get("puff_alpha")), RainDay.SPRAY_ALPHA),
		"rain day: the tyre spray reaches down the street and is a thicker veil")
	var keys: Array = weather.get_script().get_script_constant_map().get("STATE_KEYS", [])
	var hour_was := float(day.get("hour"))
	var state_was := int(weather.get("state"))
	day.set("hour", 14.0)
	weather.call("force_state", keys.find("clear"), true)
	for i in 3:
		await city.get_tree().process_frame
	day.call("_apply")
	var clear_energy := sun.light_energy if sun else 0.0
	weather.call("force_state", keys.find("rain"), true)
	for i in 3:
		await city.get_tree().process_frame
	day.set("hour", 14.0)
	day.call("_apply")
	if sun:
		_t._check(sun.light_energy < clear_energy * 0.4 and sun.shadow_opacity < 0.5,
			"rain day: at 14:00 in the rain the sun is a fraction of the clear one and casts faint shadows (%.2f of %.2f, opacity %.2f)"
			% [sun.light_energy, clear_energy, sun.shadow_opacity])
	_t._check(DayNight.lamp_now > 0.08 and RainDay.after_dark_lamp(DayNight.lamp_now) < 0.01,
		"rain day: the weather brings the lamps on (%.2f) but nothing that burns only after dark" % DayNight.lamp_now)
	_t._check(RainDay._pushed > 0.9, "rain day: the road's day weight is published by day (%.2f)" % RainDay._pushed)
	var sky: ShaderMaterial = day.get("_sky")
	if sky:
		_t._check(float(sky.get_shader_parameter("rain_deck")) > 0.9, "rain day: the sky's rain deck is on at 14:00 in the rain")
	day.set("hour", 23.0)
	day.call("_apply")
	_t._check(RainDay._pushed < 0.01, "rain day: and taken away at night (%.2f)" % RainDay._pushed)
	if sky:
		_t._check(float(sky.get_shader_parameter("rain_deck")) == 0.0, "rain day: and the rain deck is off at night")
	day.set("hour", hour_was)
	weather.call("force_state", state_was, true)
	day.call("_apply")
