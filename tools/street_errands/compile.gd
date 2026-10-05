extends SceneTree
## Compiles StreetErrands' scripts and the files it hooks into once the autoloads exist and prints
## any error (seconds):
##   godot --headless --path . --script tools/street_errands/compile.gd

const SCRIPTS := ["res://scripts/npc/street_errands.gd", "res://scripts/npc/errand_car.gd",
	"res://scripts/npc/errand_props.gd", "res://scripts/npc/pedestrian.gd", "res://scripts/npc/traffic.gd",
	"res://scripts/world/building.gd", "res://scripts/vehicles/big_vehicles.gd", "res://scripts/world/city_chunk.gd", "res://tests/street_errands_checks.gd",
	"res://tools/street_errands/stage.gd", "res://tools/glshot/still_shot.gd"]

func _initialize() -> void:
	await process_frame
	for p: String in SCRIPTS:
		var s: Script = load(p)
		print("COMPILE %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAILED"])
	quit()
