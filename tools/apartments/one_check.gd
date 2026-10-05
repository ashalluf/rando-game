extends Node
## Runs ONE tests/*_checks.gd against the city, the way tests/smoke_test.gd sets it up (police and
## emergency services off), for an A/B of a single suite without the 30-minute gate:
##   CHECK=res://tests/emergency_checks.gd [APARTMENTS=0] godot --headless --path . res://tools/apartments/one_check.tscn

var passed := 0
var failed := 0


func _check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("PASS ", what)
	else:
		failed += 1
		print("FAIL ", what)


func _ready() -> void:
	await get_tree().process_frame
	var city: Node3D = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(city)
	for n in ["Police", "Emergency"]:
		var node: Node = city.get_node_or_null(n)
		if node:
			node.set("enabled", false)
	for i in 30:
		await get_tree().physics_frame
	var suite: Variant = load(OS.get_environment("CHECK")).new().run(self, city)
	if suite is Object:
		pass
	await suite
	print("ONE_CHECK passed %d failed %d" % [passed, failed])
	get_tree().quit()
