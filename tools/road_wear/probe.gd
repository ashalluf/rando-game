extends SceneTree
## Finds streets for RoadWear stills: per district, a few roads with an EYE on the carriageway
## looking along them (still_shot.gd EYE=). Headless, only the plan is read:
##   godot --headless --path . --script tools/road_wear/probe.gd -- --spawn=x,z,0,0
## R=metres round the spawn (default 1500), N=roads per district (default 4).
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
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 1500.0
	var per := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 4
	var AX: int = load("res://scripts/world/city_plan.gd").AXIS_X
	var names := ["DOWNTOWN", "MIDTOWN", "SUBURBS", "INDUSTRIAL", "CAMPUS", "BEACHTOWN"]
	var found := {}
	var start: Vector2i = plan.block_index_at(c)
	var span := int(reach / 90.0) + 2
	var rw: GDScript = load("res://scripts/world/road_wear.gd") if ResourceLoader.exists("res://scripts/world/road_wear.gd") else null
	for r in range(0, span):
		for ix in range(start.x - r, start.x + r + 1):
			for iz in range(start.y - r, start.y + r + 1):
				if maxi(absi(ix - start.x), absi(iz - start.y)) != r:
					continue
				var block: Dictionary = plan.block(ix, iz)
				var rect: Rect2 = block.rect
				if rect.get_center().distance_to(c) > reach or int(plan.zone_at(rect.get_center())) != 0 or block.has("site"):
					continue
				var d := int(block.district)
				var k: String = names[d]
				var wx: float = plan.road_width(AX, ix + 1)
				var avenue: bool = wx >= plan.avenue_width - 0.1
				k += "_AVENUE" if avenue else "_STREET"
				if int(found.get(k, 0)) >= per or not plan.road_open(AX, ix + 1, rect.get_center().y):
					continue
				found[k] = int(found.get(k, 0)) + 1
				var rx: float = plan.road_pos(AX, ix + 1)
				var eye := Vector2(rx + wx * 0.25, rect.position.y + 4.0)
				var extra := ""
				if rw:
					extra = " wear=%.2f" % rw.call("road_level", plan, AX, ix + 1, d)
				print("ROAD %s block=%d,%d width=%.1f EYE=%.1f,1.6,%.1f,180,-8 (looking +z along x=%.1f)%s" % [k, ix, iz, wx, eye.x, eye.y, rx, extra])
	quit()
