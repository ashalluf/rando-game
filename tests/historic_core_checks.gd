extends RefCounted
## Downtown's historic core (HistoricCore, HistoricFacade), for tests/smoke_test.gd. Loaded at run
## time, not named there, so it compiles after the autoloads.
##
## Checks the table (invented names only), the placement (every dressed lot fronts Spring St or
## Main St between 2nd and 9th St, none of Broadway's), then builds a historic block FULL and
## checks each beaux-arts building: a slab filling its lot under the 150 ft limit, punched windows,
## bronze shop frames, no kit surround, the two ornament meshes on the right materials, a cornice
## ledge, the entrance's lamp; the LOD build's far cornice boxes; and built with the feature off,
## the block's other buildings, trash cans and street props are where they were.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_table()
	var blocks := _placement(plan)
	_shader()
	if blocks.is_empty():
		_t._check(false, "the historic core has blocks to build")
		return
	_full_block(city, plan, blocks[blocks.size() / 2])
	_lod_block(city, blocks[0])


func _table() -> void:
	var real := ["BRADBURY", "HELLMAN", "BRALY", "VAN NUYS", "HUNTINGTON", "STIMSON", "DOUGLAS", "SECURITY",
		"FARMERS", "CONTINENTAL", "TITLE GUARANTEE", "ROWAN", "PERSHING", "BARCLAY", "CORONADO", "PACIFIC",
		"CROCKER", "WELLS", "CHASE", "UNION BANK", "BANK OF AMERICA", "ORPHEUM", "EASTERN", "HAYWARD"]
	var clean := true
	var seen := {}
	for n: String in HistoricCore.NAMES:
		seen[n] = true
		for r: String in real:
			clean = clean and n.find(r) < 0
	_t._check(clean and seen.size() == HistoricCore.NAMES.size(), "the historic core's names are invented and unique (%d)" % seen.size())


## Every historic block of the plan (Vector2i), checking each dressed lot as it goes.
func _placement(plan: CityPlan) -> Array:
	var zr := HistoricCore.z_range()
	var out: Array = []
	var lots := 0
	var ok := zr.y > zr.x + 1000.0
	for name: String in HistoricCore.AVENUES:
		var av := HistoricCore.avenue(name)
		ok = ok and not av.is_empty()
		if av.is_empty():
			continue
		var z := zr.x + 5.0
		while z < zr.y:
			for side: float in [-1.0, 1.0]:
				var bi := plan.block_index_at(Vector2(float(av[0]) + side * 30.0, z))
				if out.has(bi) or HistoricCore.block_fronts(plan, bi.x, bi.y).is_empty():
					continue
				out.append(bi)
				for lot: Dictionary in plan.lots(bi.x, bi.y):
					var spec := HistoricCore.spec_for(plan, bi.x, bi.y, lot)
					if spec.is_empty():
						continue
					lots += 1
					var c: Vector2 = lot.center
					ok = ok and c.y > zr.x - 120.0 and c.y < zr.y + 120.0
					ok = ok and HistoricCore.AVENUES.has(spec.avenue) and HistoricCore.NAMES.has(spec.name)
					ok = ok and not HistoricCore.street_faces(plan, bi.x, bi.y, lot).is_empty()
			z += 40.0
	_t._check(ok and lots >= 30 and out.size() >= 10,
		"the historic core: %d lots on %d blocks fronting Spring St and Main St between 2nd and 9th St" % [lots, out.size()])
	return out


func _shader() -> void:
	var sh: Shader = load("res://shaders/historic_lamp.gdshader")
	var src := FileAccess.get_file_as_string("res://shaders/historic_lamp.gdshader")
	var bsrc := FileAccess.get_file_as_string("res://shaders/building.gdshader")
	_t._check(sh != null and sh.get_shader_uniform_list().size() >= 3 and src.contains("lamp_factor") and src.contains("cs_out(")
		and bsrc.contains("uniform int shop_frame_force"), "historic_lamp loads; building.gdshader takes the forced shop frame")


func _historic(chunk: CityChunk) -> Array:
	var out: Array = []
	for c in chunk.get_children():
		if c is Building and (c as Node).has_meta("historic"):
			out.append(c)
	return out


