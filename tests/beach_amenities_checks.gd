extends RefCounted
## The beach's public amenities (BeachAmenities), for tests/smoke_test.gd. Loaded at run time, not
## named there, so it compiles after the autoloads.
##
## Checks the plan is pure and world-anchored (two halves of a stretch plan what the whole does),
## that every kind turns up along the coast, that nothing stands in anything else, on BeachLife's
## court or on a stretch the beach keeps off, that the stand's shutter follows the hour; then
## builds the FULL beach chunk that holds a station and checks its batches on the amenities shader,
## that BeachLife's sunbathers keep off every item, that the block's palms and tower roll as before
## with the amenities off, and that a LOD chunk draws the buildings as boxes.

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var was := BeachAmenities.enabled
	BeachAmenities.enabled = true
	_plan(plan)
	_tables()
	var z := _station_z(plan)
	_t._check(z != INF, "a restroom or concession stand stands on the open beach")
	if z != INF:
		_full_chunk(city, plan, z)
		_lod_chunk(city, plan, z)
	BeachAmenities.enabled = was
	BeachLife.force_hour = -1.0


func _plan(plan: CityPlan) -> void:
	var z0 := -4000.0
	var z1 := 6000.0
	var whole: Array = BeachAmenities.plan_stretch(plan, z0, z1)
	var again: Array = BeachAmenities.plan_stretch(plan, z0, z1)
	var a: Array = BeachAmenities.plan_stretch(plan, z0, 600.0)
	var b: Array = BeachAmenities.plan_stretch(plan, 600.0, z1)
	_t._check(whole.size() > 20 and str(whole) == str(again), "the beach's amenities are a pure plan (%d items over the whole coast, z -4000..6000)" % whole.size())
	_t._check(whole.size() == a.size() + b.size() and str(_sorted(whole)) == str(_sorted(a + b)),
		"the amenities are world-anchored: two halves of the shore hold the whole's (%d vs %d + %d)" % [whole.size(), a.size(), b.size()])
	# Which kinds exist is counted over more coast: the power plant, the marina and the coast
	# highway take stretches of the 4 km above, and a seed may leave a rare kind out of it.
	var counts := {}
	for it: Dictionary in BeachAmenities.plan_stretch(plan, -2500.0, 4000.0):
		counts[String(it.kind)] = int(counts.get(String(it.kind), 0)) + 1
	var every := true
	for k: String in ["restroom", "concession", "gym", "court", "shower", "rack", "can"]:
		every = every and int(counts.get(k, 0)) > 0
	_t._check(every, "every kind stands somewhere on the coast %s" % str(counts))
	# Nothing in anything else (the drum pairs stand 0.75 m apart, their halves 0.35).
	var clash := ""
	for i in whole.size():
		var p: Dictionary = whole[i]
		for j in range(i + 1, whole.size()):
			var q: Dictionary = whole[j]
			if BeachAmenities._overlaps(p.at, p.half, q.at, q.half, -0.02):
				clash = "%s at %s and %s at %s" % [p.kind, str(p.at), q.kind, str(q.at)]
	_t._check(clash == "", "no amenity stands in another %s" % clash)
	# Off BeachLife's courts and the stretches the beach keeps off.
	var courts := BeachLife.courts_in(plan, z0 - 50.0, z1 + 50.0)
	var off := ""
	for it: Dictionary in whole:
		var at: Vector2 = it.at
		for c: Dictionary in courts:
			if String(it.kind) != "court" and BeachLife._near_court(c, at, maxf((it.half as Vector2).x, (it.half as Vector2).y)):
				off = "%s on a court at %s" % [it.kind, str(at)]
		if BeachAmenities.off(plan, at.y) and String(it.kind) != "can":
			off = "%s on a kept-off stretch at %s" % [it.kind, str(at)]
		var w := plan.macro.beach_width_at(at.y)
		var across := (at.x - plan.macro.coast_x(at.y)) / maxf(w, 1.0)
		if across < 0.2 or across > 1.0:
			off = "%s off the dry sand (%.2f) at %s" % [it.kind, across, str(at)]
	_t._check(off == "", "every amenity stands on the dry sand, off BeachLife's courts and the kept-off stretches %s" % off)
	# The buildings and showers line the bike path's seaward side, clear of the path.
	var path_ok := true
	for it: Dictionary in whole:
		if String(it.kind) in ["restroom", "concession", "shower", "rack"]:
			var at: Vector2 = it.at
			var edge := BeachLife.path_x(plan, at.y) - BeachLife.PATH_WIDTH * 0.5
			path_ok = path_ok and at.x + (it.half as Vector2).y <= edge + 0.05
	_t._check(path_ok, "the buildings, showers and racks stand seaward of the bike path, off it")


