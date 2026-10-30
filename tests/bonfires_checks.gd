extends RefCounted
## Beach bonfire rings (Bonfires, BonfireFire, BonfireFigure), for tests/smoke_test.gd. Loaded at
## run time, not named there, so it compiles after the autoloads.
##
## Checks the tables and the shader's copies, that the rings are a pure world-anchored plan above
## the tide line and clear of the bike path and the courts, the night's clock (lit after dusk, out
## by day, none in rain, a night past midnight is the evening's), that a group sits round its ring
## facing the fire, then builds a FULL beach chunk at 21:00 with every ring lit and checks the
## ring batch, a fire node and collision per ring, the fire's flames on the car fire's material,
## the light, the pool, a clothed figure per planned person that wakes into a clothed BeachGoer,
## the block's palms and tower unmoved with the rings off, the same chunk at 13:00 empty round
## its rings, and the LOD chunk's pools at night and none by day.

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var lit_was := Bonfires.force_lit
	_tables()
	_plan(plan)
	_clock(plan)
	var k := _beach_block(plan)
	_t._check(k.x != 99999, "a beach block with bonfire rings near the Esplanade's north")
	if k.x != 99999:
		_full_chunk(city, k)
		_day_chunk(city, k)
		_lod_chunk(city, k)
	Bonfires.force_hour = -1.0
	Bonfires.force_lit = lit_was
	BeachLife.force_hour = -1.0


func _tables() -> void:
	var ok := true
	for m: int in Bonfires.MODELS:
		ok = ok and m >= 0 and m < Pedestrian.MODELS.size()
	var w := 0.0
	for r: Array in Bonfires.POSES:
		w += float(r[0])
		ok = ok and (String(r[2]) == "" or BeachGoer.BEACH_POSES.has(String(r[2])))
	_t._check(ok and absf(w - 1.0) < 1e-4, "bonfire rigs exist and the poses' weights sum to 1 (%.3f)" % w)
	var src := FileAccess.get_file_as_string("res://shaders/bonfire.gdshader")
	_t._check(src.contains("ring_r = %s;" % str(Bonfires.RING_R)) and src.contains("ring_wall = %s;" % str(Bonfires.RING_WALL))
		and src.contains("ring_h = %s;" % str(Bonfires.RING_H)), "bonfire.gdshader's ring size matches Bonfires.RING_*")
	var m := Bonfires.ring_mesh()
	var aabb := m.get_aabb()
	_t._check(m.get_surface_count() == 1 and m.surface_get_material(0) == Bonfires.material() and absf(aabb.size.x - Bonfires.RING_R * 2.0) < 0.06
		and absf(aabb.end.y - Bonfires.RING_H) < 0.01, "the ring is one surface on the bonfire shader at its real size (%.2f x %.2f m)" % [aabb.size.x, aabb.end.y])
	var s := Bonfires.stack_mesh()
	_t._check(s.surface_get_material(0) == Bonfires.material(true) and s.surface_get_material(0) != Bonfires.material(false),
		"tonight's log stack wears the hot material (glowing coals)")


func _plan(plan: CityPlan) -> void:
	var a: Array = Bonfires.rings_in(plan, 100.0, 1300.0)
	var b: Array = Bonfires.rings_in(plan, 100.0, 1300.0)
	var h1: Array = Bonfires.rings_in(plan, 100.0, 700.0)
	var h2: Array = Bonfires.rings_in(plan, 700.0, 1300.0)
	_t._check(a.size() > 10 and str(a) == str(b), "the rings are a pure plan (%d along 1.2 km of shore)" % a.size())
	_t._check(a.size() == h1.size() + h2.size(), "the plan is world-anchored: two halves of the shore hold the whole's rings (%d vs %d + %d)" % [a.size(), h1.size(), h2.size()])
	var ok := true
	var courts := BeachLife.courts_in(plan, 0.0, 1400.0)
	var worst := 0.0
	for r: Dictionary in a:
		var at: Vector2 = r.at
		var w := plan.macro.beach_width_at(at.y)
		var across := (at.x - plan.macro.coast_x(at.y)) / w
		worst = maxf(worst, absf(across - 0.64))
		ok = ok and across > 0.4 and BeachLife.path_x(plan, at.y) - at.x > Bonfires.GROUP_CLEAR + BeachLife.PATH_WIDTH * 0.5
		for c: Dictionary in courts:
			ok = ok and not BeachLife._near_court(c, at, Bonfires.GROUP_CLEAR)
	_t._check(ok, "every ring stands above the tide line, clear of the bike path and the volleyball courts")


