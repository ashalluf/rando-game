extends RefCounted
## The city at night from a helicopter (docs/HANDOFF.md, "The night flight"; NightFlight): checks
## for tests/smoke_test.gd. No shader runs under --headless, so these hold the contract: the
## shaders' copies of NightFlight's numbers, the platoons' mean and spread, the street rank's
## order, the junction's corner pools, the switch through the global, and the beams' near fade.

var _t: Node


func run(t: Node, _city: Node3D) -> void:
	_t = t
	_copies_agree()
	_platoons()
	_rank()
	_switch()


## The numbers the shaders and NightFlight both hold are the same numbers.
func _copies_agree() -> void:
	var traffic := FileAccess.get_file_as_string("res://shaders/far_traffic.gdshaderinc")
	var glow := FileAccess.get_file_as_string("res://shaders/street_glow.gdshaderinc")
	_t._check(traffic.contains("const float FT_PLATOON = %.1f;" % NightFlight.PLATOON)
		and traffic.contains("const float FT_PLATOON_LO = %.1f;" % NightFlight.PLATOON_LO)
		and traffic.contains("const float FT_PLATOON_SPAN = %.1f;" % NightFlight.PLATOON_SPAN)
		and traffic.contains("const float FT_TAIL_MEAN = %.1f;" % NightFlight.TAIL_MEAN),
		"the traffic's platoon numbers are NightFlight's")
	_t._check(glow.contains("const float RANK_LO = %.2f;" % NightFlight.RANK_LO)
		and glow.contains("const float RANK_HI = %.2f;" % NightFlight.RANK_HI)
		and glow.contains("const float RANK_W0 = %.1f;" % NightFlight.RANK_W0)
		and glow.contains("const float RANK_W1 = %.1f;" % NightFlight.RANK_W1),
		"the streets' rank numbers are NightFlight's")
	# Every far street's glow wears the rank, and every junction the corner pools.
	var ground := FileAccess.get_file_as_string("res://shaders/far_ground.gdshader")
	var lod := FileAccess.get_file_as_string("res://shaders/building_lod.gdshader")
	var road := FileAccess.get_file_as_string("res://shaders/road.gdshader")
	_t._check(ground.contains("street_rank(width)") and ground.contains("street_glow_junction(")
		and lod.contains("street_rank(") and lod.contains("street_glow_junction(")
		and road.contains("street_rank(g_width)") and road.contains("glow_square ? street_glow_junction("),
		"the LOD ground, the far plates and the near road's far glow all rank their streets")
	_t._check(ProjectSettings.has_setting("shader_globals/night_flight"), "night_flight is a shader global")


## Platoons: a factor with mean ~1 (the hour's level is kept on average), real gaps and knots,
## smooth along the road.
func _platoons() -> void:
	var lo := 9.0
	var hi := 0.0
	var sum := 0.0
	var n := 0
	var jump := 0.0
	var prev := NightFlight.platoon(0.0, 3.0)
	for i in 4000:
		var p := NightFlight.platoon(float(i) * 5.0, 3.0)
		lo = minf(lo, p)
		hi = maxf(hi, p)
		sum += p
		n += 1
		jump = maxf(jump, absf(p - prev))
		prev = p
	var mean := sum / float(n)
	_t._check(absf(mean - 1.0) < 0.12, "the platoons keep the hour's traffic on average (mean %.3f)" % mean)
	_t._check(lo < 0.55 and hi > 1.45, "the platoons leave gaps and knots (%.2f .. %.2f)" % [lo, hi])
	_t._check(jump < 0.2, "the platoons change smoothly along the road (largest step %.3f in 5 m)" % jump)
	_t._check(not is_equal_approx(NightFlight.platoon(1000.0, 1.0), NightFlight.platoon(1000.0, 2.0)),
		"the two carriageways have their own platoons")


## The rank: wider is brighter, side streets dimmer than before, arterials brighter.
func _rank() -> void:
	var side := NightFlight.street_rank(8.0)
	var mid := NightFlight.street_rank(15.0)
	var art := NightFlight.street_rank(26.0)
	_t._check(side < 0.6 and side < mid and mid < art and art > 1.2,
		"the street grid has a hierarchy (8 m x%.2f, 15 m x%.2f, 26 m x%.2f)" % [side, mid, art])


## NIGHT_FLIGHT=0: everything back to 1, the global to 0; and back on.
func _switch() -> void:
	var was := NightFlight.enabled
	NightFlight.set_enabled(false)
	var off_ok := is_equal_approx(NightFlight.street_rank(8.0), 1.0) and is_equal_approx(NightFlight.platoon(123.0, 1.0), 1.0)
	var g := float(RenderingServer.global_shader_parameter_get("night_flight"))
	NightFlight.set_enabled(true)
	var g_on := float(RenderingServer.global_shader_parameter_get("night_flight"))
	NightFlight.set_enabled(was)
	_t._check(off_ok and is_zero_approx(g) and is_equal_approx(g_on, 1.0),
		"NIGHT_FLIGHT=0 puts every street and lane back as it was (global %.0f / %.0f)" % [g, g_on])
	var beam := FileAccess.get_file_as_string("res://shaders/nightlife_beam.gdshader")
	_t._check(beam.contains("night_flight > 0.5") and beam.contains("CAMERA_POSITION_WORLD.y - lens_world.y"),
		"a sky beam fades only for a camera near it and up in the air over its lamp")
