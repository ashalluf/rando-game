extends RefCounted
## The body of tools/worship/probe.gd (loaded once the autoloads exist).

func run(_tree: SceneTree) -> void:
	var seed_value := 1337
	var want := ""
	var near := Vector2.INF
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = int(a.substr(7))
		elif a.begins_with("--kind="):
			want = a.substr(7)
		elif a.begins_with("--near="):
			var p := a.substr(7).split(",")
			near = Vector2(float(p[0]), float(p[1]))
	var scene: PackedScene = load("res://scenes/levels/city.tscn")
	var sc = scene.instantiate()
	var plan := CityPlan.new()
	plan.seed = seed_value
	plan.block_size_range = sc.block_size_range
	plan.street_width = sc.street_width
	plan.avenue_width = sc.avenue_width
	plan.sidewalk_width = sc.sidewalk_width
	plan.downtown_radius = sc.downtown_radius
	plan.midtown_radius = sc.midtown_radius
	sc.free()
	var m := MacroMap.new()
	m.seed = seed_value
	m.setup()
	plan.macro = m
	var counts := {}
	var t0 := Time.get_ticks_msec()
	var found: Array[Dictionary] = []
	for cx in range(-10, 11):
		for cz in range(-10, 11):
			var s := Worship.for_cell(plan, Vector2i(cx, cz))
			if s.is_empty():
				continue
			found.append(s)
			var k: String = Worship.KIND_NAMES[int(s.kind)]
			counts[k] = int(counts.get(k, 0)) + 1
	print("WORSHIP %d sites in %d ms: %s  why %s" % [found.size(), Time.get_ticks_msec() - t0, counts, Worship.why])
	if near != Vector2.INF:
		found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a.site as Rect2).get_center().distance_to(near) < (b.site as Rect2).get_center().distance_to(near))
	for s: Dictionary in found:
		var k: String = Worship.KIND_NAMES[int(s.kind)]
		if want != "" and k != want:
			continue
		var f: Dictionary = s.frame
		var n: Vector2 = f.n
		var front := Industrial.fp(f, float(s.L) * 0.5, 0.0)
		var road: Array = s.road
		var rw := plan.road_width(int(road[0]), int(road[1]))
		var out := -n
		var yaw := rad_to_deg(atan2(out.x, out.y))
		var e1 := front + out * (rw + plan.sidewalk_width + 1.0)
		var e2 := front + out * (rw + plan.sidewalk_width + 1.0) + Vector2(-out.y, out.x) * 10.0
		var to_c := (front + n * float(s.D) * 0.45) - e2
		var yaw2 := rad_to_deg(atan2(-to_c.x, -to_c.y))
		var g := m.relief_at(front)
		if OS.get_environment("DEBUG") == "1":
			debug_site(plan, s)
		print("%-10s %-32s block %s site %s L %.0f D %.0f  EYE=%.1f,%.1f,%.1f,%.0f,8  EYE=%.1f,%.1f,%.1f,%.0f,-16" % [k, s.name, str(s.block),
			str((s.site as Rect2).get_center().round()), s.L, s.D, e1.x, 1.8, e1.y, yaw, e2.x, 13.0, e2.y, yaw2])


## DEBUG=1: why a site's chunk might not build it.
static func debug_site(plan: CityPlan, s: Dictionary) -> void:
	var bx: int = s.block.x
	var bz: int = s.block.y
	var role := plan.macro.replica.block_role(plan, bx, bz) if plan.macro.replica else -1
	print("  DEBUG block %s replica role %d district %d kind %d site %s" % [str(s.block), role, int(plan.block(bx, bz).district), int(plan.block(bx, bz).kind), str(s.site)])
	for lot: Dictionary in plan.lots(bx, bz):
		if (s.lots as Array).has(int(lot.seed)):
			var c: Vector2 = lot.center
			var fw: bool = plan.macro.freeway != null and plan.macro.freeway.blocks_rect(Rect2(c - Vector2(14, 14), Vector2(28, 28)), 0.0)
			print("    lot %s size %s yard %s builder %s freeway14 %s keys %s" % [str(c.round()), str((lot.size as Vector2).round()), str(lot.yard), str(int(lot.seed) == int(s.builder)), str(fw), str(lot.keys())])
