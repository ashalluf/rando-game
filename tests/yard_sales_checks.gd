extends RefCounted
## Weekend yard sales (YardSales, YardSaleKit, YardSaleBrowser) for tests/smoke_test.gd. Loaded at
## run time (not named there), so it compiles after the autoloads. Checks: every kit mesh and sign
## builds inside its triangle budget on the one material; WHEN is pure and weekend-only (Saturday,
## Sunday, both; nothing on a weekday, before setup or after the leftovers go); a share of the
## suburbs' houses hold one on a Saturday morning; the plan is pure and lays a row in the front
## yard, clear of the house, the front walk, the lawn's tree, a car in the drive, the street line
## and each other, with the aisle in front of it; a FULL chunk draws it (a batch per kind, every
## thing knockable, corner signs, the seller and browsers, browse spots) and with the system off
## everything else in the chunk is the same (batches, prop ids); after the sale a FREE box and no
## seller; a weekday chunk, a LOD chunk and the far city's capture draw none of it. Everything it
## needs is staged here (force_day / force_hour / force_all), never left by an earlier check.

var _t: Node

const NEAR := Vector2(1911, 4260)
## Triangle budgets per kit mesh.
const BUDGET := {"table6_0": 9000, "table6_1": 9000, "table6_2": 9000, "table6_bare": 3000, "card_0": 6000, "card_1": 6000,
	"card_2": 6000, "card_bare": 3000, "rack": 9000, "sofa": 1500, "boxes_0": 2000, "boxes_1": 3000, "floor_lamp": 600,
	"balloons": 1500, "free_box": 2500}


func run(t: Node, city: Node3D) -> void:
	_t = t
	var t0 := Time.get_ticks_msec()
	var saved := [YardSales.enabled, YardSales.force_all, YardSales.force_day, YardSales.force_hour]
	YardSales.enabled = true
	_kit()
	var plan: CityPlan = city.plan
	_when(plan)
	_share(plan)
	YardSales.force_all = true
	var block := _sale_block(plan)
	_plan(plan, block)
	_full(city, block)
	_lod(city, block)
	YardSales.enabled = saved[0]
	YardSales.force_all = saved[1]
	YardSales.force_day = saved[2]
	YardSales.force_hour = saved[3]
	print("YARD_SALES_CHECKS %d ms" % (Time.get_ticks_msec() - t0))


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


static func _tris(m: Mesh) -> int:
	var tris := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		tris += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return tris


func _kit() -> void:
	var over: Array = []
	var mat := YardSaleKit.material()
	var same_mat := true
	for k: String in BUDGET:
		var m: Mesh = YardSaleKit.get_mesh(k)
		var tris := _tris(m) if m else 0
		if tris > int(BUDGET[k]) or tris < 4:
			over.append("%s %d" % [k, tris])
		if m:
			for s in m.get_surface_count():
				same_mat = same_mat and m.surface_get_material(s) == mat
	_check(over.is_empty(), "yard sales: every kit mesh builds inside its triangle budget %s" % str(over))
	_check(same_mat and mat.shader != null and mat.shader.get_shader_uniform_list().size() > 0, "yard sales: the kit is one shader")
	var signs := [YardSaleKit.stake_sign("YARD SALE", "SAT 8-2", 1, 1), YardSaleKit.pole_sign("GARAGE SALE", 1, 0, 0),
		YardSaleKit.pole_sign("GARAGE SALE", -1, 0, 0), YardSaleKit.lath_sign("MOVING SALE", 1, 2, 2), YardSaleKit.tag_mesh("$40"),
		YardSaleKit.tag_mesh("FREE"), YardSaleKit.tape_ring(0.155)]
	var bad: Array = []
	for m: Mesh in signs:
		var tris := _tris(m)
		if tris < 12 or tris > 4000:
			bad.append("%s %d" % [m.resource_name, tris])
	_check(bad.is_empty(), "yard sales: the hand-lettered signs build (%s)" % str(bad))
	# The arrow points the way asked: its head's vertices are on that side of the board.
	var r := _arrow_side(YardSaleKit.pole_sign("GARAGE SALE", 1, 0, 0))
	var l := _arrow_side(YardSaleKit.pole_sign("GARAGE SALE", -1, 0, 0))
	_check(r > 0.02 and l < -0.02, "yard sales: a corner sign's arrow points to the reader's right or left (%.3f / %.3f)" % [r, l])


