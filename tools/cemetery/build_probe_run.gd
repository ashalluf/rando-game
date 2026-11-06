extends RefCounted
## The body of tools/cemetery/build_probe.gd.

func run(tree: SceneTree) -> void:
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
	plan.macro.setup()
	var style: Dictionary = city.chunk_style()
	var blocks: Array = []
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		var v := (args[0] as String).split(",")
		var pl := Cemetery.plan_for(plan, int(v[0]), int(v[1]))
		blocks = pl.blocks
	else:
		var d := {}
		for cx in range(-4, 5):
			for cz in range(-4, 5):
				d = Cemetery.decide(plan, Vector2i(cx, cz))
				if not d.is_empty():
					break
			if not d.is_empty():
				break
		blocks = d.blocks
	var pl := Cemetery.plan_for(plan, (blocks[0] as Vector2i).x, (blocks[0] as Vector2i).y)
	var tm := Time.get_ticks_usec()
	Cemetery._mask(pl)
	print("MASK %.1f ms" % ((Time.get_ticks_usec() - tm) / 1000.0))
	tm = Time.get_ticks_usec()
	Cemetery._monuments(pl)
	print("MONUMENTS %.1f ms" % ((Time.get_ticks_usec() - tm) / 1000.0))
	tm = Time.get_ticks_usec()
	for key: String in CemeteryKit.MESHES:
		CemeteryKit.mesh(key)
	print("KIT %.1f ms" % ((Time.get_ticks_usec() - tm) / 1000.0))
	tm = Time.get_ticks_usec()
	var gg := Cemetery.graves(pl, pl.site, 0, 1)
	print("GRAVES %d in %.1f ms" % [gg.size(), (Time.get_ticks_usec() - tm) / 1000.0])
	print("PARK '%s' blocks %s site %s mask %s monuments %d" % [pl.name, blocks, pl.site, pl.get("mask_n", "-"), Cemetery._monuments(pl).size()])
	var chunk_script: GDScript = load("res://scripts/world/city_chunk.gd")
	for level in [0, 1, 2]:
		var total_graves := 0
		for k: Vector2i in blocks:
			var ch = chunk_script.new()
			ch.plan = plan
			ch.ix = k.x
			ch.iz = k.y
			ch.level = 0 if level == 0 else 1
			ch.style = style
			if level == 2:
				ch.capturing = true
				ch.captured = {"ground": [], "boxes": []}
			tree.root.add_child(ch)
			var t0 := Time.get_ticks_usec()
			ch.begin_build()
			var worst := 0
			var n := 0
			while true:
				var s0 := Time.get_ticks_usec()
				var done: bool = ch.build_step()
				worst = maxi(worst, Time.get_ticks_usec() - s0)
				if Time.get_ticks_usec() - s0 > 40000:
					print("   slow step %d (%s): %.1f ms" % [n, (ch._steps[n] as Callable).get_method() if n < ch._steps.size() else "?", (Time.get_ticks_usec() - s0) / 1000.0])
				n += 1
				if done:
					break
			var lights := 0
			var zones := 0
			for c in ch.get_children():
				if c is OmniLight3D:
					lights += 1
				if c.is_in_group(Sanctuary.ZONE_GROUP):
					zones += 1
			var keys := []
			for c in ch.get_children():
				if c is MultiMeshInstance3D and String(c.name).contains("cem_"):
					keys.append("%s:%d" % [String(c.name).replace("Batch_", ""), (c as MultiMeshInstance3D).multimesh.instance_count])
					if not String(c.name).contains("Shadow") and not String(c.name).contains("tree") and not String(c.name).contains("pine") and not String(c.name).contains("cypress") and not String(c.name).contains("palm"):
						total_graves += (c as MultiMeshInstance3D).multimesh.instance_count
			for key in ch._batch.keys():
				if String(key).begins_with("cem_"):
					keys.append("%s:%d" % [key, (ch._batch.data()[key].xforms as Array).size()])
					if not String(key).contains("tree") and not String(key).contains("pine") and not String(key).contains("cypress") and not String(key).contains("palm"):
						total_graves += (ch._batch.data()[key].xforms as Array).size()
			var body: Node = ch.get_node_or_null("CemeteryBody")
			print("%s (%d,%d): %d steps, %.1f ms total, worst step %.1f ms, children %d, lights %d, zones %d, shapes %d, batches %s%s" % [
				["FULL", "LOD", "CAPTURE"][level], k.x, k.y, n, (Time.get_ticks_usec() - t0) / 1000.0, worst / 1000.0, ch.get_child_count(), lights, zones,
				body.get_child_count() if body else 0, keys,
				(" captured %d ground %d boxes" % [(ch.captured.ground as Array).size(), (ch.captured.boxes as Array).size()]) if level == 2 else ""])
			ch.queue_free()
		if level == 0:
			print("STONES %d" % total_graves)
	print("ROAD closed: %s" % [pl.closed])
	city.free()
