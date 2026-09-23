extends SceneTree
## Renders the city scene with the real OpenGL renderer under a virtual display and saves a PNG,
## without a browser or a web export. Same spawn syntax as the game:
##
##   OUT=city.png SPAWN=300,300,45,-8 HOUR=11 FRAMES=40 LIBGL_ALWAYS_SOFTWARE=1 \
##     xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --display-driver x11 \
##     --audio-driver Dummy --path . --script tools/glshot/city_shot.gd --resolution 960x540 \
##     -- --spawn=300,300,45,-8 --hour=11
##
## The `--spawn` / `--hour` after `--` are what CityStreamer and DayNight read; OUT, FRAMES
## (frames to wait for streaming before the shot), HIDE (node name patterns to hide) and OCCLUSION=0
## (occlusion culling off) are read here. It is the Compatibility renderer,
## so lighting is flatter than the Mac build; judge geometry and materials. A shot takes a minute or
## two on llvmpipe.
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var frames := 40
	var f := OS.get_environment("FRAMES")
	if f != "":
		frames = int(f)
	# Hold the requested height: the player falls during the seconds of streaming, so an aerial
	# shot taken after it lands on the street instead of looking down on the city.
	var hold := 0.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var parts := arg.trim_prefix("--spawn=").split(",")
			if parts.size() >= 5:
				hold = parts[4].to_float()
	# HIDE=Planting_*,FarLandmark_* hides every node under the scene matching those name patterns
	# (find_children wildcards), re-applied each frame because chunks and tiles keep streaming in.
	# For telling apart which of several overlapping things a stray pixel belongs to.
	var hide := OS.get_environment("HIDE").split(",", false)
	# OCCLUSION=0 renders without occlusion culling, to diff against a normal shot: anything that
	# is in one and not the other was culled while in plain sight, i.e. an occluder is too big.
	if OS.get_environment("OCCLUSION") == "0":
		get_root().use_occlusion_culling = false
	for i in frames:
		await process_frame
		if not hide.is_empty() and get_root().get_child_count() > 0:
			var scene := get_root().get_child(get_root().get_child_count() - 1)
			for pattern in hide:
				for n in scene.find_children(pattern, "", true, false):
					if n is Node3D:
						(n as Node3D).visible = false
		if hold > 0.0:
			var player: Node3D = get_first_node_in_group("player")
			if player:
				player.global_position.y = hold
				player.set("velocity", Vector3.ZERO)
	# What the frame was ACTUALLY rendered at. DayNight advances its own clock in _process, and a
	# software frame takes seconds, so a shot asked for at --hour=13 can land somewhere else
	# entirely; the camera's auto exposure is still converging too. A uniform brightness shift
	# between two shots of the same camera is almost always one of these two rather than anything
	# in the scene, and guessing at it costs a render every time.
	var dn := get_first_node_in_group("player")
	var city := get_root().get_child(get_root().get_child_count() - 1)
	var day := city.get_node_or_null("DayNight") if city else null
	if day:
		print("clock ", day.clock_text(), "  night_factor %.2f" % day.night_factor)
	var cam := get_root().get_camera_3d()
	if cam and cam.attributes:
		print("exposure multiplier %.3f  auto %s" % [cam.attributes.exposure_multiplier, str(cam.attributes.auto_exposure_enabled)])
	var out := OS.get_environment("OUT")
	if out == "":
		out = "city_shot.png"
	get_root().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
