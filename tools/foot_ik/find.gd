extends Node3D
## Finds places for the foot-placement stills (headless, seconds after the map's setup):
## the kerb of block FEET_BLOCK=ix,iz (default 0,0), the steepest city pavements (relief) and
## hill-road shoulders with a walkable grade, each with a FEET_AT for tools/foot_ik/stage.gd.
##   godot --headless --path . tools/foot_ik/find.tscn

func _ready() -> void:
	await get_tree().process_frame
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
	var b := OS.get_environment("FEET_BLOCK").split_floats(",") if OS.get_environment("FEET_BLOCK") != "" else PackedFloat64Array([0, 0])
	var ix := int(b[0])
	var iz := int(b[1])
	var x := plan.road_pos(CityPlan.AXIS_X, ix) + plan.road_width(CityPlan.AXIS_X, ix) * 0.5
	var z := (plan.road_pos(CityPlan.AXIS_Z, iz) + plan.road_pos(CityPlan.AXIS_Z, iz + 1)) * 0.5
	print("KERB block %d,%d: FEET_AT=%.1f,%.1f (west kerb at x %.2f)" % [ix, iz, x + 1.2, z, x])
	# City pavements: the steepest relief within 2 km of the spawn.
	var best: Array = []
	for gx in range(-40, 41):
		for gz in range(-40, 41):
			var p := Vector2(gx * 50.0, gz * 50.0)
			if plan.zone_at(p) != MacroMap.Zone.CITY:
				continue
			var e := 2.0
			var g := Vector2(plan.height_at(p + Vector2(e, 0)) - plan.height_at(p - Vector2(e, 0)),
				plan.height_at(p + Vector2(0, e)) - plan.height_at(p - Vector2(0, e))) / (2.0 * e)
			best.append([g.length(), p])
	best.sort_custom(func(a, c): return a[0] > c[0])
	for i in mini(6, best.size()):
		print("CITY grade %.1f %% at FEET_AT=%.1f,%.1f" % [best[i][0] * 100.0, best[i][1].x, best[i][1].y])
	# Hill-road shoulders: 5 m off a kept road, a grade of 15-35 %.
	var hr: HillRoads = macro.hill_roads
	var found := 0
	for road in hr.roads:
		if road.get("drive", false) or road.get("pad", false):
			continue
		var pts: PackedVector2Array = road.points
		for k in range(4, pts.size() - 4, 9):
			var d := (pts[k + 1] - pts[k]).normalized()
			for side in [-1.0, 1.0]:
				var p: Vector2 = pts[k] + Vector2(-d.y, d.x) * 7.0 * float(side)
				var e := 1.5
				var g := Vector2(plan.height_at(p + Vector2(e, 0)) - plan.height_at(p - Vector2(e, 0)),
					plan.height_at(p + Vector2(0, e)) - plan.height_at(p - Vector2(0, e))) / (2.0 * e)
				if g.length() > 0.15 and g.length() < 0.35 and found < 10:
					found += 1
					print("HILL grade %.0f %% at FEET_AT=%.1f,%.1f (road %s, h %.1f)" % [g.length() * 100.0, p.x, p.y, road.get("name", "?"), plan.height_at(p)])
	get_tree().quit()
