extends SceneTree
## godot --headless --path . --script tools/rc5_fire_station/probe.gd
## Lists the fire stations within RADIUS (env, default 3500 m) of downtown with their district,
## street, frame and an EYE across the street looking at the bays (rc5-fire-station-night).

func _initialize() -> void:
	await process_frame
	load("res://tools/rc5_fire_station/probe_run.gd").new().call("run", self)
	quit()
