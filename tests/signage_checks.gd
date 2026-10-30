extends RefCounted
## Boulevard signs (BoulevardSigns, SignKit), for tests/smoke_test.gd. Loaded at run time, not
## named there, so it compiles after the autoloads.
##
## Checks the atlas grid (the script's, the generated table's and the shader's FAMS agree, the
## atlas is the size they assume), that the pole-sign plan is pure and finds every kind round
## midtown, then builds a FULL midtown chunk with pole signs and checks: the signs are breakable
## props on the sign shader in one batch per kind, drawn to POLE_DRAW; vinyl, plates and posts
## were laid; the block built with the signs off is the same block (every earlier prop at the same
## place in the same order: the signs roll nothing and come last); and a LOD chunk of a block with
## a tall sign gets its far boxes (a lit PANEL and a MAST each) and nothing else.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_tables()
	var found := _find(plan, Vector2(600.0, 1650.0), 700.0)
	_t._check(found.kinds.size() == BoulevardSigns.Pole.size(),
		"midtown's boulevards carry every kind of pole sign (%s)" % str(found.kinds))
	var k: Vector2i = found.block
	if k.x == 99999:
		return
	var p1 := BoulevardSigns.plan_poles(plan, k.x, k.y)
	var p2 := BoulevardSigns.plan_poles(plan, k.x, k.y)
	_t._check(str(p1) == str(p2) and not p1.is_empty(), "the pole-sign plan is pure (%d signs on block %s)" % [p1.size(), str(k)])
	_full_chunk(city, plan, k)
	if found.tall.x != 99999:
		_lod_chunk(city, found.tall)


func _tables() -> void:
	var ok := BoulevardSigns.FAMILIES.size() == SignArtTable.FAMILIES.size()
	var src := FileAccess.get_file_as_string("res://shaders/boulevard_sign.gdshader")
	for fam: String in BoulevardSigns.FAMILIES:
		var f: Array = BoulevardSigns.FAMILIES[fam]
		ok = ok and SignArtTable.FAMILIES.has(fam) and str(SignArtTable.FAMILIES[fam]) == str(f)
		ok = ok and src.contains("vec4(%d.0, %d.0, %d.0, %d.0)" % [f[0], f[1], f[2], f[3]])
	_t._check(ok, "the sign atlas grid agrees in BoulevardSigns, SignArtTable and boulevard_sign.gdshader")
	var tex: Texture2D = load("res://assets/textures/boulevard_signs/sign_atlas.png")
	_t._check(tex != null and tex.get_width() == 2048 and tex.get_height() == 3072, "the sign atlas is 2048 x 3072")
	_t._check(SignArtTable.TENANT_MEAN.size() == 24 and SignArtTable.NAME_MEAN.size() == 12, "the far colours cover every pylon header and sign head")


## A midtown block with pole signs near `c`, every kind seen, and a block with a tall one.
func _find(plan: CityPlan, c: Vector2, reach: float) -> Dictionary:
	var out := {"block": Vector2i(99999, 0), "tall": Vector2i(99999, 0), "kinds": {}}
	var start: Vector2i = plan.block_index_at(c)
	var span := int(reach / 60.0) + 2
	var best := 0
	for ix in range(start.x - span, start.x + span + 1):
		for iz in range(start.y - span, start.y + span + 1):
			if (plan.block(ix, iz).rect as Rect2).get_center().distance_to(c) > reach:
				continue
			var poles := BoulevardSigns.plan_poles(plan, ix, iz)
			var tall := false
			for p: Dictionary in poles:
				out.kinds[int(p.kind)] = true
				tall = tall or int(p.kind) == BoulevardSigns.Pole.MOTEL or int(p.kind) == BoulevardSigns.Pole.TENANT
			if poles.size() > best:
				best = poles.size()
				out.block = Vector2i(ix, iz)
			if tall and (out.tall as Vector2i).x == 99999:
				out.tall = Vector2i(ix, iz)
	return out


