extends RefCounted
## The dawn review (docs/HANDOFF.md "The dawn review", DawnReview) for tests/smoke_test.gd: pins
## what the 05:00-08:30 shots were tuned to, and that nothing else moved.
## - The dawn weight is 0 from noon on and in the night, so noon, the evening and the night are
##   bit-identical with the review on and off (every number DayNight hands out compared).
## - At 06:15 the sun and the sky are cooler and pinker than the evening's at the same elevation,
##   the smog thinner, the haze cool; the GOLDEN grade is eased.
## - The street lamps are off before the sunrise (on at 05:30, off by 06:05) and go out as a ramp.
## - No colour jumps between two game minutes 05:00-08:30.
## - sun_through()'s dawn palette in sky.gdshader is SunsetSky's copy.
## Stages its own clock and weather on the city's DayNight and puts them back.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_pure()
	_shader()
	var day: Node = city.get_node_or_null("DayNight")
	_t._check(day != null, "dawn: the city has a DayNight")
	if day == null:
		return
	var held := {"hour": day.get("hour"), "weather_darken": day.get("weather_darken"),
		"marine": day.get("marine"), "santa_ana": day.get("santa_ana"), "cloud_extra": day.get("cloud_extra")}
	for k in ["weather_darken", "marine", "santa_ana", "cloud_extra"]:
		day.set(k, 0.0)
	var was := DawnReview.enabled
	DawnReview.enabled = true
	_untouched(day)
	_dawn(day)
	_ramps(day)
	DawnReview.enabled = was
	for k in held:
		day.set(k, held[k])
	day.call("_apply")


func _pure() -> void:
	_t._check(DawnReview.weight(12.0, 1.0) == 0.0 and DawnReview.weight(18.0, 0.0) == 0.0
		and DawnReview.weight(17.0, 0.26) == 0.0 and DawnReview.weight(3.0, -0.71) == 0.0,
		"dawn: no weight at noon, in the evening or at night")
	_t._check(DawnReview.weight(6.25, 0.065) > 0.99 and DawnReview.weight(7.0, 0.259) > 0.99,
		"dawn: whole at 06:15 and 07:00")
	_t._check(DawnReview.weight(8.75, 0.70) == 0.0, "dawn: gone by 08:45")
	var lamp_530 := DawnReview.lamp_factor(1.0, 5.5, -0.13)
	var lamp_605 := DawnReview.lamp_factor(1.0, 6.08, 0.022)
	_t._check(lamp_530 > 0.99 and lamp_605 == 0.0,
		"dawn: the lamps burn at 05:30 (%.2f) and are out by 06:05 (%.2f)" % [lamp_530, lamp_605])
	_t._check(DawnReview.lamp_factor(0.4, 18.1, 0.0) == 0.4, "dawn: the evening's lamps are night_factor's")
	var dawn := SunsetSky.sun_through(0.06, 2.0, 1.0)
	var dusk := SunsetSky.sun_through(0.06, 2.0, 0.0)
	_t._check(dawn.b > dusk.b * 2.0 and dawn.g > dusk.g, "dawn: the low sun on the clouds is pinker at dawn (b %.2f vs %.2f)" % [dawn.b, dusk.b])


func _shader() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/sky.gdshader").replace("\n", " ").replace("\t", "")
	var cs := []
	for c in SunsetSky.DAWN_PAL_C:
		cs.append("vec3(%.2f, %.2f, %.2f)" % [c.x, c.y, c.z])
	_t._check(src.contains(", ".join(cs)), "dawn: sky.gdshader's DAWN_PAL_C matches SunsetSky's copy")
	_t._check(src.contains("uniform float dawn = 0.0;") and src.contains("if (dawn > 0.0)"),
		"dawn: the sky's dawn block is skipped at 0")


