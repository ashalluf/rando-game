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
func _initialize() -> void:
	var plan := CityPlan.new()
	plan.seed = 12345
	plan.macro = MacroMap.new()
	plan.macro.seed = 12345
	plan.macro.setup()
	for lm in Landmarks.all():
		var p := Node3D.new()
		var s := StaticBody3D.new()
		root.add_child(p)
		root.add_child(s)
		await process_frame
		Landmarks.build(lm, p, s, plan, true)
		await process_frame
		print("%-20s r=%5.1f tris=%8d shapes=%4d" % [lm.id, lm.radius, _tris(p), s.get_child_count()])
		p.queue_free()
		s.queue_free()
		await process_frame
	quit()
