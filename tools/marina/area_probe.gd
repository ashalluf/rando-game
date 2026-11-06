extends SceneTree
## Marina area probe: zones, districts and heights round the coast between Venice and the
## airport, the roads there, the freeways and landmarks nearby. Headless, seconds:
##   godot --headless --path . --script tools/marina/area_probe.gd   (X0,X1,Z0,Z1,STEP)
func _initialize() -> void:
	var macro := MacroMap.new()
	macro.seed = 1337
	macro.setup()
	var plan := CityPlan.new()
	plan.seed = 1337
	plan.macro = macro
	var x0 := float(OS.get_environment("X0")) if OS.get_environment("X0") != "" else -1000.0
	var x1 := float(OS.get_environment("X1")) if OS.get_environment("X1") != "" else -150.0
	var z0 := float(OS.get_environment("Z0")) if OS.get_environment("Z0") != "" else -500.0
	var z1 := float(OS.get_environment("Z1")) if OS.get_environment("Z1") != "" else 650.0
	var st := float(OS.get_environment("STEP")) if OS.get_environment("STEP") != "" else 40.0
	var zl := "CBOHAP"
	var dl := "DMSICBW" # check CityPlan.District order below
	print("districts: ", CityPlan.District.keys())
	var z := z0
	while z <= z1:
		var line := "%6.0f " % z
		var x := x0
		while x <= x1:
			var p := Vector2(x, z)
			var zn := macro.zone_at(p)
			var c := zl[zn]
			if zn == MacroMap.Zone.CITY:
				c = String(CityPlan.District.keys()[macro.district_at(p)]).substr(0, 1).to_lower()
			line += c
			x += st
		print(line, "   coast_x=%.0f bw=%.0f" % [macro.coast_x(z), macro.beach_width_at(z)])
		z += st
	print("roads X (x positions):")
	var i := plan._index_at(CityPlan.AXIS_X, x0)
	while plan.road_pos(CityPlan.AXIS_X, i) < x1:
		print("  ix=%d x=%.1f w=%.1f %s" % [i, plan.road_pos(CityPlan.AXIS_X, i), plan.road_width(CityPlan.AXIS_X, i), plan.road_name(CityPlan.AXIS_X, i)])
		i += 1
	print("roads Z:")
	i = plan._index_at(CityPlan.AXIS_Z, z0)
	while plan.road_pos(CityPlan.AXIS_Z, i) < z1:
		print("  iz=%d z=%.1f w=%.1f %s" % [i, plan.road_pos(CityPlan.AXIS_Z, i), plan.road_width(CityPlan.AXIS_Z, i), plan.road_name(CityPlan.AXIS_Z, i)])
		i += 1
	print("heights:")
	for zz in [-200.0, 0.0, 200.0, 400.0]:
		var hl := "  z=%.0f " % zz
		for xx in [-850.0, -800.0, -750.0, -700.0, -600.0, -500.0, -400.0, -300.0]:
			hl += "%.1f " % macro.height_at(Vector2(xx, zz))
		print(hl)
	for lm in Landmarks.all():
		var a: Vector2 = lm.anchor
		if a.x > x0 - 300 and a.x < x1 + 300 and a.y > z0 - 300 and a.y < z1 + 300:
			print("landmark ", lm.id, " ", a, " r=", lm.radius)
	for fr in macro.freeway.routes:
		var pts: PackedVector2Array = fr.points
		for j in range(0, pts.size(), 4):
			var q := pts[j]
			if q.x > x0 and q.x < x1 and q.y > z0 and q.y < z1:
				print("freeway ", fr.name, " ", q)
	for r in macro.hill_roads.roads if "roads" in macro.hill_roads else []:
		pass
	quit()
