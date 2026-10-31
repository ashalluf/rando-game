extends RefCounted
## Stunt ramps (StuntRamps, StuntKit, StuntBuild, StuntDirector; docs/HANDOFF.md "Stunt ramps"):
## checks for tests/smoke_test.gd. Loaded at run time, so it compiles after the autoloads. Stages
## everything it needs (its own chunks, a director fed synthetic ticks) and puts Engine.time_scale
## and the audio speed back whatever happens.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var sites := StuntRamps.all_sites(plan)
	var kinds := {}
	for s: Dictionary in sites:
		kinds[int(s.kind)] = int(kinds.get(int(s.kind), 0)) + 1
	var cps := _car_parks(plan)
	_t._check(int(kinds.get(StuntRamps.Kind.QPIPE, 0)) >= 1 and int(kinds.get(StuntRamps.Kind.LAUNCH, 0)) >= 1
		and int(kinds.get(StuntRamps.Kind.LAUNCH, 0)) == int(kinds.get(StuntRamps.Kind.LAND, 0))
		and int(kinds.get(StuntRamps.Kind.LOOP, 0)) >= 1 and int(kinds.get(StuntRamps.Kind.PIER, 0)) == 1 and not cps.is_empty(),
		"stunt ramps: the default seed has a river quarter-pipe, a freeway ramp pair, a loop, the pier kicker and car park kickers (%s, %d car park roofs)" % [str(kinds), cps.size()])
	_pure(plan, sites)
	_sound(plan, sites, cps)
	_kit()
	_vacant(plan)
	# A freeway piece, the loop, the river's quarter-pipe and a car park roof, built in their chunks.
	var built := {}
	for s: Dictionary in sites + cps:
		var k := int(s.kind)
		if k == StuntRamps.Kind.LAND or built.has(k):
			continue
		built[k] = true
		_chunk(city, plan, s)
	await _director(t)
	_switch(plan)


## Car park kickers in the downtown / midtown blocks round the middle of the map.
func _car_parks(plan: CityPlan) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var b0 := plan.block_index_at(Vector2(-400.0, -1800.0))
	var b1 := plan.block_index_at(Vector2(3800.0, 2400.0))
	for bx in range(b0.x, b1.x + 1):
		for bz in range(b0.y, b1.y + 1):
			var s := StuntRamps.car_park_site(plan, bx, bz)
			if not s.is_empty():
				out.append(s)
	return out


## The same question twice (with the caches dropped) gives the same sites at the same places.
func _pure(plan: CityPlan, sites: Array[Dictionary]) -> void:
	StuntRamps._cache.clear()
	var again := StuntRamps.all_sites(plan)
	var same := again.size() == sites.size()
	for i in mini(again.size(), sites.size()):
		same = same and String(again[i].id) == String(sites[i].id) and (again[i].p as Vector3).is_equal_approx(sites[i].p) \
			and is_equal_approx(float(again[i].yaw), float(sites[i].yaw))
	var ids := {}
	var unique := true
	for s: Dictionary in sites:
		unique = unique and not ids.has(s.id)
		ids[s.id] = true
	_t._check(same and unique, "stunt ramps: placement is pure (the same %d sites twice, every id once)" % sites.size())


