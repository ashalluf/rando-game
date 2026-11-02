extends SceneTree
## Lists candidate eyes for the canyon_road refcam: points on the switchbacks and Valley Vista Dr
## with an estate near and the ground falling toward the basin (south, +z). Headless, seconds:
##   godot --headless --path . --script tools/rc2_canyon_road/probe.gd

func _initialize() -> void:
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var macro := MacroMap.new()
	macro.seed = city.world_seed
	var plan := CityPlan.new()
	plan.seed = macro.seed
	for key in ["block_size_range", "street_width", "avenue_width", "sidewalk_width", "downtown_radius", "midtown_radius"]:
		plan.set(key, city.get(key))
	plan.macro = macro
	city.free()
	macro.setup()
	var hr: HillRoads = macro.hill_roads
	for r: Dictionary in hr.roads:
		var nm := String(r.name)
		if not (nm.begins_with("Switchback") or nm.begins_with("Valley Vista") or nm.begins_with("Canyon") or nm.begins_with("Estates") or nm == "Sunset Drive"):
			continue
		var pts: PackedVector2Array = r.points
		var hs: PackedFloat32Array = r.heights
		for i in range(0, pts.size(), 3):
			var p := pts[i]
			# the drop toward the basin: ground 150 m and 400 m south
			var g150 := plan.height_at(p + Vector2(0, 150))
			var g400 := plan.height_at(p + Vector2(0, 400))
			var near_est := 999.0
			var est_pos := Vector2.ZERO
			for m: Dictionary in hr.mansions:
				var d := (m.pos as Vector2).distance_to(p)
				if d < near_est:
					near_est = d
					est_pos = m.pos
			var drop := hs[i] - minf(g150, g400)
			if drop > 25.0 and near_est < 90.0:
				print("CAND %-16s i %3d p %7.1f %7.1f bed %6.1f drop150 %5.1f drop400 %5.1f est %4.1f at %7.1f %7.1f" % [nm, i, p.x, p.y, hs[i], hs[i] - g150, hs[i] - g400, near_est, est_pos.x, est_pos.y])
	quit()
