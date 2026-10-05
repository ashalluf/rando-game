extends RefCounted
## The beach on a warm afternoon (BeachLife, BeachFigure, BeachGoer, BeachActivity), for
## tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## Checks the tables (the shader's copy of the second colours), the day's curve (nobody at night, a
## full beach mid-afternoon, a few at sunset), that the plan is pure and world-anchored (two halves
## of a stretch plan the people the whole stretch does), that the front of the beach fills first,
## then builds a FULL beach chunk at 15:00 and checks the batches on the beach shader, a figure per
## planned person, the path, the activity, that a figure woken by a knock is a live BeachGoer, that
## gunfire nearby sends the nearest sunbathers running, that the block's own rolls (palms, the
## tower) did not move, the LOD chunk's dots, nobody at 23:00, and the cyclist's legs on the pedals
## (the IK, on a real rig's skeleton; the bakes themselves need mesh data, which the headless dummy
## renderer does not keep).

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_tables()
	_curve()
	_plan(plan)
	var k: Vector2i = _beach_block(plan)
	_t._check(k.x != 99999, "a beach chunk owns the shore near the Esplanade's north")
	if k.x != 99999:
		_full_chunk(city, k)
		_lod_chunk(city, k)
		_night_chunk(city, k)
	_ride(city)
	BeachLife.force_hour = -1.0


func _tables() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/beach_props.gdshader")
	var same := true
	for c: Color in BeachLife.CANVAS2:
		same = same and src.contains("vec3(%s, %s, %s)" % [_num(c.r), _num(c.g), _num(c.b)])
	_t._check(same and BeachLife.CANVAS2.size() <= 6, "beach_props.gdshader's CANVAS2 matches BeachLife.CANVAS2")
	var styles := true
	for m: int in BeachGoer.BEACH_MODELS:
		styles = styles and BeachGoer.STYLE_OF.has(m) and m < Pedestrian.MODELS.size()
	for m: int in BeachGoer.RIDER_MODELS:
		styles = styles and m in BeachGoer.BEACH_MODELS
	_t._check(styles, "every beach rig has a swimsuit style, every rider is a beach rig")


static func _num(v: float) -> String:
	var s := "%.2f" % v
	if s.ends_with("0") and not s.ends_with(".0"):
		s = s.substr(0, s.length() - 1)
	return s


func _curve() -> void:
	var night := BeachLife.density(23.0) + BeachLife.density(3.0)
	var peak := BeachLife.density(15.0)
	var dusk := BeachLife.density(19.2)
	var morning := BeachLife.density(9.0)
	_t._check(night == 0.0 and absf(peak - 1.0) < 1e-4 and dusk > 0.0 and dusk < 0.35 and morning > 0.05 and morning < peak,
		"the beach is empty at night, full at 15:00, a few left at dusk (%.2f) and filling in the morning (%.2f)" % [dusk, morning])


func _plan(plan: CityPlan) -> void:
	var z0 := 100.0
	var z1 := 400.0
	var whole: Dictionary = BeachLife.plan_stretch(plan, z0, z1, 1.0)
	var again: Dictionary = BeachLife.plan_stretch(plan, z0, z1, 1.0)
	var a: Dictionary = BeachLife.plan_stretch(plan, z0, 250.0, 1.0)
	var b: Dictionary = BeachLife.plan_stretch(plan, 250.0, z1, 1.0)
	var n := (whole.people as Array).size()
	_t._check(n > 60 and n == (again.people as Array).size() and str(whole.people) == str(again.people),
		"a beach's people are a pure plan (%d over 300 m of shore at 15:00)" % n)
	_t._check(n == (a.people as Array).size() + (b.people as Array).size(),
		"the plan is world-anchored: two halves of the shore hold the whole's people (%d vs %d + %d)" % [n, (a.people as Array).size(), (b.people as Array).size()])
	var front := 0
	var back := 0
	for p: Dictionary in whole.people:
		var at: Vector2 = p.at
		var across := (at.x - plan.macro.coast_x(at.y)) / plan.macro.beach_width_at(at.y)
		if across < 0.45:
			front += 1
		else:
			back += 1
	_t._check(front > back * 1.4, "people crowd the front of the beach and thin toward the back (%d front, %d back)" % [front, back])
	var dusk: Dictionary = BeachLife.plan_stretch(plan, z0, z1, BeachLife.density(19.2))
	var night: Dictionary = BeachLife.plan_stretch(plan, z0, z1, BeachLife.density(23.0))
	_t._check((dusk.people as Array).size() > 0 and (dusk.people as Array).size() < n / 3 and (night.people as Array).is_empty(),
		"a few people at dusk (%d), nobody at night" % (dusk.people as Array).size())
	var court_ok := true
	for p: Dictionary in whole.people:
		if not (whole.court as Dictionary).is_empty() and BeachLife._near_court(whole.court, p.at, 0.0):
			court_ok = false
	_t._check(court_ok, "nobody lies on the volleyball court")


