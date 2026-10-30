extends SceneTree
## Loads the city at a camera and prints what the frame costs: draw calls, objects and
## triangles, averaged over the last frames. Used to measure the generated car wheels against
## the wheels baked into the body models at the same downtown camera.
##
##   SPAWN=300,300,45,-6,3 FRAMES=70 WHEELS=0 LIBGL_ALWAYS_SOFTWARE=1 \
##     xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##     --display-driver x11 --audio-driver Dummy --path . --script tools/glshot/city_stats.gd \
##     --resolution 1280x720 -- --spawn=300,300,45,-6,3 --hour=11 --nohud
##
## WHEELS=0 turns the generated wheels off fleet-wide (Vehicle.wheels_enabled), which is the
## "before" side of the measurement. It has to be set before the scene loads, so it goes through
## the script resource rather than by naming Vehicle as a type: this script is compiled before
## the autoloads exist and Vehicle reaches for Sfx (CLAUDE.md).
func _initialize() -> void:
	if OS.get_environment("WHEELS") == "0":
		var s: GDScript = load("res://scripts/vehicles/vehicle.gd")
		s.set("wheels_enabled", false)
	change_scene_to_file("res://scenes/levels/city.tscn")
	var frames := 70
	if OS.get_environment("FRAMES") != "":
		frames = int(OS.get_environment("FRAMES"))
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
	var draws := 0.0
	var objects := 0.0
	var tris := 0.0
	var n := 12
	for i in n:
		await process_frame
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		tris += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	# "Cars in the scene" is not what the wheels cost: a wheel only draws within
	# Vehicle.wheel_draw_distance of the camera, and a caliper within caliper_distance. Count
	# those, or a measurement taken where two cars are visible gets reported as if it had
	# measured a hundred and fifty.
	var cars := get_nodes_in_group("vehicle")
	var cam := get_root().get_camera_3d()
	var eye: Vector3 = cam.global_position if cam else Vector3.ZERO
	var near := 0
	var mid := 0
	var cal := 0
	for c in cars:
		var d: float = (c as Node3D).global_position.distance_to(eye)
		if d <= 85.0:
			near += 1
			if d <= 30.0:
				mid += 1
			if d <= 26.0:
				cal += 1
	print("STATS wheels=%s cars=%d within85=%d within30=%d calipers=%d draws=%.0f objects=%.0f tris=%.0f" % [
		OS.get_environment("WHEELS") != "0", cars.size(), near, mid, cal,
		draws / n, objects / n, tris / n])
	var out := OS.get_environment("OUT")
	if out != "":
		get_root().get_texture().get_image().save_png(out)
		print("saved ", out)
	quit()
