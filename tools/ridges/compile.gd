extends SceneTree
## Compiles the ridges' scripts in seconds (a parse error prints SCRIPT ERROR):
##   godot --headless --path . --script tools/ridges/compile.gd
func _initialize() -> void:
	for p in ["res://scripts/world/ridges.gd", "res://scripts/world/ridge_kit.gd", "res://scripts/world/ridge_build.gd",
			"res://scripts/world/ridge_system.gd", "res://scripts/world/ridge_cover.gd", "res://tests/ridges_checks.gd"]:
		var s := load(p) as Script
		print("COMPILE ", p, " ", s != null and s.can_instantiate())
	quit()
