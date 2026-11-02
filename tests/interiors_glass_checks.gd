extends RefCounted
## The glass at arm's length (InteriorsGlass; shaders/interior_people.gdshaderinc, shop_interior.gdshaderinc,
## window_rooms.gdshaderinc, building.gdshader, shop_spill.gdshader) for tests/smoke_test.gd. Loaded at
## run time (not named there), so it compiles after the autoloads.
## Checks: the switch and its global; the near walls trace people in the shops (laid out by
## shop_person() against the fittings, behind the switch and the near distance) and the homes' and
## offices' people as bodies near the camera with the old capsules as the fallback; the fittings'
## light (scallops, floor pools, the mirrored fittings) is behind the switch; the storefront mirror is
## stronger by day only; every open shop's pool on the pavement carries its window (pitch, bays,
## reach) for shop_spill.gdshader, which keeps the old dot's numbers when off.

var _t: Node


func run(t: Node, _city: Node3D) -> void:
	_t = t
	var t0 := Time.get_ticks_msec()
	_check(InteriorsGlass.enabled, "interiors glass: on (INTERIORS_GLASS is not 0)")
	_switch()
	_shaders()
	_spill()
	print("INTERIORS_GLASS_CHECKS %d ms" % (Time.get_ticks_msec() - t0))


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _switch() -> void:
	_check(ProjectSettings.has_setting("shader_globals/interiors_glass"),
		"interiors glass: the interiors_glass global is declared")
	var was := InteriorsGlass.enabled
	InteriorsGlass.set_enabled(false)
	# The dummy renderer (headless) keeps no globals: null there.
	var off_raw = RenderingServer.global_shader_parameter_get("interiors_glass")
	var off := float(off_raw) if off_raw != null else 0.0
	InteriorsGlass.set_enabled(true)
	var on_raw = RenderingServer.global_shader_parameter_get("interiors_glass")
	var on := float(on_raw) if on_raw != null else 1.0
	InteriorsGlass.set_enabled(was)
	_check(is_zero_approx(off) and is_equal_approx(on, 1.0) and InteriorsGlass.enabled == was,
		"INTERIORS_GLASS=0 reaches the shaders and the switch puts it back (global %.0f / %.0f)" % [off, on])


func _shaders() -> void:
	var near := FileAccess.get_file_as_string("res://shaders/building.gdshader")
	var people := "#include \"res://shaders/interior_people.gdshaderinc\""
	var shops := "#include \"res://shaders/shop_interior.gdshaderinc\""
	_check(near.find(people) >= 0 and near.find(people) < near.find(shops),
		"interiors glass: the near walls include the people before the shops that use them")
	_check(near.contains("TIME, shop_open ||") and near.contains("ip_shop_mirror_day, ip_on() * (1.0 - night_factor) * (1.0 - smoothstep(60.0, 110.0, length(VERTEX)))"),
		"interiors glass: the shops get the clock and whether they trade, and a stronger mirror by day, near only (the far boxes keep step)")
	var inc := FileAccess.get_file_as_string("res://shaders/shop_interior.gdshaderinc")
	var bad: Array = []
	for s: String in ["bool shop_person(", "ip_trace(ro, rd, pat, pyaw, ppose", "bool people = ip_on() > 0.5 && dist < IP_NEAR;",
			"bid = SI_PERSON;", "float shop_scallop(", "if (ip_on() > 0.5 && dist < shop_fittings_distance)", "ip_foot_shadow("]:
		if not inc.contains(s):
			bad.append(s)
	# A person per kind of room: every kind lays somebody out.
	for k: String in ["ROOM_RETAIL", "ROOM_CLOTHING", "ROOM_CAFE || kind == ROOM_RESTAURANT", "ROOM_LAUNDROMAT", "ROOM_BARBER", "ROOM_BANK"]:
		var at := inc.find("bool shop_person(")
		if inc.find("kind == " + k, at) < 0:
			bad.append(k)
	_check(bad.is_empty(), "interiors glass: the shops trace their people and their fittings' light behind the switch (%s)" % str(bad))
	var rooms := FileAccess.get_file_as_string("res://shaders/window_rooms.gdshaderinc")
	_check(rooms.count("ip_on() > 0.5 && dist < IP_NEAR") == 2 and rooms.count("wr_person(") >= 3,
		"interiors glass: homes and offices draw bodies near the camera and keep the capsules past it")
	var body := FileAccess.get_file_as_string("res://shaders/interior_people.gdshaderinc")
	_check(body.contains("global uniform float interiors_glass;") and body.contains("vec2 ip_body(") and body.contains("for (int i = 0; i < 28; i++)"),
		"interiors glass: a person is a body ray-marched within its box, a bounded march")


func _spill() -> void:
	var mesh := PropFactory.shop_spill()
	var mat := mesh.surface_get_material(0) as ShaderMaterial
	_check(mat != null and mat.shader.resource_path == "res://shaders/shop_spill.gdshader" and is_equal_approx(float(mat.get_shader_parameter("falloff")), 1.7),
		"interiors glass: the shop spill wears its own shader, with the old dot's falloff")
	var src := FileAccess.get_file_as_string("res://shaders/shop_spill.gdshader")
	_check(src.contains("float a = pow(r, falloff);") and src.contains("interiors_glass > 0.5 && v_custom.a > 0.5"),
		"interiors glass: off, the spill is the old soft dot")
	var n := 0
	var bad := 0
	for b in _t.get_tree().get_nodes_in_group("building"):
		for pool: Array in b.get("shop_pools"):
			n += 1
			if pool.size() < 3:
				bad += 1
				continue
			var c: Color = pool[2]
			if c.r <= 0.5 or c.g < 1.0 or c.b <= 1.0 or c.a != 1.0:
				bad += 1
	_check(n > 0 and bad == 0, "interiors glass: every open shop's pool carries its window (%d pools, %d without)" % [n, bad])
