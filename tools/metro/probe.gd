extends SceneTree
## The underground station's probe (MetroStation, MetroBuild): the frame, the exits, the
## chunk's build (triangles per mesh, collision boxes, riders, time) and an EYE for the stills.
##   godot --headless --path . --script tools/metro/probe.gd

func _initialize() -> void:
	await process_frame
	var runner: RefCounted = load("res://tools/metro/probe_run.gd").new()
	await runner.call("run", self)
	quit()
