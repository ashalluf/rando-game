extends SceneTree
## Compiles the car panic's scripts and the files it hooks into once the autoloads exist and
## prints any error (seconds):  godot --headless --path . --script tools/car_panic/compile.gd

const SCRIPTS := ["res://scripts/npc/car_panic.gd", "res://scripts/npc/panic_car.gd",
	"res://scripts/npc/traffic.gd", "res://scripts/npc/pedestrian.gd", "res://scripts/vehicles/vehicle.gd",
	"res://scripts/player/player.gd", "res://tests/car_panic_checks.gd"]

func _initialize() -> void:
	await process_frame
	for p: String in SCRIPTS:
		if not ResourceLoader.exists(p):
			continue
		var s: Script = load(p)
		print("COMPILE %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAILED"])
	quit()
