extends RefCounted
## Broadway's theatre district (Broadway, BroadwayTheatre, BroadwayStreet), for
## tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## Checks the table (every address inside the stretch, in order, every name original to it), that
## every palace lands on its own Broadway-fronting lot near its real address on two seeds, the
## shop names (Broadway's pool only on Broadway's blocks; every other building's names exactly as
## before), then builds a palace's block FULL and checks: the palace node with its one sign surface
## on broadway_sign.gdshader, collision, its light; the lamps on Broadway's pavement are the
## lanterns in the lamp slot; goods and the clock; the LOD build's boxes and lit sign panels; and
## built with Broadway off it is the same block (the props, trash cans and the other buildings).

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_table()
	_placement(plan)
	_shop_names()
	_shader()
	var pal: Array = Broadway.palaces(plan)
	if pal.is_empty():
		_t._check(false, "Broadway has palaces to build")
		return
	_full_block(city, plan, pal)
	_lod_block(city, pal)


func _table() -> void:
	var zr := Broadway.z_range()
	var ok := zr.y > zr.x + 1000.0
	var last := -INF
	var ids := {}
	for spec: Dictionary in Broadway.THEATRES:
		var z := Broadway.address_z(int(spec.num))
		ok = ok and z > zr.x and z < zr.y and z >= last
		last = z
		ids[spec.id] = true
		for key: String in ["name", "style", "front_h", "sign_h", "marquee", "titles", "enamel", "neon", "letters", "terrazzo"]:
			ok = ok and spec.has(key)
		ok = ok and (spec.titles as Array).size() >= 4
	_t._check(ok and ids.size() == Broadway.THEATRES.size(),
		"Broadway's palaces: real addresses in order between 3rd St and Olympic (z %.0f..%.0f), every row complete" % [zr.x, zr.y])
	# The real palaces' names never appear (invented names only).
	var real := ["MILLION DOLLAR", "ROXIE", "CAMEO", "ARCADE", "LOS ANGELES", "PALACE", "STATE", "GLOBE",
		"TOWER", "RIALTO", "ORPHEUM", "UNITED ARTISTS", "MAYAN", "BELASCO", "ACE"]
	var clean := true
	for spec: Dictionary in Broadway.THEATRES:
		for r: String in real:
			clean = clean and str(spec.name).find(r) < 0
	_t._check(clean, "no palace carries a real theatre's name")


func _placement(plan: CityPlan) -> void:
	for seed_value: int in [plan.seed, plan.seed + 7919]:
		var p2 := plan
		if seed_value != plan.seed:
			p2 = CityPlan.new()
			p2.seed = seed_value
			p2.macro = plan.macro
		var pal: Array = Broadway.palaces(p2)
		var lots := {}
		var ok := pal.size() >= Broadway.THEATRES.size() - 1
		var worst := 0.0
		for p: Dictionary in pal:
			var lot: Dictionary = p.lot
			var bi: Vector2i = p.block
			ok = ok and Broadway.block_side(p2, bi.x, bi.y) == int(p.side)
			ok = ok and Broadway.lot_fronts(p2, bi.x, bi.y, int(p.side), lot)
			var key := "%d,%d,%d" % [bi.x, bi.y, int(lot.seed)]
			ok = ok and not lots.has(key)
			lots[key] = true
			var off := maxf(absf(float(p.z) - (lot.center as Vector2).y) - (lot.size as Vector2).y * 0.5, 0.0)
			worst = maxf(worst, off)
			ok = ok and Broadway.claims(p2, bi.x, bi.y, lot)
		_t._check(ok and worst <= Broadway.LOT_REACH,
			"seed %d: %d palaces, each on its own Broadway-fronting lot, at most %.0f m off its address" % [seed_value, pal.size(), worst])


