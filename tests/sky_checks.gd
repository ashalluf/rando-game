extends RefCounted
## The sky (sky.gdshader, DayNight's date and moon, SkyExtras) for tests/smoke_test.gd. Loaded at
## run time so it compiles after the autoloads. Checks: the cumulus noise builds at its sizes and
## is handed to the sky; the shader keeps its street-under-the-horizon cubemap pass, its smog and
## its Compatibility guards; the moon's place follows its age (new with the sun, full opposite
## it) and the age grows a day when the clock passes midnight; the contrail jets cruise 9-12 km up,
## move, and reach the shader; the light dome lights the night over the city, faces downtown from
## the beach, wraps round it downtown, and is gone by day.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var day: Node = city.get_node_or_null("DayNight")
	_t._check(day != null, "sky: the city has a DayNight")
	if day == null:
		return
	var extras: Node = day.get_node_or_null("SkyExtras")
	_t._check(extras != null, "sky: DayNight made its SkyExtras")
	_source()
	_noise(day)
	_moon(day)
	if extras:
		_contrails(day, extras)
		_dome(day, extras)


func _sky(day: Node) -> ShaderMaterial:
	var we := day.get_node_or_null(day.get("environment_path")) as WorldEnvironment
	if we and we.environment and we.environment.sky:
		return we.environment.sky.sky_material as ShaderMaterial
	return null


func _source() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/sky.gdshader")
	_t._check(src.contains("if (AT_CUBEMAP_PASS) {") and src.contains("reflect_ground"),
		"sky: reflections still see the street under the horizon")
	_t._check(src.contains("if (smog > 0.002)") and src.contains("smog_glow"), "sky: the golden-hour smog is still drawn")
	# The half-resolution pass and HALF_RES_COLOR stay off the Compatibility renderer.
	var guard := src.find("#if CURRENT_RENDERER != RENDERER_COMPATIBILITY\nrender_mode use_half_res_pass;")
	_t._check(guard >= 0, "sky: the half-resolution pass is Forward+ only")
	var bad := 0
	var lines := src.split("\n")
	var forward := []
	for line in lines:
		var s: String = line.strip_edges()
		if s.begins_with("#if"):
			forward.append(s.contains("!= RENDERER_COMPATIBILITY"))
		elif s.begins_with("#endif"):
			forward.pop_back()
		elif s.begins_with("#else"):
			forward[forward.size() - 1] = not forward[forward.size() - 1]
		elif (s.contains("HALF_RES_COLOR") or s.contains("AT_HALF_RES_PASS")) and not s.begins_with("//"):
			if not forward.has(true):
				bad += 1
	_t._check(bad == 0, "sky: every half-res reference is inside a Forward+ guard (%d outside)" % bad)
	# The photographic cumulus (wave 2 review): a flat base, the fragments' population, three
	# erosion octaves, the crown thinned so the billows make it.
	_t._check(src.contains("d *= smoothstep(0.0, 0.012, hn);") and src.contains("float fcol = column(")
		and src.contains("qe * 4.7") and src.contains("d_big *= 1.0 - 0.8 * smoothstep(0.35, 1.0, rel);"),
		"sky: the cumulus keep their flat bases, fragments, three-octave edges and turreted crowns")


func _noise(day: Node) -> void:
	var ok: bool = SkyExtras.textures()
	_t._check(ok, "sky: the cloud noise images load")
	if not ok:
		return
	var shape: ImageTexture3D = SkyExtras._shape_tex
	var weather: ImageTexture = SkyExtras._weather_tex
	_t._check(shape.get_width() == 64 and shape.get_height() == 64 and shape.get_depth() == 64,
		"sky: the billow volume is 64^3 (%dx%dx%d)" % [shape.get_width(), shape.get_height(), shape.get_depth()])
	_t._check(weather.get_width() == 256 and weather.get_height() == 256, "sky: the weather map is 256^2")
	var sky := _sky(day)
	_t._check(sky != null and float(sky.get_shader_parameter("cloud_volume")) > 0.5
		and sky.get_shader_parameter("cloud_shape") == shape,
		"sky: the volume's noise is handed to the sky shader")


