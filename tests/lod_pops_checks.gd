extends RefCounted
## Popping (LodFade; docs/HANDOFF.md "Popping while driving and flying"), for tests/smoke_test.gd.
## Loaded at run time, not named there, so it compiles after the autoloads.
##
## Pins the margin rule, what soften() changes and what it leaves, the crowd tier band, and - with
## the watcher forced on (headless is not Forward+, where it installs itself) - that a hard range
## added to the city is softened within a few frames, and that a car's parts are left alone (an
## alpha fade shows a body through itself). Puts everything back.

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	_margins()
	_soften()
	_bands()
	await _watcher(city)


func _margins() -> void:
	_t._check(is_equal_approx(LodFade.margin_for(30.0), 3.6) and LodFade.margin_for(5.0) == LodFade.MIN_MARGIN
		and LodFade.margin_for(9000.0) == LodFade.MAX_MARGIN,
		"lod pops: a margin is 12 percent of the range, 2 m at least, 40 m at most (30 m -> %.2f)" % LodFade.margin_for(30.0))


func _soften() -> void:
	var g := MeshInstance3D.new()
	g.visibility_range_end = 75.0
	var changed := LodFade.soften(g)
	_t._check(changed and g.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		and is_equal_approx(g.visibility_range_end_margin, 9.0) and g.visibility_range_end == 75.0,
		"lod pops: a hard end gets a fading margin and keeps its distance")
	var far := MeshInstance3D.new()
	far.visibility_range_begin = 30.0
	LodFade.soften(far)
	_t._check(far.visibility_range_begin_margin > 0.0 and far.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF,
		"lod pops: a hard begin (a far twin) fades in too")
	var kept := MeshInstance3D.new()
	kept.visibility_range_end = 100.0
	kept.visibility_range_end_margin = 2.0
	kept.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_t._check(not LodFade.soften(kept) and kept.visibility_range_end_margin == 2.0,
		"lod pops: a range that already fades is left as it was")
	var hard := MeshInstance3D.new()
	hard.visibility_range_end = 50.0
	hard.set_meta("lod_hard", true)
	var none := MeshInstance3D.new()
	_t._check(not LodFade.soften(hard) and hard.visibility_range_end_margin == 0.0 and not LodFade.soften(none),
		"lod pops: a node marked lod_hard, and a node with no range, are not touched")
	for n in [g, far, kept, hard, none]:
		n.free()


func _bands() -> void:
	var th := [45.0, 50.0, 140.0]
	_t._check(LodFade.tier_band(1, 2, 51.0, th) == 1 and LodFade.tier_band(1, 2, 54.5, th) == 2,
		"lod pops: a crowd body moves out a tier only TIER_BAND past its threshold")
	_t._check(LodFade.tier_band(2, 1, 48.0, th) == 2 and LodFade.tier_band(2, 1, 45.5, th) == 1,
		"lod pops: and comes back in only TIER_BAND inside it")
	_t._check(LodFade.tier_band(0, 3, 200.0, th) == 3 and LodFade.tier_band(3, 0, 10.0, th) == 0,
		"lod pops: a jump over several tiers (a teleport) lands at once")


func _watcher(city: Node3D) -> void:
	var was_force := LodFade.force
	LodFade.force = true
	var had := is_instance_valid(LodFade._node)
	if not had:
		LodFade.install(city)
	var node := MeshInstance3D.new()
	node.name = "LodPopsProbe"
	node.visibility_range_end = 60.0
	city.add_child(node)
	var ok := false
	for i in 8:
		await city.get_tree().process_frame
		if node.visibility_range_end_margin > 0.0:
			ok = true
			break
	_t._check(ok and node.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF,
		"lod pops: the watcher softens a hard range added to the city within a few frames")
	node.get_parent().remove_child(node)
	node.free()
	# Nothing under a vehicle is alpha-faded (it showed the body through itself), and the car's
	# own crossfade (CarLodBlend) on free-standing meshes, never in the city: a Vehicle built here
	# changed what the next file's twice-built block got.
	var veh := Node3D.new()
	veh.add_to_group("vehicle")
	var part := MeshInstance3D.new()
	part.visibility_range_end = 30.0
	veh.add_child(part)
	_t._check(not LodFade.soften(part) and part.visibility_range_end_margin == 0.0,
		"lod pops: a vehicle's parts are never alpha-faded")
	veh.free()
	_car_blend()
	if not had and is_instance_valid(LodFade._node):
		var n2: Node = LodFade._node
		n2.get_parent().remove_child(n2)
		n2.free()
		LodFade._node = null
	LodFade.force = was_force
	await city.get_tree().process_frame
	await city.get_tree().process_frame


func _car_blend() -> void:
	var was := LodFade.force
	LodFade.force = true
	var paint := ShaderMaterial.new()
	paint.shader = Vehicle.PAINT_SHADER
	var trim := StandardMaterial3D.new()
	var box := BoxMesh.new()
	var near := MeshInstance3D.new()
	near.mesh = box
	near.set_surface_override_material(0, paint)
	near.visibility_range_end = 30.0
	var near_trim := MeshInstance3D.new()
	near_trim.mesh = box
	near_trim.set_surface_override_material(0, trim)
	near_trim.visibility_range_end = 30.0
	var far := MeshInstance3D.new()
	far.mesh = box
	far.set_surface_override_material(0, paint)
	far.visibility_range_begin = 30.0
	var car := Node3D.new()
	var nears: Array[MeshInstance3D] = [near, near_trim]
	var fars: Array[MeshInstance3D] = [far]
	CarLodBlend.apply(car, nears, fars, 30.0)
	var fp := far.get_surface_override_material(0) as ShaderMaterial
	var tm := near_trim.get_surface_override_material(0) as StandardMaterial3D
	var lo := 30.0 - CarLodBlend.BAND * 0.5
	var hi := 30.0 + CarLodBlend.BAND * 0.5
	_t._check(near.visibility_range_end > hi and far.visibility_range_begin < lo and fp != paint and fp != null
		and paint.get_shader_parameter("lod_blend") == Vector3(lo, hi, 0.0) and fp.get_shader_parameter("lod_blend") == Vector3(lo, hi, 1.0),
		"lod pops: a car's near body and far twin overlap past the band, the far one on its own paint copy (far side)")
	_t._check(tm != null and tm != trim and tm.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_OBJECT_DITHER
		and is_equal_approx(tm.distance_fade_min_distance, hi) and is_equal_approx(tm.distance_fade_max_distance, lo),
		"lod pops: the glTF parts fade out by the same dither (OBJECT_DITHER, %.0f -> %.0f m)" % [hi, lo])
	CarLodBlend.revert(car)
	_t._check(near.visibility_range_end == 30.0 and far.visibility_range_begin == 30.0 and far.get_surface_override_material(0) == paint
		and near_trim.get_surface_override_material(0) == trim and paint.get_shader_parameter("lod_blend") == Vector3.ZERO,
		"lod pops: the first hit puts the hard swap back (CarDamage copies the paint)")
	for n in [near, near_trim, far, car]:
		n.free()
	var src := FileAccess.get_file_as_string("res://shaders/car_paint.gdshaderinc") + FileAccess.get_file_as_string("res://shaders/car_glass.gdshader")
	_t._check(src.count("lod_blend_cut(") == 2 and FileAccess.get_file_as_string("res://shaders/lod_blend.gdshaderinc").contains("52.9829189"),
		"lod pops: the paint and the cabin glass carry the screen door, StandardMaterial3D's noise")
	LodFade.force = was
