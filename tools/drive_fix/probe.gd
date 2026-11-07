extends SceneTree
## Driving probe (wave 9 drive-fix): a car on a flat floor driven by simulated Input actions.
## Prints 0-100 km/h, top speed, and yaw rate with move_left vs move_right at 5 / 15 / 30 m/s,
## per body type. Headless, seconds a body:
##   godot --headless --path . --script tools/drive_fix/probe.gd [-- --types=0,1,2 --real-player]
## MODE=room drives with the real Player in the test box (enter_vehicle), MODE=city on a
## straight downtown street (Flower St; heavy). DRIVE_FIX=0 is the before. TYPES= picks body types (Vehicle.BodyType ints; "moto" / "low").

func _initialize() -> void:
	var mode := OS.get_environment("MODE")
	if mode == "room":
		change_scene_to_file("res://scenes/levels/test_box.tscn")
		for i in 8:
			await process_frame
	elif mode == "city":
		change_scene_to_file("res://scenes/levels/city.tscn")
		for i in 12:
			await process_frame
	await process_frame
	await load("res://tools/drive_fix/probe_run.gd").new().run(self)
	quit()
