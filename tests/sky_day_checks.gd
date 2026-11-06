extends RefCounted
## The day sky (SkyDay, sky.gdshader's `sky_day` blocks; docs/HANDOFF.md "The day sky") for
## tests/smoke_test.gd. Loaded at run time so it compiles after the autoloads. Checks: the weight
## is 0 at and outside 09:00 / 16:00 (so dawn, the golden hour, the sunset and the night draw
## exactly as before), full from 10:00 to 15:00, gone under rain and the marine layer, off with
## SKY_DAY=0; the shader defaults it to 0 and keeps every use behind `sky_day > 0.0`; DayNight
## hands it to the sky at noon, and 0 at 08:30, 16:30 and 02:00.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_weight()
	_source()
	var day: Node = city.get_node_or_null("DayNight")
	_t._check(day != null, "sky day: the city has a DayNight")
	if day:
		_day_night(day)


func _weight() -> void:
	var was: bool = SkyDay.enabled
	SkyDay.enabled = true
	var outside := [0.0, 3.0, 6.0, 8.5, 8.999, 9.0, 16.0, 16.01, 17.0, 18.6, 21.0, 23.9]
	var any := 0.0
	for h: float in outside:
		any = maxf(any, SkyDay.weight(h))
	_t._check(any == 0.0, "sky day: exactly 0 at and outside 09:00-16:00 (max %f)" % any)
	_t._check(SkyDay.weight(10.0) == 1.0 and SkyDay.weight(12.0) == 1.0 and SkyDay.weight(15.0) == 1.0,
		"sky day: full from 10:00 to 15:00")
	var a := SkyDay.weight(9.5)
	var b := SkyDay.weight(15.5)
	_t._check(a > 0.2 and a < 0.8 and b > 0.2 and b < 0.8, "sky day: eased in and out (%.2f %.2f)" % [a, b])
	_t._check(SkyDay.weight(12.0, 1.0) == 0.0 and SkyDay.weight(12.0, 0.0, 1.0) == 0.0,
		"sky day: none under rain or the marine layer")
	_t._check(SkyDay.weight(12.0, 0.3) < 1.0 and SkyDay.weight(12.0, 0.3) > 0.0, "sky day: faded by light weather")
	SkyDay.enabled = false
	_t._check(SkyDay.weight(12.0) == 0.0, "sky day: SKY_DAY=0 turns it off")
	SkyDay.enabled = was


func _source() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/sky.gdshader")
	_t._check(src.contains("uniform float sky_day = 0.0;"), "sky day: the sky's weight defaults to off")
	_t._check(src.contains("sday = sky_day * day_cubemap;"), "sky day: the ambient cubemap takes only a share of it")
	# Every line that reads the weight is a gate, or sits inside one (a mix() whose weight is 0 is
	# exact): count the gates and the reads.
	var gates := src.count("if (sky_day > 0.0") + src.count("if (sday > 0.0")
	var reads := 0
	var gated := 0
	var depth := 0
	var gate_depth: Array[int] = []
	for line: String in src.split("\n"):
		var s := line.strip_edges()
		if s.begins_with("//") or s.begins_with("uniform"):
			continue
		var opened := s.count("{")
		var closed := s.count("}")
		var gate := s.begins_with("if (sky_day > 0.0") or s.begins_with("if (sday > 0.0")
		# sky() reads it once into `sday` (the cubemap pass takes a share), then gates on that.
		var reads_it := (s.contains("sky_day") or s.contains("sday")) and s != "float sday = sky_day;"
		if reads_it and not gate:
			reads += 1
			if not gate_depth.is_empty():
				gated += 1
		if gate:
			gate_depth.append(depth)
		depth += opened - closed
		while not gate_depth.is_empty() and depth <= gate_depth[-1]:
			gate_depth.pop_back()
	_t._check(gates >= 9, "sky day: the day blocks are gated on sky_day > 0 (%d gates)" % gates)
	_t._check(reads > 0 and reads == gated, "sky day: every read of the weight is inside a gate (%d of %d)" % [gated, reads])


func _sky(day: Node) -> ShaderMaterial:
	var we := day.get_node_or_null(day.get("environment_path")) as WorldEnvironment
	if we and we.environment and we.environment.sky:
		return we.environment.sky.sky_material as ShaderMaterial
	return null


func _day_night(day: Node) -> void:
	var sky := _sky(day)
	_t._check(sky != null, "sky day: DayNight has the sky material")
	if sky == null:
		return
	var was_hour: float = day.get("hour")
	var was_on: bool = SkyDay.enabled
	SkyDay.enabled = true
	var darken: float = day.get("weather_darken")
	var marine: float = day.get("marine")
	day.set("hour", 12.0)
	day.call("_apply")
	var noon := float(sky.get_shader_parameter("sky_day"))
	var want := SkyDay.weight(12.0, darken, marine)
	_t._check(absf(noon - want) < 1e-5 and (darken > 0.3 or marine > 0.3 or noon > 0.5),
		"sky day: noon hands the sky its weight (%.3f, weather darken %.2f, marine %.2f)" % [noon, darken, marine])
	var off := 0.0
	for h: float in [8.5, 16.5, 2.0]:
		day.set("hour", h)
		day.call("_apply")
		off = maxf(off, float(sky.get_shader_parameter("sky_day")))
	_t._check(off == 0.0, "sky day: 08:30, 16:30 and 02:00 hand the sky 0")
	SkyDay.enabled = was_on
	day.set("hour", was_hour)
	day.call("_apply")
