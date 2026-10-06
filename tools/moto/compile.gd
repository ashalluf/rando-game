extends SceneTree
## Compiles the motorcycles' scripts and the files they hook into once the autoloads exist, and
## prints any error (seconds):  godot --headless --path . --script tools/moto/compile.gd

const SCRIPTS := ["res://scripts/vehicles/motorcycle.gd", "res://scripts/vehicles/ride_solver.gd",
	"res://scripts/npc/moto_rider.gd", "res://scripts/npc/moto_helmet.gd", "res://scripts/player/hero_ride.gd",
	"res://scripts/player/moto_throw.gd", "res://scripts/npc/traffic.gd", "res://scripts/world/city_chunk.gd",
	"res://scripts/player/player.gd", "res://scripts/world/city_streamer.gd", "res://scripts/ui/warm_rehearsal.gd"]


func _initialize() -> void:
	await process_frame
	for p: String in SCRIPTS:
		var s: Script = load(p)
		print("COMPILE %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAILED"])
	quit()
