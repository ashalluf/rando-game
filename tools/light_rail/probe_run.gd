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
	print("RAIL resolved in %d ms: length %.0f m, %d samples, boulevard z %.1f (%s), avenue x %.1f" % [Time.get_ticks_msec() - t0, lr.length, lr.pts.size(), lr.boulevard_z, plan.road_name(1, lr.boulevard_index), lr.avenue_x])
	var last := -1
	for i in lr.pts.size():
		if lr.mode[i] != last:
			print("  mode %d from s %.0f at (%.0f, %.0f) rail %.1f street %.1f" % [lr.mode[i], lr.run[i], lr.pts[i].x, lr.pts[i].y, lr.rail[i], lr.street[i]])
			last = lr.mode[i]
	var hmax := 0.0
	for i in lr.pts.size():
		hmax = maxf(hmax, lr.rail[i] - lr.street[i])
	var worst := 0.0
	var wi := 0
	for i in range(1, lr.pts.size()):
		if lr.run[i] < lr.daylight_s + 2.0:
			continue
		var g := absf(lr.rail[i] - lr.rail[i - 1]) / maxf(lr.run[i] - lr.run[i - 1], 0.01)
		if g > worst:
			worst = g
			wi = i
	print("  steepest %.1f %% at s %.0f (%.0f, %.0f) rail %.2f -> %.2f run %.2f -> %.2f mode %d" % [worst * 100.0, lr.run[wi], lr.pts[wi].x, lr.pts[wi].y, lr.rail[wi - 1], lr.rail[wi], lr.run[wi - 1], lr.run[wi], lr.mode[wi]])
	print("  highest over the street: %.1f m; mouth s %.0f daylight s %.0f" % [hmax, lr.mouth_s, lr.daylight_s])
	for st in lr.stations:
		print("  STATION %s s %.0f at (%.0f, %.0f) mode %d y %.1f" % [st.name, st.s, st.pos.x, st.pos.y, st.mode, st.y])
	for c in lr.crossings:
		print("  CROSSING node %s s %.0f at (%.0f, %.0f) gates %s" % [c.node, c.s, c.pos.x, c.pos.y, c.gates])
	for iz in range(5, 20):
		print("  road z %.1f w %.0f %s" % [plan.road_pos(1, iz), plan.road_width(1, iz), plan.road_name(1, iz)])
	for f in lr.flyovers:
		print("  FLYOVER s %.0f deck %.1f rail %.1f" % [f.s, f.deck, lr.sample(f.s).y])
	print("  trips %.0f / %.0f s, fleet %d, headway %.0f s" % [lr.trip_len[0], lr.trip_len[1], lr.fleet, lr.headway])
	for t in [3600.0, 3700.0, 3800.0]:
		var tr := lr.trains_at(t)
		var line := "  t %.0f:" % t
		for x in tr:
			line += " [#%d dir %d s %.0f v %.1f%s]" % [x.id, x.dir, x.s, x.v, " dwell" if x.dwell else ""]
		print(line)
	for k in [3, 6]:
		var tc := lr.clock_at_crossing(k, 0, 2.0)
		var line := "  crossing %d s %.0f clock %.1f:" % [k, lr.crossings[k].s, tc]
		for x in lr.trains_at(tc):
			line += " [#%d dir %d s %.0f v %.1f]" % [x.id, x.dir, x.s, x.v]
		print(line, " t_at %.1f" % lr.trip_time_at(0, lr.crossings[k].s), " phase ", lr.crossing_phase(lr.crossings[k], tc))
	s.free()
