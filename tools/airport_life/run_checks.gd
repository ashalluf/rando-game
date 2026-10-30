extends SceneTree
## Runs tests/airport_life_checks.gd on its own (the city, the player at the airport), in a
## minute or two instead of the whole smoke test:
##   godot --headless --path . --script tools/airport_life/run_checks.gd

class Checker extends Node:
	var passed := 0
	var failed := 0

	func _check(ok: bool, label: String) -> void:
		printerr("%s %s" % ["PASS" if ok else "FAIL", label])
		if ok:
			passed += 1
		else:
			failed += 1


func _initialize() -> void:
	await process_frame
	var city: Node3D = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	root.add_child(city)
	current_scene = city
	for i in 30:
		await process_frame
	var checker := Checker.new()
	root.add_child(checker)
	await load("res://tests/airport_life_checks.gd").new().run(checker, city)
	printerr("AIRPORT LIFE: %d passed, %d failed" % [checker.passed, checker.failed])
	quit()
