extends SceneTree
## Cemetery probe: every memorial park the plan places in a window of the basin, its size, crown,
## drive, trees and an EYE for still_shot.gd (seconds, headless):
##   godot --headless --path . --script tools/cemetery/probe.gd [-- x0,z0,x1,z1]

func _initialize() -> void:
	await process_frame
	load("res://tools/cemetery/probe_run.gd").new().call("run", self)
	quit()
