extends RefCounted

func run(tree: SceneTree) -> void:
	var at := Vector2(-500, 0)
	var n := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at="):
			var p := a.substr(5).split(",")
			at = Vector2(p[0].to_float(), p[1].to_float())
		if a.begins_with("--n="):
			n = a.substr(4).to_int()
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
	var style: Dictionary = s.chunk_style()
	var k0 := plan.block_index_at(at)
	for dx in range(-n + 1, n):
		for dz in range(-n + 1, n):
			var k := Vector2i(k0.x + dx, k0.y + dz)
			var b := plan.block(k.x, k.y)
			var zone: int = plan.macro.zone_at((b.rect as Rect2).get_center())
			var ch := CityChunk.new()
			ch.plan = plan
			ch.ix = k.x
			ch.iz = k.y
			ch.level = CityChunk.Level.LOD
			ch.style = style
			ch.capturing = true
			ch.begin_build()
			var guard := 0
			while not ch.build_step() and guard < 10000:
				guard += 1
			var cap: Dictionary = ch.captured
			var batch: Dictionary = cap.get("batch", {})
			var kinds := {}
			if batch.has("lod_box"):
				var lb: Dictionary = batch["lod_box"]
				for i in (lb.xforms as Array).size():
					var key := "a%.0f" % float(lb.custom[i].a)
					kinds[key] = int(kinds.get(key, 0)) + 1
			var veg := []
			var vc := []
			var vcu := []
			var t0 := Time.get_ticks_usec()
			var trees := MidCity.yard_trees(plan, k, b, cap, ch._gy, func(q: Vector2) -> bool: return ch._under_freeway(q, 4.0), veg, vc, vcu)
			var pools := 0
			if batch.has("lod_box"):
				for c: Color in batch["lod_box"].custom:
					if is_equal_approx(c.a, MidCity.POOL_FLAG):
						pools += 1
			print("TREES %s %d in %.2f ms, pools %d" % [k, trees, float(Time.get_ticks_usec() - t0) / 1000.0, pools])
			print("BLOCK %s zone %d district %d kind %d rect %s lots %d batch_keys %s lodbox %s boxes %d ground %d" % [k, zone, b.district, b.kind,
				b.rect, plan.lots(k.x, k.y).size(), batch.keys(), kinds, (cap.get("boxes", []) as Array).size(), (cap.get("ground", []) as Array).size()])
			ch.free()
	s.free()
	tree.quit()
