extends SceneTree
## Lists the beach bonfire rings (Bonfires.rings_in) along a stretch of shore, for framing stills:
##   godot --headless --path . --script tools/bonfires/probe.gd -- [--z0=-600 --z1=1400] [--hour=21]
## Each line: the ring's slot, its true-world point, whether it burns at the hour (night 0, clear),
## how many sit round it, and two EYEs for still_shot.gd: one standing 7 m off on the land side
## looking at it, one 22 m up the beach a little above, looking down along the row.
## Headless is enough: only the plan is read.
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var z0 := -600.0
	var z1 := 1400.0
	var hour := 21.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--z0="):
			z0 = arg.trim_prefix("--z0=").to_float()
		if arg.begins_with("--z1="):
			z1 = arg.trim_prefix("--z1=").to_float()
		if arg.begins_with("--hour="):
			hour = arg.trim_prefix("--hour=").to_float()
	for i in 8:
		await process_frame
	var plan = current_scene.get("plan")
	var bf: GDScript = load("res://scripts/world/bonfires.gd")
	var rings: Array = bf.call("rings_in", plan, z0, z1)
	var lit := 0
	for r: Dictionary in rings:
		var at: Vector2 = r.at
		var land: Vector2 = r.land
		var on: bool = bf.call("lit_at", plan, int(r.k), hour, 0, 0)
		var n: int = (bf.call("group", plan, r, int((bf.call("night_of", hour, 0) as Array)[0])) as Array).size() if on else 0
		lit += int(on)
		var e1 := at + land * 7.0
		var d1 := at - e1
		var e2 := at + land * 9.0 + Vector2(-land.y, land.x) * 20.0
		var d2 := at - e2
		print("RING k=%d at=(%.1f, %.1f) lit=%s people=%d EYE=%.1f,1.7,%.1f,%.1f,-8 EYE2=%.1f,6,%.1f,%.1f,-12" % [int(r.k), at.x, at.y, str(on), n,
			e1.x, e1.y, rad_to_deg(atan2(-d1.x, -d1.y)), e2.x, e2.y, rad_to_deg(atan2(-d2.x, -d2.y))])
	print("RINGS %d, lit at %.1f: %d" % [rings.size(), hour, lit])
	quit()
