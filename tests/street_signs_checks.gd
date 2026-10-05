extends RefCounted
## The street's signs (StreetSigns, StreetSignKit, SignFont), for tests/smoke_test.gd. Loaded at run
## time, not named there, so it compiles after the autoloads.
##
## Checks the stroke font covers every character a street name uses, the kit's assemblies (one
## surface on the sign shader, real sizes, triangle budgets), then builds FULL chunks round a
## four-way stop, a signalised junction and a school and checks: the stop signs face the traffic
## they stop (the near right corner of each approach), the blades sit on the stop post and the
## signal pole, every mast arm carries a name sign naming the street it crosses, the school's
## faces carry the school zone sign, the sign batches draw to their distances, and the block
## built with the signs off is the same block (every other prop's id, kind and place unchanged).

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	StreetSigns.keep_xforms = true
	_font()
	_kit()
	var stop := _find(plan, CityPlan.Intersection.STOP_SIGNS)
	var sig := _find(plan, CityPlan.Intersection.SIGNALS)
	_t._check(stop.x != 99999 and sig.x != 99999, "a four-way stop and a signalised junction near the start")
	if stop.x != 99999:
		_stop_chunk(city, plan, stop)
	if sig.x != 99999:
		_signal_chunk(city, plan, sig)
	_school(city, plan)
	StreetSigns.keep_xforms = false


func _font() -> void:
	var chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-'/&"
	var missing := ""
	for ch in chars:
		var g := SignFont.glyph(ch)
		if (g[0] as Array).is_empty():
			missing += ch
	for n: String in CityPlan.STREET_NAMES + CityPlan.ORDINALS:
		for ch in n.to_upper():
			if ch != " " and (SignFont.glyph(ch)[0] as Array).is_empty() and not missing.contains(ch):
				missing += ch
	var w1: float = SignFont.layout("ELM", 0.1, 0.015)[1]
	var w2: float = SignFont.layout("ELM ST", 0.1, 0.015)[1]
	_t._check(missing == "" and w2 > w1 and w1 > 0.1, "the sign font draws every letter, digit and mark a street name uses (missing '%s')" % missing)


func _kit() -> void:
	var meshes := {
		"name post": StreetSignKit.name_post("VISTA BLVD", "600", "5TH ST", "1100"),
		"stop": StreetSignKit.stop_post(),
		"stop with blades": StreetSignKit.stop_post(["HILL AVE", "600", "WILSHIRE BLVD", "500"]),
		"yield": StreetSignKit.yield_post(),
		"speed": StreetSignKit.speed_post(35),
		"no parking": StreetSignKit.no_parking_post(),
		"school": StreetSignKit.school_post(),
		"arm name": StreetSignKit.arm_name("WILSHIRE BLVD", "300"),
		"arm lanes": StreetSignKit.arm_lanes(),
		"no turn on red": StreetSignKit.arm_no_turn_red(),
	}
	var bad: Array = []
	var worst := 0
	for k: String in meshes:
		var m: ArrayMesh = meshes[k]
		var tris := StreetSignKit.triangles(m)
		worst = maxi(worst, tris)
		if m.get_surface_count() != 1 or m.surface_get_material(0) != StreetSignKit.material() or tris < 40 or tris > 4000:
			bad.append("%s (%d)" % [k, tris])
	_t._check(bad.is_empty(), "every sign assembly is one surface on the sign shader within 4,000 triangles (worst %d; bad %s)" % [worst, str(bad)])
	# Real sizes: the stop sign's octagon is 30 in across its flats, its bottom 7 ft up; the
	# blades sit at the post's top.
	var stop: AABB = (meshes["stop"] as ArrayMesh).get_aabb()
	_t._check(absf(stop.size.x - 0.762) < 0.05 and stop.end.y > 2.9 and stop.end.y < 3.1, "the stop sign is a 30 in octagon on a 3 m post (%.3f wide, %.2f tall)" % [stop.size.x, stop.end.y])
	var np: AABB = (meshes["name post"] as ArrayMesh).get_aabb()
	_t._check(np.end.y > 3.3 and np.end.y < 3.6 and np.size.x > 0.7 and np.size.z > 0.7, "the name post carries two crossed blades on top (%.2f m, %.2f x %.2f)" % [np.end.y, np.size.x, np.size.z])
	_t._check(StreetSignKit.split_name("VISTA BLVD") == ["VISTA", "BL"] and StreetSignKit.split_name("5TH ST") == ["5TH", "ST"] and StreetSignKit.split_name("ESPLANADE") == ["ESPLANADE", ""],
		"street names split into the name and LA's short suffix")


