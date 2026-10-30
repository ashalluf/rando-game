extends SceneTree
## Compiles the light rail's scripts once the autoloads exist and prints any error (seconds):
##   godot --headless --path . --script tools/light_rail/compile.gd

const SCRIPTS := ["res://scripts/world/light_rail.gd", "res://scripts/world/light_rail_kit.gd",
	"res://scripts/world/rail_gate.gd", "res://scripts/world/city_chunk.gd",
	"res://scripts/world/light_rail_system.gd", "res://scripts/vehicles/light_rail_train.gd",
	"res://scripts/npc/traffic.gd", "res://scripts/world/city_streamer.gd", "res://scripts/npc/rail_rider.gd"]

func _initialize() -> void:
	await process_frame
	for p: String in SCRIPTS:
		if not ResourceLoader.exists(p):
			continue
		var s: Script = load(p)
		print("COMPILE %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAILED"])
	quit()
