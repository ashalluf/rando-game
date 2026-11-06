extends RefCounted
## The body of tools/metro/probe.gd (loaded once the autoloads exist).

func run(tree: SceneTree) -> void:
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var plan := CityPlan.new()
	plan.seed = city.world_seed if OS.get_environment("SEED") == "" else OS.get_environment("SEED").to_int()
	plan.block_size_range = city.block_size_range
	plan.street_width = city.street_width
	plan.avenue_width = city.avenue_width
	plan.sidewalk_width = city.sidewalk_width
	plan.downtown_radius = city.downtown_radius
	plan.midtown_radius = city.midtown_radius
	plan.macro = MacroMap.new()
	plan.macro.seed = plan.seed
	plan.macro.setup()
	var line := LightRail.of(plan)
	var f := MetroStation.frame(line)
	if f.is_empty():
		print("METRO none (METRO_STATION=0 or no tunnel station)")
		return
	print("METRO %s at (%.1f, %.1f) dir %s street %.2f rail %.2f platform %.2f s %.1f" % [f.name, f.o.x, f.o.y, f.d, f.y0, f.rail, f.plat, f.s])
	print("  exits: %s" % [MetroStation.exit_names(line)])
	print("  track half at the platform %.2f, 60 m out %.2f" % [line.sample(float(f.s)).half, line.sample(float(f.s) + 60.0).half])
	for o in MetroStation.openings():
		print("  opening u %.1f..%.1f v %.1f..%.1f" % o)
	var key := plan.chunk_index_at(f.o)
	var ch := CityChunk.new()
	ch.plan = plan
	ch.ix = key.x
	ch.iz = key.y
	ch.level = CityChunk.Level.FULL
	ch.style = city.chunk_style()
	tree.root.add_child(ch)
	var t0 := Time.get_ticks_usec()
	var kit := MetroBuild.new(ch)
	var ok := kit.build()
	print("  build %s in %.1f ms" % [ok, (Time.get_ticks_usec() - t0) / 1000.0])
	for n in ch.get_children():
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var m: Mesh = (n as MeshInstance3D).mesh
			var tris := 0
			for si in m.get_surface_count():
				var arr := m.surface_get_arrays(si)
				tris += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			print("  mesh %s: %d triangles" % [n.name, tris])
		elif n is StaticBody3D:
			print("  body %s: %d shapes" % [n.name, n.get_child_count()])
		elif n is Area3D:
			print("  zone %s: %d shapes" % [n.name, n.get_child_count()])
	var riders := 0
	for n in ch.get_children():
		if n is MetroRider:
			riders += 1
	print("  riders %d; registered %s" % [riders, MetroStation.built()])
	var eye := func(u: float, h: float, v: float, yaw_off: float, pitch: float) -> String:
		var w := MetroStation.to_world(f, Vector3(u, h, v))
		var d: Vector2 = f.d
		var yaw := rad_to_deg(atan2(-d.x, -d.y)) + yaw_off
		return "%.1f,%.2f,%.1f,%.0f,%.0f" % [w.x, w.y - plan.height_at(Vector2(w.x, w.z)), w.z, yaw, pitch]
	print("  EYE platform looking +u: %s" % eye.call(-28.0, float(f.plat) + 1.7, 1.5, 180.0, -2.0))
	print("  EYE concourse: %s" % eye.call(-27.0, MetroStation.CONC_FLOOR + 1.7, -5.5, 180.0, -4.0))
	print("  EYE kiosk street: %s" % eye.call(-40.0, 1.7, -5.0, 180.0, -8.0))
	print("  EYE down the stair: %s" % eye.call(-31.5, 1.7, -0.8, 180.0, -25.0))
	ch.queue_free()
