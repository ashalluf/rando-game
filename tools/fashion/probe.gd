extends Node
## The fashion district's blocks (FashionDistrict), headless and in seconds: every block in the
## stretch with its kind, district, lots, alley and what the district makes of it. BUILD=1 also
## builds the FULL chunks of the district (or AT="x,z;...") through the real CityChunk build and
## prints what FashionDistrict placed in each, its step time and EYEs for still_shot.gd.
##
##   godot --headless --path . res://tools/fashion/probe.tscn
##
## Env: SEED, BUILD=1, AT="x,z;x,z", FASHION=0 (the A/B).
## Scene, not --script: CityChunk names autoloads.

func _ready() -> void:
	await get_tree().process_frame
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var plan := CityPlan.new()
	plan.seed = int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else city.world_seed
	plan.block_size_range = city.block_size_range
	plan.street_width = city.street_width
	plan.avenue_width = city.avenue_width
	plan.sidewalk_width = city.sidewalk_width
	plan.downtown_radius = city.downtown_radius
	plan.midtown_radius = city.midtown_radius
	plan.macro = MacroMap.new()
	plan.macro.seed = plan.seed
	plan.macro.setup()
	var a := plan.block_index_at(Vector2(3150.0, 420.0))
	var b := plan.block_index_at(Vector2(3950.0, 1560.0))
	var keys: Array[Vector2i] = []
	for bz in range(a.y - 1, b.y + 2):
		for bx in range(a.x - 1, b.x + 2):
			var blk := plan.block(bx, bz)
			var r: Rect2 = blk.rect
			var sp := Alleys.spec(plan, bx, bz)
			var al := "-"
			if not sp.is_empty():
				al = "%s seam %.0f band %s" % ["x" if sp.along_x else "z", float(sp.seam), sp.band]
			var fd := ""
			if ClassDB.class_exists("FashionDistrict") or ResourceLoader.exists("res://scripts/world/fashion_district.gd"):
				var fds: GDScript = load("res://scripts/world/fashion_district.gd")
				var info: Dictionary = fds.call("block_info", plan, bx, bz)
				if not info.is_empty():
					fd = " FASHION faces %s market %s" % [info.faces, info.market]
					keys.append(Vector2i(bx, bz))
			print("B %d,%d rect %s kind %d dist %d boost %.2f site %s grounds %s skid %.2f lots %d alley %s%s" % [bx, bz, r, int(blk.kind), int(blk.district),
				plan.macro.skyline_boost(r.get_center()), blk.has("site"), blk.get("grounds", "-"), Encampment.skid_row(plan, bx, bz), plan.lots(bx, bz).size(), al, fd])
	if OS.get_environment("AT") != "":
		keys.clear()
		for e in OS.get_environment("AT").split(";", false):
			var v := e.split_floats(",")
			keys.append(plan.block_index_at(Vector2(v[0], v[1])))
	if OS.get_environment("BUILD") == "1":
		var style: Dictionary = city.chunk_style()
		var chunk_script: GDScript = load("res://scripts/world/city_chunk.gd")
		for k in keys:
			var ch = chunk_script.new()
			ch.plan = plan
			ch.ix = k.x
			ch.iz = k.y
			ch.level = 0
			ch.style = style
			add_child(ch)
			var t0 := Time.get_ticks_usec()
			ch.build()
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			var m: Dictionary = ch.get_meta("fashion", {})
			print("BUILD %s build=%.0f ms fashion=%s" % [k, ms, m.get("stats", {})])
			for e: String in m.get("eyes", []):
				print("  EYE=%s" % e)
			ch.free()
	city.free()
	get_tree().quit()
