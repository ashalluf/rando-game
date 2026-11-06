extends RefCounted

func run(tree: SceneTree) -> void:
	var eye := Vector2(2359.0, 880.0)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--eye="):
			var p := a.substr(6).split(",")
			eye = Vector2(p[0].to_float(), p[1].to_float())
	var s = load("res://scenes/levels/city.tscn").instantiate()
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
	var sky := Skyline.new()
	tree.root.add_child(sky)
	sky.setup(plan, s.chunk_style())
	sky.build_near(eye, 7000.0)
	var box_t: int = 12
	var veg_t: int = PropFactory.canopy_blob().surface_get_array_index_len(0) / 3
	if veg_t <= 0:
		veg_t = 24
	var lod_reach := float(s.lod_radius_blocks) * plan.block_size_range.y
	var full_reach := 2.0 * plan.block_size_range.y
	var c := plan.block_index_at(eye)
	var cover := {}
	for dx in range(-s.lod_radius_blocks, s.lod_radius_blocks + 1):
		for dz in range(-s.lod_radius_blocks, s.lod_radius_blocks + 1):
			var k := Vector2i(c.x + dx, c.y + dz)
			var r := plan.owned_rect(k.x, k.y)
			var d := Vector2(maxf(maxf(r.position.x - eye.x, eye.x - r.end.x), 0.0), maxf(maxf(r.position.y - eye.y, eye.y - r.end.y), 0.0)).length()
			var ring := maxi(absi(dx), absi(dz))
			if ring > s.load_radius_blocks and d > lod_reach:
				continue
			cover[k] = 0 if ring <= s.load_radius_blocks and d <= full_reach else 1
	var drawn := [0, 0]
	var waste := [0, 0]
	var hidden := [0, 0]
	var mixed := 0
	for t in sky._tile_blocks:
		var tb: Array = sky._tile_blocks[t]
		var any_b := false
		var any_v := false
		var tb_tris := [0, 0, 0, 0]
		for k: Vector2i in tb:
			var b: Dictionary = sky._blocks[k]
			var nb := (int(b.bn) + int(b.hn) + int(b.get("en", 0))) * box_t
			var nv := int(b.vn) * veg_t
			var cov_b := cover.has(k)
			var cov_v := cover.has(k) and int(cover[k]) == 0
			if not cov_b:
				any_b = true
			if not cov_v:
				any_v = true
			tb_tris[0 if cov_b else 1] += nb
			tb_tris[2 if cov_v else 3] += nv
		# boxes
		if any_b:
			drawn[0] += tb_tris[1]
			waste[0] += tb_tris[0]
			if tb_tris[0] > 0:
				mixed += 1
		else:
			hidden[0] += tb_tris[0]
		if any_v:
			drawn[1] += tb_tris[3]
			waste[1] += tb_tris[2]
		else:
			hidden[1] += tb_tris[2]
	print("FARCOVER eye=%s tiles=%d mixed=%d covered_blocks=%d" % [eye, sky._tile_blocks.size(), mixed, cover.size()])
	print("FARCOVER boxes drawn=%d collapsed_in_shown=%d hidden=%d" % [drawn[0], waste[0], hidden[0]])
	print("FARCOVER veg   drawn=%d collapsed_in_shown=%d hidden=%d (veg tris %d each)" % [drawn[1], waste[1], hidden[1], veg_t])
