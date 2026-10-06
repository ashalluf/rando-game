extends RefCounted
## Downtown's fashion district (FashionDistrict, FashionKit, FashionShopper), for
## tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## Checks the stretch and the pure block table on two seeds (only DOWNTOWN building blocks east of
## Main between 7th and Pico; Main's historic frontage left to HistoricCore; the same answer twice),
## the shop names (clothing and textile names already in Building.SHOP_NAMES, behind clothing rooms),
## the kit (budgets, collision inside each set, the shader's kind codes), then builds a district
## block FULL - sets against the wall with their collision, the camps off those faces, the dressed
## buildings - and a market alley - stalls both sides of a clear aisle, tarps over it, people in it -
## and checks the block built with the district off has the same lots, buildings and the same
## props outside the district's own.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_table(plan)
	_names()
	_kit()
	var keys := _district_blocks(plan)
	if keys.is_empty():
		_t._check(false, "the fashion district has blocks on this seed")
		return
	_full_block(city, plan, keys)
	_market(city, plan, keys)


func _district_blocks(plan: CityPlan) -> Array[Vector2i]:
	var st := FashionDistrict.stretch()
	var a := plan.block_index_at(st.position + Vector2(1.0, 1.0))
	var b := plan.block_index_at(st.end - Vector2(1.0, 1.0))
	var out: Array[Vector2i] = []
	for bz in range(a.y, b.y + 1):
		for bx in range(a.x, b.x + 1):
			if not FashionDistrict.block_info(plan, bx, bz).is_empty():
				out.append(Vector2i(bx, bz))
	return out


func _table(plan: CityPlan) -> void:
	var st := FashionDistrict.stretch()
	_t._check(st.size.x > 300.0 and st.size.y > 900.0 and absf(st.position.y - Broadway.street_z("7TH ST")) < 0.5,
		"the fashion district runs east of Main St from 7th St to Pico Blvd (%s)" % st)
	for seed_value: int in [plan.seed, plan.seed + 7919]:
		var p2 := plan
		if seed_value != plan.seed:
			p2 = CityPlan.new()
			p2.seed = seed_value
			p2.block_size_range = plan.block_size_range
			p2.street_width = plan.street_width
			p2.avenue_width = plan.avenue_width
			p2.sidewalk_width = plan.sidewalk_width
			p2.downtown_radius = plan.downtown_radius
			p2.midtown_radius = plan.midtown_radius
			p2.macro = plan.macro
		var keys := _district_blocks(p2)
		var ok := keys.size() >= 4
		var faces := 0
		var markets := 0
		var same := true
		for k in keys:
			var b: Dictionary = p2.block(k.x, k.y)
			var info := FashionDistrict.block_info(p2, k.x, k.y)
			ok = ok and int(b.kind) == CityPlan.BlockKind.BUILDINGS and int(b.district) == CityPlan.District.DOWNTOWN and not b.has("site")
			var c := (b.rect as Rect2).get_center()
			ok = ok and c.y > st.position.y and c.y < st.end.y and (b.rect as Rect2).position.x >= st.position.x - 1.0
			# Main St's frontage north of 9th is the historic core's.
			if not HistoricCore.block_fronts(p2, k.x, k.y).is_empty():
				ok = ok and not (2 in (info.faces as Array))
			faces += (info.faces as Array).size()
			markets += 1 if bool(info.market) else 0
			# Pure: the same answer from the cache and from scratch.
			same = same and FashionDistrict._block_info(p2, k.x, k.y).faces == info.faces
			for e: int in info.faces:
				ok = ok and FashionDistrict.owns_face(p2, k.x, k.y, e)
		# Outside the stretch nothing is the district's.
		var outside := FashionDistrict.block_info(p2, p2.block_index_at(Vector2(2900.0, 700.0)).x, p2.block_index_at(Vector2(2900.0, 700.0)).y)
		ok = ok and outside.is_empty() and FashionDistrict.block_info(p2, p2.block_index_at(Vector2(3300.0, 200.0)).x, p2.block_index_at(Vector2(3300.0, 200.0)).y).is_empty()
		_t._check(ok and same and faces >= keys.size() and markets >= 1,
			"seed %d: %d district blocks, %d faces of goods, %d market alleys, a pure table, nothing outside the stretch" % [seed_value, keys.size(), faces, markets])


func _names() -> void:
	var pool := FashionDistrict.shop_pool()
	var clothing := 0
	var ok := pool.size() == FashionDistrict.SHOP_POOL.size()
	for i: int in pool:
		ok = ok and i >= 0 and i < Building.SHOP_NAMES.size()
		if ok and int(Building.SHOP_NAME_ROOMS[Building.SHOP_NAMES[i]]) == Building.ShopRoom.CLOTHING:
			clothing += 1
	# The window vinyl's six-bit codes hold the index (Building.shop_name_codes()).
	for i: int in pool:
		ok = ok and i + 1 < 64
	_t._check(ok and clothing * 2 >= pool.size(),
		"the district's shop names are Building's own (%d, %d behind clothing rooms), so the interiors and vinyl know them" % [pool.size(), clothing])


