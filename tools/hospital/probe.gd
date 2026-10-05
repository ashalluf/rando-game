extends Node
## Hospital probe (Hospital): every hospital on the map with its block, frame, name, storeys,
## district and an EYE for still_shot.gd (from the front street, the ER street and the air).
## Headless, seconds:  godot --headless --path . tools/hospital/probe.tscn   (SEED=n)
func _ready() -> void:
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
	var found: Array[Vector2i] = []
	var med := Hospital.medical_block(plan)
	print("medical block ", med, " ms=", Time.get_ticks_msec() - t0)
	if med != Vector2i.MAX:
		found.append(med)
	t0 = Time.get_ticks_msec()
	for cx in range(-5, 6):
		for cz in range(-4, 7):
			var bi := Hospital.cell_block(plan, Vector2i(cx, cz))
			if bi != Vector2i.MAX:
				found.append(bi)
	print("cells ms=", Time.get_ticks_msec() - t0, " hospitals=", found.size())
	for bi in found:
		var b := plan.block(bi.x, bi.y)
		var lay := Hospital.layout(plan, bi.x, bi.y)
		var c := (lay.inner as Rect2).get_center()
		var front := Hospital.fp(lay, float(lay.W) * 0.5, -40.0)
		var er := Hospital.er_goal(lay) + (lay.a as Vector2) * 30.0
		var gy := macro.relief_at(c)
		var to := Hospital.fp(lay, float(lay.W) * 0.5, 10.0)
		var yaw_f := rad_to_deg(atan2(-(to - front).x, -(to - front).y))
		var bay := Hospital.fp(lay, (lay.court as Rect2).position.x, (lay.canopy as Rect2).get_center().y)
		var yaw_e := rad_to_deg(atan2(-(bay - er).x, -(bay - er).y))
		print("%s %s grounds=%s kind=%d district=%d W=%.0f D=%.0f storeys=%d garage=%s lot=%s er_right=%s centre=(%.0f,%.0f) relief=%.2f" % [
			bi, lay.name, b.get("grounds", ""), int(b.kind), int(b.district), lay.W, lay.D, lay.storeys, (lay.garage as Rect2).size.x > 0.0, (lay.lot as Rect2).size.x > 0.0, lay.er_right, c.x, c.y, gy])
		print("   EYE front %.1f,%.1f,%.1f,%.1f,8" % [front.x, gy + 1.8, front.y, yaw_f])
		print("   EYE er    %.1f,%.1f,%.1f,%.1f,2" % [er.x, gy + 1.7, er.y, yaw_e])
		for sc in ["front", "bay", "roof", "aerial"]:
			print("   STAGE %s %s" % [sc, HospitalStage.eye_for(lay, sc)])
		var air := front + (front - c).normalized() * 60.0
		print("   EYE air   %.1f,%.1f,%.1f,%.1f,-30" % [air.x, gy + 90.0, air.y, yaw_f])
		# The lots the block would have had (none now) and its neighbours untouched.
		if not plan.lots(bi.x, bi.y).is_empty():
			print("   ERROR: lots on a hospital block")
	if OS.get_environment("WHY") == "1":
		_why(plan)
	get_tree().quit()


## Why candidate blocks fail (WHY=1): the first failing test of every block in the cells' range.
func _why(plan: CityPlan) -> void:
	var macro := plan.macro
	var counts := {}
	for cx in range(-5, 6):
		for cz in range(-4, 7):
			for k in Hospital.CANDIDATES:
				var sd := plan.seed
				var target := Vector2((float(cx) + lerpf(0.15, 0.85, Hospital._h01([sd, cx, cz, k, "hx"]))) * Hospital.CELL,
						(float(cz) + lerpf(0.15, 0.85, Hospital._h01([sd, cx, cz, k, "hz"]))) * Hospital.CELL)
				var reason := "ok"
				if macro.zone_at(target) != MacroMap.Zone.CITY:
					reason = "zone_target"
				else:
					var bi := plan.block_index_at(target)
					var rect := Hospital.block_rect(plan, bi.x, bi.y)
					var inner := rect.grow(-plan.sidewalk_width)
					var lo := INF
					var hi := -INF
					for p: Vector2 in [rect.position, rect.end, rect.get_center()]:
						lo = minf(lo, macro.relief_at(p))
						hi = maxf(hi, macro.relief_at(p))
					if minf(inner.size.x, inner.size.y) < Hospital.MIN_INNER.x or maxf(inner.size.x, inner.size.y) < Hospital.MIN_INNER.y:
						reason = "size"
					elif not (int(plan.district_at(rect.get_center())) in Hospital.DISTRICTS):
						reason = "district%d" % int(plan.district_at(rect.get_center()))
					elif DowntownReal.in_extent(rect.get_center()) or Landmarks.claims(rect):
						reason = "downtown"
					elif macro.freeway and macro.freeway.blocks_rect(rect, 8.0):
						reason = "freeway"
					elif hi - lo >= 2.5:
						reason = "relief"
					elif not Hospital._suitable(plan, bi.x, bi.y, Hospital.DISTRICTS, Hospital.MIN_INNER):
						reason = "other"
				counts[reason] = int(counts.get(reason, 0)) + 1
	print("WHY ", counts)
