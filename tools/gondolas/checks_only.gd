extends SceneTree
## Runs tests/tower_gondolas_checks.gd alone, headless, in under a minute:
##   godot --headless --path . --script tools/gondolas/checks_only.gd

class Checker:
	extends Node
	var passed := 0
	var failed := 0

	func _check(ok: bool, msg: String) -> void:
		if ok:
			passed += 1
			print("PASS ", msg)
		else:
			failed += 1
			print("FAIL ", msg)


func _initialize() -> void:
	await process_frame
	var c := Checker.new()
	root.add_child(c)
	var city := Node3D.new()
	city.name = "City"
	root.add_child(city)
	await physics_frame
	load("res://tests/tower_gondolas_checks.gd").new().run(c, city)
	print("CHECKS passed=%d failed=%d" % [c.passed, c.failed])
	quit(1 if c.failed > 0 else 0)
