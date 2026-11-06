extends SceneTree
## CrowdFeet's cost at a spot, headless (docs/HANDOFF.md, the perf-audit-3 section): loads the city,
## settles, then counts CrowdFeet's calls and its time in _sample() (the rays) and in all of it
## over FRAMES physics frames. Run it on two trees to compare.
##
##   godot --headless --path . --script tools/perf_audit_3/feet_probe.gd -- --spawn=2359.4,880,0,12,2
func _initialize() -> void:
	root.add_child((load("res://scenes/levels/city.tscn") as PackedScene).instantiate())
	for i in int(_env("SETTLE", "400")):
		await physics_frame
	var feet: GDScript = load("res://scripts/npc/crowd_feet.gd")
	var c0: int = feet.calls
	var s0: int = feet.cost_sample_usec
	var u0: int = feet.cost_usec
	var frames := int(_env("FRAMES", "600"))
	for i in frames:
		await physics_frame
	print("FEET %d physics frames: %d foot ticks, rays %.1f ms (%.2f ms a frame), all %.1f ms (%.2f ms a frame)" % [frames,
		feet.calls - c0, (feet.cost_sample_usec - s0) / 1000.0, (feet.cost_sample_usec - s0) / 1000.0 / frames,
		(feet.cost_usec - u0) / 1000.0, (feet.cost_usec - u0) / 1000.0 / frames])
	quit()


func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d
