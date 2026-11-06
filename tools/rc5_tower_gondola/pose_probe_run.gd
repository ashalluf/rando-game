extends RefCounted

func run(tree: SceneTree) -> void:
	var id := OS.get_environment("TOWER") if OS.get_environment("TOWER") != "" else "dt_park_c"
	var si := int(OS.get_environment("SITE"))
	var s: Dictionary = TowerGondolas.landmark_sites(id, 1337).hung[si]
	var a: Vector2 = LandmarkDowntown.anchor(id)
	var t0 := float(OS.get_environment("T0"))
	var t1 := float(OS.get_environment("T1")) if OS.get_environment("T1") != "" else 20000.0
	var dt := float(OS.get_environment("DT")) if OS.get_environment("DT") != "" else 50.0
	var y0 := float(OS.get_environment("Y0")) if OS.get_environment("Y0") != "" else -INF
	var y1 := float(OS.get_environment("Y1")) if OS.get_environment("Y1") != "" else INF
	print("SITE %s anchor %s m %s n %s lanes %s top %.1f bottom %.1f roof %.1f" % [id, a, s.m, s.n, s.lanes, s.top, s.bottom, s.roof])
	var t := t0
	while t <= t1:
		var p := TowerGondolas.pose_at(s, t)
		var c: Vector3 = Vector3(a.x, 0, a.y) + (s.m as Vector3) + (s.t as Vector3) * float(p.lane) + (s.n as Vector3) * TowerGondolas.GAP
		if float(p.y) >= y0 and float(p.y) <= y1:
			print("T %.0f lane %.1f y %.1f moving %d step %.2f washed %.1f cradle %.1f,%.1f" % [t, p.lane, p.y, p.moving, p.step, p.washed, c.x, c.z])
		t += dt
	tree.quit()
