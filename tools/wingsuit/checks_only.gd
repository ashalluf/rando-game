extends Node
## Runs tests/wingsuit_checks.gd alone in the test room (seconds; no city):
##   godot --headless --path . tools/wingsuit/checks_only.tscn

var passed := 0
var failed := 0


func _ready() -> void:
	var level: Node = load("res://scenes/levels/test_box.tscn").instantiate()
	get_tree().root.add_child.call_deferred(level)
	for i in 40:
		await get_tree().physics_frame
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	await load("res://tests/wingsuit_checks.gd").new().run(self, player)
	print("WINGSUIT CHECKS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("  PASS  ", what)
	else:
		failed += 1
		print("  FAIL  ", what)
