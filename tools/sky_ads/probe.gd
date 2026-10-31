extends Node
## Aerial advertising, headless and in seconds: the routes (lengths, heights, where they run),
## the meshes' triangle counts, the banners' lengths and the night sign's strip.
##   godot --headless --path . res://tools/sky_ads/probe.tscn      (SEED=n for another seed)

func _ready() -> void:
	await get_tree().process_frame
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var t0 := Time.get_ticks_msec()
	var macro := MacroMap.new()
	var seed_env := OS.get_environment("SEED")
	macro.seed = int(seed_env) if seed_env != "" else city.world_seed
	var plan := CityPlan.new()
	plan.seed = macro.seed
	for key in ["block_size_range", "street_width", "avenue_width", "sidewalk_width", "downtown_radius", "midtown_radius"]:
		plan.set(key, city.get(key))
	plan.macro = macro
	city.free()
	macro.setup()
	var air := AirTraffic.new()
	air.plan = plan
	air.macro = macro
	var ads := SkyAds.new()
	ads.air = air
	ads.plan = plan
	ads.macro = macro
	var t1 := Time.get_ticks_msec()
	ads._build_routes()
	print("setup ms=%d routes ms=%d" % [t1 - t0, Time.get_ticks_msec() - t1])
	print("stadium ", ads.stadium_centre(), " beach ", ads.beach_centre(), " zone ", MacroMap.zone_name(macro.zone_at(ads.beach_centre())))
	for r: AirRoute in [ads.blimp_route] + ads.banner_routes:
		var lo := INF
		var hi := -INF
		var clear := INF
		var sea := 0
		var bank := 0.0
		for i in r.xz.size():
			lo = minf(lo, r.y[i])
			hi = maxf(hi, r.y[i])
			clear = minf(clear, r.y[i] - float(air.obstacle_top(r.xz[i])))
			if macro.zone_at(r.xz[i]) == MacroMap.Zone.OCEAN:
				sea += 1
			bank = maxf(bank, absf(r.turn[i]))
		print("%s length %.0f m, %d points, height %.0f..%.0f, least clearance %.0f, %d %% over the sea, tightest turn radius %.0f m" % [r.name, r.length, r.xz.size(), lo, hi, clear, 100 * sea / maxi(r.xz.size(), 1), 1.0 / maxf(bank, 1e-6)])
		var s := 0.0
		while s < r.length:
			var p: Vector3 = r.sample(s).pos
			print("   s=%5.0f (%6.0f, %5.0f, %6.0f) %s" % [s, p.x, p.y, p.z, MacroMap.zone_name(macro.zone_at(Vector2(p.x, p.z)))])
			s += r.length / 8.0
	var tc := SkyAdMesh.triangle_counts()
	print("triangles: ", tc)
	for b: Array in SkyAds.BANNERS:
		var m := SkyAdMesh.banner(b[0], b[1])
		print("banner '%s': %.1f m, %d triangles" % [b[0], float(m.get_meta("length")), m.surface_get_array_index_len(0) / 3])
	print("led strip %d px" % SkyAds.led_width())
	for h in [6.0, 8.5, 10.0, 13.0, 18.0, 19.0, 22.0]:
		print("hour %.1f: blimp %s, banners %s %s" % [h, SkyAds.blimp_flies(h, 0), ads.banner_flies(0, h, 0), ads.banner_flies(1, h, 0)])
	air.free()
	ads.free()
	get_tree().quit()
