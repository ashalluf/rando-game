extends Node
## Finds the city's billboards (Billboards) for framing stills, headless:
##   godot --headless --path . res://tools/billboard_probe.tscn -- --spawn=x,z   (env R=blocks)
## (a scene, not --script: it names CityChunk, which needs the autoloads.)
## Builds the far city's capture of every block within R (default 6) blocks of the point and
## counts the board faces it records (lod_box PANEL boxes with a lit flag: roof bulletins and
## posters, digital boards, supergraphics, monopole faces), by block; then, for the busiest
## blocks (TOP, default 3), builds the FULL chunk and prints each board with an EYE for
## tools/glshot/still_shot.gd looking at its face from the street.

func _ready() -> void:
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	add_child(city)
	var c := Vector2.ZERO
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
	for i in 30:
		await get_tree().process_frame
	var plan: CityPlan = city.get("plan")
	var r := int(OS.get_environment("R")) if OS.get_environment("R") != "" else 6
	var top := int(OS.get_environment("TOP")) if OS.get_environment("TOP") != "" else 3
	var k0: Vector2i = plan.block_index_at(c)
	var counts: Array = []
	var total := {"lit": 0, "led": 0, "super": 0}
	for bx in range(k0.x - r, k0.x + r + 1):
		for bz in range(k0.y - r, k0.y + r + 1):
			var cap := CityChunk.new()
			cap.plan = plan
			cap.ix = bx
			cap.iz = bz
			cap.level = CityChunk.Level.LOD
			cap.style = city.chunk_style()
			cap.capturing = true
			cap.build()
			var boxes: Dictionary = (cap.captured.get("batch", {}) as Dictionary).get("lod_box", {})
			var n := 0
			var customs: Array = boxes.get("custom", [])
			for cu: Color in customs:
				if is_equal_approx(cu.a, FarBuilding.PLANT_FLAG) and int(cu.r + 0.5) == FarBuilding.Plant.PANEL and cu.b > 0.25:
					n += 1
					if cu.b > 1.5:
						total.led += 1
					elif cu.b > 0.75:
						total.lit += 1
					else:
						total.super += 1
			if n > 0:
				counts.append([n, Vector2i(bx, bz), CityPlan.DISTRICT_NAMES[plan.block(bx, bz).district]])
			cap.free()
	# The freeway monopoles (pure) and the strip roads in the window.
	for bx in range(k0.x - r, k0.x + r + 1):
		for bz in range(k0.y - r, k0.y + r + 1):
			for j: Dictionary in Billboards.monopoles(plan, bx, bz, plan.block(bx, bz)):
				var a: Vector3 = j.anchor
				var u: Dictionary = j.units[0]
				print("  POLE (%.1f, %.1f) top %.1f %s fmt %d" % [a.x, a.z, float(j.pole_top), Vector2i(bx, bz), int(u.fmt)])
	for axis in 2:
		for i in range((k0.x if axis == 0 else k0.y) - r, (k0.x if axis == 0 else k0.y) + r + 2):
			if Billboards.is_strip(plan, axis, i):
				print("  STRIP axis %d index %d at %.1f" % [axis, i, plan.road_pos(axis, i)])
	counts.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	print("BOARDS lit %d  led %d  super %d over %d blocks" % [total.lit, total.led, total.super, (2 * r + 1) * (2 * r + 1)])
	for i in mini(counts.size(), 12):
		print("  BLOCK ", counts[i][1], " ", counts[i][2], " faces ", counts[i][0])
	for i in mini(counts.size(), top):
		var k: Vector2i = counts[i][1]
		var chunk: CityChunk = city.call("_new_chunk", k, CityChunk.Level.FULL)
		chunk.build()
		for rec: Dictionary in chunk.prop_records:
			if rec.kind == "bus_stop":
				print("  SHELTER %s at %s" % [k, (rec.position as Vector3).snapped(Vector3.ONE * 0.1)])
			if rec.kind != "billboard":
				continue
			var at: Vector3 = rec.position
			var keys := {}
			for inst: Array in rec.instances:
				keys[inst[0]] = true
			print("  BOARD %s at (%.1f, %.1f, %.1f) %s" % [k, at.x, at.y, at.z, ",".join(keys.keys())])
		var bb := 0
		for ch in chunk.get_children():
			if String(ch.name).begins_with("Batch_bb_") or String(ch.name).begins_with("BatchShadow_bb_"):
				bb += 1
		print("  CHUNK %s billboard batches %d" % [k, bb])
		chunk.get_parent().remove_child(chunk)
		chunk.free()
	get_tree().quit()
