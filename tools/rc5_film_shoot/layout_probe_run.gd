extends RefCounted

func run() -> void:
	var s = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
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
	var cell := Vector2i(int(OS.get_environment("CX")), int(OS.get_environment("CZ")))
	var m := FilmShoot.decide(plan, cell)
	var lay := FilmShoot.layout(m)
	print("SITE lo %.1f hi %.1f centre %.1f width %.1f camp_side %d dir %d" % [m.lo, m.hi, m.centre, m.width, m.camp_side, lay.dir])
	var pt := func(t: float, o: float) -> String:
		var p := FilmShoot.point(m, t, o)
		return "(%.1f, %.1f) gy %.2f" % [p.x, p.y, plan.macro.relief_at(p)]
	print("ENDS ", lay.ends)
	for c: Dictionary in lay.camp:
		print("CAMP %s t %.1f o %.1f -> %s" % [c.kind, c.t, c.o, pt.call(c.t, c.o)])
	print("TENT ", pt.call(lay.tent.t, lay.tent.o))
	print("TRACK t %.1f..%.1f o %.1f" % [lay.track.t0, lay.track.t1, lay.track.o])
	print("DOLLY ", pt.call(lay.dolly_t, lay.track.o))
	print("CRANE ", pt.call(lay.crane.t, lay.crane.o))
	for h: Dictionary in lay.hmis:
		print("HMI ", pt.call(h.t, h.o))
	print("BALLOON ", pt.call(lay.balloon.t, lay.balloon.o))
	print("VILLAGE ", pt.call(lay.village.t, lay.village.o))
	print("ACTION ", pt.call(lay.action.t, lay.action.o))
	print("DIRS ", FilmShoot.dirs(m))
