extends RefCounted
## Body of tools/rc5_friday_lights/probe.gd: every high school in the basin with game_night, its
## track, stands, scoreboard, parking and the light standards' feet.
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
	var c0 := Schools._cell_of(Vector2(-7000, -7000))
	var c1 := Schools._cell_of(Vector2(7000, 7000))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var d := Schools.decide(plan, Vector2i(cx, cz))
			if d.is_empty() or not d.high:
				continue
			var pl := Schools.plan_for_school(plan, d)
			print("HIGH %s '%s' game_night %s site %s front %d" % [d.cell, pl.full_name, pl.game_night, pl.site, pl.front])
			for f: Dictionary in pl.fac:
				if true:
					print("   %s r %s c %s u %s" % [f.t, f.r, f.get("c"), f.get("u")])
					if f.t == "track":
						print("      R %s S %s lanes %s football %s L %s W %s gy %.1f" % [f.R, f.S, f.lanes, f.football, f.L, f.W, plan.macro.height_at((f.r as Rect2).get_center())])
