extends SceneTree
## Lists the Googie motel signs that stand at a surface car park's front corner (BoulevardSigns,
## src "park": the lots Motels builds a motor court on) round a point, with the lot and the road:
##   godot --headless --path . --script tools/motel_probe.gd -- --spawn=x,z,0,0   (R= metres)
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
	var bs: GDScript = load("res://scripts/world/boulevard_signs.gd")
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 1500.0
	var start: Vector2i = plan.block_index_at(c)
	var span := int(reach / 80.0) + 2
	for ix in range(start.x - span, start.x + span + 1):
		for iz in range(start.y - span, start.y + span + 1):
			var block: Dictionary = plan.block(ix, iz)
			if (block.rect as Rect2).get_center().distance_to(c) > reach:
				continue
			for p: Dictionary in bs.call("plan_poles", plan, ix, iz):
				if int(p.kind) != 1 or String(p.get("src", "")) != "park":
					continue
				var lot := {}
				for l: Dictionary in plan.lots(ix, iz):
					if int(l.seed) == int((p.id as Array)[0]):
						lot = l
				var road: Array = bs.call("edge_road", ix, iz, int(p.e))
				var at: Vector2 = p.at
				var inward: Vector2 = p.out
				var along: Vector2 = p.along
				var cell: Rect2 = lot.cell if not lot.is_empty() else Rect2()
				var w: float = plan.road_width(road[0], road[1])
				# Across the street, looking at the lot's middle.
				var mid := cell.get_center()
				var sw: float = plan.sidewalk_width
				var eye: Vector2 = at - inward * (w + sw * 2.0 + 1.0) + along * 10.0
				var look: Vector2 = mid - eye
				var yaw := rad_to_deg(atan2(-look.x, -look.y))
				print("MOTEL block=%d,%d dist=%d a=%d at=%.1f,%.1f cell=%s road=%s w=%.1f name=%s EYE=%.1f,1.7,%.1f,%.0f,8" % [
					ix, iz, int(block.district), int(p.a), at.x, at.y, str(cell), str(road), w, plan.road_name(road[0], road[1]), eye.x, eye.y, yaw])
	quit()
