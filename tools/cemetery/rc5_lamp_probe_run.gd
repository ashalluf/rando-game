extends RefCounted
## The body of tools/cemetery/rc5_lamp_probe.gd (loaded once the autoloads exist).

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
	var pl: Dictionary = Cemetery.plan_for(plan, 17, 30)
	print("CROWN ", pl.crown, " H ", pl.H, " gate ", pl.gate, " maus ", pl.mausoleum)
	for p in pl.lamps:
		print("LAMP ", p, " rise %.2f gy %.2f" % [Cemetery.height(pl, p), plan.macro.height_at(p)])
