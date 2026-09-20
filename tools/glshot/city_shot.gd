extends SceneTree
## Renders the city scene with the real OpenGL renderer under a virtual display and saves a PNG,
## without a browser or a web export. Same spawn syntax as the game:
##
##   OUT=city.png SPAWN=300,300,45,-8 HOUR=11 FRAMES=40 LIBGL_ALWAYS_SOFTWARE=1 \
##     xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --display-driver x11 \
##     --audio-driver Dummy --path . --script tools/glshot/city_shot.gd --resolution 960x540 \
##     -- --spawn=300,300,45,-8 --hour=11
##
## The `--spawn` / `--hour` after `--` are what CityStreamer and DayNight read; OUT and FRAMES
## (frames to wait for streaming before the shot) are read here. It is the Compatibility renderer,
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
	for i in frames:
		await process_frame
		if hold > 0.0:
			var player: Node3D = get_first_node_in_group("player")
			if player:
				player.global_position.y = hold
				player.set("velocity", Vector3.ZERO)
	var out := OS.get_environment("OUT")
	if out == "":
		out = "city_shot.png"
	get_root().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
