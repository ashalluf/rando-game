extends RefCounted
## The body of probe.gd (loaded once the autoloads exist).

func run(tree: SceneTree) -> void:
	var plan: CityPlan = load("res://tools/car_park/probe_run.gd").make_plan()
	var at := Vector2(1735.0, 360.0)
	if OS.get_environment("AT") != "":
		var v := OS.get_environment("AT").split(",")
		at = Vector2(float(v[0]), float(v[1]))
	var s := CarPark.nearest(plan, at, 400.0)
	if s.is_empty():
		print("no car park near ", at)
		return
	var lay: Dictionary = s.layout
	var f: Dictionary = s.frame
	var gy := CarPark.ground_y(plan, s)
	var roof := gy + CarPark.FLOOR * float(lay.decks)
	print("CP %s site %s side %d decks %d ground %.2f roof %.2f frame a %s n %s" % [s.name, s.site, s.side, lay.decks, gy, roof, f.a, f.n])
	print("CP u0 %.1f v0 %.1f ls %.1f ds %.1f r0 %.1f r1 %.1f m1 %.1f s0 %.1f s1 %.1f" % [lay.u0, lay.v0, lay.ls, lay.ds, lay.r0, lay.r1, lay.m1, lay.s0, lay.s1])
	for b in lay.bands:
		print("CP band ", b)
	var path := CarPark.drive_path(plan, s)
	for i in range(maxi(0, path.size() - 4), path.size()):
		print("CP path ", path[i])
	for u: float in [0.0, float(lay.ls)]:
		for v: float in [0.0, float(lay.ds)]:
			print("CP corner u %.1f v %.1f -> %s" % [u, v, CarPark.world_xz(s, float(lay.u0) + u, float(lay.v0) + v)])
