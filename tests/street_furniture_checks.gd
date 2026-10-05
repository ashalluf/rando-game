extends RefCounted
## Street furniture (StreetFurniture), for tests/smoke_test.gd. Loaded at run time, not named
## there, so it compiles after the autoloads.
##
## Checks the meshes (every piece builds on the furniture shader inside its triangle budget, at
## real size, with a shadow twin), the shader's copy of the kinds, the ad atlas's rows, the pure
## rolls (pay station and bench-stop shares, collection days Monday to Friday, the hydrant facing
## the street, the bin by district), then builds a metered downtown block and a suburban block on
## collection day: the new pieces are there as batches on the furniture shader, the carts are
## props with ids of their own, and the same blocks built with the furniture off are the same
## blocks (the same props by kind and place, the same buildings, trash cans and parked cars).

var _t: Node

## Most triangles a piece may have at its finest level.
const BUDGET := {"hydrant": 5200, "meter": 2600, "pay_station": 2600, "ad_bench": 900, "mesh_bin": 4200, "cart": 3600, "bike_rack": 900, "planter": 900}
## Height ranges (m) each piece must stand to: real sizes.
const HEIGHTS := {"hydrant": Vector2(0.55, 0.7), "meter": Vector2(1.4, 1.55), "pay_station": Vector2(2.0, 2.3), "ad_bench": Vector2(0.95, 1.15), "mesh_bin": Vector2(0.95, 1.1), "cart": Vector2(1.0, 1.12), "bike_rack": Vector2(0.85, 0.95), "planter": Vector2(0.45, 0.52)}


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_meshes()
	_shader()
	_rolls(plan)
	_downtown(city, plan)
	_carts(city, plan)


