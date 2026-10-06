extends Node
## Swimming's data in seconds, headless: compiles Swim and its helpers, makes the default seed's
## map, and prints the sea's height over time at points off the beach (SeaSurface), the water
## SwimWater finds at the sea, the marina and on land, and the seabed's profile.
##
##   godot --headless --path . tools/swim/probe.tscn [-- seed]   (a scene: the autoloads first)

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := int(args[0]) if args.size() > 0 else 1
	var t0 := Time.get_ticks_usec()
	var plan := GroundCoverage.make_plan(seed_value)
	var m: MacroMap = plan.macro
	print("SWIM map in %d ms" % ((Time.get_ticks_usec() - t0) / 1000))
	var st := [1.0, 0.0, Surf.params(1.0)[0], Surf.params(1.0)[1]]
	for z in [-400.0, 0.0, 600.0]:
		var cx := m.coast_x(z)
		for off in [2.0, 10.0, 40.0, 120.0, 400.0]:
			var p := Vector2(cx - off, z)
			var hs := []
			for k in 6:
				hs.append("%.2f" % SeaSurface.height(m, p, 10.0 + k * 1.5, st))
			var w := SwimWater.at(m, Vector3(p.x, 0.0, p.y), 10.0, st)
			print("SWIM sea z %.0f off %.0f: zone %d s %.1f h %s kind %s floor %.2f" % [z, off, m.zone_at(p), SeaSurface.shore_distance(m, p).x, ",".join(hs), str(w.get("kind", "-")), float(w.get("floor", 0.0))])
	var t1 := Time.get_ticks_usec()
	for k in 200:
		SeaSurface.height(m, Vector2(m.coast_x(0.0) - 60.0, float(k)), 3.0, st)
	print("SWIM SeaSurface.height %.1f us each" % ((Time.get_ticks_usec() - t1) / 200.0))
	if m.marina and m.marina.ok:
		var c: Vector2 = Geometry2D.convex_hull(m.marina.basin)[0] if false else Vector2.ZERO
		var sum := Vector2.ZERO
		for q in m.marina.basin:
			sum += q
		c = sum / float(m.marina.basin.size())
		var w2 := SwimWater.at(m, Vector3(c.x, 0.0, c.y), 0.0, st)
		print("SWIM marina centre %s: %s" % [str(c), str(w2)])
	print("SWIM land (0, 0): %s" % str(SwimWater.at(m, Vector3.ZERO, 0.0, st)))
	for zz in [-600.0, -300.0, 0.0, 300.0]:
		print("SWIM coast_x(%.0f) = %.1f" % [zz, m.coast_x(zz)])
	# The rec-park pools nearest the spawn (Parks' plans): an EYE for each.
	var found := 0
	for r in range(1, 30):
		for iz in range(-r, r + 1):
			for ix in range(-r, r + 1):
				if maxi(absi(ix), absi(iz)) != r or found >= 4:
					continue
				var pl := Parks.plan_for(plan, ix, iz)
				for f: Dictionary in pl.get("fac", []):
					if str(f.get("t", "")) == "pool":
						found += 1
						var c: Vector2 = f.c
						print("SWIM rec pool block (%d, %d) at (%.1f, %.1f) height %.2f long_x %s" % [ix, iz, c.x, c.y, plan.height_at(c), str((f.u as Vector2).x != 0.0)])
	if LandmarkMacArthurPark.enabled:
		var lay := LandmarkMacArthurPark.layout(plan)
		if lay.has("lake_bounds"):
			print("SWIM MacArthur lake bounds %s, height %.2f" % [str(lay.lake_bounds), plan.height_at((lay.lake_bounds as Rect2).get_center())])
	var prof := []
	for s in [0.0, 2.0, 3.5, 10.0, 26.0, 60.0, 200.0]:
		prof.append("%.0f:%.2f" % [s, SeaSurface.seabed(s)])
	print("SWIM seabed " + " ".join(prof))
	get_tree().quit()
