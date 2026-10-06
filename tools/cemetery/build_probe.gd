extends SceneTree
## Builds a memorial park's chunks headless at FULL, LOD and in the far city's capture mode and
## prints what each made and how long its slowest step took (seconds; no renderer):
##   godot --headless --path . --script tools/cemetery/build_probe.gd [-- ix,iz]
## With no block, the first park the plan finds round the basin.

func _initialize() -> void:
	await process_frame
	load("res://tools/cemetery/build_probe_run.gd").new().call("run", self)
	quit()