func _full_block(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var tris0 := LandmarkGeo.committed_triangles
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var tris := LandmarkGeo.committed_triangles - tris0
	var hist := _historic(chunk)
	var ok := not hist.is_empty()
	var ornate := 0
	var lamps := 0
	var ledges := 0
	var why := ""
	for b: Building in hist:
		var spec: Dictionary = b.get_meta("historic")
		var shape_ok: bool = b.shape == Building.Shape.SLAB and b.height <= 46.5 and b.window_style == Building.WindowStyle.PUNCHED \
			and b.shop_frame_force == 1 and b.parts.size() == 1
		if not shape_ok and why == "":
			why = "shape %d h %.1f win %d parts %d" % [b.shape, b.height, b.window_style, b.parts.size()]
		ok = ok and shape_ok
		var node := b.get_node_or_null("Historic")
		if node == null:
			if why == "":
				why = "no ornament on %s" % spec.name
			ok = false
			continue
		var main := node.get_node_or_null("HistoricMain") as MeshInstance3D
		var fine := node.get_node_or_null("HistoricFine") as MeshInstance3D
		var mats := main != null and fine != null and main.mesh != null and fine.mesh != null \
			and main.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
			and fine.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
			and main.visibility_range_end > 0.0 and fine.visibility_range_end > 0.0
		if mats:
			var lamp_mat := false
			for s in fine.mesh.get_surface_count():
				var m := fine.mesh.surface_get_material(s) as ShaderMaterial
				if m and m.shader and m.shader.resource_path.ends_with("historic_lamp.gdshader"):
					lamp_mat = true
			for c in node.get_children():
				if c is OmniLight3D and (c as Node).is_in_group("lamp_light") and lamp_mat:
					lamps += 1
			ornate += 1
		ok = ok and mats
		if b.get_node_or_null("HistoricLedge") != null:
			ledges += 1
	_t._check(ok and ornate == hist.size() and ledges == hist.size() and lamps >= 1 and tris > 2000 * hist.size(),
		"block %s: %d beaux-arts buildings, each a slab with its ornament (%d triangles), ledges, %d lit entrances %s" % [k, hist.size(), tris, lamps, why])
	print("HISTORIC longest ornament build step %.1f ms" % (float(HistoricCore.max_step_us) / 1000.0))
	# Off: the rest of the block is where it was.
	var sig := _signature(chunk)
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	HistoricCore.enabled = false
	var bare: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	bare.build()
	HistoricCore.enabled = true
	var bare_sig := _signature(bare)
	var none := _historic(bare).is_empty()
	if bare_sig != sig:
		var only_on := sig.filter(func(x: String) -> bool: return not bare_sig.has(x))
		var only_off := bare_sig.filter(func(x: String) -> bool: return not sig.has(x))
		printerr("HISTORIC same-block diff: with %s ... without %s" % [str(only_on.slice(0, 6)), str(only_off.slice(0, 6))])
	_t._check(none and bare_sig == sig and not sig.is_empty(),
		"the historic core rolls nothing from the block: built without it, the same street props and trash cans (%d)" % sig.size())
	bare.get_parent().remove_child(bare)
	bare.free()


func _lod_block(city: Node3D, k: Vector2i) -> void:
	var counts: Array[int] = []
	for on: bool in [true, false]:
		HistoricCore.enabled = on
		var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.LOD)
		chunk.build()
		var lod := chunk.get_node_or_null("Batch_lod_box") as MultiMeshInstance3D
		counts.append(lod.multimesh.instance_count if lod else 0)
		chunk.get_parent().remove_child(chunk)
		chunk.free()
	HistoricCore.enabled = true
	_t._check(counts[0] > counts[1] and counts[1] > 0, "far: the historic block's cornices and belts as far boxes (%d boxes, %d without)" % [counts[0], counts[1]])


func _signature(chunk: CityChunk) -> Array:
	# The historic lots are the feature: what is compared is the street (lamps, signals, poles,
	# hydrants, ...) and the trash cans; the lots' own forecourt furniture follows the buildings.
	var plan := chunk.plan
	var own: Array[Rect2] = []
	for lot: Dictionary in plan.lots(chunk.ix, chunk.iz):
		if HistoricCore.lot_avenue(plan, chunk.ix, chunk.iz, lot) != "":
			var c: Vector2 = lot.center
			var sz: Vector2 = lot.size
			own.append(Rect2(c - sz * 0.5, sz).grow(1.0))
	var mine := func(q: Vector2) -> bool:
		for r: Rect2 in own:
			if r.has_point(q):
				return true
		return false
	var out: Array = []
	for c in chunk.get_children():
		if c is TrashCan:
			var p: Vector3 = (c as Node3D).position
			out.append("%s %.2f %.2f" % [c.get_class(), p.x, p.z])
		elif c is Building:
			var p: Vector3 = (c as Node3D).position
			if not mine.call(Vector2(p.x, p.z)):
				out.append("Building %.2f %.2f" % [p.x, p.z])
	for r in chunk.prop_records:
		var q: Vector3 = r.position
		if String(r.kind) in ["bench", "bollard", "planter", "aboard", "cafe"]:
			continue
		if mine.call(Vector2(q.x, q.z)):
			continue
		out.append("%s %.2f %.2f" % [r.kind, q.x, q.z])
	out.sort()
	return out
