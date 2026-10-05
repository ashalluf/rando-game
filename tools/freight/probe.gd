extends SceneTree
## Freight rail probe (FreightRail): the line's sections, junctions, crossings, the timetable and a
## few consists. Headless, seconds:
##   godot --headless --path . --script tools/freight/probe.gd      (SEED=n for another seed)
func _initialize() -> void:
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	var t0 := Time.get_ticks_msec()
	var macro := MacroMap.new()
	macro.seed = sd
	macro.setup()
	var plan := CityPlan.new()
	plan.seed = sd
	plan.macro = macro
	var t1 := Time.get_ticks_msec()
	var fr := FreightRail.of(plan)
	print("setup ms=", t1 - t0, " resolve ms=", Time.get_ticks_msec() - t1)
	if fr == null:
		print("NO LINE")
		quit()
		return
	print("avenue x=%.1f idx=%d w=%.1f east x=%.1f idx=%d" % [fr.avenue_x, fr.avenue_index, fr.avenue_width, fr.east_x, fr.east_index])
	print("z0=%.1f length=%.0f yard rect=%s yard_n=%d yard_s=%d" % [fr.z0, fr.length, fr.yard_rect, fr.yard_n, fr.yard_s])
	print("s: yard_end=%.0f grade0=%.0f grade1=%.0f mouth=%.0f hide=%.0f xo=%.0f  (z %.0f %.0f %.0f %.0f)" % [fr.s_yard_end, fr.s_grade0, fr.s_grade1, fr.s_mouth, fr.s_hide, fr.s_xo, fr.z0 + fr.s_yard_end, fr.z0 + fr.s_grade0, fr.z0 + fr.s_grade1, fr.z0 + fr.s_mouth])
	var s := 0.0
	while s < fr.s_mouth + 100.0:
		print("  s=%5.0f z=%5.0f street=%6.2f rail=%6.2f drop=%5.2f mode=%d" % [s, fr.z0 + s, fr.street_at(s), fr.rail_at(s), fr.street_at(s) - fr.rail_at(s), fr.mode_at(s)])
		s += 100.0
	var names := ["YARD", "BRIDGE", "CLOSED", "CROSSING", "COVERED"]
	for j in fr.junctions:
		print("  junction k=%d z=%.1f w=%.0f s=%.0f %s %s" % [j.k, j.z, j.w, j.s, names[j.kind], plan.road_name(CityPlan.AXIS_Z, j.k)])
	print("crossings=", fr.crossings.size(), " headway=", fr.headway)
	for n in range(3, 8):
		var c := fr.consist(n)
		var counts := {}
		for car in c.cars:
			counts[car.type] = counts.get(car.type, 0) + 1
		var tr := fr.trips_for(float(c.len))
		print("  trip %d kind=%d cars=%d len=%.0f types=%s T_nb=%.0f T_sb=%.0f" % [n, c.kind, c.cars.size(), c.len, counts, tr.T_nb, tr.T_sb])
	var t := 5400.0
	for k in 12:
		var tt := t + k * 120.0
		var ts := fr.trains_at(tt)
		var line := "  t=%.0f:" % tt
		for st in ts:
			line += " [n%d ph%d sA=%.0f v=%.1f hid=%s]" % [st.n, st.phase, st.sA, st.v, fr.hidden(st)]
		print(line)
	if fr.crossings.size() > 0:
		var c0: Dictionary = fr.crossings[0]
		var closed_t := 0.0
		var tt := 0.0
		while tt < fr.headway * 3.0:
			if fr.crossing_phase(c0, 5400.0 + tt) > 0.0:
				closed_t += 5.0
			tt += 5.0
		print("crossing 0 closed %.0f s of %.0f" % [closed_t, fr.headway * 3.0])
	# Freeway bents near the line (columns at +-0.26 of the deck's half width off the route).
	var pe := int(round(Freeway.PILLAR_SPACING / Freeway.STEP))
	for seg in macro.freeway.segments_in(Rect2(fr.avenue_x - 40.0, fr.z0, 80.0, fr.s_mouth)):
		if int(seg.index) % pe != 0:
			continue
		var a: Vector2 = seg.a
		var b: Vector2 = seg.b
		var d := (b - a).normalized()
		var nrm := Vector2(-d.y, d.x)
		for side: float in [-1.0, 1.0]:
			var col := a + nrm * float(seg.width) * 0.5 * 0.26 * side
			if absf(col.x - fr.avenue_x) < 20.0 and col.y > fr.z0 and col.y < fr.z0 + fr.s_mouth:
				print("  BENT column at ", col, " off=", col.x - fr.avenue_x, " s=", col.y - fr.z0)
	quit()
