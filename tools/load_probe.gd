extends SceneTree
## How long the city takes to load, headless (the dummy renderer, so the CPU side: the plan, the
## far city, the first chunks, the warm-ups) - from the scene entering the tree until the loading
## screen frees itself, and how many frames that took.
##
##   godot --headless --path . --audio-driver Dummy --script tools/load_probe.gd -- --spawn=x,z
func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	root.add_child((load("res://scenes/levels/city.tscn") as PackedScene).instantiate())
	var frames := 0
	var seen := false
	while frames < 20000:
		await process_frame
		frames += 1
		var screen := root.find_child("LoadingScreen", true, false)
		if screen != null:
			seen = true
		elif seen or frames > 5:
			break
	print("LOAD %d ms, %d frames (loading screen seen: %s)" % [Time.get_ticks_msec() - t0, frames, seen])
	quit()
