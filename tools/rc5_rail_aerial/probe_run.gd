extends RefCounted
## Body of tools/rc5_rail_aerial/probe.gd: where the Coral Line's structure crosses each freeway,
## the columns there, and the line's samples round each flyover.

func run(tree: SceneTree) -> void:
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
	var lr := LightRail.of(plan)
	var fw = plan.macro.freeway
	poles_near(lr, 2200, 2800)
	for f in lr.flyovers:
		var smp := lr.sample(f.s)
		var segs: Array = fw.segments_in(Rect2(smp.pos - Vector2(30, 30), Vector2(60, 60)))
		var names := {}
		for g in segs:
			names[fw.routes[int(g.route)].name if int(g.route) < fw.routes.size() else "link"] = true
		print("FLYOVER s %.0f at (%.1f, %.1f) dir (%.2f, %.2f) rail %.1f street %.1f deck %.1f routes %s" % [f.s, smp.pos.x, smp.pos.y, smp.dir.x, smp.dir.y, smp.y, plan.height_at(smp.pos), f.deck, names.keys()])
		for k in range(-6, 7):
			var ss: float = f.s + k * 15.0
			var q := lr.sample(ss)
			print("   s %.0f (%.1f, %.1f) mode %d rail %.1f blocked %s" % [ss, q.pos.x, q.pos.y, q.mode, q.y, fw.blocks(q.pos, 2.5)])


static func routes_near(plan: CityPlan, rect: Rect2) -> void:
	var fw = plan.macro.freeway
	for g in fw.segments_in(rect):
		var a: Vector2 = g.a
		if rect.has_point(a):
			print("   SEG route %d %s a (%.0f, %.0f) h %.1f width %.0f" % [g.route, fw.routes[int(g.route)].name if int(g.route) < fw.routes.size() else "link", a.x, a.y, g.ha, g.width])


static func poles_near(lr: LightRail, s0: float, s1: float) -> void:
	for s in lr.poles:
		if s >= s0 and s <= s1:
			var q := lr.sample(s)
			print("   POLE s %.1f (%.1f, %.1f) mode %d rail %.1f" % [s, q.pos.x, q.pos.y, q.mode, q.y])
