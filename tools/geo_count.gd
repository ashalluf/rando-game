extends SceneTree
## Triangle, draw-call and object count for one frame of the city, so a geometry change can be
## measured instead of argued about.
##
##   LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 800x600x24" godot \
##     --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy \
##     --path . --script tools/geo_count.gd --resolution 800x600
##
## It must run under a real renderer. `--headless` uses the dummy rendering server, where every
## Performance monitor reads zero and a change of any size looks like no change at all.
##
## AB=Batch_sig_*,BatchShadow_sig_* counts the frame, hides every node whose name matches one of
## those patterns, and counts the same frame again, so the cost of one kind of geometry comes out
## of a single run with the traffic, the crowd and the camera exactly where they were.
func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/levels/city.tscn")
	root.add_child(scene.instantiate())
	await process_frame
	for i in 90:
		await process_frame
	_report("GEO")
	var patterns := OS.get_environment("AB").split(",", false)
	if patterns.is_empty():
		quit()
		return
	# Hold the world still for the second count: same cars, same people, same frame.
	Engine.time_scale = 0.0
	await process_frame
	await process_frame
	_report("GEO with")
	var hidden := 0
	for n in root.find_children("*", "Node3D", true, false):
		for p in patterns:
			if String(n.name).match(p):
				(n as Node3D).visible = false
				hidden += 1
				break
	await process_frame
	await process_frame
	_report("GEO without (%d nodes hidden)" % hidden)
	quit()


func _report(label: String) -> void:
	var tris := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var objs := Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	print("%s tris=%d draws=%d objects=%d" % [label, int(tris), int(draws), int(objs)])
