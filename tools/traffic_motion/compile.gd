extends SceneTree
## Compiles the traffic-motion scripts once the autoloads exist and prints any error (seconds):
##   godot --headless --path . --script tools/traffic_motion/compile.gd

const SCRIPTS := ["res://scripts/vehicles/traffic_motion.gd", "res://scripts/vehicles/vehicle.gd",
	"res://scripts/npc/traffic.gd", "res://scripts/npc/traffic_ai.gd", "res://tests/traffic_motion_checks.gd"]

func _initialize() -> void:
	await process_frame
	for p: String in SCRIPTS:
		if not ResourceLoader.exists(p):
			continue
		var s: Script = load(p)
		print("COMPILE %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAILED"])
	quit()
