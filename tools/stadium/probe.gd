extends SceneTree
## Ballpark probe: the ground round the site, the zones, the hill roads and estates near it, the
## freeways. Headless, seconds:  godot --headless --path . --script tools/stadium/probe.gd
func _initialize() -> void:
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	var macro := MacroMap.new()
	macro.seed = sd
	macro.setup()
	var plan := CityPlan.new()
	plan.seed = sd
	plan.macro = macro
	var c := Vector2(2010.0, -2850.0)
	if OS.get_environment("AT") != "":
		var p := OS.get_environment("AT").split(",")
		c = Vector2(float(p[0]), float(p[1]))
	var span := float(OS.get_environment("SPAN")) if OS.get_environment("SPAN") != "" else 600.0
	var step := span / 8.0
	print("raw / height (zone) around ", c, " step ", step)
	for j in range(-8, 9):
		var line := "z=%6.0f " % (c.y + j * step)
		for i in range(-8, 9):
			var p := c + Vector2(i * step, j * step)
			var z := macro.zone_at(p)
			line += "%4.0f%s " % [macro.height_at(p), "h" if z == MacroMap.Zone.HILLS else ("c" if z == MacroMap.Zone.CITY else "?")]
		print(line)
	var area := Rect2(c - Vector2(span, span), Vector2(span, span) * 2.0)
	for s in macro.hill_roads.segments_in(area):
		print("road seg ", s.get("name", ""), " ", s.a, " ", s.b, " w=", s.width)
	for m in macro.hill_roads.mansions_in(area):
		print("estate ", m.pos)
	for fr in macro.freeway.routes:
		for p in fr.points:
			if area.has_point(p):
				print("freeway ", fr.name, " ", p)
				break
	var idx := plan.block_index_at(c)
	print("block ", idx, " rect ", plan.block(idx.x, idx.y).rect, " district ", plan.district_at(c))
	for i in range(-4, 5):
		print(" x road ", idx.x + i, " at ", plan.road_pos(0, idx.x + i), "  z road ", idx.y + i, " at ", plan.road_pos(1, idx.y + i))
	# The site: cut and fill over the pad, and each ballpark road's bed against the ground.
	var cut := 0.0
	var fill := 0.0
	var n := 0
	var u := -Ballpark.SITE_U
	while u <= Ballpark.SITE_U:
		var v := Ballpark.SITE_V0
		while v <= Ballpark.SITE_V1:
			var q := Vector2(u, v)
			if Ballpark.site_sd(q) < 0.0:
				var p := Ballpark.world(u, v)
				var nat := macro.raw_height_at(p) + macro.relief_at(p)
				var d := nat - Ballpark.level(q)
				cut = maxf(cut, d)
				fill = maxf(fill, -d)
				n += 1
			v += 20.0
		u += 20.0
	print("site samples ", n, " max cut %.0f max fill %.0f" % [cut, fill])
	for rn in ["Sunridge Dr", "Stadium Way"]:
		var r := Ballpark.road(macro, rn)
		if r.is_empty():
			print("no road ", rn)
			continue
		var pts: PackedVector2Array = r.points
		var worst := 0.0
		var length := 0.0
		var g := 0.0
		for i in pts.size():
			var p := pts[i]
			var nat := Ballpark.carve(p, macro.raw_height_at(p) + macro.relief_at(p))
			var d: float = nat - float(r.heights[i])
			if absf(d) > absf(worst):
				worst = d
			if i > 0:
				length += pts[i].distance_to(pts[i - 1])
				g = maxf(g, absf(float(r.heights[i]) - float(r.heights[i - 1])) / pts[i].distance_to(pts[i - 1]))
			if OS.get_environment("ROADS") != "" and i % 5 == 0:
				print("   %s %d (%.0f, %.0f) bed %.1f ground %.1f" % [rn, i, p.x, p.y, r.heights[i], nat])
		print("road ", rn, " length %.0f bed %.1f -> %.1f worst earthwork %.1f max grade %.3f" % [length, r.heights[0], r.heights[r.heights.size() - 1], worst, g])
	quit()
