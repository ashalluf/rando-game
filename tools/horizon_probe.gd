extends SceneTree
## Renders the city scene like tools/glshot/city_shot.gd, but also prints the render statistics
## (triangles, draw calls, objects) for the frame it saves. Used to measure the horizon plane's
## cost before and after a change, because "looks better" is not evidence.
##
##   OUT=shot.png FRAMES=70 LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1600x900x24" \
##     godot --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/horizon_probe.gd --resolution 1280x720 -- --spawn=700,420,180,-16,120 \
##     --hour=11 --nohud
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var frames := 40
	var f := OS.get_environment("FRAMES")
	if f != "":
		frames = int(f)
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
		out = "horizon_probe.png"
	get_root().get_texture().get_image().save_png(out)
	print("STATS tris=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		" draws=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		" objects=", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	print("saved ", out)
	quit()