## Where they stand: the freeway pieces on the right of way, off every deck and road, the pair
## square across one deck facing it; the quarter-pipe on the bed at the toe; the kickers on the roof
## between the last light pole and the end zone.
func _sound(plan: CityPlan, sites: Array[Dictionary], cps: Array[Dictionary]) -> void:
	var fw: Freeway = plan.macro.freeway
	var worst := ""
	for s: Dictionary in sites:
		var k := int(s.kind)
		var p: Vector3 = s.p
		var fwd := Vector2(sin(float(s.yaw)), cos(float(s.yaw)))
		if k == StuntRamps.Kind.LAUNCH or k == StuntRamps.Kind.LAND or k == StuntRamps.Kind.LOOP:
			var r: Rect2 = s.clear
			if fw.blocks_rect(r.grow(-2.6), 0.5):
				worst = "%s stands under a deck" % s.id
			if plan.district_at(r.get_center()) != CityPlan.District.INDUSTRIAL:
				worst = "%s is not in the industrial district" % s.id
			# Never on a road: every corner of its footprint inside its block's inner ground.
			var blk := plan.block_index_at(r.get_center())
			var inner: Rect2 = (plan.block(blk.x, blk.y).rect as Rect2).grow(-plan.sidewalk_width + 0.3)
			for q: Vector2 in [r.grow(-2.6).position, r.grow(-2.6).end]:
				if not inner.has_point(q):
					worst = "%s reaches a street" % s.id
		if k == StuntRamps.Kind.LAUNCH:
			# The lip faces the deck: the route's nearest point is ahead of it.
			var lip := Vector2(p.x, p.z) + fwd * float(s.len)
			var pts: PackedVector2Array = fw.routes[int(s.route)].points
			var c := (pts[int(s.index)] + pts[int(s.index) + 1]) * 0.5
			var d := c - lip
			if d.dot(fwd) < 5.0:
				worst = "%s does not face its deck" % s.id
		if k == StuntRamps.Kind.QPIPE:
			var rv: LaRiver = plan.macro.river
			var n := rv.nearest(Vector2(p.x, p.z), 200.0)
			var off := absf(n.y)
			if n.w < 0.5 or off > rv.bed_half(n.x) - 2.0 or off < LaRiver.lf_half() + 1.0:
				worst = "%s is not on the bed by the bank (%.1f m off the centre)" % [s.id, off]
	for s: Dictionary in cps:
		var cs := CarPark.on_block(plan, plan.block_index_at(Vector2((s.p as Vector3).x, (s.p as Vector3).z)).x,
			plan.block_index_at(Vector2((s.p as Vector3).x, (s.p as Vector3).z)).y)
		if cs.is_empty():
			worst = "%s: no car park under it" % s.id
			continue
		var top := CarPark.ground_y(plan, cs) + CarPark.FLOOR * float(cs.layout.decks)
		if absf((s.p as Vector3).y - top) > 0.05:
			worst = "%s is not on the roof (%.2f vs %.2f)" % [s.id, (s.p as Vector3).y, top]
		var site: Rect2 = cs.site
		var fwd := Vector2(sin(float(s.yaw)), cos(float(s.yaw)))
		var lip := Vector2((s.p as Vector3).x, (s.p as Vector3).z) + fwd * float(s.len)
		if not site.grow(0.5).has_point(lip):
			worst = "%s's lip is off its car park" % s.id
	_t._check(worst == "", "stunt ramps: freeway pieces on the right of way facing the deck, the quarter-pipe on the bed, kickers on the roof (%s)" % worst)


## The kit: every piece has a mesh and collision, the kicker's lip is where StuntRamps says, the
## loop closes on itself shifted sideways.
func _kit() -> void:
	var k := StuntKit.kicker(StuntRamps.KICKER_LEN, StuntRamps.KICKER_H, StuntRamps.KICKER_W, StuntRamps.PAINTS[1])
	var prof := StuntKit.arc_profile(StuntRamps.KICKER_LEN, StuntRamps.KICKER_H, 14)
	var lip: Array = prof[prof.size() - 1]
	var l := StuntKit.launch(StuntRamps.LAUNCH_LEN, StuntRamps.LAUNCH_H, StuntRamps.PAIR_W, StuntRamps.PAINTS[0])
	var d := StuntKit.landing(StuntRamps.LAND_LEN, StuntRamps.LAND_H, StuntRamps.PAIR_W, StuntRamps.PAINTS[0])
	var q := StuntKit.qpipe(StuntRamps.QP_LEN, StuntRamps.QP_RADIUS, StuntRamps.QP_ANGLE, StuntRamps.QP_DECK, LaRiver.SLOPE)
	var o := StuntKit.loop(StuntRamps.LOOP_R, StuntRamps.LOOP_W, -StuntRamps.LOOP_SHIFT, StuntRamps.LOOP_RUN, StuntRamps.PAINTS[3])
	var ok := true
	var tris := []
	for piece: Array in [k, l, d, q, o]:
		ok = ok and piece[0] != null and (piece[1] as PackedVector3Array).size() >= 30 and int(piece[2]) > 40
		tris.append(int(piece[2]))
	var p0 := StuntKit.loop_point(6.0, 5.0, 0.0)
	var p1 := StuntKit.loop_point(6.0, 5.0, TAU)
	var top := StuntKit.loop_point(6.0, 5.0, PI)
	var loop_ok := p0.is_equal_approx(Vector3.ZERO) and p1.is_equal_approx(Vector3(5.0, 0.0, 0.0)) and is_equal_approx(top.y, 12.0) \
		and StuntKit.loop_normal(PI).is_equal_approx(Vector3(0.0, -1.0, 0.0))
	_t._check(ok and loop_ok and is_equal_approx(float(lip[0]), StuntRamps.KICKER_LEN) and is_equal_approx(float(lip[1]), StuntRamps.KICKER_H),
		"stunt ramps: kit pieces with collision (triangles kicker/launch/landing/qpipe/loop %s), the kicker's lip at its numbers, the loop closes shifted" % str(tris))
	# Dirt jumps: a tabletop rises to its height on its table and is flat ground off its sides.
	var jumps := [[2.0, 3.0, 2.0, 5.0, 1.4]]
	var on_table := StuntKit.dirt_height(jumps, 4.0, 0.0, 6.0)
	var off_side := StuntKit.dirt_height(jumps, 4.0, 6.0, 6.0)
	var before := StuntKit.dirt_height(jumps, 4.0, 0.0, 1.0)
	_t._check(is_equal_approx(on_table, 1.4) and off_side == 0.0 and before == 0.0,
		"stunt ramps: a dirt tabletop is %.2f m on its table, %.2f off its side, %.2f before its takeoff" % [on_table, off_side, before])