## The mean x of the arrow's ink (under the text): its head's side.
static func _arrow_side(m: Mesh) -> float:
	var arr := m.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var c: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var sum := 0.0
	var n := 0
	for i in v.size():
		if int(floor(c[i].a * 16.0)) == YardSaleKit.K_INK and v[i].y < -0.05:
			sum += v[i].x
			n += 1
	return sum / maxf(float(n), 1.0)


func _when(plan: CityPlan) -> void:
	var ok_pure := true
	var days := {"sat": 0, "sun": 0, "both": 0}
	var weekday_any := false
	var states_ok := true
	var n := 0
	for k in 4000:
		var info := YardSales.sale_info(plan, k * 7919 + 13, CityPlan.District.SUBURBS)
		if str(info) != str(YardSales.sale_info(plan, k * 7919 + 13, CityPlan.District.SUBURBS)):
			ok_pure = false
		if info.is_empty():
			continue
		n += 1
		var d: Array = info.days
		days["both" if d.size() > 1 else ("sat" if d[0] == 6 else "sun")] += 1
		for wd in range(1, 6):
			if YardSales.state_at(info, wd, 10.0) != YardSales.State.NONE:
				weekday_any = true
		var day: int = d[0]
		var h: Array = info.hours
		states_ok = states_ok and YardSales.state_at(info, day, float(h[0]) - 0.1) == YardSales.State.NONE \
			and YardSales.state_at(info, day, (float(h[0]) + float(h[1])) * 0.5) == YardSales.State.SETUP \
			and YardSales.state_at(info, day, (float(h[1]) + float(h[2])) * 0.5) == YardSales.State.OPEN \
			and YardSales.state_at(info, day, float(h[3]) + 0.1) == YardSales.State.NONE
	_check(ok_pure, "yard sales: who holds one and when is pure (the same twice)")
	_check(n > 100 and n < 600 and not weekday_any, "yard sales: %d of 4000 suburban houses hold one, never on a weekday" % n)
	_check(days.sat > days.sun and days.sun > 0 and days.both > 0 and states_ok,
		"yard sales: Saturdays most, Sundays and both too (%s), setup, open, then gone" % str(days))
	_check(YardSales.sale_info(plan, 12345, CityPlan.District.DOWNTOWN).is_empty(), "yard sales: none downtown")


## Over the suburbs round NEAR on a Saturday morning (the real odds), the share of lots with a sale.
func _share(plan: CityPlan) -> void:
	var was := YardSales.force_all
	YardSales.force_all = false
	var c: Vector2i = plan.block_index_at(NEAR)
	var lots := 0
	var sales := 0
	var usec := 0
	for bx in range(c.x - 3, c.x + 4):
		for bz in range(c.y - 3, c.y + 4):
			if not _house_block(plan, bx, bz):
				continue
			var d := int(plan.block(bx, bz).district)
			var bp := YardSales.block_plans(plan, bx, bz)
			for lp: Dictionary in bp.lots:
				lots += 1
				var t0 := Time.get_ticks_usec()
				if not YardSales.plan_lot(plan, lp, d, 6, 9.5).is_empty():
					sales += 1
				usec += Time.get_ticks_usec() - t0
	YardSales.force_all = was
	_check(lots > 50 and sales >= 1 and float(sales) / float(lots) < 0.12,
		"yard sales: %d of %d houses round the suburb bookmark have a sale out on a Saturday morning (%.0f us a lot)" % [sales, lots, float(usec) / maxf(lots, 1)])


static func _house_block(plan: CityPlan, bx: int, bz: int) -> bool:
	var b: Dictionary = plan.block(bx, bz)
	var d := int(b.district)
	return (d == CityPlan.District.SUBURBS or d == CityPlan.District.BEACHTOWN) and int(b.kind) == CityPlan.BlockKind.BUILDINGS \
		and not b.has("site") and plan.zone_at((b.rect as Rect2).get_center()) == MacroMap.Zone.CITY and not plan.marina_block(bx, bz)


## With every candidate holding one: the house block round NEAR with the most sale items.
func _sale_block(plan: CityPlan) -> Vector2i:
	var c: Vector2i = plan.block_index_at(NEAR)
	var best := c
	var most := -1
	for bx in range(c.x - 2, c.x + 3):
		for bz in range(c.y - 2, c.y + 3):
			if not _house_block(plan, bx, bz):
				continue
			var n := 0
			for sp: Array in YardSales.block_sales(plan, bx, bz, 6, 9.5):
				n += (sp[1].items as Array).size()
			if n > most:
				most = n
				best = Vector2i(bx, bz)
	print("YARD_SALES check block %s (%d items)" % [str(best), most])
	return best


