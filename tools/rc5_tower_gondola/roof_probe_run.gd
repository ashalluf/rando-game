extends RefCounted
## The body of roof_probe.gd, loaded once the autoloads exist.

func run(tree: SceneTree) -> void:
	var at := Vector2(2290.0, 230.0)
	var radius := 140.0
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
	var k0: Vector2i = plan.block_index_at(at)
	var n := int(ceilf(radius / 120.0))
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
				if is_equal_approx(cu.a, FarBuilding.PLANT_FLAG):
					continue
				var xf: Transform3D = xs[i]
				var sz := Vector3(xf.basis.x.length(), xf.basis.y.length(), xf.basis.z.length())
				if sz.y < 8.0 or sz.x < 6.0:
					continue
				var p := Vector2(xf.origin.x, xf.origin.z)
				if p.distance_to(at) > radius:
					continue
				print("PART block %d,%d centre (%.1f, %.1f) size %.1f x %.1f top %.1f" % [bx, bz, p.x, p.y, sz.x, sz.z, xf.origin.y + sz.y * 0.5])
			cap.free()
	s.free()
	tree.quit()
