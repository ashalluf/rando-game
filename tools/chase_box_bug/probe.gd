extends SceneTree
## Finds what draws the pale rectangles round the player's own car's tail lamps (the chase-box bug).
## Stages the drive_strip scene (a sedan up Flower St at 30 km/h, the player at the wheel), stops
## the car, pauses the tree, and shoots: the plain frame, then frames with groups of drawables
## taken OUT OF THE RENDER by their layers (not `visible`: a script that re-shows its node every
## frame defeats a visibility bisection). Prints, per shot, how pale the two lamp squares read.
##   OUT_DIR=build/chasebox xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##     --display-driver x11 --audio-driver Dummy --path . --fixed-fps 60 \
##     --script tools/chase_box_bug/probe.gd --resolution 1280x720 -- --spawn=2363,960,0,-8,2 --nohud --hour=16

func _initialize() -> void:
	Engine.set_meta("postfx_motion_blur", 0.0)
	change_scene_to_file("res://scenes/levels/city.tscn")
	for i in 12:
		await process_frame
	await load("res://tools/chase_box_bug/probe_run.gd").new().run(self)
	quit()