## A beach block clear of the landmarks' stretches (default seed: the shore north of the piers).
func _beach_block(plan: CityPlan) -> Vector2i:
	for z in [300.0, 500.0, 700.0, -900.0, 100.0]:
		var x := plan.macro.coast_x(z) + 20.0
		var k := plan.block_index_at(Vector2(x, z))
		var block: Dictionary = plan.block(k.x, k.y)
		var r: Rect2 = block.rect
		if not BeachLife.kept_off(plan, r.get_center().y):
			return k
	return Vector2i(99999, 99999)


func _batch(chunk: Node, key: String) -> MultiMeshInstance3D:
	for c in chunk.get_children():
		if c is MultiMeshInstance3D and String(c.name) == "Batch_" + key:
			return c
	return null


func _figures(chunk: Node) -> Array:
	return chunk.get_children().filter(func(c: Node) -> bool: return c is BeachFigure)


func _full_chunk(city: Node3D, k: Vector2i) -> void:
	BeachLife.force_hour = 15.0
	var chunk: CityChunk = null
	# The chunk that owns the shore at this block's z (the beach is built by the one the waterline
	# runs through).
	for dx in range(-2, 3):
		var c: CityChunk = city._new_chunk(Vector2i(k.x + dx, k.y), CityChunk.Level.FULL)
		c.build()
		if c.has_meta("beach_plan"):
			chunk = c
			break
		c.queue_free()
	_t._check(chunk != null, "a FULL beach chunk builds its beach life")
	if chunk == null:
		return
	var stretch: Dictionary = chunk.get_meta("beach_plan")
	var towels := _batch(chunk, "beach_towel")
	var umbrellas := _batch(chunk, "beach_umbrella")
	_t._check(towels != null and umbrellas != null and towels.multimesh.mesh.surface_get_material(0) == BeachLife.material(),
		"towels and umbrellas are batches on the beach shader (%d towels, %d umbrellas)" % [towels.multimesh.instance_count if towels else 0, umbrellas.multimesh.instance_count if umbrellas else 0])
	var figs := _figures(chunk)
	var planned := (stretch.people as Array).size()
	_t._check(figs.size() >= planned and figs.size() <= planned + 1 and planned > 20,
		"a static figure for every planned sunbather (%d planned, %d figures)" % [planned, figs.size()])
	_t._check(chunk.get_node_or_null("BikePath") != null, "the bike path is laid along the back of the sand")
	var act := chunk.get_node_or_null("BeachActivity") as BeachActivity
	_t._check(act != null, "the chunk has its beach activity (water, path, volleyball, walkers)")
	# The block's own rolls: the same palms with the beach life off (the path only nudges one off
	# it), and the tower in the same place.
	BeachLife.enabled = false
	var plain: CityChunk = city._new_chunk(Vector2i(chunk.ix, chunk.iz), CityChunk.Level.FULL)
	plain.build()
	BeachLife.enabled = true
	var palms_a := 0
	var palms_b := 0
	for c in chunk.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("Batch_palm_"):
			palms_a += (c as MultiMeshInstance3D).multimesh.instance_count
	for c in plain.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("Batch_palm_"):
			palms_b += (c as MultiMeshInstance3D).multimesh.instance_count
	var tower_a := _batch(chunk, "beach_tower") != null
	var tower_b := _batch(plain, "lifeguard_cabin") != null
	_t._check(palms_a == palms_b and tower_a == tower_b, "the block's palms and tower roll as before (%d palms, tower %s)" % [palms_a, str(tower_a)])
	plain.queue_free()
	# Knocked: the figure is a live BeachGoer.
	var first: BeachFigure = figs[0] if not figs.is_empty() else null
	var woke: RoughSleeper = first.wake() if first else null
	_t._check(woke is BeachGoer and woke.is_in_group("pedestrian") and (woke as BeachGoer).beach_pose == first.beach_pose,
		"a woken figure is a live BeachGoer in the same pose")
	# Gunfire on the beach: the nearest sunbathers get up and run.
	if act and figs.size() > 4:
		var target: BeachFigure = figs[figs.size() / 2]
		Pedestrian._last_alarm_ms -= 1000
		Pedestrian.alarm(chunk.get_tree(), target.global_position, 40.0, 0, true, "")
		for i in 6:
			act._scatter()
		var running := 0
		for c in chunk.get_children():
			if c is BeachGoer and not (c as BeachGoer)._down and (c as BeachGoer)._state == RoughSleeper.State.FLEE:
				running += 1
		_t._check(running >= 4, "gunfire on the beach sends the nearest sunbathers running (%d)" % running)
	chunk.queue_free()


