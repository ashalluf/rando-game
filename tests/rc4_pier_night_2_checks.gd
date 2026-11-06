extends RefCounted
## The pier at night from the beach, second pass (RcPierNight / CoastExposure, rc4-pier-night-2;
## refcam pier_night), for tests/smoke_test.gd. Loaded at run time, not named there, so it compiles
## after the autoloads.
##
## Checks: the coast's exposure is 1 by day, at the 18:36 sunset and inland, full on the sand and
## over the sea at night, and 1 under the A/B; the park's material carries the wash and its glows
## (none under the A/B), the shader keeps the wash behind `wash > 0`; the sand and the ocean take
## the piers' rows (the same rows the ocean mirrors) with each deck on its rows' facing side, the
## include's line source is zero far away and largest beside the row; the strollers come only at
## night, near a pier, out of the rain, and are clothed.

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	var was_r := RcPierNight.enabled
	var was_c := CoastExposure.enabled
	RcPierNight.enabled = true
	CoastExposure.enabled = true
	_exposure(city)
	_wash()
	_sand()
	_strollers(city)
	RcPierNight.enabled = false
	CoastExposure.enabled = false
	var m := ShaderMaterial.new()
	RcPierNight.dress_material(m)
	RcPierNight.push(m)
	_t._check(CoastExposure.gain_for(1.0, 1.0) == 1.0 and m.get_shader_parameter("wash") == null
		and m.get_shader_parameter("pw_gain") == null and RcPierNight.stroller_count(_plan(city), -400.0, -300.0, 21.0, 1.0) == 0,
		"RC4_PIER_NIGHT=0: no coast exposure, no wash, no light on the sand or the sea, no strollers")
	RcPierNight.enabled = was_r
	CoastExposure.enabled = was_c


func _plan(city: Node3D) -> CityPlan:
	return city.get("plan") as CityPlan


func _exposure(city: Node3D) -> void:
	var plan := _plan(city)
	var macro := plan.macro
	var z := -235.0
	var sand := Vector2(macro.coast_x(z) + macro.beach_width_at(z) * 0.5, z)
	var sea := Vector2(macro.coast_x(z) - 200.0, z)
	var inland := Vector2(macro.coast_x(z) + macro.beach_width_at(z) + CoastExposure.COAST_REACH + 50.0, z)
	_t._check(CoastExposure.coast_weight(macro, sand) == 1.0 and CoastExposure.coast_weight(macro, sea) == 1.0
		and CoastExposure.coast_weight(macro, inland) == 0.0,
		"the coast weight is 1 on the sand and over the sea, 0 inland")
	_t._check(is_equal_approx(CoastExposure.gain_for(1.0, 1.0), CoastExposure.COAST_GAIN) and CoastExposure.gain_for(0.0, 1.0) == 1.0
		and CoastExposure.gain_for(1.0, 0.0) == 1.0 and CoastExposure.gain_for(1.0, 0.5) == 1.0,
		"the coast opens up %.2fx at night only (day, the 18:36 sunset and the street untouched)" % CoastExposure.COAST_GAIN)
	# The 18:36 sunset camera's moonlight (DayNight: smoothstep(0.02, -0.34, elevation)).
	var el := sin((18.6 - 6.0) / 12.0 * PI)
	var moon := smoothstep(0.02, -0.34, el)
	_t._check(CoastExposure.gain_for(1.0, moon) == 1.0, "the Esplanade sunset (18:36, moonlight %.2f) keeps its exposure" % moon)
	var day := city.get_node_or_null("DayNight")
	_t._check(day != null and CoastExposure.exposure_gain(day, 0.0) == 1.0, "DayNight's hook returns 1 by day")


