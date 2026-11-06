extends SceneTree
## Stills of the window-washing gondolas (TowerGondolas) on ONE landmark tower, alone, in under a
## minute: the tower built detailed at the origin with its rigs forced live, a sun and a sky, and
## a camera framed on a cradle. Compatibility renderer: judge geometry and materials, not light.
##
##   OUT=g.png TOWER=dt_bronze_slab SITE=0 VIEW=near T=4000 LIBGL_ALWAYS_SOFTWARE=1 \
##     xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --display-driver x11 \
##     --audio-driver Dummy --path . --script tools/gondolas/gondola_shot.gd --resolution 1280x720
##
## Env: TOWER (a LandmarkDowntown id), SITE (index of the hung site), VIEW near | side | below |
## roof | far | close (or CAM=dist,up,along relative to the cradle), FOV, T (GONDOLA_T: the clock),
## HIT=n rounds (a blast with HIT=blast) at the cradle before the shot, SHOT_AFTER seconds of
## simulated swing after the hit, NIGHT=1, LIST=1 prints every tower's sites and quits.
var _run: RefCounted


func _initialize() -> void:
	await process_frame
	# Held here: a RefCounted freed mid-await never resumes.
	_run = load("res://tools/gondolas/gondola_shot_run.gd").new()
	_run.call("run", self)
