extends RefCounted
## Service alleys (Alleys, AlleyKit), for tests/smoke_test.gd. Loaded at run time, not named there,
## so it compiles after the autoloads.
##
## Checks the pure plan (the band on the lot grid's seam, the same answer twice, LotFill's cells
## trimmed off it), then builds a FULL chunk of a downtown and a midtown alley block and checks:
## one ground mesh (no shadow) and one upright mesh, runs inside the band at least MIN_WIDTH wide
## and clear of every building's ground parts, no parked car across a mouth and no street lamp on
## one; that the far city's capture lays the band as ground; and that the block built with the
## alleys off is the same block (hash-seeded: the buildings, the hydrant and the trash cans - the
## last things the block rng places before the walkers - are where they were).

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var down := _find(plan, CityPlan.District.DOWNTOWN, Vector2(2850.0, -300.0))
	var mid := _find(plan, CityPlan.District.MIDTOWN, Vector2(-250.0, -100.0))
	_t._check(down.x != 99999, "a downtown block has a service alley")
	_t._check(mid.x != 99999, "a midtown block has a service alley")
	_counts(plan)
	for k: Vector2i in [down, mid]:
		if k.x == 99999:
			continue
		_pure(plan, k)
		_full(city, plan, k)
		_capture(city, plan, k)
	if down.x != 99999:
		_unmoved(city, down)


## The nearest alley block of `district` to `near` (true world XZ), or (99999, 0).
func _find(plan: CityPlan, district: int, near: Vector2) -> Vector2i:
	var c := plan.block_index_at(near)
	var best := Vector2i(99999, 0)
	var best_d := INF
	for bx in range(c.x - 6, c.x + 7):
		for bz in range(c.y - 6, c.y + 7):
			var sp := Alleys.spec(plan, bx, bz)
			if sp.is_empty() or int(sp.district) != district:
				continue
			var d := (sp.rect as Rect2).get_center().distance_to(near)
			if d < best_d:
				best_d = d
				best = Vector2i(bx, bz)
	return best


func _counts(plan: CityPlan) -> void:
	var c := plan.block_index_at(Vector2(2850.0, -300.0))
	var n := 0
	var blocks := 0
	var off := 0
	for bx in range(c.x - 8, c.x + 9):
		for bz in range(c.y - 8, c.y + 9):
			var b := plan.block(bx, bz)
			var sp := Alleys.spec(plan, bx, bz)
			if int(b.kind) == CityPlan.BlockKind.BUILDINGS and int(b.district) in Alleys.DISTRICTS:
				blocks += 1
			if not sp.is_empty():
				n += 1
				if not int(b.district) in Alleys.DISTRICTS or int(b.kind) != CityPlan.BlockKind.BUILDINGS:
					off += 1
	_t._check(n > blocks / 3 and off == 0, "alleys run behind %d of the %d downtown and midtown blocks round the core, and only there" % [n, blocks])


func _pure(plan: CityPlan, k: Vector2i) -> void:
	var sp := Alleys.spec(plan, k.x, k.y)
	var again := Alleys._spec(plan, k.x, k.y)
	_t._check(not sp.is_empty() and float(again.seam) == float(sp.seam) and bool(again.along_x) == bool(sp.along_x),
		"the alley band is a pure function of the plan (block %d,%d)" % [k.x, k.y])
	var band: Rect2 = sp.band
	var inner: Rect2 = sp.inner
	_t._check(inner.encloses(band) and absf((band.size.y if sp.along_x else band.size.x) - Alleys.HALF_BAND * 2.0) < 0.01,
		"the band lies inside the block's inner rect, HALF_BAND either side of the seam")
	var cut := 0
	var clear := true
	for lot: Dictionary in sp.lots:
		var cell: Rect2 = lot.cell
		var tr := Alleys.trim(plan, k.x, k.y, cell)
		if tr != cell:
			cut += 1
		if tr.size.x > 0.01 and tr.size.y > 0.01 and tr.grow(-0.01).intersects(band):
			clear = false
	_t._check(cut >= 2 and clear, "LotFill's cells along the seam are trimmed off the band (%d cut)" % cut)


