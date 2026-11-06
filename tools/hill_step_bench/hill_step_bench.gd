extends Node
## Times every build step of the FULL hill chunks in a region, the way CityStreamer runs them
## (one step at a time), and reports what the hill shells built. Headless is fine (no render):
##   REGION=x0,z0,x1,z1 godot --headless --path . res://tools/hill_step_bench/hill_step_bench.tscn
## REGION defaults to a patch of the front range round the hills stills (-700,-1500,300,-900).
## Prints one STEP line per step (worst and mean ms over the chunks, by step name) and a SHELLS
## line per chunk (tile quads, layers, vertices, triangles at each LOD). The streamer's frame
## budget is CityStreamer.build_budget_ms (4 ms): a step over it is a hitch. The first chunk's
## worst is printed apart: it loads the models, materials and shaders the rest reuse.

func _ready() -> void:
	await get_tree().process_frame
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var plan := CityPlan.new()
	plan.seed = city.world_seed
	plan.block_size_range = city.block_size_range
	plan.street_width = city.street_width
	plan.avenue_width = city.avenue_width
	plan.sidewalk_width = city.sidewalk_width
	plan.downtown_radius = city.downtown_radius
	plan.midtown_radius = city.midtown_radius
	plan.macro = MacroMap.new()
	plan.macro.seed = city.world_seed
	var t_setup := Time.get_ticks_msec()
	plan.macro.setup()
	print("macro setup %d ms" % (Time.get_ticks_msec() - t_setup))
	var style: Dictionary = city.chunk_style()
	var r := OS.get_environment("REGION")
	var reg := [-700.0, -1500.0, 300.0, -900.0]
	if r != "":
		var parts := r.split(",")
		for i in 4:
			reg[i] = parts[i].to_float()
	var k0: Vector2i = plan.block_index_at(Vector2(reg[0], reg[1]))
	var k1: Vector2i = plan.block_index_at(Vector2(reg[2], reg[3]))
	var chunk_script: GDScript = load("res://scripts/world/city_chunk.gd")
	var stats := {}
	var order: Array[String] = []
	var chunks := 0
	for bz in range(k0.y, k1.y + 1):
		for bx in range(k0.x, k1.x + 1):
			var b := plan.block(bx, bz)
			if plan.zone_at((b.rect as Rect2).get_center()) != MacroMap.Zone.HILLS:
				continue
			var ch = chunk_script.new()
			ch.plan = plan
			ch.ix = bx
			ch.iz = bz
			ch.level = 0
			ch.style = style
			ch.begin_build()
			var runs := {}
			while true:
				var i: int = ch._step
				if i >= ch._steps.size():
					break
				var c: Callable = ch._steps[i]
				var name := "%02d %s" % [i, c.get_method()]
				var t0 := Time.get_ticks_usec()
				var done: bool = ch.build_step()
				var ms := (Time.get_ticks_usec() - t0) / 1000.0
				if not stats.has(name):
					stats[name] = {"worst": 0.0, "first": 0.0, "sum": 0.0, "n": 0, "calls": 0}
					order.append(name)
				var s: Dictionary = stats[name]
				# The first chunk loads the models, materials and shaders every later one reuses.
				if chunks == 0:
					s.first = maxf(s.first, ms)
				else:
					s.worst = maxf(s.worst, ms)
				s.sum += ms
				s.calls += 1
				runs[name] = true
				if done:
					break
			for name in runs:
				stats[name].n += 1
			chunks += 1
			var node: MultiMeshInstance3D = ch.get("hill_shell_node")
			var tile: Mesh = ch.get("_terrain_mesh")
			if node:
				var tris := 0
				if tile:
					var arr := tile.surface_get_arrays(0)
					if arr.size() > 0 and arr[Mesh.ARRAY_INDEX] != null:
						tris = PackedInt32Array(arr[Mesh.ARRAY_INDEX]).size() / 3
				print("SHELLS block %d,%d: tile n=%d, %d triangles, %d layers -> %d triangles close up" % [bx, bz, ch._terrain_grid.n, tris, node.multimesh.instance_count, tris * node.multimesh.instance_count])
			else:
				print("SHELLS block %d,%d: none" % [bx, bz])
			ch.free()
	print("chunks %d" % chunks)
	for name in order:
		var s: Dictionary = stats[name]
		print("STEP %-34s worst %6.2f ms  mean %6.2f ms/call  calls/chunk %.1f  (first chunk %.1f ms)" % [name, s.worst, s.sum / maxf(s.calls, 1), float(s.calls) / maxf(s.n, 1), s.first])
	city.free()
	get_tree().quit()
