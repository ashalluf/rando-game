extends SceneTree
## Walks the coast and prints, every Z_STEP metres from Z0 to Z1, where the waterline and the bike
## path are and what BeachLife plans there at an hour: people, props, courts, and an EYE for
## still_shot.gd standing on the sand looking along the beach. Headless, seconds:
##   godot --headless --path . --script tools/beach/probe.gd -- --hour=15
## Z0, Z1, Z_STEP (default -1500, 2500, 100).
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var hour := 15.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hour="):
			hour = arg.trim_prefix("--hour=").to_float()
	for i in 8:
		await process_frame
	var plan = current_scene.get("plan")
	var bl: GDScript = load("res://scripts/world/beach_life.gd")
	var z0 := float(OS.get_environment("Z0")) if OS.get_environment("Z0") != "" else -1500.0
	var z1 := float(OS.get_environment("Z1")) if OS.get_environment("Z1") != "" else 2500.0
	var step := float(OS.get_environment("Z_STEP")) if OS.get_environment("Z_STEP") != "" else 100.0
	var dens: float = bl.call("density", hour)
	print("DENSITY hour=%.1f %.2f" % [hour, dens])
	var z := z0
	var total := 0
	while z < z1:
		var cx: float = plan.macro.coast_x(z)
		var w: float = plan.macro.beach_width_at(z)
		var s: Dictionary = bl.call("plan_stretch", plan, z, z + step, dens)
		var kept: bool = bl.call("kept_off", plan, z + step * 0.5)
		var ppl: int = (s.people as Array).size()
		total += ppl
		var court := ""
		if not (s.court as Dictionary).is_empty():
			court = " court=%.1f,%.1f" % [(s.court.centre as Vector2).x, (s.court.centre as Vector2).y]
		print("Z %.0f coast=%.1f width=%.1f path=%.1f people=%d props=%d kept=%s%s EYE=%.1f,1.7,%.1f,180,-6" % [
			z, cx, w, bl.call("path_x", plan, z), ppl, (s.props as Array).size(), kept, court, cx + w * 0.62, z - 30.0])
		if OS.get_environment("PEOPLE") == "1":
			for q: Dictionary in s.people:
				print("  PERSON %s at=%.1f,%.1f key=%s pose=%d model=%d group=%d" % [str(q.group), q.at.x, q.at.y, q.key, q.pose, q.model, q.group])
		z += step
	print("TOTAL people ", total)
	quit()
