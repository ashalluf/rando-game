extends SceneTree
## LA River probe (LaRiver): the route, its land level, which streets bridge it and which end at
## the bank, the ramps and the rail bridge, the river blocks. Headless, seconds:
##   godot --headless --path . --script tools/la_river/probe.gd      (SEED=n for another seed)
func _initialize() -> void:
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	var t0 := Time.get_ticks_msec()
	var macro := MacroMap.new()
	macro.seed = sd
	macro.setup()
	var plan := CityPlan.new()
	plan.seed = sd
	plan.macro = macro
	var rv: LaRiver = macro.river
	print("setup ms=", Time.get_ticks_msec() - t0, " length=%.0f points=%d" % [rv.length, rv.pts.size()])
	var s := 0.0
	while s <= rv.length:
		var p: Vector2 = rv.at(s)[0]
		print("s=%5.0f p=(%.0f, %.0f) top=%.2f toe=%.2f water=%.2f bed_half=%.1f top_half=%.1f zone=%s relief=%.2f" % [s, p.x, p.y, rv.top_at(s), rv.toe_at(s), rv.water_at(s), rv.bed_half(s), rv.top_half(s), MacroMap.zone_name(macro.zone_at(p)), macro.relief_at(p)])
		s += 500.0
	t0 = Time.get_ticks_msec()
	var brs := rv.bridges(plan)
	print("classify ms=", Time.get_ticks_msec() - t0)
	var closed := 0
	for k in rv._segs:
		if rv._segs[k] == LaRiver.Seg.CLOSED:
			closed += 1
	print("segments closed=", closed, " bridges=", brs.size())
	for b in brs:
		print("  bridge ", ["ARCH", "RIBBON", "GIRDER", "RAIL"][b.kind], " ", b.name, " s=%.0f p=(%.0f, %.0f) skew=%.0f span=%.1f owner=%s" % [b.s, b.p.x, b.p.y, b.skew, b.t1 - b.t0, b.owner])
	for r in rv.ramps(plan):
		print("  ramp s0=%.0f s1=%.0f side=%d owner=%s" % [r.s0, r.s1, r.side, r.owner])
	print("  rail ", rv.rail_bridge(plan))
	var roles := 0
	for ix in range(-10, 60):
		for iz in range(-40, 90):
			var r := plan.owned_rect(ix, iz)
			if r.position.x > 3800 and r.position.x < 5000 and plan.river_block(ix, iz):
				roles += 1
	print("river blocks=", roles)
	for fr in macro.freeway.routes:
		var pts: PackedVector2Array = fr.points
		for i in pts.size() - 1:
			var f := rv.channel_floor(pts[i])
			if f < INF:
				print("  freeway ", fr.name, " over the channel at ", pts[i], " deck=%.1f floor=%.1f" % [fr.heights[i], f])
				break
	quit()
