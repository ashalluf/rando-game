extends RefCounted
## Wilshire's deco boulevard (DecoBoulevard, DecoBuild), for tests/smoke_test.gd. Loaded at run
## time, not named there, so it compiles after the autoloads.
##
## Checks the pure plan along Wilshire's midtown stretch (a run of every kind, only boulevard
## frontage in midtown, a theatre a block at most, the same answer asked twice, every massing box
## inside its cell and near its lot's planned height, invented names), the shader's kinds, then
## builds a FULL chunk with a deco tower and checks its meshes and materials, its collision, that
## no Building stands on a deco lot and that its parked cars and other buildings are where they
## are with the deco off (hash-seeded: the chunk rng untouched), and a LOD chunk's far boxes.

var _t: Node

const REAL_NAMES := ["WILTERN", "BULLOCKS", "PELLISSIER", "EL REY", "PANTAGES", "ORPHEUM", "MAYAN", "EL ROYALE",
	"TALMADGE", "OVIATT", "EASTERN", "CORONET", "MIRAMAR", "SAVOY", "PALLADIUM"]


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var stretch := _wilshire(plan)
	_plan_checks(plan, stretch)
	_shader_checks()
	var tower_block := Vector2i(99999, 0)
	for k: Vector2i in stretch:
		for lp: Dictionary in DecoBoulevard.block_plans(plan, k.x, k.y).values():
			if int(lp.kind) == DecoBoulevard.Kind.TOWER and tower_block.x == 99999:
				tower_block = k
	_t._check(tower_block.x != 99999, "Wilshire's midtown stretch has a zigzag deco tower")
	if tower_block.x != 99999:
		_full_chunk(city, plan, tower_block)
		_lod_chunk(city, plan, tower_block)


## The blocks either side of Wilshire from MacArthur Park to the 110.
func _wilshire(plan: CityPlan) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var z := 312.7
	var x := 480.0
	while x < 1650.0:
		var n := plan.block_index_at(Vector2(x, z - 20.0))
		var s := plan.block_index_at(Vector2(x, z + 20.0))
		out.append(n)
		out.append(s)
		x = (plan.block(n.x, n.y).rect as Rect2).end.x + 20.0
	return out


func _plan_checks(plan: CityPlan, stretch: Array[Vector2i]) -> void:
	var counts := {}
	var total := 0
	var only_midtown := true
	var on_boulevard := true
	var one_theatre := true
	var inside := true
	var heights := true
	var invented := true
	for k: Vector2i in stretch:
		var plans := DecoBoulevard.block_plans(plan, k.x, k.y)
		var theatres := 0
		for lp: Dictionary in plans.values():
			total += 1
			counts[int(lp.kind)] = int(counts.get(int(lp.kind), 0)) + 1
			only_midtown = only_midtown and plan.block(k.x, k.y).district == CityPlan.District.MIDTOWN
			var road: Array = lp.road
			on_boulevard = on_boulevard and plan.road_width(road[0], road[1]) >= DecoBoulevard.BOULEVARD_WIDTH
			if int(lp.kind) == DecoBoulevard.Kind.THEATRE:
				theatres += 1
			var cell: Rect2 = lp.cell
			inside = inside and cell.grow(0.05).encloses(lp.foot)
			var xf := DecoBoulevard.frame_xform(lp, 0.0)
			for mb: Array in lp.boxes:
				var c: Vector3 = mb[0]
				var sz: Vector3 = mb[1]
				heights = heights and c.y + sz.y * 0.5 <= float(lp.h) + 10.0
				for corner in 4:
					var q := c + Vector3(sz.x * (0.5 if corner & 1 else -0.5), 0.0, sz.z * (0.5 if corner & 2 else -0.5))
					var w := xf * q
					inside = inside and cell.grow(0.1).has_point(Vector2(w.x, w.z))
			for bad: String in REAL_NAMES:
				invented = invented and not String(lp.name).contains(bad)
		one_theatre = one_theatre and theatres <= 1
	var kinds := counts.size()
	_t._check(total >= 10 and kinds >= 4, "Wilshire's midtown stretch is a run of deco buildings (%d buildings, %d kinds: %s)" % [total, kinds, counts])
	_t._check(only_midtown and on_boulevard, "deco only on midtown lots that front a boulevard")
	_t._check(one_theatre, "a theatre a block at most")
	_t._check(inside, "every deco massing box stands inside its lot's cell")
	_t._check(heights, "no deco building tops its lot's planned height by more than 10 m")
	_t._check(invented, "the deco names are invented (none of the real boulevard's buildings)")
	# Pure: the same answer from a cold cache.
	var before := []
	for k: Vector2i in stretch:
		for lp: Dictionary in DecoBoulevard.block_plans(plan, k.x, k.y).values():
			before.append("%d %s %s %.2f" % [int(lp.kind), lp.palette, lp.name, float(lp.h)])
	DecoBoulevard._cache.clear()
	var after := []
	for k: Vector2i in stretch:
		for lp: Dictionary in DecoBoulevard.block_plans(plan, k.x, k.y).values():
			after.append("%d %s %s %.2f" % [int(lp.kind), lp.palette, lp.name, float(lp.h)])
	_t._check(before == after and not before.is_empty(), "the deco plan is pure (the same %d buildings from a cold cache)" % before.size())
	# Off, no plan at all.
	DecoBoulevard.enabled = false
	var off := DecoBoulevard.block_plans(plan, stretch[0].x, stretch[0].y).size()
	DecoBoulevard.enabled = true
	_t._check(off == 0, "DecoBoulevard.enabled false plans nothing")


