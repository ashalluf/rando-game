extends SceneTree
## Lists the street lamps (StreetLamps.pick) round a point, for framing stills and checking the
## mix: godot --headless --path . --script tools/street_lamps/probe.gd -- --spawn=x,z,0,0
## R=metres (default 500). Prints the share of each type per district, then for each type up to
## EACH (default 2) lamps with an EYE for still_shot.gd on the pavement 14 m along the kerb,
## looking back at the lamp. Headless is enough: only the plan is read.
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
	var sl: GDScript = load("res://scripts/world/street_lamps.gd")
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 500.0
	var each := int(OS.get_environment("EACH")) if OS.get_environment("EACH") != "" else 2
	var skip := int(OS.get_environment("SKIP")) if OS.get_environment("SKIP") != "" else 0
	var spacing := 24.0
	var names := ["cobra", "twin", "lantern", "post", "mast"]
	var counts := {}
	var shown := {}
	var start: Vector2i = plan.block_index_at(c)
	var span := int(reach / 80.0) + 2
	for ix in range(start.x - span, start.x + span + 1):
		for iz in range(start.y - span, start.y + span + 1):
			var block: Dictionary = plan.block(ix, iz)
			var rect: Rect2 = block.rect
			if rect.get_center().distance_to(c) > reach or int(plan.zone_at(rect.get_center())) != 0:
				continue
			var edges := [
				[Vector2(rect.position.x, rect.position.y), Vector2(rect.end.x, rect.position.y), Vector2(0.0, 1.0)],
				[Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.end.y), Vector2(0.0, -1.0)],
				[Vector2(rect.position.x, rect.position.y), Vector2(rect.position.x, rect.end.y), Vector2(1.0, 0.0)],
				[Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.end.y), Vector2(-1.0, 0.0)],
			]
			for e in edges.size():
				var a: Vector2 = edges[e][0]
				var b: Vector2 = edges[e][1]
				var inward: Vector2 = edges[e][2]
				var length := a.distance_to(b)
				var dir := (b - a) / length
				var t := spacing * (0.5 if e % 2 == 0 else 0.25)
				while t < length - 4.0:
					var p := a + dir * t + inward
					var ty: int = sl.call("pick", plan, p, -inward)
					var d := str(plan.district_at(p))
					var key := "%s %s" % [d, names[ty]]
					counts[key] = counts.get(key, 0) + 1
					if shown.get(ty, 0) < each + skip and t > 20.0 and t < length - 20.0:
						shown[ty] = shown.get(ty, 0) + 1
						if shown[ty] <= skip:
							t += spacing
							continue
						var eye := p - dir * 14.0 + inward * 1.2
						var look := (p - eye).normalized()
						var yaw := rad_to_deg(atan2(-look.x, -look.y))
						var g: float = plan.height_at(eye)
						# And from the far kerb, a little up the street, which clears the poles and
						# trees on the lamp's own pavement.
						var st: Array = sl.call("street_of", plan, p, -inward)
						var w: float = plan.road_width(st[0], st[1])
						var xe := p - inward * (w + 2.4) - dir * 9.0
						var xl := (p - xe).normalized()
						var xg: float = plan.height_at(xe)
						print("LAMP %s district %s at %.1f,%.1f facing %s  EYE=%.1f,%.1f,%.1f,%.0f,8  XEYE=%.1f,%.1f,%.1f,%.0f,14" % [names[ty], d, p.x, p.y, -inward, eye.x, g + 1.7, eye.y, yaw,
							xe.x, xg + 1.7, xe.y, rad_to_deg(atan2(-xl.x, -xl.y))])
					t += spacing
	var keys := counts.keys()
	keys.sort()
	for k in keys:
		print("COUNT ", k, " ", counts[k])
	quit()
