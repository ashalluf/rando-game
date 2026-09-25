extends RefCounted
## Street-level wear (StreetWear: tags, buffs, posters, stickers), for tests/smoke_test.gd.
## Loaded at run time, not named there, so it compiles after the autoloads.
##
## Builds a few FULL downtown chunks and the chunks round Masjid Omar ibn Al-Khattab straight
## from the plan (city._new_chunk + build()) and checks: downtown walls, poles and cabinets carry
## wear as ONE batch on the wear shader, shadowless, faded out at its draw distance, within the
## per-chunk cap; nothing is laid within a place of worship's reach; and the block built with the
## wear off is the same block (hash-seeded, the chunk rng untouched). Placement points come from
## the chunk's "street_wear" meta, not the MultiMesh (instance transforms read back as identity
## under --headless).

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var per_district := [StreetWear.TAGS_PER_M, StreetWear.POSTERS_PER_M, StreetWear.STICKERS_PER_POLE, StreetWear.PILLAR_ODDS]
	var short := 0
	for table: Array in per_district:
		if table.size() != CityPlan.District.size():
			short += 1
	_t._check(short == 0, "every StreetWear per-district table covers all %d districts" % CityPlan.District.size())
	_downtown(city, plan)
	_worship(city, plan)


func _downtown(city: Node3D, plan: CityPlan) -> void:
	var centre := plan.block_index_at(Vector2(589.0, 860.0))
	var keys: Array[Vector2i] = []
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var k := centre + Vector2i(dx, dz)
			var b := plan.block(k.x, k.y)
			if int(b.district) == CityPlan.District.DOWNTOWN and int(b.kind) == CityPlan.BlockKind.BUILDINGS and not b.has("site") \
					and plan.zone_at((b.rect as Rect2).get_center()) == MacroMap.Zone.CITY and not plan.lots(k.x, k.y).is_empty():
				keys.append(k)
	_t._check(keys.size() >= 3, "downtown has blocks of buildings to wear (%d)" % keys.size())
	var total := 0
	var worst := 0
	var batch_ok := true
	var same := true
	for k in keys.slice(0, 3):
		var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
		chunk.build()
		var pts: PackedVector2Array = chunk.get_meta("street_wear", PackedVector2Array())
		total += pts.size()
		worst = maxi(worst, pts.size())
		var node := chunk.get_node_or_null("Batch_" + StreetWear.KEY) as MultiMeshInstance3D
		if pts.size() > 0:
			var mesh: Mesh = node.multimesh.mesh if node else null
			batch_ok = batch_ok and node != null and node.multimesh.instance_count == pts.size() and mesh.get_surface_count() == 1 \
				and mesh.surface_get_material(0) is ShaderMaterial \
				and node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
				and absf(node.visibility_range_end - StreetWear.DRAW_DISTANCE) < 0.5
		# Off, the same block: same buildings and props.
		var sig := _signature(chunk)
		chunk.get_parent().remove_child(chunk)
		chunk.free()
		StreetWear.enabled = false
		var bare: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
		bare.build()
		StreetWear.enabled = true
		same = same and _signature(bare) == sig and bare.get_node_or_null("Batch_" + StreetWear.KEY) == null
		bare.get_parent().remove_child(bare)
		bare.free()
	_t._check(total >= 40, "downtown blocks carry tags, posters and stickers (%d on 3 blocks)" % total)
	_t._check(batch_ok, "a chunk's wear is one shadowless batch on the wear shader, faded at %d m" % int(StreetWear.DRAW_DISTANCE))
	_t._check(worst <= StreetWear.MAX_PER_CHUNK, "wear stays within its per-chunk cap (%d)" % worst)
	_t._check(same, "the wear rolls nothing from the block: built without it, the block is the same")


## Buildings, props and trash cans of a chunk, by position (the crowd is left out: it is capped
## city-wide, so two builds of one block can seat different numbers of people).
func _signature(chunk: CityChunk) -> Array:
	var out: Array = []
	for c in chunk.get_children():
		if c is Building or c is TrashCan:
			var p: Vector3 = (c as Node3D).position
			out.append("%s %.2f %.2f" % [c.get_class(), p.x, p.z])
	for r in chunk.prop_records:
		out.append("%s %.2f %.2f" % [r.kind, (r.position as Vector3).x, (r.position as Vector3).z])
	out.sort()
	return out


func _worship(city: Node3D, plan: CityPlan) -> void:
	var anchor := Vector2.INF
	var radius := 0.0
	for lm in Landmarks.all():
		if lm.id == "masjid_omar":
			anchor = lm.anchor
			radius = lm.radius
	_t._check(anchor != Vector2.INF and not StreetWear.allowed(anchor) and StreetWear.allowed(anchor + Vector2(radius + StreetWear.WORSHIP_MARGIN + 30.0, 0.0)),
		"no wear is allowed at a place of worship")
	if anchor == Vector2.INF:
		return
	var reach := radius + StreetWear.WORSHIP_MARGIN
	var centre := plan.block_index_at(anchor)
	var near := 0
	var built := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var k := centre + Vector2i(dx, dz)
			var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
			chunk.build()
			var pts: PackedVector2Array = chunk.get_meta("street_wear", PackedVector2Array())
			built += pts.size()
			for p in pts:
				if p.distance_to(anchor) < reach:
					near += 1
			chunk.get_parent().remove_child(chunk)
			chunk.free()
	_t._check(near == 0, "nothing painted or pasted within %d m of the masjid (%d placed round it, %d inside)" % [int(reach), built, near])
