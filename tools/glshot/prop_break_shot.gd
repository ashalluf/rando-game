extends SceneTree
## Street props breaking (PropBreak, scripts/world/prop_break.gd) on their own: a pavement with a
## hydrant, a street lamp, a bus shelter, a mailbox, a parking meter and a news box in a row,
## built through a real CityChunk's _add_prop() (so the records, batches and shapes are the
## city's), then broken at once and shot at given moments. Seconds a frame instead of minutes.
##
##   OUT=pb CAPS=0,0.3,1.5 CAM=-6,1.7,9 LOOK=0,1.2,0 xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver opengl3 --audio-driver Dummy --path . \
##     --script tools/glshot/prop_break_shot.gd --resolution 1280x720
##
## Env: OUT (prefix: <OUT>_<i>.png per CAPS entry), CAPS (seconds after the break; a negative one
## is the BEFORE, shot before anything breaks), CAM / LOOK (x,y,z), FOV, NIGHT=1, BREAK = the kinds
## to break (default all: hydrant,lamp,bus_stop,mailbox,meter,newsbox; "lean" bends the lamp
## instead; "glass" breaks only the shelter's glass), CAR=1 drives a sedan into the hydrant and
## the lamp at CAR_SPEED (m/s) instead of breaking them by hand, PROP_BREAK=0 the old breaks.
## Layout: kerb along x at z 0, the road at z > 0, the props at z -0.8 from x -10, 4 m apart.

func _initialize() -> void:
	await process_frame
	# Loaded now, not named: a script naming CityChunk compiles before the autoloads exist.
	await load("res://tools/glshot/prop_break_stage.gd").new().run(self)
