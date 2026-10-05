extends Node
## The extra occluders (Occluders, MountainOccluder), headless, a minute: builds a hill chunk, a
## freeway chunk, a river chunk and (searching the freeway's suburban stretches) a chunk with a
## sound wall, FULL, and prints what each occluder holds, how long it took and an EYE to look at
## it from; then the mountain sheet round a few points. Usage:
##   godot --headless --path . res://tools/occluders/probe.tscn
## CHECKS=1 runs tests/occluders_checks.gd alone instead (a minute or two); LANDMARKS=1 lists every
## landmark's occluder.
var passed := 0
var failed := 0


func _ready() -> void:
	await get_tree().process_frame
	var city: Node3D = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	for n in ["Police", "Emergency"]:
		if city.get_node_or_null(n):
			city.get_node(n).set("enabled", false)
	get_tree().root.add_child(city)
	for i in 30:
		await get_tree().process_frame
	if OS.get_environment("CHECKS") == "1":
		await load("res://tests/occluders_checks.gd").new().run(self, city)
		print("OCCLUDER CHECKS %d passed, %d failed" % [passed, failed])
		get_tree().quit()
		return
	var plan: CityPlan = city.plan
	if OS.get_environment("LANDMARKS") == "1":
		await _landmarks(plan)
		get_tree().quit()
		return
	var occ: GDScript = load("res://scripts/world/occluders.gd")
	# A hill chunk on the front range, a freeway chunk downtown, a river chunk.
	var spots := {"hill": Vector2(300.0, -1150.0), "freeway": Vector2(1989.0, 160.0)}
	var rv: LaRiver = plan.macro.river
	if rv:
		spots["river"] = rv.point(rv.length * 0.4, 0.0)
	if rv:
		var s := rv.length * 0.4
		var pd := rv.at(s)
		var d: Vector2 = pd[1]
		print("RIVER_EYE=%.1f,%.1f,%.1f,%.0f,2 (bed)" % [(pd[0] as Vector2).x, rv.water_at(s) + 1.7, (pd[0] as Vector2).y, rad_to_deg(atan2(-d.x, -d.y))])
	for p: Vector2 in [Vector2(300, -1500), Vector2(420, -1500), Vector2(300, -2900), Vector2(150, -1800), Vector2(500, -1900)]:
		print("HEIGHT %s = %.1f zone=%d" % [p, plan.height_at(p), plan.zone_at(p)])
	for name: String in spots:
		var p: Vector2 = spots[name]
		_build(city, plan, plan.chunk_index_at(p), name)
	# Sound walls: the freeway's chunks in the house districts, until one has some.
	var fw: Freeway = plan.macro.freeway
	var tried := {}
	var found := 0
	for seg: Dictionary in fw.segments_in(Rect2(-6000, -6000, 12000, 12000)):
		var mid: Vector2 = (seg.a as Vector2).lerp(seg.b, 0.5)
		var d := plan.district_at(mid)
		if d != CityPlan.District.SUBURBS:
			continue
		for off: Vector2 in [Vector2(0, 0), Vector2(60, 0), Vector2(-60, 0), Vector2(0, 60), Vector2(0, -60)]:
			var k := plan.chunk_index_at(mid + off)
			if tried.has(k) or tried.size() > 60:
				continue
			tried[k] = true
			var before: int = (occ.get("stats") as Dictionary).wall
			_build(city, plan, k, "wall?", true)
			if (occ.get("stats") as Dictionary).wall > before:
				found += 1
				_build(city, plan, k, "wall")
				var q: Array = (occ.get("last_walls") as Array).back()
				var c: Vector3 = (q[0] + q[2]) * 0.5
				var along: Vector3 = (q[1] - q[0]).normalized()
				var nrm := Vector3(along.z, 0.0, -along.x)
				for sgn: float in [1.0, -1.0]:
					var eye: Vector3 = c + nrm * sgn * 14.0
					var look := -nrm * sgn
					print("  SOUND_EYE=%.1f,%.1f,%.1f,%.0f,0" % [eye.x, plan.height_at(Vector2(eye.x, eye.z)) + 1.7, eye.z, rad_to_deg(atan2(-look.x, -look.z))])
		if found >= 2 or tried.size() > 60:
			break
	print("STATS ", occ.get("stats"))
	var m = city.get_node_or_null("MountainOccluder")
	if m:
		for p: Vector2 in [Vector2(300, 600), Vector2(-500, 2000), Vector2(400, -2600), Vector2(2800, 100)]:
			var t0 := Time.get_ticks_usec()
			m.update(p)
			print("MOUNTAIN at %s: %d triangles, %.1f ms" % [p, m.triangles, (Time.get_ticks_usec() - t0) / 1000.0])
	else:
		print("MOUNTAIN none")
	get_tree().quit()


## LANDMARKS=1: every landmark built detailed, with its occluder's triangles against its own size.
func _landmarks(plan: CityPlan) -> void:
	var lms: GDScript = load("res://scripts/world/landmarks.gd")
	for lm: Dictionary in lms.call("all"):
		var holder := Node3D.new()
		var statics := StaticBody3D.new()
		holder.add_child(statics)
		get_tree().root.add_child(holder)
		lms.call("build", lm, holder, statics, plan, true)
		var occ_tris := 0
		var occ_n := 0
		for n in holder.find_children("*", "OccluderInstance3D", true, false):
			occ_n += 1
			var o := (n as OccluderInstance3D).occluder as ArrayOccluder3D
			if o:
				occ_tris += o.indices.size() / 3
		var aabb := AABB()
		var first := true
		for n in holder.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			var b := mi.global_transform * mi.get_aabb()
			aabb = b if first else aabb.merge(b)
			first = false
		print("LANDMARK %-22s occluders=%d tris=%d size=%s" % [lm.id, occ_n, occ_tris, aabb.size.round()])
		holder.queue_free()
		await get_tree().process_frame


func _build(city: Node3D, plan: CityPlan, k: Vector2i, label: String, quiet: bool = false) -> void:
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	var t0 := Time.get_ticks_usec()
	chunk.build()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var node := chunk.get_node_or_null("OccluderExtra") as OccluderInstance3D
	var base := chunk.get_node_or_null("Occluder") as OccluderInstance3D
	if not quiet:
		var tris := 0
		var aabb := AABB()
		if node:
			var o := node.occluder as ArrayOccluder3D
			tris = o.indices.size() / 3
			aabb = AABB(o.vertices[0], Vector3.ZERO)
			for v in o.vertices:
				aabb = aabb.expand(v)
		var r := plan.owned_rect(k.x, k.y)
		print("%s chunk %s zone=%d district=%d build=%.0f ms extra=%d tris aabb=%s buildings=%d tris" % [label, k, plan.zone_at(r.get_center()), plan.district_at(r.get_center()),
			ms, tris, aabb, (base.occluder as ArrayOccluder3D).indices.size() / 3 if base else 0])
		print("  EYE=%.1f,%.1f,%.1f" % [r.get_center().x, plan.height_at(r.get_center()) + 2.0, r.get_center().y])
	chunk.get_parent().remove_child(chunk)
	chunk.free()


func _check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("  ok   ", what)
	else:
		failed += 1
		print("  FAIL ", what)
