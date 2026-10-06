extends RefCounted
## Backyard life (Backyards, BackyardKit) for tests/smoke_test.gd. Loaded at run time (not named
## there), so it compiles after the autoloads. Checks: every kit mesh builds inside its triangle
## budget; the plan is pure (twice the same) and keeps every piece inside its back yard, clear of
## the house, of each other, and the floats on the water; a suburb block furnishes most of its
## yards; a FULL chunk draws a batch per kind, the string lights as one mesh and the grills,
## tables, trampolines and doghouses as breakable props, and with the system off everything else
## in the chunk is the same (batches, prop ids); a LOD chunk keeps only what reads from the air;
## the far city's capture records none of it.

var _t: Node

## Where to look for a furnished house block (the suburb bookmark), and the block found there.
const NEAR := Vector2(1911, 4260)
var BLOCK := Vector2i.ZERO

## Triangle budgets per kit mesh.
const BUDGET := {"dining_metal": 7000, "dining_teak": 3000, "umbrella": 3000, "umbrella_lod": 40, "loungers": 3000,
	"grill_gas": 2500, "grill_kettle": 2500, "smoke": 40, "trampoline": 9000, "trampoline_lod": 200, "float_ring": 900,
	"float_mat": 1600, "float_ball": 400, "laundry": 3500, "citrus": 3500, "citrus_leaves": 2000, "doghouse": 1200,
	"dog_run": 1500, "toys": 2000, "post": 40}


func run(t: Node, city: Node3D) -> void:
	_t = t
	var t0 := Time.get_ticks_msec()
	_meshes()
	var plan: CityPlan = city.plan
	BLOCK = _busiest(plan)
	_plan(plan)
	_full(city)
	_lod(city)
	_capture(city)
	print("BACKYARDS_CHECKS %d ms" % (Time.get_ticks_msec() - t0))


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _meshes() -> void:
	var over: Array = []
	for k: String in BUDGET:
		var m: Mesh = BackyardKit.get_mesh(k)
		var tris := 0
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			tris += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		if tris > int(BUDGET[k]) or tris < 2:
			over.append("%s %d" % [k, tris])
	_check(over.is_empty(), "backyards: every kit mesh builds inside its triangle budget %s" % str(over))
	var mats: Array = BackyardKit.warm()
	var ok := true
	for m: ShaderMaterial in mats:
		ok = ok and m.shader != null and m.shader.get_shader_uniform_list().size() > 0
	_check(ok and mats.size() == 5, "backyards: the props', floats', net, chain-link and smoke materials load")


static func _block_plans(plan: CityPlan, bx: int, bz: int) -> Dictionary:
	var b: Dictionary = plan.block(bx, bz)
	var d := int(b.district)
	var lots: Array = plan.lots(bx, bz)
	if HouseKit.enabled:
		lots.append_array(HouseKit.extra_lots(plan, bx, bz))
	var entries: Array = []
	for lot: Dictionary in lots:
		if lot.yard or YardFill.is_corridor(plan, lot):
			continue
		entries.append(HouseKit.yard_entry(lot, HouseKit.plan_house(plan, bx, bz, lot, d)))
	return {"bp": YardFill.beach_block(plan, bx, bz, entries), "district": d}


## The house block round NEAR whose yards get the most pieces (a few blocks each way).
func _busiest(plan: CityPlan) -> Vector2i:
	var c: Vector2i = plan.block_index_at(NEAR)
	var best := c
	var most := -1
	for bx in range(c.x - 3, c.x + 4):
		for bz in range(c.y - 3, c.y + 4):
			var b: Dictionary = plan.block(bx, bz)
			var d := int(b.district)
			if not (d == CityPlan.District.SUBURBS or d == CityPlan.District.BEACHTOWN) or int(b.kind) != CityPlan.BlockKind.BUILDINGS \
					or b.has("site") or plan.zone_at((b.rect as Rect2).get_center()) != MacroMap.Zone.CITY or plan.marina_block(bx, bz):
				continue
			var bd := _block_plans(plan, bx, bz)
			var n := 0
			for lp: Dictionary in bd.bp.lots:
				n += Backyards.plan_lot(plan, lp, d).size()
			if n > most:
				most = n
				best = Vector2i(bx, bz)
	print("BACKYARDS check block %s (%d pieces), seed %d" % [str(best), most, plan.seed])
	return best


