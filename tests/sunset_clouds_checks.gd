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
	var es: PackedStringArray = []
	for e in SunsetSky.PALETTE_E:
		es.append("%.2f" % e)
	_t._check(src.contains("SUNSET_PAL_E[7] = float[](%s);" % ", ".join(es)), "sunset: sun_through()'s palette stops match SunsetSky's copy")
	var cs: PackedStringArray = []
	for c in SunsetSky.PALETTE_C:
		cs.append("vec3(%.2f, %.2f, %.2f)" % [c.x, c.y, c.z])
	var flat := src.replace("\n\t", " ").replace("\n", " ")
	_t._check(flat.contains(", ".join(cs)), "sunset: sun_through()'s palette colours match SunsetSky's copy")
	_t._check(src.contains("const float SUNSET_SHADOW_R = %.1f;" % SunsetSky.SHADOW_R)
		and src.contains("float lit = smoothstep(-0.4, 0.5, htr);") and src.contains("float elr = min(el + 0.01, 0.0);"),
		"sunset: the shader's earth shadow is SunsetSky's")
	_t._check(src.contains("vec3 sunset_out(vec3 lin)") and src.contains("RENDERER_COMPATIBILITY"),
		"sunset: computed colours are handed to Compatibility in display numbers")


func _light() -> void:
	var gold := SunsetSky.sun_through(0.25, 2.0)
	_t._check(gold.g > 0.5 and gold.b > 0.2 and gold.a > 0.95,
		"sunset: fifteen degrees up the sun lights a cloud gold-orange (%s)" % str(gold))
	var orange := SunsetSky.sun_through(0.065, 2.0)
	_t._check(orange.g < 0.4 and orange.b < 0.15 and orange.a > 0.9,
		"sunset: four degrees up it is a deep orange, never lemon (%s)" % str(orange))
	var pink := SunsetSky.sun_through(-0.07, 2.0)
	_t._check(pink.b > pink.g and pink.r > 0.9 and pink.a > 0.5,
		"sunset: under the horizon the bases 2 km up are lit pink (%s)" % str(pink))
	var magenta := SunsetSky.sun_through(-0.13, 2.0)
	_t._check(magenta.b > 0.4 and magenta.a > 0.1 and magenta.a < pink.a,
		"sunset: then magenta, dimming as the shadow climbs (%s)" % str(magenta))
	var low := SunsetSky.sun_through(-0.13, 0.3)
	var cirrus := SunsetSky.sun_through(-0.13, 9.0)
	_t._check(low.a < 0.02, "sunset: the earth's shadow has the fractus 300 m up by then (%.3f)" % low.a)
	_t._check(cirrus.a > 0.5, "sunset: the cirrus 9 km up still glow (%.3f)" % cirrus.a)
	# 20 km toward the sun the local horizon tips 3 mrad toward it.
	var near := SunsetSky.sun_through(-0.14 + 20.0 / SunsetSky.EARTH_R, 2.0)
	var far := SunsetSky.sun_through(-0.14 - 20.0 / SunsetSky.EARTH_R, 2.0)
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
	# A June-gloom deck an earlier file left (Weather on MARINE) takes the sunset away: held at 0
	# here with the read (shuffled gate 2303 read 0.200 with no darken).
	var was_marine: float = day.get("marine")
	day.set("marine", 0.0)
	day.set("hour", 12.0)
	day.call("_apply")
	var noon: float = float(sky.get_shader_parameter("sunset"))
	_t._check(noon == 0.0, "sunset: noon hands the sky 0 (%.3f)" % noon)
	day.set("hour", 18.0)
	day.call("_apply")
	var dusk: float = float(sky.get_shader_parameter("sunset"))
	var want := SunsetSky.weight(0.0, darken, float(day.get("marine")))
	_t._check(absf(dusk - want) < 1e-4 and (darken > 0.3 or dusk > 0.5),
		"sunset: 18:00 hands the sky its weight (%.3f, weather darken %.2f, marine %.2f held at 0, %s)" % [dusk, darken, was_marine, "Weather" if w else "no Weather"])
	day.set("hour", 2.0)
	day.call("_apply")
	_t._check(float(sky.get_shader_parameter("sunset")) == 0.0, "sunset: 2:00 hands the sky 0")
	SunsetSky.enabled = was_on
	day.set("marine", was_marine)
	day.set("hour", was_hour)
	day.call("_apply")
