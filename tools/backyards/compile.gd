extends SceneTree
## Compiles Backyards and BackyardKit (and YardFill, which calls them) headless, in seconds.
##   godot --headless --path . --script tools/backyards/compile.gd
func _initialize() -> void:
	for p in ["res://scripts/world/backyard_kit.gd", "res://scripts/world/backyards.gd", "res://scripts/world/yard_fill.gd"]:
		var s: GDScript = load(p)
		print("COMPILE ", p, " ", s != null and s.can_instantiate())
	quit()
