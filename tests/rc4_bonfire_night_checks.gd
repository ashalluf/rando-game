extends RefCounted
## The bonfire_night refcam (wave 7, tools/refcams/cameras_w7.json; docs/HANDOFF.md "The beach
## bonfires at night"), for tests/smoke_test.gd. Loaded at run time, not named there.
##
## Checks: a ring whose spot a palm, the tower or a beach station takes is slid along the shore to
## a clear spot instead of dropped (Bonfires.slide_clear), never into another ring's room; a FULL
## beach chunk at 21:00 builds at least as many rings as with RC4_BONFIRE=0; a lit fire has its
## glow on bonfire_glow.gdshader (fog-free, zero at the edge) and flames that fade out still
## orange; the sand's night look is on and gated by the clock; the camera row and its key.

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var hour_was := Bonfires.force_hour
	var lit_was := Bonfires.force_lit
	var bl_was := BeachLife.force_hour
	_slide(plan)
	_shaders()
	_camera()
	Bonfires.force_hour = 21.0
	BeachLife.force_hour = 21.0
	Bonfires.force_lit = 1
	_chunk(city, plan)
	Bonfires.force_hour = hour_was
	Bonfires.force_lit = lit_was
	BeachLife.force_hour = bl_was
	Bonfires.rc4 = true


func _slide(plan: CityPlan) -> void:
	var rings: Array = Bonfires.rings_in(plan, 100.0, 1300.0)
	var ok := not rings.is_empty()
	var tried := 0
	for r: Dictionary in rings:
		var at: Vector2 = r.at
		var obstacles := [[at + Vector2(0.4, 0.3), 0.8]]
		var moved := Bonfires.slide_clear(plan, r, obstacles)
		if moved.is_empty():
			continue
		tried += 1
		var m: Vector2 = moved.at
		var w := plan.macro.beach_width_at(m.y)
		var a0 := (at.x - plan.macro.coast_x(at.y)) / plan.macro.beach_width_at(at.y)
		var a1 := (m.x - plan.macro.coast_x(m.y)) / w
		ok = ok and BeachLife._clear_of(obstacles, m, Bonfires.GROUP_CLEAR) and absf(m.y - at.y) <= 12.01 and absf(a1 - a0) < 1e-3 \
			and BeachLife.path_x(plan, m.y) - BeachLife.PATH_WIDTH * 0.5 - m.x >= Bonfires.GROUP_CLEAR + 0.6 and int(moved.k) == int(r.k)
	_t._check(ok and tried > rings.size() / 2, "a ring whose spot is taken slides along the shore to a clear one, same distance up the beach (%d of %d)" % [tried, rings.size()])
	Bonfires.rc4 = false
	var off := Bonfires.slide_clear(plan, rings[0], [[(rings[0] as Dictionary).at, 0.8]]) if not rings.is_empty() else {}
	Bonfires.rc4 = true
	_t._check(off.is_empty(), "with RC4_BONFIRE=0 a blocked ring is dropped as before")


func _shaders() -> void:
	var glow := FileAccess.get_file_as_string("res://shaders/bonfire_glow.gdshader")
	_t._check(glow.contains("blend_add") and glow.contains("fog_disabled") and glow.contains("smoothstep(0.2, 1.0, r)") and glow.contains("cs_out("),
		"the fire's glow is additive, fog-free, linear, and reaches zero at its quad's edge")
	var sand := FileAccess.get_file_as_string("res://shaders/beach_sand.gdshader")
	_t._check(sand.contains("uniform float night_look = 0.0;") and sand.contains("smoothstep(19.0, 19.8, city_hour)"),
		"the sand's night look defaults off in the shader and is gated by the clock (dusk untouched)")
	var mat := PropFactory.beach_sand_material()
	_t._check(float(mat.get_shader_parameter("night_look")) == (1.0 if Bonfires.rc4 else 0.0), "the beach sand material carries the night look")


func _camera() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w7.json"))
	var found := false
	if parsed is Dictionary:
		for c: Dictionary in parsed.get("cameras", []):
			found = found or (String(c.name) == "bonfire_night" and int(c.get("bonfire_lit", 0)) == 1 and float(c.hour) == 21.0)
	_t._check(found, "cameras_w7.json has the bonfire_night row at 21:00 with every ring lit")


func _chunk(city: Node3D, plan: CityPlan) -> void:
	# Beach blocks along the shore: with the slide every ring in the block's stretch that has room
	# is built; without it a palm or a station drops it.
	var best_on := -1
	var best_off := -1
	var spacing_ok := true
	var glow_ok := false
	var flames_ok := false
	for z in [-60.0, 300.0, 500.0, 700.0]:
		var k := plan.block_index_at(Vector2(plan.macro.coast_x(z) + 20.0, z))
		var counts := []
		for on in [true, false]:
			Bonfires.rc4 = on
			var c: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
			c.build()
			var rings: Array = c.get_meta("bonfires", [])
			counts.append(rings.size())
			if on:
				for i in rings.size():
					for j in range(i + 1, rings.size()):
						spacing_ok = spacing_ok and ((rings[i] as Dictionary).at as Vector2).distance_to((rings[j] as Dictionary).at) >= Bonfires.GROUP_CLEAR * 2.0
				for f in c.get_children():
					if f is BonfireFire and not glow_ok:
						var fire := f as BonfireFire
						fire._check()
						if not fire._built:
							fire._build()
						var g := fire.get_node_or_null("Glow") as MeshInstance3D
						glow_ok = g != null and g.mesh == BonfireFire.glow_mesh() and g.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						var ramp: Gradient = fire._flames.color_ramp
						var last := ramp.get_color(ramp.get_point_count() - 1)
						flames_ok = last.a == 0.0 and last.r > 0.3 and fire._flames.position.y > Bonfires.ASH_Y + 0.25
			c.queue_free()
		Bonfires.rc4 = true
		if int(counts[0]) - int(counts[1]) > best_on - best_off or best_on < 0:
			best_on = counts[0]
			best_off = counts[1]
	_t._check(best_on >= best_off and best_on > 0, "a FULL beach chunk builds at least the rings it did, more where palms stood (%d vs %d)" % [best_on, best_off])
	_t._check(spacing_ok, "slid rings keep a group's room from each other")
	_t._check(glow_ok, "a lit fire carries its glow, shadowless, on the shared glow material")
	_t._check(flames_ok, "the flames start over the ash and fade out while still orange")
