extends RefCounted
## The apartment kit (Apartments, ApartmentBuild), for tests/smoke_test.gd. Loaded at run time, not
## named there, so it compiles after the autoloads.
##
## Over midtown and the inner suburbs round the default seed's downtown: the kit claims lots in
## both, every kind appears, the plans are pure, every wing, stair and court lies inside its yard and
## the wings keep apart, heights are low-rise; the walk-ups have galleries and stairs that reach every
## floor; the claim never takes a parking lot, a pocket garden or a tall midtown lot. Then a FULL
## chunk of a midtown block with apartments: the house meshes and their collision are there and no
## Building stands on a claimed lot; captured for the far city, its wings are LOD boxes; and with the
## kit off the same block is Building boxes again.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var centre: Vector2 = plan.macro.downtown_center
	var lo := plan.block_index_at(centre - Vector2(1800.0, 1800.0))
	var hi := plan.block_index_at(centre + Vector2(1800.0, 1800.0))
	var kinds := {}
	var districts := {}
	var impure := 0
	var astray := 0
	var overlaps := 0
	var tall := 0
	var bad_claim := 0
	var stairs_short := 0
	var walkups := 0
	var total := 0
	var block_with := Vector2i(9999, 9999)
	var best := 0
	for bx in range(lo.x, hi.x + 1):
		for bz in range(lo.y, hi.y + 1):
			var b := plan.block(bx, bz)
			var d: int = b.district
			if (d != CityPlan.District.MIDTOWN and d != CityPlan.District.SUBURBS) or int(b.kind) != CityPlan.BlockKind.BUILDINGS:
				continue
			var here := 0
			for lot: Dictionary in plan.lots(bx, bz):
				var ap := Apartments.plan_house(plan, bx, bz, lot, d)
				if ap.is_empty():
					continue
				if lot.yard or lot.get("parking", false):
					bad_claim += 1
				if d == CityPlan.District.MIDTOWN and plan.lot_height(lot.seed, d, plan.macro.skyline_boost(lot.center)) > Apartments.MIDTOWN_MAX_H:
					bad_claim += 1
				total += 1
				here += 1
				kinds[Apartments.KIND_NAMES[int(ap.apt)]] = true
				districts[d] = true
				if var_to_str(ap.wings) != var_to_str(Apartments.plan_house(plan, bx, bz, lot, d).wings):
					impure += 1
				if float(ap.height) > 14.5:
					tall += 1
				var f: Dictionary = ap.f
				var yard := Rect2(0.0, 0.0, float(f.U), float(f.V)).grow(0.05)
				var rects: Array[Rect2] = []
				for w: Dictionary in ap.wings:
					rects.append(w.r)
				for i in rects.size():
					for j in range(i + 1, rects.size()):
						if rects[i].grow(-0.06).intersects(rects[j].grow(-0.06)):
							overlaps += 1
				for r: Rect2 in ap.extra_ground:
					rects.append(r)
				if (ap.court as Rect2).size.x > 0.0:
					rects.append(ap.court)
				for r: Rect2 in rects:
					if not yard.encloses(r):
						astray += 1
				if int(ap.apt) == Apartments.Kind.WALKUP:
					walkups += 1
					var top := 0.0
					for s: Dictionary in ap.stairs:
						top = maxf(top, float(s.y1))
					var storeys: int = ap.wings[0].storeys
					if ap.galleries.is_empty() or absf(top - float(storeys - 1) * Apartments.STOREY) > 0.01:
						stairs_short += 1
			if d == CityPlan.District.MIDTOWN and here > best and plan.zone_at((b.rect as Rect2).get_center()) == MacroMap.Zone.CITY:
				best = here
				block_with = Vector2i(bx, bz)
	_t._check(total >= 150 and districts.size() >= 1 and kinds.size() == 4 and bad_claim == 0,
		"apartments: %d buildings in midtown and the inner suburbs, kinds %s, %d wrong claims" % [total, kinds.keys(), bad_claim])
	_t._check(impure == 0 and astray == 0 and overlaps == 0 and tall == 0,
		"apartments: pure (%d differ), inside their yards (%d astray), wings apart (%d overlap), low-rise (%d over 14.5 m)" % [impure, astray, overlaps, tall])
	_t._check(walkups > 0 and stairs_short == 0, "apartments: %d walk-ups, every one with galleries and a stair to its top floor (%d short)" % [walkups, stairs_short])
	if block_with == Vector2i(9999, 9999):
		_t._check(false, "apartments: a midtown block with apartments to build")
		return
	_full(city, plan, block_with)


func _full(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	var t0 := Time.get_ticks_usec()
	chunk.build()
	var on_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var meshes := 0
	for c in chunk.get_children():
		if c is MeshInstance3D and String(c.name).begins_with("House_"):
			meshes += 1
	var body := chunk.get_node_or_null("Houses")
	var shapes := body.get_child_count() if body else 0
	# No Building on a claimed lot.
	var claimed: Array[Rect2] = []
	var d: int = plan.block(k.x, k.y).district
	for lot: Dictionary in plan.lots(k.x, k.y):
		if Apartments.claims(plan, k.x, k.y, lot, d):
			claimed.append(Rect2((lot.center as Vector2) - (lot.size as Vector2) * 0.5, lot.size))
	var on_claimed := 0
	for c in chunk.get_children():
		if c is Building:
			var p := Vector2((c as Node3D).position.x, (c as Node3D).position.z)
			for r: Rect2 in claimed:
				if r.has_point(p):
					on_claimed += 1
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	_t._check(meshes >= 4 and shapes >= claimed.size() and on_claimed == 0 and not claimed.is_empty(),
		"apartments block %s FULL: %d claimed lots, %d house meshes, %d shapes, %d Buildings on claimed lots" % [k, claimed.size(), meshes, shapes, on_claimed])
	# The far city: a LOD box per wing at least.
	var cap := CityChunk.new()
	cap.plan = plan
	cap.ix = k.x
	cap.iz = k.y
	cap.level = CityChunk.Level.LOD
	cap.capturing = true
	cap.style = city.chunk_style()
	cap.build()
	var lb: Dictionary = (cap.captured.batch as Dictionary).get("lod_box", {})
	var boxes: int = (lb.get("xforms", []) as Array).size()
	cap.free()
	_t._check(boxes >= claimed.size(), "apartments block %s for the far city: %d LOD boxes for %d buildings" % [k, boxes, claimed.size()])
	# Off: Building boxes again.
	Apartments.enabled = false
	var off: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	var t1 := Time.get_ticks_usec()
	off.build()
	var off_ms := float(Time.get_ticks_usec() - t1) / 1000.0
	Apartments.enabled = true
	var off_b := 0
	for c in off.get_children():
		if c is Building:
			off_b += 1
	off.get_parent().remove_child(off)
	off.free()
	_t._check(off_b >= claimed.size(), "apartments block %s with the kit off: %d Building boxes (the A/B; built in %.0f ms on, %.0f ms off)" % [k, off_b, on_ms, off_ms])
