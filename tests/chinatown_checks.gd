extends RefCounted
## Chinatown (Chinatown, ChinatownKit, ChinatownGeo), for tests/smoke_test.gd. Loaded at run time,
## not named there, so it compiles after the autoloads.
##
## Checks the table (every name invented, the shop and goods tables aligned), where it lands on two
## seeds (district blocks north of Cesar Chavez between the pinned avenues, the plaza on the Hill -
## Broadway block, the gate over Broadway clear of the junctions, nothing claimed that another
## feature owns, blocks outside the district untouched), the lot claims (street-facing, each lot's
## frame facing its street, pure plans), then builds the plaza's block, a district block and the
## gate's block FULL and LOD: one mesh on chinatown.gdshader, collision, light pools, the LOD and
## far boxes, nothing of it at LOD but boxes; and built with Chinatown off the block is its old self.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_table()
	_placement(plan)
	_claims(plan)
	_shader()
	_builds(city, plan)


func _table() -> void:
	_t._check(Chinatown.SHOP_NAMES.size() == Chinatown.SHOP_GOODS.size(),
		"Chinatown: every shop name has its goods (%d)" % Chinatown.SHOP_NAMES.size())
	var real := ["PHOENIX", "WING HOP", "TEN REN", "HOP LOUIE", "GOLDEN DRAGON", "FAR EAST", "CATHAY", "EMPRESS PAVILION",
		"PEARL RIVER", "THIEN HAU", "KIM CHUY", "YANG CHOW", "HOP SING", "PHILIPPE", "GIN LING", "MEI LING", "CENTRAL PLAZA", "DRAGON GATE"]
	var all: Array = Chinatown.SHOP_NAMES.duplicate()
	all.append_array([Chinatown.GATE_NAME, Chinatown.PLAZA_NAME, Chinatown.HALL_NAME])
	var clean := true
	for n: String in all:
		for r: String in real:
			clean = clean and n.find(r) < 0
	_t._check(clean, "Chinatown: no real business's or landmark's name anywhere (%d names)" % all.size())


func _placement(plan: CityPlan) -> void:
	for seed_value: int in [plan.seed, plan.seed + 7919]:
		var p2 := plan
		if seed_value != plan.seed:
			p2 = CityPlan.new()
			p2.seed = seed_value
			p2.macro = plan.macro
		var ext := Chinatown.extent()
		var a := p2.block_index_at(ext.position)
		var b := p2.block_index_at(ext.end)
		var n := 0
		var ok := true
		for iz in range(a.y - 1, b.y + 2):
			for ix in range(a.x - 1, b.x + 2):
				var bl := p2.block(ix, iz)
				var role := Chinatown.block_role(p2, ix, iz)
				if role == "":
					continue
				n += 1
				var c := (bl.rect as Rect2).get_center()
				ok = ok and ext.has_point(c) and c.y < Chinatown.south_z()
				ok = ok and not bl.has("site") and not bl.has("grounds") and bl.kind != CityPlan.BlockKind.SCHOOL
				ok = ok and (role == "plaza") == (bl.kind == CityPlan.BlockKind.PLAZA)
		var pb := Chinatown.plaza_block(p2)
		var plaza_ok := pb.x > -9999 and Chinatown.block_role(p2, pb.x, pb.y) == "plaza"
		if plaza_ok:
			var r: Rect2 = p2.block(pb.x, pb.y).rect
			plaza_ok = absf(r.position.x - (Chinatown.avenue_x("HILL ST") + p2.road_width(CityPlan.AXIS_X, pb.x) * 0.5)) < 0.1
		var g := Chinatown.gate(p2)
		var gate_ok := not g.is_empty() and absf(float(g.x) - Chinatown.avenue_x("BROADWAY")) < 0.01
		if gate_ok:
			var br: Rect2 = p2.block((g.block as Vector2i).x, (g.block as Vector2i).y).rect
			gate_ok = float(g.z) > br.position.y + 11.0 and float(g.z) < br.end.y - 11.0 and float(g.z) < Chinatown.south_z()
		_t._check(ok and n >= 6 and plaza_ok and gate_ok,
			"Chinatown on seed %d: %d district blocks north of Cesar Chavez, none another feature's; the plaza on the Hill - Broadway block %s; the gate over Broadway at z %.0f clear of the junctions" % [
				seed_value, n, str(pb), float(g.get("z", NAN))])
	# A block outside the district is what it always was.
	var outside := plan.block_index_at(Vector2(Chinatown.avenue_x("BROADWAY") + 20.0, Chinatown.south_z() + 200.0))
	var before := plan.block(outside.x, outside.y)
	Chinatown.enabled = false
	var bare := CityPlan.new()
	bare.seed = plan.seed
	bare.macro = plan.macro
	var b2 := bare.block(outside.x, outside.y)
	var in_d := bare.block(Chinatown.plaza_block(plan).x, Chinatown.plaza_block(plan).y)
	Chinatown.enabled = true
	_t._check(before.kind == b2.kind and int(before.seed) == int(b2.seed) and not before.has("chinatown")
		and int(in_d.seed) == int(plan.block(Chinatown.plaza_block(plan).x, Chinatown.plaza_block(plan).y).seed),
		"Chinatown moves no roll: the block south of Cesar Chavez is unchanged, the plaza's block keeps its seed")