func _lod_chunk(city: Node3D, k: Vector2i) -> void:
	BeachLife.force_hour = 15.0
	var found := false
	for dx in range(-2, 3):
		var c: CityChunk = city._new_chunk(Vector2i(k.x + dx, k.y), CityChunk.Level.LOD)
		c.build()
		if _batch(c, "beach_dot_towel") != null:
			found = _batch(c, "beach_dot_towel").cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			c.queue_free()
			break
		c.queue_free()
	_t._check(found, "a LOD beach chunk draws its towels as dots of colour, with no shadow")


func _night_chunk(city: Node3D, k: Vector2i) -> void:
	BeachLife.force_hour = 23.0
	var people := -1
	for dx in range(-2, 3):
		var c: CityChunk = city._new_chunk(Vector2i(k.x + dx, k.y), CityChunk.Level.FULL)
		c.build()
		if c.has_meta("beach_plan"):
			people = _figures(c).size() + c.get_children().filter(func(n: Node) -> bool: return n is BeachRider or n is BeachWalker).size()
			c.queue_free()
			break
		c.queue_free()
	_t._check(people == 0, "nobody on the beach at 23:00 (%d)" % people)


## The cyclist's legs: on a real rig, at four crank angles, each ankle within a few centimetres of
## where its pedal puts it.
func _ride(city: Node3D) -> void:
	var ped := BeachGoer.new()
	ped.setup_sleeper(Rect2(0.0, 0.0, 10.0, 10.0), 2.0, BeachGoer.seed_for(BeachGoer.RIDER_MODELS[0], 0), RoughSleeper.Pose.CHAIR, Vector2.ZERO, 0.0)
	ped.position = Vector3(0.0, -3000.0, 0.0)
	city.add_child(ped)
	var worst := 0.0
	var ok := ped._skel != null
	for k in 4:
		var fit := ped.ride_pose(TAU * float(k) / 4.0)
		if fit.is_empty():
			ok = false
			break
		var skel := ped._skel
		skel.force_update_all_bone_transforms()
		var to_local := ped.global_transform.affine_inverse() * skel.global_transform
		for side: String in ["Left", "Right"]:
			var ankle := to_local * skel.get_bone_global_pose(skel.find_bone(side + "Foot")).origin
			var pedal: Vector3 = fit["pedal_l" if side == "Left" else "pedal_r"]
			# The ankle rides 7 cm over the spindle and 4 cm behind it (forward is -z here).
			var want := pedal + Vector3(0.0, 0.07, 0.04)
			worst = maxf(worst, ankle.distance_to(want))
	_t._check(ok and worst < 0.05, "a cyclist's ankles follow the pedals round the crank (worst %.3f m)" % worst)
	ped.queue_free()
