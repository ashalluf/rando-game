extends RefCounted
## The farmers' market (FarmersMarket, FarmersMarketKit, FarmersMarketBuild, MarketShopper), for
## tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## Checks the tables, that the basin has markets a few kilometres apart on plain local streets of
## the residential districts, each closed between its crossings with the junctions left open, the
## layout (stalls on the street, apart, an aisle down the middle, vans behind clear of the
## canopies), the hours (nothing before dawn, the canopies up mid-morning, packed up after one,
## gone in the afternoon, nothing on another day), then builds the market's chunk busy and packed
## up and checks its batches, knockable canopies and tables, browse spots, the asphalt under it and
## people standing on it, no parked car in it, the LOD canopies, and that with the market off the
## street is open and the block's buildings are the same.

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_tables()
	var markets := _markets(plan)
	_t._check(markets.size() >= 2, "the basin has farmers' markets a few kilometres apart (%d)" % markets.size())
	if markets.is_empty():
		return
	_streets(plan, markets)
	var m: Dictionary = markets[0]
	_layout(m)
	_hours(m)
	_meshes()
	_chunks(city, plan, m)


func _tables() -> void:
	var day := 0.0
	for v: float in FarmersMarket.DAY_ODDS:
		day += v
	var kind := 0.0
	for v: float in FarmersMarket.KIND_ODDS:
		kind += v
	_t._check(absf(day - 1.0) < 0.001 and FarmersMarket.DAY_ODDS.size() == 7 and absf(kind - 1.0) < 0.001
		and FarmersMarket.KIND_ODDS.size() == FarmersMarket.Kind.size() and FarmersMarketKit.VARIANTS.size() == FarmersMarket.Kind.size(),
		"the market's day and stall odds each add up to one, a share and a variant count per kind")


func _markets(plan: CityPlan) -> Array:
	var out: Array = []
	var c0 := FarmersMarket._cell_of(Vector2(-6000.0, -6000.0))
	var c1 := FarmersMarket._cell_of(Vector2(6000.0, 6000.0))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var m := FarmersMarket.decide(plan, Vector2i(cx, cz))
			if not m.is_empty():
				out.append(m)
	return out


func _streets(plan: CityPlan, markets: Array) -> void:
	var ok := true
	var why := ""
	for m: Dictionary in markets:
		var axis := int(m.axis)
		var index := int(m.index)
		var mid := (float(m.lo) + float(m.hi)) * 0.5
		var o := 1 - axis
		var jx := index if axis == CityPlan.AXIS_X else int(m.k)
		var jz := int(m.k) if axis == CityPlan.AXIS_X else index
		var good := not plan.road_open(axis, index, mid) and plan.road_open(axis, index, float(m.lo) + 1.0) \
			and plan.road_open(axis, index, float(m.hi) - 1.0) and not plan.junction_closed(jx, jz) \
			and float(m.width) < plan.avenue_width - 0.1 and int(plan.district_at(FarmersMarket.point(m, mid, 0.0))) in FarmersMarket.DISTRICTS \
			and FarmersMarket.decide(plan, m.cell) == m and o != axis
		if not good:
			ok = false
			why = String(m.name)
	_t._check(ok, "every market's street is a residential local street, closed between its crossings, the junctions open (%s)" % why)
	# Apart: no two in one cell, and the nearest pair a kilometre or more apart.
	var near := INF
	for i in markets.size():
		for j in range(i + 1, markets.size()):
			var a := FarmersMarket.point(markets[i], (float(markets[i].lo) + float(markets[i].hi)) * 0.5, 0.0)
			var b := FarmersMarket.point(markets[j], (float(markets[j].lo) + float(markets[j].hi)) * 0.5, 0.0)
			near = minf(near, a.distance_to(b))
	_t._check(near > 600.0, "markets stand well apart (nearest pair %.0f m)" % near)