func _plan(plan: CityPlan) -> void:
	var bd := _block_plans(plan, BLOCK.x, BLOCK.y)
	var d: int = bd.district
	_check(d == CityPlan.District.SUBURBS or d == CityPlan.District.BEACHTOWN, "backyards: the check block is a house block (%d)" % d)
	var lots: Array = bd.bp.lots
	var furnished := 0
	var items := 0
	var kinds := {}
	var same := true
	var bad: Array = []
	for lp: Dictionary in lots:
		var a: Array = Backyards.plan_lot(plan, lp, d)
		var b: Array = Backyards.plan_lot(plan, lp, d)
		same = same and str(a) == str(b)
		if not a.is_empty():
			furnished += 1
		var f: Dictionary = lp.frame
		var U: float = f.U
		var V: float = f.V
		var house: Array[Rect2] = []
		for r: Rect2 in lp.parts:
			house.append(YardFill._to_frame(f, r))
		var pool := Rect2()
		for pc: Array in lp.pieces:
			if String(pc[3]) == "pool":
				pool = YardFill._to_frame(f, pc[0])
		var mine: Array[Rect2] = []
		for it: Dictionary in a:
			items += 1
			var k := String(it.kind)
			kinds[k] = int(kinds.get(k, 0)) + 1
			if k == "lights":
				continue
			var at: Vector2 = it.at
			if k.begins_with("float"):
				if not pool.has_point(at):
					bad.append("float off the water")
				continue
			var r := Rect2(at - (it.size as Vector2) * 0.5, it.size)
			if r.position.x < 0.0 or r.end.x > U or r.end.y > V or r.position.y < float(lp.back):
				bad.append("%s outside the back yard" % k)
			for h: Rect2 in house:
				if r.intersects(h):
					bad.append("%s on the house" % k)
			if pool.size.x > 0.0 and r.intersects(pool):
				bad.append("%s in the pool" % k)
			for o: Rect2 in mine:
				if r.intersects(o):
					bad.append("%s on another" % k)
			mine.append(r)
	_check(same, "backyards: the plan is pure (planned twice, the same)")
	_check(bad.is_empty(), "backyards: every piece stands in its back yard, off the house, the pool and each other %s" % str(bad.slice(0, 6)))
	_check(lots.size() > 6 and furnished * 2 >= lots.size() and kinds.size() >= 8,
		"backyards: %d of %d yards furnished, %d pieces of %d kinds" % [furnished, lots.size(), items, kinds.size()])


func _children(chunk: Node) -> Dictionary:
	var out := {}
	for c in chunk.get_children():
		out[String(c.name)] = c
	return out


func _full(city: Node3D) -> void:
	var was := Backyards.enabled
	Backyards.enabled = false
	var off: CityChunk = city._new_chunk(BLOCK, CityChunk.Level.FULL)
	off.build()
	var off_props := {}
	for r: Dictionary in off.prop_records:
		off_props[String(r.id)] = true
	var off_batches := {}
	for c in off.get_children():
		if c is MultiMeshInstance3D:
			off_batches[String(c.name)] = (c as MultiMeshInstance3D).multimesh.instance_count
	off.get_parent().remove_child(off)
	off.free()
	Backyards.enabled = true
	var on: CityChunk = city._new_chunk(BLOCK, CityChunk.Level.FULL)
	on.build()
	Backyards.enabled = was
	var names := _children(on)
	var kinds := 0
	var moved: Array = []
	for n: String in names:
		var c: Node = names[n]
		if not (c is MultiMeshInstance3D):
			continue
		if n.begins_with("Batch_by_"):
			kinds += 1
		elif not n.begins_with("BatchShadow_by_"):
			var cnt := (c as MultiMeshInstance3D).multimesh.instance_count
			if int(off_batches.get(n, -1)) != cnt:
				moved.append("%s %d->%d" % [n, int(off_batches.get(n, -1)), cnt])
	var lights: MeshInstance3D = names.get("BackyardLights")
	var bulbs := 0
	if lights:
		var arr := lights.mesh.surface_get_arrays(0)
		var cu: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM0]
		for i in range(3, cu.size(), 4):
			if cu[i] > 0.5:
				bulbs += 1
	var counts: Dictionary = on.get_meta("backyards", {})
	_check(kinds >= 8, "backyards: a FULL suburb chunk draws a batch per kind (%d kinds: %s)" % [kinds, str(counts)])
	_check(lights == null and not counts.has("lights") or (lights != null and bulbs > 50 and lights.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF),
		"backyards: the chunk's string lights are one shadowless mesh (%d bulb vertices)" % bulbs)
	var by_props := 0
	var kept := true
	for r: Dictionary in on.prop_records:
		var k := String(r.kind)
		if k in ["patio", "grill", "trampoline", "doghouse"]:
			by_props += 1
		elif not off_props.has(String(r.id)):
			kept = false
	_check(by_props >= 10, "backyards: tables, grills, trampolines and doghouses are breakable props (%d)" % by_props)
	_check(kept and moved.is_empty(), "backyards: with them off the chunk's other props keep their ids and its batches their counts %s" % str(moved.slice(0, 6)))
	on.get_parent().remove_child(on)
	on.free()


func _lod(city: Node3D) -> void:
	var lod: CityChunk = city._new_chunk(BLOCK, CityChunk.Level.LOD)
	lod.build()
	var names := _children(lod)
	var full_kinds := 0
	for n: String in names:
		if n.begins_with("Batch_by_") and not (n in ["Batch_by_umbrella_lod", "Batch_by_trampoline_lod", "Batch_by_glow"]):
			full_kinds += 1
	_check(full_kinds == 0 and (names.has("Batch_by_umbrella_lod") or names.has("Batch_by_trampoline_lod")) and not names.has("BackyardLights"),
		"backyards: a LOD chunk keeps only the umbrellas, the trampolines and the lights' glow")
	lod.get_parent().remove_child(lod)
	lod.free()


func _capture(city: Node3D) -> void:
	var cap := CityChunk.new()
	cap.plan = city.plan
	cap.ix = BLOCK.x
	cap.iz = BLOCK.y
	cap.level = CityChunk.Level.LOD
	cap.style = city.chunk_style()
	cap.capturing = true
	cap.build()
	var any := false
	for k: String in (cap.captured.get("batch", {}) as Dictionary):
		if k.begins_with("by_"):
			any = true
	_check(not any, "backyards: the far city's capture records none of it")
	cap.free()
