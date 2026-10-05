extends SceneTree
## Lists the overhead lines (UtilityPoles.block_runs) round a point, for framing stills:
##   godot --headless --path . --script tools/utility_poles/probe.gd -- --spawn=x,z,0,0
## R=metres (default 500), DISTRICT=suburbs|beachtown|midtown|industrial|downtown|campus to filter,
## MAX=lines to print (default 20).
## Each line: district, road, how many poles, the first pole's pin point (true world) and two EYEs
## for still_shot.gd: on the pavement 14 m down the line looking along it, and across the street.
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
	var up: GDScript = load("res://scripts/world/utility_poles.gd")
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 500.0
	var want := OS.get_environment("DISTRICT")
	var most := int(OS.get_environment("MAX")) if OS.get_environment("MAX") != "" else 20
	var names := ["downtown", "midtown", "suburbs", "industrial", "campus", "beachtown"]
	var start: Vector2i = plan.block_index_at(c)
	var span := int(reach / 80.0) + 2
	var rows: Array = []
	for ix in range(start.x - span, start.x + span + 1):
		for iz in range(start.y - span, start.y + span + 1):
			var rect: Rect2 = plan.block(ix, iz).rect
			if rect.get_center().distance_to(c) > reach:
				continue
			var d: String = names[int(plan.district_at(rect.get_center()))]
			if want != "" and d != want:
				continue
			for r: Dictionary in up.call("block_runs", plan, ix, iz):
				var poles: Array = r.poles
				if poles.size() < 2:
					continue
				var p0: Vector3 = poles[0].pin
				var run_dir: Vector3 = r.run_dir
				var street: Vector3 = r.street
				var y := p0.y + plan.macro.relief_at(Vector2(p0.x, p0.z))
				var e1 := p0 - run_dir * 14.0 + street * 0.4
				var yaw1 := rad_to_deg(atan2(-run_dir.x, -run_dir.z))
				var e2 := p0 + street * 14.0 + run_dir * 6.0
				var look := (p0 - e2).normalized()
				var yaw2 := rad_to_deg(atan2(-look.x, -look.z))
				rows.append([Vector2(p0.x, p0.z).distance_to(c), "UPLINE %s block %d,%d axis %d road %d poles %d first (%.1f, %.2f, %.1f) EYE=%.1f,%.1f,%.1f,%.0f,8 ACROSS=%.1f,%.1f,%.1f,%.0f,14" % [
					d, ix, iz, r.axis, r.index, poles.size(), p0.x, y, p0.z, e1.x, y + 1.7, e1.z, yaw1, e2.x, y + 1.7, e2.z, yaw2]])
	rows.sort_custom(func(a, b): return a[0] < b[0])
	for i in mini(most, rows.size()):
		print(rows[i][1])
	print("UPLINES %d within %.0f m" % [rows.size(), reach])
	quit()
