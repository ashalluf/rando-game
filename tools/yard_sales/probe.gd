extends Node
## Yard sales (YardSales) without a city: walks the suburb and beach-town blocks round a point and
## prints the sales YardSales.plan_lot() lays out on a weekend morning - counts per kind, the plan
## time, and an EYE (tools/glshot/still_shot.gd) from the street in front of each of the first few.
## Seconds, headless. A scene (the autoloads must exist for YardSales to compile).
##
##   godot --headless --path . tools/yard_sales/probe.tscn -- --spawn=x,z [R=metres] [SEED=n]
##       [DAY=6] [HOUR=9.5] [YARD_SALE=all]

func _ready() -> void:
	var c := Vector2(1911, 4260)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 900.0
	var seed_value := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	var day := int(OS.get_environment("DAY")) if OS.get_environment("DAY") != "" else 6
	var hour := float(OS.get_environment("HOUR")) if OS.get_environment("HOUR") != "" else 9.5
	var gc: GDScript = load("res://scripts/world/ground_coverage.gd")
	var ys: GDScript = load("res://scripts/world/yard_sales.gd")
	var plan = gc.call("make_plan", seed_value)
	var lo: Vector2i = plan.block_index_at(c - Vector2(reach, reach))
	var hi: Vector2i = plan.block_index_at(c + Vector2(reach, reach))
	var totals := {}
	var lots_n := 0
	var sales := 0
	var usec := 0
	var shown := 0
	for bx in range(lo.x, hi.x + 1):
		for bz in range(lo.y, hi.y + 1):
			var b: Dictionary = plan.block(bx, bz)
			var d := int(b.district)
			if not (d == CityPlan.District.SUBURBS or d == CityPlan.District.BEACHTOWN):
				continue
			if int(b.kind) != CityPlan.BlockKind.BUILDINGS or b.has("site") or plan.zone_at((b.rect as Rect2).get_center()) != MacroMap.Zone.CITY:
				continue
			if plan.marina_block(bx, bz):
				continue
			var bp: Dictionary = ys.call("block_plans", plan, bx, bz)
			for lp: Dictionary in bp.lots:
				lots_n += 1
				if OS.get_environment("FD_HIST") == "1":
					var fdb := int(float(lp.front))
					totals["fd_%02d" % fdb] = int(totals.get("fd_%02d" % fdb, 0)) + 1
					if bool(lp.get("walk_front", false)):
						totals["walk_front"] = int(totals.get("walk_front", 0)) + 1
				var t0 := Time.get_ticks_usec()
				var s: Dictionary = ys.call("plan_lot", plan, lp, d, day, hour)
				usec += Time.get_ticks_usec() - t0
				if s.is_empty():
					continue
				sales += 1
				for it: Dictionary in s.items:
					totals[it.kind] = int(totals.get(it.kind, 0)) + 1
				totals["browsers"] = int(totals.get("browsers", 0)) + int(s.browsers)
				if shown < 10:
					shown += 1
					var f: Dictionary = lp.frame
					var mid: Vector2 = ((s.aisle[0] as Vector2) + (s.aisle[1] as Vector2)) * 0.5
					var w := YardFill._fp(f, mid.x, float(s.row_v))
					var v: Vector2 = f.v
					var eye := w - v * 9.5 + (f.u as Vector2) * 3.0
					var dir := (w - eye).normalized()
					print("SALE block %d,%d lot %d %s '%s' items %d at %.1f,%.1f EYE=%.1f,2.2,%.1f,%.0f,-9" % [bx, bz, int(lp.lot.seed) % 100000,
						["", "SETUP", "OPEN", "LEFTOVER"][int(s.state)], s.info.headline, (s.items as Array).size(), w.x, w.y, eye.x, eye.y,
						rad_to_deg(atan2(-dir.x, -dir.y))])
	print("YARD_SALES lots %d, sales %d, plan %.2f ms total (%.0f us a lot)" % [lots_n, sales, usec / 1000.0, float(usec) / maxf(lots_n, 1)])
	for k in totals:
		print("  %-12s %d" % [k, totals[k]])
	get_tree().quit()
