extends SceneTree
## Stills of the minimap, the full-screen map, the GPS route and the waypoint's beacon (WorldMap,
## MapPainter), from one load of the city. opengl3 under Xvfb, a minute or two:
##
##   OUT=map SHOTS="mini;map:2800,100,0.12;map:2700,300,1.2" WAYPOINT=2400,1500 \
##     xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --display-driver x11 \
##     --audio-driver Dummy --path . --script tools/minimap/map_shot.gd --resolution 1920x1080 \
##     -- --spawn=2700,300,0,-8 --hour=13 --nohud
##
## SHOTS is a ;-list, saved as OUT_<n>_<kind>.png: `mini` (the HUD in its clean mode, and a crop
## of the minimap OUT_<n>_mini_crop.png), `map:x,z,ppm` (the full map centred on world x,z at ppm
## screen pixels per metre at 1080 lines), `beacon` (map closed, HUD hidden: the world with the
## waypoint's beacon). WAYPOINT=x,z sets the waypoint first and runs its route to the end;
## WAYPOINT_AHEAD=m puts it that far ahead of the camera instead. FRAMES frames of streaming first
## (default 60). YAW=deg turns the camera rig first (the minimap turns with it). STARS=n puts the
## police on (n stars) for the blips.
func _initialize() -> void:
	Engine.set_meta("postfx_motion_blur", 0.0)
	change_scene_to_file("res://scenes/levels/city.tscn")
	var frames := int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 60
	for i in frames:
		await process_frame
	var city := get_first_node_in_group("city")
	var player: Node3D = get_first_node_in_group("player")
	var hud := get_root().get_child(get_root().get_child_count() - 1).get_node_or_null("DebugHud")
	var wm = get_first_node_in_group("world_map")
	if wm == null or city == null or player == null:
		print("no map")
		quit(1)
		return
	if OS.get_environment("YAW") != "":
		var rig: Node3D = player.get("camera_rig")
		if rig:
			rig.global_rotation.y = deg_to_rad(float(OS.get_environment("YAW")))
	# The basin's map data in one go (the HUD warms it a slice a frame).
	var data = load("res://scripts/ui/map_data.gd").of(city.plan)
	while not data.warm(1000000):
		pass
	if OS.get_environment("STARS") != "":
		var police := get_first_node_in_group("wanted")
		if police:
			police.set("enabled", true)
			police.set("stars", int(OS.get_environment("STARS")))
	var wp_env := OS.get_environment("WAYPOINT")
	var ahead := OS.get_environment("WAYPOINT_AHEAD")
	if ahead != "":
		var cam := get_root().get_camera_3d()
		var f := -cam.global_basis.z
		f.y = 0.0
		var at: Vector3 = city.world_position(cam.global_position + f.normalized() * float(ahead))
		wm.set_waypoint(Vector2(at.x, at.z))
	elif wp_env != "":
		var p := wp_env.split(",")
		wm.set_waypoint(Vector2(float(p[0]), float(p[1])))
	if wm.has_waypoint():
		wm.finish_route()
		var r = wm.route()
		print("ROUTE ok=%s points=%d length=%.0f" % [str(r.ok if r else false), r.points.size() if r else 0, r.length if r else 0.0])
	var out := OS.get_environment("OUT")
	if out == "":
		out = "map"
	var shots := OS.get_environment("SHOTS").split(";", false)
	if shots.is_empty():
		shots = PackedStringArray(["mini"])
	for n in shots.size():
		var spec := shots[n]
		var kind := spec.split(":")[0]
		var file := "%s_%d_%s.png" % [out, n, kind]
		match kind:
			"mini":
				wm.close()
				if hud:
					hud.set("mode", 0)
					hud.call("_apply_mode")
				for i in 6:
					await process_frame
				var img := get_root().get_texture().get_image()
				img.save_png(file)
				var mm: Control = hud.get_node("MinimapFrame") if hud else null
				if mm:
					var r := Rect2i(Vector2i(mm.global_position) - Vector2i(40, 40), Vector2i(mm.size) + Vector2i(80, 80))
					r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
					img.get_region(r).save_png(file.replace(".png", "_crop.png"))
				var mini = hud.get_node("MinimapFrame/Minimap") if hud else null
				if mini:
					var worst := 0
					for i in 10:
						mini.queue_redraw()
						await process_frame
						worst = maxi(worst, int(mini.get("last_draw_usec")))
					print("MINIMAP draw worst of 10: %.2f ms" % (worst / 1000.0))
			"map":
				var p := spec.split(":")[1].split(",")
				wm.open()
				wm.center = Vector2(float(p[0]), float(p[1]))
				wm.ppm = float(p[2]) * clampf(get_root().get_visible_rect().size.y / 1080.0, 0.6, 3.0)
				wm.call("_refresh")
				for i in 6:
					await process_frame
				get_root().get_texture().get_image().save_png(file)
				wm.close()
			"beacon":
				wm.close()
				if hud:
					hud.set("mode", 2)
					hud.call("_apply_mode")
				for i in 8:
					await process_frame
				get_root().get_texture().get_image().save_png(file)
		print("saved ", file)
	quit()
