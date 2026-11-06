extends RefCounted
## The body of tools/car_park/probe.gd (loaded once the autoloads exist).

static func make_plan() -> CityPlan:
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
	return plan


func run(tree: SceneTree) -> void:
	var plan := make_plan()
	var box := Rect2(-4000.0, -4000.0, 9000.0, 9000.0)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		var v := (args[0] as String).split(",")
		box = Rect2(float(v[0]), float(v[1]), float(v[2]) - float(v[0]), float(v[3]) - float(v[1]))
	var t0 := Time.get_ticks_msec()
	var c0 := CarPark._cell_of(box.position)
	var c1 := CarPark._cell_of(box.end)
	var found: Array = []
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var s := CarPark.for_cell(plan, Vector2i(cx, cz))
			if s.is_empty():
				continue
			found.append(s)
			var lay: Dictionary = s.layout
			var site: Rect2 = s.site
			var f: Dictionary = s.frame
			var front := CarPark.world_xz(s, float(lay.entry_u), -plan.sidewalk_width - 4.0)
			var look := CarPark.world_xz(s, float(lay.entry_u), 6.0)
			var eye := front + (front - look).normalized() * 14.0 + (f.a as Vector2) * -12.0
			var to: Vector2 = CarPark.world_xz(s, float(lay.u0) + float(lay.ls) * 0.5, 10.0) - eye
			var yaw := rad_to_deg(atan2(-to.x, -to.y))
			var gy: float = CarPark.ground_y(plan, s)
			print("CARPARK %s block %s district %d site %s side %d L %.1f D %.1f ls %.1f ds %.1f modules %d decks %d stalls/row %d lots %d  EYE=%.1f,%.1f,%.1f,%.1f,8" % [
				s.name, s.block, plan.block((s.block as Vector2i).x, (s.block as Vector2i).y).district, site, s.side, lay.L, lay.D, lay.ls, lay.ds,
				lay.modules, lay.decks, lay.stalls, (s.lots as Array).size(), eye.x, gy + 9.0, eye.y, yaw])
	print("CARPARKS %d in %d ms" % [found.size(), Time.get_ticks_msec() - t0])