## Everything DayNight sets, read back (sky uniforms, the light, the environment, the globals).
func _state(day: Node, h: float) -> Dictionary:
	day.set("hour", h)
	day.call("_apply")
	var out := {"lamp": float(day.get("lamp_now")), "tint": day.get("_horizon_now"), "fog_gain": day.get("fog_gain")}
	var sky: ShaderMaterial = day.get("_sky")
	if sky:
		for p in ["sky_top", "sky_horizon", "cloud_color", "cloud_shadow", "smog", "smog_color", "sun_color",
				"ground_color", "dawn", "sunset", "twilight_warm", "twilight_amount"]:
			out[p] = sky.get_shader_parameter(p)
	var sun := day.get("_sun") as DirectionalLight3D
	if sun:
		out["light"] = sun.light_color
		out["energy"] = sun.light_energy
	var we := day.get_node_or_null(day.get("environment_path")) as WorldEnvironment
	if we and we.environment:
		var env := we.environment
		out["exp"] = env.tonemap_exposure
		out["fog"] = env.fog_light_color
		out["sat"] = env.adjustment_saturation
		out["amb"] = env.ambient_light_color
	return out


static func _c(v: Variant) -> Color:
	if v is Color:
		return v
	if v is Vector3:
		return Color(v.x, v.y, v.z)
	return Color(0, 0, 0)


## Noon, the afternoon, the evening and the night: the same with the review on and off.
func _untouched(day: Node) -> void:
	var differs := []
	for h in [0.0, 3.0, 4.5, 9.0, 12.0, 15.0, 17.5, 18.0, 18.5, 21.0, 23.5]:
		DawnReview.enabled = true
		var on := _state(day, h)
		DawnReview.enabled = false
		var off := _state(day, h)
		DawnReview.enabled = true
		for k in on:
			if on[k] != off.get(k):
				differs.append("%s@%.1f" % [k, h])
	_t._check(differs.is_empty(), "dawn: noon, evening and night are bit-identical with the review off (%s)" % ", ".join(differs))


func _dawn(day: Node) -> void:
	DawnReview.enabled = false
	var off := _state(day, 6.25)
	DawnReview.enabled = true
	var on := _state(day, 6.25)
	var dusk := _state(day, 17.75) # the same elevation in the evening
	if on.has("light"):
		var a: Color = on["light"]
		var b: Color = dusk["light"]
		_t._check(a.b > b.b + 0.04 and a.g > b.g, "dawn: the 06:15 sun is cooler than the 17:45 one (%s vs %s)" % [a, b])
	if on.has("sky_horizon"):
		var r: Color = _c(on["sky_horizon"])
		var r0: Color = _c(off["sky_horizon"])
		_t._check(r.b > r0.b, "dawn: the horizon is pinker, less orange (b %.2f vs %.2f)" % [r.b, r0.b])
		_t._check(float(on["smog"]) < float(off["smog"]) or float(off["smog"]) == 0.0, "dawn: the smog is thinner")
		_t._check(float(on["dawn"]) > 0.99 and float(dusk["dawn"]) == 0.0, "dawn: the sky's dawn uniform is on at 06:15, off at 17:45")
	if on.has("fog"):
		var f: Color = on["fog"]
		var fd: Color = dusk["fog"]
		_t._check(f.b > fd.b and f.r - f.b < fd.r - fd.b, "dawn: the morning haze is cooler than the evening's (%s vs %s)" % [f, fd])
		_t._check(float(on["fog_gain"]) > float(off["fog_gain"]), "dawn: the morning haze is thicker with the sun low")


func _ramps(day: Node) -> void:
	var keys := ["sky_top", "sky_horizon", "tint", "light", "fog", "cloud_color"]
	var prev := {}
	var worst := {}
	var lamp_jump := 0.0
	var prev_lamp := -1.0
	var m := 0
	while m <= 210:
		var s := _state(day, 5.0 + float(m) / 60.0)
		for k in keys:
			if not s.has(k):
				continue
			var c: Color = _c(s[k])
			if prev.has(k):
				var p: Color = prev[k]
				worst[k] = maxf(float(worst.get(k, 0.0)), maxf(absf(c.r - p.r), maxf(absf(c.g - p.g), absf(c.b - p.b))))
			prev[k] = c
		var l: float = s["lamp"]
		if prev_lamp >= 0.0:
			lamp_jump = maxf(lamp_jump, absf(l - prev_lamp))
		prev_lamp = l
		m += 1
	var smooth := true
	var text := ""
	for k in worst:
		text += "%s %.3f " % [k, worst[k]]
		smooth = smooth and float(worst[k]) < 0.05
	_t._check(smooth, "dawn: no colour jumps between two game minutes 05:00-08:30 (%s)" % text)
	_t._check(lamp_jump < 0.12, "dawn: the lamps go out as a ramp (worst step %.3f)" % lamp_jump)
