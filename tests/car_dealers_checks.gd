extends RefCounted
## Car dealerships (CarDealers), for tests/smoke_test.gd. Loaded at run time, not named there, so
## it compiles after the autoloads.
##
## Checks the tables (six invented brands with six distinct marks, the sign shader draws every
## one), the placement (auto rows exist round the start in both kinds, every site in a dealer
## district, inside its block's lots, clear of the freeways, its anchor one of its own lots, the
## same answer when asked again from a cold cache), then builds FULL chunks with a new-car dealer
## and a used lot and checks: the dealer node, the lot cars as unbreakable props on their batches
## with a price sticker each, the tube men on their shader, real Vehicles for sale in the front
## row and on the showroom floor, and the block built with the dealers off is the same block
## outside the site (hash-seeded: no roll moved); and a LOD chunk draws the site as far boxes.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_tables()
	var sites := _sites(plan)
	var new_k := Vector2i(99999, 0)
	var used_k := Vector2i(99999, 0)
	for k: Vector2i in sites:
		var s: Dictionary = sites[k]
		if s.used and used_k.x == 99999:
			used_k = k
		if not s.used and new_k.x == 99999 and float((s.frame as Dictionary).len) >= 40.0:
			new_k = k
	_t._check(sites.size() >= 6 and new_k.x != 99999 and used_k.x != 99999,
		"auto rows hold new-car dealers and used lots round the start (%d sites)" % sites.size())
	if new_k.x != 99999:
		_chunk(city, plan, new_k, false)
	if used_k.x != 99999:
		_chunk(city, plan, used_k, true)
		_lod(city, plan, used_k)


func _tables() -> void:
	var marks := {}
	var names := {}
	for b: Array in CarDealers.BRANDS:
		marks[int(b[1])] = true
		names[String(b[0])] = true
	_t._check(marks.size() == CarDealers.BRANDS.size() and names.size() == CarDealers.BRANDS.size(),
		"every brand has its own name and its own mark")
	var src := FileAccess.get_file_as_string("res://shaders/dealer_sign.gdshader")
	var drawn := 0
	for m in CarDealers.BRANDS.size() - 1:
		if src.contains("mark == %d" % m):
			drawn += 1
	_t._check(drawn == CarDealers.BRANDS.size() - 1, "dealer_sign.gdshader draws every brand's mark (the last as its fallback)")


## Every dealer site within ~1.6 km of the start, checked as it is found.
func _sites(plan: CityPlan) -> Dictionary:
	var out := {}
	var ok_district := true
	var ok_inside := true
	var ok_freeway := true
	var ok_anchor := true
	for ix in range(-14, 15):
		for iz in range(-16, 17):
			var s := CarDealers.site(plan, ix, iz)
			if s.is_empty():
				continue
			out[Vector2i(ix, iz)] = s
			var b := plan.block(ix, iz)
			ok_district = ok_district and CarDealers.DISTRICTS.has(int(b.district)) and int(b.kind) == CityPlan.BlockKind.BUILDINGS
			var inner: Rect2 = (b.rect as Rect2).grow(-plan.sidewalk_width + 0.05)
			ok_inside = ok_inside and inner.encloses(s.rect)
			if plan.macro.freeway:
				ok_freeway = ok_freeway and not plan.macro.freeway.blocks_rect(s.rect, 3.0)
			var seeds: Array = []
			for lot: Dictionary in plan.lots(ix, iz):
				seeds.append(int(lot.seed))
			for sd: int in s.lots:
				ok_anchor = ok_anchor and seeds.has(sd)
			ok_anchor = ok_anchor and (s.lots as Array).has(int(s.anchor))
	_t._check(ok_district, "every dealer stands on a buildings block in a dealer district")
	_t._check(ok_inside, "every dealer site is inside its block's pavement ring")
	_t._check(ok_freeway, "no dealer site is under a freeway")
	_t._check(ok_anchor, "a dealer claims only its block's own lots, and is built by one of them")
	# Pure: a cold cache gives the same sites.
	var before := {}
	for k: Vector2i in out:
		before[k] = [out[k].rect, out[k].lots, out[k].name]
	CarDealers._cache.clear()
	var same := true
	for k: Vector2i in before:
		var s := CarDealers.site(plan, k.x, k.y)
		same = same and not s.is_empty() and [s.rect, s.lots, s.name] == before[k]
	_t._check(same, "the dealer sites are worked out the same way every time (hashes, no state)")
	return out


