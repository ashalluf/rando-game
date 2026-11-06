extends SceneTree
## Compiles the street sounds' scripts once the autoloads exist and prints any error (seconds):
##   godot --headless --path . --script tools/street_sounds/compile.gd

const SCRIPTS := ["res://scripts/util/street_sounds.gd", "res://scripts/util/ambience.gd",
	"res://scripts/util/sfx.gd", "res://scripts/npc/street_errands.gd", "res://scripts/npc/errand_car.gd"]

func _initialize() -> void:
	await process_frame
	for p: String in SCRIPTS:
		var s: Script = load(p)
		print("COMPILE %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAILED"])
	quit()
