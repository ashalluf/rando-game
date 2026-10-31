extends RefCounted
## The sunset on the Esplanade (docs/HANDOFF.md "The sunset on the Esplanade", SunsetReview) for
## tests/smoke_test.gd: pins what the `sunset` reference camera was tuned to.
## - The dusk horizon cools round the side away from the sun (sky.gdshader `dusk_away`), only at
##   dusk: noon and the night skip the block.
## - The old violet twilight band waits for the sun to be down.
## - The depth fog goes to night with the sky (GoldenHour's ramp), not with the slower light, and
##   its dusk colour is not orange.
## - The lamps' lights come in on the square of the lamp level; the level itself is untouched.
## - SUNSET_REVIEW=0 hands every old value back.
## Stages its own clock and weather on the city's DayNight and puts them back.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_pure()
	_shader()
	var day: Node = city.get_node_or_null("DayNight")
	_t._check(day != null, "rc-sunset: the city has a DayNight")
	if day == null:
		return
	var held := {"hour": day.get("hour"), "weather_darken": day.get("weather_darken"),
		"marine": day.get("marine"), "santa_ana": day.get("santa_ana"), "cloud_extra": day.get("cloud_extra")}
	for k in ["weather_darken", "marine", "santa_ana", "cloud_extra"]:
		day.set(k, 0.0)
	_live(day)
	for k in held:
		day.set(k, held[k])
	day.call("_apply")


func _pure() -> void:
	# Elevation is DayNight's sin(t * PI): 17:51 about +0.04, 18:00 0, 18:36 about -0.16.
	_t._check(SunsetReview.band_gain(0.08, 0.6) == 0.0 and SunsetReview.band_gain(-0.05, 0.0) == 1.0,
		"rc-sunset: the twilight band is off with the sun up and whole once it is down")
	_t._check(SunsetReview.band_gain(0.035, 0.29) < 0.3,
		"rc-sunset: two degrees before sunset the band is mostly off (%.2f)" % SunsetReview.band_gain(0.035, 0.29))
	_t._check(SunsetReview.dusk_away(0.0) == 0.0 and SunsetReview.dusk_away(1.0) > 0.5,
		"rc-sunset: the cool side of the dusk sky only exists at dusk")
	_t._check(SunsetReview.fog_night(0.3, 0.8) == 0.8 and SunsetReview.fog_night(0.6, 0.2) == 0.6,
		"rc-sunset: the fog goes to night on the faster ramp")
	_t._check(is_equal_approx(SunsetReview.light_level(1.0), 1.0) and SunsetReview.light_level(0.0) == 0.0
		and SunsetReview.light_level(0.5) < 0.3, "rc-sunset: the lamps' lights come in on the square")
	_t._check(SunsetReview.pool_ease(0.0) == 1.0 and SunsetReview.pool_ease(1.0) == 0.0,
		"rc-sunset: the lamp pools ease in at a clear dusk, not under a storm")
	var planted := 0
	var stable := true
	for i in 200:
		var p := Vector3(-500.0 + i * 3.7, 4.0, 3600.0 + i * 1.3)
		var c := SunsetReview.bluff_far(p, 1337)
		if c.g > c.r:
			planted += 1
		stable = stable and c == SunsetReview.bluff_far(p, 1337)
	_t._check(stable and planted > 90 and planted < 185,
		"rc-sunset: the far bluff face is mostly planted, partly bare (%d of 200 planted)" % planted)
	var fog := SunsetReview.DUSK_FOG
	_t._check(fog.r / fog.b < 1.5, "rc-sunset: the dusk fog is rose-grey, not orange (R/B %.2f)" % (fog.r / fog.b))
	# The A/B.
	var was := SunsetReview.enabled
	SunsetReview.enabled = false
	var old_ok := SunsetReview.band_gain(0.035, 0.29) == 1.0 - 0.29 and SunsetReview.dusk_away(1.0) == 0.0 \
		and SunsetReview.fog_night(0.3, 0.8) == 0.3 and SunsetReview.light_level(0.5) == 0.5 \
		and SunsetReview.dusk_fog(Color(0.72, 0.45, 0.33)) == Color(0.72, 0.45, 0.33) and SunsetReview.pool_ease(0.0) == 0.0
	SunsetReview.enabled = was
	_t._check(old_ok, "rc-sunset: SUNSET_REVIEW=0 hands back DayNight's old values")


