extends SceneTree
## Runs tests/freight_checks.gd alone against the city (a few minutes, headless), for the loop:
##   godot --headless --path . --script tools/freight/checks.gd
var fails := 0


func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	for i in 10:
		await process_frame
	var city: Node3D = current_scene
	var host := Node.new()
	host.set_script(load("res://tools/freight/check_host.gd"))
	root.add_child(host)
	await process_frame
	await load("res://tests/freight_checks.gd").new().run(host, city)
	print("FREIGHT CHECKS done, %d failed" % host.fails)
	quit()
