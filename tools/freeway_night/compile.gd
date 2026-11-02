extends Node
## Compiles FreewayNight, the kit and the refcam shot with the autoloads present, and prints the
## light standards' heads round the freeway_night camera (seconds):
##   godot --headless --path . tools/freeway_night/compile.tscn
func _ready() -> void:
	for p in ["res://scripts/world/freeway_night.gd", "res://scripts/world/freeway_kit.gd", "res://tools/refcams/refcams_shot.gd"]:
		var s: Script = load(p)
		print("COMPILE %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAILED"])
	var macro := MacroMap.new()
	macro.seed = 1337
	macro.setup()
	var plan := CityPlan.new()
	plan.seed = 1337
	plan.macro = macro
	var heads: Array = FreewayNight.heads_near(plan, Vector2(1795.8, 1092.3), 240.0)
	print("HEADS ", heads.size())
	for h: Dictionary in heads.slice(0, 8):
		print("  ", h)
	get_tree().quit()
