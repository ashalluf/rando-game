extends Node
## LA hills probe (LaHills): per hill its relief, every street stretch over it with its grade
## (stairs past LaHills.STAIR_GRADE), the landmarks standing on it, the freeways, rail and river
## nearby, the districts; an EYE for the steepest street and for each stairway. Headless, seconds:
##   godot --headless --path . res://tools/la_hills/probe.tscn      (SEED=n, HILL=id, ALL=1 every stretch)
func _ready() -> void:
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	var only := OS.get_environment("HILL")
	var t0 := Time.get_ticks_msec()
	var macro := MacroMap.new()
	macro.seed = sd
	macro.setup()
	var plan := CityPlan.new()
	plan.seed = sd
	plan.macro = macro
	print("setup ms=", Time.get_ticks_msec() - t0)
	var lh: LaHills = macro.la_hills
	if lh == null:
		print("LA_HILLS off")
		get_tree().quit()
		return
	for hl: Dictionary in lh.hills():
		if only != "" and hl.id != only:
			continue
		var box: Rect2 = hl.box
		var top := 0.0
		var top_at := Vector2.ZERO
		var districts := {}
		var x := box.position.x
		while x < box.end.x:
			var z := box.position.y
			while z < box.end.y:
				var p := Vector2(x, z)
				var r := macro.relief_at(p)
				if r > top:
					top = r
					top_at = p
				if macro.zone_at(p) == MacroMap.Zone.CITY:
					var dn := str(CityPlan.District.keys()[macro.district_at(p)])
					districts[dn] = int(districts.get(dn, 0)) + 1
				z += 20.0
			x += 20.0
		print("\n== %s (%s) box=%s relief max %.1f at (%.0f, %.0f) districts=%s" % [hl.id, hl.name, box, top, top_at.x, top_at.y, districts])
		# Street stretches over it.
		var ix0 := plan._index_at(CityPlan.AXIS_X, box.position.x)
		var ix1 := plan._index_at(CityPlan.AXIS_X, box.end.x) + 1
		var iz0 := plan._index_at(CityPlan.AXIS_Z, box.position.y)
		var iz1 := plan._index_at(CityPlan.AXIS_Z, box.end.y) + 1
		var n := 0
		var stairs := 0
		var steep := 0
		var worst := 0.0
		var worst_drive := 0.0
		var worst_drive_txt := ""
		for axis: int in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
			var i0 := ix0 if axis == CityPlan.AXIS_X else iz0
			var i1 := ix1 if axis == CityPlan.AXIS_X else iz1
			var k0 := iz0 if axis == CityPlan.AXIS_X else ix0
			var k1 := iz1 if axis == CityPlan.AXIS_X else ix1
			for i in range(i0, i1 + 1):
				for k in range(k0, k1):
					var st := LaHills.stretch(plan, axis, i, k)
					if not st.has("near") or float(st.grade) < 0.02:
						continue
					n += 1
					var at := plan.road_pos(axis, i)
					var s: float = st.steep_at
					var p := Vector2(at, s) if axis == CityPlan.AXIS_X else Vector2(s, at)
					var is_st := LaHills.is_stairs(plan, axis, i, k)
					var name := plan.road_name(axis, i)
					var open := plan.road_open(axis, i, s)
					var txt := "  %s %s [%d k%d] grade %.0f%% h %.1f..%.1f at (%.0f, %.0f)%s%s" % [
						"X" if axis == CityPlan.AXIS_X else "Z", name, i, k, float(st.grade) * 100.0,
						st.h0, st.h1, p.x, p.y, " STAIRS" if is_st else "", "" if open else " closed"]
					worst = maxf(worst, st.grade)
					if is_st:
						stairs += 1
						var yaw := 180.0 if axis == CityPlan.AXIS_X else 90.0
						print(txt, "  EYE=%.0f,%.1f,%.0f,%.0f,8" % [p.x + (6.0 if axis == CityPlan.AXIS_X else 0.0), macro.relief_at(p) + 1.7, p.y + (0.0 if axis == CityPlan.AXIS_X else 6.0), yaw])
					else:
						if float(st.grade) > 0.15:
							steep += 1
						if open and float(st.grade) > worst_drive:
							worst_drive = st.grade
							worst_drive_txt = txt
						if OS.get_environment("ALL") == "1":
							print(txt)
		print("  stretches %d  steep(>15%%) %d  stairs %d  steepest %.0f%%  steepest open %.0f%%" % [n, steep, stairs, worst * 100.0, worst_drive * 100.0])
		print("  steepest open:", worst_drive_txt)
		# Landmarks on it.
		for lm: Dictionary in Landmarks.all():
			var a: Vector2 = lm.anchor
			if box.grow(100.0).has_point(a):
				print("  landmark %s at (%.0f, %.0f) r=%.0f lift %.1f relief %.1f" % [lm.id, a.x, a.y, lm.radius, LaHills.landmark_lift(plan, a), macro.relief_at(a)])
		# Freeways nearby.
		for fr in macro.freeway.routes:
			var pts: PackedVector2Array = fr.points
			var best := INF
			var bp := Vector2.ZERO
			for q in pts:
				var d := box.get_center().distance_to(q)
				if box.grow(150.0).has_point(q):
					var lr := lh.lift_raw(q)
					if lr > 0.5:
						print("  freeway %s over the hill at (%.0f, %.0f) lift %.1f" % [fr.name, q.x, q.y, lr])
						break
				if d < best:
					best = d
					bp = q
	for fr in macro.freeway.routes:
		var worst := 0.0
		var wq := Vector2.ZERO
		for q: Vector2 in (fr.points as PackedVector2Array):
			if lh.lift_raw(q) > worst:
				worst = lh.lift_raw(q)
				wq = q
		if worst > 0.0:
			print("freeway %s max lift %.2f at %s hill %s" % [fr.name, worst, wq, lh.hill_at(wq).get("id", "")])
	if macro.river:
		var worst := 0.0
		var wq := Vector2.ZERO
		for q: Vector2 in macro.river.pts:
			if lh.lift_raw(q) > worst:
				worst = lh.lift_raw(q)
				wq = q
		print("river max lift %.2f at %s" % [worst, wq])
	get_tree().quit()
