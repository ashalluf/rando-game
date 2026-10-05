extends SceneTree
## Compiles the apartment kit's scripts once the autoloads exist and prints any error (seconds):
##   godot --headless --path . --script tools/apartments/compile.gd

const SCRIPTS := ["res://scripts/world/apartments.gd", "res://scripts/world/apartment_build.gd", "res://scripts/world/house_kit.gd",
	"res://scripts/world/house_build.gd", "res://scripts/world/city_chunk.gd", "res://scripts/world/ground_coverage.gd"]

func _initialize() -> void:
	await process_frame
	for p: String in SCRIPTS:
		if not ResourceLoader.exists(p):
			continue
		var s: Script = load(p)
		print("COMPILE %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAILED"])
	quit()
