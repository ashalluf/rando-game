extends SceneTree
## Schools probe: every school the plan places in a window of the basin, with its kind, name,
## blocks, the closed streets, its facilities and an EYE for still_shot.gd (seconds, headless):
##   godot --headless --path . --script tools/schools/probe.gd [-- x0,z0,x1,z1]

func _initialize() -> void:
	await process_frame
	load("res://tools/schools/probe_run.gd").new().call("run", self)
	quit()