func _meshes() -> void:
	var ok := true
	var sizes := true
	var report := []
	for name: String in BUDGET:
		var m: Mesh = StreetFurniture.call(name)
		var tris := 0
		if m and m.get_surface_count() == 1:
			tris = (m.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		ok = ok and m != null and m.get_surface_count() == 1 and m.surface_get_material(0) == StreetFurniture.material() and tris > 40 and tris <= int(BUDGET[name])
		var h := m.get_aabb().end.y if m else 0.0
		var want: Vector2 = HEIGHTS[name]
		sizes = sizes and h >= want.x and h <= want.y and m.get_aabb().position.y > -0.01
		report.append("%s %d/%.2fm" % [name, tris, h])
	_t._check(ok, "every furniture piece is one surface on the furniture shader inside its budget (%s)" % ", ".join(report))
	_t._check(sizes, "every furniture piece stands on the pavement at its real height")
	_t._check(PropFactory.shadow_proxy(StreetFurniture.hydrant()) != null and PropFactory.shadow_proxy(StreetFurniture.mesh_bin()) != null,
		"the hydrant and the bin cast their shadows from lighter twins")


func _shader() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/street_furniture.gdshader")
	var same := true
	var consts := {"K_PAINT": 0, "K_PAINT_V": 1, "K_GALV": 2, "K_STEEL": 3, "K_RUBBER": 4, "K_CONCRETE": 5, "K_PERF": 6, "K_LINER": 7, "K_HDPE": 8, "K_AD": 9, "K_SCREEN": 10, "K_SOIL": 11, "K_LABEL": 12, "K_SOLAR": 13, "K_GLASS": 14, "K_BRASS": 15}
	for k: String in consts:
		same = same and int(StreetFurniture.get(k)) == int(consts[k]) and src.contains("const float %s = %d.0;" % [k, int(consts[k])])
	_t._check(same, "street_furniture.gdshader's kinds are StreetFurniture's")
	var tex: Texture2D = load("res://assets/textures/street_furniture/bench_ads.jpg")
	_t._check(tex != null and tex.get_height() == tex.get_width() * StreetFurniture.BENCH_ADS * 320 / 1024,
		"the bench ad atlas holds StreetFurniture.BENCH_ADS rows")


func _rolls(plan: CityPlan) -> void:
	var pays := 0
	var benches := 0
	var n := 400
	for i in n:
		var at := Vector3(float(i) * 7.3, 0.12, float(i % 17) * 11.1)
		if (StreetFurniture.meter_instance(plan.seed, at, 0.0, null)[0] as String) == "pay_station":
			pays += 1
		if StreetFurniture.bench_stop(plan.seed, at):
			benches += 1
	_t._check(absf(float(pays) / n - StreetFurniture.PAY_STATION_SHARE) < 0.07, "about %d %% of metered spaces are pay stations (%d of %d)" % [int(StreetFurniture.PAY_STATION_SHARE * 100.0), pays, n])
	_t._check(absf(float(benches) / n - StreetFurniture.BENCH_STOP_SHARE) < 0.09, "about half the bus stops are an ad bench without a shelter (%d of %d)" % [benches, n])
	var days := {}
	for i in 60:
		days[StreetFurniture.collection_day(plan.seed, i, i * 3 - 7)] = true
	_t._check(days.size() == 5 and not days.has(5) and not days.has(6), "collection days run Monday to Friday")
	# The hydrant's pumper to the street, whatever the rolled spin.
	var facing := true
	for inward: Vector2 in [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]:
		var inst: Array = StreetFurniture.hydrant_instances(plan.seed, false, 1.3, Vector3(10.0, 0.12, 20.0), inward)[0]
		var front: Vector3 = (inst[2] as Transform3D).basis * Vector3(0, 0, -1)
		facing = facing and Vector2(front.x, front.z).dot(-inward) > 0.9
	_t._check(facing, "a hydrant faces its pumper outlet to the street")
	_t._check(StreetFurniture.bin_style(CityPlan.District.DOWNTOWN) == 1 and StreetFurniture.bin_style(CityPlan.District.SUBURBS) == 0,
		"downtown's trash cans are the perforated bin, the suburbs' the old can")


## Props by kind and place (the new pieces keep the old kinds), buildings, trash cans, parked cars.
func _signature(chunk: CityChunk) -> Array:
	var out: Array = []
	for c in chunk.get_children():
		if c is Building or c is TrashCan or c is Vehicle:
			var p: Vector3 = (c as Node3D).position
			out.append("%s %.2f %.2f" % [c.get_class(), p.x, p.z])
	for car in chunk.get("_cars"):
		if is_instance_valid(car):
			var p: Vector3 = (car as Node3D).position
			out.append("car %.2f %.2f" % [p.x, p.z])
	for r in chunk.prop_records:
		if String(r.kind) != "cart":
			out.append("%s %s %.2f %.2f" % [r.id, r.kind, (r.position as Vector3).x, (r.position as Vector3).z])
	out.sort()
	return out


func _batch_material_ok(chunk: CityChunk, key: String) -> bool:
	var node := chunk.get_node_or_null("Batch_" + key) as MultiMeshInstance3D
	return node != null and node.multimesh.mesh.surface_get_material(0) == StreetFurniture.material()


func _free(chunk: CityChunk) -> void:
	chunk.get_parent().remove_child(chunk)
	chunk.free()


func _downtown(city: Node3D, plan: CityPlan) -> void:
	var centre := plan.block_index_at(plan.macro.downtown_center if plan.macro else Vector2.ZERO)
	var found: CityChunk = null
	var key := Vector2i.ZERO
	var tries := 0
	for r in 4:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if found != null or tries >= 8 or maxi(absi(dx), absi(dz)) != r:
					continue
				var k := centre + Vector2i(dx, dz)
				var b := plan.block(k.x, k.y)
				if b.has("site") or plan.zone_at((b.rect as Rect2).get_center()) != MacroMap.Zone.CITY:
					continue
				tries += 1
				var ch: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
				ch.build()
				var meters := 0
				for rec: Dictionary in ch.prop_records:
					if String(rec.kind) == "meter":
						meters += 1
				if meters >= 6:
					found = ch
					key = k
				else:
					_free(ch)
	_t._check(found != null, "a metered downtown block builds")
	if found == null:
		return
	var has_meter := _batch_material_ok(found, "meter")
	_t._check(has_meter, "its meters are a batch on the furniture shader")
	var sig := _signature(found)
	_free(found)
	StreetFurniture.enabled = false
	var bare: CityChunk = city._new_chunk(key, CityChunk.Level.FULL)
	bare.build()
	StreetFurniture.enabled = true
	var bare_sig := _signature(bare)
	_free(bare)
	_t._check(sig == bare_sig, "the furniture moves nothing in a downtown block: built with the old meshes it is the same block (%d vs %d entries)" % [sig.size(), bare_sig.size()])


func _carts(city: Node3D, plan: CityPlan) -> void:
	var key := Vector2i(99999, 99999)
	for r in range(2, 40):
		for dz in range(-r, r + 1, 3):
			for dx in range(-r, r + 1, 3):
				if key.x != 99999 or maxi(absi(dx), absi(dz)) != r:
					continue
				var b := plan.block(dx, dz)
				var c: Vector2 = (b.rect as Rect2).get_center()
				if b.has("site") or b.has("grounds") or plan.zone_at(c) != MacroMap.Zone.CITY or plan.district_at(c) != CityPlan.District.SUBURBS:
					continue
				if plan.river_block(dx, dz) or plan.marina_block(dx, dz):
					continue
				key = Vector2i(dx, dz)
	_t._check(key.x != 99999, "a suburban block to put carts out on")
	if key.x == 99999:
		return
	StreetFurniture.force_carts = true
	var chunk: CityChunk = city._new_chunk(key, CityChunk.Level.FULL)
	chunk.build()
	var carts: Array = []
	for rec: Dictionary in chunk.prop_records:
		if String(rec.kind) == "cart":
			carts.append(rec)
	var ids_ok := true
	for i in carts.size():
		ids_ok = ids_ok and String(carts[i].id) == "cart_%d" % i and (carts[i].shapes as Array).size() == 1
	_t._check(carts.size() >= 4 and ids_ok and _batch_material_ok(chunk, "cart"),
		"collection day: %d carts at the kerb as props with ids of their own, one batch on the furniture shader" % carts.size())
	var sig := _signature(chunk)
	# A broken cart stays broken across a rebuild.
	if not carts.is_empty():
		chunk.break_prop(carts[0])
	_free(chunk)
	var again: CityChunk = city._new_chunk(key, CityChunk.Level.FULL)
	again.build()
	var gone := true
	for rec: Dictionary in again.prop_records:
		if String(rec.kind) == "cart" and String(rec.id) == "cart_0":
			gone = false
	_t._check(carts.is_empty() or gone, "a smashed cart stays gone when its chunk is rebuilt")
	_free(again)
	StreetFurniture.force_carts = false
	var quiet: CityChunk = city._new_chunk(key, CityChunk.Level.FULL)
	StreetFurniture.enabled = false
	quiet.build()
	StreetFurniture.enabled = true
	var quiet_sig := _signature(quiet)
	_free(quiet)
	_t._check(sig == quiet_sig, "the carts roll nothing from the block: built without the furniture it is the same block")
