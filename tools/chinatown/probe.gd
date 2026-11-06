extends Node
## Chinatown's layout for a seed, headless and in seconds: the district's blocks and their roles,
## the plaza, the gate, how many lots each block gives the shop buildings, then each block built
## FULL and LOD the real way (CityChunk), with its build time, triangles and collision - and EYEs
## for still_shot.gd / block_shot.tscn.
##   godot --headless --path . res://tools/chinatown/probe.tscn [-- --seed=N] [BUILD=0]

func _ready() -> void:
	await get_tree().process_frame
	var seed_value := 1337
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = int(a.substr(7))
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var plan := CityPlan.new()
	plan.seed = seed_value
	plan.block_size_range = city.block_size_range
	plan.street_width = city.street_width
	plan.avenue_width = city.avenue_width
	plan.sidewalk_width = city.sidewalk_width
	plan.downtown_radius = city.downtown_radius
	plan.midtown_radius = city.midtown_radius
	plan.macro = MacroMap.new()
	plan.macro.seed = seed_value
	plan.macro.setup()
	for s in ["JADE MOON TEA HOUSE", "D", Chinatown.NAME]:
		var geo := ShopfrontKit._text_geo(s, 0.42)
		var idx = geo[2]
		print("CT text '%s' tris %d" % [s, (idx.size() if idx != null else (geo[0] as PackedVector3Array).size()) / 3])
	var gt0 := ChinatownGeo.new()
	gt0.use("sign", ChinatownKit.material())
	ChinatownKit.lantern(gt0, Vector3.ZERO, 0.1, 0.5, Color.RED, 0.0)
	print("CT lantern tris %d" % gt0.triangles)
	var gt1 := ChinatownGeo.new()
	gt1.use("sign", ChinatownKit.material())
	var u := ChinatownKit.plan_units(1, 2, 9.0)
	u[0].goods = -1
	u[0].blade = false
	ChinatownKit.shop_unit(gt1, u[0], 14.0, false)
	print("CT unit tris %d (%s, %d storeys)" % [gt1.triangles, u[0].roof, u[0].storeys])
	var ext := Chinatown.extent()
	print("CT extent ", ext, " enabled ", Chinatown.enabled)
	var a := plan.block_index_at(ext.position)
	var b := plan.block_index_at(ext.end)
	var blocks: Array = []
	for iz in range(a.y - 1, b.y + 2):
		for ix in range(a.x - 1, b.x + 2):
			var role := Chinatown.block_role(plan, ix, iz)
			if role == "":
				continue
			var lots := plan.lots(ix, iz)
			var claimed := 0
			for lot in lots:
				if Chinatown.claims(plan, ix, iz, lot):
					claimed += 1
			var r: Rect2 = plan.block(ix, iz).rect
			print("CT block %d,%d %-5s kind %d lots %d claimed %d rect %s" % [ix, iz, role, plan.block(ix, iz).kind, lots.size(), claimed, r])
			blocks.append(Vector2i(ix, iz))
	var pb := Chinatown.plaza_block(plan)
	print("CT plaza ", pb)
	if pb.x > -9999:
		var L := ChinatownKit.plaza_layout(plan.block(pb.x, pb.y).rect, plan.sidewalk_width)
		var h: Vector2 = L.hall
		print("CT hall %.1f,%.1f  EYE=%.1f,1.7,%.1f,0,8 (hall from the walk)" % [h.x, h.y, h.x, float(L.walk_z) + 4.0])
	var gt := Chinatown.gate(plan)
	print("CT gate ", gt)
	if not gt.is_empty():
		print("CT gate EYE=%.1f,1.7,%.1f,0,10 (from the south, up Broadway)" % [float(gt.x) + 3.0, float(gt.z) + 45.0])
	if OS.get_environment("BUILD") == "0":
		city.free()
		get_tree().quit()
		return
	var style: Dictionary = city.chunk_style()
	var chunk_script: GDScript = load("res://scripts/world/city_chunk.gd")
	if OS.get_environment("ONLY") != "":
		var o := OS.get_environment("ONLY").split(",")
		blocks = [Vector2i(int(o[0]), int(o[1]))]
	var reps := 2 if OS.get_environment("REPEAT") == "1" else 1
	for k: Vector2i in blocks:
		for level in ([0, 0, 1] if reps == 2 else [0, 1]):
			var t0 := Time.get_ticks_usec()
			var tris0 := LandmarkGeo.committed_triangles
			var ch = chunk_script.new()
			ch.plan = plan
			ch.ix = k.x
			ch.iz = k.y
			ch.level = level
			ch.style = style
			add_child(ch)
			ch.begin_build()
			var worst := 0.0
			var worst_i := 0
			var si := 0
			while true:
				var s0 := Time.get_ticks_usec()
				var done: bool = ch.build_step()
				var sms := float(Time.get_ticks_usec() - s0) / 1000.0
				if OS.get_environment("STEPS") == "1" and sms > 8.0:
					print("CT   step %d %.1f ms" % [si, sms])
				if sms > worst:
					worst = sms
					worst_i = si
				si += 1
				if done:
					break
			var ms := float(Time.get_ticks_usec() - t0) / 1000.0
			var node: Node = ch.get_node_or_null("Chinatown")
			var shapes := 0
			if node and node.get_node_or_null("ChinatownBody"):
				shapes = node.get_node("ChinatownBody").get_child_count()
			print("CT build %d,%d %s %.1f ms (worst step %.1f ms #%d of %d) tris %d  shapes %d  buildings %d" % [k.x, k.y, "FULL" if level == 0 else "LOD", ms, worst, worst_i, si,
				LandmarkGeo.committed_triangles - tris0, shapes, ch.building_count])
			ch.queue_free()
			await get_tree().process_frame
	city.free()
	get_tree().quit()
