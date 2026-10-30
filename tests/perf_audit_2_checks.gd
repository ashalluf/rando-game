extends RefCounted
## The second perf audit's cuts (docs/HANDOFF.md, the perf-audit-2 section) for tests/smoke_test.gd.
## Loaded at run time, so it compiles after the autoloads. Every cut keeps its answers: the
## memorial parks' road closures cached per road and cell answer what the old per-quarter-metre
## cache did; CityPlan.road_open()'s site bounds are the expressions it evaluated each call;
## Vehicle.road_lift() kept per body type is _dims()'s; a capture-mode chunk leaves no freeway
## collision body out of the tree. Leans on nothing an earlier check left behind (its own plan).

var _t: Node


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.get("plan")
	if plan == null:
		_check(false, "perf2: the city has a plan")
		return
	_index_at(plan)
	_cemetery(plan)
	_site_bounds(plan)
	_road_lift()
	_micro_meshes()
	_refinery_far(city)
	_freeway_orphans(plan, city)


## _index_at() from its bucket's hint is the walk from road 0 it was.
func _index_at(plan: CityPlan) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var bad := 0
	for k in 3000:
		var axis := k % 2
		var v := rng.randf_range(-9000.0, 9000.0)
		if k % 7 == 0:
			v = plan.road_pos(axis, rng.randi_range(-60, 60))
		var want := 0
		while v >= plan.road_pos(axis, want + 1):
			want += 1
		while v < plan.road_pos(axis, want):
			want -= 1
		if plan._index_at(axis, v) != want:
			bad += 1
	_check(bad == 0, "perf2: _index_at() from its hint finds the road the walk from road 0 found (3000 samples, %d differ)" % bad)


## The old Cemetery.road_closed(), recomputed here from decide(): spans of the nine cells round
## the probe's cell that hold `along`.
func _old_closed(plan: CityPlan, axis: int, index: int, along: float) -> bool:
	var pos := plan.road_pos(axis, index)
	var probe := Vector2(pos, along) if axis == CityPlan.AXIS_X else Vector2(along, pos)
	var c := Cemetery._cell_of(probe)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var d := Cemetery.decide(plan, c + Vector2i(dx, dz))
			if d.is_empty():
				continue
			for cl: Array in d.closed:
				if int(cl[0]) == axis and int(cl[1]) == index and along > float(cl[2]) and along < float(cl[3]):
					return true
	return false


func _cemetery(plan: CityPlan) -> void:
	if not Cemetery.enabled:
		return
	# Every closed stretch of every memorial park within a few cells of the middle of the map,
	# sampled across its ends and inside, and roads either side of it.
	var tried := 0
	var closed := 0
	var bad := 0
	for cx in range(-3, 4):
		for cz in range(-3, 4):
			var d := Cemetery.decide(plan, Vector2i(cx, cz))
			if d.is_empty():
				continue
			for cl: Array in d.closed:
				var axis := int(cl[0])
				var lo := float(cl[2])
				var hi := float(cl[3])
				for index in [int(cl[1]) - 1, int(cl[1]), int(cl[1]) + 1]:
					for k in 41:
						var along := lerpf(lo - 20.0, hi + 20.0, float(k) / 40.0)
						for a in [along, lo, hi, lo + 0.001, hi - 0.001]:
							var now := Cemetery.road_closed(plan, axis, index, a)
							tried += 1
							closed += int(now)
							if now != _old_closed(plan, axis, index, a):
								bad += 1
	_check(bad == 0 and (tried == 0 or closed > 0),
		"perf2: a memorial park's closed roads answer as before with the cache per road and cell (%d samples, %d closed, %d differ)" % [tried, closed, bad])


func _site_bounds(plan: CityPlan) -> void:
	var bad := 0
	var n := 0
	for s: Dictionary in plan.sites():
		var b := plan._site_bounds(s)
		n += 1
		var want := [plan.road_pos(CityPlan.AXIS_Z, s.iz0) + plan.road_width(CityPlan.AXIS_Z, s.iz0) * 0.5,
			plan.road_pos(CityPlan.AXIS_Z, s.iz1) - plan.road_width(CityPlan.AXIS_Z, s.iz1) * 0.5,
			plan.road_pos(CityPlan.AXIS_X, s.ix0) + plan.road_width(CityPlan.AXIS_X, s.ix0) * 0.5,
			plan.road_pos(CityPlan.AXIS_X, s.ix1) - plan.road_width(CityPlan.AXIS_X, s.ix1) * 0.5]
		for i in 4:
			if float(b[i]) != float(want[i]):
				bad += 1
		var kept: PackedFloat64Array = b[4]
		var ki := 0
		for k: int in s.keep_z:
			if kept[ki] != plan.road_pos(CityPlan.AXIS_Z, k) or kept[ki + 1] != plan.road_width(CityPlan.AXIS_Z, k) * 0.5:
				bad += 1
			ki += 2
	_check(n > 0 and bad == 0, "perf2: road_open()'s site bounds are the very numbers it worked out each call (%d sites, %d differ)" % [n, bad])