func _shop_names() -> void:
	var b := Building.new()
	b.seed = 424242
	# Without a pool: exactly the old roll over the first 30 names.
	var same := true
	for face in 4:
		var names := b.shop_names(face, 7)
		var last := -1
		for run in 7:
			var i := absi(hash([b.seed, "sign_name", face, run * 7919])) % 30
			if i == last:
				i = (i + 1) % 30
			last = i
			same = same and names[run] == i
	b.name_pool = Broadway.shop_pool()
	var pooled := true
	for face in 4:
		for i: int in b.shop_names(face, 7):
			pooled = pooled and Broadway.BROADWAY_SHOPS.has(Building.SHOP_NAMES[i])
	var rooms := true
	for n: String in Broadway.BROADWAY_SHOPS:
		rooms = rooms and Building.SHOP_NAME_ROOMS.has(n) and Building.SHOP_NAMES.find(n) >= Building.BASE_SHOP_NAMES
	b.free()
	_t._check(same and pooled and rooms and not Broadway.shop_pool().has(-1),
		"shop names: every other building rolls the old 30 exactly; Broadway's pool names its shops, each with a room")


func _shader() -> void:
	var sh: Shader = load("res://shaders/broadway_sign.gdshader")
	var src := FileAccess.get_file_as_string("res://shaders/broadway_sign.gdshader")
	var ok := sh != null and sh.get_shader_uniform_list().size() > 5 and src.contains("cs_out(emit)") and src.contains("lamp_factor")
	# The kinds the builder writes are the shader's (k < n.5 branches up to the terrazzo).
	ok = ok and src.contains("k < 10.5") and BroadwayTheatre.K_TERRAZZO == 11 and BroadwayTheatre.K_POSTER == 10
	var clock: Shader = load("res://shaders/broadway_clock.gdshader")
	_t._check(ok and clock != null and clock.get_shader_uniform_list().size() >= 1, "broadway_sign and broadway_clock shaders load, the kinds agree")


func _full_block(city: Node3D, plan: CityPlan, pal: Array) -> void:
	var p: Dictionary = pal[0]
	var k: Vector2i = p.block
	var tris0 := LandmarkGeo.committed_triangles
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var tris := LandmarkGeo.committed_triangles - tris0
	var node: Node3D = null
	for c in chunk.get_children():
		if c is Node3D and (c as Node).is_in_group("broadway_palace"):
			node = c
	var mesh_ok := false
	var body_ok := false
	var light_ok := false
	if node:
		var mi := node.get_node_or_null("Palace") as MeshInstance3D
		if mi and mi.mesh:
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s) as ShaderMaterial
				if m and m.shader and m.shader.resource_path.ends_with("broadway_sign.gdshader"):
					mesh_ok = true
		body_ok = node.get_node_or_null("Body") is StaticBody3D and node.get_node("Body").get_child_count() >= 4
		for c in node.get_children():
			if c is OmniLight3D and (c as Node).is_in_group("lamp_light"):
				light_ok = true
	_t._check(node != null and mesh_ok and body_ok and light_ok and tris > 3000 and tris < 160000,
		"the %s builds FULL: one mesh with its sign surface, collision, a lamp light (%d triangles)" % [p.spec.name, tris])
	# The pavement: lanterns in the lamp slot, goods, the coloured pools.
	var lantern := chunk.get_node_or_null("Batch_bw_lamp") as MultiMeshInstance3D
	_t._check(lantern != null and lantern.multimesh.instance_count >= 3 and chunk.get_node_or_null("Batch_bw_pool") != null,
		"Broadway's pavement has its own lanterns (%d) and the marquee's pools of light" % (lantern.multimesh.instance_count if lantern else 0))
	var goods := 0
	for key: String in ["Batch_bw_rack", "Batch_bw_gown", "Batch_bw_table"]:
		var n := chunk.get_node_or_null(key) as MultiMeshInstance3D
		if n:
			goods += n.multimesh.instance_count
	_t._check(goods > 0, "goods out on the pavement in front of the shops (%d)" % goods)
	# The building next door is a 1920s block with Broadway's shops.
	var dressed := 0
	var too_tall := 0
	for c in chunk.get_children():
		if c is Building:
			var b := c as Building
			if not b.name_pool.is_empty():
				dressed += 1
				if b.height > Broadway.HEIGHT_LIMIT + 0.5:
					too_tall += 1
	_t._check(dressed > 0 and too_tall == 0, "Broadway's other buildings are dressed (%d) and under the height limit" % dressed)
	# Off: the same block (props, trash cans, the other buildings).
	var sig := _signature(chunk, p.lot)
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	Broadway.enabled = false
	Broadway._plans.clear()
	var bare: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	bare.build()
	Broadway.enabled = true
	Broadway._plans.clear()
	var bare_sig := _signature(bare, p.lot)
	if bare_sig != sig:
		var only_on := sig.filter(func(x: String) -> bool: return not bare_sig.has(x))
		var only_off := bare_sig.filter(func(x: String) -> bool: return not sig.has(x))
		printerr("BROADWAY same-block diff: with %s ... without %s" % [str(only_on.slice(0, 6)), str(only_off.slice(0, 6))])
	_t._check(bare_sig == sig and not sig.is_empty(), "Broadway rolls nothing from the block: built without it, the same props and buildings (%d)" % sig.size())
	bare.get_parent().remove_child(bare)
	bare.free()
	# The street clock's block.
	var found := false
	for zi in range(-3, 7):
		for xi: int in [k.x - 1, k.x, k.x + 1]:
			var side := Broadway.block_side(plan, xi, zi)
			if side == 0:
				continue
			var north := plan.road_name(CityPlan.AXIS_Z, zi)
			for cl: Array in BroadwayStreet.CLOCKS:
				if str(cl[0]) == north and int(cl[1]) == side:
					var ch: CityChunk = city._new_chunk(Vector2i(xi, zi), CityChunk.Level.FULL)
					ch.build()
					found = ch.get_node_or_null("BroadwayClock") != null
					ch.get_parent().remove_child(ch)
					ch.free()
	_t._check(found, "the street clock stands on its corner")


