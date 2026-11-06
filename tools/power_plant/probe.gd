extends Node
## The power plant, printed (headless, a minute or two): the snapped site, its pieces, the line's
## towers and station, the lots it takes; then builds every site chunk and the line's chunks FULL
## and LOD and times them, and prints EYEs for stills (still_shot.gd EYE=x,y,z,yaw,pitch).
##   godot --headless --path . res://tools/power_plant/probe.tscn   (BUILD=0 skips the builds)

func _ready() -> void:
	var city: Node3D = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	for n in ["Police", "Emergency"]:
		if city.get_node_or_null(n):
			city.get_node(n).set("enabled", false)
	var t0 := Time.get_ticks_msec()
	var plan := CityPlan.new()
	plan.seed = 1337
	plan.macro = MacroMap.new()
	plan.macro.seed = 1337
	plan.macro.setup()
	print("PLAN ready in %d ms" % (Time.get_ticks_msec() - t0))
	var lay := PowerPlant.layout(plan)
	if lay.is_empty():
		print("PLANT none; sites=", plan.sites().map(func(x): return x.id))
		get_tree().quit()
		return
	var s: Dictionary = lay.site
	print("PLANT rect=%s ok=%s roads x %d..%d z %d..%d pieces=%d" % [lay.rect, lay.ok, s.ix0, s.ix1, s.iz0, s.iz1, (lay.pieces as Array).size()])
	for p: Dictionary in lay.pieces:
		print("  PIECE %s at %s size %s" % [p.kind, p.c, p.size])
	for ix in range(int(s.ix0), int(s.ix1)):
		for iz in range(int(s.iz0), int(s.iz1)):
			var b := plan.block(ix, iz)
			print("  BLOCK %d,%d site=%s grounds=%s kind=%d zone=%s" % [ix, iz, b.get("site", ""), b.get("grounds", ""), int(b.kind), MacroMap.zone_name(plan.zone_at((b.rect as Rect2).get_center()))])
	t0 = Time.get_ticks_msec()
	var ln := PowerPlant.line(plan)
	print("LINE planned in %d ms: %s" % [Time.get_ticks_msec() - t0, "none" if ln.is_empty() else "%d towers" % (ln.towers as Array).size()])
	if not ln.is_empty():
		for t: Dictionary in ln.towers:
			print("  TOWER %d at %s yaw %.2f kind %d base %.2f h %.0f" % [t.id, t.pos, t.yaw, t.kind, t.base, t.h])
		print("  STATION %s" % ln.station.rect)
		var taken := 0
		var blocks := {}
		for seg: Array in ln.row:
			for k in [plan.block_index_at(seg[0]), plan.block_index_at(seg[1])]:
				blocks[k] = true
		for k: Vector2i in blocks:
			var before := 0
			for lot in plan.lots(k.x, k.y):
				before += 1
			print("  ROW block %s lots left %d claimed? (houses via extra) %d" % [k, before, HouseKit.extra_lots(plan, k.x, k.y).size()])
	var r: Rect2 = lay.rect
	var c := r.get_center()
	print("EYE aerial_sw %.1f,160,%.1f,%.1f,-30" % [c.x - 260.0, c.y + 300.0, rad_to_deg(atan2(-260.0, 300.0))])
	print("EYE beach %.1f,2.0,%.1f,%.1f,8" % [r.position.x - 70.0, c.y + 160.0, rad_to_deg(atan2(-70.0, 160.0))])
	print("EYE gate %.1f,1.7,%.1f,%.1f,10" % [r.end.x + 40.0, (lay.gate.at as Vector2).y + 30.0, rad_to_deg(atan2(40.0, 30.0))])
	if OS.get_environment("BUILD") != "0":
		get_tree().root.add_child.call_deferred(city)
		for i in 10:
			await get_tree().process_frame
		var cplan: CityPlan = city.get("plan")
		var keys: Array = []
		for ix in range(int(s.ix0), int(s.ix1)):
			for iz in range(int(s.iz0), int(s.iz1)):
				keys.append(Vector2i(ix, iz))
		keys.append(Vector2i(int(s.ix0) - 1, int(s.iz0)))
		var cl := PowerPlant.line(cplan)
		if not cl.is_empty():
			for t: Dictionary in cl.towers:
				var k := cplan.chunk_index_at(t.pos)
				if not keys.has(k):
					keys.append(k)
			var k2 := cplan.chunk_index_at((cl.station.rect as Rect2).get_center())
			if not keys.has(k2):
				keys.append(k2)
		for key: Vector2i in keys:
			for lvl in [CityChunk.Level.FULL, CityChunk.Level.LOD]:
				var ch: CityChunk = city.call("_new_chunk", key, lvl)
				if ch.get_parent() == null:
					city.add_child(ch)
				var tb := Time.get_ticks_usec()
				ch.begin_build()
				var worst := 0
				var n := 0
				while true:
					var ts := Time.get_ticks_usec()
					var done: bool = ch.build_step()
					worst = maxi(worst, Time.get_ticks_usec() - ts)
					n += 1
					if done:
						break
				var tris := 0
				for mi in ch.find_children("PowerPlant*", "MeshInstance3D", true, false):
					var m: Mesh = (mi as MeshInstance3D).mesh
					for si in m.get_surface_count():
						tris += m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX].size() / 3
				print("BUILD %s %s: %d ms, %d steps, worst %.1f ms, plant tris %d, nodes %d" % [key, "FULL" if lvl == CityChunk.Level.FULL else "LOD", (Time.get_ticks_usec() - tb) / 1000, n, worst / 1000.0, tris, ch.get_child_count()])
				ch.queue_free()
				await get_tree().process_frame
	get_tree().quit()
