extends SceneTree
## Runs tests/road_detail_checks.gd alone against the city (a minute, headless), for the loop:
##   godot --headless --path . --script tools/road_detail/checks.gd
var fails := 0

func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	for i in 10:
		await process_frame
	var city: Node3D = current_scene
	load("res://tests/road_detail_checks.gd").new().run(self, city)
	print("ROAD DETAIL CHECKS done, %d failed" % fails)
	quit()


func _check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails += 1
