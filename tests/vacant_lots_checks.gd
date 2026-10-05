extends RefCounted
## The vacant lots and gravel car parks (VacantLots, VacantKit), for tests/smoke_test.gd. Loaded at
## run time, not named there, so it compiles after the autoloads.
##
## The pure plan over downtown and the midtown and industrial land round it: a small share of the
## lots in MIDTOWN, INDUSTRIAL and downtown's edges stand empty, car parks near the arena, none in
## the downtown core away from it, the suburbs or the beach town, never a courtyard or an inner lot;
## off (`enabled` false) none at all. Each plan: the ground pieces partition the lot's cell, every
## item and fence stands inside it. Then a FULL chunk of a block with a vacant lot: ONE shadowless
## ground mesh on the ground shader, ONE casting upright mesh on the walls shader, no Building on
## the lot, the weeds in shadowless batches; built with VacantLots off the block keeps every pavement
## prop where it was; a LOD build lays no meshes and the far city's capture records the lot's cell
## as ground.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_shaders()
	var found := _plans(plan)
	if found.is_empty():
		return
	var k: Vector2i = found[0]
	var lot: Dictionary = found[1]
	_full_chunk(city, k, lot)
	_same_block(city, k, (lot.cell as Rect2).grow(0.5))
	_lod_chunk(city, plan, k, lot)


func _shaders() -> void:
	var ok := true
	for p: String in ["res://shaders/vacant_ground.gdshader", "res://shaders/vacant_walls.gdshader", "res://shaders/vacant_weeds.gdshader"]:
		var sh: Shader = load(p)
		ok = ok and sh != null and sh.get_shader_uniform_list().size() >= 3
	# The walls shader's kind table runs to the kit's last kind.
	var src := FileAccess.get_file_as_string("res://shaders/vacant_walls.gdshader")
	ok = ok and src.contains("%d lamp" % VacantKit.K_LAMP) and VacantKit.KIND_COUNT == VacantKit.K_LAMP + 1
	_t._check(ok, "the vacant lots' three shaders load and the walls shader's kinds match VacantKit's")


