extends RefCounted
## The body of tools/pier/compile.gd (loaded after the autoloads exist).

func run(tree: SceneTree) -> void:
	var root3d := Node3D.new()
	tree.root.add_child(root3d)
	for detailed in [true, false]:
		var holder := Node3D.new()
		root3d.add_child(holder)
		var t0 := Time.get_ticks_usec()
		var before: int = PierMesh.built_triangles
		PierPark.build(Vector2(-940.0, -350.0), holder, null, null, detailed)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		var nodes := 0
		var shapes := 0
		var stack: Array[Node] = [holder]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			nodes += 1
			if n is CollisionShape3D:
				shapes += 1
			stack.append_array(n.get_children())
		print("PARK detailed=%s ms=%.1f triangles=%d nodes=%d shapes=%d" % [detailed, ms, PierMesh.built_triangles - before, nodes, shapes])
	print("COASTER length=%.1f period=%.1f drop_v=%.1f max_v=%.1f" % [PierCoaster.length, PierCoaster.period, PierCoaster.speed_at(90.0), _max_v()])
	for t in [0.0, 30.0, 45.0, 60.0, 70.0, 80.0, 90.0]:
		var s := PierCoaster.lead_s(t)
		print("  t=%.0f s=%.1f h=%.1f v=%.1f" % [t, s, PierCoaster.height_at(s), PierCoaster.speed_at(s)])

	# The checks that need no city (tests/pier_park_checks.gd), printed PASS / FAIL.
	var gs := GDScript.new()
	gs.source_code = "extends Node\nfunc _check(ok, label):\n\tprint(('PASS ' if ok else 'FAIL ') + label)\n"
	gs.reload()
	var reporter := Node.new()
	reporter.set_script(gs)
	tree.root.add_child(reporter)
	var chk = load("res://tests/pier_park_checks.gd").new()
	chk._t = reporter
	chk._tree = tree
	chk._layout()
	chk._coaster()
	chk._walks()


func _max_v() -> float:
	var m := 0.0
	var s := 0.0
	while s < PierCoaster.length:
		m = maxf(m, PierCoaster.speed_at(s))
		s += 1.0
	return m
