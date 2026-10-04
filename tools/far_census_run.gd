extends RefCounted
## The body of tools/far_census.gd, loaded at run time: a --script compiles before the autoloads
## exist, so it must not name CityPlan, Skyline or anything that uses one (CLAUDE.md).

func run(tree: SceneTree) -> void:
	var root := tree.root
	var eye := Vector2(1900.0, 500.0)
	var radius := 7000.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--eye="):
			var p := a.substr(6).split(",")
			eye = Vector2(p[0].to_float(), p[1].to_float())
		elif a.begins_with("--radius="):
			radius = a.substr(9).to_float()
	var scene: PackedScene = load("res://scenes/levels/city.tscn")
	var s = scene.instantiate()
	var plan := CityPlan.new()
	plan.seed = s.world_seed
	plan.block_size_range = s.block_size_range
	plan.street_width = s.street_width
	plan.avenue_width = s.avenue_width
	plan.sidewalk_width = s.sidewalk_width
	plan.downtown_radius = s.downtown_radius
	plan.midtown_radius = s.midtown_radius
	plan.macro = MacroMap.new()
	plan.macro.seed = s.world_seed
	plan.macro.setup()
	# FAR_CODED=0|1 forces the coded far boxes off or on (FarBuilding.enabled), for an A/B.
	var coded := OS.get_environment("FAR_CODED")
	if coded != "":
		FarBuilding.enabled = coded == "1"
	print("FAR_CENSUS coded far boxes: %s" % str(FarBuilding.enabled))
	var sky := Skyline.new()
	root.add_child(sky)
	sky.setup(plan, s.chunk_style())
	sky.radius = radius
	# Warm the caches a first block pays for (meshes, materials), so the timing is the build.
	sky.build_near(eye, 10.0)
	var mem0 := Performance.get_monitor(Performance.MEMORY_STATIC)
	var t0 := Time.get_ticks_usec()
	sky.build_near(eye, radius)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var mem1 := Performance.get_monitor(Performance.MEMORY_STATIC)
	# Second pass, counting: the same tiles built again by hand, read just before each is committed
	# (a committed tile keeps only its colours).
	var kinds := {"facade": 0, "facade_v2": 0, "plain": 0, "plate": 0, "deck": 0, "other": 0}
	var box_tris := 0
	var veg := 0
	var houses := 0
	var tiles := 0
	var count := Skyline.new()
	root.add_child(count)
	count.setup(plan, s.chunk_style())
	var box_mesh_tris := _tris(PropFactory.unit_box())
	for t in sky._tiles:
		if sky._tiles[t] == null:
			continue
		tiles += 1
		count._begin_tile(t)
		while true:
			var w: Dictionary = count._work
			if not w.has("cap") and int(w.next) >= (w.blocks as Array).size():
				for c: Color in w.customs:
					if c.a < -0.5:
						kinds.facade_v2 += 1
					elif c.a < 0.5:
						kinds.facade += 1
					elif c.a < 1.5:
						kinds.plain += 1
					elif c.a < 2.5:
						kinds.plate += 1
					elif c.a < 3.5:
						kinds.deck += 1
					else:
						kinds.other += 1
				veg += (w.veg as Array).size()
				houses += (w.houses as Array).size()
			if count._work_step():
				break
		var tile = count._tiles.get(t)
		if tile != null and tile.node:
			var mm: MultiMesh = (tile.node as MultiMeshInstance3D).multimesh
			box_tris += _tris(mm.mesh) * mm.instance_count
		# Free as we go: the counting copy is not what is being measured.
		if tile != null:
			for key in ["node", "veg", "house"]:
				if tile[key]:
					(tile[key] as Node).free()
			count._tiles[t] = null
	var meshes := {"unit_box": box_mesh_tris}
	# The LOD ring round the eye (CityStreamer.lod_radius_blocks, seven blocks): every city block's
	# LOD build, which the capture is, counted the same way - the LOD chunks draw ALL of a
	# building's roof plant, the far city only its silhouettes.
	var ring := {"parts": 0, "plain": 0, "plant_small": 0, "plant_big": 0, "old_facade": 0}
	var here: Vector2i = plan.block_index_at(eye)
	var t1 := Time.get_ticks_usec()
	var ring_blocks := 0
	for dx in range(-7, 8):
		for dz in range(-7, 8):
			var k := Vector2i(here.x + dx, here.y + dz)
			var b := plan.block(k.x, k.y)
			if plan.zone_at((b.rect as Rect2).get_center()) != MacroMap.Zone.CITY:
				continue
			var cap := CityChunk.new()
			cap.plan = plan
			cap.ix = k.x
			cap.iz = k.y
			cap.level = CityChunk.Level.LOD
			cap.style = s.chunk_style()
			cap.capturing = true
			cap.build()
			ring_blocks += 1
			for c: Color in (cap.captured.batch.get("lod_box", {"custom": []}) as Dictionary).custom:
				if c.a < -0.5:
					ring.parts += 1
				elif c.a > 3.5:
					ring["plant_big" if c.g > 0.5 else "plant_small"] += 1
				elif c.a > 0.5:
					ring.plain += 1
				else:
					ring.old_facade += 1
			cap.free()
	var ring_ms := float(Time.get_ticks_usec() - t1) / 1000.0
	var ring_total: int = ring.parts + ring.plain + ring.plant_small + ring.plant_big + ring.old_facade
	print("FAR_CENSUS lod_ring blocks=%d instances=%d tris=%d %s build_ms=%.0f" % [ring_blocks, ring_total, ring_total * box_mesh_tris, str(ring), ring_ms])
	print("FAR_CENSUS eye=%s radius=%.0f blocks=%d tiles=%d build_ms=%.0f static_mem_mb=%.1f" % [str(eye), radius, sky.blocks_built, tiles, ms, (mem1 - mem0) / 1048576.0])
	print("FAR_CENSUS boxes facade=%d facade_v2=%d plain=%d plate=%d deck=%d other=%d box_tris=%d veg=%d houses=%d meshes=%s" % [kinds.facade, kinds.facade_v2, kinds.plain, kinds.plate, kinds.deck, kinds.other, box_tris, veg, houses, str(meshes)])
	s.free()
	sky.queue_free()
	count.queue_free()
	tree.quit()


static func _tris(mesh: Mesh) -> int:
	var n := 0
	for i in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(i)
		var idx = a[Mesh.ARRAY_INDEX]
		n += (idx as PackedInt32Array).size() / 3 if idx != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n
