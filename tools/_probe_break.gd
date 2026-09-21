extends SceneTree
func _initialize() -> void:
	var parent := Node3D.new()
	root.add_child(parent)
	await process_frame
	LandmarkVerdeCafe.build(Vector2(0, 0), parent, null, null, true)
	await process_frame
	var by_kind := {}
	var total := 0
	for n in parent.get_children():
		_walk(n, by_kind)
	var keys := by_kind.keys()
	keys.sort_custom(func(a, b): return by_kind[a][0] > by_kind[b][0])
	for k in keys:
		total += by_kind[k][0]
		print("%-28s tris=%6d count=%3d" % [k, by_kind[k][0], by_kind[k][1]])
	print("TOTAL %d" % total)
	quit()

func _walk(n: Node, acc: Dictionary) -> void:
	if n is MeshInstance3D:
		var m: Mesh = (n as MeshInstance3D).mesh
		if m != null:
			var t := m.get_faces().size() / 3
			var k: String = m.get_class()
			if m is CylinderMesh:
				var c := m as CylinderMesh
				k = "CylinderMesh r=%.2f h=%.2f seg=%d" % [c.bottom_radius, c.height, c.radial_segments]
			elif m is SphereMesh:
				k = "SphereMesh rs=%d rings=%d" % [(m as SphereMesh).radial_segments, (m as SphereMesh).rings]
			if not acc.has(k):
				acc[k] = [0, 0]
			acc[k][0] += t
			acc[k][1] += 1
	for c in n.get_children():
		_walk(c, acc)
