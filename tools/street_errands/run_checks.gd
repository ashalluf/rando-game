extends Node
## Runs tests/street_errands_checks.gd alone in the city (a minute or two, against the whole
## smoke test's quarter of an hour): the scene tools/street_errands/run_checks.tscn,
##   godot --headless --path . res://tools/street_errands/run_checks.tscn

var _checks := 0
var _fails: Array[String] = []
var _traffic: Node
var _checker: RefCounted
var _said := false


func _physics_process(_delta: float) -> void:
	if _traffic == null or _said:
		return
	for c in _traffic.get("cars"):
		if not is_instance_valid(c):
			print("DEBUG: a freed car is still in the traffic's list, after check %d" % _checks)
			_said = true
			return


func _ready() -> void:
	await get_tree().process_frame
	var city: Node3D = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(city)
	for n: String in ["Police", "Emergency"]:
		var node := city.get_node_or_null(n)
		if node:
			node.set("enabled", false)
	for i in 30:
		await get_tree().physics_frame
	_traffic = city.get_node("Traffic")
	_checker = load("res://tests/street_errands_checks.gd").new()
	await _checker.run(self, city)
	print("ERRAND CHECKS %d, %d failed" % [_checks, _fails.size()])
	for f in _fails:
		print("FAILED: ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	printerr("%s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fails.append(label)
