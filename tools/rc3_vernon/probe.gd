extends SceneTree
## Lists Vernon industrial blocks with a rail spur and their truck courts (the vernon_industrial
## refcam's framing). Headless, seconds:  godot --headless --path . --script tools/rc3_vernon/probe.gd
## Env RECT=x,z,w,d (default Vernon), MAX.
func _initialize() -> void:
	await process_frame
	var gc: GDScript = load("res://scripts/world/ground_coverage.gd")
	var ind: GDScript = load("res://scripts/world/industrial.gd")
	var plan = gc.call("make_plan", 1337)
	var r := Rect2(2200.0, 2400.0, 1300.0, 2400.0)
	if OS.get_environment("RECT") != "":
		var p := OS.get_environment("RECT").split(",")
		r = Rect2(float(p[0]), float(p[1]), float(p[2]), float(p[3]))
	var lo: Vector2i = plan.block_index_at(r.position)
	var hi: Vector2i = plan.block_index_at(r.end)
	for bx in range(lo.x, hi.x + 1):
		for bz in range(lo.y, hi.y + 1):
			var b: Dictionary = plan.block(bx, bz)
			var rc: Rect2 = b.rect
			if not r.has_point(rc.get_center()) or int(b.district) != 3:
				continue
			var sp: Dictionary = ind.call("spur", plan, bx, bz)
			var ents: Array = ind.call("block_entries", plan, bx, bz)
			var courts := 0
			var wh := 0
			for e: Dictionary in ents:
				if not (e.plan as Dictionary).is_empty():
					wh += 1
					if (e.plan as Dictionary).get("court", 0.0) > 0.0:
						courts += 1
			if OS.get_environment("DETAIL") == "1":
				if not sp.is_empty():
					print("  SPUR rect %s" % [sp.rect])
				for e: Dictionary in ents:
					var lp: Dictionary = e.plan
					if not lp.is_empty():
						print("  WH rect %s side %d court %.1f rail_back %s h %.1f" % [lp.rect, lp.side, lp.court, lp.rail_back, lp.h])
			print("BLOCK %d,%d rect %s spur %s axis %s wh %d courts %d" % [bx, bz, rc, not sp.is_empty(), sp.get("axis", -1), wh, courts])
	quit()
