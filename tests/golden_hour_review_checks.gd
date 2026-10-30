extends RefCounted
## The golden-hour review (docs/HANDOFF.md "The golden hour review", GoldenHour) for
## tests/smoke_test.gd: pins what the 17:00-19:30 strips were tuned to, so none of it slides back.
## - The sky darkens on its own twilight ramp, not on night_factor: at 18:15 (sun ~4 degrees down,
##   night_factor already 1) the zenith, the horizon and `sky_tint` (what the sea and glass mirror)
##   are still well over their night colours, and night by nautical dusk.
## - At the sunset the zenith holds blue and the violet band sits low; the GOLDEN grade is eased
##   while the sun is on the horizon and whole again by golden hour proper.
## - The ramps are continuous: no colour the sky, the light or the grade hands out jumps between
##   two game minutes 17:00-19:30, and the lamps come on as a ramp, not a switch.
## - GOLDEN_HOUR_REVIEW=0 puts every old number back (restore()).
## Stages its own clock and weather on the city's DayNight and puts them back.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_pure()
	var day: Node = city.get_node_or_null("DayNight")
	_t._check(day != null, "golden hour: the city has a DayNight")
	if day == null:
		return
	var held := {"hour": day.get("hour"), "weather_darken": day.get("weather_darken"),
		"marine": day.get("marine"), "santa_ana": day.get("santa_ana"), "cloud_extra": day.get("cloud_extra")}
	for k in ["weather_darken", "marine", "santa_ana", "cloud_extra"]:
		day.set(k, 0.0)
	_numbers(day)
	_live(day)
	_ramps(day)
	_restore(day)
	for k in held:
		day.set(k, held[k])
	day.call("_apply")


func _pure() -> void:
	# Elevation is DayNight's sin(t * PI); 18:15 is about -0.065, 18:50 about -0.22.
	var at_1815 := GoldenHour.sky_night(-0.065, 1.0)
	_t._check(at_1815 > 0.15 and at_1815 < 0.6,
		"golden hour: at 18:15 the sky is part way to night (%.2f), not at it like night_factor" % at_1815)
	_t._check(GoldenHour.sky_night(0.05, 0.0) == 0.0 and GoldenHour.sky_night(-0.25, 1.0) == 1.0,
		"golden hour: the sky is day colours with the sun up and night past nautical dusk")
	var sunset := GoldenHour.golden_grade(0.0)
	_t._check(sunset >= 0.3 and sunset <= 0.6 and is_equal_approx(GoldenHour.golden_grade(0.2), 1.0),
		"golden hour: the GOLDEN grade eases at the sunset (%.2f) and is whole at golden hour" % sunset)
	var w0: Dictionary = HourGrade.weights(0.0, 1.0, 0.0, 0.0, 0.0)
	var w1: Dictionary = HourGrade.weights(0.15, 1.0, 0.0, 0.0, 0.0)
	_t._check(float(w0[HourGrade.Look.GOLDEN]) < 0.65 and float(w1[HourGrade.Look.GOLDEN]) > 0.95,
		"golden hour: the grade's GOLDEN weight %.2f at the sunset, %.2f with the sun up" % [w0[HourGrade.Look.GOLDEN], w1[HourGrade.Look.GOLDEN]])


func _numbers(day: Node) -> void:
	var top: Color = day.get("dusk_sky_top")
	_t._check(top.b > top.r * 3.0 and top.b > 0.4,
		"golden hour: the sunset zenith is blue (%.2f, %.2f, %.2f)" % [top.r, top.g, top.b])
	var band: Vector2 = day.get("twilight_band_height")
	_t._check(band.x <= 0.22, "golden hour: the violet band sits low at the sunset (%.2f)" % band.x)
	var moon: Color = day.get("night_sun_color")
	_t._check(moon.b - moon.r <= 0.3, "golden hour: the moonlight is cool, not teal (%.2f, %.2f, %.2f)" % [moon.r, moon.g, moon.b])
	_t._check(float(day.get("golden_fog_gain")) <= 1.3 and float(day.get("ground_smog")) <= 0.55,
		"golden hour: the smog lid leaves the ranges their shape")


func _sky_at(day: Node, h: float) -> Dictionary:
	day.set("hour", h)
	day.call("_apply")
	var sky: ShaderMaterial = day.get("_sky")
	var out := {"lamp": float(day.get("lamp_now")), "night": float(day.get("night_factor")),
		"tint": day.get("_horizon_now") as Color}
	if sky:
		out["top"] = _c(sky.get_shader_parameter("sky_top"))
		out["rim"] = _c(sky.get_shader_parameter("sky_horizon"))
	var sun := day.get("_sun") as DirectionalLight3D
	if sun:
		out["sun"] = sun.light_color
		out["energy"] = sun.light_energy
	var we := day.get_node_or_null(day.get("environment_path")) as WorldEnvironment
	if we and we.environment:
		out["sat"] = we.environment.adjustment_saturation
		out["exp"] = we.environment.tonemap_exposure
		out["fog"] = we.environment.fog_light_color
	return out


