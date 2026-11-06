extends Node
## Runs tests/traffic_ai_checks.gd alone against the city (a few minutes, headless), for the loop:
##   godot --headless --path . res://tools/traffic_ai/checks.tscn
var fails := 0


func _ready() -> void:
	var city: Node3D = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(city)
	for i in 30:
		await get_tree().physics_frame
	for n in ["Police", "Emergency"]:
		var node := city.get_node_or_null(n)
		if node:
			node.set("enabled", false)
	await load("res://tests/traffic_ai_checks.gd").new().run(self, city)
	print("TRAFFIC AI CHECKS done, %d failed" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails += 1