## The block index of a junction of `kind` nearest the start, owned by a plain city block.
func _find(plan: CityPlan, kind: int) -> Vector2i:
	var best := Vector2i(99999, 99999)
	var best_d := INF
	for ix in range(-6, 6):
		for iz in range(-4, 4):
			var inter: Dictionary = plan.intersection(ix + 1, iz + 1)
			var block: Dictionary = plan.block(ix, iz)
			if int(inter.kind) != kind or plan.junction_closed(ix + 1, iz + 1) or block.has("site") or plan.river_block(ix, iz):
				continue
			if plan.zone_at((block.rect as Rect2).get_center()) != MacroMap.Zone.CITY:
				continue
			var d := (inter.pos as Vector2).length()
			if d < best_d:
				best_d = d
				best = Vector2i(ix, iz)
	return best


func _instances(chunk: CityChunk, kind: String) -> Array:
	var out: Array = []
	for r: Dictionary in chunk.prop_records:
		if String(r.kind) != kind:
			continue
		for inst: Array in r.instances:
			if String(inst[0]).begins_with("ss_"):
				out.append([r, inst])
	return out


## [mesh, transform] of a prop instance, read from the chunk's batch nodes (under the dummy
## renderer instance transforms read back as identity, so this reads the batch data the chunk
## kept: CityChunk keeps the records, StreetSigns adds nothing else).
func _signature(chunk: CityChunk) -> Array:
	var out: Array = []
	for r: Dictionary in chunk.prop_records:
		if String(r.id).begins_with("ssign_"):
			continue
		var p: Vector3 = r.position
		out.append("%s %s %.2f %.2f" % [r.id, r.kind, p.x, p.z])
	return out


