extends SceneTree
## Lists the lowrider meets (LowriderMeet.decide) round a point, for framing stills:
##   godot --headless --path . --script tools/lowrider_probe.gd -- --spawn=x,z,0,0
## R=metres (default 3000). Each line: the cell, the road and its kerb, the cars, the row's ends
## in true world, and two EYEs for still_shot.gd: down the row from the pavement past its end, and
## across the road at its middle. Headless is enough: only the plan is read.
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var c := Vector2.ZERO
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
	for i in 8:
		await process_frame
	var plan = current_scene.get("plan")
	var lm: GDScript = load("res://scripts/world/lowrider_meet.gd")
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 3000.0
	var cell_size := float(lm.get("CELL"))
	var c0: Vector2i = lm.call("cell_of", c)
	var span := int(reach / cell_size) + 1
	var found := 0
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var cell := c0 + Vector2i(dx, dz)
			var m: Dictionary = lm.call("decide", plan, cell)
			if m.is_empty():
				continue
			var axis := int(m.axis)
			var lo := float(m.lo)
			var hi := float(m.hi)
			var lane := float(m.lane)
			var side := float(m.side)
			var mid := (lo + hi) * 0.5
			var pw := lane + side * 5.5
			var e1: Vector2
			var l1: Vector2
			var e2: Vector2
			if axis == 0:
				e1 = Vector2(pw, lo - 4.0)
				l1 = Vector2(lane, mid)
				e2 = Vector2(float(m.centre) - side * (float(m.width) * 0.5 + 1.5), mid)
			else:
				e1 = Vector2(lo - 4.0, pw)
				l1 = Vector2(mid, lane)
				e2 = Vector2(mid, float(m.centre) - side * (float(m.width) * 0.5 + 1.5))
			var d1 := l1 - e1
			var y1 := rad_to_deg(atan2(-d1.x, -d1.y))
			var d2 := (Vector2(lane, mid) if axis == 0 else Vector2(mid, lane)) - e2
			var y2 := rad_to_deg(atan2(-d2.x, -d2.y))
			var gy: float = plan.macro.relief_at(e1) + 0.25
			var gy2: float = plan.macro.relief_at(e2) + 0.25
			print("MEET cell=%d,%d road=%s#%d side=%+d cars=%d width=%.1f %s=%.1f..%.1f owner=%s dist=%.0f EYE=%.1f,%.1f,%.1f,%.0f,-6 EYE2=%.1f,%.1f,%.1f,%.0f,-3" % [
				cell.x, cell.y, "X" if axis == 0 else "Z", int(m.index), int(side), int(m.cars), float(m.width),
				"z" if axis == 0 else "x", lo, hi, str(m.owner), (l1 - c).length(),
				e1.x, gy + 1.9, e1.y, y1, e2.x, gy2 + 1.7, e2.y, y2])
			found += 1
	print("FOUND ", found)
	quit()
