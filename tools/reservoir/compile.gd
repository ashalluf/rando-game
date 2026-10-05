extends SceneTree
## Compiles the reservoir's scripts and the shared ones it hooks into, once the autoloads exist,
## and prints any error (seconds):
##   godot --headless --path . --script tools/reservoir/compile.gd

const SCRIPTS := ["res://scripts/world/reservoir.gd", "res://scripts/world/landmark_reservoir.gd",
	"res://scripts/world/macro_map.gd", "res://scripts/world/landmarks.gd", "res://scripts/world/city_chunk.gd",
	"res://scripts/world/skyline.gd", "res://scripts/world/city_streamer.gd"]

func _initialize() -> void:
	await process_frame
	for p: String in SCRIPTS:
		var s: Script = load(p)
		print("COMPILE %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAILED"])
	quit()
