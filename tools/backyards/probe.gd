extends SceneTree
## Backyard life (Backyards) without a city: walks the suburb and beach-town blocks round a point,
## plans each lot's yard the way the chunk does (HouseKit's houses, YardFill.beach_block()) and
## prints what Backyards.plan_lot() puts out back - counts per kind, the plan time, and the blocks
## with the most, each with an EYE for tools/glshot/still_shot.gd over its back yards. Seconds.
##
##   godot --headless --path . --script tools/backyards/probe.gd -- --spawn=x,z [R=metres] [SEED=n]

func _initialize() -> void:
	var c := Vector2(1911, 4260)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 900.0
	var seed_value := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	var gc: GDScript = load("res://scripts/world/ground_coverage.gd")
	var by: GDScript = load("res://scripts/world/backyards.gd")
	var tp := Time.get_ticks_msec()
	var plan = gc.call("make_plan", seed_value)
	print("PLAN made in %d ms" % (Time.get_ticks_msec() - tp))
	var lo: Vector2i = plan.block_index_at(c - Vector2(reach, reach))
	var hi: Vector2i = plan.block_index_at(c + Vector2(reach, reach))
	var totals := {}
	var lots_n := 0
	var usec := 0
	var best: Array = []
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
			var lots: Array = plan.lots(bx, bz)
			if HouseKit.enabled:
				lots.append_array(HouseKit.extra_lots(plan, bx, bz))
			var entries: Array = []
			for lot: Dictionary in lots:
				if lot.yard or YardFill.is_corridor(plan, lot):
					continue
				var house := HouseKit.plan_house(plan, bx, bz, lot, d)
				entries.append(HouseKit.yard_entry(lot, house))
			var bp := YardFill.beach_block(plan, bx, bz, entries)
			var count := 0
			var kinds := {}
			for lp: Dictionary in bp.lots:
				lots_n += 1
				var t0 := Time.get_ticks_usec()
				var items: Array = by.call("plan_lot", plan, lp, d)
				usec += Time.get_ticks_usec() - t0
				for it: Dictionary in items:
					var k := String(it.kind)
					if (k == "lights" or k == "trampoline" or k == "grill_gas") and int(totals.get(k, 0)) < 3:
						var f: Dictionary = lp.frame
						var at: Vector2 = (it.glow as Rect2).get_center() if k == "lights" else it.at
						var w := YardFill._fp(f, at.x, at.y)
						var back: Vector2 = f.v
						var eye := w + back * 9.0
						var yaw := rad_to_deg(atan2(back.x, back.y))
						print("%s at %.1f,%.1f EYE=%.1f,6,%.1f,%.0f,-22" % [k.to_upper(), w.x, w.y, eye.x, eye.y, yaw])
					totals[k] = int(totals.get(k, 0)) + 1
					kinds[k] = int(kinds.get(k, 0)) + 1
					count += 1
			var rc: Vector2 = (b.rect as Rect2).get_center()
			best.append([count, bx, bz, rc, d, kinds])
	best.sort_custom(func(a, b): return a[0] > b[0])
	print("BACKYARDS lots %d, plan %.2f ms total (%.0f us a lot)" % [lots_n, usec / 1000.0, float(usec) / maxf(lots_n, 1)])
	for k in totals:
		print("  %-14s %d" % [k, totals[k]])
	for i in mini(8, best.size()):
		var e: Array = best[i]
		var rc: Vector2 = e[3]
		print("BLOCK %d,%d %s items %d %s EYE=%.0f,45,%.0f,0,-50 EYE_HIGH=%.0f,150,%.0f,0,-55" % [e[1], e[2], "SUBURBS" if e[4] == CityPlan.District.SUBURBS else "BEACHTOWN", e[0], str(e[5]), rc.x, rc.y + 30.0, rc.x, rc.y + 90.0])
	quit()
