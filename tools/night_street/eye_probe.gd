extends SceneTree
## Prints a street EYE for each point given: the block there, its district, and a camera in the
## road along the block's +Z side (2.5 m off its kerb, looking east along the road).
##   godot --headless --path . --script tools/night_street/eye_probe.gd -- --at=x,z;x,z
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	for i in 8:
		await process_frame
	var plan = current_scene.get("plan")
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--at="):
			continue
		for pt in arg.trim_prefix("--at=").split(";"):
			var p := pt.split(",")
			var c := Vector2(p[0].to_float(), p[1].to_float())
			var b: Vector2i = plan.block_index_at(c)
			var blk = plan.block(b.x, b.y)
			var r: Rect2 = blk.rect
			var w: float = plan.road_width(1, b.y + 1)
			print("EYEP at=%s block=%s district=%d kind=%d rect=%s road_w=%.1f name=%s EYE=%.1f,1.7,%.1f,-90,3" % [c, b,
				plan.district_at(r.get_center()), int(blk.kind), r, w, plan.road_name(1, b.y + 1),
				r.position.x + 12.0, r.end.y + 2.5])
	quit()
