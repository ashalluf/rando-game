extends SceneTree
func _initialize() -> void:
	var macro := MacroMap.new()
	macro.seed = 1337
	macro.setup()
	var ch: CoastHighway = macro.coast_highway
	for r in macro.hill_roads.roads:
		if r.name == "Pacific Coast Highway":
			var pts: PackedVector2Array = r.points
			for i in pts.size():
				if pts[i].y < ch.z_south + 30.0:
					print("pch z %.0f h %.2f bench %.2f d %.1f" % [pts[i].y, r.heights[i], ch.bench_y(pts[i].y), pts[i].x - macro.coast_x(pts[i].y)])
	var probes: Array[Vector2] = []
	for k in 40:
		var zz := lerpf(ch.z_north - 400.0, ch.z_south + 400.0, float(k) / 39.0)
		probes.append(Vector2(macro.coast_x(zz) + CoastHighway.REACH + CoastHighway.REACH_FADE + 5.0 + float(k % 4) * 60.0, zz))
		probes.append(Vector2(macro.coast_x(zz) + 40.0, ch.z_south + 5.0 + float(k) * 9.0))
	var with := PackedFloat32Array()
	for p in probes:
		with.append(macro.raw_height_at(p) + macro.relief_at(p))
	macro.coast_highway = null
	for i in probes.size():
		var v := macro.raw_height_at(probes[i]) + macro.relief_at(probes[i])
		if absf(v - with[i]) > 0.001:
			print("moved ", probes[i], " d ", probes[i].x - macro.coast_x(probes[i].y), " ", with[i], " -> ", v)
	quit()
