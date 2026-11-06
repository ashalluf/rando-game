extends Node
## Lists the front range's switchback hairpins (headless, seconds):
##   godot --headless --path . res://tools/rc5_switchback_night/pin_probe.tscn
## A hairpin is where a switchback drive's heading turns past 150 degrees within 50 m. Prints the
## apex (x, z, bed y), the road, the side the outside faces, the estates within 160 m with their
## height over the apex, and how far the ground falls 300 m out from the outside edge.

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
	# GRID=x,z: height_at() on a 1 m grid 24 m round the point, with the nearest drawn road's
	# bed (its centre line's height) and the distance to that centre line.
	var gs := OS.get_environment("GRID")
	if gs != "":
		var gp := Vector2(float(gs.split(",")[0]), float(gs.split(",")[1]))
		var segs: Array = macro.hill_roads.segments_in(Rect2(gp - Vector2(40, 40), Vector2(80, 80)))
		for j in range(-12, 13, 2):
			var line := ""
			for i in range(-12, 13, 2):
				var q := gp + Vector2(i, j)
				var bd := INF
				var bed := 0.0
				for sg: Dictionary in segs:
					if not sg.get("draw", true) or sg.get("drive", false):
						continue
					var c := Geometry2D.get_closest_point_to_segment(q, sg.a, sg.b)
					var d := q.distance_to(c)
					if d < bd:
						bd = d
						var t := (c - (sg.a as Vector2)).length() / maxf((sg.b - sg.a).length(), 0.001)
						bed = lerpf(float(sg.ha), float(sg.hb), t)
				var h := plan.height_at(q)
				line += " %+5.1f" % (h - bed) if bd < 7.0 else "   .  "
			print("GRID %+3d %s" % [j, line])
		get_tree().quit()
		return
	# CHEV=x,z: RcSwitchback's chevrons within 200 m of the point.
	var chev := OS.get_environment("CHEV")
	if chev != "":
		var cp := Vector2(float(chev.split(",")[0]), float(chev.split(",")[1]))
		for c: Dictionary in RcSwitchback.chevrons(plan, Rect2(cp - Vector2(200, 200), Vector2(400, 400))):
			print("CHEV %.1f,%.1f y %.1f t %s o %s" % [c.pos.x, c.pos.y, c.y, str(c.t), str(c.o)])
		get_tree().quit()
		return
	var hr: HillRoads = macro.hill_roads
	var n := 0
	for ri in hr.roads.size():
		var road: Dictionary = hr.roads[ri]
		if not road.get("switchback", false) or road.get("drive", false):
			continue
		var pts: PackedVector2Array = road.points
		var hs: PackedFloat32Array = road.heights
		var i := 2
		while i < pts.size() - 2:
			# find j > i with turn > 150 deg and arc length < 50 m
			var d0 := (pts[i] - pts[i - 1]).normalized()
			var arc := 0.0
			var found := -1
			for j in range(i + 1, mini(pts.size() - 1, i + 30)):
				arc += pts[j].distance_to(pts[j - 1])
				if arc > 60.0:
					break
				var d1 := (pts[j + 1] - pts[j]).normalized()
				if d0.dot(d1) < -0.86:
					found = j
					break
			if found < 0:
				i += 1
				continue
			var mid := (i + found) / 2
			var apex := pts[mid]
			var centre := (pts[i] + pts[found]) * 0.5
			var out := (apex - centre).normalized()
			var edge: Vector2 = apex + out * float(road.width) * 0.5
			var g_out := macro.height_at(edge + out * 300.0)
			var ests := []
			for m in hr.mansions:
				var d: float = (m.pos as Vector2).distance_to(apex)
				if d < 160.0:
					ests.append("%d@%.0fm%+.0f" % [hr.mansions.find(m), d, float(m.height) - hs[mid]])
			print("PIN road %d %s apex %.1f,%.1f y %.1f out %.2f,%.2f (yaw %.0f) drop300 %.0f estates %s" % [
				ri, road.name, apex.x, apex.y, hs[mid], out.x, out.y, rad_to_deg(atan2(-out.x, -out.y)), hs[mid] - g_out, str(ests)])
			# The view: for every 15 degrees of azimuth, the highest terrain elevation angle seen from
			# 1.6 m over the outside edge out to 4 km (negative: the ground falls away - open).
			var eye_y := hs[mid] + 1.9
			var view := ""
			for az in range(0, 360, 15):
				var d := Vector2(-sin(deg_to_rad(az)), -cos(deg_to_rad(az)))
				var best := -90.0
				var r := 12.0
				while r < 4000.0:
					var g := macro.height_at(edge + d * r)
					best = maxf(best, rad_to_deg(atan2(g - eye_y, r)))
					r *= 1.12
				view += " %d:%.0f" % [az, best]
			print("VIEW %s" % view)
			n += 1
			i = found + 3
	var at_env := OS.get_environment("AT")
	if at_env != "":
		var a := Vector2(float(at_env.split(",")[0]), float(at_env.split(",")[1]))
		for ri in hr.roads.size():
			var road: Dictionary = hr.roads[ri]
			var pts: PackedVector2Array = road.points
			for k in pts.size():
				if pts[k].distance_to(a) < 160.0:
					print("PT road %d %s k %d %.1f,%.1f y %.1f w %.1f drive %s" % [ri, road.name, k, pts[k].x, pts[k].y, road.heights[k], road.width, road.get("drive", false)])
		for m in hr.mansions:
			if (m.pos as Vector2).distance_to(a) < 200.0:
				print("EST %d %.1f,%.1f y %.1f yaw %.0f road %d" % [hr.mansions.find(m), m.pos.x, m.pos.y, m.height, rad_to_deg(m.yaw), m.road])
	print("PINS %d" % n)
	get_tree().quit()
