extends SceneTree
## What the far city (Skyline) draws for the blocks round a point: captures each block's LOD build
## the way Skyline does and prints its district, box instances by kind, plain boxes, and the plate.
##   godot --headless --path . --script tools/mid_city/probe.gd -- --at=x,z [--n=2]

func _initialize() -> void:
	await process_frame
	var runner: RefCounted = load("res://tools/mid_city/probe_run.gd").new()
	runner.call("run", self)
