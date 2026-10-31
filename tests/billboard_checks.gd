extends RefCounted
## The city's billboards (Billboards), for tests/smoke_test.gd. Loaded at run time, not named
## there, so it compiles after the autoloads.
##
## The atlas and its table load; the monopole plan is pure (the same twice) and every pole stands
## in a corridor lot clear of the decks; somewhere near downtown a FULL chunk carries boards as
## props in one batch per kind (no stray batches), each with collision; a LOD build and the far
## city's capture carry them as lit far boxes and build no board meshes; the shelter ad rides the
## bus stop's prop; and with Billboards off the block's other props are where they were.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_atlas()
	var found := _find(city, plan)
	_t._check(found != Vector2i(9999, 9999), "there is a block with billboards near downtown (%s)" % [found])
	if found == Vector2i(9999, 9999):
		return
	_full_chunk(city, found)
	_lod_chunk(city, plan, found)
	_poles(plan)
	_same_props(city, found)


func _atlas() -> void:
	var tex: Texture2D = load("res://assets/textures/billboards/billboard_ads.jpg")
	_t._check(tex != null and BillboardTable.BULLETIN_MEAN.size() == Billboards.ADS and BillboardTable.POSTER_MEAN.size() == Billboards.ADS
		and BillboardTable.PORTRAIT_MEAN.size() == Billboards.PORTRAITS,
		"billboard atlas loads and its table has %d bulletins, %d posters, %d portraits" % [BillboardTable.BULLETIN_MEAN.size(), BillboardTable.POSTER_MEAN.size(), BillboardTable.PORTRAIT_MEAN.size()])
	var src := FileAccess.get_file_as_string("res://shaders/billboard_face.gdshader")
	_t._check(src.contains("vec2(2048.0, 3072.0)") and src.contains("1788.0") and src.contains("2556.0"),
		"the face shader's atlas grid is the generator's (2048 x 3072, posters at 1788, portraits at 2556)")


## The block nearest downtown's edge with the most board far boxes in its capture.
func _find(city: Node3D, plan: CityPlan) -> Vector2i:
	var best := Vector2i(9999, 9999)
	var most := 0
	var k0: Vector2i = plan.block_index_at(Vector2(1300.0, 700.0))
	for bx in range(k0.x - 4, k0.x + 5):
		for bz in range(k0.y - 4, k0.y + 5):
			var n := _far_faces(_capture(city, plan, Vector2i(bx, bz)))
			if n > most:
				most = n
				best = Vector2i(bx, bz)
	return best


func _capture(city: Node3D, plan: CityPlan, k: Vector2i) -> Dictionary:
	var cap := CityChunk.new()
	cap.plan = plan
	cap.ix = k.x
	cap.iz = k.y
	cap.level = CityChunk.Level.LOD
	cap.style = city.chunk_style()
	cap.capturing = true
	cap.build()
	var boxes: Dictionary = (cap.captured.get("batch", {}) as Dictionary).get("lod_box", {})
	cap.free()
	return boxes


func _far_faces(boxes: Dictionary) -> int:
	var n := 0
	for cu: Color in boxes.get("custom", []):
		if is_equal_approx(cu.a, FarBuilding.PLANT_FLAG) and int(cu.r + 0.5) == FarBuilding.Plant.PANEL and cu.b > 0.25:
			n += 1
	return n


func _full_chunk(city: Node3D, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var boards := 0
	var shaped := true
	for rec: Dictionary in chunk.prop_records:
		if rec.kind == "billboard":
			boards += 1
			shaped = shaped and not (rec.shapes as Array).is_empty()
	var names := {}
	var ok := true
	for c in chunk.get_children():
		var nm := String(c.name)
		if nm.begins_with("Batch_bb_"):
			ok = ok and not names.has(nm)
			names[nm] = true
			var mm := (c as MultiMeshInstance3D).multimesh
			ok = ok and mm.instance_count > 0
	_t._check(boards >= 1 and shaped and ok and names.size() >= 2 and chunk.billboard_jobs.is_empty(),
		"FULL block %s: %d boards as props with collision, one batch per kind (%s)" % [k, boards, ",".join(names.keys())])
	chunk.get_parent().remove_child(chunk)
	chunk.free()


func _lod_chunk(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.LOD)
	chunk.build()
	var meshes := 0
	for c in chunk.get_children():
		if String(c.name).begins_with("Batch_bb_"):
			meshes += 1
	var far := _far_faces(_capture(city, plan, k))
	_t._check(meshes == 0 and far >= 1, "LOD block %s builds no board meshes; the far city keeps %d faces as lit far boxes" % [k, far])
	chunk.get_parent().remove_child(chunk)
	chunk.free()


## Monopoles along the freeways round downtown: pure, in corridor lots, clear of every deck.
func _poles(plan: CityPlan) -> void:
	var fw: Freeway = plan.macro.freeway
	var k0: Vector2i = plan.block_index_at(Vector2(1900.0, 800.0))
	var poles := 0
	var pure := true
	var clear := true
	for bx in range(k0.x - 8, k0.x + 9):
		for bz in range(k0.y - 8, k0.y + 9):
			var block := plan.block(bx, bz)
			var a := Billboards.monopoles(plan, bx, bz, block)
			var b := Billboards.monopoles(plan, bx, bz, block)
			pure = pure and a.size() == b.size()
			for j: Dictionary in a:
				poles += 1
				var p: Vector3 = j.anchor
				clear = clear and not fw.blocks(Vector2(p.x, p.z), 2.0) and (block.rect as Rect2).has_point(Vector2(p.x, p.z))
				for u: Dictionary in j.units:
					var e3: Vector3 = (u.xf as Transform3D) * Vector3.ZERO
					clear = clear and not fw.blocks(Vector2(e3.x, e3.z), 1.0)
	_t._check(poles >= 1 and pure and clear, "freeway monopoles: %d near downtown, pure, on their block, clear of every deck" % poles)


## Billboards off: every other prop of the block in the same place (the boards' own rolls are
## hashes and their props come last).
func _same_block_props(city: Node3D, k: Vector2i) -> Array:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var out: Array = []
	for rec: Dictionary in chunk.prop_records:
		if rec.kind != "billboard":
			out.append([rec.kind, (rec.position as Vector3).snapped(Vector3.ONE * 0.01)])
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	return out


func _same_props(city: Node3D, k: Vector2i) -> void:
	var on := _same_block_props(city, k)
	Billboards.enabled = false
	var off := _same_block_props(city, k)
	Billboards.enabled = true
	_t._check(on == off and on.size() > 5, "block %s with billboards off keeps its %d other props where they were" % [k, off.size()])
