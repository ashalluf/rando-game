extends RefCounted
## Street furniture (StreetFurniture), for tests/smoke_test.gd. Loaded at run time, not named
## there, so it compiles after the autoloads.
##
## Checks the meshes (every piece builds on the furniture shader inside its triangle budget, at
## real size, with a shadow twin), the shader's copy of the kinds, the ad atlas's rows, the pure
## rolls (pay station and stop-bench shares, the hydrant facing the street, the bin by district),
## then builds metered downtown blocks: the new pieces are batches on the furniture shader, every
## bus stop keeps its shelter, the stop benches are props with ids of their own standing by a
## shelter and stay gone once smashed, and the same block built with the furniture off is the same
## block (the same props by id, kind and place, buildings, trash cans, parked cars, camp pieces
## and kerb rows).

var _t: Node
## StreetFurniture's script, for the calls by name (a class cannot be .call()ed).
var _sf: GDScript = load("res://scripts/world/street_furniture.gd")

## Most triangles a piece may have at its finest level.
const BUDGET := {"hydrant": 5200, "meter": 2600, "pay_station": 2600, "ad_bench": 900, "mesh_bin": 4200, "bike_rack": 1000, "planter": 900}
## Height ranges (m) each piece must stand to: real sizes.
const HEIGHTS := {"hydrant": Vector2(0.55, 0.7), "meter": Vector2(1.4, 1.55), "pay_station": Vector2(2.0, 2.3), "ad_bench": Vector2(0.95, 1.15), "mesh_bin": Vector2(0.95, 1.1), "bike_rack": Vector2(0.85, 0.95), "planter": Vector2(0.45, 0.52)}


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_meshes()
	_shader()
	_rolls(plan)
	_downtown(city, plan)


func _meshes() -> void:
	var ok := true
	var sizes := true
	var report := []
	for name: String in BUDGET:
		var m: Mesh = _sf.call(name)
		var tris := 0
		if m and m.get_surface_count() == 1:
			tris = (m.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var this_ok := m != null and m.get_surface_count() == 1 and m.surface_get_material(0) == StreetFurniture.material() and tris > 40 and tris <= int(BUDGET[name])
		if not this_ok:
			report.append("BAD %s" % name)
		ok = ok and this_ok
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
		same = same and int(_sf.get(k)) == int(consts[k]) and src.contains("const float %s = %d.0;" % [k, int(consts[k])])
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
		if _sf.call("_h01", [plan.seed, "stop_bench", roundi(at.x), roundi(at.z)]) < StreetFurniture.STOP_BENCH_SHARE:
			benches += 1
	_t._check(absf(float(pays) / n - StreetFurniture.PAY_STATION_SHARE) < 0.07, "about %d %% of metered spaces are pay stations (%d of %d)" % [int(StreetFurniture.PAY_STATION_SHARE * 100.0), pays, n])
	_t._check(absf(float(benches) / n - StreetFurniture.STOP_BENCH_SHARE) < 0.08, "about a third of the bus shelters get an ad bench beside them (%d of %d)" % [benches, n])
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
		if c is Building or c is TrashCan or c is Vehicle or c is EncampmentItem:
			var p: Vector3 = (c as Node3D).position
			out.append("%s %.2f %.2f" % [c.get_class(), p.x, p.z])
	for car in chunk.get("_cars"):
		if is_instance_valid(car):
			var p: Vector3 = (car as Node3D).position
			out.append("car %.2f %.2f" % [p.x, p.z])
	# The camps and the kerb rows: the passes that keep clear of the props.
	var data: Dictionary = chunk._batch.data()
	for k: String in data:
		if k.begins_with("camp_") or k.begins_with("kerb") or k.begins_with("vend_"):
			out.append("batch %s %d" % [k, (data[k].xforms as Array).size()])
	for r in chunk.prop_records:
		if String(r.kind) != "ad_bench":
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
	var fallback: CityChunk = null
	var fallback_key := Vector2i.ZERO
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
				var bench := false
				for rec: Dictionary in ch.prop_records:
					if String(rec.kind) == "meter":
						meters += 1
					bench = bench or String(rec.kind) == "ad_bench"
				# The first metered block with a stop bench, else the first metered one.
				if meters >= 6 and (bench or fallback == null):
					if fallback != null and fallback != ch:
						_free(fallback)
					fallback = ch
					fallback_key = k
					if bench:
						found = ch
						key = k
				else:
					_free(ch)
	if found == null and fallback != null:
		found = fallback
		key = fallback_key
	_t._check(found != null, "a metered downtown block builds")
	if found == null:
		return
	var has_meter := _batch_material_ok(found, "meter")
	_t._check(has_meter, "its meters are a batch on the furniture shader")
	var stops: Array = []
	var benches: Array = []
	for rec: Dictionary in found.prop_records:
		if String(rec.kind) == "bus_stop":
			stops.append(rec)
		elif String(rec.kind) == "ad_bench":
			benches.append(rec)
	var shelters := true
	for rec: Dictionary in stops:
		var has_roof := false
		for inst in rec.instances:
			has_roof = has_roof or String(inst[0]) == "shelter_roof"
		shelters = shelters and has_roof
	_t._check(shelters, "every bus stop keeps its shelter (%d stops)" % stops.size())
	var near := true
	for i in benches.size():
		var b: Dictionary = benches[i]
		var by_stop := false
		for st: Dictionary in stops:
			by_stop = by_stop or (b.position as Vector3).distance_to(st.position) < 6.0
		near = near and by_stop and String(b.id) == "ad_bench_%d" % i and (b.shapes as Array).size() == 1
	_t._check(near and (benches.is_empty() or _batch_material_ok(found, "ad_bench")),
		"the stop benches (%d) stand by a shelter, ids of their own, one batch on the furniture shader" % benches.size())
	var sig := _signature(found)
	if not benches.is_empty():
		found.break_prop(benches[0])
	_free(found)
	if not benches.is_empty():
		var again: CityChunk = city._new_chunk(key, CityChunk.Level.FULL)
		again.build()
		var gone := true
		for rec: Dictionary in again.prop_records:
			gone = gone and String(rec.id) != "ad_bench_0"
		_t._check(gone, "a smashed stop bench stays gone when its chunk is rebuilt")
		_free(again)
	StreetFurniture.enabled = false
	var bare: CityChunk = city._new_chunk(key, CityChunk.Level.FULL)
	bare.build()
	StreetFurniture.enabled = true
	var bare_sig := _signature(bare)
	_free(bare)
	_t._check(sig == bare_sig, "the furniture moves nothing in a downtown block: built with the old meshes it is the same block (%d vs %d entries)" % [sig.size(), bare_sig.size()])