func _moon(day: Node) -> void:
	var hour: float = day.get("hour")
	var age: float = day.get("moon_age_days")
	var count: int = day.get("day_count")
	var start: float = day.get("start_hour")
	day.set("day_count", 0)
	day.set("hour", start)
	day.set("moon_age_days", 0.0)
	day.call("_apply")
	var sd: Vector3 = day.get("sun_dir")
	var md: Vector3 = day.get("moon_dir")
	_t._check(sd.dot(md) > 0.95, "sky: a new moon stands with the sun (%.2f)" % sd.dot(md))
	day.set("moon_age_days", 29.53 * 0.5)
	day.call("_apply")
	md = day.get("moon_dir")
	sd = day.get("sun_dir")
	_t._check(sd.dot(md) < -0.95, "sky: a full moon stands opposite the sun (%.2f)" % sd.dot(md))
	# Across midnight the date moves on and the moon with it.
	day.set("moon_age_days", 3.0)
	day.set("hour", 23.999)
	day.call("_apply")
	var before: float = day.get("moon_age")
	day.call("_process", 1.0)
	var after: float = day.get("moon_age")
	_t._check(int(day.get("day_count")) == 1 and absf(after - before) < 0.05 and after > before,
		"sky: the date turns over at midnight and the moon keeps ageing (%.3f -> %.3f)" % [before, after])
	day.set("day_count", count)
	day.set("moon_age_days", age)
	day.set("hour", hour)
	day.call("_apply")


func _contrails(day: Node, extras: Node) -> void:
	var jets: Array = extras.get("_jets")
	_t._check(jets.size() == int(extras.get("contrail_jets")) and jets.size() > 0,
		"sky: %d high jets are crossing" % jets.size())
	var high := true
	for j in jets:
		high = high and float(j.height) >= 9000.0 and float(j.height) <= 12000.0
	_t._check(high, "sky: the jets cruise 9-12 km up")
	var along: float = jets[0].along
	extras.call("_fly", 2.0, Vector3.ZERO)
	_t._check(float(jets[0].along) > along + 400.0, "sky: a jet flies on (%.0f m in 2 s)" % (float(jets[0].along) - along))
	extras.call("_push_trails", Vector3.ZERO)
	var sky := _sky(day)
	if sky:
		var a: PackedVector4Array = sky.get_shader_parameter("trail_a")
		_t._check(int(sky.get_shader_parameter("trail_count")) == jets.size() and a.size() == 8
			and a[0].y > 8.5 and a[0].w > 0.0, "sky: the trails reach the shader, ~10 km over the camera")


func _dome(day: Node, extras: Node) -> void:
	var plan: Object = day.get_parent().get("plan")
	if plan == null:
		return
	var macro: Object = plan.get("macro")
	var dt: Vector2 = macro.get("downtown_center")
	extras.call("_survey", dt)
	_t._check(float(extras.get("_city_wrap")) > 0.5, "sky: downtown, the light dome wraps the horizon (%.2f)" % float(extras.get("_city_wrap")))
	var pier := Vector2(-940.0, -350.0)
	extras.call("_survey", pier)
	var cd: Vector2 = extras.get("_city_dir")
	_t._check(cd.x > 0.5 and float(extras.get("_city_wrap")) < 0.45,
		"sky: from the pier the dome stands inland, to the east (%s, wrap %.2f)" % [str(cd), float(extras.get("_city_wrap"))])
	var hour: float = day.get("hour")
	var darken: float = day.get("weather_darken")
	var sky := _sky(day)
	# Clear weather for this: a storm lights the lamps (and so the dome) at noon too.
	day.set("weather_darken", 0.0)
	day.set("hour", 23.0)
	day.call("_apply")
	extras.call("_push_dome")
	var night: float = sky.get_shader_parameter("city_glow") if sky else 0.0
	day.set("hour", 12.0)
	day.call("_apply")
	extras.call("_push_dome")
	var noon: float = sky.get_shader_parameter("city_glow") if sky else 1.0
	_t._check(night > 0.01 and noon < 0.001, "sky: the city lights the night sky (%.3f), not the day (%.4f)" % [night, noon])
	day.set("hour", hour)
	day.set("weather_darken", darken)
	day.call("_apply")
