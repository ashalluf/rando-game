extends Node
## Runs tests/roadside_checks.gd alone against the city (a few minutes, headless), for the loop:
##   godot --headless --path . res://tools/roadside/checks.tscn
## (a scene, not --script: the checks take a Node and name CityChunk, which needs the autoloads.)
var fails := 0


func _ready() -> void:
	var city: Node3D = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	add_child(city)
	for i in 10:
		await get_tree().process_frame
	load("res://tests/roadside_checks.gd").new().run(self, city)
	print("ROADSIDE CHECKS done, %d failed" % fails)
	get_tree().quit()


func _check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails += 1
