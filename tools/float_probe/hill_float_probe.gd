extends Node
## Floating-prop probe: builds every hill chunk in a region at FULL (up to its finish, so the
## batch is still data) and compares each batched instance's origin y with MacroMap.height_at().
## Headless (the batch is read as data, so the dummy renderer is fine):
##   REGION=x0,z0,x1,z1 godot --headless --path . res://tools/float_probe/hill_float_probe.tscn
## REGION defaults to the front range, -1500,-2200,1500,-400; the whole basin
## (-3500,-3500,3500,3000) takes about two minutes. Prints PROBE lines, worst chunks first.

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
	plan.macro.setup()
	var style: Dictionary = city.chunk_style()
	var r := OS.get_environment("REGION")
	var reg := [-1500.0, -2200.0, 1500.0, -400.0]
	if r != "":
		var parts := r.split(",")
		for i in 4:
			reg[i] = parts[i].to_float()
	var k0: Vector2i = plan.block_index_at(Vector2(reg[0], reg[1]))
	var k1: Vector2i = plan.block_index_at(Vector2(reg[2], reg[3]))
	var chunk_script: GDScript = load("res://scripts/world/city_chunk.gd")
	var hill_zone: int = MacroMap.Zone.HILLS
	var rows: Array = []
	var total := 0
	var bad := 0
	var worst := 0.0
	var t0 := Time.get_ticks_msec()
	for bz in range(k0.y, k1.y + 1):
		for bx in range(k0.x, k1.x + 1):
			var b := plan.block(bx, bz)
			var c: Vector2 = (b.rect as Rect2).get_center()
			if plan.zone_at(c) != hill_zone:
				continue
			var ch = chunk_script.new()
			ch.plan = plan
			ch.ix = bx
			ch.iz = bz
			ch.level = 0
			ch.style = style
			ch.begin_build()
			while ch._step < ch._steps.size() - 1:
				ch.build_step()
			var n := 0
			var nb := 0
			var cmax := 0.0
			var ckey := ""
			var cat := Vector3.ZERO
			var data: Dictionary = ch._batch.data()
			for key: String in data:
				for xf: Transform3D in data[key].xforms:
					var o := xf.origin
					var dy := o.y - plan.height_at(Vector2(o.x, o.z))
					n += 1
					if absf(dy) > 3.0:
						nb += 1
					if absf(dy) > absf(cmax):
						cmax = dy
						ckey = key
						cat = o
			total += n
			bad += nb
			worst = maxf(worst, absf(cmax))
			rows.append([absf(cmax), "block %d,%d centre %.0f,%.0f: %d instances, %d off by >3 m, worst %+.1f m (%s at %.0f,%.0f) relief %.1f" % [bx, bz, c.x, c.y, n, nb, cmax, ckey, cat.x, cat.z, plan.macro.relief_at(Vector2(cat.x, cat.z))]])
			ch.free()
	rows.sort_custom(func(a, b): return a[0] > b[0])
	var bad_chunks := 0
	for row in rows:
		if row[0] > 3.0:
			bad_chunks += 1
	print("PROBE region %s: %d hill chunks, %d instances, %d off by >3 m in %d chunks, worst %.1f m (%d ms)" % [str(reg), rows.size(), total, bad, bad_chunks, worst, Time.get_ticks_msec() - t0])
	for i in mini(15, rows.size()):
		print("PROBE  ", rows[i][1])
	city.free()
	get_tree().quit()
