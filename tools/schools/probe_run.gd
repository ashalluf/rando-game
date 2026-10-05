extends RefCounted
## The body of tools/schools/probe.gd (loaded once the autoloads exist).

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
	var high := 0
	var c0 := Schools._cell_of(box.position)
	var c1 := Schools._cell_of(box.end)
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var d := Schools.decide(plan, Vector2i(cx, cz))
			if d.is_empty():
				continue
			found += 1
			if d.high:
				high += 1
			var pl := Schools.plan_for_school(plan, d)
			var site: Rect2 = pl.site
			var b := plan.block((d.blocks[0] as Vector2i).x, (d.blocks[0] as Vector2i).y)
			var kinds := {}
			for f: Dictionary in pl.fac:
				kinds[f.t] = int(kinds.get(f.t, 0)) + 1
			var fr: Dictionary = pl.fr
			# An EYE on the street in front, looking at the entry.
			var gate := site.get_center()
			for f: Dictionary in pl.fac:
				if f.t == "lawn":
					gate = Schools._lp(fr, f.gate_s, 0.0)
			var eye := gate - (fr.d as Vector2) * 18.0 + (fr.s as Vector2) * 14.0
			var to := gate + (fr.d as Vector2) * 8.0 - eye
			var yaw := rad_to_deg(atan2(-to.x, -to.y))
			print("SCHOOL %s %s '%s' district %d blocks %s roads %s site %s (%.0f x %.0f) front %d %s" % [
				"HIGH" if d.high else "ELEM", d.cell, pl.full_name, int(b.district), d.blocks, d.roads, site.position.round(), site.size.x, site.size.y, pl.front, kinds])
			for f: Dictionary in pl.fac:
				if f.t == "track" or f.t == "gym" or f.t == "auditorium":
					print("   %s at %s size %s" % [f.t, (f.r as Rect2).get_center().round(), (f.r as Rect2).size.round()])
			print("   BUS spots %s" % [Schools.bus_spots(plan, pl)])
			print("   EYE=%.1f,%.1f,%.1f,%.1f,-4  centre %s  gy %.1f" % [eye.x, 1.7 + plan.macro.height_at(eye), eye.y, yaw, site.get_center().round(), plan.macro.height_at(site.get_center())])
	print("WHY %s" % [Schools.why])
	print("SCHOOLS %d (%d high) in %d ms" % [found, high, Time.get_ticks_msec() - t0])