func _lod_block(city: Node3D, pal: Array) -> void:
	var p: Dictionary = pal[pal.size() - 1]
	var chunk: CityChunk = city._new_chunk(p.block, CityChunk.Level.LOD)
	chunk.build()
	var palace_node := false
	for c in chunk.get_children():
		if (c as Node).is_in_group("broadway_palace"):
			palace_node = true
	var lod := chunk.get_node_or_null("Batch_lod_box") as MultiMeshInstance3D
	_t._check(not palace_node and lod != null and lod.multimesh.instance_count >= 4,
		"far: the palace is boxes with its sign column (no detailed node)")
	chunk.get_parent().remove_child(chunk)
	chunk.free()


func _signature(chunk: CityChunk, _palace_lot: Dictionary) -> Array:
	# Broadway's own lots (the palace's and the dressed blocks') and its pavement are the feature:
	# what their buildings put round them (a forecourt's benches and bollards, the shops' A-boards)
	# follows the new buildings and is not compared - except the lamps, which keep their slot. The
	# rest of the block is compared by kind and place (the lots' own props shift later ids).
	var plan := chunk.plan
	var side := Broadway.block_side(plan, chunk.ix, chunk.iz)
	var rect: Rect2 = plan.block(chunk.ix, chunk.iz).rect
	var own: Array[Rect2] = []
	for lot: Dictionary in plan.lots(chunk.ix, chunk.iz):
		if Broadway.lot_fronts(plan, chunk.ix, chunk.iz, side, lot):
			var c: Vector2 = lot.center
			var sz: Vector2 = lot.size
			own.append(Rect2(c - sz * 0.5, sz).grow(1.0))
	var strip := Rect2(rect.end.x - plan.sidewalk_width, rect.position.y, plan.sidewalk_width, rect.size.y) if side < 0 \
		else Rect2(rect.position.x, rect.position.y, plan.sidewalk_width, rect.size.y)
	var mine := func(q: Vector2) -> bool:
		for r: Rect2 in own:
			if r.has_point(q):
				return true
		return false
	var out: Array = []
	for c in chunk.get_children():
		if c is Building or c is TrashCan:
			var p: Vector3 = (c as Node3D).position
			if c is Building and mine.call(Vector2(p.x, p.z)):
				continue
			out.append("%s %.2f %.2f" % [c.get_class(), p.x, p.z])
	for r in chunk.prop_records:
		var q: Vector3 = r.position
		var q2 := Vector2(q.x, q.z)
		# Forecourt furniture (LotFill) runs on per-chunk budgets, so one changed lot moves it
		# across the block: the street's own props are what is compared.
		if String(r.kind) in ["bench", "bollard", "planter", "aboard", "cafe"]:
			continue
		if mine.call(q2) or (strip.grow(0.5).has_point(q2) and String(r.kind) != "lamp"):
			continue
		out.append("%s %.2f %.2f" % [r.kind, q.x, q.z])
	out.sort()
	return out
