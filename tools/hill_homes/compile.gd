extends SceneTree
## Compiles the hill homes' scripts once the autoloads exist and prints any error (seconds):
##   godot --headless --path . --script tools/hill_homes/compile.gd

const SCRIPTS := ["res://scripts/world/hill_home_kit.gd", "res://scripts/world/hill_home_build.gd",
	"res://scripts/world/city_chunk.gd", "res://scripts/world/skyline.gd", "res://scripts/world/city_streamer.gd"]

func _initialize() -> void:
	await process_frame
	for p: String in SCRIPTS:
		var s: Script = load(p)
		print("COMPILE %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAILED"])
	quit()
