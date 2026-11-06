extends Node
## Runs tests/marina_checks.gd alone against a loaded city (a minute or two, not the whole smoke
## test):  godot --headless --path . tools/marina/marina_check.tscn   (CHECK=res://tests/<other>.gd runs another)
var failed := 0


func _ready() -> void:
	var city: Node3D = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(city)
	await get_tree().process_frame
	await get_tree().process_frame
	var path := OS.get_environment("CHECK") if OS.get_environment("CHECK") != "" else "res://tests/marina_checks.gd"
	await load(path).new().run(self, city)
	print("MARINA CHECKS: %d failed" % failed)
	get_tree().quit(1 if failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failed += 1
