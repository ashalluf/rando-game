extends RefCounted
## The body of tools/civic/probe.gd (loaded after the autoloads exist).

func run(tree: SceneTree) -> void:
	var seed_value := 1337
	var radius := 4000.0
	var at := Vector2(1200.0, 400.0)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = int(a.substr(7))
		elif a.begins_with("--radius="):
			radius = float(a.substr(9))
		elif a.begins_with("--at="):
			var p := a.substr(5).split(",")
			at = Vector2(float(p[0]), float(p[1]))
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var plan := CityPlan.new()
	plan.seed = seed_value
	plan.block_size_range = city.block_size_range
	plan.street_width = city.street_width
	plan.avenue_width = city.avenue_width
	plan.sidewalk_width = city.sidewalk_width
	plan.downtown_radius = city.downtown_radius
	plan.midtown_radius = city.midtown_radius
	city.free()
	var m := MacroMap.new()
	m.seed = seed_value
	m.setup()
	plan.macro = m
	var t0 := Time.get_ticks_usec()
	var list := CivicBuildings.near(plan, at, radius)
	var counts := {}
	for s: Dictionary in list:
		var k := CivicBuildings.kind_name(int(s.kind))
		counts[k] = int(counts.get(k, 0)) + 1
		var f: Dictionary = s.frame
		var n2: Vector2 = f.n
		var front: Vector2 = s.front
		var rw := plan.road_width(int(s.road[0]), int(s.road[1]))
		var eye := front - n2 * (rw * 0.5 + 2.0)
		var yaw := rad_to_deg(atan2(-n2.x, -n2.y))
		var g := m.relief_at(eye)
		var site: Rect2 = s.site
		var far := front - n2 * (rw * 0.5 + 26.0) + (f.a as Vector2) * 14.0
		var yaw2 := rad_to_deg(atan2(-(site.get_center() - far).x, -(site.get_center() - far).y))
		print("CIVIC %-16s %-16s %s district %d lots %d site %.0fx%.0f at (%.0f, %.0f)  EYE=%.1f,%.1f,%.1f,%.0f,6  EYE2=%.1f,%.1f,%.1f,%.0f,-14" % [
			CivicBuildings.kind_name(int(s.kind)), s.name, str(s.block), int(s.district), (s.lots as Array).size(), float(s.L), float(s.D),
			site.get_center().x, site.get_center().y, eye.x, g + 1.7, eye.y, yaw, far.x, m.relief_at(far) + 14.0, far.y, yaw2])
	print("REASONS ", CivicBuildings.reasons)
	print("CIVIC_TOTAL %d in %.0f m of %s: %s (%.0f ms)" % [list.size(), radius, str(at), str(counts), float(Time.get_ticks_usec() - t0) / 1000.0])
