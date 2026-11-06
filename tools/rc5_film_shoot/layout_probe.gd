extends SceneTree
## Prints the first shoot's layout (seed 1337): lo / hi, camp side, every set piece in world x, z.
##   godot --headless --path . --script tools/rc5_film_shoot/layout_probe.gd

func _initialize() -> void:
	await process_frame
	load("res://tools/rc5_film_shoot/layout_probe_run.gd").new().call("run")
	quit()
