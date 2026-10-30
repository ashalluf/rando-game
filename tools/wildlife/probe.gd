extends SceneTree
## Lists where the wildlife lives round a point at an hour (Wildlife.plan_cell, pure), for framing
## stills and judging the odds:
##   godot --headless --path . --script tools/wildlife/probe.gd -- --spawn=x,z,0,0 [--hour=6.5]
## R=metres (default 600), SPECIES=coyote|deer|raccoon|squirrel|rabbit to filter, MAX=lines per
## species (default 6). Prints the counts per species and habitat, then each spot: species, kind
## (idle | cross | bins), count, the true-world point and an EYE for still_shot.gd 9 m off it at
## eye height looking at it.
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var c := Vector2.ZERO
	var hour := 6.5
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
		if arg.begins_with("--hour="):
			hour = arg.trim_prefix("--hour=").to_float()
	for i in 8:
		await process_frame
	var plan = current_scene.get("plan")
	var wl: GDScript = load("res://scripts/world/wildlife.gd")
	var reach := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 600.0
	var want := OS.get_environment("SPECIES")
	var max_lines := int(OS.get_environment("MAX")) if OS.get_environment("MAX") != "" else 6
	var cell: float = wl.get("CELL") if wl.get("CELL") else 46.0
	var counts := {}
	var lines := {}
	var t0 := Time.get_ticks_usec()
	var cells := 0
	for cx in range(floori((c.x - reach) / 46.0), floori((c.x + reach) / 46.0) + 1):
		for cz in range(floori((c.y - reach) / 46.0), floori((c.y + reach) / 46.0) + 1):
			cells += 1
			for s: Dictionary in wl.call("plan_cell", plan, cx, cz, hour):
				var key := "%s/%s" % [s.species, s.habitat]
				counts[key] = int(counts.get(key, 0)) + int(s.count)
				if want != "" and s.species != want:
					continue
				var n: int = lines.get(s.species, 0)
				if n >= max_lines:
					continue
				lines[s.species] = n + 1
				var at: Vector2 = s.at
				var gy: float = plan.height_at(at)
				var eye := at + Vector2(9.0, 0.0)
				print("SPOT %s %s x%d at %.1f,%.1f gy %.1f  EYE=%.1f,%.1f,%.1f,90,-8" % [s.species, s.kind, s.count, at.x, at.y, gy, eye.x, gy + 1.6, eye.y])
	print("CELLS %d in %d ms" % [cells, (Time.get_ticks_usec() - t0) / 1000])
	var keys := counts.keys()
	keys.sort()
	for k in keys:
		print("COUNT %s %d" % [k, counts[k]])
	quit()
