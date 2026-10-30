extends SceneTree
## Frame strips of the chase camera (DriveCam) from a scripted drive in the city: the player at
## the wheel, the car's velocity set every tick (it still rides its wheels on the road), stills
## from the player's own camera. Run with --fixed-fps 60 so every frame is 1/60 s of game time
## whatever the software renderer manages. Scenarios: s30, s80, s150 (straight up Flower St),
## corner (35 km/h right turn onto Olympic), jump (80 km/h, a 9 m/s hop). Stills go to
## OUT_DIR/<PREFIX><scenario>_<n>.jpg; tools/driving_camera/strips.py joins them into strips.
##   OUT_DIR=build/drivecam PREFIX=after_ xvfb-run -a -s "-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . --fixed-fps 60 \
##     --script tools/driving_camera/drive_strip.gd --resolution 1280x720 -- \
##     --spawn=2363,960,0,-8,2 --nohud --hour=16
## SCENARIOS=s30,s80 picks some; DRIVE_CAM=0 is the before (the old free camera).

func _initialize() -> void:
	Engine.set_meta("postfx_motion_blur", 0.0)
	change_scene_to_file("res://scenes/levels/city.tscn")
	for i in 12:
		await process_frame
	await load("res://tools/driving_camera/drive_strip_run.gd").new().run(self)
	quit()
