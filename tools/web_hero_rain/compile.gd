extends SceneTree
## Compiles the web-hero-rain tools in seconds (a parse error in one only shows when the browser
## loads it): godot --headless --path . --script tools/web_hero_rain/compile.gd

func _initialize() -> void:
	var bad := 0
	for p in ["res://tools/web_hero_rain/hero_probe.gd", "res://tools/web_hero_rain/hero_rain.gd"]:
		var s := load(p) as GDScript
		if s == null or not s.can_instantiate():
			print("COMPILE FAIL ", p)
			bad += 1
		else:
			print("COMPILE OK ", p)
	quit(1 if bad > 0 else 0)
