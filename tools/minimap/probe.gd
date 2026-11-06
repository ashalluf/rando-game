extends SceneTree
## Map probe (MapData, GpsRoute): how many blocks the whole-basin map holds, what building its
## records costs, and a few GPS routes across the city with their timing. Headless, seconds:
##   godot --headless --path . --script tools/minimap/probe.gd      (SEED=n for another seed)
func _initialize() -> void:
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	var t0 := Time.get_ticks_msec()
	var macro := MacroMap.new()
	macro.seed = sd
	macro.setup()
	var plan := CityPlan.new()
	plan.seed = sd
	plan.macro = macro
	print("setup ms=", Time.get_ticks_msec() - t0)
	t0 = Time.get_ticks_msec()
	var data := MapData.new(plan)
	while not data.warm(50000):
		pass
	print("map data ms=", Time.get_ticks_msec() - t0, " blocks=", data.blocks.size(), " grid=", data.lo, "..", data.hi)
	var counts := {}
	for b: Dictionary in data.blocks:
		counts[b.kind] = int(counts.get(b.kind, 0)) + 1
	print("kinds ", counts)
	print("district labels ", data.district_labels.size())
	for l in data.district_labels:
		print("  ", l.name, " at ", l.pos)
	var trips := [[Vector2(2800, 100), Vector2(-300, 1200)], [Vector2(2800, 100), Vector2(3000, 5600)],
		[Vector2(300, 300), Vector2(4200, 2400)], [Vector2(-500, -400), Vector2(2600, -450)]]
	for trip in trips:
		t0 = Time.get_ticks_usec()
		var r := GpsRoute.new(plan, trip[0], trip[1])
		var steps := 0
		while not r.step(4000):
			steps += 1
		print("route ", trip, " ok=", r.ok, " points=", r.points.size(), " length=%.0f expanded=%d steps=%d ms=%.1f" % [r.length, r.expanded, steps, (Time.get_ticks_usec() - t0) / 1000.0])
	quit()