## The shader's default tint is SunsetReview's (DayNight never sets it).
func _shader() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/sky.gdshader")
	var re := RegEx.create_from_string("uniform vec3 dusk_away_tint = vec3\\(([0-9.]+), ([0-9.]+), ([0-9.]+)\\);")
	var m := re.search(src)
	var ok := m != null
	if ok:
		var v := Vector3(float(m.get_string(1)), float(m.get_string(2)), float(m.get_string(3)))
		ok = v.is_equal_approx(SunsetReview.DUSK_AWAY_TINT)
	_t._check(ok, "rc-sunset: sky.gdshader's dusk_away_tint is SunsetReview.DUSK_AWAY_TINT")
	var pool := FileAccess.get_file_as_string("res://shaders/light_pool.gdshader")
	_t._check(pool.find("lamp_factor * mix(1.0, lamp_factor, lamp_ease)") >= 0
		and ProjectSettings.has_setting("shader_globals/lamp_ease"),
		"rc-sunset: the lamp pools read the lamp_ease global")
	_t._check(src.find("uniform float dusk_away = 0.0;") >= 0 and src.find("if (dusk_away > 0.001)") >= 0,
		"rc-sunset: the sky skips the dusk_away block at 0")


func _at(day: Node, h: float) -> Dictionary:
	day.set("hour", h)
	day.call("_apply")
	var sky: ShaderMaterial = day.get("_sky")
	var out := {"lamp": float(day.get("lamp_now"))}
	if sky:
		out["away"] = float(sky.get_shader_parameter("dusk_away"))
		out["band"] = float(sky.get_shader_parameter("twilight_band_gain"))
	var we := day.get_node_or_null(day.get("environment_path")) as WorldEnvironment
	if we and we.environment:
		out["fog"] = we.environment.fog_light_color
	return out


func _live(day: Node) -> void:
	var noon := _at(day, 12.0)
	var night := _at(day, 22.0)
	if noon.has("away"):
		_t._check(float(noon["away"]) == 0.0 and float(night["away"]) == 0.0,
			"rc-sunset: noon and night skip the dusk_away block")
		var dusk := _at(day, 17.85)
		_t._check(float(dusk["away"]) > 0.5 and float(dusk["band"]) < 0.3,
			"rc-sunset: at 17:51 the sky cools away from the sun (%.2f) with the band mostly off (%.2f)" % [dusk["away"], dusk["band"]])
	var late := _at(day, 18.6)
	if late.has("fog"):
		var fog: Color = late["fog"]
		var night_fog: Color = day.get("night_fog")
		_t._check(fog.get_luminance() < night_fog.get_luminance() + 0.12,
			"rc-sunset: at 18:36 the fog is near its night colour (%.3f vs %.3f)" % [fog.get_luminance(), night_fog.get_luminance()])
	# The lights: half way up the level, a quarter of the energy.
	var lights := day.get_tree().get_nodes_in_group("lamp_light")
	if lights.size() > 0:
		var mid := 17.0
		for i in 120:
			var h := 17.5 + i / 120.0
			day.set("hour", h)
			day.call("_apply")
			if float(day.get("lamp_now")) >= 0.5:
				mid = h
				break
		day.set("hour", mid)
		day.set("_lamp_timer", 0.0)
		day.call("_apply")
		var l := lights[0] as OmniLight3D
		var full := float(day.get("lamp_energy")) * float(day.get("lamp_scale")) * float(l.get_meta("lamp_gain", 1.0))
		var lamp := float(day.get("lamp_now"))
		_t._check(full <= 0.0 or l.light_energy <= full * lamp * lamp + 0.05,
			"rc-sunset: half way up, a lamp's light is on the square of the level (%.2f of %.2f, level %.2f)" % [l.light_energy, full, lamp])