func _road_lift() -> void:
	var bad := []
	for type in [Vehicle.BodyType.SEDAN, Vehicle.BodyType.PICKUP, Vehicle.BodyType.VAN, Vehicle.BodyType.BUS]:
		var car := Vehicle.new()
		car.body_type = type
		var want := -float(car._dims().get("road", car._dims().get("ride", car.model_bottom_y)))
		var first := car.road_lift()
		var again := car.road_lift()
		car.body_type = Vehicle.BodyType.SEMI
		var other := car.road_lift()
		var semi_want := -float(car._dims().get("road", car._dims().get("ride", car.model_bottom_y)))
		if first != want or again != want or other != semi_want:
			bad.append(type)
		car.free()
	_check(bad.is_empty(), "perf2: Vehicle.road_lift() kept per body type is _dims()'s, and follows a change of type %s" % [bad])


## The micromobility kit's meshes carry a lighter shadow twin (from their generated LODs) and the
## same triangles as before at full detail (an indexed copy of the old unindexed surface).
func _micro_meshes() -> void:
	var rows := []
	var ok := true
	for kind in [MicroMesh.Kind.SCOOTER_A, MicroMesh.Kind.SHARE]:
		var m := MicroMesh.whole(kind)
		var tris := _tris(m)
		var proxy := PropFactory.shadow_proxy(m)
		var ptris := _tris(proxy) if proxy else -1
		rows.append([kind, tris, ptris])
		ok = ok and tris > 500 and proxy != null and ptris > 0 and ptris < tris
	_check(ok, "perf2: parked scooters and share bikes cast from a lighter twin (kind, tris, shadow tris %s)" % [rows])


func _tris(m: Mesh) -> int:
	var n := 0
	if m == null:
		return 0
	for i in m.get_surface_count():
		var a := m.surface_get_arrays(i)
		var idx = a[Mesh.ARRAY_INDEX]
		n += ((idx as PackedInt32Array).size() if idx != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n


## The refinery's far pieces are indexed meshes (with generated LODs) whose triangles are the plant's.
func _refinery_far(city: Node3D) -> void:
	var far: Node = city.get_node_or_null("RefineryFar")
	if far == null:
		return
	var pieces := 0
	var indexed := 0
	var tris := 0
	for piece in far.get_children():
		var mi := piece.get_node_or_null("Plant") as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		pieces += 1
		var a := mi.mesh.surface_get_arrays(0)
		var idx = a[Mesh.ARRAY_INDEX]
		var verts := (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if idx != null and (idx as PackedInt32Array).size() > verts:
			indexed += 1
		tris += _tris(mi.mesh)
	_check(pieces > 0 and indexed == pieces and tris > 20000,
		"perf2: the refinery's far pieces are indexed, LOD-carrying meshes (%d of %d, %d triangles)" % [indexed, pieces, tris])


## A far-city capture of a freeway chunk built its deck body and dropped it out of the tree (an
## orphan StaticBody3D with a shape per segment, every capture of every freeway block).
func _freeway_orphans(plan: CityPlan, city: Node3D) -> void:
	var fw = plan.macro.freeway if plan.macro else null
	if fw == null:
		return
	var at := Vector2i(999999, 0)
	for seg: Dictionary in fw.segments_in(Rect2(Vector2(-3000, -3000), Vector2(6000, 6000))):
		if not seg.has("link"):
			var mid: Vector2 = (seg.a as Vector2).lerp(seg.b, 0.5)
			at = plan.block_index_at(mid)
			break
	if at.x == 999999:
		return
	var before := _orphan_bodies()
	var ch := CityChunk.new()
	ch.plan = plan
	ch.ix = at.x
	ch.iz = at.y
	ch.level = CityChunk.Level.LOD
	ch.style = city.call("chunk_style")
	ch.capturing = true
	ch.begin_build()
	var guard := 0
	while not ch.build_step() and guard < 4000:
		guard += 1
	var after := _orphan_bodies()
	ch.free()
	_check(after <= before, "perf2: a capture of a freeway block leaves no body out of the tree (%d -> %d)" % [before, after])


func _orphan_bodies() -> int:
	var n := 0
	for id in Node.get_orphan_node_ids():
		var o := instance_from_id(id)
		if o is StaticBody3D and (o as Node).get_parent() == null and String((o as Node).name) in ["FreewayBody", "RampBody"]:
			n += 1
	return n
