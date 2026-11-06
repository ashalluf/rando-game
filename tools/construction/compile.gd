extends SceneTree
## Compiles the building sites' scripts once the autoloads exist and prints any error (seconds):
##   godot --headless --path . --script tools/construction/compile.gd

const SCRIPTS := ["res://scripts/world/construction_kit.gd", "res://scripts/world/construction.gd",
	"res://scripts/npc/hard_hat.gd", "res://scripts/npc/construction_worker.gd", "res://scripts/world/city_chunk.gd"]

func _initialize() -> void:
	await process_frame
	for p: String in SCRIPTS:
		var s: Script = load(p)
		print("COMPILE %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAILED"])
	quit()
