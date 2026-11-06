extends SceneTree
## Compiles the airport's ground scripts once the autoloads exist and prints any error (seconds):
##   godot --headless --path . --script tools/airport_life/compile.gd

const SCRIPTS := ["res://scripts/world/air_route.gd", "res://scripts/world/airport_ground.gd",
	"res://scripts/world/apron_kit.gd", "res://scripts/world/jet_bridge.gd",
	"res://scripts/vehicles/ambient_jet.gd", "res://scripts/world/air_traffic.gd",
	"res://scripts/world/airport.gd", "res://scripts/world/airport_terminal.gd",
	"res://scripts/world/city_chunk.gd", "res://scripts/world/city_streamer.gd"]

func _initialize() -> void:
	await process_frame
	for p: String in SCRIPTS:
		var s: Script = load(p)
		print("COMPILE %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAILED"])
	quit()
