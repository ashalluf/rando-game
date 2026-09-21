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
func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/levels/city.tscn")
	root.add_child(scene.instantiate())
	await process_frame
	for i in 90:
		await process_frame
	var tris := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var objs := Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	print("GEO tris=%d draws=%d objects=%d" % [int(tris), int(draws), int(objs)])
	quit()
