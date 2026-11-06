extends SceneTree
## rc5-cemetery-dawn: Hollycrest's lamps and crown (seconds, headless):
##   godot --headless --path . --script tools/cemetery/rc5_lamp_probe.gd

func _initialize() -> void:
	await process_frame
	load("res://tools/cemetery/rc5_lamp_probe_run.gd").new().call("run", self)
	quit()
