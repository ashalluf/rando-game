extends SceneTree
## Compiles the crowd look's scripts once the autoloads exist. Headless, seconds:
##   godot --headless --path . --script tools/crowd_look/compile.gd

const SCRIPTS := ["res://scripts/npc/crowd_look.gd", "res://scripts/npc/pedestrian.gd",
	"res://scripts/vehicles/vehicle.gd", "res://scripts/player/landing_fx.gd", "res://tests/crowd_look_checks.gd"]

func _initialize() -> void:
	await process_frame
	for p: String in SCRIPTS:
		if not ResourceLoader.exists(p):
			continue
		var s: Script = load(p)
		print("COMPILE %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAILED"])
	quit()
