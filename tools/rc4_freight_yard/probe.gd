extends SceneTree
## The freight yard refcam's framing probe (rc4-freight-yard): the yard's rect, its tracks, masts,
## cranes and the departing train's ends over a minute of its pull-out. Headless, seconds:
##   godot --headless --path . --script tools/rc4_freight_yard/probe.gd   (INTO=<s into the stand>)
func _initialize() -> void:
	await process_frame
	var macro = load("res://scripts/world/macro_map.gd").new()
	macro.seed = 1337
	macro.setup()
	var plan = load("res://scripts/world/city_plan.gd").new()
	plan.seed = 1337
	plan.macro = macro
	var fr = load("res://scripts/world/freight_rail.gd").of(plan)
	var lay: Dictionary = load("res://scripts/world/freight_yard.gd").layout(fr)
	print("avenue x=%.1f z0=%.1f yard=%s yard_end s=%.0f" % [fr.avenue_x, fr.z0, fr.yard_rect, fr.s_yard_end])
	for t in lay.tracks:
		print("track x=%.1f z %.0f..%.0f loading=%s" % [t.x, t.z0, t.z1, t.loading])
	var ext := {}
	for c in lay.cuts:
		var j: int = c.track
		if not ext.has(j):
			ext[j] = [1e9, -1e9, 0]
		ext[j][0] = minf(ext[j][0], float(c.z)); ext[j][1] = maxf(ext[j][1], float(c.z)); ext[j][2] += 1
	for j in ext:
		print("cuts track %d z %.0f..%.0f n=%d" % [j, ext[j][0], ext[j][1], ext[j][2]])
	print("ladder ", lay.ladder, " cranes ", lay.cranes, " tower ", lay.tower)
	print("masts ", lay.masts)
	var base: float = fr.clock_at_yard(0.0)
	for into in [100.0, 140.0, 150.0, 160.0, 170.0, 180.0, 190.0, 200.0, 210.0, 220.0, 240.0, 260.0]:
		for st in fr.trains_at(base + into):
			if absf(float(st.sA)) < 3000.0:
				print("into=%.0f n=%d phase=%s sA=%.1f (z %.1f) v=%.2f dir=%s len=%.0f" % [into, st.n, str(st.phase), st.sA, fr.z0 + float(st.sA), st.v, str(st.dir), st.len])
	quit()
