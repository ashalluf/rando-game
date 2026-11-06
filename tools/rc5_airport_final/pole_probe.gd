extends SceneTree
## Streets carrying overhead lines round a point, and the staged final's route there (refcam5
## airport_final framing):  godot --headless --path . --script tools/rc5_airport_final/pole_probe.gd -- --spawn=x,z
## R=metres (default 400). POLE lines: block, axis, road, its position and name. ROUTE lines: the
## arrival_south route every 100 m (x, y, z, heading) where it passes within R.
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
	var sd: GDScript = load("res://scripts/world/street_detail.gd")
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 400.0
	var start: Vector2i = plan.block_index_at(c)
	var span := int(reach / 80.0) + 2
	for ix in range(start.x - span, start.x + span + 1):
		for iz in range(start.y - span, start.y + span + 1):
			var rect: Rect2 = plan.block(ix, iz).rect
			if rect.get_center().distance_to(c) > reach:
				continue
			# StreetDetail._overhead_lines(): each face of the block, the side from the hash.
			for f in [[0, ix, 1], [0, ix + 1, 0], [1, iz, 1], [1, iz + 1, 0]]:
				var axis: int = f[0]
				var index: int = f[1]
				if absi(hash([plan.seed, "pole_side", axis, index])) % 2 != f[2]:
					continue
				if sd.call("_has_poles", plan, ix, iz, axis, index):
					print("POLE block=%d,%d axis=%d road=%d side=%d pos=%.1f w=%.1f name=%s span=%.0f..%.0f district=%s" % [ix, iz, axis, index, f[2],
						plan.road_pos(axis, index), plan.road_width(axis, index), plan.road_name(axis, index),
						rect.position.y if axis == 0 else rect.position.x, rect.end.y if axis == 0 else rect.end.x, str(plan.district_at(rect.get_center()))])
	var air := current_scene.get_node_or_null("AirTraffic")
	for i in 30:
		await process_frame
	if air and air.get("routes") is Dictionary and air.routes.has("arrival_south"):
		var r = air.routes["arrival_south"]
		var d := 0.0
		while d < r.length:
			var smp: Dictionary = r.sample(d)
			var p: Vector3 = smp.pos
			if Vector2(p.x, p.z).distance_to(c) < reach:
				print("ROUTE d=%.0f to_aim=%.0f pos=%.1f,%.1f,%.1f yaw=%.1f" % [d, float(r.marks.aim) - d, p.x, p.y, p.z, rad_to_deg(float(smp.yaw))])
			d += 50.0
	quit()