static func _sorted(items: Array) -> Array:
	var keys: Array = []
	for it: Dictionary in items:
		keys.append("%s|%.2f|%.2f" % [it.mesh, (it.at as Vector2).x, (it.at as Vector2).y])
	keys.sort()
	return keys


func _tables() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/beach_amenities.gdshader")
	var codes := true
	for pair: Array in [[BeachAmenities.K_CONCRETE, "code == 1"], [BeachAmenities.K_BLOCK, "code == 2"], [BeachAmenities.K_PAINT, "code == 3"],
			[BeachAmenities.K_GALV, "code == 4"], [BeachAmenities.K_STAINLESS, "code == 5"], [BeachAmenities.K_CANVAS, "code == 7"],
			[BeachAmenities.K_LAMP, "code == 8"], [BeachAmenities.K_MENU, "code == 12"], [BeachAmenities.K_PAD, "code == 13"],
			[BeachAmenities.K_SHUTTER, "code == 15"], [BeachAmenities.K_SANDWOOD, "code == 16"]]:
		codes = codes and src.contains(String(pair[1]))
	_t._check(codes and BeachAmenities.material().shader != null, "beach_amenities.gdshader draws every kind BeachAmenities writes")
	var names := true
	for n: String in BeachAmenities.STAND_NAMES:
		names = names and n.length() <= 18
	_t._check(names, "the stands' invented names fit their fascia")


## The z of a restroom or concession on an ordinary stretch (clear of the replica and the piers).
func _station_z(plan: CityPlan) -> float:
	# The middle of the open shore first (the far north is the coast highway's, the far south the
	# replica's), then anywhere.
	for it: Dictionary in BeachAmenities.plan_stretch(plan, 300.0, 1400.0) + BeachAmenities.plan_stretch(plan, -1500.0, 2500.0):
		if String(it.kind) in ["restroom", "concession"]:
			return (it.at as Vector2).y
	return INF


func _batch(chunk: Node, key: String) -> MultiMeshInstance3D:
	for c in chunk.get_children():
		if c is MultiMeshInstance3D and String(c.name) == "Batch_" + key:
			return c
	return null


## The FULL chunk that builds the beach at z (the one the waterline runs through).
func _beach_chunk(city: Node3D, plan: CityPlan, z: float, level: int) -> CityChunk:
	var k := plan.block_index_at(Vector2(plan.macro.coast_x(z) + 20.0, z))
	for dx in range(-2, 3):
		var c: CityChunk = city._new_chunk(Vector2i(k.x + dx, k.y), level)
		c.build()
		if level == CityChunk.Level.FULL and c.has_meta("beach_amenities"):
			return c
		if level != CityChunk.Level.FULL and c.has_meta("beach_lod"):
			return c
		if level != CityChunk.Level.FULL and _batch(c, "beach_dot_towel") != null:
			return c
		c.queue_free()
	return null