func _layout(m: Dictionary) -> void:
	var lay := FarmersMarket.layout(m)
	var stalls: Array = lay.stalls
	var ok := stalls.size() >= 12
	var rect: Rect2 = m.rect
	var squares: Array[Rect2] = []
	for s: Dictionary in stalls:
		var c := FarmersMarket.point(m, float(s.t), float(s.o))
		var r := Rect2(c - Vector2.ONE * FarmersMarketKit.HALF, Vector2.ONE * FarmersMarketKit.HALF * 2.0)
		ok = ok and rect.grow(0.01).encloses(r)
		for q: Rect2 in squares:
			ok = ok and not q.grow(-0.05).intersects(r.grow(-0.05))
		squares.append(r)
	var vans_ok := true
	for v: Dictionary in lay.vans:
		var c := FarmersMarket.point(m, float(v.t), float(v.o))
		var along: Vector2 = FarmersMarket.dirs(m)[0]
		var size := Vector2(FarmersMarket.VAN_W, 5.95) if absf(along.y) > 0.5 else Vector2(5.95, FarmersMarket.VAN_W)
		var r := Rect2(c - size * 0.5, size)
		vans_ok = vans_ok and rect.grow(0.05).encloses(r)
		for q: Rect2 in squares:
			vans_ok = vans_ok and not q.intersects(r.grow(-0.1))
	var aisle := FarmersMarketBuild._aisle(m, lay)
	_t._check(ok, "the market's %d stalls stand on its street, none overlapping" % stalls.size())
	_t._check(vans_ok, "the vans behind the stalls stand on the street, clear of the canopies (%d)" % (lay.vans as Array).size())
	_t._check(float(aisle.o1) - float(aisle.o0) > 2.5, "an aisle runs down the middle (%.1f m clear)" % (float(aisle.o1) - float(aisle.o0)))
	FarmersMarket._layouts.clear()
	var again := FarmersMarket.layout(m)
	var same := (again.stalls as Array).size() == stalls.size()
	for i in mini(stalls.size(), (again.stalls as Array).size()):
		same = same and is_equal_approx(float(again.stalls[i].t), float(stalls[i].t)) and int(again.stalls[i].kind) == int(stalls[i].kind) \
			and String(again.stalls[i].name) == String(stalls[i].name)
	_t._check(same, "the layout is pure: worked out again it is the same market")


func _hours(m: Dictionary) -> void:
	var day := int(m.day)
	var other := (day + 3) % 7
	var counts := {}
	for h: float in [5.0, 7.0, 10.0, 13.6, 16.0]:
		var st := FarmersMarket.status(m, h, day)
		var c := [0, 0, 0]
		for s: int in st.states:
			c[s] += 1
		counts[h] = c
	var n := (FarmersMarket.layout(m).stalls as Array).size()
	_t._check(int(counts[5.0][0]) == n and int(counts[16.0][0]) == n, "nothing stands at 5:00 or 16:00 on the market's day")
	_t._check(int(counts[10.0][2]) == n, "every canopy is up at 10:00 (%d of %d)" % [int(counts[10.0][2]), n])
	_t._check(int(counts[7.0][1]) > 0 and int(counts[13.6][1]) > 0 and int(counts[13.6][2]) < n,
		"stalls are setting up at 7:00 and packing up at 13:36 (folded %d, %d)" % [int(counts[7.0][1]), int(counts[13.6][1])])
	var busy := FarmersMarket.status(m, 10.0, day)
	var quiet := FarmersMarket.status(m, 16.0, day)
	var off := FarmersMarket.status(m, 10.0, other)
	_t._check(int(busy.shoppers) > 10 and int(quiet.shoppers) == 0 and int(off.shoppers) == 0 and int(off.up) == 0,
		"shoppers at 10:00 on its day (%d), none in the afternoon or on another day" % int(busy.shoppers))


func _meshes() -> void:
	var worst := 0
	var ok := true
	for k in 4:
		for v in int(FarmersMarketKit.VARIANTS[k]):
			var mesh := FarmersMarketKit.goods(k, v) as ArrayMesh
			var idx: PackedInt32Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
			worst = maxi(worst, idx.size() / 3)
			ok = ok and mesh.get_surface_count() == 1 and mesh.surface_get_material(0) == FarmersMarketKit.material() \
				and PropFactory.shadow_proxy(mesh) != null
	var canopy := FarmersMarketKit.canopy() as ArrayMesh
	_t._check(ok and canopy.surface_get_material(0) == FarmersMarketKit.material(),
		"every market mesh is one surface on the market shader, its far level casting the shadow")
	_t._check(worst < 14000, "a stall's goods stay under 14k triangles (worst %d)" % worst)
	var src := FileAccess.get_file_as_string("res://shaders/farmers_market.gdshader")
	_t._check(src.contains("#include \"res://shaders/color_space.gdshaderinc\"") and src.contains("cs_out("),
		"the market shader works in linear on both renderers (color_space.gdshaderinc)")


