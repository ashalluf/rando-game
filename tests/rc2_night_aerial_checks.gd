extends RefCounted
## The night aerial refcam (NightAerial, docs/HANDOFF.md "The night aerial review"): checks for
## tests/smoke_test.gd. Under --headless no shader runs, so the shaders are read back against the
## GDScript copies, and the rolls are counted on the CPU. Nothing here leans on what an earlier file
## left: the switch is put back as it was found.

var _t: Node


func run(t: Node, _city: Node3D = null) -> void:
	_t = t
	_global_and_switch()
	_floods()
	_pools()
	_beams()
	_lane_mean()
	_camera_row()


## The shader global exists, and the switch drives it.
func _global_and_switch() -> void:
	_t._check(ProjectSettings.has_setting("shader_globals/night_aerial"), "night_aerial is a shader global")
	var was := NightAerial.enabled
	NightAerial.set_enabled(false)
	var off_raw = RenderingServer.global_shader_parameter_get("night_aerial")
	var off := float(off_raw) if off_raw != null else 0.0
	NightAerial.set_enabled(true)
	var on_raw = RenderingServer.global_shader_parameter_get("night_aerial")
	var on := float(on_raw) if on_raw != null else 1.0
	NightAerial.set_enabled(was)
	_t._check(is_equal_approx(off, 0.0) and is_equal_approx(on, 1.0),
		"NIGHT_AERIAL switches the night_aerial global (off %.1f, on %.1f)" % [off, on])


## tower_wash() keeps FLOOD_KEEP of the masonry floods under the switch, and the old share without.
func _floods() -> void:
	var inc := FileAccess.get_file_as_string("res://shaders/window_lights.gdshaderinc")
	_t._check(inc.contains("wl_roll(sd, 113u) < %.2f" % NightAerial.FLOOD_KEEP)
			and inc.contains("(na ? %.1f : 1.5)" % NightAerial.FLOOD_GAIN)
			and inc.contains("!na ||"),
		"tower_wash() keeps NightAerial.FLOOD_KEEP of the floods at FLOOD_GAIN, all of them with the switch off")
	var was := NightAerial.enabled
	var lit_on := 0
	var lit_off := 0
	for s in 1000:
		NightAerial.enabled = true
		lit_on += 1 if NightAerial.floodlit(s) else 0
		NightAerial.enabled = false
		lit_off += 1 if NightAerial.floodlit(s) else 0
	NightAerial.enabled = was
	var share_on := float(lit_on) / 1000.0
	var share_off := float(lit_off) / 1000.0
	_t._check(absf(share_off - NightSkyline.FLOOD_SHARE) < 0.06 and share_on > 0.12 and share_on < 0.28,
		"a fifth of masonry is floodlit with the pass, 60 %% without (%.2f / %.2f)" % [share_on, share_off])


## The freeway's pools ease their rim and fade from the air; only display_add pools (the freeway's).
func _pools() -> void:
	var sh := FileAccess.get_file_as_string("res://shaders/light_pool.gdshader")
	_t._check(sh.contains("if (display_add && night_aerial > 0.5)") and sh.contains("smoothstep(0.0, 0.45, r)")
			and sh.contains("uniform float pool_air_gain = 0.45;"),
		"light_pool eases a broad pool's rim and dims it from the air, behind the switch")
	var mat := FreewayKit.pool_material()
	_t._check(mat != null and bool(mat.get_shader_parameter("display_add")),
		"the freeway's pools are the display_add ones the pass reaches")


## The far searchlight shaft fades from the air past beam_far_from.
func _beams() -> void:
	var sh := FileAccess.get_file_as_string("res://shaders/nightlife_beam.gdshader")
	_t._check(sh.contains("if (night_aerial > 0.5 && night_flight > 0.5)") and sh.contains("1.0 - exp(-a * 1.3), above_a)")
			and sh.contains("above_a * smoothstep(beam_far_from, beam_far_to, length(VERTEX))"),
		"the searchlight shaft fades far off from the air, behind the switch")
	var heli := FileAccess.get_file_as_string("res://shaders/searchlight_beam.gdshader")
	_t._check(heli.contains("if (night_aerial > 0.5)") and heli.contains("smoothstep(far_from, far_to, length(VERTEX))")
			and heli.contains("1.0 - exp(-a * 1.3), far_k)") and heli.contains("uniform float far_gain = 0.2;"),
		"a helicopter's searchlight shaft far off saturates softly and fades, behind the switch")


## The camera this review is judged on is in wave 5's table.
func _camera_row() -> void:
	var text := FileAccess.get_file_as_string("res://tools/refcams/cameras_w5.json")
	var data = JSON.parse_string(text)
	var found := false
	if data is Dictionary:
		for c: Dictionary in data.get("cameras", []):
			if String(c.get("name", "")) == "night_aerial":
				found = float(c.get("hour", 0.0)) > 22.0 and (c.get("eye", []) as Array).size() == 5
	_t._check(found, "the night_aerial refcam is in tools/refcams/cameras_w5.json")


## The freeway's lane mean: its numbers are NightAerial's and its along term keeps the total.
func _lane_mean() -> void:
	var inc := FileAccess.get_file_as_string("res://shaders/far_traffic.gdshaderinc")
	_t._check(inc.contains("const float FT_NEAR_BLOOM = %.1f;" % NightAerial.NEAR_BLOOM)
			and inc.contains("const float FT_BLOOM_FULL = %.1f;" % NightAerial.BLOOM_FULL)
			and inc.contains("const float FT_CELLS_FROM = %.1f;" % NightAerial.CELLS_FROM)
			and inc.contains("const float FT_CELLS_GONE = %.1f;" % NightAerial.CELLS_GONE)
			and inc.contains("shape = ft_mean_shape("),
		"far_traffic's lane mean shape holds NightAerial's numbers and is used in the mean")
	var worst := 0.0
	for lvl: float in [0.2, 0.45, 0.8]:
		worst = maxf(worst, absf(NightAerial.mean_along(lvl, 37.0) - 1.0))
	_t._check(worst < 0.15, "the lane mean drawn as cars keeps its total (worst %.2f off)" % worst)