func _claims(plan: CityPlan) -> void:
	var ext := Chinatown.extent()
	var a := plan.block_index_at(ext.position)
	var b := plan.block_index_at(ext.end)
	var claimed := 0
	var facing_ok := true
	var pure := true
	for iz in range(a.y, b.y + 1):
		for ix in range(a.x, b.x + 1):
			if Chinatown.block_role(plan, ix, iz) != "block":
				continue
			var rect: Rect2 = plan.block(ix, iz).rect
			for lot: Dictionary in plan.lots(ix, iz):
				if not Chinatown.claims(plan, ix, iz, lot):
					continue
				claimed += 1
				var out2 := Chinatown.lot_front(plan, ix, iz, lot)
				# The front is the lot's side nearest the block's edge in that direction.
				var c: Vector2 = lot.center
				var to_edge := (rect.end.x - c.x) if out2.x > 0.0 else (c.x - rect.position.x) if out2.x < 0.0 else (rect.end.y - c.y) if out2.y > 0.0 else (c.y - rect.position.y)
				var span := (lot.size as Vector2).x * 0.5 if out2.x != 0.0 else (lot.size as Vector2).y * 0.5
				facing_ok = facing_ok and to_edge - span < plan.sidewalk_width + 4.5
				var u1 := ChinatownKit.plan_units(plan.seed, int(lot.seed), 20.0)
				var u2 := ChinatownKit.plan_units(plan.seed, int(lot.seed), 20.0)
				pure = pure and str(u1) == str(u2) and float(u1[0].x0) == -10.0 and float(u1[u1.size() - 1].x1) == 10.0
	_t._check(claimed >= 20 and facing_ok and pure,
		"Chinatown's shop buildings take %d street-facing lots, each facing its street; their units are pure and fill the frontage" % claimed)


func _shader() -> void:
	var sh: Shader = load("res://shaders/chinatown.gdshader")
	var m := ChinatownKit.material()
	_t._check(sh != null and m.shader == sh and sh.get_shader_uniform_list().size() >= 5,
		"chinatown.gdshader compiles and is the district's material")


func _builds(city: Node3D, plan: CityPlan) -> void:
	var pb := Chinatown.plaza_block(plan)
	var gate := Chinatown.gate(plan)
	var gk: Vector2i = gate.get("block", Vector2i(-99999, 0))
	# The plaza.
	var r := _build(city, pb, CityChunk.Level.FULL)
	_t._check(r.mesh_ok and r.shapes >= 30 and r.tris > 20000 and r.tris < 260000 and r.pools > 0,
		"the plaza builds FULL: one mesh on chinatown.gdshader (%d triangles), %d collision boxes, %d light pools" % [r.tris, r.shapes, r.pools])
	var rl := _build(city, pb, CityChunk.Level.LOD)
	_t._check(not rl.mesh_ok and rl.lod_boxes >= 10,
		"the plaza at LOD is boxes (%d), no mesh of its own" % rl.lod_boxes)
	# The gate's block.
	var g := _build(city, gk, CityChunk.Level.FULL)
	_t._check(g.mesh_ok and g.buildings > 0 and g.pools > 0 and g.shapes >= 3,
		"the gate's block builds FULL: shop buildings (%d), the gate's columns, lantern pools (%d)" % [g.buildings, g.pools])
	var gl := _build(city, gk, CityChunk.Level.LOD)
	_t._check(not gl.mesh_ok and gl.lod_boxes > g.buildings,
		"the gate's block at LOD: the buildings' and the gate's boxes (%d)" % gl.lod_boxes)
	# Off: the gate's block is its old self (ordinary buildings, no Chinatown node).
	Chinatown.enabled = false
	var bare_plan := CityPlan.new()
	for prop in ["seed", "block_size_range", "street_width", "avenue_width", "sidewalk_width", "downtown_radius", "midtown_radius", "macro"]:
		bare_plan.set(prop, plan.get(prop))
	var saved: CityPlan = city.plan
	city.plan = bare_plan
	var off := _build(city, gk, CityChunk.Level.FULL)
	city.plan = saved
	Chinatown.enabled = true
	_t._check(not off.mesh_ok and off.buildings > 0, "with Chinatown off the gate's block builds as ordinary buildings (%d)" % off.buildings)


func _build(city: Node3D, k: Vector2i, level: CityChunk.Level) -> Dictionary:
	var out := {"mesh_ok": false, "shapes": 0, "tris": 0, "pools": 0, "lod_boxes": 0, "buildings": 0}
	if k.x < -9000:
		return out
	var tris0 := LandmarkGeo.committed_triangles
	var chunk: CityChunk = city._new_chunk(k, level)
	chunk.build()
	out.tris = LandmarkGeo.committed_triangles - tris0
	out.buildings = chunk.building_count
	var node := chunk.get_node_or_null("Chinatown")
	if node:
		var mi := node.get_node_or_null("ChinatownMesh") as MeshInstance3D
		if mi and mi.mesh and mi.mesh.get_surface_count() == 1:
			var m := mi.mesh.surface_get_material(0) as ShaderMaterial
			out.mesh_ok = m != null and m.shader != null and m.shader.resource_path.ends_with("chinatown.gdshader")
		var body := node.get_node_or_null("ChinatownBody")
		if body:
			out.shapes = body.get_child_count()
	var pools := chunk.get_node_or_null("Batch_ct_pool") as MultiMeshInstance3D
	if pools:
		out.pools = pools.multimesh.instance_count
	var lod := chunk.get_node_or_null("Batch_lod_box") as MultiMeshInstance3D
	if lod:
		out.lod_boxes = lod.multimesh.instance_count
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	return out
