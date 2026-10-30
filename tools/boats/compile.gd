extends SceneTree
## Compiles the boats' scripts once the autoloads exist and prints any error (seconds):
##   godot --headless --path . --script tools/boats/compile.gd

const SCRIPTS := ["res://scripts/vehicles/boat_kit.gd", "res://scripts/vehicles/boat.gd",
	"res://scripts/vehicles/boat_wake.gd", "res://scripts/vehicles/boat_ride_pose.gd",
	"res://scripts/vehicles/boat_moorings.gd", "res://scripts/world/marina_build.gd"]

func _initialize() -> void:
	await process_frame
	for p: String in SCRIPTS:
		var s: Script = load(p)
		print("COMPILE %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAILED"])
	for k in 2:
		for lv in 3:
			print("TRIS kind %d level %d: %d" % [k, lv, BoatKit.triangles(k, lv)])
	quit()
