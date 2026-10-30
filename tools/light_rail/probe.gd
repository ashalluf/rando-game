extends SceneTree
## Light-rail probe: prints the route the plan resolves (legs, stations, crossings) and what the
## map says along it. godot --headless --path . --script tools/light_rail/probe.gd

func _initialize() -> void:
	await process_frame
	var runner: RefCounted = load("res://tools/light_rail/probe_run.gd").new()
	runner.call("run", self)
	quit()