func _full(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var sp := Alleys.spec(plan, k.x, k.y)
	var ground: MeshInstance3D = chunk.get_node_or_null("AlleyGround")
	var walls: MeshInstance3D = chunk.get_node_or_null("AlleyWalls")
	var grounds := 0
	var uprights := 0
	for c in chunk.get_children():
		if String(c.name).begins_with("AlleyGround"):
			grounds += 1
		if String(c.name).begins_with("AlleyWalls"):
			uprights += 1
	_t._check(ground != null and grounds == 1 and ground.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		and ground.material_override == Alleys.ground_material(), "the alley's ground is one shadowless mesh on the alley shader (block %d,%d)" % [k.x, k.y])
	_t._check(walls != null and uprights == 1 and walls.material_override == IndustrialKit.walls_material(),
		"everything upright in the alley is one mesh on the industrial walls material")
	var runs: Array = chunk.get_meta("alley_runs", [])
	var ok := not runs.is_empty()
	var band: Rect2 = sp.band
	var foot: Array[Rect2] = []
	for c in chunk.get_children():
		var b := c as Building
		if b == null:
			continue
		for part: Dictionary in b.parts:
			var size: Vector3 = part.size
			var mid: Vector3 = part.center
			if mid.y - size.y * 0.5 > 0.05:
				continue
			foot.append(Rect2(Vector2(b.position.x + mid.x - size.x * 0.5, b.position.z + mid.z - size.z * 0.5), Vector2(size.x, size.z)))
	var hits := 0
	for r: Dictionary in runs:
		var rr := Alleys._run_rect(sp, r)
		ok = ok and float(r.w) >= Alleys.MIN_WIDTH - 0.01 and float(r.w) <= Alleys.WIDTH + 0.01 and band.grow(0.01).encloses(rr)
		for f: Rect2 in foot:
			if f.intersects(rr.grow(-0.05)):
				hits += 1
	_t._check(ok and hits == 0, "the alley runs %d stretch(es) inside its band, %.1f-%.1f m wide, clear of every building (%d hits)" % [runs.size(), Alleys.MIN_WIDTH, Alleys.WIDTH, hits])
	var blocked := 0
	for car in chunk.get("_cars"):
		if is_instance_valid(car):
			var p: Vector3 = WorldState.to_world((car as Node3D).position) if (car as Node).get_parent() != chunk else (car as Node3D).position
			if Alleys.keeps_clear(plan, Vector2(p.x, p.z)):
				blocked += 1
	_t._check(blocked == 0, "no parked car stands across an alley's mouth (%d)" % blocked)
	var lamps := 0
	for r: Dictionary in chunk.prop_records:
		if String(r.kind) == "lamp":
			var p: Vector3 = r.position
			if Alleys.in_mouth(plan, k.x, k.y, Vector2(p.x, p.z)):
				lamps += 1
	_t._check(lamps == 0, "no street lamp stands across an alley's mouth (%d)" % lamps)
	chunk.get_parent().remove_child(chunk)
	chunk.free()


func _capture(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var cap := CityChunk.new()
	cap.plan = plan
	cap.ix = k.x
	cap.iz = k.y
	cap.level = CityChunk.Level.LOD
	cap.style = city.chunk_style()
	cap.capturing = true
	cap.build()
	var sp := Alleys.spec(plan, k.x, k.y)
	var band: Rect2 = sp.band
	var n := 0
	for g: Array in cap.captured.get("ground", []):
		var r: Rect2 = g[0]
		if (g[1] as Color).is_equal_approx(Alleys.FAR_COLOR) and band.grow(0.1).encloses(r):
			n += 1
	cap.free()
	_t._check(n > 0, "the far city lays the alley's band as ground (%d slabs)" % n)


func _unmoved(city: Node3D, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var sig := _signature(chunk)
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	Alleys.enabled = false
	var bare: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	bare.build()
	Alleys.enabled = true
	var bare_sig := _signature(bare)
	bare.get_parent().remove_child(bare)
	bare.free()
	_t._check(sig == bare_sig and not sig.is_empty(), "the alleys roll nothing from the block: built without them its buildings, hydrant and trash cans are where they were (%d)" % sig.size())


func _signature(chunk: CityChunk) -> Array:
	var out: Array = []
	for c in chunk.get_children():
		if c is Building or c is TrashCan:
			var p: Vector3 = (c as Node3D).position
			out.append("%s %.2f %.2f %.2f" % [c.get_class(), p.x, p.z, (c as Node3D).rotation.y])
	# The pavement's hydrant is placed after its lamps and trees, from the block rng: where it
	# lands says the stream ran the same. (Forecourt furniture is not compared: LotFill keeps it
	# off the alley's band on purpose.)
	for r in chunk.prop_records:
		if String(r.kind).begins_with("hydrant"):
			out.append("%s %.2f %.2f" % [r.kind, (r.position as Vector3).x, (r.position as Vector3).z])
	out.sort()
	return out
