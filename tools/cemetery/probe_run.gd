extends RefCounted
## The body of tools/cemetery/probe.gd (loaded once the autoloads exist).

func run(_tree: SceneTree) -> void:
	var scene: PackedScene = load("res://scenes/levels/city.tscn")
	var s = scene.instantiate()
	var plan := CityPlan.new()
	plan.seed = s.world_seed if OS.get_environment("SEED") == "" else OS.get_environment("SEED").to_int()
	plan.block_size_range = s.block_size_range
	plan.street_width = s.street_width
	plan.avenue_width = s.avenue_width
	plan.sidewalk_width = s.sidewalk_width
	plan.downtown_radius = s.downtown_radius
	plan.midtown_radius = s.midtown_radius
	plan.macro = MacroMap.new()
	plan.macro.seed = plan.seed
	plan.macro.setup()
	s.free()
	var box := Rect2(-6000.0, -6000.0, 12000.0, 12000.0)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		var v := (args[0] as String).split(",")
		box = Rect2(float(v[0]), float(v[1]), float(v[2]) - float(v[0]), float(v[3]) - float(v[1]))
	var t0 := Time.get_ticks_msec()
	var found := 0
	var seen := {}
	var suburbs := 0
	var k0 := plan.block_index_at(box.position)
	var k1 := plan.block_index_at(box.end)
	for ix in range(k0.x, k1.x + 1):
		for iz in range(k0.y, k1.y + 1):
			var b := plan.block(ix, iz)
			if int(b.district) == CityPlan.District.SUBURBS and plan.zone_at((b.rect as Rect2).get_center()) == MacroMap.Zone.CITY:
				suburbs += 1
			if String(b.get("grounds", "")) != "cemetery":
				continue
			var pl := Cemetery.plan_for(plan, ix, iz)
			if seen.has(pl.seed):
				continue
			seen[pl.seed] = true
			found += 1
			var site: Rect2 = pl.site
			var gate: Vector2 = pl.gate
			var n: Vector2 = pl.n
			var a: Vector2 = pl.a
			var eye := gate - n * 22.0 + a * 10.0
			var to := gate + n * 30.0 - eye
			var yaw := rad_to_deg(atan2(-to.x, -to.y))
			var g := plan.macro.height_at(eye)
			print("CEMETERY (%d,%d) %s '%s' site %s (%.0f x %.0f) H %.1f front %d road %d pts trees %d lamps %d" % [
				ix, iz, pl.blocks, pl.name, site.position.round(), site.size.x, site.size.y, pl.H, pl.front,
				(pl.road as PackedVector2Array).size(), (pl.trees as Array).size(), (pl.lamps as Array).size()])
			print("   EYE=%.1f,%.1f,%.1f,%.1f,-3   crown %s gy %.1f" % [eye.x, 1.7 + g, eye.y, yaw, (pl.crown as Vector2).round(), g])
			var c: Vector2 = site.get_center()
			var air := c - n * (site.size.length() * 0.55)
			var to2 := c - air
			print("   AIR=%.1f,%.1f,%.1f,%.1f,-28" % [air.x, g + 70.0, air.y, rad_to_deg(atan2(-to2.x, -to2.y))])
	print("WHY %s" % [Cemetery.why])
	var sizes := []
	print("CEMETERIES %d of %d suburb blocks in %d ms" % [found, suburbs, Time.get_ticks_msec() - t0])
