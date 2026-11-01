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
		"lod pops: a margin is 12 % of the range, 2 m at least, 40 m at most (30 m -> %.2f)" % LodFade.margin_for(30.0))


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
	node.queue_free()
	# A car built now keeps its hard near / far swap: the alpha fade showed the body's own
	# underside and wheels through its paint (see LodFade._closed_body).
	var car: Node3D = load("res://scripts/vehicles/vehicle.gd").new()
	car.call("setup", 0, Color(0.5, 0.1, 0.1), 0)
	car.position = Vector3(0.0, -500.0, 0.0)
	car.set("gravity_scale", 0.0)
	city.add_child(car)
	for i in 4:
		await city.get_tree().process_frame
	var ranged := 0
	for g in car.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		if gi.visibility_range_end > 0.0 or gi.visibility_range_begin > 0.0:
			ranged += 1
	_t._check(ranged > 0 and not LodFade.soften(car.find_children("*", "GeometryInstance3D", true, false)[0] as GeometryInstance3D),
		"lod pops: a car's parts are never alpha-faded (%d ranged parts)" % ranged)
	car.queue_free()
	if not had and is_instance_valid(LodFade._node):
		LodFade._node.queue_free()
		LodFade._node = null
	LodFade.force = was_force
