extends SceneTree
## Compiles PropBreak's scripts once the autoloads exist and prints any error (seconds):
##   godot --headless --path . --script tools/prop_break/compile.gd

const SCRIPTS := ["res://scripts/world/prop_break.gd", "res://scripts/world/prop_shards.gd",
	"res://scripts/world/hydrant_geyser.gd", "res://scripts/world/falling_pole.gd",
	"res://scripts/world/city_chunk.gd", "res://scripts/vehicles/vehicle.gd",
	"res://scripts/world/broadway_street.gd", "res://tests/prop_destruction_checks.gd"]

func _initialize() -> void:
	await process_frame
	for p: String in SCRIPTS:
		if not ResourceLoader.exists(p):
			continue
		var s: Script = load(p)
		print("COMPILE %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAILED"])
	quit()