func _full_chunk(city: Node3D, plan: CityPlan, z: float) -> void:
	BeachLife.force_hour = 15.0
	var chunk := _beach_chunk(city, plan, z, CityChunk.Level.FULL)
	_t._check(chunk != null, "a FULL beach chunk builds its amenities")
	if chunk == null:
		return
	var items: Array = chunk.get_meta("beach_amenities")
	var batches := 0
	var on_mat := true
	for c in chunk.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("Batch_bam_") and String(c.name) != "Batch_bam_pool":
			batches += 1
			on_mat = on_mat and (c as MultiMeshInstance3D).multimesh.mesh.surface_get_material(0) == BeachAmenities.material()
	_t._check(not items.is_empty() and batches > 0 and on_mat, "the chunk's amenities are batches on the amenities shader (%d items, %d batches)" % [items.size(), batches])
	var stand_open := _batch(chunk, "bam_concession_0") != null or _batch(chunk, "bam_concession_1") != null or _batch(chunk, "bam_concession_2") != null \
		or _batch(chunk, "bam_concession_3") != null or _batch(chunk, "bam_concession_4") != null
	var has_stand := false
	for it: Dictionary in items:
		has_stand = has_stand or String(it.kind) == "concession"
	_t._check(not has_stand or stand_open, "the stand's shutter is up at 15:00")
	# BeachLife's sunbathers keep off every amenity.
	var stretch: Dictionary = chunk.get_meta("beach_plan", {})
	var on_top := 0
	for p: Dictionary in stretch.get("people", []):
		for it: Dictionary in items:
			if BeachAmenities._overlaps(p.at, Vector2(0.5, 0.5), it.at, it.half, -0.3):
				on_top += 1
	_t._check(on_top == 0, "nobody sunbathes in a restroom, a gym or under a shower (%d)" % on_top)
	# The block's own rolls: the same palms and tower with the amenities off, no amenity batches.
	BeachAmenities.enabled = false
	var plain: CityChunk = city._new_chunk(Vector2i(chunk.ix, chunk.iz), CityChunk.Level.FULL)
	plain.build()
	BeachAmenities.enabled = true
	var palms := [0, 0]
	var bam_off := 0
	for i in 2:
		for c in ([chunk, plain][i] as Node).get_children():
			if c is MultiMeshInstance3D and String(c.name).begins_with("Batch_palm_"):
				palms[i] += (c as MultiMeshInstance3D).multimesh.instance_count
			if i == 1 and c is MultiMeshInstance3D and String(c.name).begins_with("Batch_bam_"):
				bam_off += 1
	_t._check(palms[0] == palms[1] and (_batch(chunk, "beach_tower") != null) == (_batch(plain, "beach_tower") != null) and bam_off == 0 and not plain.has_meta("beach_amenities"),
		"BEACH_AMENITIES=0 builds the same palms and tower and no amenities (%d / %d palms)" % [palms[0], palms[1]])
	plain.queue_free()
	# At night the stand is shut.
	if has_stand:
		BeachLife.force_hour = 23.0
		var night: CityChunk = city._new_chunk(Vector2i(chunk.ix, chunk.iz), CityChunk.Level.FULL)
		night.build()
		var shut := false
		for c in night.get_children():
			shut = shut or (c is MultiMeshInstance3D and String(c.name).begins_with("Batch_bam_concession") and String(c.name).ends_with("_shut"))
		_t._check(shut, "the stand's shutter is down at 23:00")
		night.queue_free()
		BeachLife.force_hour = 15.0
	chunk.queue_free()


func _lod_chunk(city: Node3D, plan: CityPlan, z: float) -> void:
	var k := plan.block_index_at(Vector2(plan.macro.coast_x(z) + 20.0, z))
	var found := false
	for dx in range(-2, 3):
		BeachAmenities.enabled = false
		var off: CityChunk = city._new_chunk(Vector2i(k.x + dx, k.y), CityChunk.Level.LOD)
		off.build()
		BeachAmenities.enabled = true
		var on: CityChunk = city._new_chunk(Vector2i(k.x + dx, k.y), CityChunk.Level.LOD)
		on.build()
		var a := _batch(off, "lod_box")
		var b := _batch(on, "lod_box")
		var na := a.multimesh.instance_count if a else 0
		var nb := b.multimesh.instance_count if b else 0
		off.queue_free()
		on.queue_free()
		if nb > na:
			found = true
			break
	_t._check(found, "a LOD beach chunk draws the restroom or the stand as a box")
