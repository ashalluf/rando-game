extends SceneTree
## Compiles the night life's scripts once the autoloads exist and prints any error (seconds):
##   godot --headless --path . --script tools/nightlife/compile.gd

const SCRIPTS := ["res://scripts/world/nightlife.gd", "res://scripts/world/nightlife_kit.gd", "res://scripts/world/sky_beam.gd",
	"res://scripts/npc/night_goer.gd", "res://scripts/npc/night_pickups.gd", "res://scripts/world/city_chunk.gd",
	"res://scripts/world/building.gd", "res://scripts/ui/loading_screen.gd", "res://tests/nightlife_checks.gd"]

func _initialize() -> void:
	await process_frame
	for p: String in SCRIPTS:
		if not ResourceLoader.exists(p):
			continue
		var s: Script = load(p)
		print("COMPILE %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAILED"])
	quit()
