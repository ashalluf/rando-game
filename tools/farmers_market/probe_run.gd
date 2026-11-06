extends RefCounted
## The body of tools/farmers_market/probe.gd (loaded once the autoloads exist).

func run(_tree: SceneTree) -> void:
	var scene: PackedScene = load("res://scenes/levels/city.tscn")
	var s = scene.instantiate()
	var plan := CityPlan.new()
	plan.seed = s.world_seed if OS.get_environment("SEED") == "" else OS.get_environment("SEED").to_int()
	plan.block_size_range = s.block_size_range
	plan.street_width = s.street_width
	plan.avenue_width = s.avenue_width
	plan.sidewalk_width = s.sidewalk_width
	plan.downtown_radius = s.downtown_radius
	plan.midtown_radius = s.midtown_radius
	plan.macro = MacroMap.new()
	plan.macro.seed = plan.seed
	plan.macro.setup()
	s.free()
	var box := Rect2(-6000.0, -6000.0, 12000.0, 12000.0)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		var v := (args[0] as String).split(",")
		box = Rect2(float(v[0]), float(v[1]), float(v[2]) - float(v[0]), float(v[3]) - float(v[1]))
	var t0 := Time.get_ticks_msec()
	var found := 0
	var c0 := FarmersMarket._cell_of(box.position)
	var c1 := FarmersMarket._cell_of(box.end)
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var m := FarmersMarket.decide(plan, Vector2i(cx, cz))
			if m.is_empty():
				continue
			found += 1
			var lay := FarmersMarket.layout(m)
			var kinds := [0, 0, 0, 0]
			for st: Dictionary in lay.stalls:
				kinds[int(st.kind)] += 1
			var mid := FarmersMarket.point(m, (float(m.lo) + float(m.hi)) * 0.5, 0.0)
			var along: Vector2 = FarmersMarket.dirs(m)[0]
			var eye := FarmersMarket.point(m, float(lay.len0) - 6.0, 0.0)
			var yaw := rad_to_deg(atan2(-along.x, -along.y))
			var closed_mid := not plan.road_open(int(m.axis), int(m.index), (float(m.lo) + float(m.hi)) * 0.5)
			var open_end := plan.road_open(int(m.axis), int(m.index), float(m.lo) + 1.0)
			print("MARKET cell %s %s axis %d road %d k %d owner %s width %.1f len %.0f day %d stalls %d (p%d f%d b%d j%d) vans %d district %d closed_mid %s open_end %s mid (%.0f, %.0f)" % [
				m.cell, m.name, m.axis, m.index, m.k, m.owner, m.width, float(m.hi) - float(m.lo), m.day,
				(lay.stalls as Array).size(), kinds[0], kinds[1], kinds[2], kinds[3], (lay.vans as Array).size(),
				plan.district_at(mid), closed_mid, open_end, mid.x, mid.y])
			print("  EYE=%.1f,%.1f,%.1f,%.1f,-8  aerial EYE=%.1f,%.1f,%.1f,%.1f,-35" % [eye.x, plan.macro.relief_at(eye) + 1.7, eye.y, yaw,
				eye.x - along.x * 20.0, plan.macro.relief_at(eye) + 30.0, eye.y - along.y * 20.0, yaw])
	print("MARKETS %d in %d ms" % [found, Time.get_ticks_msec() - t0])
	var t1 := Time.get_ticks_usec()
	var meshes := {"canopy": FarmersMarketKit.canopy(), "folded": FarmersMarketKit.canopy_folded(), "bollard": FarmersMarketKit.bollard(), "sign": FarmersMarketKit.sign_post()}
	for k in 4:
		for v in int(FarmersMarketKit.VARIANTS[k]):
			meshes["goods_%d_%d" % [k, v]] = FarmersMarketKit.goods(k, v)
	for v in 2:
		meshes["packed_%d" % v] = FarmersMarketKit.packed(v)
	print("KIT built in %d ms" % ((Time.get_ticks_usec() - t1) / 1000))
	for key: String in meshes:
		var mesh: ArrayMesh = meshes[key]
		var arr := mesh.surface_get_arrays(0)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		print("  %s: %d tris near, aabb %s" % [key, idx.size() / 3, mesh.get_aabb()])
	var van := FarmersMarketBuild.van_mesh(0)
	print("VAN %s" % ["none" if van.is_empty() else "size %s offset %s length_x %s" % [van.size, van.offset, van.length_x]])
