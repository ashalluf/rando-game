extends SceneTree
## rc5-car-park-roof probe: the car park nearest AT=x,z (default the TEMPLE GARAGE on Pershing's
## west side), its frame, its roof height, the roof's drive path and an EYE on the roof by the
## ramp's head looking along the structure (headless, seconds):
##   godot --headless --path . --script tools/rc5_car_park_roof/probe.gd

func _initialize() -> void:
	await process_frame
	await load("res://tools/rc5_car_park_roof/probe_run.gd").new().call("run", self)
	quit()
