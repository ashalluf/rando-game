extends SceneTree
## Prints the blocks round a point (district, zone, kind, rect, road widths, landmarks) for
## placing the canal neighbourhood:
##   godot --headless --path . --script tools/canals/map_probe.gd -- --spawn=x,z  [R=metres]
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var c := Vector2(-800.0, -340.0)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
	for i in 8:
		await process_frame
	var plan = current_scene.get("plan")
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 400.0
	var k: Vector2i = plan.block_index_at(c)
	var span := int(reach / 60.0) + 2
	for iz in range(k.y - span, k.y + span + 1):
		for ix in range(k.x - span, k.x + span + 1):
			var b: Dictionary = plan.block(ix, iz)
			var r: Rect2 = b.rect
			if r.get_center().distance_to(c) > reach:
				continue
			var zone: int = plan.zone_at(r.get_center())
			print("BLOCK %d,%d rect=(%.0f,%.0f %.0fx%.0f) dist=%s kind=%d zone=%d roadX=%.0f(w%.0f) roadZ=%.0f(w%.0f) site=%s grounds=%s claims=%s lots=%d h=%.1f" % [
				ix, iz, r.position.x, r.position.y, r.size.x, r.size.y, plan.district_name(b.district), b.kind, zone,
				plan.road_pos(0, ix), plan.road_width(0, ix), plan.road_pos(1, iz), plan.road_width(1, iz),
				b.get("site", ""), b.get("grounds", ""), load("res://scripts/world/landmarks.gd").call("claims", r), plan.lots(ix, iz).size(), plan.height_at(r.get_center())])
	for z in range(-700, 100, 50):
		print("COAST z=%d x=%.1f" % [z, plan.macro.coast_x(float(z))])
	quit()
