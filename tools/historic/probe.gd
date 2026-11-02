extends SceneTree
## Lists the historic core's beaux-arts lots for a seed (HistoricCore): the block, the avenue,
## the lot, its spec and an EYE for still_shot.gd looking at it from across the avenue.
##   godot --headless --path . --script tools/historic/probe.gd [-- --seed=N]

func _initialize() -> void:
	await process_frame
	var seed_value := 1337
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = int(a.substr(7))
	var m := MacroMap.new()
	m.seed = seed_value
	m.setup()
	var plan := CityPlan.new()
	plan.seed = seed_value
	plan.macro = m
	print("HISTORIC z %s" % [HistoricCore.z_range()])
	for name: String in HistoricCore.AVENUES:
		print("AVENUE %s %s" % [name, HistoricCore.avenue(name)])
	var zr := HistoricCore.z_range()
	var n := 0
	var seen := {}
	for name: String in HistoricCore.AVENUES:
		var av := HistoricCore.avenue(name)
		var z := zr.x + 5.0
		while z < zr.y:
			for side: float in [-1.0, 1.0]:
				var bi := plan.block_index_at(Vector2(float(av[0]) + side * 30.0, z))
				if seen.has(bi):
					continue
				seen[bi] = true
				var fronts := HistoricCore.block_fronts(plan, bi.x, bi.y)
				var b := plan.block(bi.x, bi.y)
				print("BLOCK %s kind %d district %d rect %s fronts %s lots %d" % [bi, int(b.kind), int(b.district), b.rect, fronts, plan.lots(bi.x, bi.y).size()])
				for lot: Dictionary in plan.lots(bi.x, bi.y):
					var spec := HistoricCore.spec_for(plan, bi.x, bi.y, lot)
					if spec.is_empty():
						continue
					n += 1
					var c: Vector2 = lot.center
					var s: Vector2 = lot.size
					var faces := HistoricCore.street_faces(plan, bi.x, bi.y, lot)
					var eye_x := float(av[0]) + (float(av[0]) - c.x) * 0.0
					var yaw := -90.0 if c.x > float(av[0]) else 90.0
					print("  LOT %s size %s %s brick %s cols %s %s faces %s EYE=%.1f,1.7,%.1f,%.0f,14" % [c, s, spec.avenue, spec.brick, spec.columns, spec.name, faces, eye_x - signf(c.x - float(av[0])) * 6.0, c.y, yaw])
			z += 40.0
	print("HISTORIC LOTS %d" % n)
	quit()
