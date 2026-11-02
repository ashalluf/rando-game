extends SceneTree
## A still of the city from a FREE camera, for framing landmarks: the city streams in around the
## `--spawn` (the player is held there and hidden), then a camera at CAM (world x,y,z) looking at
## LOOK (world x,y,z) takes the frame. Both are TRUE world positions (re-centering is undone).
##
##   OUT=shot.png CAM=380,6,440 LOOK=352,18,474 FOV=60 FRAMES=90 LIBGL_ALWAYS_SOFTWARE=1 \
##     xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --display-driver x11 \
##     --audio-driver Dummy --path . --script tools/glshot/landmark_shot.gd --resolution 1280x720 \
##     -- --spawn=380,440,0,0 --hour=18.3 --nohud
##
## Env: OUT, CAM, LOOK, FOV (default 60), FRAMES (streaming frames before the shot, default 90),
## SETTLE (frames with the clock nearly frozen, default 4), HIDE (node-name patterns to hide).
## Also prints the frame's triangles / draw calls / objects (a real renderer: never --headless).
## On opengl3 this is the Compatibility renderer - judge geometry and materials, not the light;
## the same script runs through the real Forward+ pipeline with --rendering-driver vulkan.
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var frames := int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 90
	var settle := int(OS.get_environment("SETTLE")) if OS.get_environment("SETTLE") != "" else 4
	var cam_pos := _vec(OS.get_environment("CAM"), Vector3(0.0, 20.0, 0.0))
	var look := _vec(OS.get_environment("LOOK"), Vector3(0.0, 0.0, -50.0))
	var fov := float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 60.0
	var hide := OS.get_environment("HIDE").split(",", false)
	var hold := Vector3.INF
	var cam: Camera3D = null
	for i in frames + settle:
		await process_frame
		var scene := current_scene
		if scene == null:
			continue
		var player := get_first_node_in_group("player") as Node3D
		if player:
			if hold == Vector3.INF:
				hold = player.global_position
			player.global_position = hold
			player.set("velocity", Vector3.ZERO)
			player.visible = false
		var ws := root.get_node_or_null("/root/WorldState")
		var off: Vector3 = ws.get("world_offset") if ws else Vector3.ZERO
		if cam == null:
			cam = Camera3D.new()
			cam.name = "LandmarkShotCamera"
			scene.add_child(cam)
			cam.far = 4000.0
		cam.fov = fov
		cam.global_position = cam_pos - off
		cam.look_at(look - off, Vector3.UP)
		cam.current = true
		for pattern in hide:
			for n in scene.find_children(pattern, "", true, false):
				if n is Node3D:
					(n as Node3D).visible = false
		if i == frames:
			Engine.time_scale = 0.0005
	var day := current_scene.get_node_or_null("DayNight") if current_scene else null
	if day:
		print("clock ", day.clock_text(), "  night_factor %.2f" % day.night_factor)
	var out := OS.get_environment("OUT")
	if out == "":
		out = "landmark_shot.png"
	get_root().get_texture().get_image().save_png(out)
	print("STATS tris=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		" draws=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		" objects=", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	print("saved ", out)
	quit()


static func _vec(text: String, fallback: Vector3) -> Vector3:
	var p := text.split(",")
	if p.size() < 3:
		return fallback
	return Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())
