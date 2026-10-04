extends RefCounted
## The industrial district (Industrial, IndustrialKit), for tests/smoke_test.gd. Loaded at run
## time, not named there, so it compiles after the autoloads.
##
## Coverage (GroundCoverage): the industrial blocks round Vernon and the Arts District, before
## (fill 2: YardFill and LotFill, no Industrial) and after - the bare share must fall to a few
## percent. The plans over a window of blocks: warehouses with truck courts and docks, rail spurs,
## brick and murals in the Arts District; every warehouse inside its cell and on no other lot's
## ground, no yard piece under a warehouse, outside its block or on another piece (identical
## surfaces at one height z-fight). Then a FULL chunk of a block with a court: the ground is ONE
## shadowless mesh on the ground shader and everything upright ONE casting mesh on the walls
## shader, no Building for a warehouse lot, trailers at the docks, the warehouses in the
## encampments' wall list; built with Industrial off, every pavement prop is where it was; a LOD
## build and the far city's capture carry the warehouses as far boxes and build no meshes.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_coverage(plan)
	_kinds()
	var found := _plans(plan)
	var k: Vector2i = found
	_t._check(k != Vector2i(9999, 9999), "there is an industrial block with a truck court to build (%s)" % [k])
	if k == Vector2i(9999, 9999):
		return
	_full_chunk(city, plan, k)
	_same_block(city, k)
	_lod_chunk(city, plan, k)


func _coverage(plan: CityPlan) -> void:
	var area := Rect2(2250.0, 2500.0, 900.0, 1400.0)
	var before := _bare(plan, area, 2)
	var after := _bare(plan, area, 3)
	_t._check(before.y >= 20 and before.x > 0.2 and after.x < 0.03,
		"INDUSTRIAL ground is filled: bare %.1f %% -> %.1f %% over %d blocks" % [100.0 * before.x, 100.0 * after.x, int(before.y)])


func _bare(plan: CityPlan, area: Rect2, fill: int) -> Vector2:
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
			if res.is_empty() or res.row != "INDUSTRIAL":
				continue
			blocks += 1
			bare += int(res.k[GroundCoverage.BARE])
			cells += int(res.cells)
	return Vector2(float(bare) / maxf(float(cells), 1.0), blocks)


## The walls shader handles every kind the kit writes (one branch each, the last an else).
func _kinds() -> void:
	var src: String = (load("res://shaders/industrial_walls.gdshader") as Shader).code
	var branches := src.count("} else if (kind < ")
	_t._check(branches == IndustrialKit.KIND_COUNT - 2 and src.contains("if (kind < 0.5)"),
		"the industrial walls shader has a branch for each of the kit's %d kinds (%d)" % [IndustrialKit.KIND_COUNT, branches + 2])
	var gsrc: String = (load("res://shaders/industrial_ground.gdshader") as Shader).code
	_t._check(gsrc.count("} else if (kind < ") == 5, "the industrial ground shader has a branch for each ground kind")


## Plans over a window of Vernon and of the Arts District. Returns a block with a truck court.
func _plans(plan: CityPlan) -> Vector2i:
	var n := {"warehouses": 0, "courts": 0, "docks": 0, "spurs": 0, "brick": 0, "murals": 0, "towers": 0, "store": 0}
	var bad := []
	var court_block := Vector2i(9999, 9999)
	for area: Rect2 in [Rect2(2400.0, 3100.0, 650.0, 650.0), Rect2(3990.0, 300.0, 360.0, 900.0)]:
		var lo: Vector2i = plan.block_index_at(area.position)
		var hi: Vector2i = plan.block_index_at(area.end)
		for bx in range(lo.x, hi.x + 1):
			for bz in range(lo.y, hi.y + 1):
				var b := plan.block(bx, bz)
				if int(b.district) != CityPlan.District.INDUSTRIAL or int(b.kind) != CityPlan.BlockKind.BUILDINGS or b.has("site"):
					continue
				var inner: Rect2 = (b.rect as Rect2).grow(-plan.sidewalk_width)
				var entries := Industrial.block_entries(plan, bx, bz)
				var bp := Industrial.block_plan(plan, bx, bz, entries)
				if not (bp.spur as Dictionary).is_empty():
					n.spurs += 1
				if bp.tower != null:
					n.towers += 1
				var builds: Array[Rect2] = []
				for e: Dictionary in entries:
					var lp: Dictionary = e.plan
					for r: Rect2 in e.parts:
						builds.append(r)
					if lp.is_empty():
						continue
					n.warehouses += 1
					var cell: Rect2 = lp.cell
					var rect: Rect2 = lp.rect
					if not cell.grow(0.05).encloses(rect) or rect.size.x < 10.0 or rect.size.y < 10.0:
						bad.append("warehouse %s outside its cell %s" % [rect, cell])
					if float(lp.court) > 0.0:
						n.courts += 1
						if court_block == Vector2i(9999, 9999) and (lp.docks as Array).size() >= 5:
							court_block = Vector2i(bx, bz)
					for dk: Dictionary in lp.docks:
						n.docks += 1 if int(dk.kind) == 0 else 0
					n.brick += 1 if lp.brick else 0
					n.murals += (lp.murals as Array).size()
				var pieces: Array = bp.pieces
				for i in pieces.size():
					var r: Rect2 = pieces[i][0]
					if pieces[i][1] == "store":
						n.store += 1
					if not inner.grow(0.05).encloses(r):
						bad.append("piece %s outside block %s" % [r, inner])
					for w: Rect2 in builds:
						if r.intersection(w).get_area() > 0.05:
							bad.append("piece %s under a building %s" % [r, w])
					for j in range(i + 1, pieces.size()):
						if r.intersection(pieces[j][0]).get_area() > 0.05:
							bad.append("pieces overlap %s %s" % [r, pieces[j][0]])
					if not (bp.spur as Dictionary).is_empty() and r.intersection(bp.spur.rect).get_area() > 0.05:
						bad.append("piece %s on the spur" % [r])
	_t._check(bad.is_empty(), "industrial plans: warehouses in their cells, yards on nobody's ground (%s)" % [bad.slice(0, 3)])
	_t._check(n.warehouses >= 20 and n.courts >= 8 and n.docks >= 40 and n.spurs >= 2 and n.brick >= 4 and n.murals >= 4 and n.store >= 5,
		"industrial plans: warehouses, truck courts, docks, rail spurs, Arts District brick and murals, storage yards (%s)" % [n])
	return court_block


