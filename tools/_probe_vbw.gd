extends SceneTree

func _tris(n: Node) -> int:
	var t := 0
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		t += (n as MeshInstance3D).mesh.get_faces().size() / 3
	if n is MultiMeshInstance3D:
		var mm := (n as MultiMeshInstance3D).multimesh
		if mm and mm.mesh:
			t += (mm.mesh.get_faces().size() / 3) * mm.instance_count
	for c in n.get_children():
		t += _tris(c)
	return t

func _count(n: Node) -> int:
	var c := 1
	for k in n.get_children():
		c += _count(k)
	return c

func _initialize() -> void:
	var anchor := Vector2(-949.0, -340.0)
	var plan := CityPlan.new()
	plan.seed = 12345
	plan.macro = MacroMap.new()
	plan.macro.seed = 12345
	plan.macro.setup()
	var macro = plan.macro
	print("--- cross-section along the run, taken from _at() itself ---")
	var L: float = LandmarkVeniceBoardwalk.LENGTH
	for i in 9:
		var lz: float = -L * 0.5 + L * float(i) / 8.0
		var walk: Vector3 = LandmarkVeniceBoardwalk._at(anchor, plan, 0.0, lz, 0.0)
		var sea: Vector3 = LandmarkVeniceBoardwalk._at(anchor, plan, -48.0, lz, 0.0)
		var land: Vector3 = LandmarkVeniceBoardwalk._at(anchor, plan, 23.0, lz, 0.0)
		var cw: float = macro.coast_x(walk.z)
		var cs: float = macro.coast_x(sea.z)
		print("lz=%7.1f | walk %s at %6.1f m from water (%s) | seaward edge %6.1f m from water (%s) | inland edge (%s) | yaw %5.1f deg" % [
			lz, "%8.1f" % walk.x, walk.x - cw, MacroMap.ZONE_NAMES[macro.zone_at(Vector2(walk.x, walk.z))],
			sea.x - cs, MacroMap.ZONE_NAMES[macro.zone_at(Vector2(sea.x, sea.z))],
			MacroMap.ZONE_NAMES[macro.zone_at(Vector2(land.x, land.z))],
			rad_to_deg(LandmarkVeniceBoardwalk._shore_yaw(plan, anchor.y + lz))])
	for mode in [true, false]:
		var p := Node3D.new()
		var s := StaticBody3D.new()
		root.add_child(p)
		root.add_child(s)
		await process_frame
		LandmarkVeniceBoardwalk.build(anchor, p, s if mode else null, plan, mode)
		await process_frame
		var aabb := AABB()
		var first := true
		for c in p.get_children():
			if c is Node3D:
				var v: Vector3 = (c as Node3D).position
				if first:
					aabb = AABB(v, Vector3.ZERO)
					first = false
				else:
					aabb = aabb.expand(v)
		print("detailed=%s tris=%7d nodes=%4d shapes=%4d origin_span=%s" % [mode, _tris(p), _count(p) - 1, s.get_child_count(), aabb])
		p.queue_free()
		s.queue_free()
		await process_frame
	# statics == null on the detailed path must not crash.
	var p2 := Node3D.new()
	root.add_child(p2)
	await process_frame
	LandmarkVeniceBoardwalk.build(anchor, p2, null, plan, true)
	await process_frame
	print("detailed with statics=null: OK, tris=%d" % _tris(p2))
	# determinism
	var p3 := Node3D.new()
	root.add_child(p3)
	await process_frame
	LandmarkVeniceBoardwalk.build(anchor, p3, null, plan, true)
	await process_frame
	print("deterministic: %s" % [_tris(p2) == _tris(p3) and _count(p2) == _count(p3)])
	quit()
