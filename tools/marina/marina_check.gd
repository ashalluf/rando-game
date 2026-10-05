extends Node
## Runs tests/marina_checks.gd alone against a loaded city (a minute or two, not the whole smoke
## test):  godot --headless --path . tools/marina/marina_check.tscn
var failed := 0


func _ready() -> void:
	var city: Node3D = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(city)
	await get_tree().process_frame
	await get_tree().process_frame
	load("res://tests/marina_checks.gd").new().run(self, city)
	print("MARINA CHECKS: %d failed" % failed)
	get_tree().quit(1 if failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failed += 1
