extends RefCounted
## The city at night from the air (docs/HANDOFF.md, "The night aerial"): checks for
## tests/smoke_test.gd. Loaded at run time, so it can name CityChunk, FreewayKit and NightCity.
## Under --headless no shader runs, so these hold the contract: the GDScript copies of the
## shaders' numbers (the traffic and window profiles, the lamp patches, the light pattern's
## period), the integer lamp roll against known values, the near lamps taking the far glow's
## colour, and the LOD decks' traffic skin.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_copies_agree()
	_profiles()
	_lamp_patches()
	_near_lamps_match(city)
	_lod_deck_skin(city)


## The numbers the shaders and GDScript both hold are the same numbers.
func _copies_agree() -> void:
	var traffic := FileAccess.get_file_as_string("res://shaders/far_traffic.gdshaderinc")
	var windows := FileAccess.get_file_as_string("res://shaders/window_lights.gdshaderinc")
	var glow := FileAccess.get_file_as_string("res://shaders/street_glow.gdshaderinc")
	_t._check(_keys(traffic) == NightCity.LEVEL_KEYS, "the far traffic's hours are NightCity.LEVEL_KEYS (%s)" % [_keys(traffic)])
	_t._check(_keys(windows) == NightCity.WINDOW_KEYS, "the lit offices' hours are NightCity.WINDOW_KEYS (%s)" % [_keys(windows)])
	_t._check(traffic.contains("const float FT_CELL = %.1f;" % NightCity.CELL) and traffic.contains("const float FT_CELLS = %.1f;" % NightCity.CELLS),
		"the traffic lights' cell and period are NightCity's (%.0f m)" % NightCity.PERIOD)
	_t._check(glow.contains("const float LAMP_CELL = %.1f;" % NightCity.LAMP_CELL)
		and glow.contains("const vec2 LAMP_CENTRE = vec2(%.1f, %.1f);" % [NightCity.LAMP_CENTRE.x, NightCity.LAMP_CENTRE.y])
		and glow.contains("mix(0.72, 0.38, clamp((length(world_xz - LAMP_CENTRE) - 2000.0) / 4500.0"),
		"the lamp patches are NightCity's cell, centre and shares")
	var globals_ok := ProjectSettings.has_setting("shader_globals/city_hour")
	_t._check(globals_ok and windows.contains("ratio_in * floor_mul * window_hour_scale()"),
		"the clock is a shader global and the lit offices follow it")


## The first number of every `float k[13] = float[13](...)` in a shader source.
func _keys(src: String) -> Array[float]:
	var out: Array[float] = []
	var at := src.find("float[13](")
	if at < 0:
		return out
	var body := src.substr(at + 10, src.find(")", at) - at - 10)
	for part in body.split(","):
		out.append(float(part.strip_edges()))
	return out


## Busy evening, empty small hours; offices fuller at seven than at three.
func _profiles() -> void:
	var t3 := NightCity.traffic_level(3.0)
	var t21 := NightCity.traffic_level(21.0)
	var t17 := NightCity.traffic_level(17.5)
	_t._check(t3 < t21 and t21 < t17 and t3 > 0.05, "the far traffic thins through the night (17:30 %.2f, 21:00 %.2f, 03:00 %.2f)" % [t17, t21, t3])
	var w3 := NightCity.window_hour_scale(3.0)
	var w19 := NightCity.window_hour_scale(19.0)
	_t._check(w3 < 0.6 and w19 > 1.1 and is_equal_approx(NightCity.window_hour_scale(24.0), NightCity.window_hour_scale(0.0)),
		"offices empty toward three in the morning (19:00 x%.2f, 03:00 x%.2f)" % [w19, w3])


