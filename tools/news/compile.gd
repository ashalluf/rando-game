extends SceneTree
## Compiles the news crews' scripts once the autoloads exist and prints any error (seconds):
##   godot --headless --path . --script tools/news/compile.gd

const SCRIPTS := ["res://scripts/world/news_kit.gd", "res://scripts/vehicles/news_van.gd",
	"res://scripts/npc/news_crew.gd", "res://scripts/npc/news_crews.gd", "res://tests/news_crews_checks.gd"]

func _initialize() -> void:
	await process_frame
	for p: String in SCRIPTS:
		if not ResourceLoader.exists(p):
			continue
		var s: Script = load(p)
		print("COMPILE %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAILED"])
	quit()
