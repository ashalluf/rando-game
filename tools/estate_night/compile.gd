extends SceneTree
## Compiles the far estates' scripts once the autoloads exist and prints any error (seconds):
##   godot --headless --path . --script tools/estate_night/compile.gd

const SCRIPTS := ["res://scripts/world/estate_far.gd", "res://scripts/world/skyline.gd", "res://scripts/world/city_chunk.gd", "res://scripts/world/city_streamer.gd", "res://tests/estate_night_checks.gd"]

func _initialize() -> void:
	await process_frame
	for p: String in SCRIPTS:
		if not ResourceLoader.exists(p):
			continue
		var s: Script = load(p)
		print("COMPILE %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAILED"])
	quit()
