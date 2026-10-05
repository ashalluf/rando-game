extends Node
## Runs tests/hill_homes_checks.gd alone against the city scene (a few minutes, not the whole
## smoke test): godot --headless --path . res://tools/hill_homes/check_runner.tscn
var passed := 0
var failed := 0


func _ready() -> void:
	await get_tree().process_frame
	var city: Node3D = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(city)
	for n in ["Police", "Emergency"]:
		var node := city.get_node_or_null(n)
		if node:
			node.set("enabled", false)
	for i in 30:
		await get_tree().physics_frame
	await load("res://tests/hill_homes_checks.gd").new().run(self, city)
	print("CHECKS passed %d failed %d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		print("FAIL ", label)
