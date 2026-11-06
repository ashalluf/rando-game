extends RefCounted
## Murals, ghost signs, painted crosswalks and cabinets (Murals), for tests/smoke_test.gd.
## Loaded at run time, not named there, so it compiles after the autoloads.
##
## Checks the per-district tables, the crosswalk rule (one per district, a hash), the instance
## encoding against half floats; builds FULL chunks round downtown and the freeway west of it
## (city._new_chunk + build()) until it has seen every kind - a big mural, a ghost sign or frieze,
## a painted crosswalk, a painted cabinet - and checks a chunk's paint is ONE shadowless batch on
## the mural shader, faded at its draw distance, within the cap, the cabinet wrap rides its prop,
## and the block built with the murals off is the same block (hash-seeded); and that nothing is
## painted round Masjid Omar ibn Al-Khattab. Placement points come from the chunk's "murals" meta
## (instance transforms read back as identity under --headless).

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var short := 0
	for table: Array in [Murals.PILLAR_ODDS, Murals.WALL_ODDS, Murals.FRIEZE_ODDS, Murals.CABINET_ODDS, Murals.CROSSWALK_ODDS, Murals.SCENE_WEIGHTS]:
		if table.size() != CityPlan.District.size():
			short += 1
	_t._check(short == 0, "every Murals per-district table covers all %d districts" % CityPlan.District.size())
	var rules_ok := true
	for d in CityPlan.District.size():
		var r := Murals.crosswalk_rule(plan, d)
		rules_ok = rules_ok and r >= -1 and r <= Murals.XWALK_FLOWERS and r == Murals.crosswalk_rule(plan, d)
	_t._check(rules_ok and Murals.crosswalk_rule(plan, CityPlan.District.INDUSTRIAL) == -1,
		"one crosswalk rule per district, from a hash (industrial keeps white bars)")
	# The instance data survives Compatibility's half floats: small integers and thousandths.
	var c := Murals.custom(Murals.MODE_FRIEZE, 5, 0.6789, 15.0, Murals.SUB_STEEL, 7)
	_t._check(c.r == 69.0 and c.a == 61.0 and absf(c.g - 0.679) < 0.0005 and c.b == 15.0, "mural instance codes are small exact numbers")
	var mat := Murals.material()
	_t._check(mat.shader != null and mat.render_priority == -1 and mat.get_shader_parameter("ghost_atlas") != null,
		"the mural material: its shader, the ghost-sign atlas, drawn before the street wear")
	_t._check(Murals.cabinet_faces().size() == 4, "a cabinet is wrapped on all four sides")
	_city(city, plan)
	_worship(city, plan)


func _city(city: Node3D, plan: CityPlan) -> void:
	var centre := plan.block_index_at(plan.macro.downtown_center if plan.macro else Vector2(2800.0, 100.0))
	# Downtown's blocks, then the freeway's columns west of them (the 110).
	var keys: Array[Vector2i] = []
	for dz in range(-3, 3):
		for dx in range(-3, 3):
			keys.append(centre + Vector2i(dx, dz))
	for dz in range(-3, 2):
		for dx in range(-8, -5):
			keys.append(centre + Vector2i(dx, dz))
	var seen := {}
	var batch_ok := true
	var worst := 0
	var built := 0
	var wrap_ok := true
	var same := true
	var compared := 0
	for k in keys:
		if seen.size() >= 4 and built >= 6:
			break
		var b := plan.block(k.x, k.y)
		if plan.zone_at((b.rect as Rect2).get_center()) != MacroMap.Zone.CITY:
			continue
		var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
		chunk.build()
		built += 1
		var pts: PackedVector2Array = chunk.get_meta("murals", PackedVector2Array())
		var modes: Dictionary = chunk.get_meta("mural_modes", {})
		worst = maxi(worst, pts.size())
		var fresh := false
		for m: int in modes:
			var kind := "ghost" if m == Murals.MODE_GHOST or m == Murals.MODE_FRIEZE else str(m)
			if not seen.has(kind):
				fresh = true
			seen[kind] = true
		if pts.size() > 0:
			var node := chunk.get_node_or_null("Batch_" + Murals.KEY) as MultiMeshInstance3D
			var mesh: Mesh = node.multimesh.mesh if node else null
			batch_ok = batch_ok and node != null and node.multimesh.instance_count == pts.size() and mesh.get_surface_count() == 1 \
				and mesh.surface_get_material(0) == Murals.material() \
				and node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
				and absf(node.visibility_range_end - Murals.DRAW_DISTANCE) < 0.5
		if modes.has(Murals.MODE_WRAP):
			var found := false
			for r: Dictionary in chunk.prop_records:
				if String(r.kind) == "signal_cabinet":
					for inst: Array in r.instances:
						if inst[0] == Murals.KEY:
							found = true
			wrap_ok = wrap_ok and found
		# Off, the same block, for the first few that painted something.
		if fresh and compared < 3:
			compared += 1
			var sig := _signature(chunk)
			chunk.get_parent().remove_child(chunk)
			chunk.free()
			Murals.enabled = false
			var bare: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
			bare.build()
			Murals.enabled = true
			same = same and _signature(bare) == sig and bare.get_node_or_null("Batch_" + Murals.KEY) == null
			bare.get_parent().remove_child(bare)
			bare.free()
		else:
			chunk.get_parent().remove_child(chunk)
			chunk.free()
	var want := {"ghost": "a ghost sign or frieze", str(Murals.MODE_MURAL): "a big mural", str(Murals.MODE_CROSSWALK): "a painted crosswalk", str(Murals.MODE_WRAP): "a painted cabinet"}
	var missing: Array = []
	for k: String in want:
		if not seen.has(k):
			missing.append(want[k])
	_t._check(missing.is_empty(), "downtown and the 110 carry murals of every kind (%d chunks; missing %s)" % [built, missing])
	_t._check(batch_ok, "a chunk's murals are one shadowless batch on the mural shader, faded at %d m" % int(Murals.DRAW_DISTANCE))
	_t._check(worst <= Murals.MAX_PER_CHUNK, "murals stay within the per-chunk cap (%d)" % worst)
	_t._check(wrap_ok, "a painted cabinet's wrap rides the cabinet prop (it goes when the cabinet breaks)")
	_t._check(same and compared > 0, "the murals roll nothing from the block: built without them, the block is the same (%d compared)" % compared)


## Buildings, props and trash cans of a chunk, by position (as street_wear_checks.gd).
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
	if anchor == Vector2.INF:
		return
	var reach := radius + StreetWear.WORSHIP_MARGIN
	var centre := plan.block_index_at(anchor)
	var near := 0
	var placed := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var chunk: CityChunk = city._new_chunk(centre + Vector2i(dx, dz), CityChunk.Level.FULL)
			chunk.build()
			var pts: PackedVector2Array = chunk.get_meta("murals", PackedVector2Array())
			placed += pts.size()
			for p in pts:
				if p.distance_to(anchor) < reach:
					near += 1
			chunk.get_parent().remove_child(chunk)
			chunk.free()
	_t._check(near == 0, "no mural within %d m of the masjid (%d placed round it, %d inside)" % [int(reach), placed, near])
