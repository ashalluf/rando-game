extends Node
## Times the FULL hill chunks that hold estates, step by step, with the hill homes on and off:
##   godot --headless --path . res://tools/hill_homes/bench.tscn   (N= chunks, default 12)
## Prints per chunk the estates, the slowest step and the total, and the means.

func _ready() -> void:
	await get_tree().process_frame
	var city: Node3D = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(city)
	for n in ["Police", "Emergency"]:
		var node := city.get_node_or_null(n)
		if node:
			node.set("enabled", false)
	for i in 10:
		await get_tree().physics_frame
	var plan: CityPlan = city.plan
	var want := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 12
	var keys: Array[Vector2i] = []
	var seen := {}
	for m: Dictionary in plan.macro.hill_roads.mansions:
		var k: Vector2i = plan.block_index_at(m.pos)
		if seen.has(k):
			continue
		seen[k] = true
		keys.append(k)
	keys = keys.slice(0, keys.size(), maxi(1, keys.size() / want))
	var kit: GDScript = load("res://scripts/world/hill_home_kit.gd")
	for on: bool in [false, true]:
		kit.set("enabled", on)
		var tot := 0.0
		var worst := 0.0
		for k in keys:
			var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
			chunk.begin_build()
			var mx := 0.0
			var sum := 0.0
			var done := false
			while not done:
				var t0 := Time.get_ticks_usec()
				done = chunk.build_step()
				var ms := (Time.get_ticks_usec() - t0) / 1000.0
				mx = maxf(mx, ms)
				sum += ms
			var n := plan.macro.hill_roads.mansions_in(chunk.owned_rect()).size()
			print("BENCH %s %s estates %d worst step %.1f ms total %.1f ms" % ["on " if on else "off", k, n, mx, sum])
			tot += sum
			worst = maxf(worst, mx)
			chunk.get_parent().remove_child(chunk)
			chunk.free()
		print("BENCH %s: %d chunks, mean total %.1f ms, worst step %.1f ms" % ["ON" if on else "OFF", keys.size(), tot / keys.size(), worst])
	get_tree().quit()