func _clock(plan: CityPlan) -> void:
	Bonfires.force_lit = -1
	var rings: Array = Bonfires.rings_in(plan, 100.0, 1300.0)
	var day_lit := 0
	var night_lit := 0
	var rain_lit := 0
	var late_lit := 0
	for r: Dictionary in rings:
		day_lit += int(Bonfires.lit_at(plan, r.k, 13.0, 3, Weather.State.CLEAR))
		night_lit += int(Bonfires.lit_at(plan, r.k, 21.0, 3, Weather.State.CLEAR))
		rain_lit += int(Bonfires.lit_at(plan, r.k, 21.0, 3, Weather.State.RAIN)) + int(Bonfires.lit_at(plan, r.k, 21.0, 3, Weather.State.SANTA_ANA))
		late_lit += int(Bonfires.lit_at(plan, r.k, 4.0, 4, Weather.State.CLEAR))
	var share := float(night_lit) / float(maxi(rings.size(), 1))
	_t._check(day_lit == 0 and late_lit == 0 and rain_lit == 0 and share > 0.25 and share < 0.95,
		"fires burn after dusk (%d of %d at 21:00), none by day, by 04:00, in rain or a Santa Ana" % [night_lit, rings.size()])
	var n: Array = Bonfires.night_of(1.5, 5)
	_t._check(int(n[0]) == 4 and absf(float(n[1]) - 25.5) < 1e-4, "01:30 belongs to the evening before (night 4, hour 25.5)")
	var ok := true
	var sizes := 0
	for r: Dictionary in rings:
		var g: Array = Bonfires.group(plan, r, 3)
		ok = ok and str(g) == str(Bonfires.group(plan, r, 3))
		ok = ok and g.size() >= Bonfires.GROUP.x and g.size() <= Bonfires.GROUP.y
		sizes += g.size()
		for p: Dictionary in g:
			var d: Vector2 = (r.at as Vector2) - (p.at as Vector2)
			var fwd := Vector2(-sin(float(p.yaw)), -cos(float(p.yaw)))
			ok = ok and d.length() > Bonfires.RING_R + 0.9 and d.length() < Bonfires.SEAT_R.y + 0.5 and fwd.dot(d.normalized()) > 0.9
	_t._check(ok, "each group sits round its ring facing the fire (%d people round %d rings)" % [sizes, rings.size()])


## A beach block whose stretch has rings (default seed: the shore north of the piers).
func _beach_block(plan: CityPlan) -> Vector2i:
	for z in [300.0, 500.0, 700.0, -900.0, 100.0, 900.0]:
		var x := plan.macro.coast_x(z) + 20.0
		var k := plan.block_index_at(Vector2(x, z))
		var r: Rect2 = plan.block(k.x, k.y).rect
		if not BeachLife.kept_off(plan, r.get_center().y) and Bonfires.rings_in(plan, r.position.y, r.end.y).size() >= 2:
			return k
	return Vector2i(99999, 99999)


func _batch(chunk: Node, key: String) -> MultiMeshInstance3D:
	for c in chunk.get_children():
		if c is MultiMeshInstance3D and String(c.name) == "Batch_" + key:
			return c
	return null


func _children(chunk: Node, cls: Variant) -> Array:
	return chunk.get_children().filter(func(c: Node) -> bool: return is_instance_of(c, cls))


func _chunk_with_rings(city: Node3D, k: Vector2i, level: CityChunk.Level) -> CityChunk:
	for dx in range(-2, 3):
		var c: CityChunk = city._new_chunk(Vector2i(k.x + dx, k.y), level)
		c.build()
		if level == CityChunk.Level.FULL and c.has_meta("bonfires") and not (c.get_meta("bonfires") as Array).is_empty():
			return c
		if level == CityChunk.Level.LOD and _batch(c, "bonfire_lod_pool") != null:
			return c
		c.queue_free()
	return null


