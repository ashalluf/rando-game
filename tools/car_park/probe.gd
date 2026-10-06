extends SceneTree
## Car park probe: every multi-storey car park the plan places in a window of the basin, its
## size, decks and stalls, and EYEs for tools/glshot/still_shot.gd (seconds, headless):
##   godot --headless --path . --script tools/car_park/probe.gd [-- x0,z0,x1,z1]
## BUILD=1 also builds the nearest one's block at FULL and prints the build time and triangles.

func _initialize() -> void:
	await process_frame
	await load("res://tools/car_park/probe_run.gd").new().call("run", self)
	quit()
