extends RefCounted
## The body of tools/rooftops/find.gd, loaded once the autoloads exist.

func run(tree: SceneTree) -> void:
	var at := Vector2(2800.0, 100.0)
	var radius := 600.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at="):
			var p := a.substr(5).split(",")
			at = Vector2(p[0].to_float(), p[1].to_float())
		elif a.begins_with("--radius="):
			radius = a.substr(9).to_float()
	var scene: PackedScene = load("res://scenes/levels/city.tscn")
	var s = scene.instantiate()
	var plan := CityPlan.new()
	plan.seed = s.world_seed
	plan.block_size_range = s.block_size_range
	plan.street_width = s.street_width
	plan.avenue_width = s.avenue_width
	plan.sidewalk_width = s.sidewalk_width
	plan.downtown_radius = s.downtown_radius
	plan.midtown_radius = s.midtown_radius
	plan.macro = MacroMap.new()
	plan.macro.seed = s.world_seed
	plan.macro.setup()
	var names := {FarBuilding.Plant.HELIPAD: "helipad", FarBuilding.Plant.POOL: "pool", 100: "cradle"}
	var want := OS.get_environment("KIND")
	var k0: Vector2i = plan.block_index_at(at)
	var n := int(ceilf(radius / 120.0))
	var seen := 0
	var counts := {}
	for bx in range(k0.x - n, k0.x + n + 1):
		for bz in range(k0.y - n, k0.y + n + 1):
			var cap := CityChunk.new()
			cap.plan = plan
			cap.ix = bx
			cap.iz = bz
			cap.level = CityChunk.Level.LOD
			cap.style = s.chunk_style()
			cap.capturing = true
			cap.build()
			var boxes: Dictionary = (cap.captured.get("batch", {}) as Dictionary).get("lod_box", {})
			var xs: Array = boxes.get("xforms", [])
			var cs: Array = boxes.get("custom", [])
			for i in xs.size():
				var cu: Color = cs[i]
				if not is_equal_approx(cu.a, FarBuilding.PLANT_FLAG):
					continue
				var kind: int = roundi(cu.r)
				var col: Color = (boxes.get("colors", []) as Array)[i]
				# The washing machine's cradle hanging on a facade is a UNIT box in its yellow.
				if kind == FarBuilding.Plant.UNIT and col.is_equal_approx(Rooftops.CRADLE_YELLOW):
					kind = 100
				if not names.has(kind):
					continue
				var xf: Transform3D = xs[i]
				var p := Vector2(xf.origin.x, xf.origin.z)
				if p.distance_to(at) > radius:
					continue
				counts[names[kind]] = int(counts.get(names[kind], 0)) + 1
				if want != "" and want != names[kind]:
					continue
				var y := xf.origin.y
				# An EYE 30 m off to the south-east and 15 m up, looking back at it.
				var eye := Vector3(p.x + 22.0, y + 16.0, p.y + 22.0)
				print("ROOF %s at (%.1f, %.1f, %.1f) size %.1f  EYE=%.1f,%.1f,%.1f,45,-28" % [names[kind], p.x, y, p.y, xf.basis.x.length(), eye.x, eye.y, eye.z])
				seen += 1
			cap.free()
	print("ROOF total %d %s round %s r %.0f" % [seen, counts, at, radius])
	s.free()
	tree.quit()