func _full_chunk(city: Node3D, k: Vector2i) -> void:
	Bonfires.force_hour = 21.0
	BeachLife.force_hour = 21.0
	Bonfires.force_lit = 1
	var chunk := _chunk_with_rings(city, k, CityChunk.Level.FULL)
	_t._check(chunk != null, "a FULL beach chunk builds its bonfire rings")
	if chunk == null:
		return
	var rings: Array = chunk.get_meta("bonfires")
	var batch := _batch(chunk, "bonfire_ring")
	_t._check(batch != null and batch.multimesh.instance_count == rings.size() and batch.multimesh.mesh.surface_get_material(0) == Bonfires.material(),
		"the rings are one batch on the bonfire shader (%d rings)" % rings.size())
	var fires := _children(chunk, BonfireFire)
	_t._check(fires.size() == rings.size(), "a fire node in every ring (%d)" % fires.size())
	var planned := 0
	for r: Dictionary in rings:
		planned += Bonfires.group(chunk.plan, r, int(Bonfires.night_of(21.0, int(Bonfires.clock(chunk)[1]))[0])).size()
	var figs := _children(chunk, BonfireFigure)
	_t._check(planned > 0 and figs.size() == planned, "a clothed figure for everyone round the fires (%d planned, %d figures)" % [planned, figs.size()])
	_t._check(_batch(chunk, "bonfire_wood") != null, "a bundle of firewood beside every lit ring")
	if not fires.is_empty():
		var f: BonfireFire = fires[0]
		f._check()
		if not f._built:
			f._build()
		_t._check(f.lit and f._flames != null and f._flames.mesh.surface_get_material(0) == CarDamage.fire_material() and f._smoke != null
			and f._stack != null and f._stack.mesh == Bonfires.stack_mesh() and f._pool != null,
			"a lit fire burns: flames on the car fire's material, smoke, the log stack and the pool of light")
		_t._check(WeaponFX._web() or f._light != null, "a desktop fire carries a real light")
	if not figs.is_empty():
		var woke: RoughSleeper = (figs[0] as BonfireFigure).wake()
		_t._check(woke is BeachGoer and (woke as BeachGoer).clothed and (woke as BeachGoer).beach_pose == (figs[0] as BonfireFigure).beach_pose,
			"a woken bonfire figure is a live BeachGoer in street clothes in the same pose")
	# The block's own rolls: the same palms and tower with the rings off.
	Bonfires.enabled = false
	var plain: CityChunk = city._new_chunk(Vector2i(chunk.ix, chunk.iz), CityChunk.Level.FULL)
	plain.build()
	Bonfires.enabled = true
	var palms := [0, 0]
	var i := 0
	for c: CityChunk in [chunk, plain]:
		for n in c.get_children():
			if n is MultiMeshInstance3D and String(n.name).begins_with("Batch_palm_"):
				palms[i] += (n as MultiMeshInstance3D).multimesh.instance_count
		i += 1
	_t._check(palms[0] == palms[1] and (_batch(chunk, "beach_tower") != null) == (_batch(plain, "beach_tower") != null)
		and _children(plain, BonfireFire).is_empty() and _batch(plain, "bonfire_ring") == null,
		"with BONFIRES=0 there are no rings and the block's palms and tower roll as before (%d palms)" % palms[0])
	plain.queue_free()
	chunk.queue_free()


func _day_chunk(city: Node3D, k: Vector2i) -> void:
	Bonfires.force_hour = 13.0
	BeachLife.force_hour = 13.0
	Bonfires.force_lit = -1
	var chunk := _chunk_with_rings(city, k, CityChunk.Level.FULL)
	if chunk == null:
		_t._check(false, "a FULL beach chunk at 13:00 builds its rings")
		return
	var fires := _children(chunk, BonfireFire)
	var any_lit := false
	for f: BonfireFire in fires:
		f._check()
		any_lit = any_lit or f.lit or f._built
	_t._check(not fires.is_empty() and not any_lit and _children(chunk, BonfireFigure).is_empty() and _batch(chunk, "bonfire_wood") == null,
		"by day the rings stand empty (%d rings, no fire, nobody round them)" % fires.size())
	chunk.queue_free()


func _lod_chunk(city: Node3D, k: Vector2i) -> void:
	Bonfires.force_hour = 21.0
	BeachLife.force_hour = 21.0
	Bonfires.force_lit = 1
	var night := _chunk_with_rings(city, k, CityChunk.Level.LOD)
	var pool := _batch(night, "bonfire_lod_pool") if night else null
	_t._check(pool != null and pool.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"a LOD beach chunk at night lays the fires' pools of light, with no shadow")
	if night:
		var ix := night.ix
		night.queue_free()
		Bonfires.force_hour = 13.0
		BeachLife.force_hour = 13.0
		Bonfires.force_lit = -1
		var day: CityChunk = city._new_chunk(Vector2i(ix, k.y), CityChunk.Level.LOD)
		day.build()
		_t._check(_batch(day, "bonfire_lod_pool") == null, "and none by day")
		day.queue_free()
