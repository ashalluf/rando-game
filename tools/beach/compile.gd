extends SceneTree
## Compiles the beach's scripts once the autoloads exist and prints any error (seconds):
##   godot --headless --path . --script tools/beach/compile.gd

const SCRIPTS := ["res://scripts/world/beach_life.gd", "res://scripts/world/beach_figure.gd",
	"res://scripts/world/beach_activity.gd", "res://scripts/npc/beach_goer.gd",
	"res://scripts/npc/beach_rider.gd", "res://scripts/npc/beach_walker.gd",
	"res://scripts/world/city_chunk.gd", "res://scripts/ui/loading_screen.gd"]

func _initialize() -> void:
	await process_frame
	for p: String in SCRIPTS:
		var s: Script = load(p)
		print("COMPILE %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAILED"])
	quit()
