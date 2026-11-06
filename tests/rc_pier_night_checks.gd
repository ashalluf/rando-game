extends RefCounted
## The pier at night (PierNight, the pier_night reference camera), for tests/smoke_test.gd. Loaded
## at run time, not named there, so it compiles after the autoloads.
##
## Checks: the wheel's glow shader and the LED include compile into the materials and agree with
## the wheel (hub, omega, radius, spokes); the shared LED include is the one pier_park reads; the
## halos (every lamp globe, coaster bulbs on both rails all the way round, thinned for the far
## copy, nothing on the deck's walking surface); a built park (near and far) carries the wheel's
## glow and one halo MultiMesh, shadowless; the coaster's near track carries the bulbs; the A/B
## builds neither; the painted cumulus' night light uniforms exist in the sky shader.

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	var was := PierNight.enabled
	PierNight.enabled = true
	_shaders()
	_points()
	_build(city)
	PierNight.enabled = was


func _shaders() -> void:
	var park := FileAccess.get_file_as_string("res://shaders/pier_park.gdshader")
	var glow := FileAccess.get_file_as_string("res://shaders/pier_wheel_glow.gdshader")
	_t._check(park.contains("pier_led.gdshaderinc") and glow.contains("pier_led.gdshaderinc") and not park.contains("vec3 led_pattern("),
		"the wheel's LEDs and their glow run one pattern include")
	var mesh: ArrayMesh = PierNight._wheel_glow_mesh()
	var mat := mesh.surface_get_material(0) as ShaderMaterial
	_t._check(mat != null and mat.shader != null and is_equal_approx(float(mat.get_shader_parameter("omega")), FerrisWheel.OMEGA)
		and is_equal_approx(float(mat.get_shader_parameter("radius")), FerrisWheel.RADIUS)
		and is_equal_approx(float(mat.get_shader_parameter("spokes")), float(FerrisWheel.SPOKES))
		and (mat.get_shader_parameter("hub") as Vector3).is_equal_approx(Vector3(0.0, FerrisWheel.HUB_H, 0.0)),
		"the wheel's glow turns with the wheel (hub, omega, radius, spokes)")
	var aabb := mesh.get_aabb()
	_t._check(aabb.size.x >= FerrisWheel.RADIUS * 3.0 and absf(aabb.get_center().y - FerrisWheel.HUB_H) < 0.01
		and absf(aabb.size.z - 2.0 * (FerrisWheel.RIM_Z + 0.16)) < 0.01,
		"the glow's quads span the wheel and stand just proud of its LEDs (%s)" % str(aabb))
	_t._check(glow.contains("1.0 - smoothstep(radius * 1.3, radius * 1.55, r)") and FerrisWheel.RADIUS * 1.6 > FerrisWheel.RADIUS * 1.55,
		"the air's glow reaches zero inside its quad (an additive tail draws the quad on Forward+)")
	var sky := FileAccess.get_file_as_string("res://shaders/sky.gdshader")
	_t._check(sky.contains("uniform float painted_night_gain") and sky.contains("uniform float painted_city_light"),
		"the painted cumulus carry their night light uniforms")


func _points() -> void:
	var deck := PierPark.DECK_TOP
	var cp := PierNight.coaster_points(deck)
	var per_side := int(ceil((PierCoaster.length - 0.5) / PierNight.BULB_STEP))
	_t._check(cp.size() == per_side * 2, "a coaster bulb every %.1f m on both rails (%d)" % [PierNight.BULB_STEP, cp.size()])
	var off_track := 0
	for pt: Array in cp:
		var p: Vector3 = pt[0]
		if p.y < deck + 0.2:
			off_track += 1
	_t._check(off_track == 0, "no coaster bulb sits on the deck (%d)" % off_track)
	var near := PierNight.halo_points(deck, false)
	var far := PierNight.halo_points(deck, true)
	var lamps := 0
	for h: Array in near:
		if is_equal_approx(float(h[1]), PierNight.LAMP_HALO):
			lamps += 1
	_t._check(lamps == PierPark.LAMP_COUNT * 4, "a halo on every lamp globe (%d)" % lamps)
	_t._check(far.size() < near.size() * 0.5 and far.size() > PierPark.LAMP_COUNT * 4,
		"the far copy keeps every lamp and thins the bulbs (%d of %d)" % [far.size(), near.size()])


## Builds the park in the tree (the coaster's train looks nodes up) far off under the city, and frees it.
func _build(city: Node3D) -> void:
	var holder := Node3D.new()
	holder.position = Vector3(0.0, -4000.0, 0.0)
	city.add_child(holder)
	PierPark.build(Vector2.ZERO, holder, null, null, true)
	var far := Node3D.new()
	far.position = Vector3(0.0, -4000.0, 0.0)
	city.add_child(far)
	PierPark.build(Vector2.ZERO, far, null, null, false)
	for h: Node3D in [holder, far]:
		var halos := h.find_children("PierHalos", "MultiMeshInstance3D", true, false)
		var glows := h.find_children("WheelGlow", "MeshInstance3D", true, false)
		_t._check(halos.size() == 1 and glows.size() == 1
			and (halos[0] as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			and (glows[0] as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"a built park carries one halo batch and the wheel's glow, shadowless (%d, %d)" % [halos.size(), glows.size()])
		h.free()
	PierNight.enabled = false
	var off := Node3D.new()
	off.position = Vector3(0.0, -4000.0, 0.0)
	city.add_child(off)
	PierPark.build(Vector2.ZERO, off, null, null, true)
	_t._check(off.find_children("PierHalos", "", true, false).is_empty() and off.find_children("WheelGlow", "", true, false).is_empty(),
		"PIER_NIGHT=0 builds the park as before")
	off.free()
	PierNight.enabled = true
	# The coaster's near track carries the bulbs (more triangles than without).
	var with_b: ArrayMesh = PierCoaster._track_mesh(PierPark.DECK_TOP, true)
	PierNight.enabled = false
	var without: ArrayMesh = PierCoaster._track_mesh(PierPark.DECK_TOP, true)
	PierNight.enabled = true
	var n_with := 0
	var n_without := 0
	for i in with_b.get_surface_count():
		n_with += with_b.surface_get_array_len(i)
	for i in without.get_surface_count():
		n_without += without.surface_get_array_len(i)
	_t._check(n_with > n_without, "the coaster's near track carries its chaser bulbs (%d > %d vertices)" % [n_with, n_without])
