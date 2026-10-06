extends SceneTree
## Drives the player across the city in a straight line and prints the live chunk set, so a
## change to CityStreamer can be checked without a renderer and without the owner's eyes.
##
##   STEP=25 godot --headless --path . --script tools/stream_probe.gd
##
## STEP is metres per streaming tick; update_interval is 0.25 s, so 8 m is about 115 km/h and
## 25 m about 360 km/h. What to look for:
##   - `chunks` STABILISES. If it climbs every step, chunks are leaking.
##   - `full` never reaches 0. min_full_radius_blocks guarantees the ground under the player,
##     and it is the last thing standing between a fast flight and a hole in the world.
## At absurd speeds (STEP 120, ~1700 km/h) the set thins to what the per-tick build budget can
## carry - that is the budget, not a leak, and `full` still holds at the min radius.
##
## Untyped on purpose: this script is compiled before the autoloads exist, so naming
## CityStreamer or CityChunk as a type here fails to load, exactly as in tests/smoke_test.gd.
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	await process_frame
	await process_frame
	var city = get_root().get_child(get_root().get_child_count() - 1)
	var player = get_first_node_in_group("player")
	if city == null or player == null:
		print("PROBE: no city or player"); quit(); return
	var step_m := 25.0
	var env := OS.get_environment("STEP")
	if env != "":
		step_m = float(env)
	for step in 40:
		player.global_position += Vector3(step_m, 0.0, 0.0)
		player.set("velocity", Vector3(step_m / 0.25, 0.0, 0.0))
		city.update_streaming(false)
		await process_frame
		if step % 8 == 0 or step == 39:
			var counts = city.chunk_counts()
			print("step %2d  chunks %4d  full %3d  lod %4d  objects %6d" % [
				step, city.chunks.size(), counts.x, counts.y,
				Performance.get_monitor(Performance.OBJECT_COUNT)])
	quit()
