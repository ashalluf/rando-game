extends RefCounted
## The fashion district refcam (rc3-fashion-district, tools/refcams/cameras_w6.json
## "fashion_district"), for tests/smoke_test.gd. Loaded at run time, not named there.
##
## - The pavement goods are batched per variant, face and FashionDistrict.SET_CELL stretch: a
##   node's draw range is measured to its bounds' centre, and one batch a block drew nothing
##   while the camera stood beside the goods.
## - LotFill's forecourt planters are left out of a goods face's frontage band (their rolls still
##   made): the same props, positions and other batches with FD_PLANTERS on and off.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var k := _densest(plan)
	if k.x == 1 << 30:
		_t._check(false, "rc3 fashion: the district has blocks on this seed")
		return
	FashionDistrict.force_hour = 11.5
	_cells(city, k)
	_planters(city, plan, k)
	FashionDistrict.force_hour = -1.0


func _densest(plan: CityPlan) -> Vector2i:
	var st := FashionDistrict.stretch()
	var a := plan.block_index_at(st.position + Vector2(1.0, 1.0))
	var b := plan.block_index_at(st.end - Vector2(1.0, 1.0))
	var best := Vector2i(1 << 30, 0)
	var most := 0
	for bz in range(a.y, b.y + 1):
		for bx in range(a.x, b.x + 1):
			var info := FashionDistrict.block_info(plan, bx, bz)
			if not info.is_empty() and (info.faces as Array).size() > most:
				most = (info.faces as Array).size()
				best = Vector2i(bx, bz)
	return best


func _build(city: Node3D, k: Vector2i) -> CityChunk:
	var ch: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	ch.build()
	return ch


func _free(ch: CityChunk) -> void:
	ch.get_parent().remove_child(ch)
	ch.free()


func _cells(city: Node3D, k: Vector2i) -> void:
	var ch := _build(city, k)
	var by_key := {}
	for r: Dictionary in ch.prop_records:
		if String(r.kind) != "fd_set":
			continue
		var key := String((r.instances as Array)[0][0])
		if not by_key.has(key):
			by_key[key] = []
		(by_key[key] as Array).append(r.position)
	var spread := 0.0
	var sets := 0
	for key: String in by_key:
		var ps: Array = by_key[key]
		sets += ps.size()
		for p: Vector3 in ps:
			for q: Vector3 in ps:
				spread = maxf(spread, Vector2(p.x - q.x, p.z - q.z).length())
	# A stretch is SET_CELL long and a set at most ~7 m: no batch spans much more.
	var limit := FashionDistrict.SET_CELL + 8.0
	var nodes := 0
	var ranged := true
	for c in ch.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("Batch_fd_set_"):
			nodes += 1
			ranged = ranged and (c as GeometryInstance3D).visibility_range_end > 0.0
	_t._check(sets >= 4 and spread <= limit and nodes == by_key.size() and ranged,
		"rc3 fashion: block %s's %d goods sets are in %d batches of at most a %.0f m stretch each (widest %.1f m), each with a draw range" % [k, sets, by_key.size(), limit, spread])
	_free(ch)


func _signature(ch: CityChunk) -> Array:
	var out: Array = []
	for r: Dictionary in ch.prop_records:
		var p: Vector3 = r.position
		out.append("P %s %.2f,%.2f" % [r.kind, p.x, p.z])
	for c in ch.get_children():
		if c is Building:
			out.append("B %d" % (c as Building).seed)
		elif c is MultiMeshInstance3D and not String(c.name).contains("bush") and not String(c.name).contains("tree") \
				and not String(c.name).contains("la_") and not String(c.name).begins_with("BatchContact"):
			out.append("M %s %d" % [c.name, (c as MultiMeshInstance3D).multimesh.instance_count])
	out.sort()
	return out


func _planters(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var before := FashionDistrict.planters_cleared
	var on := _build(city, k)
	var cleared := FashionDistrict.planters_cleared - before
	var sig_on := _signature(on)
	_free(on)
	FashionDistrict.clear_planters = false
	var off := _build(city, k)
	var sig_off := _signature(off)
	_free(off)
	FashionDistrict.clear_planters = true
	# The pure test: a rect at a goods face's kerb band is cleared, one deep in the block is not,
	# nor any outside the district.
	var info := FashionDistrict.block_info(plan, k.x, k.y)
	var rect: Rect2 = info.rect
	var e: int = (info.faces as Array)[0]
	var edge: Array = CityChunk._sidewalk_edges(rect)[e]
	var mid: Vector2 = ((edge[0] as Vector2) + (edge[1] as Vector2)) * 0.5
	var inward: Vector2 = edge[2]
	var probe: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	var near := FashionDistrict.clears_planter(probe, Rect2(mid + inward * 5.0 - Vector2(1, 1), Vector2(2, 2)))
	var deep := FashionDistrict.clears_planter(probe, Rect2(rect.get_center() - Vector2(1, 1), Vector2(2, 2)))
	probe.get_parent().remove_child(probe)
	probe.free()
	_t._check(near and not deep and sig_on == sig_off,
		"rc3 fashion: forecourt planters left out of the goods' frontage (%d here, a kerb-band rect %s, the block's middle %s), every prop and other batch the same with them kept (%d entries)" % [cleared, near, deep, sig_on.size()])
