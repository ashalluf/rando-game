extends Node
## Runs tests/oil_field_checks.gd alone against the real city scene (headless, a minute or two,
## instead of the whole smoke test): godot --headless --path . res://tools/oil_field/check_runner.tscn
var passed := 0
var failed := 0


func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		print("FAIL ", label)


func _ready() -> void:
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	add_child(city)
	for i in 10:
		await get_tree().process_frame
	await load("res://tests/oil_field_checks.gd").new().run(self, city)
	print("OIL CHECKS: %d passed, %d failed" % [passed, failed])
	get_tree().quit()
