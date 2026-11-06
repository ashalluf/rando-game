extends RefCounted
## The body of tools/film_shoot/probe.gd (loaded once the autoloads exist).

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
	var lo := Vector2(-6000, -6000)
	var hi := Vector2(6000, 6000)
	for a in OS.get_cmdline_user_args():
		var p := a.split(",")
		if p.size() == 4:
			lo = Vector2(p[0].to_float(), p[1].to_float())
			hi = Vector2(p[2].to_float(), p[3].to_float())
	var t0 := Time.get_ticks_msec()
	var c0 := FilmShoot._cell_of(lo)
	var c1 := FilmShoot._cell_of(hi)
	var n := 0
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var m := FilmShoot.decide(plan, Vector2i(cx, cz))
			if m.is_empty():
				continue
			n += 1
			var lay := FilmShoot.layout(m)
			var act: Dictionary = lay.action
			var mid := FilmShoot.point(m, float(act.t), 0.0)
			var along: Vector2 = FilmShoot.dirs(m)[0]
			var across: Vector2 = FilmShoot.dirs(m)[1]
			print("SHOOT %s  \"%s\" (%s, %s) axis %d road %d %s  width %.1f  len %.0f  district %d  owner %s  camp %d  vehicles %d" % [
				m.cell, m.title, m.company, m.code, m.axis, m.index, plan.road_name(int(m.axis), int(m.index)), float(m.width),
				float(m.hi) - float(m.lo), plan.district_at(mid), m.owner, (lay.camp as Array).size(), int(m.camp_side)])
			# EYEs: down the street from one end at head height, and from the set side's corner.
			var e0 := FilmShoot.point(m, float(m.lo) + 3.0, float(m.camp_side) * -1.5)
			var yaw := rad_to_deg(atan2(-along.x, -along.y))
			var gy := plan.macro.relief_at(e0) if plan.macro else 0.0
			print("  EYE street %.1f,%.1f,%.1f,%.1f,-4" % [e0.x, gy + 1.7, e0.y, yaw])
			var e1 := FilmShoot.point(m, float(act.t) - 18.0 * 1.0, float(m.camp_side) * (float(m.width) * 0.5 + 2.0))
			var to := FilmShoot.point(m, float(act.t), float(act.o)) - e1
			print("  EYE set %.1f,%.1f,%.1f,%.1f,-8" % [e1.x, gy + 3.2, e1.y, rad_to_deg(atan2(-to.x, -to.y))])
			var e2 := mid - across * float(m.camp_side) * 30.0 - along * 25.0
			var to2 := mid - e2
			print("  EYE aerial %.1f,%.1f,%.1f,%.1f,-30" % [e2.x, gy + 26.0, e2.y, rad_to_deg(atan2(-to2.x, -to2.y))])
	print("FILM SHOOTS %d in %d ms" % [n, Time.get_ticks_msec() - t0])
