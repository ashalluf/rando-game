extends Node
## The film studio lot, printed (headless, a minute): the snapped site, the sub-blocks and their
## roles, the stages, the gate, the fronts, basecamp; then builds every site chunk FULL and LOD and
## times it, and prints EYEs for stills (still_shot.gd EYE=x,y,z,yaw,pitch).
##   godot --headless --path . res://tools/film_studio/probe.tscn   (BUILD=0 skips the builds)

func _ready() -> void:
	var city: Node3D = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	for n in ["Police", "Emergency"]:
		if city.get_node_or_null(n):
			city.get_node(n).set("enabled", false)
	get_tree().root.add_child.call_deferred(city)
	for i in 10:
		await get_tree().process_frame
	var plan = city.get("plan")
	var fs: GDScript = load("res://scripts/world/film_studio.gd")
	var lay: Dictionary = fs.call("layout", plan)
	if lay.is_empty():
		print("STUDIO none sites=", plan.sites().map(func(x): return x.id), " entries=", Landmarks.all().map(func(x): return x.id).slice(-3))
		get_tree().quit()
		return
	var s: Dictionary = lay.site
	print("STUDIO rect=%s inner=%s roads x %d..%d z %d..%d gate=%s" % [lay.rect, lay.inner, s.ix0, s.ix1, s.iz0, s.iz1, lay.gate.at])
	for sub: Dictionary in lay.subs:
		print("SUB %d,%d %s content=%s" % [sub.bx, sub.bz, sub.role, sub.content])
	for sg: Dictionary in lay.stages:
		print("STAGE %d at %s size %s doors %d rolling %s" % [sg.number, sg.c, sg.size, sg.doors.size(), sg.rolling])
	print("FRONTS %d LOTS %d PARKING %d CARTS %d LAMPS %d CARS %d STREETS %d tower=%s offices=%s" % [lay.fronts.size(), lay.lots.size(), lay.parking.size(), lay.carts.size(), lay.lamps.size(), lay.cars.size(), lay.streets.size(), lay.tower, lay.offices.get("c", "")])
	for ix in range(int(s.ix0) - 1, int(s.ix1) + 1):
		print("ROAD X %d open(mid)=%s" % [ix, plan.road_open(0, ix, (lay.rect as Rect2).get_center().y)])
	for iz in range(int(s.iz0) - 1, int(s.iz1) + 1):
		print("ROAD Z %d open(mid)=%s" % [iz, plan.road_open(1, iz, (lay.rect as Rect2).get_center().x)])
	var g: Vector2 = lay.gate.at
	print("EYE gate  %.1f,1.7,%.1f,%.1f,4" % [g.x + 10.0, g.y + 30.0, rad_to_deg(atan2(10.0, 30.0))])
	var t: Vector2 = lay.tower
	print("EYE tower %.1f,40,%.1f,%.1f,-15" % [t.x - 70.0, t.y + 70.0, rad_to_deg(atan2(-70.0, 70.0))])
	var r: Rect2 = lay.rect
	print("EYE aerial %.1f,140,%.1f,%.1f,-35" % [r.get_center().x + 160.0, r.end.y + 140.0, rad_to_deg(atan2(160.0, 140.0))])
	if not (lay.backlot_street as Rect2).has_area():
		print("NO BACKLOT")
	else:
		var b: Rect2 = lay.backlot_street
		print("EYE backlot %.1f,1.7,%.1f" % [b.get_center().x, b.end.y - 4.0])
	if lay.stages.size() > 0:
		var sg: Dictionary = lay.stages[0]
		print("STAGE0 %s yaw %.2f" % [sg.c, sg.yaw])
	if OS.get_environment("BUILD") != "0":
		var streamer = city
		var kit: GDScript = load("res://scripts/world/film_studio_kit.gd")
		var keys: Array = []
		for ix in range(int(s.ix0), int(s.ix1)):
			for iz in range(int(s.iz0), int(s.iz1)):
				keys.append(Vector2i(ix, iz))
		# Two ordinary midtown neighbours for reference.
		keys.append(Vector2i(int(s.ix0) - 2, int(s.iz0)))
		keys.append(Vector2i(int(s.ix1) + 1, int(s.iz0)))
		for key: Vector2i in keys:
			var ix := key.x
			var iz := key.y
			if true:
				for level in [0, 1]:
					var t0 := Time.get_ticks_usec()
					var tris0: int = kit.get("tris")
					var ch = streamer.call("_new_chunk", Vector2i(ix, iz), level)
					ch.zone = plan.zone_at(plan.block(ix, iz).rect.get_center())
					ch.begin_build()
					var worst := 0.0
					var worst_i := -1
					var n_steps := 0
					while true:
						var s0 := Time.get_ticks_usec()
						var done: bool = ch.build_step()
						var st_ms := (Time.get_ticks_usec() - s0) / 1000.0
						if st_ms > worst:
							worst = st_ms
							worst_i = n_steps
						n_steps += 1
						if done:
							break
					var dt := (Time.get_ticks_usec() - t0) / 1000.0
					var names := []
					for c in ch.get_children():
						if String(c.name).begins_with("Studio"):
							names.append(c.name)
					print("CHUNK %d,%d level %d site=%s %.1f ms (%d steps, worst %.1f at step %d) tris+%d %s" % [ix, iz, level, plan.block(ix, iz).get("site", ""), dt, n_steps, worst, worst_i, int(kit.get("tris")) - tris0, names])
					ch.queue_free()
	print("PROBE_DONE")
	get_tree().quit()
