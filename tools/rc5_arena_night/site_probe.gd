extends SceneTree
## Prints the arena district's site rects (world XZ) and the plaza's parts, for framing arena_night.
##   godot --headless --path . --script tools/rc5_arena_night/site_probe.gd
func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/levels/city.tscn")
	var streamer: Node3D = scene.instantiate()
	root.add_child(streamer)
	for i in 3:
		await process_frame
	var plan: Variant = streamer.get("plan")
	var CS: Variant = load("res://scripts/world/civic_sites.gd")
	var LA: Variant = load("res://scripts/world/landmark_arena_district.gd")
	for id in ["arena", "live_plaza", "live_hotel", "convention_center"]:
		var info: Dictionary = CS.site(plan, id)
		print("SITE %s world %s centre %s yaw %.2f y0 %.2f" % [id, str(info.world), str(info.centre), info.yaw, info.y0])
		if id == "live_plaza":
			var p: Rect2 = LA._plaza_open(info.local)
			print("  plaza_open world %s grove_z(local) %.1f" % [str(CS.rect_to_world(info, p)), LA._plaza_grove_z(p)])
	quit()
