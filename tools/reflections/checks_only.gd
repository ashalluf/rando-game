extends Node
## Runs tests/reflection_probes_checks.gd alone against the city scene (a minute or two instead of
## the whole smoke test):  godot --headless --path . res://tools/reflections/checks_only.tscn

var fails := 0


func _ready() -> void:
	await get_tree().process_frame
	var city: Node3D = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	for n in ["Police", "Emergency"]:
		if city.get_node_or_null(n):
			city.get_node(n).set("enabled", false)
	get_tree().root.add_child(city)
	for i in 30:
		await get_tree().process_frame
	await load("res://tests/reflection_probes_checks.gd").new().run(self, city)
	print("CHECKS_ONLY failures=%d" % fails)
	get_tree().quit()


func _check(ok: bool, label: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1