## Vacant lots: some VACANT lots get a line, only down the clear drive, never past the lot.
func _vacant(plan: CityPlan) -> void:
	var found := 0
	var bad := ""
	var b0 := plan.block_index_at(Vector2(-200.0, -1500.0))
	var b1 := plan.block_index_at(Vector2(4200.0, 4000.0))
	for bx in range(b0.x, b1.x + 1, 1):
		for bz in range(b0.y, b1.y + 1, 1):
			var b := plan.block(bx, bz)
			if int(b.kind) != CityPlan.BlockKind.BUILDINGS or not VacantLots.ODDS.has(int(b.district)):
				continue
			for lot: Dictionary in plan.lots(bx, bz):
				if VacantLots.kind_of(plan, bx, bz, lot) != VacantLots.VACANT:
					continue
				var vp := VacantLots.plan_lot(plan, bx, bz, lot, VacantLots.VACANT)
				var s := StuntRamps.vacant_site(plan, lot, vp)
				if s.is_empty():
					continue
				found += 1
				var cell: Rect2 = lot.cell
				var fwd := Vector2(sin(float(s.yaw)), cos(float(s.yaw)))
				var foot := Vector2((s.p as Vector3).x, (s.p as Vector3).z)
				for j: Array in s.jumps:
					var end := foot + fwd * (float(j[0]) + float(j[1]) + float(j[2]) + float(j[3]))
					if not cell.grow(0.2).has_point(end):
						bad = "%s runs out of its lot" % s.id
				if found >= 12:
					break
	_t._check(found >= 1 and bad == "", "stunt ramps: vacant lots with dirt lines (%d found), every jump inside its lot (%s)" % [found, bad])


func _chunk(city: Node3D, plan: CityPlan, s: Dictionary) -> void:
	var p: Vector3 = s.p
	var k := plan.chunk_index_at(Vector2(p.x, p.z))
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	var before := StuntDirector.site_count()
	chunk.build()
	var pivot := chunk.get_node_or_null("Stunt_" + String(s.id)) as Node3D
	var mesh := pivot.get_node_or_null("Mesh") as MeshInstance3D if pivot else null
	var body := pivot.get_node_or_null("Body") as StaticBody3D if pivot else null
	var faces := 0
	if body and body.get_child_count() > 0:
		faces = ((body.get_child(0) as CollisionShape3D).shape as ConcavePolygonShape3D).get_faces().size() / 3
	var placed := pivot != null and pivot.global_position.is_equal_approx(WorldState.to_local(p))
	_t._check(pivot != null and mesh != null and mesh.mesh != null and body != null and body.collision_layer == 1 and body.collision_mask == 0
		and faces > 10 and placed and StuntDirector.site_count() > before,
		"stunt ramps: chunk %s builds %s (%s) - a mesh, %d collision triangles on the world layer, registered with the director" % [k, s.id, StuntRamps.Kind.keys()[int(s.kind)], faces])
	if s.has("clear"):
		var left := 0
		for key: String in chunk._batch._batches:
			if key == "lod_box" or key == "lamp_pool" or chunk._batch.tilt_keys.has(key):
				continue
			for xf: Transform3D in chunk._batch._batches[key].xforms:
				if xf.basis.get_scale().x < 0.01:
					continue
				if (s.clear as Rect2).grow(-0.3).has_point(Vector2(xf.origin.x, xf.origin.z)):
					left += 1
		_t._check(left == 0, "stunt ramps: chunk %s keeps its planting off %s (%d left)" % [k, s.id, left])
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	_t._check(StuntDirector.site_count() == before, "stunt ramps: a freed chunk's pieces leave the director (%d)" % StuntDirector.site_count())


