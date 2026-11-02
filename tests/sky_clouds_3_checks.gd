extends RefCounted
## Cloud shadows from the real clouds (CloudShadows, shaders/cloud_shadow*.gdshader*; docs/HANDOFF.md
## "Cloud shadows from the real clouds") for tests/smoke_test.gd. Loaded at run time so it compiles
## after the autoloads. Checks: the strength rule (none at night or under a low sun, full by day,
## gone in overcast, rain and the marine layer), the include's field is cumulus()'s own lines, the
## screen shader parses and multiplies, it is Forward+ desktop only (none headless, the plane keeps
## its own shadows), CLOUD_SHADOWS=0 is honoured, and DayNight's hook is there.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_strength()
	_mirror()
	_shaders()
	_city(city)


func _strength() -> void:
	var noon := CloudShadows.strength_for(0.5, 0.85, 0.45, 0.0, 0.0)
	_t._check(absf(noon - 0.5) < 1e-5, "cloud shadows: full strength under a high sun in a broken sky (%.3f)" % noon)
	_t._check(CloudShadows.strength_for(0.5, -0.1, 0.45, 0.0, 0.0) == 0.0, "cloud shadows: none at night")
	_t._check(CloudShadows.strength_for(0.5, 0.04, 0.45, 0.0, 0.0) == 0.0, "cloud shadows: none with the sun on the horizon")
	var low := CloudShadows.strength_for(0.5, 0.12, 0.45, 0.0, 0.0)
	_t._check(low > 0.0 and low < 0.5, "cloud shadows: eased in as the sun climbs (%.3f)" % low)
	_t._check(CloudShadows.strength_for(0.5, 0.85, 0.95, 0.0, 0.0) == 0.0, "cloud shadows: none in overcast (all of it is shade)")
	_t._check(CloudShadows.strength_for(0.5, 0.85, 0.45, 0.8, 0.0) == 0.0, "cloud shadows: none in rain")
	_t._check(CloudShadows.strength_for(0.5, 0.85, 0.45, 0.0, 1.0) == 0.0, "cloud shadows: none under the marine layer")
	var mid := CloudShadows.strength_for(0.5, 0.85, 0.83, 0.0, 0.0)
	_t._check(mid > 0.0 and mid < 0.5, "cloud shadows: a closing sky fades them (%.3f)" % mid)