## Walks the plan; returns [block, lot] of a vacant lot with a slab and a sign to build, or [].
func _plans(plan: CityPlan) -> Array:
	var area := Rect2(0.0, -1800.0, 4200.0, 5600.0)
	var lo: Vector2i = plan.block_index_at(area.position)
	var hi: Vector2i = plan.block_index_at(area.end)
	var per := {}
	var lots := {}
	var bad := 0
	var bad_plan := ""
	var core := 0
	var near_arena_parks := 0
	var best: Array = []
	for bx in range(lo.x, hi.x + 1):
		for bz in range(lo.y, hi.y + 1):
			var b: Dictionary = plan.block(bx, bz)
			if not area.has_point((b.rect as Rect2).get_center()):
				continue
			var d: int = b.district
			for lot: Dictionary in plan.lots(bx, bz):
				lots[d] = int(lots.get(d, 0)) + 1
				var kind := VacantLots.kind_of(plan, bx, bz, lot)
				if kind == VacantLots.NONE:
					continue
				per[d] = int(per.get(d, 0)) + 1
				if lot.yard or not lot.edge:
					bad += 1
				var centre: Vector2 = lot.center
				var near := centre.distance_to(VacantLots.arena_xz()) < VacantLots.ARENA_REACH
				if d == CityPlan.District.DOWNTOWN and plan.macro.skyline_boost(centre) >= VacantLots.EDGE_BOOST and not near:
					core += 1
				if near and kind == VacantLots.PARKING:
					near_arena_parks += 1
				var lp := VacantLots.plan_lot(plan, bx, bz, lot, kind)
				var why := _plan_ok(lp)
				if why != "" and bad_plan == "":
					bad_plan = "block (%d,%d): %s" % [bx, bz, why]
				if best.is_empty() and kind == VacantLots.VACANT and (lp.slab as Rect2).size != Vector2.ZERO:
					var has_sign := false
					for it: Dictionary in lp.items:
						has_sign = has_sign or it.t == "lease"
					if has_sign:
						best = [Vector2i(bx, bz), lot]
	var share := func(d: int) -> float: return float(per.get(d, 0)) / maxf(float(lots.get(d, 0)), 1.0)
	var mid: float = share.call(CityPlan.District.MIDTOWN)
	var ind: float = share.call(CityPlan.District.INDUSTRIAL)
	var dt: float = share.call(CityPlan.District.DOWNTOWN)
	var others := int(per.get(CityPlan.District.SUBURBS, 0)) + int(per.get(CityPlan.District.BEACHTOWN, 0)) + int(per.get(CityPlan.District.CAMPUS, 0))
	_t._check(mid > 0.015 and mid < 0.1 and ind > 0.01 and ind < 0.1 and dt > 0.01 and dt < 0.12 and others == 0 and bad == 0 and core == 0,
		"a small share of lots stand empty: midtown %.1f %%, industrial %.1f %%, downtown edges %.1f %%, none elsewhere (%d), none inner (%d) or in the core (%d)" % [100.0 * mid, 100.0 * ind, 100.0 * dt, others, bad, core])
	_t._check(near_arena_parks >= 3, "gravel car parks round the arena (%d)" % near_arena_parks)
	_t._check(bad_plan == "", "every vacant lot's plan partitions its cell and keeps its pieces inside it %s" % bad_plan)
	VacantLots.enabled = false
	var off := 0
	for bx in range(lo.x, lo.x + 12):
		for bz in range(lo.y, hi.y + 1):
			for lot: Dictionary in plan.lots(bx, bz):
				off += int(VacantLots.kind_of(plan, bx, bz, lot) != VacantLots.NONE)
	VacantLots.enabled = true
	_t._check(off == 0, "with VacantLots off no lot stands empty (%d)" % off)
	_t._check(not best.is_empty(), "there is a vacant lot with a slab and a broker's sign to build")
	return best


func _plan_ok(lp: Dictionary) -> String:
	var cell: Rect2 = lp.cell
	var area := 0.0
	var pieces: Array = lp.ground
	for i in pieces.size():
		var r: Rect2 = pieces[i][0]
		area += r.get_area()
		if not cell.grow(0.01).encloses(r):
			return "a ground piece outside the cell"
		for j in range(i + 1, pieces.size()):
			var o: Rect2 = pieces[j][0]
			if r.intersection(o).get_area() > 0.01:
				return "two ground pieces overlap"
	if absf(area - cell.get_area()) > 0.05:
		return "the ground pieces cover %.1f of %.1f m2" % [area, cell.get_area()]
	for fe: Dictionary in lp.fences:
		if not cell.grow(0.01).has_point(fe.a) or not cell.grow(0.01).has_point(fe.b):
			return "a fence outside the cell"
	for it: Dictionary in lp.items:
		if it.has("p") and not cell.grow(0.05).has_point(it.p):
			return "%s outside the cell" % it.t
	for sl: Array in lp.stalls:
		if not cell.has_point(sl[0]):
			return "a stall outside the cell"
	if not (lp.slab as Rect2).size == Vector2.ZERO and not cell.encloses(lp.slab):
		return "the slab outside the cell"
	return ""


