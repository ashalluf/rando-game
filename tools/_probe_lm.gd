extends SceneTree
func _tris(n: Node) -> int:
	var t := 0
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		t += (n as MeshInstance3D).mesh.get_faces().size() / 3
	for c in n.get_children():
		t += _tris(c)
	return t
func _count(n: Node) -> int:
	var c := 1
	for k in n.get_children():
		c += _count(k)
	return c
func _initialize() -> void:
	for lm in Landmarks.all():
		var p := Node3D.new()
		var s := StaticBody3D.new()
		root.add_child(p)
		root.add_child(s)
		await process_frame
		Landmarks.build(lm, p, s, null, true)
		await process_frame
		print("%-20s r=%5.1f tris=%7d nodes=%4d" % [lm.id, lm.radius, _tris(p), _count(p) - 1])
		p.queue_free()
		s.queue_free()
		await process_frame
	quit()
