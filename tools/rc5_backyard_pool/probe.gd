extends SceneTree
## The backyard_pool refcam's finder: suburb lots round a point whose back yard has a pool, a
## lounger pair with sunbathers and a grill (Backyards.plan_lot()), each with an EYE on the patio
## (the house's back line) looking over the pool to the back fence, and the hills' height that way.
##
##   godot --headless --path . --script tools/rc5_backyard_pool/probe.gd -- --spawn=x,z [R=metres]

func _initialize() -> void:
	var c := Vector2(0, -1200)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 900.0
	var gc: GDScript = load("res://scripts/world/ground_coverage.gd")
	var by: GDScript = load("res://scripts/world/backyards.gd")
	var plan = gc.call("make_plan", 1337)
	var lo: Vector2i = plan.block_index_at(c - Vector2(reach, reach))
	var hi: Vector2i = plan.block_index_at(c + Vector2(reach, reach))
	var n := 0
	for bx in range(lo.x, hi.x + 1):
		for bz in range(lo.y, hi.y + 1):
			var b: Dictionary = plan.block(bx, bz)
			var d := int(b.district)
			if d != CityPlan.District.SUBURBS:
				continue
			if int(b.kind) != CityPlan.BlockKind.BUILDINGS or b.has("site") or plan.zone_at((b.rect as Rect2).get_center()) != MacroMap.Zone.CITY:
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
			for lp: Dictionary in bp.lots:
				var pool := Rect2()
				for pc: Array in lp.pieces:
					if int(pc[1]) == YardFill.G_POOL:
						pool = pc[0]
				if pool.size.x <= 0.0:
					continue
				var items: Array = by.call("plan_lot", plan, lp, d)
				var kinds := []
				var sun := 0
				var cook := -1.0
				for it: Dictionary in items:
					kinds.append(String(it.kind))
					if String(it.kind).begins_with("grill"):
						cook = Rc5Backyard.cooking(float(it.seed), 15.0, true)
					if String(it.kind) == "loungers":
						sun += (it.get("sun", []) as Array).size()
				if sun == 0 or not ("grill_gas" in kinds or "grill_kettle" in kinds):
					continue
				var f: Dictionary = lp.frame
				var back: Vector2 = f.v
				var pc2 := pool.get_center()
				var pq := YardFill._to_frame(f, pool)
				var eye := YardFill._fp(f, pq.get_center().x, float(lp.back) + 0.7)
				var yaw := rad_to_deg(atan2(-back.x, -back.y))
				var gy: float = plan.height_at(eye)
				var tall := _tallest_behind(plan, bx, bz, pc2, back)
				var far := pc2 + back * 3000.0
				print("LOT b%d,%d pool %.1f,%.1f %s sun %d %s back %s dist %.1f EYE=%.1f,1.7,%.1f,%.0f,-6 ground %.1f hills_ahead %.0f cooks_sat_15 %.2f behind_storeys %d" % [bx, bz, pc2.x, pc2.y, str(pool.size), sun, str(kinds), str(back), eye.distance_to(pc2), eye.x, eye.y, yaw, gy, plan.height_at(far), cook, tall])
				n += 1
	print("FOUND %d" % n)
	quit()


## The most storeys of any house wing standing 5-45 m beyond the pool (within 12 m of the line).
func _tallest_behind(plan, bx: int, bz: int, c: Vector2, dir: Vector2) -> int:
	var best := 0
	var side := Vector2(-dir.y, dir.x)
	for x in range(bx - 1, bx + 2):
		for z in range(bz - 1, bz + 2):
			var b: Dictionary = plan.block(x, z)
			var d := int(b.district)
			var lots: Array = plan.lots(x, z)
			if HouseKit.enabled:
				lots.append_array(HouseKit.extra_lots(plan, x, z))
			for lot: Dictionary in lots:
				if lot.yard or YardFill.is_corridor(plan, lot):
					continue
				var h := HouseKit.plan_house(plan, x, z, lot, d)
				var f: Dictionary = h.get("f", {})
				for w: Dictionary in h.get("wings", []):
					var r: Rect2 = w.r
					var wc := YardFill._fp(f, r.get_center().x, r.get_center().y) if not f.is_empty() else r.get_center()
					var rel := wc - c
					var along := rel.dot(dir)
					if along > 5.0 and along < 45.0 and absf(rel.dot(side)) < 12.0 + along * 0.3:
						best = maxi(best, int(w.storeys))
	return best