static func _c(v: Variant) -> Color:
	if v is Color:
		return v
	if v is Vector3:
		return Color(v.x, v.y, v.z)
	return Color(0, 0, 0)


func _live(day: Node) -> void:
	var night_top: Color = day.get("night_sky_top")
	var night_rim: Color = day.get("night_horizon")
	var s := _sky_at(day, 18.25)
	_t._check(float(s["night"]) > 0.99, "golden hour: night_factor is 1 at 18:15 (lamps on)")
	if s.has("top"):
		var top: Color = s["top"]
		var rim: Color = s["rim"]
		_t._check(top.get_luminance() > night_top.get_luminance() * 1.6 and rim.get_luminance() > night_rim.get_luminance() * 1.6,
			"golden hour: the 18:15 sky is twilight, not night (zenith %.3f vs %.3f)" % [top.get_luminance(), night_top.get_luminance()])
	var tint: Color = s["tint"]
	_t._check(tint.get_luminance() > night_rim.get_luminance() * 1.6,
		"golden hour: sky_tint (the sea's and glass's mirror) still glows at 18:15 (%.3f)" % tint.get_luminance())
	var n := _sky_at(day, 19.25)
	if n.has("top"):
		_t._check((n["top"] as Color).is_equal_approx(night_top),
			"golden hour: the sky is night by 19:15")
	var sunset := _sky_at(day, 18.0)
	if sunset.has("top"):
		var st: Color = sunset["top"]
		_t._check(st.b > st.r * 2.0, "golden hour: the zenith is blue at the sunset (%.2f, %.2f, %.2f)" % [st.r, st.g, st.b])


## Every colour DayNight hands out, every game minute 17:00-19:30: no step bigger than a share of
## its whole swing (a pop is a jump between two minutes). The lamps ramp over at least 20 minutes.
func _ramps(day: Node) -> void:
	var keys := ["top", "rim", "tint", "sun", "fog"]
	var prev := {}
	var worst := {}
	var lamp_on := -1.0
	var lamp_full := -1.0
	var lamp_jump := 0.0
	var prev_lamp := -1.0
	var m := 0
	while m <= 150:
		var h := 17.0 + float(m) / 60.0
		var s := _sky_at(day, h)
		for k in keys:
			if not s.has(k):
				continue
			var c: Color = s[k]
			if prev.has(k):
				var p: Color = prev[k]
				var d := maxf(absf(c.r - p.r), maxf(absf(c.g - p.g), absf(c.b - p.b)))
				worst[k] = maxf(float(worst.get(k, 0.0)), d)
			prev[k] = c
		var l: float = s["lamp"]
		if prev_lamp >= 0.0:
			lamp_jump = maxf(lamp_jump, absf(l - prev_lamp))
		if lamp_on < 0.0 and l > 0.01:
			lamp_on = h
		if lamp_full < 0.0 and l > 0.99:
			lamp_full = h
		prev_lamp = l
		m += 1
	var smooth := true
	var text := ""
	for k in worst:
		text += "%s %.3f " % [k, worst[k]]
		smooth = smooth and float(worst[k]) < 0.05
	_t._check(smooth, "golden hour: no colour jumps between two game minutes 17:00-19:30 (%s)" % text)
	_t._check(lamp_on > 0.0 and lamp_full > lamp_on + 0.33 and lamp_jump < 0.06,
		"golden hour: the lamps come on as a ramp (%.2f -> %.2f, worst step %.3f)" % [lamp_on, lamp_full, lamp_jump])


func _restore(day: Node) -> void:
	var was := GoldenHour.enabled
	var keep := {}
	for k: String in GoldenHour.OLD:
		keep[k] = day.get(k)
	GoldenHour.enabled = false
	GoldenHour.restore(day)
	var all := true
	for k: String in GoldenHour.OLD:
		all = all and day.get(k) == GoldenHour.OLD[k]
	var old_ramp := GoldenHour.sky_night(-0.065, 0.77) == 0.77 and GoldenHour.golden_grade(0.0) == 1.0
	GoldenHour.enabled = was
	for k in keep:
		day.set(k, keep[k])
	_t._check(all and old_ramp, "golden hour: GOLDEN_HOUR_REVIEW=0 puts the old numbers and ramps back")
