extends SceneTree
## Lists the second street-clutter pass (StreetClutter2) of the FULL chunks round a point: counts
## per kind, the step's time, and an EYE for still_shot.gd near the first few of each kind.
##   godot --headless --path . --script tools/street_clutter_2/probe.gd -- --spawn=x,z,0,0
## R=blocks (default 1), HOUR=h, DAY=0..6, KIND=<batch key> to list only that kind.
## Classes load at run time (the tool compiles before the autoloads exist).
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var c := Vector2.ZERO
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
	for i in 8:
		await process_frame
	var city = current_scene
	var plan = city.get("plan")
	var sc: GDScript = load("res://scripts/world/street_clutter_2.gd")
	if OS.get_environment("HOUR") != "":
		sc.set("force_hour", float(OS.get_environment("HOUR")))
	if OS.get_environment("DAY") != "":
		sc.set("force_day", int(OS.get_environment("DAY")))
	var reach := int(OS.get_environment("R")) if OS.get_environment("R") != "" else 1
	var want := OS.get_environment("KIND")
	var start: Vector2i = plan.block_index_at(c)
	var totals := {}
	for ix in range(start.x - reach, start.x + reach + 1):
		for iz in range(start.y - reach, start.y + reach + 1):
			var chunk = city.call("_new_chunk", Vector2i(ix, iz), 0)
			var t0 := Time.get_ticks_usec()
			chunk.call("build")
			var built := Time.get_ticks_usec() - t0
			var out: Dictionary = chunk.get_meta("street_clutter_2", {})
			# The step's own cost: plan the same chunk again (the lay is a batch.add a piece).
			var t1 := Time.get_ticks_usec()
			if not out.is_empty():
				sc.call("plan_block", chunk, plan.block(ix, iz))
			var planned := Time.get_ticks_usec() - t1
			var line := "BLOCK %d,%d district=%d rect=%s build=%.0fms plan=%.1fms" % [ix, iz, int(plan.block(ix, iz).district), str(plan.block(ix, iz).rect), built / 1000.0, planned / 1000.0]
			for key: String in out:
				line += " %s=%d" % [key, (out[key] as Array).size()]
				totals[key] = int(totals.get(key, 0)) + (out[key] as Array).size()
				if want != "" and key != want:
					continue
				var shown := 0
				for it: Array in out[key]:
					if shown >= (3 if want != "" else 1):
						break
					var o: Vector3 = (it[0] as Transform3D).origin
					var eye := Vector2(o.x, o.z) + Vector2(3.0, 3.0)
					var look := Vector2(o.x, o.z) - eye
					var yaw := rad_to_deg(atan2(-look.x, -look.y))
					print("  %s at=%.1f,%.1f EYE=%.1f,%.1f,%.1f,%.0f,-22" % [key, o.x, o.z, eye.x, o.y + 1.7, eye.y, yaw])
					shown += 1
			print(line)
			chunk.get_parent().remove_child(chunk)
			chunk.free()
	print("TOTALS ", totals)
	quit()
