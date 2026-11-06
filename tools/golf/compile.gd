extends SceneTree
## Compiles the golf course's scripts once the autoloads exist and prints any error (seconds):
##   godot --headless --path . --script tools/golf/compile.gd

const SCRIPTS := ["res://scripts/world/golf_course.gd", "res://scripts/world/golf_build.gd",
	"res://scripts/world/golf_life.gd", "res://scripts/world/golf_far.gd", "res://scripts/npc/golfer.gd",
	"res://scripts/world/city_chunk.gd", "res://scripts/world/landmarks.gd", "res://scripts/world/skyline.gd"]

func _initialize() -> void:
	await process_frame
	for p: String in SCRIPTS:
		if not ResourceLoader.exists(p):
			continue
		var s: Script = load(p)
		print("COMPILE %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAILED"])
	quit()
