extends SceneTree
## TEMPORARY review probe for LandmarkVerdeCafe. Deleted after use.

func _tris(n: Node) -> int:
	var t := 0
	if n is MeshInstance3D:
		var m: Mesh = (n as MeshInstance3D).mesh
		if m != null:
			t += m.get_faces().size() / 3
	for c in n.get_children():
		t += _tris(c)
	return t

func _count(n: Node) -> int:
	var c := 1
	for k in n.get_children():
		c += _count(k)
	return c

func _aabb(n: Node, acc: AABB, first: Array) -> AABB:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			var b := mi.global_transform * mi.mesh.get_aabb()
			if first[0]:
				acc = b
				first[0] = false
			else:
				acc = acc.merge(b)
	for c in n.get_children():
		acc = _aabb(c, acc, first)
	return acc

func _initialize() -> void:
	var errs := 0
	for mode in [true, false]:
		for with_statics in [true, false]:
			var parent := Node3D.new()
			var statics: StaticBody3D = StaticBody3D.new() if with_statics else null
			root.add_child(parent)
			if statics:
				root.add_child(statics)
			await process_frame
			LandmarkVerdeCafe.build(Vector2(0, 0), parent, statics, null, mode)
			await process_frame
			var shapes := 0
			if statics:
				for c in statics.get_children():
					if c is CollisionShape3D:
						shapes += 1
			var first := [true]
			var box := _aabb(parent, AABB(), first)
			print("MODE detailed=%s statics=%s tris=%d nodes=%d shapes=%d" % [mode, with_statics, _tris(parent), _count(parent) - 1, shapes])
			if not first[0]:
				print("   aabb pos=%v size=%v" % [box.position, box.size])
			parent.queue_free()
			if statics:
				statics.queue_free()
			await process_frame
	# Determinism: two builds at the same anchor must match vertex-for-vertex.
	var sig := []
	for pass_i in 2:
		var p := Node3D.new()
		root.add_child(p)
		await process_frame
		LandmarkVerdeCafe.build(Vector2(-900, -430), p, null, null, true)
		await process_frame
		var s := ""
		for c in p.get_children():
			s += "%v|" % (c as Node3D).position if c is Node3D else "?"
		sig.append(s.hash())
		p.queue_free()
		await process_frame
	print("DETERMINISM same=%s" % [sig[0] == sig[1]])
	quit()
