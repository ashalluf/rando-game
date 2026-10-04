extends RefCounted
## The ground outside downtown and midtown (YardFill), for tests/smoke_test.gd. Loaded at run time,
## not named there, so it compiles after the autoloads.
##
## Coverage (GroundCoverage, the numbers tools/lot_coverage.gd prints): beach-town, campus and
## freeway blocks round the bookmarks, before (LotFill only) and after (both fills) - the bare
## share must fall to a few percent, and the right of way must be filled out to its cells. Then
## FULL chunks of a beach block (with its walk street when the seed gives one), a campus block and
## a freeway block straight from the plan: the yard ground is ONE shadowless mesh on the yard
## shader and everything upright ONE mesh on the walls shader, the planting keeps its budgets, a
## LOD build of the same block has neither, and with the fill off the block is the same block
## (hash-seeded: the chunk rng untouched).

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_coverage(plan)
	_shader_ids()
	_campus_plan(plan)
	var beach := _find(plan, CityPlan.District.BEACHTOWN, Vector2(-687.0, 100.0), false)
	var campus := _find(plan, CityPlan.District.CAMPUS, Vector2(-620.0, -500.0), false)
	var freeway := _find(plan, -1, Vector2(-503.0, 100.0), true)
	_t._check(beach != Vector2i(9999, 9999) and campus != Vector2i(9999, 9999) and freeway != Vector2i(9999, 9999),
		"there are beach-town, campus and freeway blocks to build (%s %s %s)" % [beach, campus, freeway])
	if beach != Vector2i(9999, 9999):
		_full_chunk(city, plan, beach, "beach town")
		_same_block(city, beach)
		_lod_chunk(city, beach)
	if campus != Vector2i(9999, 9999):
		_full_chunk(city, plan, campus, "campus")
	if freeway != Vector2i(9999, 9999):
		_full_chunk(city, plan, freeway, "freeway")
		_same_block(city, freeway)


## The bare share before and after, over a window of blocks round each bookmark.
func _coverage(plan: CityPlan) -> void:
	var rows := {"BEACHTOWN": [Rect2(-1000.0, -800.0, 700.0, 1400.0), 0.12], "CAMPUS": [Rect2(-900.0, -800.0, 500.0, 600.0), 0.08],
		"FREEWAY": [Rect2(-700.0, -300.0, 400.0, 900.0), 0.15]}
	for row: String in rows:
		var area: Rect2 = rows[row][0]
		var before := _bare(plan, area, row, 1)
		var after := _bare(plan, area, row, 2)
		_t._check(before.y > 0 and after.x < float(rows[row][1]) and after.x < before.x * 0.5,
			"%s ground is filled: bare %.1f %% -> %.1f %% over %d blocks" % [row, 100.0 * before.x, 100.0 * after.x, int(before.y)])
	# The right of way out to its cells: nothing bare inside a corridor lot's cell.
	var lo: Vector2i = plan.block_index_at(Vector2(-700.0, -300.0))
	var hi: Vector2i = plan.block_index_at(Vector2(-300.0, 600.0))
	var row_cells := 0
	var corridor_lots := 0
	for bx in range(lo.x, hi.x + 1):
		for bz in range(lo.y, hi.y + 1):
			var res := GroundCoverage.block(plan, bx, bz, 2, 1.0)
			if not res.is_empty() and res.freeway:
				row_cells += int(res.k[GroundCoverage.ROW])
				for lot: Dictionary in plan.lots(bx, bz):
					if YardFill.is_corridor(plan, lot):
						corridor_lots += 1
	_t._check(corridor_lots > 0 and row_cells > corridor_lots * 150, "the freeway's right of way is filled out to its cells (%d lots, %d m2)" % [corridor_lots, row_cells])


