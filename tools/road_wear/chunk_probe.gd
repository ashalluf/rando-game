extends SceneTree
## Builds FULL chunks round a point and prints their road wear (count, stamps by kind, deep
## potholes indexed, build time). Headless, a minute:
##   godot --headless --path . --script tools/road_wear/chunk_probe.gd -- --spawn=x,z,0,0
## N=blocks either way (default 1). ROAD_WEAR=0 for the before.
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var c := Vector2.ZERO
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
	for i in 8:
		await process_frame
	var city = current_scene
	var plan = city.get("plan")
	var rw: GDScript = load("res://scripts/world/road_wear.gd")
	var n := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 1
	var k0: Vector2i = plan.block_index_at(c)
	var names := ["DOWNTOWN", "MIDTOWN", "SUBURBS", "INDUSTRIAL", "CAMPUS", "BEACHTOWN"]
	for dz in range(-n, n + 1):
		for dx in range(-n, n + 1):
			var k := k0 + Vector2i(dx, dz)
			var chunk = city.call("_new_chunk", k, 0)
			var t0 := Time.get_ticks_usec()
			chunk.call("build")
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			var d := int(plan.block(k.x, k.y).district)
			print("CHUNK %d,%d %s wear=%d build=%.0fms lvlX=%.2f lvlZ=%.2f kinds=%s" % [k.x, k.y, names[d], int(chunk.get_meta("road_wear_count", 0)), ms,
				rw.call("road_level", plan, 0, k.x + 1, d), rw.call("road_level", plan, 1, k.y + 1, d), str(chunk.get_meta("road_wear_kinds", {}))])
			chunk.queue_free()
	print("BUMPS ", rw.call("bump_total"), " VARIANTS ", rw.call("variant_count"))
	quit()
