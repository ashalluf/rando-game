extends SceneTree
## Finds the vacant lots and gravel car parks (VacantLots) in a rect and prints, for each, its
## block, kind, size, what is on it and EYE lines for tools/glshot/still_shot.gd: one from the
## pavement looking across the lot (its street side), one aerial. Headless, seconds.
##
##   godot --headless --path . --script tools/vacant_probe.gd
##
## Env: RECT=x,z,w,d (default downtown and the midtown west of it), SEED (default 1337), MAX (lines
## to print, default 40).
## Everything is loaded dynamically: this script compiles before the autoloads exist.
func _initialize() -> void:
	await process_frame
	var gc: GDScript = load("res://scripts/world/ground_coverage.gd")
	var vl: GDScript = load("res://scripts/world/vacant_lots.gd")
	var seed_value := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	var plan = gc.call("make_plan", seed_value)
	var r := Rect2(0.0, -1800.0, 4200.0, 5600.0)
	if OS.get_environment("RECT") != "":
		var p := OS.get_environment("RECT").split(",")
		r = Rect2(float(p[0]), float(p[1]), float(p[2]), float(p[3]))
	var most := int(OS.get_environment("MAX")) if OS.get_environment("MAX") != "" else 40
	var lo: Vector2i = plan.block_index_at(r.position)
	var hi: Vector2i = plan.block_index_at(r.end)
	var counts := {}
	var lots := 0
	var printed := 0
	for bx in range(lo.x, hi.x + 1):
		for bz in range(lo.y, hi.y + 1):
			var b: Dictionary = plan.block(bx, bz)
			if not r.has_point((b.rect as Rect2).get_center()):
				continue
			for lot: Dictionary in plan.lots(bx, bz):
				var d: int = b.district
				if not counts.has(d):
					counts[d] = [0, 0, 0]
				counts[d][0] += 1
				lots += 1
				var k: int = vl.call("kind_of", plan, bx, bz, lot)
				if k == 0:
					continue
				counts[d][k] += 1
				if printed >= most:
					continue
				printed += 1
				var lp: Dictionary = vl.call("plan_lot", plan, bx, bz, lot, k)
				var f: Dictionary = lp.frame
				var cell: Rect2 = lp.cell
				var o: Vector2 = f.o
				var a: Vector2 = f.a
				var n: Vector2 = f.n
				# From the far kerb of the street, looking across it into the lot.
				var eye: Vector2 = o + a * (float(f.len) * 0.5) - n * (plan.sidewalk_width + 12.0)
				var look := n
				var yaw := rad_to_deg(atan2(-look.x, -look.y))
				var air: Vector2 = cell.get_center() - n * 70.0
				var names := []
				for it: Dictionary in lp.items:
					names.append(it.t)
				var front_screen := false
				for fe: Dictionary in lp.fences:
					if (fe.gate as Vector2).x >= 0.0:
						front_screen = fe.screen
				print("VACANT %s front_screen=%s block (%d,%d) district %d cell %s slab %s items %s" % [["", "lot", "PARKING"][k], front_screen, bx, bz, d, cell, (lp.slab as Rect2).size, names])
				print("  EYE=%.1f,1.7,%.1f,%.0f,-2   AIR EYE=%.1f,45,%.1f,%.0f,-30" % [eye.x, eye.y, yaw, air.x, air.y, yaw])
	for d in counts:
		print("DISTRICT %d: %d lots, %d vacant, %d car parks (%.1f %%)" % [d, counts[d][0], counts[d][1], counts[d][2], 100.0 * float(counts[d][1] + counts[d][2]) / maxf(float(counts[d][0]), 1.0)])
	print("LOTS %d" % lots)
	quit()
