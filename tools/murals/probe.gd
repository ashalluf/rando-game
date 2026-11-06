extends SceneTree
## Lists the murals (Murals) of the FULL chunks round a point, with an EYE for each for
## tools/glshot/still_shot.gd, and counts them by kind:
##   MURAL_DEBUG=1 godot --headless --path . --script tools/murals/probe.gd -- --spawn=x,z [R=blocks]
## MODE=0..4 filters (0 mural, 1 ghost sign, 2 crosswalk, 3 cabinet, 4 frieze).
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var c := Vector2(2800, 100)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
	for i in 8:
		await process_frame
	var city = current_scene
	var plan = city.get("plan")
	var r := int(OS.get_environment("R")) if OS.get_environment("R") != "" else 2
	var want := int(OS.get_environment("MODE")) if OS.get_environment("MODE") != "" else -1
	var names := ["mural", "ghost", "crosswalk", "cabinet", "frieze"]
	var k0: Vector2i = plan.block_index_at(c)
	var counts := {}
	var t0 := Time.get_ticks_usec()
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var k := k0 + Vector2i(dx, dz)
			var chunk = city.call("_new_chunk", k, 0)
			chunk.build()
			for s: Array in chunk.get_meta("mural_spots", []):
				var mode: int = s[0]
				counts[names[mode]] = int(counts.get(names[mode], 0)) + 1
				if want >= 0 and mode != want:
					continue
				var at: Vector3 = s[1]
				var n: Vector3 = s[2]
				var w: float = s[3]
				var dist := clampf(maxf(w, float(s[4])) * 1.3, 6.0, 30.0)
				var eye := at + n * dist
				var pitch := -6.0
				if mode == 2:
					eye = at + Vector3(0.0, 12.0, 8.0)
					n = Vector3(0, 0, 1)
					pitch = -55.0
				elif mode == 3:
					eye = at + n * 3.0
					eye.y = at.y + 0.9
					pitch = -12.0
				else:
					eye.y = maxf(1.7, at.y - 1.0 + 1.7) if mode != 1 else 1.7 + plan.height_at(Vector2(at.x, at.z))
					pitch = rad_to_deg(atan2(at.y - eye.y, dist))
				var look := at - eye
				var yaw := rad_to_deg(atan2(-look.x, -look.z))
				print("MURAL %s block=%d,%d at=%.1f,%.1f,%.1f size=%.1fx%.1f EYE=%.1f,%.1f,%.1f,%.0f,%.0f" % [names[mode], k.x, k.y, at.x, at.y, at.z, w, s[4], eye.x, eye.y, eye.z, yaw, pitch])
			chunk.queue_free()
	print("COUNTS ", counts, " ms ", (Time.get_ticks_usec() - t0) / 1000)
	quit()
