extends RefCounted
## Street vendors (StreetVendors, StreetVendor), for tests/smoke_test.gd. Loaded at run time, not
## named there, so it compiles after the autoloads.
##
## Checks the tables (every kind in every place, the hours, the shader's copy of the canvases),
## the schedule's wrap past midnight, that downtown has trucks at night and carts by day, then
## builds FULL chunks with a truck and with a cart (StreetVendors.force_hour) and checks: one
## batch per kind on the vendor shader, the truck a prop nothing breaks with its window left open,
## its stretch of kerb free of parked cars, a queue and a vendor for each stand, a cart that tips
## over (EncampmentItem) and stays gone, and the block built with the vendors off is the same block
## (hash-seeded: the chunk rng, the props and the parked cars' rolls untouched).

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_tables()
	_hours()
	_meshes()
	var night := _find(plan, 21.0, StreetVendors.Kind.TRUCK)
	var day := _find(plan, 13.0, StreetVendors.Kind.FRUIT)
	_t._check(night.x != 99999, "downtown has a taco truck working at 21:00")
	_t._check(day.x != 99999, "a fruit cart works a downtown or park block at 13:00")
	var counts := _counts(plan)
	_t._check(counts[0] > counts[1] and counts[3] > counts[2],
		"trucks work the night and carts the day round downtown (trucks %d at 21:00, %d at 13:00; carts %d at 21:00, %d at 13:00)" % counts)
	if night.x != 99999:
		_truck_chunk(city, plan, night)
	if day.x != 99999:
		_cart_chunk(city, plan, day)


func _tables() -> void:
	var ok := true
	for place: int in StreetVendors.ODDS:
		ok = ok and (StreetVendors.ODDS[place] as Array).size() == StreetVendors.Kind.size()
	for kind in StreetVendors.Kind.size():
		ok = ok and StreetVendors.SCHEDULE.has(kind)
	_t._check(ok, "every vendor place rolls every kind, and every kind has hours")
	# The shader's copy of the canvases' second colours (CANVAS2) is the script's.
	var src := FileAccess.get_file_as_string("res://shaders/street_vendor.gdshader")
	var same := true
	for i in StreetVendors.CANVAS.size():
		var c: Color = StreetVendors.CANVAS[i][1]
		same = same and src.contains("vec3(%s, %s, %s)" % [_num(c.r), _num(c.g), _num(c.b)])
	_t._check(same and StreetVendors.CANVAS.size() <= 6, "street_vendor.gdshader's CANVAS2 matches StreetVendors.CANVAS")


static func _num(v: float) -> String:
	var s := "%.2f" % v
	if s.ends_with("0") and not s.ends_with(".0"):
		s = s.substr(0, s.length() - 1)
	return s


func _hours() -> void:
	var a := StreetVendors.open_at(Vector2(17.5, 2.0), 23.0) and StreetVendors.open_at(Vector2(17.5, 2.0), 1.0) \
		and not StreetVendors.open_at(Vector2(17.5, 2.0), 12.0) and StreetVendors.open_at(Vector2(9.0, 18.0), 12.0) \
		and not StreetVendors.open_at(Vector2(9.0, 18.0), 21.0)
	_t._check(a, "vendor hours wrap past midnight (a truck open 17:30-02:00 works at 23:00 and 01:00, not noon)")


func _meshes() -> void:
	var ok := true
	var worst := 0
	var meshes: Array[Mesh] = [StreetVendors.umbrella_mesh()]
	for i in StreetVendors.TRUCKS.size():
		meshes.append(StreetVendors.truck(i))
	for kind: int in StreetVendors.CART_KEYS:
		meshes.append(StreetVendors.cart(kind))
	for m in meshes:
		var tris := 0
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			tris += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		worst = maxi(worst, tris)
		ok = ok and m.get_surface_count() == 1 and m.surface_get_material(0) == StreetVendors.material() and tris > 200
	_t._check(ok, "every vendor mesh is one surface on the vendor shader")
	_t._check(worst < 40000, "a vendor mesh stays under 40k triangles (worst %d)" % worst)


## The first block round downtown with a `kind` working at `hour`.
func _find(plan: CityPlan, hour: float, kind: int) -> Vector2i:
	var centre := plan.block_index_at(plan.macro.downtown_center if plan.macro else Vector2.ZERO)
	for r in 6:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var k := centre + Vector2i(dx, dz)
				var b := plan.block(k.x, k.y)
				if plan.zone_at((b.rect as Rect2).get_center()) != MacroMap.Zone.CITY:
					continue
				for v: Dictionary in StreetVendors.plan_block(plan, k.x, k.y, hour):
					if int(v.kind) == kind:
						return k
	return Vector2i(99999, 99999)


func _counts(plan: CityPlan) -> Array:
	var centre := plan.block_index_at(plan.macro.downtown_center if plan.macro else Vector2.ZERO)
	var out := [0, 0, 0, 0]
	for dz in range(-4, 5):
		for dx in range(-4, 5):
			for h in 2:
				for v: Dictionary in StreetVendors.plan_block(plan, centre.x + dx, centre.y + dz, 21.0 if h == 0 else 13.0):
					if int(v.kind) == StreetVendors.Kind.TRUCK:
						out[h] += 1
					else:
						out[2 + h] += 1
	return out