func _full_chunk(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var grounds := chunk.find_children("IndustrialGround", "MeshInstance3D", false, false)
	var walls := chunk.find_children("IndustrialWalls", "MeshInstance3D", false, false)
	_t._check(grounds.size() == 1 and (grounds[0] as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		and (grounds[0] as MeshInstance3D).material_override == Industrial.ground_material(),
		"industrial block %s: its yards are one shadowless mesh on the ground shader (%d)" % [k, grounds.size()])
	_t._check(walls.size() == 1 and (walls[0] as MeshInstance3D).material_override == IndustrialKit.walls_material()
		and (walls[0] as MeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"industrial block %s: its warehouses, docks and fences are one casting mesh on the walls shader (%d)" % [k, walls.size()])
	var entries: Array = chunk._ind.get("entries", [])
	var houses := 0
	var others := 0
	for e: Dictionary in entries:
		if (e.plan as Dictionary).is_empty():
			others += 1
		else:
			houses += 1
	var buildings := 0
	for c in chunk.get_children():
		if c is Building:
			buildings += 1
	var trailers := 0
	for c in chunk.get_children():
		if String(c.name).begins_with("Batch_ind_trailer_"):
			trailers += ((c as MultiMeshInstance3D).multimesh.instance_count)
	_t._check(houses >= 1 and buildings <= others and trailers >= 1 and (chunk._ind.foot as Array).size() == houses,
		"industrial block %s: %d warehouses built as Industrial's (no Building), %d trailers at the docks" % [k, houses, trailers])
	var feet := StreetDetail._footprints(chunk)
	var all_in := true
	for r: Rect2 in chunk._ind.foot:
		all_in = all_in and feet.has(r)
	_t._check(all_in, "industrial block %s: the warehouses are walls the encampments and service drops see" % [k])
	chunk.get_parent().remove_child(chunk)
	chunk.free()


## Built with Industrial off, the block keeps every pavement prop and trash can where it was.
func _same_block(city: Node3D, k: Vector2i) -> void:
	var on: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	on.build()
	var with := _signature(on)
	on.get_parent().remove_child(on)
	on.free()
	Industrial.enabled = false
	var off: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	off.build()
	Industrial.enabled = true
	var without := _signature(off)
	var none := off.get_node_or_null("IndustrialGround") == null and off.get_node_or_null("IndustrialWalls") == null
	off.get_parent().remove_child(off)
	off.free()
	var missing := 0
	for s: String in without:
		if not with.has(s):
			missing += 1
	_t._check(none and missing == 0 and with.size() >= without.size(),
		"industrial block %s built without Industrial keeps its street furniture (%d of %d moved)" % [k, missing, without.size()])


func _signature(chunk: CityChunk) -> Array:
	var out: Array = []
	for c in chunk.get_children():
		if c is TrashCan:
			var p: Vector3 = (c as Node3D).position
			out.append("%s %.2f %.2f" % [c.get_class(), p.x, p.z])
	for r in chunk.prop_records:
		out.append("%s %.2f %.2f" % [r.kind, (r.position as Vector3).x, (r.position as Vector3).z])
	return out


## A LOD build lays no industrial meshes, and it and the far city's capture draw each warehouse as
## a far box at its footprint.
func _lod_chunk(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.LOD)
	chunk.build()
	var none := chunk.get_node_or_null("IndustrialGround") == null and chunk.get_node_or_null("IndustrialWalls") == null
	var foot: Array = chunk._ind.get("foot", [])
	_t._check(none and not foot.is_empty(), "a LOD build of industrial block %s lays no industrial meshes (%d warehouses as far boxes)" % [k, foot.size()])
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
	var boxes: Dictionary = (cap.captured.get("batch", {}) as Dictionary).get("lod_box", {})
	var hits := 0
	for r: Rect2 in cap._ind.get("foot", []):
		for x: Transform3D in boxes.get("xforms", []):
			if absf(x.origin.x - r.get_center().x) < 0.05 and absf(x.origin.z - r.get_center().y) < 0.05:
				hits += 1
				break
	_t._check(hits >= 1 and hits == (cap._ind.get("foot", []) as Array).size(), "the far city captures industrial block %s's warehouses as far boxes (%d)" % [k, hits])
	cap.free()