func _wash() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/pier_park.gdshader")
	_t._check(src.contains("uniform float wash = 0.0") and src.contains("if (wash > 0.0 && lit > 0.0)") and src.contains("vec3 park_wash("),
		"pier_park's wash is behind its uniform, off by default")
	var m := PierMesh.material("rc4_pier_night_probe")
	_t._check(float(m.get_shader_parameter("wash")) == RcPierNight.WASH
		and int(m.get_shader_parameter("wash_pt_count")) == RcPierNight.GLOWS.size()
		and RcPierNight.GLOWS.size() <= 10,
		"a park material is made with the wash and its %d glows" % RcPierNight.GLOWS.size())
	var a := RcPierNight.pier_anchor()
	_t._check((m.get_shader_parameter("wash_anchor") as Vector3).is_equal_approx(Vector3(a.x, 0.0, a.y)),
		"the wash is anchored on the pier's landmark")
	for g: Array in RcPierNight.GLOWS:
		var p: Vector3 = g[0]
		var on := false
		for r: Rect2 in [PierPark.MAIN, PierPark.NORTH, PierPark.SOUTH]:
			on = on or r.grow(2.0).has_point(Vector2(p.x, p.z))
		_t._check(on and p.y > PierPark.DECK_TOP, "glow %s stands over the pier's decks" % str(p))


func _sand() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/pier_wash.gdshaderinc")
	var sand := FileAccess.get_file_as_string("res://shaders/beach_sand.gdshader")
	var ocean := FileAccess.get_file_as_string("res://shaders/ocean.gdshader")
	_t._check(src.contains("uniform float pw_gain = 0.0") and sand.contains("pier_wash.gdshaderinc") and ocean.contains("pier_wash.gdshaderinc")
		and sand.contains("if (pw_gain > 0.0") and ocean.contains("if (pw_gain > 0.0"),
		"the sand and the sea take the piers' light behind pw_gain (0 by default)")
	var m := PropFactory.beach_sand_material()
	RcPierNight.push(m)
	var lines := Weather.pier_light_lines()
	_t._check(int(m.get_shader_parameter("pw_count")) == mini(lines.size(), 10) and lines.size() <= 10
		and float(m.get_shader_parameter("pw_gain")) == RcPierNight.SAND_GAIN,
		"the sand takes the %d lamp rows the ocean mirrors" % lines.size())
	# RANDO PIER's two rows face each other across the deck.
	var a := RcPierNight.pier_anchor()
	var sides := 0
	for i in lines.size():
		var l: Vector4 = (lines[i] as Array)[0]
		if absf(l.x - (a.x - 20.0)) > 0.1:
			continue
		var dir := (Vector2(l.z, l.w) - Vector2(l.x, l.y)).normalized()
		var m2 := Vector2(-dir.y, dir.x)
		var to_axis := signf((Vector2(l.x, a.y) - Vector2(l.x, l.y)).dot(m2))
		if RcPierNight.deck_side(lines, i) == to_axis:
			sides += 1
	_t._check(sides == 2, "RANDO PIER's deck is on the inner side of both its rows (%d of 2)" % sides)


func _strollers(city: Node3D) -> void:
	var plan := _plan(city)
	var a := RcPierNight.pier_anchor()
	var z0 := a.y + 10.0
	var z1 := a.y + 110.0
	_t._check(RcPierNight.stroller_count(plan, z0, z1, 21.0, 1.0) > 0, "strollers by the pier at 21:00")
	_t._check(RcPierNight.stroller_count(plan, z0, z1, 15.0, 1.0) == 0 and RcPierNight.stroller_count(plan, z0, z1, 3.0, 1.0) == 0,
		"none by day (the beach's own crowd) or at 3:00")
	_t._check(RcPierNight.stroller_count(plan, z0, z1, 21.0, 0.05) == 0, "none in the rain")
	_t._check(RcPierNight.stroller_count(plan, a.y - 2100.0, a.y - 2000.0, 21.0, 1.0) == 0, "none far from every pier")
	var src := FileAccess.get_file_as_string("res://scripts/npc/beach_walker.gd")
	_t._check(src.contains("var clothed: bool = false") and src.contains("BonfireFigure.clothe("),
		"a stroller is dressed in street clothes")