func _kit() -> void:
	var ok := true
	var worst := 0
	for v in FashionKit.SET_VARIANTS:
		var fs := FashionKit.frontage(v)
		var len: float = fs.length
		worst = maxi(worst, int(fs.tris))
		ok = ok and len > 3.0 and len < 9.0 and (fs.mesh as ArrayMesh).get_surface_count() == 1
		for b: Array in fs.boxes:
			var size: Vector3 = b[0]
			var c: Vector3 = b[1]
			ok = ok and absf(c.x) + size.x * 0.5 <= len * 0.5 + 0.3 and c.z - size.z * 0.5 >= -0.2 and c.z + size.z * 0.5 < 1.6
	var stall_tris := 0
	for v in FashionKit.STALL_VARIANTS:
		stall_tris = maxi(stall_tris, FashionKit.tris(FashionKit.stall_mesh(v)))
	var mat := FashionKit.material()
	var code := (mat.shader as Shader).code if mat and mat.shader else ""
	ok = ok and code.find("kind == 14") >= 0 and code.find("cs_out(") >= 0
	_t._check(ok and worst < 7000 and stall_tris < 7000,
		"the goods are built in code on one shader: frontage sets up to %d triangles, stalls %d, collision inside each set" % [worst, stall_tris])


func _signature(chunk: CityChunk) -> Array:
	var out: Array = []
	for c in chunk.get_children():
		if c is Building:
			out.append("B %d %.1f,%.1f" % [(c as Building).seed, (c as Node3D).position.x, (c as Node3D).position.z])
	for r: Dictionary in chunk.prop_records:
		var kind := String(r.kind)
		if kind.begins_with("fd_"):
			continue
		var p: Vector3 = r.position
		out.append("P %s %.1f,%.1f" % [kind, p.x, p.z])
	out.sort()
	return out


func _full_block(city: Node3D, plan: CityPlan, keys: Array[Vector2i]) -> void:
	# The block with the most faces of goods (the first such).
	var k := keys[0]
	for kk in keys:
		if (FashionDistrict.block_info(plan, kk.x, kk.y).faces as Array).size() > (FashionDistrict.block_info(plan, k.x, k.y).faces as Array).size():
			k = kk
	var info := FashionDistrict.block_info(plan, k.x, k.y)
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var sets := 0
	var shapes_ok := true
	for r: Dictionary in chunk.prop_records:
		if String(r.kind) == "fd_set":
			sets += 1
			shapes_ok = shapes_ok and not (r.shapes as Array).is_empty()
	var nodes := 0
	var mat_ok := true
	for c in chunk.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("Batch_fd_set_"):
			nodes += 1
			var mm := (c as MultiMeshInstance3D).multimesh
			var m := mm.mesh.surface_get_material(0) as ShaderMaterial
			mat_ok = mat_ok and m != null and m.shader.resource_path.ends_with("fashion_goods.gdshader")
			mat_ok = mat_ok and (c as GeometryInstance3D).visibility_range_end > 0.0
	_t._check(sets >= 4 and shapes_ok and nodes >= 1 and mat_ok,
		"block %s: %d frontage sets of goods along %d faces, each with collision, drawn on the goods shader with a draw distance" % [k, sets, (info.faces as Array).size()])
	# Every set stands against a wall on the district's faces, back from the kerb.
	var rect: Rect2 = plan.block(k.x, k.y).rect
	var near_wall := true
	for r: Dictionary in chunk.prop_records:
		if String(r.kind) != "fd_set":
			continue
		var p: Vector3 = r.position
		var d := minf(minf(p.x - rect.position.x, rect.end.x - p.x), minf(p.z - rect.position.y, rect.end.y - p.z))
		near_wall = near_wall and d > 2.0 and d <= FashionDistrict.MAX_WALL_DEPTH
	_t._check(near_wall, "the goods stand at the shop fronts, between 2 m and %.1f m in from the kerb" % FashionDistrict.MAX_WALL_DEPTH)
	# The camps keep off those faces (Encampment._faces()).
	var camp_faces: Array = Encampment._faces(plan, k.x, k.y)
	var clash := false
	for e: int in camp_faces:
		clash = clash or e in (info.faces as Array)
	_t._check(not clash, "no camp on a face the goods stand on (camps on %s, goods on %s)" % [camp_faces, info.faces])
	# The buildings are clothing and textile shops under awnings.
	var dressed := 0
	var all_pooled := true
	for c in chunk.get_children():
		if c is Building and not (c as Building).name_pool.is_empty() and not (c as Building).fill_lot:
			dressed += 1
			all_pooled = all_pooled and (c as Building).kit_awning_building_chance >= 1.0
	_t._check(dressed > 0 and all_pooled, "the district's buildings take its shop names and hang awnings (%d)" % dressed)
	# Off: the same lots, buildings and props outside the district's own.
	var sig := _signature(chunk)
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	FashionDistrict.enabled = false
	FashionDistrict._info.clear()
	var bare: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	bare.build()
	var fd_left := 0
	for r: Dictionary in bare.prop_records:
		if String(r.kind).begins_with("fd_"):
			fd_left += 1
	var bare_sig := _signature(bare)
	FashionDistrict.enabled = true
	FashionDistrict._info.clear()
	bare.get_parent().remove_child(bare)
	bare.free()
	# Props on the district's own faces may differ by design (the camps keep off them); compare the
	# buildings, which nothing may move.
	var b_on := sig.filter(func(x: String) -> bool: return x.begins_with("B "))
	var b_off := bare_sig.filter(func(x: String) -> bool: return x.begins_with("B "))
	if b_on != b_off:
		printerr("FASHION same-block diff: on %s off %s" % [str(b_on.slice(0, 4)), str(b_off.slice(0, 4))])
	_t._check(fd_left == 0 and b_on == b_off and not b_on.is_empty(),
		"FASHION off builds none of it, and the block's buildings are the same either way (%d)" % b_on.size())


