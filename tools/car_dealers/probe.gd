extends SceneTree
## Lists the car dealerships (CarDealers.site) round a point, for framing stills:
##   godot --headless --path . --script tools/car_dealers/probe.gd -- [--spawn=x,z,0,0]
## R=metres (default 2500). Each line: new / used, the name, the block, the road it fronts, the
## site rect, and EYEs for still_shot.gd: STREET (across the road at eye height looking at it)
## and ABOVE (40 m up over the road, looking down on the lot). Headless: only the plan is read.
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
	var cd: GDScript = load("res://scripts/world/car_dealers.gd")
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 2500.0
	var start: Vector2i = plan.block_index_at(c)
	var span := int(reach / 70.0) + 2
	var found := 0
	var used := 0
	for ix in range(start.x - span, start.x + span + 1):
		for iz in range(start.y - span, start.y + span + 1):
			var rect: Rect2 = plan.block(ix, iz).rect
			if rect.get_center().distance_to(c) > reach:
				continue
			var s: Dictionary = cd.call("site", plan, ix, iz)
			if s.is_empty():
				continue
			found += 1
			if s.used:
				used += 1
			var r: Rect2 = s.rect
			var f: Dictionary = s.frame
			var n: Vector2 = f.n
			var mid: Vector2 = (f.o as Vector2) + (f.a as Vector2) * float(f.len) * 0.5
			var w: float = plan.road_width(int(s.road[0]), int(s.road[1]))
			var eye: Vector2 = mid - n * (plan.sidewalk_width + w * 0.85)
			var yaw := rad_to_deg(atan2(-n.x, -n.y))
			var above: Vector2 = mid - n * (plan.sidewalk_width + w * 0.5 + 18.0)
			print("DEALER %s \"%s\" block=%d,%d district=%d road=%d/%d rect=(%.0f,%.0f %.0fx%.0f) lots=%d STREET=%.1f,1.7,%.1f,%.0f,-2 ABOVE=%.1f,38,%.1f,%.0f,-42" % [
				"used" if s.used else "new", s.name, ix, iz, int(plan.block(ix, iz).district), int(s.road[0]), int(s.road[1]),
				r.position.x, r.position.y, r.size.x, r.size.y, (s.lots as Array).size(), eye.x, eye.y, yaw, above.x, above.y, yaw])
	print("FOUND %d (used %d)" % [found, used])
	quit()
