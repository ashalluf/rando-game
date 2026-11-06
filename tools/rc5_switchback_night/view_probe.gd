extends Node
## Scores every drawn hill road point by the city it overlooks (headless, a few minutes):
##   godot --headless --path . res://tools/rc5_switchback_night/view_probe.tscn
## From 1.9 m over the road, for each 10-degree azimuth, rays out to 6 km: a sample counts when it
## is CITY zone, visible (nothing nearer stands above its line) and below the eye by 0.5 degrees
## or more. Prints the best 25 points: road, point, bed, the best 90-degree window's azimuth (the
## refcam yaw) and count, and the distance to the nearest hairpin apex. ROADS=switchback limits it.

func _ready() -> void:
	await get_tree().process_frame
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var macro := MacroMap.new()
	macro.seed = city.world_seed
	city.free()
	macro.setup()
	var hr: HillRoads = macro.hill_roads
	var only_sb := OS.get_environment("ROADS") == "switchback"
	var results := []
	for ri in hr.roads.size():
		var road: Dictionary = hr.roads[ri]
		if road.get("drive", false) or not road.get("draw", true) or road.get("fire", false) or road.get("pad", false):
			continue
		if only_sb and not road.get("switchback", false):
			continue
		var pts: PackedVector2Array = road.points
		var hs: PackedFloat32Array = road.heights
		for k in range(0, pts.size(), 3):
			if hs[k] < float(OS.get_environment("MIN_Y") if OS.get_environment("MIN_Y") != "" else "-999"):
				continue
			var eye_y := hs[k] + 1.9
			var counts := []
			for a in 36:
				var az := a * 10.0
				var d := Vector2(-sin(deg_to_rad(az)), -cos(deg_to_rad(az)))
				var best := -90.0
				var n := 0
				var r := 15.0
				while r < 6000.0:
					var q := pts[k] + d * r
					var g := macro.height_at(q)
					var ang := rad_to_deg(atan2(g - eye_y, r))
					if ang >= best - 0.05 and ang < -0.5 and macro.zone_at(q) == MacroMap.Zone.CITY:
						n += 1
					best = maxf(best, ang)
					r *= 1.08
				counts.append(n)
			var top := 0
			var top_az := 0
			for a in 36:
				var s := 0
				for w in range(-4, 5):
					s += int(counts[(a + w + 36) % 36])
				if s > top:
					top = s
					top_az = a * 10
			var ests := 0
			for m in hr.mansions:
				if (m.pos as Vector2).distance_to(pts[k]) < 180.0 and float(m.height) > hs[k] - 2.0:
					ests += 1
			results.append([top, ri, String(road.name), pts[k], hs[k], top_az, ests])
	results.sort_custom(func(x, y): return x[0] > y[0])
	for i in mini(40, results.size()):
		var e: Array = results[i]
		print("VIEWPT %d road %d %s at %.1f,%.1f y %.1f yaw %d estates_above %d" % [e[0], e[1], e[2], e[3].x, e[3].y, e[4], e[5], e[6]])
	get_tree().quit()
