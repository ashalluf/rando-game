extends SceneTree
## Lists the Coral Line's gated crossings with what framing the rail_crossing refcam needs.
## godot --headless --path . --script tools/rc5_rail_crossing/probe.gd

func _initialize() -> void:
	await process_frame
	var runner: RefCounted = load("res://tools/rc5_rail_crossing/probe_run.gd").new()
	runner.call("run", self)
	quit()
