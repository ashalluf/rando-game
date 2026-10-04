extends RefCounted
## The suburbs' and the beach town's houses (HouseKit, HouseBuild), for tests/smoke_test.gd. Loaded
## at run time, not named there, so it compiles after the autoloads.
##
## The plans over the suburbs and the beach town west of downtown: pure (the same lot plans the
## same house twice), every wing, porch and screen inside its yard and clear of the other wings, the
## types all there, heights that are houses', a garage door wherever the yard's driveway ends (the
## yard plan reads it off the house). Then FULL chunks of a suburban and a beach block: one mesh per
## material for all the houses, their collision on one body, no Building boxes on the house lots,
## the yards laid; the same block captured for the far city: a box per wing and two tilted roof
## slabs per pitched wing in the lod_box batch; and with the kit off the lots are Building boxes
## again.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_plans(plan, CityPlan.District.SUBURBS, Rect2(-560.0, 150.0, 460.0, 450.0), "suburbs")
	_plans(plan, CityPlan.District.BEACHTOWN, Rect2(-950.0, -750.0, 500.0, 1350.0), "beach town")
	for d: Array in [[CityPlan.District.SUBURBS, Vector2(-235.7, 255.45), "suburbs"], [CityPlan.District.BEACHTOWN, Vector2(-687.3, 100.1), "beach town"]]:
		var k := _find(plan, int(d[0]), d[1])
		_t._check(k != Vector2i(9999, 9999), "there is a %s block of houses to build (%s)" % [d[2], k])
		if k == Vector2i(9999, 9999):
			continue
		_full(city, plan, k, d[2])
		_capture(city, plan, k, d[2])
	var sk := _find(plan, CityPlan.District.SUBURBS, Vector2(-235.7, 255.45))
	if sk != Vector2i(9999, 9999):
		_off(city, sk)


func _house_lots(plan: CityPlan, bx: int, bz: int) -> Array:
	var out: Array = []
	var b := plan.block(bx, bz)
	var pads: float = float((CityPlan.DISTRICTS[b.district] as Dictionary).get("pads", 0.0))
	for lot: Dictionary in plan.lots(bx, bz):
		var size: Vector2 = lot.size
		if lot.yard or lot.get("parking", false) or YardFill.is_corridor(plan, lot):
			continue
		# A lot the chunk may roll a commercial pad on (its own rng) is left out of the counts.
		if lot.edge and pads > 0.0 and size.x >= 18.0 and size.y >= 18.0:
			continue
		out.append(lot)
	return out


