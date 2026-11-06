extends Node
## Runs tests/building_damage_checks.gd alone against the city (a minute, not the smoke test's
## fifteen): godot --headless --path . res://tools/building_damage/run_checks.tscn
var passed := 0
var failed := 0


func _ready() -> void:
	var city: Node3D = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(city)
	for i in 30:
		await get_tree().physics_frame
	for n in ["Police", "Emergency"]:
		if city.get_node_or_null(n):
			city.get_node(n).set("enabled", false)
	await load("res://tests/building_damage_checks.gd").new().run(self, city)
	print("BUILDING DAMAGE CHECKS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if ok:
		passed += 1
	else:
		failed += 1
