extends SceneTree
## Film shoot probe: every shoot the plan places in a window of the basin, with its street, the
## basecamp, and EYEs for tools/glshot/still_shot.gd (seconds, headless):
##   godot --headless --path . --script tools/film_shoot/probe.gd [-- x0,z0,x1,z1]

func _initialize() -> void:
	await process_frame
	load("res://tools/film_shoot/probe_run.gd").new().call("run", self)
	quit()
