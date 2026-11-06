extends SceneTree
## High schools with their game nights and stadiums (headless, seconds):
##   godot --headless --path . --script tools/rc5_friday_lights/probe.gd
func _initialize() -> void:
	await process_frame
	load("res://tools/rc5_friday_lights/probe_run.gd").new().call("run", self)
	quit()