func _chunks(city: Node3D, plan: CityPlan, m: Dictionary) -> void:
	var owner: Vector2i = m.owner
	FarmersMarket.force_market_day = true
	FarmersMarket.force_hour = 10.0
	var chunk: CityChunk = city._new_chunk(owner, CityChunk.Level.FULL)
	chunk.build()
	var st := FarmersMarket.status(m, 10.0, 0)
	var canopy := chunk.get_node_or_null("Batch_fm_canopy") as MultiMeshInstance3D
	var items := 0
	for c in chunk.get_children():
		if c is EncampmentItem and String(c.name).begins_with("Market"):
			items += 1
	_t._check(canopy != null and canopy.multimesh.instance_count == int(st.up) and items == int(st.up) * 2,
		"the busy market's chunk puts up its %d canopies and tables, each knockable (%d bodies)" % [int(st.up), items])
	var goods := 0
	for c in chunk.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("Batch_fm_goods"):
			goods += (c as MultiMeshInstance3D).multimesh.instance_count
	_t._check(goods == int(st.up), "a goods table under every canopy (%d)" % goods)
	_t._check(chunk.get_node_or_null("MarketDetail") != null and chunk.get_node_or_null("Batch_fm_bollard") != null,
		"banners, lights and stall marks are one mesh, and bollards close both ends")
	var queue: Array = chunk.get_meta("vendor_queue", [])
	_t._check(queue.size() >= int(st.up) * 2, "a browse spot in front of every stall (%d)" % queue.size())
	var mid := FarmersMarket.point(m, (float(m.lo) + float(m.hi)) * 0.5, 0.0)
	_t._check(absf(chunk.ground_y(mid.x, mid.y) - (CityChunk.ROAD_TOP + chunk._gy(mid.x, mid.y))) < 0.001,
		"people at the market stand on the asphalt, not at pavement height")
	var parked := 0
	for car in chunk.get("_cars"):
		if is_instance_valid(car):
			var p: Vector3 = WorldState.to_world((car as Node3D).global_position)
			if (m.rect as Rect2).grow(-0.5).has_point(Vector2(p.x, p.z)):
				parked += 1
	_t._check(parked == 0, "no parked car stands in the market street (%d)" % parked)
	# The slab under it: the closed road is still paved.
	var aisle := FarmersMarketBuild._aisle(m, FarmersMarket.layout(m))
	var shopper := MarketShopper.new()
	shopper.setup_market(m, aisle, plan.block(owner.x, owner.y).rect, 77)
	var inside := true
	for k in 20:
		var p := shopper._random_ring_point(4.0)
		inside = inside and (m.rect as Rect2).has_point(p)
	shopper.free()
	_t._check(inside, "a shopper's walks stay in the market's aisle")
	# A canopy knocked over is remembered.
	var item: EncampmentItem = null
	for c in chunk.get_children():
		if c is EncampmentItem and String(c.name).begins_with("MarketCanopy"):
			item = c
			break
	if item != null:
		var id := item.item_id
		item.knock(Vector3(3.0, 5.0, 0.0))
		_t._check(WorldState.is_destroyed(chunk.key, id), "a canopy blown over is remembered as gone")
	var sig := _signature(chunk, m)
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	# Packed up in the afternoon: the bollards and marks stay, no canopy.
	FarmersMarket.force_hour = 16.0
	var late: CityChunk = city._new_chunk(owner, CityChunk.Level.FULL)
	late.build()
	_t._check(late.get_node_or_null("Batch_fm_canopy") == null and late.get_node_or_null("Batch_fm_bollard") != null
		and late.get_node_or_null("MarketDetail") != null, "in the afternoon the street is empty but for its bollards, sign and stall marks")
	late.get_parent().remove_child(late)
	late.free()
	# LOD: the canopies alone.
	FarmersMarket.force_hour = 10.0
	var lod: CityChunk = city._new_chunk(owner, CityChunk.Level.LOD)
	lod.build()
	_t._check(lod.get_node_or_null("Batch_fm_canopy") != null and lod.get_node_or_null("Batch_fm_goods_0_0") == null,
		"an LOD chunk draws the market's canopies and nothing else of it")
	lod.get_parent().remove_child(lod)
	lod.free()
	# Off: the street is open and the block is the same block.
	FarmersMarket.enabled = false
	FarmersMarket.reset()
	var open := plan.road_open(int(m.axis), int(m.index), (float(m.lo) + float(m.hi)) * 0.5)
	var bare: CityChunk = city._new_chunk(owner, CityChunk.Level.FULL)
	bare.build()
	var bare_sig := _signature(bare, m)
	bare.get_parent().remove_child(bare)
	bare.free()
	FarmersMarket.enabled = true
	FarmersMarket.reset()
	_t._check(open, "with the market off (FARMERS_MARKET=0) its street is open to traffic")
	_t._check(bare_sig == sig, "the market rolls nothing from the block: built without it the buildings stand where they stood")
	FarmersMarket.force_hour = -1.0
	FarmersMarket.force_market_day = OS.get_environment("MARKET_DAY") == "1"


## The block's buildings and trash cans by position, and its parked cars off the market street.
func _signature(chunk: CityChunk, m: Dictionary) -> Array:
	var out: Array = []
	for c in chunk.get_children():
		if c is Building or c is TrashCan:
			var p: Vector3 = (c as Node3D).position
			out.append("%s %.2f %.2f" % [c.get_class(), p.x, p.z])
	for car in chunk.get("_cars"):
		if is_instance_valid(car):
			var p: Vector3 = WorldState.to_world((car as Node3D).global_position)
			if not (m.rect as Rect2).grow(1.0).has_point(Vector2(p.x, p.z)):
				out.append("car %.1f %.1f" % [p.x, p.z])
	out.sort()
	return out