## [bare share, blocks] of the blocks of `row` whose centre is in `area`.
func _bare(plan: CityPlan, area: Rect2, row: String, fill: int) -> Vector2:
	var lo: Vector2i = plan.block_index_at(area.position)
	var hi: Vector2i = plan.block_index_at(area.end)
	var bare := 0
	var cells := 0
	var blocks := 0
	for bx in range(lo.x, hi.x + 1):
		for bz in range(lo.y, hi.y + 1):
			if not area.has_point((plan.block(bx, bz).rect as Rect2).get_center()):
				continue
			var res := GroundCoverage.block(plan, bx, bz, fill, 1.0)
			if res.is_empty() or not (res.row == row or (row == "FREEWAY" and res.freeway)):
				continue
			blocks += 1
			bare += int(res.k[GroundCoverage.BARE])
			cells += int(res.cells)
	return Vector2(float(bare) / maxf(float(cells), 1.0), blocks)


## The campus round its hall has quads with walks corner to corner, a car park and service yards,
## and none of it under the hall.
func _campus_plan(plan: CityPlan) -> void:
	var hall := Rect2()
	for lm in Landmarks.all():
		if lm.id == "campus_hall":
			hall = Landmarks.campus_footprint(lm)
	var lo: Vector2i = plan.block_index_at(Vector2(-900.0, -800.0))
	var hi: Vector2i = plan.block_index_at(Vector2(-400.0, -200.0))
	var n := {"quads": 0, "parks": 0, "service": 0, "strips": 0}
	var under := 0
	for bx in range(lo.x, hi.x + 1):
		for bz in range(lo.y, hi.y + 1):
			var b := plan.block(bx, bz)
			if int(b.district) != CityPlan.District.CAMPUS or int(b.kind) != CityPlan.BlockKind.BUILDINGS:
				continue
			var entries: Array = []
			var cp := YardFill.campus_block(plan, bx, bz, entries)
			for key: String in n:
				n[key] += (cp[key] as Array).size()
			for r: Rect2 in cp.quads + cp.parks:
				if r.intersects(hall):
					under += 1
	_t._check(n.quads >= 1 and n.parks >= 1 and n.strips >= 2 and under == 0,
		"the campus round its hall has quads, walks and a car park, none under the hall (%s)" % [n])


## The kinds YardFill writes are the ones its shaders read (their header comments list them).
func _shader_ids() -> void:
	var ground := FileAccess.get_file_as_string("res://shaders/lot_yard.gdshader")
	var walls := FileAccess.get_file_as_string("res://shaders/lot_walls.gdshader")
	var ok := ground.contains("7 ivy") and ground.contains("8 a swimming pool") and ground.contains("9 gravel yard") \
		and walls.contains("3 sound wall") and walls.contains("7 chain-link") and walls.contains("9 galvanised post")
	_t._check(ok and YardFill.G_IVY == 7 and YardFill.G_POOL == 8 and YardFill.G_GRAVEL == 9 and YardFill.W_SOUND == 3 and YardFill.W_CHAIN == 7 and YardFill.W_POST == 9,
		"YardFill's ground and upright kinds match the shaders' tables")


## The block of `district` (any, with a corridor lot, when `freeway`) with lots nearest `near`.
func _find(plan: CityPlan, district: int, near: Vector2, freeway: bool) -> Vector2i:
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
			if plan.macro.replica and plan.macro.replica.block_role(plan, k.x, k.y) != 0:
				continue
			if district >= 0 and int(b.district) != district:
				continue
			var lots := plan.lots(k.x, k.y)
			if lots.size() < 4:
				continue
			if freeway:
				var any := false
				for lot: Dictionary in lots:
					any = any or YardFill.is_corridor(plan, lot)
				if not any:
					continue
			var d := rect.get_center().distance_to(near)
			if d < best_d:
				best_d = d
				best = k
	return best


