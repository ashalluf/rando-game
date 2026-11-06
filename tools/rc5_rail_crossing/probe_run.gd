extends RefCounted
## The body of tools/light_rail/probe.gd (loaded once the autoloads exist).

func run(tree: SceneTree) -> void:
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
	var t0 := Time.get_ticks_msec()
	var lr := LightRail.of(plan)
	for k in lr.crossings.size():
		var c: Dictionary = lr.crossings[k]
		if not bool(c.gates):
			continue
		var n: Vector2i = c.node
		var w := plan.road_width(CityPlan.AXIS_X, n.x)
		var lanes := 2 if w > plan.street_width + 1.0 else 1
		var smp: Dictionary = lr.sample(float(c.s))
		var reach := float(smp.half) + 1.45 + 3.2
		print("XING k %d node %s x %.1f w %.1f lanes %d name %s district %s reach %.1f lane0 %.2f ground %.2f t_at %.1f" % [k, n, c.pos.x, w, lanes, plan.road_name(CityPlan.AXIS_X, n.x), plan.district_at(c.pos), reach, CityPlan.lane_center(w, lanes, 0), plan.height_at(c.pos), lr.trip_time_at(0, float(c.s))])
	s.free()