func _plans(plan: CityPlan, district: int, area: Rect2, label: String) -> void:
	var lo: Vector2i = plan.block_index_at(area.position)
	var hi: Vector2i = plan.block_index_at(area.end)
	var houses := 0
	var astray := 0
	var overlaps := 0
	var impure := 0
	var styles := {}
	var heights: Array[float] = []
	var garages := 0
	var drives_ok := 0
	var drives_bad := 0
	var roofs := {}
	for bx in range(lo.x, hi.x + 1):
		for bz in range(lo.y, hi.y + 1):
			var b := plan.block(bx, bz)
			if int(b.district) != district or int(b.kind) != CityPlan.BlockKind.BUILDINGS or b.has("site") \
					or plan.zone_at((b.rect as Rect2).get_center()) != MacroMap.Zone.CITY:
				continue
			if plan.macro.replica and plan.macro.replica.block_role(plan, bx, bz) != 0:
				continue
			var entries: Array = []
			for lot: Dictionary in _house_lots(plan, bx, bz):
				var hp := HouseKit.plan_house(plan, bx, bz, lot, district)
				var again := HouseKit.plan_house(plan, bx, bz, lot, district)
				if var_to_str(hp.wings) != var_to_str(again.wings) or hp.style != again.style or var_to_str(hp.colors) != var_to_str(again.colors):
					impure += 1
				houses += 1
				styles[HouseKit.STYLE_NAMES[int(hp.style)]] = int(styles.get(HouseKit.STYLE_NAMES[int(hp.style)], 0)) + 1
				heights.append(float(hp.height))
				var f: Dictionary = hp.f
				var yard := Rect2(0.0, 0.0, float(f.U), float(f.V)).grow(0.05)
				var rects: Array[Rect2] = []
				for w: Dictionary in hp.wings:
					rects.append(w.r)
					roofs[w.roof] = true
				if not (hp.porch as Dictionary).is_empty():
					rects.append(hp.porch.r)
				if (hp.breeze as Rect2).size.x > 0.0:
					rects.append(hp.breeze)
				for i in rects.size():
					if not yard.encloses(rects[i]):
						astray += 1
					for j in range(i + 1, rects.size()):
						if rects[i].grow(-0.06).intersects(rects[j].grow(-0.06)):
							overlaps += 1
				entries.append(HouseKit.yard_entry(lot, hp))
				if not (hp.garage as Dictionary).is_empty():
					garages += 1
			# The yard's driveway ends at the garage door, inside its span.
			var bp := YardFill.beach_block(plan, bx, bz, entries)
			for i in bp.lots.size():
				var lp: Dictionary = bp.lots[i]
				var e: Dictionary = entries[i]
				var hp2: Dictionary = e.house
				var dr: Rect2 = lp.drive
				var span: Vector2 = hp2.drive
				if span.y <= span.x or bool(hp2.walk_front):
					continue
				var q := YardFill._to_frame(lp.frame, dr)
				if dr.size.x > 0.0 and absf(q.end.y - float(hp2.drive_v)) < 0.05 and q.position.x >= span.x - 0.05 and q.end.x <= span.y + 0.05:
					drives_ok += 1
				else:
					drives_bad += 1
	heights.sort()
	var median: float = heights[heights.size() / 2] if not heights.is_empty() else 0.0
	var top: float = heights.back() if not heights.is_empty() else 0.0
	var want_styles := 5 if district == CityPlan.District.SUBURBS else 6
	var max_top := 9.5 if district == CityPlan.District.SUBURBS else 13.5
	_t._check(houses >= 40 and impure == 0 and astray == 0 and overlaps == 0,
		"%s houses: %d planned, pure (%d differ), inside their yards (%d astray), wings apart (%d overlap)" % [label, houses, impure, astray, overlaps])
	_t._check(styles.size() >= want_styles and roofs.size() >= 4 and median >= 3.5 and top <= max_top,
		"%s houses: %d types %s, roofs %s, %.1f m median, %.1f m the tallest" % [label, styles.size(), styles, roofs.keys(), median, top])
	_t._check(garages * 3 >= houses and drives_bad == 0 and drives_ok * 10 >= garages * 7,
		"%s houses: %d of %d with a garage or carport, %d drives end at their door, %d astray" % [label, garages, houses, drives_ok, drives_bad])


func _find(plan: CityPlan, district: int, near: Vector2) -> Vector2i:
	var centre := plan.block_index_at(near)
	var best := Vector2i(9999, 9999)
	var best_d := INF
	for dz in range(-4, 5):
		for dx in range(-4, 5):
			var k := centre + Vector2i(dx, dz)
			var b := plan.block(k.x, k.y)
			var rect: Rect2 = b.rect
			if int(b.kind) != CityPlan.BlockKind.BUILDINGS or b.has("site") or plan.zone_at(rect.get_center()) != MacroMap.Zone.CITY:
				continue
			if int(b.district) != district or (plan.macro.replica and plan.macro.replica.block_role(plan, k.x, k.y) != 0):
				continue
			if _house_lots(plan, k.x, k.y).size() < 6:
				continue
			var d := rect.get_center().distance_to(near)
			if d < best_d:
				best_d = d
				best = k
	return best


