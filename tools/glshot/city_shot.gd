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
	for i in frames:
		await process_frame
	var out := OS.get_environment("OUT")
	if out == "":
		out = "city_shot.png"
	get_root().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