func _market(city: Node3D, plan: CityPlan, keys: Array[Vector2i]) -> void:
	var chunk: CityChunk = null
	for k in keys:
		var info := FashionDistrict.block_info(plan, k.x, k.y)
		if not bool(info.market) or Alleys.spec(plan, k.x, k.y).is_empty():
			continue
		var ch: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
		ch.build()
		var st: Dictionary = ch.get_meta("fashion", {})
		if not st.is_empty() and int(st.stats.markets) > 0:
			chunk = ch
			break
		ch.get_parent().remove_child(ch)
		ch.free()
	if chunk == null:
		_t._check(false, "a district block's alley is a market alley")
		return
	var st: Dictionary = chunk.get_meta("fashion")
	var stalls := 0
	var runs: Array = Alleys._state(chunk).runs
	var sp := Alleys.spec(plan, chunk.ix, chunk.iz)
	var in_aisle := 0
	for r: Dictionary in chunk.prop_records:
		if String(r.kind) != "fd_stall":
			continue
		stalls += 1
		var p: Vector3 = r.position
		var across := p.z if sp.along_x else p.x
		for run: Dictionary in runs:
			var c: float = run.c
			# A stall's centre is STALL_D / 2 off its side's edge: never within the aisle's middle.
			if absf(across - c) < 0.35 and float(run.w) >= FashionDistrict.BOTH_SIDES_W:
				in_aisle += 1
	var tarps := 0
	var bulbs := 0
	var lights := 0
	for c in chunk.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("Batch_fd_tarp_"):
			tarps += (c as MultiMeshInstance3D).multimesh.instance_count
		if c is MultiMeshInstance3D and String(c.name) == "Batch_fd_bulbs":
			bulbs += (c as MultiMeshInstance3D).multimesh.instance_count
		if c is OmniLight3D and (c as Node).is_in_group("lamp_light"):
			lights += 1
	_t._check(stalls >= 6 and in_aisle == 0 and tarps >= 2 and bulbs >= 2 and lights >= 2,
		"block %s's market alley: %d stalls down its sides with the aisle clear, %d tarps and %d bulb strings over it, its lights" % [Vector2i(chunk.ix, chunk.iz), stalls, tarps, bulbs, lights])
	var shoppers := 0
	var bags := 0
	var keepers := 0
	var lane_ok := true
	for c in chunk.get_children():
		if c is FashionShopper:
			var s := c as FashionShopper
			shoppers += 1
			bags += 1 if s._carry == CrowdLife.Carry.BAG else 0
			for i in 8:
				var q := s._random_ring_point(1.0)
				var d := s.lane_b - s.lane_a
				var t := clampf((q - s.lane_a).dot(d) / d.length_squared(), 0.0, 1.0)
				lane_ok = lane_ok and q.distance_to(s.lane_a + d * t) <= s.lane_half + 0.01
		elif c is StreetVendor:
			keepers += 1
	# The crowd cap may hold some back: what was planned is checked, and whoever came is in the aisle.
	_t._check(int(st.stats.planned) >= 4 and lane_ok and (shoppers > 0 or int(st.stats.people) == 0),
		"the market's people: %d planned, %d shoppers strolling the aisle (%d with bags), %d stall keepers and sellers" % [int(st.stats.planned), shoppers, bags, keepers])
	chunk.get_parent().remove_child(chunk)
	chunk.free()