func _chunk(city: Node3D, plan: CityPlan, k: Vector2i, used: bool) -> void:
	var s := CarDealers.site(plan, k.x, k.y)
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	# The real cars are skipped while PhysicsBudget is full, and in the full smoke test the checks
	# before this one leave it full: give this build room (the budget is not what is checked here).
	var budget: Node = _t.get_tree().root.get_node_or_null("PhysicsBudget")
	var cap: int = int(budget.get("max_active_bodies")) if budget else 0
	if budget:
		budget.set("max_active_bodies", maxi(cap, int(budget.call("active_body_count")) + 64))
	chunk.build()
	if budget:
		budget.set("max_active_bodies", cap)
	var node: Node3D = null
	for c in chunk.get_children():
		if c.is_in_group("car_dealer"):
			node = c
	_t._check(node != null and node.get_node_or_null("Dealer") != null, "the %s dealer (%s) is built in its chunk" % ["used" if used else "new", s.name])
	var cars := 0
	var tough := true
	for r: Dictionary in chunk.prop_records:
		if String(r.kind) == "dealer_car":
			cars += 1
			tough = tough and float(r.health) > 1e9 and not (r.shapes as Array).is_empty()
	var stickers := 0
	var tube_ok := false
	for c in chunk.get_children():
		if c is MultiMeshInstance3D:
			var mmi := c as MultiMeshInstance3D
			if String(mmi.name) == "Batch_dl_sticker":
				stickers = mmi.multimesh.instance_count
			if String(mmi.name) == "Batch_dl_tube":
				var mat := mmi.multimesh.mesh.surface_get_material(0) as ShaderMaterial
				tube_ok = mat != null and mat.shader.resource_path.ends_with("tube_man.gdshader") and mmi.multimesh.instance_count >= 1
	var real := 0
	for car in chunk.get("_cars"):
		if is_instance_valid(car) and (car as Node).has_meta("for_sale"):
			real += 1
	_t._check(cars + real >= 8 and cars >= 1 and tough, "the lot is packed with cars, the ones behind the front row props that rounds spark off and never break (%d + %d real)" % [cars, real])
	_t._check(stickers == cars, "every lot car has its price on the windscreen (%d stickers, %d cars)" % [stickers, cars])
	_t._check(tube_ok, "a tube man dances on the lot (tube_man.gdshader)")
	var for_sale := 0
	for car in chunk.get("_cars"):
		if is_instance_valid(car) and (car as Node).has_meta("for_sale"):
			for_sale += 1
	_t._check(for_sale >= 1, "real cars for sale stand on the lot%s (%d)" % ["" if used else " and the showroom floor", for_sale])
	if not used:
		var lit := false
		for c in node.get_children():
			lit = lit or (c is OmniLight3D and c.is_in_group("lamp_light"))
		_t._check(lit, "the showroom has its light for the night, with the street lamps")
	# Off, the same block outside the site and the pavement in front of it (a shop's A-frame or
	# cafe table stands there only while its shop does).
	var r: Rect2 = (s.rect as Rect2).grow(plan.sidewalk_width + 1.0)
	var sig := _signature(chunk, r)
	chunk.get_parent().remove_child(chunk)
	_free(chunk)
	CarDealers.enabled = false
	CarDealers._cache.clear()
	var bare: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	bare.build()
	CarDealers.enabled = true
	CarDealers._cache.clear()
	var bare_sig := _signature(bare, r)
	if OS.get_environment("DIFF") == "1":
		for x in sig:
			if not bare_sig.has(x):
				print("ONLY WITH ", x)
		for x in bare_sig:
			if not sig.has(x):
				print("ONLY WITHOUT ", x)
	_t._check(bare_sig == sig, "a dealer rolls nothing from its block: built without it the rest of the block is the same (%d / %d things)" % [sig.size(), bare_sig.size()])
	bare.get_parent().remove_child(bare)
	_free(bare)


func _lod(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.LOD)
	chunk.build()
	var boxes := 0
	for c in chunk.get_children():
		if c is MultiMeshInstance3D and String(c.name) == "Batch_lod_box":
			boxes = (c as MultiMeshInstance3D).multimesh.instance_count
	CarDealers.enabled = false
	CarDealers._cache.clear()
	var bare: CityChunk = city._new_chunk(k, CityChunk.Level.LOD)
	bare.build()
	CarDealers.enabled = true
	CarDealers._cache.clear()
	var bare_boxes := 0
	for c in bare.get_children():
		if c is MultiMeshInstance3D and String(c.name) == "Batch_lod_box":
			bare_boxes = (c as MultiMeshInstance3D).multimesh.instance_count
	_t._check(boxes > 0, "a LOD chunk draws the dealer as far boxes (%d boxes, %d without it)" % [boxes, bare_boxes])
	for ch: CityChunk in [chunk, bare]:
		ch.get_parent().remove_child(ch)
		_free(ch)


func _free(chunk: CityChunk) -> void:
	for car in chunk.get("_cars"):
		if is_instance_valid(car):
			(car as Node).free()
	chunk.get("_cars").clear()
	chunk.free()


## What a chunk built outside rect `r`: buildings, houses' bodies, props, and the kerb's parked cars.
func _signature(chunk: CityChunk, r: Rect2) -> Array:
	var out: Array = []
	for c in chunk.get_children():
		if c is Building or c is TrashCan:
			var p: Vector3 = (c as Node3D).position
			if not r.has_point(Vector2(p.x, p.z)):
				out.append("%s %.2f %.2f" % [c.get_class(), p.x, p.z])
	for rec in chunk.prop_records:
		var p: Vector3 = rec.position
		if String(rec.kind) != "dealer_car" and not r.has_point(Vector2(p.x, p.z)):
			out.append("%s %.2f %.2f" % [rec.kind, p.x, p.z])
	for car in chunk.get("_cars"):
		if is_instance_valid(car) and not (car as Node).has_meta("for_sale"):
			var p: Vector3 = (car as Node3D).position
			out.append("car %.1f %.1f" % [p.x, p.z])
	out.sort()
	return out