func _full(city: Node3D, plan: CityPlan, k: Vector2i, label: String) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var meshes := {}
	var tris := 0
	var buildings := 0
	var shapes := 0
	for c in chunk.get_children():
		if c is MeshInstance3D and str(c.name).begins_with("House_"):
			meshes[str(c.name).trim_prefix("House_")] = true
			var m: Mesh = (c as MeshInstance3D).mesh
			for si in m.get_surface_count():
				tris += (m.surface_get_array_len(si)) / 3
		elif c is Building:
			buildings += 1
		elif c is StaticBody3D and str(c.name) == "Houses":
			shapes = c.get_child_count()
	var expect := _house_lots(plan, k.x, k.y).size()
	var roofed := meshes.has("h_shingle") or meshes.has("h_roof") or meshes.has("h_flat")
	_t._check(meshes.has("h_trim") and meshes.has("glass") and (meshes.has("h_wall") or meshes.has("h_siding")) and roofed and meshes.size() <= HouseKit.MATS.size(),
		"%s block %s: its houses are one mesh per material (%s), %d triangles" % [label, k, meshes.keys(), tris])
	_t._check(buildings <= 2 and shapes >= expect and tris > expect * 400 and tris < expect * 12000,
		"%s block %s: %d houses, no Building boxes on them (%d left: pads), %d collision shapes on one body" % [label, k, expect, buildings, shapes])
	var yard_ok := chunk.find_children("YardGround", "MeshInstance3D", false, false).size() == 1 and chunk.find_children("YardWalls", "MeshInstance3D", false, false).size() == 1
	_t._check(yard_ok and not chunk.has_meta("house_kit"), "%s block %s: the yards are laid round the houses, the house lists spent" % [label, k])
	chunk.get_parent().remove_child(chunk)
	chunk.free()


## The block captured for the far city (CityChunk.capturing): what Skyline draws is the lod_box
## batch, a box a wing and two tilted slabs (plus a gable prism) for every pitched wing.
func _capture(city: Node3D, plan: CityPlan, k: Vector2i, label: String) -> void:
	var chunk := CityChunk.new()
	chunk.plan = plan
	chunk.ix = k.x
	chunk.iz = k.y
	chunk.level = CityChunk.Level.LOD
	chunk.capturing = true
	chunk.style = city.chunk_style()
	chunk.build()
	var lb: Dictionary = (chunk.captured.batch as Dictionary).get("lod_box", {})
	var xforms: Array = lb.get("xforms", [])
	var tilted := 0
	for xf: Transform3D in xforms:
		var bx := xf.basis.x.normalized()
		if absf(bx.y) > 0.1 and absf(bx.y) < 0.99:
			tilted += 1
	var pitched := 0
	for lot: Dictionary in _house_lots(plan, k.x, k.y):
		var hp := HouseKit.plan_house(plan, k.x, k.y, lot, plan.block(k.x, k.y).district)
		for w: Dictionary in hp.wings:
			if w.roof == "hip" or w.roof == "gable":
				pitched += 1
	_t._check(tilted >= pitched * 2 and xforms.size() >= _house_lots(plan, k.x, k.y).size(),
		"%s block %s for the far city: %d LOD boxes, %d tilted roof slabs for %d pitched wings" % [label, k, xforms.size(), tilted, pitched])
	chunk.free()


## With the kit off the house lots are Building boxes again (the A/B), and nothing else moved: the
## block's trash cans and props stand where they did.
func _off(city: Node3D, k: Vector2i) -> void:
	var on: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	on.build()
	var with := _props(on)
	var with_b := on.find_children("*", "Building", false, false).size()
	on.get_parent().remove_child(on)
	on.free()
	HouseKit.enabled = false
	var off: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	off.build()
	HouseKit.enabled = true
	var without := _props(off)
	var off_b := 0
	for c in off.get_children():
		if c is Building:
			off_b += 1
	off.get_parent().remove_child(off)
	off.free()
	var moved := 0
	for s: String in without:
		if not with.has(s):
			moved += 1
	_t._check(off_b > with_b and moved == 0, "block %s with the house kit off is Building boxes again (%d against %d), %d of %d props moved" % [k, off_b, with_b, moved, without.size()])


func _props(chunk: CityChunk) -> Array:
	var out: Array = []
	for c in chunk.get_children():
		if c is TrashCan:
			var p: Vector3 = (c as Node3D).position
			out.append("%s %.2f %.2f" % [c.get_class(), p.x, p.z])
	for r in chunk.prop_records:
		if str(r.kind).begins_with("lamp") or str(r.kind).begins_with("hydrant") or str(r.kind).begins_with("sign"):
			out.append("%s %.2f %.2f" % [r.kind, (r.position as Vector3).x, (r.position as Vector3).z])
	return out
