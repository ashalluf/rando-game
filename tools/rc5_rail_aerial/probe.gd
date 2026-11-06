extends SceneTree
## godot --headless --path . --script tools/rc5_rail_aerial/probe.gd

func _initialize() -> void:
	await process_frame
	load("res://tools/rc5_rail_aerial/probe_run.gd").new().call("run", self)
	quit()