func _truck_chunk(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	StreetVendors.force_hour = 21.0
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var truck_rec: Dictionary = {}
	for r: Dictionary in chunk.prop_records:
		if String(r.kind) == "vendor_truck":
			truck_rec = r
	_t._check(not truck_rec.is_empty() and float(truck_rec.health) > 1e9, "a taco truck stands as a street prop that does not break")
	var node: MultiMeshInstance3D = null
	for c in chunk.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("Batch_" + StreetVendors.K_TRUCK):
			node = c
	_t._check(node != null and node.multimesh.mesh.surface_get_material(0) == StreetVendors.material()
		and absf(node.visibility_range_end - StreetVendors.TRUCK_DRAW) < 0.5, "the truck is a batch on the vendor shader, drawn to %d m" % int(StreetVendors.TRUCK_DRAW))
	_t._check(not truck_rec.is_empty() and (truck_rec.shapes as Array).size() == StreetVendors.TRUCK_SHAPES.size(), "the truck has its collision, the window left open")
	var trucks: Array = chunk.get_meta("vendor_trucks", [])
	var blocked := 0
	for car in chunk.get("_cars"):
		if is_instance_valid(car):
			var p: Vector3 = WorldState.to_world((car as Node3D).position) if (car as Node).get_parent() != chunk else (car as Node3D).position
			if StreetVendors.blocks_parking(chunk, p):
				blocked += 1
	_t._check(not trucks.is_empty() and blocked == 0, "no parked car stands in a truck's stretch of kerb (%d)" % blocked)
	var queue: Array = chunk.get_meta("vendor_queue", [])
	var people: Array = chunk.get_meta("vendor_people", [])
	var cooks := people.filter(func(s: Dictionary) -> bool: return bool(s.truck))
	_t._check(queue.size() >= 4 and not cooks.is_empty() and float(cooks[0].floor) > 0.6,
		"the truck has a queue on the pavement and a cook on its floor (%d spots)" % queue.size())
	var vendors := 0
	for c in chunk.get_children():
		if c is StreetVendor:
			vendors += 1
	_t._check(vendors >= 1 or people.size() == 0, "the stands' vendors are spawned (%d of %d)" % [vendors, people.size()])
	# A queue spot is handed out once.
	var spot := StreetVendors.free_queue(chunk, queue[0].p if not queue.is_empty() else Vector2.ZERO, 50.0)
	if not spot.is_empty():
		spot.taken = chunk
		var again := StreetVendors.free_queue(chunk, spot.p, 0.1)
		_t._check(again.is_empty() or again != spot, "a taken queue spot is not handed out again")
		spot.taken = null
	# Off, the same block.
	var sig := _signature(chunk)
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	StreetVendors.enabled = false
	var bare: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	bare.build()
	StreetVendors.enabled = true
	var bare_sig := _signature(bare)
	_t._check(bare_sig == sig, "the vendors roll nothing from the block: built without them it is the same block")
	bare.get_parent().remove_child(bare)
	bare.free()
	StreetVendors.force_hour = -1.0


func _cart_chunk(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	StreetVendors.force_hour = 13.0
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var item: EncampmentItem = null
	for c in chunk.get_children():
		if c is EncampmentItem and String(c.name).begins_with("Vendor_"):
			item = c
	_t._check(item != null and chunk.get_node_or_null("Batch_" + StreetVendors.CART_KEYS[StreetVendors.Kind.FRUIT]) != null,
		"a fruit cart stands on the pavement as a knockable body and a batch")
	_t._check(chunk.get_node_or_null("Batch_" + StreetVendors.K_UMBRELLA) != null, "the fruit cart has its umbrella")
	if item == null:
		StreetVendors.force_hour = -1.0
		chunk.get_parent().remove_child(chunk)
		chunk.free()
		return
	var id := item.item_id
	item.knock(Vector3(4.0, 3.0, 0.0))
	_t._check(WorldState.is_destroyed(chunk.key, id), "a knocked cart is remembered as gone")
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	var again: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	again.build()
	var back := false
	for c in again.get_children():
		if c is EncampmentItem and (c as EncampmentItem).item_id == id:
			back = true
	_t._check(not back, "a knocked-over cart does not stand back up when its chunk is rebuilt")
	again.get_parent().remove_child(again)
	again.free()
	StreetVendors.force_hour = -1.0


## Buildings, props (but the vendors' own), trash cans, and the parked cars' kinds, by position.
func _signature(chunk: CityChunk) -> Array:
	var out: Array = []
	for c in chunk.get_children():
		if c is Building or c is TrashCan:
			var p: Vector3 = (c as Node3D).position
			out.append("%s %.2f %.2f" % [c.get_class(), p.x, p.z])
	for r in chunk.prop_records:
		if String(r.kind) != "vendor_truck":
			out.append("%s %.2f %.2f" % [r.kind, (r.position as Vector3).x, (r.position as Vector3).z])
	out.sort()
	return out
