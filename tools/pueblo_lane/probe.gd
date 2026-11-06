extends Node
## The marketplace lane by Pueblo Station (PuebloLane): builds it near and far, prints the layout,
## the triangle counts, the build time and EYEs for still_shot.gd. Headless, seconds.
##   godot --headless --path . tools/pueblo_lane/probe.tscn [-- --seed=N]
## (a scene, so the autoloads exist before the classes it builds with compile)

func _ready() -> void:
	await get_tree().process_frame
	var seed_value := 1337
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = int(a.substr(7))
	var m := MacroMap.new()
	m.seed = seed_value
	m.setup()
	var plan := CityPlan.new()
	plan.seed = seed_value
	plan.macro = m
	var info := CivicSites.site(plan, PuebloLane.ID)
	var k := PuebloLane.kiosk_local(info)
	var L := PuebloLane.layout(info.local, k)
	var c: Vector2 = info.centre
	print("SITE world %s centre %s y0 %.2f kiosk local %s real %s" % [info.world, c, info.y0, k, DowntownReal.game_xz(PuebloLane.KIOSK_LATLON)])
	print("STATION %s plaza world %s (off the real plaza %.1f m)" % [CivicSites.anchor("pueblo_station"), CivicSites.to_world(info, L.p), CivicSites.to_world(info, L.p).distance_to(DowntownReal.game_xz(PuebloLane.KIOSK_LATLON))])
	for key in ["plaza", "lane", "west", "east", "north", "church", "fire", "hotel", "court", "east_lot", "east_lot2", "south", "garden", "south_lot"]:
		print("  %-9s %s" % [key, L[key]])
	print("SEGS %d STALLS %d" % [L.segs.size(), L.stalls.size()])
	var lm := {}
	for e in Landmarks.all():
		if e.id == PuebloLane.ID:
			lm = e
	for detailed in [true, true, false]:
		var root := Node3D.new()
		get_tree().root.add_child(root)
		var body := StaticBody3D.new()
		root.add_child(body)
		var t0 := Time.get_ticks_usec()
		Landmarks.build(lm, root, body if detailed else null, plan, detailed)
		var us := Time.get_ticks_usec() - t0
		var pivot := root.get_node("Civic_" + PuebloLane.ID)
		print("%s: %d us, tris %s, shapes %d, nodes %d, zones %d" % ["NEAR" if detailed else "FAR", us, pivot.get_meta("pueblo_tris", {}),
			pivot.get_node("CivicBody").get_child_count() if pivot.has_node("CivicBody") else 0, pivot.get_child_count(), get_tree().get_nodes_in_group(Sanctuary.ZONE_GROUP).size()])
		if detailed:
			print("  pergola cards %d" % int(pivot.get_meta("pergola_cards", 0)))
		root.queue_free()
		await get_tree().process_frame
	var p := CivicSites.to_world(info, L.p)
	var lane: Rect2 = L.lane
	var ln := CivicSites.to_world(info, Vector2(lane.get_center().x, lane.position.y + 20.0))
	var ch: Rect2 = L.church
	var cw := CivicSites.to_world(info, Vector2(ch.get_center().x, ch.position.y - 30.0))
	print("EYE plaza  %.1f,%.1f,%.1f,%.0f,%.0f" % [p.x + 20.0, info.y0 + 1.7, p.y + 22.0, 42.0, 2.0])
	print("EYE lane   %.1f,%.1f,%.1f,%.0f,%.0f" % [ln.x + 3.5, info.y0 + 1.7, ln.y + 60.0, 4.0, 0.0])
	print("EYE church %.1f,%.1f,%.1f,%.0f,%.0f" % [cw.x, info.y0 + 1.7, cw.y, 180.0, 8.0])
	print("EYE air    %.1f,%.1f,%.1f,%.0f,%.0f" % [p.x + 60.0, info.y0 + 60.0, p.y + 80.0, 35.0, -35.0])
	get_tree().quit()
