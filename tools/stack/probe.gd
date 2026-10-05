extends SceneTree
## The four-level stack's plan (FreewayStack): levels, connectors, heights, columns. Headless, seconds:
##   godot --headless --path . --script tools/stack/probe.gd     (SEED=n for another seed)
func _initialize() -> void:
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	var t0 := Time.get_ticks_msec()
	var macro := MacroMap.new()
	macro.seed = sd
	macro.setup()
	var fw: Freeway = macro.freeway
	print("setup ms=", Time.get_ticks_msec() - t0)
	var st: FreewayStack = fw.stack
	if st == null:
		print("NO STACK")
		quit()
		return
	print("centre ", st.centre, " low ", fw.routes[st.low].name, " high ", fw.routes[st.high].name, " levels ", st.levels)
	for k in st.links.size():
		var l: Dictionary = st.links[k]
		var hs: PackedFloat32Array = l.heights
		var mx := 0.0
		for i in range(1, hs.size()):
			mx = maxf(mx, absf(hs[i] - hs[i - 1]) / (l.run[i] - l.run[i - 1]))
		var be := 0.0
		for e in l.bank:
			be = maxf(be, absf(e))
		print("link %d level %d from %d(%d) to %d(%d) len %.0f h %.1f..%.1f maxgrade %.3f bank %.3f pts %d" % [k, l.level, l.from, l.from_sign, l.to, l.to_sign, l.length, hs[0], hs[hs.size() - 1], mx, be, hs.size()])
		var line := ""
		for i in range(0, hs.size(), 4):
			line += "%.0f " % hs[i]
		print("   ", line)
	print("open edges ", st.open_edges.size(), " covered ", st.covered.size())
	var plan := CityPlan.new()
	plan.seed = sd
	plan.macro = macro
	var cols := st.columns(plan)
	print("columns ", cols.size(), " skipped bents ", st._skip_bents.keys())
	var mains := {st.low: [fw.routes[st.low].points, fw.routes[st.low].heights, FreewayStack._runs(fw.routes[st.low].points), float(fw.routes[st.low].width)],
		st.high: [fw.routes[st.high].points, fw.routes[st.high].heights, FreewayStack._runs(fw.routes[st.high].points), float(fw.routes[st.high].width)]}
	print("verify ", st.verify_all(mains, st.links))
	# EYEs for stills: on each connector, a driver's eye a third of the way along, looking ahead.
	for k in st.links.size():
		var l: Dictionary = st.links[k]
		for frac: float in [0.35, 0.5]:
			var i := int((l.points as PackedVector2Array).size() * frac)
			var s: float = l.run[i]
			var f := FreewayStack.frame(l, i)
			var d: Vector2 = f[3]
			var r: Vector2 = f[1]
			var p: Vector3 = (f[0] as Vector3) + Vector3(r.x * -2.5, -2.5 * float(f[2]) + 1.3, r.y * -2.5)
			print("EYE link %d at %.0f: %.2f,%.2f,%.2f,%.1f,%.1f" % [k, s, p.x, p.y, p.z, rad_to_deg(atan2(-d.x, -d.y)), -3.0])
	print("ramps near ", fw.ramps_in(Rect2(st.centre - Vector2.ONE * 600, Vector2.ONE * 1200)).size())
	quit()