func _plan(plan: CityPlan, block: Vector2i) -> void:
	var sales := YardSales.block_sales(plan, block.x, block.y, 6, 9.5)
	var again := YardSales.block_sales(plan, block.x, block.y, 6, 9.5)
	_check(sales.size() >= 2 and str(sales) == str(again), "yard sales: the block's sales are pure (%d sales)" % sales.size())
	var bad: Array = []
	var kinds := {}
	for sp: Array in sales:
		var lp: Dictionary = sp[0]
		var s: Dictionary = sp[1]
		var f: Dictionary = lp.frame
		var fd: float = lp.front
		var house: Array[Rect2] = []
		for r: Rect2 in lp.parts:
			house.append(YardFill._to_frame(f, r))
		var path := Rect2()
		for pc: Array in lp.pieces:
			if String(pc[3]) == "path":
				path = YardFill._to_frame(f, pc[0])
		var rects: Array[Rect2] = []
		for it: Dictionary in s.items:
			kinds[it.kind] = true
			var sz: Vector2 = it.size
			var r := Rect2((it.at as Vector2) - sz * 0.5, sz)
			if r.position.y < YardSales.OPEN_KEEP - 0.01 or r.end.y > fd or r.position.x < 0.0 or r.end.x > float(f.U):
				bad.append("%s out of the front yard %s" % [it.kind, str(r)])
			for h: Rect2 in house:
				if r.intersects(h):
					bad.append("%s on the house" % it.kind)
			if path.size.x > 0.0 and r.intersects(path):
				bad.append("%s on the front walk" % it.kind)
			for o: Rect2 in rects:
				if r.intersects(o):
					bad.append("%s on another thing" % it.kind)
			rects.append(r)
		var aisle_v: float = (s.aisle[0] as Vector2).y
		var pav: bool = s.on_pavement
		if aisle_v >= float(s.row_v) or (aisle_v < 0.3 and not pav) or (pav and aisle_v > -0.3):
			bad.append("aisle at %.2f, row at %.2f" % [aisle_v, float(s.row_v)])
		if int(s.browsers) > YardSales.MAX_BROWSERS or (s.queue as Array).is_empty():
			bad.append("browsers %d, queue %d" % [int(s.browsers), (s.queue as Array).size()])
	_check(bad.is_empty(), "yard sales: every row stands in its front yard, clear of the house, the walk and itself, the aisle in front %s" % str(bad.slice(0, 5)))
	_check(kinds.has("table6") and kinds.size() >= 4, "yard sales: the sales put out tables and more (%s)" % str(kinds.keys()))
	# The leftovers: a FREE box at the kerb, no seller, no browsers.
	var late := YardSales.block_sales(plan, block.x, block.y, 0, 16.0)
	var ok := not late.is_empty()
	for sp: Array in late:
		var s: Dictionary = sp[1]
		ok = ok and (s.free_box as Vector2).x >= 0.0 and (s.seller as Vector2).x < 0.0 and int(s.browsers) == 0
	_check(ok, "yard sales: after it closes a FREE box at the kerb, nobody selling (%d)" % late.size())


func _children(chunk: Node) -> Dictionary:
	var out := {}
	for c in chunk.get_children():
		out[String(c.name)] = c
	return out