## The integer roll matches the shader's (values worked out from the same uint maths), and the
## city is LED near downtown, more sodium out at the edges.
func _lamp_patches() -> void:
	var exact := NightCity._lamp_hash(2147516416) == 646653579 and NightCity._lamp_hash(2147909632) == 2647451688 \
		and NightCity._lamp_hash(2147319815) == 3819557620
	_t._check(exact, "the lamp patch roll is the shader's uint hash, bit for bit")
	var near := 0
	var far := 0
	var n := 0
	for i in 20:
		for j in 20:
			n += 1
			near += 1 if NightCity.lamp_led(NightCity.LAMP_CENTRE + Vector2(i - 10, j - 10) * NightCity.LAMP_CELL * 0.35) else 0
			far += 1 if NightCity.lamp_led(Vector2(-4200.0, -900.0) + Vector2(i, j) * NightCity.LAMP_CELL) else 0
	_t._check(near > n / 3 and far < near and far > 0, "LED near downtown, more sodium out west (LED %d / %d near, %d / %d far)" % [near, n, far, n])


## A FULL chunk's lamps light in the colour the far streets glow there.
func _near_lamps_match(city: Node3D) -> void:
	var plan: CityPlan = city.plan
	var lamps := 0
	var wrong := 0
	for key: Vector2i in [plan.block_index_at(Vector2(2400.0, 600.0)), plan.block_index_at(Vector2(900.0, 1500.0))]:
		var chunk: CityChunk = city._new_chunk(key, CityChunk.Level.FULL)
		chunk.build()
		for light in chunk.get_children():
			if light is OmniLight3D and light.is_in_group("lamp_light") and light.get_parent() == chunk:
				lamps += 1
				var want := NightCity.lamp_light(Vector2(light.position.x, light.position.z))
				if not (light as OmniLight3D).light_color.is_equal_approx(want):
					wrong += 1
		chunk.get_parent().remove_child(chunk)
		chunk.free()
	_t._check(lamps > 0 and wrong == 0, "every street lamp's light is its patch's sodium or LED (%d lamps, %d wrong)" % [lamps, wrong])


## An LOD deck chunk carries the traffic skin (FULL ones have real traffic), on the deck, in the
## pattern's period, across the deck's width.
func _lod_deck_skin(city: Node3D) -> void:
	var plan: CityPlan = city.plan
	var fw: Freeway = plan.macro.freeway
	var key := Vector2i(999999, 0)
	for ri in fw.routes.size():
		var pts: PackedVector2Array = fw.routes[ri].points
		for i in range(10, pts.size() - 1, 10):
			var mid := pts[i].lerp(pts[i + 1], 0.5)
			if plan.zone_at(mid) == MacroMap.Zone.CITY:
				key = plan.block_index_at(mid)
				break
		if key.x != 999999:
			break
	if key.x == 999999:
		_t._check(false, "a city block under a freeway deck")
		return
	var lod: CityChunk = city._new_chunk(key, CityChunk.Level.LOD)
	lod.build()
	var has := lod.has_node("FreewayTraffic")
	var skin_ok := has and (lod.get_node("FreewayTraffic") as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var kit := FreewayKit.new(lod)
	var built := kit.build_segments(lod._freeway_segments(), lod.owned_rect())
	var arrays := kit.traffic.commit_to_arrays()
	var in_range := built > 0 and arrays.size() > 0 and arrays[Mesh.ARRAY_TEX_UV] != null
	if in_range:
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		in_range = uv.size() == built * 6
		for i in uv.size():
			if uv[i].x < 0.0 or uv[i].x > NightCity.PERIOD + Freeway.STEP * 2.0 or absf(uv[i].y) > uv2[i].y + 0.01 or uv2[i].x < 1.0:
				in_range = false
	lod.get_parent().remove_child(lod)
	lod.free()
	var full: CityChunk = city._new_chunk(key, CityChunk.Level.FULL)
	full.build()
	var full_none := not full.has_node("FreewayTraffic")
	full.get_parent().remove_child(full)
	full.free()
	_t._check(skin_ok and in_range and full_none, "an LOD deck carries the far traffic skin (one quad a segment, %d), a FULL one real traffic" % built)
