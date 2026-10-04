extends Node
## Counts and measures the hill roads and estates in seconds, without building a city:
##   godot --headless --path . res://tools/hill_road_probe/hill_road_probe.tscn
## Prints the roads kept (and how many points each kept of its walk), the estates (all, and on
## the front range: north of z -700), the hairpins, and the share of CARVED ground steeper than
## 60 degrees - every 4 m cell within a road's or a pad's bank reach where the carve moved the
## ground by more than 0.25 m, its slope from height_at() 2 m either way. That share is the
## cut-bank check of roadmap #17 (0.6 % when it landed); a road that cannot be graded shows up as
## sheer walls in it. OUT=map.png also writes a slope map of REGION (default the front range,
## -1800,-2400,2600,-700; north up): green under 25 degrees, yellow to 35, orange to 45, red
## past, roads black, pads blue. STEEP=0 skips the steep-share pass (it takes a minute).

func _ready() -> void:
	await get_tree().process_frame
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var macro := MacroMap.new()
	var seed_env := OS.get_environment("SEED")
	macro.seed = int(seed_env) if seed_env != "" else city.world_seed
	city.free()
	var t0 := Time.get_ticks_msec()
	macro.setup()
	print("SETUP %d ms" % (Time.get_ticks_msec() - t0))
	var hr: HillRoads = macro.hill_roads
	var kept := 0
	var front_roads := 0
	var length := 0.0
	for road in hr.roads:
		var pts: PackedVector2Array = road.points
		if pts.size() >= 2:
			kept += 1
			var l := 0.0
			for i in pts.size() - 1:
				l += pts[i].distance_to(pts[i + 1])
			length += l
			if pts[0].y < -700.0 and pts[0].y > -2600.0:
				front_roads += 1
			print("ROAD %-24s kept %3d of %3d points, %5.0f m, %s" % [road.name, pts.size(), (road.planned_points as PackedVector2Array).size(), l,
				"hairpins %d" % int(road.get("hairpins", 0))])
	var front := 0
	for m in hr.mansions:
		if (m.pos as Vector2).y < -700.0 and (m.pos as Vector2).y > -2600.0:
			front += 1
	print("COUNT %d roads (%d kept, %d on the front range), %.1f km, %d estates (%d on the front range)" % [hr.roads.size(), kept, front_roads, length / 1000.0, hr.mansions.size(), front])
	if OS.get_environment("STEEP") != "0":
		_steep(macro, hr)
	var out := OS.get_environment("OUT")
	if out != "":
		_map(macro, hr, out)
	get_tree().quit()


func _steep(macro: MacroMap, hr: HillRoads) -> void:
	var seen := {}
	var carved := 0
	var steep := 0
	var cell := 4.0
	var spots: Array = []
	for road in hr.roads:
		var pts: PackedVector2Array = road.points
		var reach: float = road.width * 0.5 + HillRoads.BANK_REACH
		for i in pts.size() - 1:
			spots.append([pts[i], pts[i + 1], reach])
	for m in hr.mansions:
		spots.append([m.pos, m.pos, HillRoads.PAD_RADIUS + HillRoads.BANK_REACH])
	for s: Array in spots:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var r: float = s[2]
		var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * r
		var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * r
		for cx in range(floori(lo.x / cell), floori(hi.x / cell) + 1):
			for cz in range(floori(lo.y / cell), floori(hi.y / cell) + 1):
				var key := Vector2i(cx, cz)
				if seen.has(key):
					continue
				var p := Vector2((cx + 0.5) * cell, (cz + 0.5) * cell)
				if p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)) > r:
					continue
				seen[key] = true
				var raw := macro.raw_height_at(p)
				if raw <= 0.5:
					continue
				var natural := raw + macro.relief_at(p)
				var h := macro.height_at(p)
				if absf(h - natural) < 0.25:
					continue
				carved += 1
				var gx := (macro.height_at(p + Vector2(2.0, 0.0)) - macro.height_at(p - Vector2(2.0, 0.0))) / 4.0
				var gz := (macro.height_at(p + Vector2(0.0, 2.0)) - macro.height_at(p - Vector2(0.0, 2.0))) / 4.0
				if Vector2(gx, gz).length() > tan(deg_to_rad(60.0)):
					steep += 1
	print("STEEP %d of %d carved cells steeper than 60 degrees (%.2f %%)" % [steep, carved, 100.0 * steep / maxf(carved, 1.0)])


