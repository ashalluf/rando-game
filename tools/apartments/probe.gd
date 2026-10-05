extends SceneTree
## The apartment kit (Apartments) on a plan, headless, seconds: how many lots it claims per district
## and kind, the plan's purity, and an EYE (still_shot.gd) for the first few of each kind.
##   godot --headless --path . --script tools/apartments/probe.gd [-- SEED=n RADIUS=m]

func _initialize() -> void:
	await process_frame
	var seed_value := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	var radius := float(OS.get_environment("RADIUS")) if OS.get_environment("RADIUS") != "" else 3200.0
	var plan := GroundCoverage.make_plan(seed_value)
	var centre: Vector2 = plan.macro.downtown_center
	var lo := plan.block_index_at(centre - Vector2(radius, radius))
	var hi := plan.block_index_at(centre + Vector2(radius, radius))
	var counts := {}
	var eyes := {}
	var total := 0
	var impure := 0
	var t0 := Time.get_ticks_msec()
	for bx in range(lo.x, hi.x + 1):
		for bz in range(lo.y, hi.y + 1):
			var b := plan.block(bx, bz)
			var d: int = b.district
			if d != CityPlan.District.MIDTOWN and d != CityPlan.District.SUBURBS:
				continue
			if int(b.kind) != CityPlan.BlockKind.BUILDINGS:
				continue
			for lot: Dictionary in plan.lots(bx, bz):
				var ap := Apartments.plan_house(plan, bx, bz, lot, d)
				if ap.is_empty():
					continue
				var again := Apartments.plan_house(plan, bx, bz, lot, d)
				if var_to_str(ap.wings) != var_to_str(again.wings):
					impure += 1
				total += 1
				var key := "%s %s" % [CityPlan.District.keys()[d], Apartments.KIND_NAMES[int(ap.apt)]]
				counts[key] = int(counts.get(key, 0)) + 1
				if not eyes.has(key):
					eyes[key] = []
				# A pad (Commercial) may be rolled on an edge lot 18 m or more each way: not a lot to look at.
				var pad_risk: bool = lot.edge and (lot.size as Vector2).x >= 18.0 and (lot.size as Vector2).y >= 18.0
				if (eyes[key] as Array).size() < 3 and not pad_risk:
					var f: Dictionary = ap.f
					# Standing in the street, 18 m out from the lot's front, looking at it.
					var front := (f.o as Vector2) + (f.u as Vector2) * float(f.U) * 0.5
					var out := -(f.v as Vector2)
					var eye := front + out * 16.0 - (f.u as Vector2) * 6.0
					var look := (front + (f.v as Vector2) * 6.0) - eye
					var yaw := rad_to_deg(atan2(-look.x, -look.y))
					var gy := plan.height_at(eye)
					(eyes[key] as Array).append("EYE=%.1f,%.1f,%.1f,%.1f,4  h %.1f m  block %d,%d" % [eye.x, 2.2, eye.y, yaw, float(ap.height), bx, bz])
	var keys := counts.keys()
	keys.sort()
	for k: String in keys:
		print("APT %s %d" % [k, counts[k]])
		for e: String in eyes[k]:
			print("   ", e)
	print("APT total %d, impure %d, %d ms" % [total, impure, Time.get_ticks_msec() - t0])
	quit()