## The moment: synthetic ticks through a registered kicker launch the slow motion; touching down
## ends it; anything else taking the time scale is left alone. Engine.time_scale is always put back.
func _director(t: Node) -> void:
	await t.get_tree().process_frame
	var dir: StuntDirector = StuntDirector.instance()
	if dir != null and not dir.is_inside_tree():
		dir = null
	var own := dir == null
	if own:
		dir = StuntDirector.new()
		t.get_tree().root.add_child(dir)
	dir.set_physics_process(false)
	dir.reset()
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	var s := {"id": "stunt_check", "kind": StuntRamps.Kind.KICKER, "p": Vector3(50000.0, 0.0, 50000.0), "yaw": 0.0,
		"len": 5.0, "h": 1.6, "w": 3.0, "paint": Color.RED}
	var pivot := Node3D.new()
	t.add_child(pivot)
	StuntDirector.register(pivot, s)
	var moments := StuntDirector.moments
	var foot: Vector3 = s.p
	var dt := 1.0 / 60.0
	# Up the kicker at 20 m/s, over the lip, then 0.3 s in the air.
	for i in 12:
		var z := 1.0 + float(i) * 20.0 * dt
		dir.watch(foot + Vector3(0.0, minf(z * 0.3, 1.6), z), Vector3(0.0, 4.0, 20.0), false, dt)
	for i in 20:
		dir.watch(foot + Vector3(0.0, 2.0 + float(i) * 0.1, 5.0 + float(i) * 0.33), Vector3(0.0, 3.0, 20.0), true, dt)
	var started := StuntDirector.moments == moments + 1 and dir.is_active() and StuntDirector.last_launch_id == "stunt_check"
	# Let the ease run a few real frames.
	# The director's ease steps at most 0.1 s a frame, so on a slow frame (a busy city in a
	# shard) 600 ms can be two frames: wait for the frames too.
	var t0 := Time.get_ticks_msec()
	var frames := 0
	# (Batch 28's gate: 4 frames took 5.8 s and the ease, at most 0.1 s a frame, reached 0.82: keep
	# going until it has slowed, up to the cap.)
	while ((Time.get_ticks_msec() - t0 < 600 or frames < 4) or (Engine.time_scale >= 0.6 and frames < 40)) and frames < 120:
		await t.get_tree().process_frame
		frames += 1
	var slowed := Engine.time_scale < 0.6
	var slowed_at := "%.2f after %d frames in %d ms" % [Engine.time_scale, frames, Time.get_ticks_msec() - t0]
	# Touch down: the world comes back to speed.
	for i in 10:
		dir.watch(foot + Vector3(0.0, 0.0, 14.0), Vector3(0.0, 0.0, 15.0), false, dt)
	t0 = Time.get_ticks_msec()
	# Real time, and a loaded runner gives few frames of it (CI 379 timed out at 900 ms).
	while Time.get_ticks_msec() - t0 < 5000 and not (is_equal_approx(Engine.time_scale, 1.0) and is_equal_approx(AudioServer.playback_speed_scale, 1.0)):
		await t.get_tree().process_frame
	var back := is_equal_approx(Engine.time_scale, 1.0) and is_equal_approx(AudioServer.playback_speed_scale, 1.0)
	# A slow ride past the lip (under min_launch_speed) is no launch.
	dir.reset()
	moments = StuntDirector.moments
	for i in 30:
		dir.watch(foot + Vector3(0.0, 1.6, 5.0), Vector3(0.0, 0.0, 6.0), i > 10, dt)
	var slow_ok := StuntDirector.moments == moments
	# Someone else holds the time scale: no moment starts and nothing is restored over them.
	dir.reset()
	Engine.time_scale = 0.5
	for i in 12:
		dir.watch(foot + Vector3(0.0, 1.6, 4.9), Vector3(0.0, 4.0, 20.0), false, dt)
	for i in 20:
		dir.watch(foot + Vector3(0.0, 3.0, 8.0), Vector3(0.0, 3.0, 20.0), true, dt)
	await t.get_tree().process_frame
	await t.get_tree().process_frame
	var polite := is_equal_approx(Engine.time_scale, 0.5)
	dir.reset()
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	pivot.queue_free()
	await t.get_tree().process_frame
	dir.set_physics_process(true)
	if own:
		dir.queue_free()
	_t._check(started and slowed and back and slow_ok and polite,
		"stunt ramps: a launch off a lip slows the world (started %s, slowed %s: %s), touch-down restores it (%s), a slow ride is no launch (%s), another owner's time scale is left alone (%s)" % [started, slowed, slowed_at, back, slow_ok, polite])


## STUNT_RAMPS=0: no sites anywhere.
func _switch(plan: CityPlan) -> void:
	var was := StuntRamps.enabled
	StuntRamps.enabled = false
	StuntRamps._cache.clear()
	var none := StuntRamps.all_sites(plan).is_empty() and StuntRamps.owned_by(plan, 0, 0).is_empty()
	StuntRamps.enabled = was
	StuntRamps._cache.clear()
	_t._check(none, "stunt ramps: STUNT_RAMPS=0 plans none")