func _map(macro: MacroMap, hr: HillRoads, out: String) -> void:
	var reg := [-1800.0, -2400.0, 2600.0, -700.0]
	var r := OS.get_environment("REGION")
	if r != "":
		var parts := r.split(",")
		for i in 4:
			reg[i] = parts[i].to_float()
	var step := float(OS.get_environment("STEP")) if OS.get_environment("STEP") != "" else 8.0
	var w := int((reg[2] - reg[0]) / step)
	var h := int((reg[3] - reg[1]) / step)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var hist := [0, 0, 0, 0]
	for y in h:
		for x in w:
			var p := Vector2(reg[0] + (x + 0.5) * step, reg[1] + (y + 0.5) * step)
			var gx := (macro.height_at(p + Vector2(step * 0.5, 0.0)) - macro.height_at(p - Vector2(step * 0.5, 0.0))) / step
			var gz := (macro.height_at(p + Vector2(0.0, step * 0.5)) - macro.height_at(p - Vector2(0.0, step * 0.5))) / step
			var deg := rad_to_deg(atan(Vector2(gx, gz).length()))
			var c := Color(0.35, 0.7, 0.35)
			var k := 0
			if macro.raw_height_at(p) <= 0.5:
				c = Color(0.8, 0.8, 0.8)
				k = -1
			elif deg > 45.0:
				c = Color(0.8, 0.2, 0.15)
				k = 3
			elif deg > 35.0:
				c = Color(0.95, 0.55, 0.15)
				k = 2
			elif deg > 25.0:
				c = Color(0.95, 0.85, 0.3)
				k = 1
			if k >= 0:
				hist[k] += 1
			# Contours every 50 m.
			var hh := macro.height_at(p)
			var band := fmod(hh, 50.0)
			var shade := 0.6 if (band < 50.0 * step / 25.0 * maxf(Vector2(gx, gz).length(), 0.2) and k >= 0) else 1.0
			img.set_pixel(x, y, c * shade)
	for m in hr.mansions:
		var q: Vector2 = m.pos
		var px := int((q.x - reg[0]) / step)
		var py := int((q.y - reg[1]) / step)
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if px + dx >= 0 and px + dx < w and py + dy >= 0 and py + dy < h:
					img.set_pixel(px + dx, py + dy, Color(0.15, 0.3, 0.95))
	var lines: Array = []
	for wp in hr.debug_walks:
		lines.append([wp, Color(0.9, 0.1, 0.9)])
	for road in hr.roads:
		lines.append([road.points, Color.BLACK])
	for line: Array in lines:
		var pts: PackedVector2Array = line[0]
		for i in pts.size() - 1:
			var n := int(pts[i].distance_to(pts[i + 1]) / (step * 0.5)) + 1
			for k in n + 1:
				var q := pts[i].lerp(pts[i + 1], float(k) / n)
				var px := int((q.x - reg[0]) / step)
				var py := int((q.y - reg[1]) / step)
				if px >= 0 and px < w and py >= 0 and py < h:
					img.set_pixel(px, py, line[1])
	img.save_png(out)
	var tot := float(hist[0] + hist[1] + hist[2] + hist[3])
	print("SLOPES on the hills: <25 %.0f %%, 25-35 %.0f %%, 35-45 %.0f %%, >45 %.0f %%" % [100 * hist[0] / tot, 100 * hist[1] / tot, 100 * hist[2] / tot, 100 * hist[3] / tot])
