extends SceneTree
## Compiles the stack interchange's scripts once the autoloads exist and prints any error (seconds):
##   godot --headless --path . --script tools/stack/compile.gd

const SCRIPTS := ["res://scripts/world/freeway_stack.gd", "res://scripts/world/stack_build.gd",
	"res://scripts/world/freeway.gd", "res://scripts/world/freeway_kit.gd", "res://scripts/world/skyline.gd",
	"res://scripts/world/city_chunk.gd", "res://scripts/npc/traffic.gd", "res://scripts/world/city_streamer.gd", "res://scripts/npc/stack_traffic.gd"]

func _initialize() -> void:
	await process_frame
	for p: String in SCRIPTS:
		if not ResourceLoader.exists(p):
			continue
		var s: Script = load(p)
		print("COMPILE %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAILED"])
	quit()
