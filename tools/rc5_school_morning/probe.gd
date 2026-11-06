extends SceneTree
## rc5-school-morning: one elementary school's plan in detail (facilities, the front road, the bus
## spots, the sign and the flagpole) for framing the refcam (seconds, headless):
##   CELL=-1,-1 godot --headless --path . --script tools/rc5_school_morning/probe.gd

func _initialize() -> void:
	await process_frame
	load("res://tools/rc5_school_morning/probe_run.gd").new().call("run", self)
	quit()