func _full(city: Node3D, block: Vector2i) -> void:
	YardSales.force_day = 6
	YardSales.force_hour = 9.5
	YardSales.enabled = false
	var off: CityChunk = city._new_chunk(block, CityChunk.Level.FULL)
	off.build()
	var off_props := {}
	for r: Dictionary in off.prop_records:
		off_props[String(r.id)] = true
	var off_batches := {}
	for c in off.get_children():
		if c is MultiMeshInstance3D:
			off_batches[String(c.name)] = (c as MultiMeshInstance3D).multimesh.instance_count
	var off_items := off.get_tree().get_nodes_in_group("yard_sale_item").size()
	off.get_parent().remove_child(off)
	off.free()
	YardSales.enabled = true
	var on: CityChunk = city._new_chunk(block, CityChunk.Level.FULL)
	on.build()
	var names := _children(on)
	var kinds := 0
	var moved: Array = []
	for n: String in names:
		var c: Node = names[n]
		if not (c is MultiMeshInstance3D):
			continue
		if n.begins_with("Batch_ys_"):
			kinds += 1
		elif not n.begins_with("BatchShadow_ys_"):
			var cnt := (c as MultiMeshInstance3D).multimesh.instance_count
			if int(off_batches.get(n, -1)) != cnt:
				moved.append("%s %d->%d" % [n, int(off_batches.get(n, -1)), cnt])
	var props_kept := true
	for r: Dictionary in on.prop_records:
		if not off_props.has(String(r.id)):
			props_kept = false
	var counts: Dictionary = on.get_meta("yard_sales", {})
	var items := 0
	for c in on.get_children():
		if c.is_in_group("yard_sale_item"):
			items += 1
	var planned := 0
	for sp: Array in YardSales.block_sales(on.plan, block.x, block.y, 6, 9.5).slice(0, YardSales.MAX_PER_CHUNK):
		planned += (sp[1].items as Array).size() + 1
	_check(off_items == 0 and int(counts.get("sales", 0)) >= 1 and kinds >= 4,
		"yard sales: a FULL chunk draws its sales, a batch per kind (%d kinds, %s)" % [kinds, str(counts)])
	_check(items == planned and items > 0, "yard sales: every thing out and the poster board is knockable (%d of %d)" % [items, planned])
	_check(int(counts.get("pole_sign", 0)) + int(counts.get("corner_stake", 0)) >= 1,
		"yard sales: signs at the block's corners (%d on poles, %d on stakes)" % [int(counts.get("pole_sign", 0)), int(counts.get("corner_stake", 0))])
	_check(props_kept and moved.is_empty(), "yard sales: with them off the chunk's other props keep their ids and its batches their counts %s" % str(moved.slice(0, 6)))
	var queue: Array = on.get_meta("vendor_queue", [])
	var sellers := 0
	var browsers := 0
	var off_yard := 0
	for c in on.get_children():
		if c.is_in_group("yard_seller"):
			sellers += 1
		elif c.is_in_group("yard_sale_browser"):
			browsers += 1
			if (c as Node3D).position.y - on.ground_y((c as Node3D).position.x, (c as Node3D).position.z) > 0.5:
				off_yard += 1
	_check(queue.size() >= 2 and browsers <= YardSales.MAX_CHUNK_BROWSERS and off_yard == 0 and sellers <= int(counts.get("sales", 0)),
		"yard sales: browse spots (%d), %d sellers and %d browsers in the crowd cap, on the ground" % [queue.size(), sellers, browsers])
	# Knocked, a thing goes over and stays gone.
	var first: Node = null
	for c in on.get_children():
		if c.is_in_group("yard_sale_item"):
			first = c
			break
	if first:
		first.call("knock", Vector3(0, 2, -6))
		_check(not is_instance_valid(first) or first.is_queued_for_deletion() or bool(first.get("_gone")), "yard sales: a knocked table goes over")
	on.get_parent().remove_child(on)
	on.free()
	# A weekday, and the night: nothing.
	YardSales.force_all = false
	YardSales.force_day = 2
	var wd: CityChunk = city._new_chunk(block, CityChunk.Level.FULL)
	wd.build()
	var any := false
	for n: String in _children(wd):
		if n.begins_with("Batch_ys_"):
			any = true
	_check(not any and not wd.has_meta("yard_sales"), "yard sales: nothing out on a Tuesday")
	wd.get_parent().remove_child(wd)
	wd.free()
	YardSales.force_all = true


func _lod(city: Node3D, block: Vector2i) -> void:
	var lod: CityChunk = city._new_chunk(block, CityChunk.Level.LOD)
	lod.build()
	var any := false
	for n: String in _children(lod):
		if n.begins_with("Batch_ys_") or n.begins_with("YardSale_"):
			any = true
	_check(not any, "yard sales: a LOD chunk draws none of it")
	lod.get_parent().remove_child(lod)
	lod.free()
	var cap := CityChunk.new()
	cap.plan = city.plan
	cap.ix = block.x
	cap.iz = block.y
	cap.level = CityChunk.Level.LOD
	cap.style = city.chunk_style()
	cap.capturing = true
	cap.build()
	var rec := false
	for k: String in (cap.captured.get("batch", {}) as Dictionary):
		if k.begins_with("ys_"):
			rec = true
	_check(not rec, "yard sales: the far city's capture records none of it")
	cap.free()
