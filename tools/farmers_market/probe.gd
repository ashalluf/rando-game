extends SceneTree
## Farmers' market probe: every market the plan places in a window of the basin, with its street,
## day, stalls and an EYE for still_shot.gd, plus the kit's triangle counts and build times
## (seconds, headless):
##   godot --headless --path . --script tools/farmers_market/probe.gd [-- x0,z0,x1,z1]

func _initialize() -> void:
	await process_frame
	load("res://tools/farmers_market/probe_run.gd").new().call("run", self)
	quit()
