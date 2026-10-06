extends SceneTree
## Drive a car up a multi-storey car park and take stills on the way (the garage-drive-in
## sequence): the player gets in a car on the street in front of the car park nearest CP=x,z and
## the autopilot (autopilot.gd: the player's own controls) drives it in past the barrier, round
## the ground deck, up every ramp to the roof. Stills (jpg) go to OUT_DIR as <PREFIX>NN_<name>.jpg.
##   CP=1699,328 OUT_DIR=build/cp PREFIX= xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/car_park/drive_shot.gd --resolution 1280x720 -- --spawn=1660,300,0,0,2 --nohud --hour=15
## TO_DECK=n stops on that deck; NO_DRIVE=1 only takes the exterior shot; BODY=<Vehicle.BodyType>.

func _initialize() -> void:
	Engine.set_meta("postfx_motion_blur", 0.0)
	change_scene_to_file("res://scenes/levels/city.tscn")
	for i in 12:
		await process_frame
	await load("res://tools/car_park/drive_run.gd").new().run(self)
	quit()