func _stop_chunk(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var stops := _instances(chunk, "stop_sign")
	var inter: Dictionary = plan.intersection(k.x + 1, k.y + 1)
	var pos: Vector2 = inter.pos
	# Each stop faces away from the junction along its approach (toward the traffic it stops),
	# from the near right corner: the corner is on the approach's kerb side of the centre line.
	var facing_ok := 0
	var blades := 0
	for e: Array in stops:
		var r: Dictionary = e[0]
		var at: Vector3 = r.position
		var c := Vector2(signf(at.x - pos.x), signf(at.z - pos.y))
		var want := Vector3(0.0, 0.0, c.y) if c.x * c.y > 0.0 else Vector3(c.x, 0.0, 0.0)
		var key: String = e[1][0]
		var mesh: ArrayMesh = chunk._mm_nodes[key].multimesh.mesh if chunk._mm_nodes.has(key) else null
		# The stop's own transform: the post stands at the record's place with the yaw of `want`.
		var yaw := atan2(want.x, want.z)
		if mesh != null and absf(wrapf(yaw - _yaw_of(chunk, key, at), -PI, PI)) < 0.05:
			facing_ok += 1
		if mesh != null and mesh.get_aabb().end.y > 3.3:
			blades += 1
	_t._check(stops.size() == 4 and facing_ok == 4, "a four-way stop has four stop signs, each facing the traffic it stops (%d of %d)" % [facing_ok, stops.size()])
	_t._check(blades >= 1 and blades <= 2, "the street-name blades stand on the stop signs' posts at the named corners (%d)" % blades)
	var old_names := 0
	for key: String in chunk._mm_nodes:
		if key.begins_with("text_") or key == "sign_plate" or key == "stop_sign":
			old_names += 1
	_t._check(old_names == 0, "no old plate, lettering or disc sign is left at the stop junction (%d)" % old_names)
	_same_block(city, chunk, k)


## The yaw StreetSigns gave the instance nearest `at` in batch `key` (from the batch's data,
## which CityChunk hands the batch builder: the dummy renderer reads instance transforms back as
## identity).
func _yaw_of(chunk: CityChunk, key: String, at: Vector3) -> float:
	var data: Dictionary = chunk.get_meta("ss_debug_xforms", {})
	var best := INF
	var yaw := 999.0
	for x: Transform3D in data.get(key, []):
		var d := Vector2(x.origin.x - at.x, x.origin.z - at.z).length()
		if d < best:
			best = d
			yaw = atan2(x.basis.z.x, x.basis.z.z)
	return yaw


func _signal_chunk(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var signs := _instances(chunk, "signal")
	var names := StreetSigns.junction_names(chunk)
	var arm_names := 0
	var tops := 0
	for e: Array in signs:
		var key: String = e[1][0]
		var mesh: ArrayMesh = chunk._mm_nodes[key].multimesh.mesh if chunk._mm_nodes.has(key) else null
		if mesh == null:
			continue
		if mesh == StreetSignKit.arm_name(names[0], names[1]) or mesh == StreetSignKit.arm_name(names[2], names[3]):
			arm_names += 1
		if mesh == StreetSignKit.pole_top_blades(names[0], names[1], names[2], names[3]):
			tops += 1
	var poles := 0
	for r: Dictionary in chunk.prop_records:
		if String(r.kind) == "signal":
			poles += 1
	_t._check(poles == 4 and arm_names == 4, "every signal mast arm carries a name sign for the street it crosses (%d of %d)" % [arm_names, poles])
	_t._check(tops >= 1 and tops <= 2, "the name blades stand on the signal poles at the named corners (%d)" % tops)
	var draw_ok := true
	for key: String in chunk._mm_nodes:
		if key.begins_with("ss_"):
			var node: GeometryInstance3D = chunk._mm_nodes[key]
			draw_ok = draw_ok and node.visibility_range_end >= StreetSigns.DRAW - 0.5 and node.visibility_range_end <= StreetSigns.ARM_DRAW + 0.5
	_t._check(draw_ok, "the sign batches stop drawing at their distances")
	_same_block(city, chunk, k)


## Built with the signs off, every other prop of the block keeps its id, kind and place.
func _same_block(city: Node3D, chunk: CityChunk, k: Vector2i) -> void:
	var sig := _signature(chunk)
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	StreetSigns.enabled = false
	var bare: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	bare.build()
	StreetSigns.enabled = true
	var bare_sig := _signature(bare)
	# The old name posts at a stop or signal junction moved onto the stop post / signal pole: their
	# ids are spent and left out, everything else matches id for id.
	var mine := {}
	for line: String in sig:
		mine[line.get_slice(" ", 0)] = line
	var diff := ""
	var moved := 0
	for line: String in bare_sig:
		var id := line.get_slice(" ", 0)
		if not mine.has(id):
			if line.get_slice(" ", 1) == "street_sign":
				moved += 1
			elif diff == "":
				diff = "lost " + line
		elif mine[id] != line and diff == "":
			diff = "%s | %s" % [mine[id], line]
		mine.erase(id)
	if not mine.is_empty() and diff == "":
		diff = "new " + str(mine.values()[0])
	_t._check(diff == "" and moved <= 2, "the signs roll nothing from the block: built without them every other prop keeps its id, kind and place (%d props, %d name posts moved onto poles%s)" % [sig.size(), moved, "" if diff == "" else "; " + diff])
	bare.get_parent().remove_child(bare)
	bare.free()


func _school(city: Node3D, plan: CityPlan) -> void:
	var found := Vector2i(99999, 99999)
	for ix in range(-8, 8):
		for iz in range(-6, 6):
			var b: Dictionary = plan.block(ix, iz)
			if int(b.kind) == CityPlan.BlockKind.SCHOOL and not b.has("site") and plan.zone_at((b.rect as Rect2).get_center()) == MacroMap.Zone.CITY:
				found = Vector2i(ix, iz)
				break
		if found.x != 99999:
			break
	if found.x == 99999:
		_t._check(true, "no school near the start on this seed (school zone signs not checked)")
		return
	var chunk: CityChunk = city._new_chunk(found, CityChunk.Level.FULL)
	chunk.build()
	var n := 0
	for key: String in chunk._mm_nodes:
		if key.begins_with("ss_") and chunk._mm_nodes[key].multimesh.mesh == StreetSignKit.school_post():
			n += chunk._mm_nodes[key].multimesh.instance_count
	_t._check(n >= 2, "a school block's faces carry the school zone sign (%d)" % n)
	chunk.get_parent().remove_child(chunk)
	chunk.free()
