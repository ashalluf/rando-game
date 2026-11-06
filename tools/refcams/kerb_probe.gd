extends SceneTree
## Lists kerbs round a point for framing a parked-car refcam (cameras_w6.json "park_car"):
##   godot --headless --path . --script tools/refcams/kerb_probe.gd -- --spawn=x,z
## R=metres (default 300). Each line: the block, its district and kind, the +x / +z road (axis,
## index, position, width, a bike lane?) and the kerb line's coordinate on both sides.
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
	var mm: GDScript = load("res://scripts/world/micromobility.gd")
	var cp: GDScript = load("res://scripts/world/city_plan.gd")
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 300.0
	var start: Vector2i = plan.block_index_at(c)
	var span := int(reach / 80.0) + 2
	for ix in range(start.x - span, start.x + span + 1):
		for iz in range(start.y - span, start.y + span + 1):
			var block: Dictionary = plan.block(ix, iz)
			var rect: Rect2 = block.rect
			if rect.get_center().distance_to(c) > reach:
				continue
			for axis in 2:
				var index: int = ix + 1 if axis == 0 else iz + 1
				var k: int = iz if axis == 0 else ix
				var w: float = plan.road_width(axis, index)
				var pos: float = plan.road_pos(axis, index)
				var off: float = cp.call("parking_offset", w)
				print("KERB block=%d,%d district=%s kind=%s axis=%d road=%d pos=%.1f w=%.1f lane=%s name=%s kerbs=%.1f/%.1f span=%.0f..%.0f" % [
					ix, iz, str(block.get("district")), str(block.get("kind")), axis, index, pos, w,
					str(mm.call("lane_on", plan, axis, index, k)), str(plan.road_name(axis, index)), pos - off, pos + off,
					rect.position.y if axis == 0 else rect.position.x, rect.end.y if axis == 0 else rect.end.x])
	quit()