func _shader_checks() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/deco_ornament.gdshader")
	var ok := src.contains("kind == %d" % DecoBuild.GILT) and src.contains("kind == %d" % DecoBuild.WATER) \
		and src.contains("kind == %d" % DecoBuild.READER) and DecoBuild.GILT < 32
	_t._check(ok, "deco_ornament.gdshader draws every DecoBuild kind (0..%d)" % DecoBuild.GILT)
	# The kind survives the vertex colour's 8 bits, floodlit or not.
	var round_trip := true
	for k in DecoBuild.GILT + 1:
		for flood: bool in [false, true]:
			var a := DecoBuild.Orn.col(Color.WHITE, k, flood).a
			var q := float(roundi(a * 255.0)) / 255.0
			var back := int(floor(fmod(q * 64.0 + 0.5, 32.0)))
			round_trip = round_trip and back == k and (q * 64.0 + 0.5 >= 32.0) == flood
	_t._check(round_trip, "every ornament kind and its floodlight flag survive an 8-bit vertex colour")


func _deco_lots(plan: CityPlan, k: Vector2i) -> Array:
	return DecoBoulevard.block_plans(plan, k.x, k.y).values()


func _full_chunk(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var orn: MeshInstance3D = chunk.get_node_or_null("DecoOrnament")
	_t._check(orn != null and orn.material_override == DecoBuild.ornament_material(), "a deco chunk has its ornament mesh on deco_ornament.gdshader")
	var walls := 0
	var walls_ok := true
	for c in chunk.get_children():
		if c is MeshInstance3D and String(c.name).begins_with("DecoWalls_"):
			walls += 1
			var m := (c as MeshInstance3D).material_override as ShaderMaterial
			walls_ok = walls_ok and m != null and m.shader == Building.SHADER and bool(m.get_shader_parameter("part_attributes")) \
				and bool(m.get_shader_parameter("uv_facade"))
	_t._check(walls > 0 and walls_ok, "its windowed walls are building.gdshader in outline mode with the part numbers in the vertices (%d palettes)" % walls)
	var lots := _deco_lots(plan, k)
	var boxes := 0
	for lp: Dictionary in lots:
		boxes += (lp.boxes as Array).size()
	var body: StaticBody3D = chunk.get_node_or_null("DecoBody")
	_t._check(body != null and body.get_child_count() == boxes and body.collision_layer == 1 and body.collision_mask == 0,
		"every deco massing box has its collision on the world layer, mask 0 (%d)" % boxes)
	var on_deco := 0
	for c in chunk.get_children():
		if c is Building:
			var p := Vector2((c as Node3D).position.x, (c as Node3D).position.z)
			for lp: Dictionary in lots:
				if (lp.foot as Rect2).has_point(p):
					on_deco += 1
	_t._check(on_deco == 0, "no Building stands on a deco lot")
	var palms := 0
	for key: String in chunk._batch.data():
		if key.begins_with("palm_"):
			palms += (chunk._batch.data()[key].xforms as Array).size()
	var sig := _signature(chunk)
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	# Off: the same block, every other building and every parked car where it was.
	DecoBoulevard.enabled = false
	var bare: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	bare.build()
	var bare_palms := 0
	for key: String in bare._batch.data():
		if key.begins_with("palm_"):
			bare_palms += (bare._batch.data()[key].xforms as Array).size()
	var bare_sig := _signature(bare, lots)
	DecoBoulevard.enabled = true
	_t._check(sig == bare_sig and not sig.is_empty(), "the deco rolls nothing from the block: its parked cars and other buildings are unmoved (%d)" % sig.size())
	_t._check(palms > bare_palms, "mature palms line the deco frontage (%d palms, %d without)" % [palms, bare_palms])
	bare.get_parent().remove_child(bare)
	bare.free()


## Parked cars, and the Buildings standing off the deco lots (`lots`: the plans whose lots a
## Building stands on when the deco is off).
func _signature(chunk: CityChunk, lots: Array = []) -> Array:
	var out: Array = []
	for c in chunk.get_children():
		if c is Building:
			var p := (c as Node3D).position
			var deco := false
			for lp: Dictionary in lots:
				deco = deco or (lp.foot as Rect2).grow(1.0).has_point(Vector2(p.x, p.z))
			if not deco:
				out.append("B %.2f %.2f" % [p.x, p.z])
	for car in chunk.get("_cars"):
		if is_instance_valid(car):
			var p := (car as Node3D).global_position
			out.append("C %.2f %.2f" % [p.x, p.z])
	out.sort()
	return out


func _lod_chunk(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.LOD)
	chunk.build()
	var lots := _deco_lots(plan, k)
	var found := 0
	var want := 0
	var data: Dictionary = chunk._batch.data()
	var xforms: Array = data["lod_box"].xforms if data.has("lod_box") else []
	for lp: Dictionary in lots:
		var xf := DecoBoulevard.frame_xform(lp, CityChunk.SIDEWALK_TOP)
		for mb: Array in lp.boxes:
			want += 1
			var at := xf * (mb[0] as Vector3)
			for b: Transform3D in xforms:
				if Vector2(b.origin.x, b.origin.z).distance_to(Vector2(at.x, at.z)) < 0.05 and absf(b.basis.get_scale().y - (mb[1] as Vector3).y) < 0.05:
					found += 1
					break
	_t._check(want > 0 and found == want, "a LOD chunk draws every deco massing box as a far box (%d of %d)" % [found, want])
	chunk.get_parent().remove_child(chunk)
	chunk.free()
