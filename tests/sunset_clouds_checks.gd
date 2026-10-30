extends RefCounted
## The Los Angeles sunset (SunsetSky, sky.gdshader's sunset model) for tests/smoke_test.gd. Loaded
## at run time so it compiles after the autoloads. Checks: the weight is 0 at noon, at night and
## under overcast and full through the sunset; DayNight hands it to the sky at 12:00 (0, so noon
## draws exactly what it did) and at 18:00; the shader keeps every sunset block behind
## `sunset > 0.0` and sun_through()'s numbers equal SunsetSky's copy; the light the low sun puts
## on a point is gold with the sun ten degrees up, red-orange on the horizon, gone on the cumulus
## base once the earth's shadow reaches it, while the cirrus 9 km up still have it (the
## afterglow), and a cloud nearer the sun keeps it longer.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_weight()
	_source()
	_light()
	var day: Node = city.get_node_or_null("DayNight")
	_t._check(day != null, "sunset: the city has a DayNight")
	if day:
		_day_night(day)


func _weight() -> void:
	var was: bool = SunsetSky.enabled
	SunsetSky.enabled = true
	_t._check(SunsetSky.weight(1.0) == 0.0 and SunsetSky.weight(0.5) == 0.0, "sunset: no sunset model by day")
	_t._check(SunsetSky.weight(-0.3) == 0.0 and SunsetSky.weight(-1.0) == 0.0, "sunset: none at night")
	_t._check(SunsetSky.weight(0.0) > 0.99 and SunsetSky.weight(0.13) > 0.99 and SunsetSky.weight(-0.06) > 0.99,
		"sunset: full from 17:30 to past the sunset (%.2f %.2f %.2f)" % [SunsetSky.weight(0.13), SunsetSky.weight(0.0), SunsetSky.weight(-0.06)])
	_t._check(SunsetSky.weight(0.0, 1.0) == 0.0 and SunsetSky.weight(0.0, 0.0, 1.0) < 0.25,
		"sunset: none under overcast, little in the marine layer")
	SunsetSky.enabled = false
	_t._check(SunsetSky.weight(0.0) == 0.0, "sunset: SUNSET_CLOUDS=0 turns it off")
	SunsetSky.enabled = was


func _source() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/sky.gdshader")
	_t._check(src.contains("uniform float sunset = 0.0;"), "sunset: the sky's weight defaults to off")
	# Every use of the weight sits behind the gate (or in a mix() inside one): count the gates.
	var gates := src.count("if (sunset > 0.0")
	_t._check(gates >= 6, "sunset: every sunset block is gated on sunset > 0 (%d gates)" % gates)
	var tr := SunsetSky.TAU_RAYLEIGH
	var ta := SunsetSky.TAU_AEROSOL
	var line := "vec3(%.3f, %.3f, %.3f) * mr + vec3(%.3f, %.3f, %.3f) * sunset_aerosol * ma" % [tr.x, tr.y, tr.z, ta.x, ta.y, ta.z]
	_t._check(src.contains(line), "sunset: sun_through()'s optical depths match SunsetSky's copy")
	_t._check(src.contains("float ht = el >= 0.0 ? h : h - el * el * EARTH_R * 0.5;")
		and src.contains("float lit = smoothstep(-0.5, 0.4, ht);") and src.contains("el += 0.01;"), "sunset: the shader's earth shadow is SunsetSky's")
	_t._check(src.contains("vec3 sunset_out(vec3 lin)") and src.contains("RENDERER_COMPATIBILITY"),
		"sunset: computed colours are handed to Compatibility in display numbers")


func _light() -> void:
	var gold := SunsetSky.sun_through(0.17, 2.0)
	_t._check(gold.g > 0.62 and gold.b > 0.25 and gold.a > 0.85,
		"sunset: ten degrees up the sun lights a cloud gold (%s)" % str(gold))
	var red := SunsetSky.sun_through(0.0, 1.5)
	_t._check(red.g < 0.45 and red.b < 0.1 and red.a > 0.3, "sunset: on the horizon it is red-orange (%s)" % str(red))
	_t._check(red.g < gold.g and red.a < gold.a, "sunset: redder and dimmer as it sinks")
	var base := SunsetSky.sun_through(-0.04, 1.5)
	var cirrus := SunsetSky.sun_through(-0.04, 9.0)
	_t._check(base.a < 0.02, "sunset: the earth's shadow has the cumulus base at 2.3 degrees under (%.3f)" % base.a)
	_t._check(cirrus.a > 0.2, "sunset: the cirrus 9 km up still glow then (%.3f)" % cirrus.a)
	var under := SunsetSky.sun_through(-0.015, 1.5)
	_t._check(under.a > 0.05, "sunset: a sun just under the street's horizon still lights the deck (%.3f)" % under.a)
	# 20 km toward the sun the local horizon tips 3 mrad toward it.
	var near := SunsetSky.sun_through(-0.038 + 20.0 / SunsetSky.EARTH_R, 2.0)
	var far := SunsetSky.sun_through(-0.038 - 20.0 / SunsetSky.EARTH_R, 2.0)
	_t._check(near.a > far.a, "sunset: a cloud toward the sun keeps the light longer than one away from it")


func _sky(day: Node) -> ShaderMaterial:
	var we := day.get_node_or_null(day.get("environment_path")) as WorldEnvironment
	if we and we.environment and we.environment.sky:
		return we.environment.sky.sky_material as ShaderMaterial
	return null


func _day_night(day: Node) -> void:
	var sky := _sky(day)
	_t._check(sky != null, "sunset: DayNight has the sky material")
	if sky == null:
		return
	var was_hour: float = day.get("hour")
	var was_on: bool = SunsetSky.enabled
	SunsetSky.enabled = true
	var w: Node = day.get_node_or_null("../Weather")
	var darken: float = day.get("weather_darken")
	day.set("hour", 12.0)
	day.call("_apply")
	var noon: float = float(sky.get_shader_parameter("sunset"))
	_t._check(noon == 0.0, "sunset: noon hands the sky 0 (%.3f)" % noon)
	day.set("hour", 18.0)
	day.call("_apply")
	var dusk: float = float(sky.get_shader_parameter("sunset"))
	var want := SunsetSky.weight(0.0, darken, float(day.get("marine")))
	_t._check(absf(dusk - want) < 1e-4 and (darken > 0.3 or dusk > 0.5),
		"sunset: 18:00 hands the sky its weight (%.3f, weather darken %.2f, %s)" % [dusk, darken, "Weather" if w else "no Weather"])
	day.set("hour", 2.0)
	day.call("_apply")
	_t._check(float(sky.get_shader_parameter("sunset")) == 0.0, "sunset: 2:00 hands the sky 0")
	SunsetSky.enabled = was_on
	day.set("hour", was_hour)
	day.call("_apply")