## The shadow's field must be the cumulus' own: the same warp, map tiling and offsets, field term
## and thresholds, or the shadows lie where no cloud is.
func _mirror() -> void:
	var sky := FileAccess.get_file_as_string("res://shaders/sky.gdshader")
	var inc := FileAccess.get_file_as_string("res://shaders/cloud_shadow.gdshaderinc")
	var lines := [
		["vec3 wn = textureLod(cloud_shape, vec3(pxz / (billow_tile * 2.6), 0.37), 0.0).rgb;", "vec3 wn = textureLod(cs_shape, vec3(pxz / (cs_billow_tile * 2.6), 0.37), 0.0).rgb;"],
		["vec2 wuv = (pxz + wv * 0.9) / weather_tile;", "vec2 wuv = (pxz + wv * 0.9) / cs_weather_tile;"],
		["float field = textureLod(cloud_weather, wuv * 0.27 + vec2(0.37, 0.71), lod).b;", "float field = textureLod(cs_weather, wuv * 0.27 + vec2(0.37, 0.71), cs_lod).b;"],
		["float cov = coverage + (field - 0.5) * 0.46 * (1.0 - smoothstep(0.7, 0.9, coverage));", "float cov = cs_coverage + (field - 0.5) * 0.46 * (1.0 - smoothstep(0.7, 0.9, cs_coverage));"],
		["float col = column(w.r, thr, 0.26);", "float col = smoothstep(thr, thr + 0.26, w.r);"],
		["float top = mix(0.16, 1.0, g) * (0.4 + 0.6 * col) * mix(0.6, 1.35, field);", "float top = mix(0.16, 1.0, w.g * w.g) * (0.4 + 0.6 * col) * mix(0.6, 1.35, field);"],
		["top = min(top * mix(0.72, 1.12, smoothstep(0.25, 0.75, wn.r)), 0.97);", "top = min(top * mix(0.72, 1.12, smoothstep(0.25, 0.75, wn.r)), 0.97);"],
		["vec2 fr = textureLod(cloud_weather, wuv * 4.3 + vec2(0.61, 0.23), lod + 1.0).rg;", "vec2 fr = textureLod(cs_weather, wuv * 4.3 + vec2(0.61, 0.23), cs_lod + 1.0).rg;"],
		["float fthr = thr + 0.16 + 0.12 * col;", "float fthr = thr + 0.16 + 0.12 * col + cs_fragments;"],
		["float ftop = mix(0.05, 0.2, fr.y);", "float ftop = mix(0.05, 0.2, fr.y);"],
		["vec2 lean = normalize(cloud_wind + vec2(1e-5)) * hc * hc * 0.22;", "vec2 lean = normalize(cs_wind + vec2(1e-5)) * cs_body * cs_body * 0.22;"],
		["p.xz += wind;", "+ cs_wind * TIME;"],
		["float rr = smoothstep(0.22, 1.0, rel);", "float rr = smoothstep(0.22, 1.0, rel);"],
		["rr = rr * rr * (1.0 + 0.4 * rr);", "rr = rr * rr * (1.0 + 0.4 * rr);"],
		["float d_big = rel < 1.0 ? clamp((sqrt(col) - rr) / max(1.0 - rr, 0.05), 0.0, 1.0) : 0.0;", "float d_big = rel < 1.0 ? clamp((sqrt(col) - rr) / max(1.0 - rr, 0.05), 0.0, 1.0) : 0.0;"],
		["float fr2 = smoothstep(0.1, 1.0, frel);", "float fr2 = smoothstep(0.1, 1.0, frel);"],
	]
	var miss: Array[String] = []
	for pair: Array in lines:
		if not sky.contains(pair[0]) or not inc.contains(pair[1]):
			miss.append(str(pair[0]))
	_t._check(miss.is_empty(), "cloud shadows: the shadow field is cumulus()'s own lines (%s)" % ", ".join(miss))
	_t._check(sky.contains("vec2 wind = cloud_wind * TIME;"), "cloud shadows: the sky drifts its clouds by cloud_wind x TIME, as the shadows do")


func _shaders() -> void:
	var sh := load("res://shaders/cloud_shadow_screen.gdshader") as Shader
	_t._check(sh != null and sh.get_shader_uniform_list().size() >= 15, "cloud shadows: the screen shader parses")
	var src := FileAccess.get_file_as_string("res://shaders/cloud_shadow_screen.gdshader")
	_t._check(src.contains("blend_mul") and src.contains("depth_test_disabled") and src.contains("#include \"res://shaders/cloud_shadow.gdshaderinc\""),
		"cloud shadows: one full-screen multiply over the opaque picture")
	_t._check(src.contains("if (depth < 0.0000001"), "cloud shadows: the sky itself is never darkened")


func _city(city: Node3D) -> void:
	var day: Node = city.get_node_or_null("DayNight")
	_t._check(day != null, "cloud shadows: the city has a DayNight")
	if day == null:
		return
	var dn := FileAccess.get_file_as_string("res://scripts/world/day_night.gd")
	_t._check(dn.contains("if CloudShadows.supported():"), "cloud shadows: DayNight makes them where they can be drawn")
	_t._check(not CloudShadows.supported(), "cloud shadows: never headless, on the web or on Compatibility")
	_t._check(day.get_node_or_null("CloudShadows") == null, "cloud shadows: none under the dummy renderer")
	var gm: Variant = city.get("_ground_material")
	if gm is ShaderMaterial:
		var v: Variant = (gm as ShaderMaterial).get_shader_parameter("cloud_shadow_strength")
		_t._check(v == null or float(v) > 0.0, "cloud shadows: where they are not drawn the far plane keeps its own")
	var was := OS.get_environment("CLOUD_SHADOWS")
	OS.set_environment("CLOUD_SHADOWS", "0")
	_t._check(not CloudShadows.enabled(), "cloud shadows: CLOUD_SHADOWS=0 turns them off")
	OS.set_environment("CLOUD_SHADOWS", was)
	_t._check(CloudShadows.enabled() == (was != "0"), "cloud shadows: the switch is read from the environment")
