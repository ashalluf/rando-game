extends Node
## Times the historic core's build steps: builds FULL chunks of the historic blocks headless and
## prints every ornament step over 1 ms (HISTORIC_TIME=1 is set for it) and the worst.
##   godot --headless --path . tools/historic/steps.tscn [-- --blocks=bx,bz;bx,bz]

func _ready() -> void:
	OS.set_environment("HISTORIC_TIME", "1")
	HistoricCore.time_steps = true
	var m := MacroMap.new()
	m.seed = 1337
	m.setup()
	var plan := CityPlan.new()
	plan.seed = 1337
	plan.macro = m
	var blocks: Array[Vector2i] = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--blocks="):
			for s in a.substr(9).split(";"):
				var v := s.split(",")
				blocks.append(Vector2i(int(v[0]), int(v[1])))
	if blocks.is_empty():
		var zr := HistoricCore.z_range()
		for name: String in HistoricCore.AVENUES:
			var av := HistoricCore.avenue(name)
			var z := zr.x + 5.0
			while z < zr.y:
				for side: float in [-1.0, 1.0]:
					var bi := plan.block_index_at(Vector2(float(av[0]) + side * 30.0, z))
					if not blocks.has(bi) and not HistoricCore.block_fronts(plan, bi.x, bi.y).is_empty():
						blocks.append(bi)
				z += 40.0
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var style: Dictionary = city.chunk_style()
	var worst_chunk_step := 0
	for k in blocks:
		var ch := CityChunk.new()
		ch.plan = plan
		ch.ix = k.x
		ch.iz = k.y
		ch.level = CityChunk.Level.FULL
		ch.style = style
		add_child(ch)
		var t0 := Time.get_ticks_usec()
		ch.build()
		print("BLOCK %s built in %.0f ms, historic worst so far %.1f ms" % [k, float(Time.get_ticks_usec() - t0) / 1000.0, float(HistoricCore.max_step_us) / 1000.0])
		remove_child(ch)
		ch.free()
	print("HISTORIC %d buildings, %d surfaces, %d triangles" % [HistoricFacade.built_count, LandmarkGeo.committed_surfaces, LandmarkGeo.committed_triangles])
	print("HISTORIC worst step %.2f ms (%s) over %d blocks" % [float(HistoricCore.max_step_us) / 1000.0, HistoricCore.max_step_label, blocks.size()])
	# The box's own noise: the same 1 ms of arithmetic 3000 times, its longest run.
	var noise := 0
	for k in 3000:
		var t0 := Time.get_ticks_usec()
		var x := 0.0
		for j in 6000:
			x += sin(float(j))
		noise = maxi(noise, Time.get_ticks_usec() - t0)
	print("NOISE longest 1 ms job %.2f ms" % (float(noise) / 1000.0))
	city.free()
	get_tree().quit()