func _full_chunk(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var counts: Dictionary = chunk.get_meta("boulevard_signs", {})
	var poles := 0
	for r: Dictionary in chunk.prop_records:
		if String(r.kind) == "pole_sign":
			poles += 1
	_t._check(poles > 0 and poles == int(counts.get("pole", -1)), "a midtown block's pole signs stand as street props (%d)" % poles)
	var nodes := 0
	var on_shader := true
	var drawn := true
	for c in chunk.get_children():
		if c is MultiMeshInstance3D and (String(c.name).begins_with("Batch_sg_tenant") or String(c.name).begins_with("Batch_sg_motel")
				or String(c.name).begins_with("Batch_sg_box") or String(c.name).begins_with("Batch_sg_tire")):
			nodes += 1
			on_shader = on_shader and (c as MultiMeshInstance3D).multimesh.mesh.surface_get_material(0) == SignKit.material()
			drawn = drawn and absf((c as MultiMeshInstance3D).visibility_range_end - BoulevardSigns.POLE_DRAW) < 0.5
	_t._check(nodes > 0 and on_shader and drawn, "pole signs are batches on the sign shader drawn to %d m (%d batches)" % [int(BoulevardSigns.POLE_DRAW), nodes])
	_t._check(int(counts.get("post", 0)) > 0 and int(counts.get("plate", 0)) >= int(counts.get("post", 0)),
		"the kerbs carry posts of parking plates (%d posts, %d plates)" % [int(counts.get("post", 0)), int(counts.get("plate", 0))])
	print("SIGNAGE counts on block %s: %s" % [str(k), str(counts)])
	# Off, the same block: every other prop at the same place (ours are marked "sg"; the
	# billboards commit in a deferred step, so the order of the last few differs).
	var before: Array = []
	var ours := 0
	for r: Dictionary in chunk.prop_records:
		if r.get("sg", false):
			ours += 1
			continue
		before.append("%s %.2f %.2f" % [r.kind, (r.position as Vector3).x, (r.position as Vector3).z])
	before.sort()
	var buildings := _buildings(chunk)
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	BoulevardSigns.enabled = false
	var bare: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	bare.build()
	BoulevardSigns.enabled = true
	var after: Array = []
	for r: Dictionary in bare.prop_records:
		after.append("%s %.2f %.2f" % [r.kind, (r.position as Vector3).x, (r.position as Vector3).z])
	after.sort()
	_t._check(ours > 0 and after == before and _buildings(bare) == buildings,
		"the signs roll nothing from the block: built without them it is the same block (%d props of ours)" % ours)
	bare.get_parent().remove_child(bare)
	bare.free()


func _buildings(chunk: CityChunk) -> Array:
	var out: Array = []
	for c in chunk.get_children():
		if c is Building or c is TrashCan:
			out.append("%.2f %.2f" % [(c as Node3D).position.x, (c as Node3D).position.z])
	out.sort()
	return out


func _lod_chunk(city: Node3D, k: Vector2i) -> void:
	var with: CityChunk = city._new_chunk(k, CityChunk.Level.LOD)
	with.build()
	var n_with := _lod_boxes(with)
	with.get_parent().remove_child(with)
	with.free()
	BoulevardSigns.enabled = false
	var without: CityChunk = city._new_chunk(k, CityChunk.Level.LOD)
	without.build()
	BoulevardSigns.enabled = true
	var n_without := _lod_boxes(without)
	without.get_parent().remove_child(without)
	without.free()
	var tall := 0
	for p: Dictionary in BoulevardSigns.plan_poles(city.plan, k.x, k.y):
		if int(p.kind) == BoulevardSigns.Pole.MOTEL or int(p.kind) == BoulevardSigns.Pole.TENANT:
			tall += 1
	_t._check(tall > 0 and n_with - n_without == tall * 2, "a LOD chunk keeps each tall pole sign as a lit head and a mast (%d signs, %d boxes)" % [tall, n_with - n_without])


func _lod_boxes(chunk: CityChunk) -> int:
	for c in chunk.get_children():
		if c is MultiMeshInstance3D and String(c.name) == "Batch_lod_box":
			return (c as MultiMeshInstance3D).multimesh.instance_count
	return 0