func _full_chunk(city: Node3D, plan: CityPlan, k: Vector2i, label: String) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var grounds := chunk.find_children("YardGround", "MeshInstance3D", false, false)
	var walls := chunk.find_children("YardWalls", "MeshInstance3D", false, false)
	var ground_ok := grounds.size() == 1 and (grounds[0] as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
		and (grounds[0] as MeshInstance3D).material_override == YardFill.yard_material() and (grounds[0] as MeshInstance3D).mesh.get_surface_count() == 1
	_t._check(ground_ok, "%s block %s: its yards are one shadowless mesh on the yard shader (%d)" % [label, k, grounds.size()])
	var walls_ok := walls.size() == 1 and (walls[0] as MeshInstance3D).material_override == YardFill.walls_material() \
		and (walls[0] as MeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_t._check(walls_ok, "%s block %s: its walls, fences and hedges are one casting mesh on the walls shader (%d)" % [label, k, walls.size()])
	_t._check(chunk._yard_shrubs <= YardFill.MAX_SHRUBS and chunk._yard_trees <= YardFill.MAX_TREES and chunk._yard_palms <= YardFill.MAX_PALMS and chunk._yard_cars <= YardFill.MAX_CARS,
		"%s block %s: the planting keeps its budgets (shrubs %d, trees %d, palms %d, cars %d)" % [label, k, chunk._yard_shrubs, chunk._yard_trees, chunk._yard_palms, chunk._yard_cars])
	var lists_empty: bool = chunk._yard_ground.is_empty() and chunk._yard_walls.is_empty() and chunk._yard_ivy.is_empty() and chunk._yard_strips.is_empty()
	_t._check(lists_empty, "%s block %s: the yard lists are spent at the finish" % [label, k])
	if label == "beach town":
		var bp := YardFill.beach_block(plan, k.x, k.y, chunk._yard_lots)
		var kinds := {}
		for lp: Dictionary in bp.lots:
			for pc: Array in lp.pieces:
				kinds[pc[1]] = true
		_t._check(kinds.size() >= 4 and not bp.lots.is_empty(), "beach block %s: %d yards in %d kinds of ground (walk street: %s)" % [k, bp.lots.size(), kinds.size(), (bp.walk as Rect2).size.x > 0.0])
	chunk.get_parent().remove_child(chunk)
	chunk.free()


## Built with the fill off, the block is the same block: the same buildings and trash cans, and every
## prop it had is still there (the fill adds lamps and benches of its own).
func _same_block(city: Node3D, k: Vector2i) -> void:
	var on: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	on.build()
	var with := _signature(on)
	on.get_parent().remove_child(on)
	on.free()
	YardFill.enabled = false
	var off: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	off.build()
	YardFill.enabled = true
	var without := _signature(off)
	var no_yard := off.get_node_or_null("YardGround") == null and off.get_node_or_null("YardWalls") == null
	off.get_parent().remove_child(off)
	off.free()
	var missing := 0
	for s: String in without:
		if not with.has(s):
			missing += 1
	_t._check(no_yard and missing == 0 and with.size() >= without.size(),
		"block %s built without the yard fill is the same block (%d of %d things moved)" % [k, missing, without.size()])


func _signature(chunk: CityChunk) -> Array:
	var out: Array = []
	for c in chunk.get_children():
		if c is Building or c is TrashCan:
			var p: Vector3 = (c as Node3D).position
			out.append("%s %.2f %.2f" % [c.get_class(), p.x, p.z])
	for r in chunk.prop_records:
		out.append("%s %.2f %.2f" % [r.kind, (r.position as Vector3).x, (r.position as Vector3).z])
	return out


## A LOD build of a yard block has no yard meshes (the lawns join its merged far ground).
func _lod_chunk(city: Node3D, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.LOD)
	chunk.build()
	var none := chunk.get_node_or_null("YardGround") == null and chunk.get_node_or_null("YardWalls") == null
	_t._check(none and chunk._yard_walls.is_empty(), "a LOD build of block %s lays no yard meshes" % [k])
	chunk.get_parent().remove_child(chunk)
	chunk.free()