func _full_chunk(city: Node3D, k: Vector2i, lot: Dictionary) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var grounds := chunk.find_children("VacantGround", "MeshInstance3D", false, false)
	var walls := chunk.find_children("VacantWalls", "MeshInstance3D", false, false)
	_t._check(grounds.size() == 1 and (grounds[0] as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		and (grounds[0] as MeshInstance3D).material_override == VacantLots.ground_material(),
		"vacant block %s: the lots' ground is one shadowless mesh on the ground shader (%d)" % [k, grounds.size()])
	var tris := 0
	if walls.size() == 1:
		tris = ((walls[0] as MeshInstance3D).mesh as ArrayMesh).surface_get_array_len(0) / 3
	_t._check(walls.size() == 1 and (walls[0] as MeshInstance3D).material_override == VacantKit.walls_material()
		and (walls[0] as MeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and tris > 500 and tris < 120000,
		"vacant block %s: fences, signs, slab, rubble and junk are one casting mesh on the walls shader (%d triangles)" % [k, tris])
	var cell: Rect2 = lot.cell
	var on_lot := 0
	for c in chunk.get_children():
		if c is Building and cell.has_point(Vector2((c as Node3D).position.x, (c as Node3D).position.z)):
			on_lot += 1
	var weeds_ok := false
	var shadow_ok := true
	for c in chunk.get_children():
		var nm := String(c.name)
		if nm.begins_with("Batch_vac_"):
			weeds_ok = true
			shadow_ok = shadow_ok and (c as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if nm.begins_with("BatchShadow_vac_"):
			shadow_ok = false
	_t._check(on_lot == 0 and weeds_ok and shadow_ok,
		"vacant block %s: no Building on the empty lot (%d), its weeds in shadowless batches" % [k, on_lot])
	chunk.get_parent().remove_child(chunk)
	chunk.free()


## Built with VacantLots off, the block keeps every pavement prop and trash can where it was (off
## the lot).
func _same_block(city: Node3D, k: Vector2i, cell: Rect2) -> void:
	var on: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	on.build()
	var with := _signature(on, cell)
	on.get_parent().remove_child(on)
	on.free()
	VacantLots.enabled = false
	var off: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	off.build()
	VacantLots.enabled = true
	var without := _signature(off, cell)
	var none := off.get_node_or_null("VacantGround") == null and off.get_node_or_null("VacantWalls") == null
	off.get_parent().remove_child(off)
	off.free()
	var missing := 0
	for s: String in without:
		if not with.has(s):
			missing += 1
	_t._check(none and missing == 0 and with.size() >= without.size(),
		"vacant block %s built without VacantLots keeps its street furniture (%d of %d moved)" % [k, missing, without.size()])


## The trash cans and props of the block, less what stood on the lot itself (a building's forecourt
## bollards and lamps, its billboard).
func _signature(chunk: CityChunk, cell: Rect2) -> Array:
	var out: Array = []
	for c in chunk.get_children():
		if c is TrashCan:
			var p: Vector3 = (c as Node3D).position
			out.append("%s %.2f %.2f" % [c.get_class(), p.x, p.z])
	for r in chunk.prop_records:
		var rp: Vector3 = r.position
		if cell.has_point(Vector2(rp.x, rp.z)):
			continue
		out.append("%s %.2f %.2f" % [r.kind, (r.position as Vector3).x, (r.position as Vector3).z])
	return out


## A LOD build lays no vacant-lot meshes, and the far city's capture records the lot as ground.
func _lod_chunk(city: Node3D, plan: CityPlan, k: Vector2i, lot: Dictionary) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.LOD)
	chunk.build()
	var none := chunk.get_node_or_null("VacantGround") == null and chunk.get_node_or_null("VacantWalls") == null
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	var cap := CityChunk.new()
	cap.plan = plan
	cap.ix = k.x
	cap.iz = k.y
	cap.level = CityChunk.Level.LOD
	cap.style = city.chunk_style()
	cap.capturing = true
	cap.build()
	var cell: Rect2 = lot.cell
	var hit := false
	for g: Array in cap.captured.get("ground", []):
		var r: Rect2 = g[0]
		if r.position.distance_to(cell.position) < 0.05 and r.size.distance_to(cell.size) < 0.05:
			hit = true
	cap.free()
	_t._check(none and hit, "a LOD build of vacant block %s lays no meshes and the far city captures the lot as ground" % [k])
