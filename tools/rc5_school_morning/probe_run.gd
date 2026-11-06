extends RefCounted
## The body of probe.gd (loaded once the autoloads exist).

func run(_tree: SceneTree) -> void:
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
	plan.macro.seed = plan.seed
	plan.macro.setup()
	s.free()
	var c := (OS.get_environment("CELL") if OS.get_environment("CELL") != "" else "-1,-1").split(",")
	var d := Schools.decide(plan, Vector2i(int(c[0]), int(c[1])))
	if d.is_empty():
		print("no school")
		return
	var pl := Schools.plan_for_school(plan, d)
	var fr: Dictionary = pl.fr
	print("NAME %s site %s fr.s %s fr.d %s A %.1f D %.1f" % [pl.full_name, pl.site, fr.s, fr.d, fr.A, fr.D])
	var road: Array = pl.front_road
	print("FRONT ROAD axis %d index %d pos %.2f width %.2f  sidewalk %.2f" % [int(road[0]), int(road[1]), plan.road_pos(int(road[0]), int(road[1])), plan.road_width(int(road[0]), int(road[1])), plan.sidewalk_width])
	print("BUS rect %s n %d axis %d spots %s" % [pl.bus_rect, pl.buses, pl.bus_axis, Schools.bus_spots(plan, pl)])
	for f: Dictionary in pl.fac:
		var extra := ""
		if f.t == "lawn":
			var gate: float = f.gate_s
			var sign_s := gate + (7.0 if gate + 9.0 < fr.A else -7.0)
			extra = "gate %s sign %s flag %s" % [Schools._lp(fr, gate, 0.0), Schools._lp(fr, sign_s, Schools.SETBACK * 0.5), Schools._lp(fr, gate - (6.0 if gate - 8.0 > 0.0 else -6.0), Schools.SETBACK * 0.55)]
		print("  %s %s %s %s" % [f.t, f.r, f.get("storeys", ""), extra])
	print("gy at site centre %.2f" % plan.macro.height_at((pl.site as Rect2).get_center()))
