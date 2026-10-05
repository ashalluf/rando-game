extends SceneTree
## Ridges probe (Ridges): the summits, the antenna farm, the fire roads and gates, the tanks, the
## lookout and domes, the substation and every tower of both lines with its span and clearance.
## Headless, seconds:
##   godot --headless --path . --script tools/ridges/probe.gd     (SEED=n another seed; OUT=map.png
##   also draws them over a hillshade of REGION=x0,z0,x1,z1, RES pixels on the long side)
func _initialize() -> void:
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	var t0 := Time.get_ticks_msec()
	var macro := MacroMap.new()
	macro.seed = sd
	macro.setup()
	var t1 := Time.get_ticks_msec()
	var plan := CityPlan.new()
	plan.seed = sd
	plan.macro = macro
	var r := Ridges.of(plan)
	print("setup %d ms, lines %d ms" % [t1 - t0, Time.get_ticks_msec() - t1])
	if r == null:
		print("no ridges")
		quit()
		return
	for i in mini(r.summits.size(), 8):
		var s: Array = r.summits[i]
		print("summit %d (%.0f, %.0f) %.0f m region %d" % [i, s[0].x, s[0].y, s[1], s[2]])
	print("farm ", r.farm)
	for m in r.masts:
		print("  mast %s kind %d h %.0f guys %d dishes %d" % [m.id, m.kind, m.h, m.guys.size(), m.dishes.size()])
	for s in r.sites:
		print("  site %s kind %d (%.0f, %.0f) base %.1f r %.1f h %.1f" % [s.id, s.kind, s.pos.x, s.pos.y, s.base, s.r, s.h])
	var total := 0.0
	for ri in r.fire_roads:
		var road: Dictionary = macro.hill_roads.roads[ri]
		var pts: PackedVector2Array = road.points
		var len := 0.0
		for i in range(1, pts.size()):
			len += pts[i].distance_to(pts[i - 1])
		total += len
		print("  fire road %s %d pts %.0f m from (%.0f, %.0f) to (%.0f, %.0f) h %.0f..%.0f" % [road.name, pts.size(), len, pts[0].x, pts[0].y, pts[-1].x, pts[-1].y, road.heights[0], road.heights[-1]])
	print("fire roads %.1f km, gates %d" % [total / 1000.0, r.gates.size()])
	print("substation ", r.substation.get("rect", "-"), " block ", r.substation.get("block", "-"))
	for li in r.lines.size():
		var line: Dictionary = r.lines[li]
		print("line %s: %d towers" % [line.name, line.towers.size()])
		var prev: Vector2 = r.substation.gantries[line.gantry].pos
		for k in line.towers.size():
			var t: Dictionary = r.towers[line.towers[k]]
			var ends: Array = r.span_ends(line, k)
			var low := INF
			var a: Array = ends[0]
			var b: Array = ends[1]
			for w in 6:
				var pts := Ridges.wire(a[w], b[w], 20)
				for q in pts:
					low = minf(low, q.y - r._ground(Vector2(q.x, q.z)))
			var feet: Array = t.legs
			var ext: float = t.base - minf(minf(feet[0], feet[1]), minf(feet[2], feet[3]))
			print("  t%d (%.0f, %.0f) %s kind %d h %.0f base %.1f ext %.1f span %.0f clear %.1f" % [t.id, t.pos.x, t.pos.y,
				MacroMap.zone_name(macro.zone_at(t.pos)), t.kind, t.h, t.base, ext, prev.distance_to(t.pos), low])
			prev = t.pos
	var claimed := 0
	for ix in range(20, 60):
		for iz in range(-10, 60):
			plan.lots(ix, iz)
	for k in r.claimed_cells:
		claimed += (r.claimed_cells[k] as Array).size()
	print("claimed cells %d in %d blocks" % [claimed, r.claimed_cells.size()])
	if OS.get_environment("OUT") != "":
		_draw(macro, r)
	quit()


func _draw(macro: MacroMap, r: Ridges) -> void:
	var reg := [-1500.0, -5500.0, 8000.0, 4500.0]
	if OS.get_environment("REGION") != "":
		var parts := OS.get_environment("REGION").split(",")
		for i in 4:
			reg[i] = parts[i].to_float()
	var res := int(OS.get_environment("RES")) if OS.get_environment("RES") != "" else 900
	var span := Vector2(reg[2] - reg[0], reg[3] - reg[1])
	var step := maxf(span.x, span.y) / float(res)
	var w := int(span.x / step)
	var h := int(span.y / step)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var hts := PackedFloat32Array()
	hts.resize(w * h)
	for y in h:
		for x in w:
			hts[y * w + x] = macro.height_at(Vector2(reg[0] + (x + 0.5) * step, reg[1] + (y + 0.5) * step))
	for y in h:
		for x in w:
			var hx := hts[y * w + mini(x + 1, w - 1)] - hts[y * w + maxi(x - 1, 0)]
			var hy := hts[mini(y + 1, h - 1) * w + x] - hts[maxi(y - 1, 0) * w + x]
			var n := Vector3(-hx, 2.0 * step, -hy).normalized()
			var l := clampf(n.dot(Vector3(-0.5, 0.7, -0.5).normalized()), 0.0, 1.0)
			var c := Color(0.35 + 0.5 * l, 0.34 + 0.48 * l, 0.3 + 0.42 * l)
			var zone := macro.zone_at(Vector2(reg[0] + (x + 0.5) * step, reg[1] + (y + 0.5) * step))
			if zone == MacroMap.Zone.CITY:
				c = c.lerp(Color(0.6, 0.6, 0.65), 0.5)
			elif zone == MacroMap.Zone.OCEAN:
				c = Color(0.1, 0.2, 0.35)
			img.set_pixel(x, y, c)
	var to_px := func(p: Vector2) -> Vector2i:
		return Vector2i(int((p.x - reg[0]) / step), int((p.y - reg[1]) / step))
	for road: Dictionary in macro.hill_roads.roads:
		var pts: PackedVector2Array = road.points
		var col := Color(1, 0.85, 0.3) if road.get("fire", false) else (Color(1, 0, 1) if road.get("pad", false) else Color(0.15, 0.15, 0.15))
		for i in range(1, pts.size()):
			for k in 8:
				var px: Vector2i = to_px.call(pts[i - 1].lerp(pts[i], k / 8.0))
				if px.x >= 0 and px.y >= 0 and px.x < w and px.y < h:
					img.set_pixelv(px, col)
	for li in r.lines.size():
		var line: Dictionary = r.lines[li]
		var prev: Vector2 = r.substation.gantries[line.gantry].pos
		for ti: int in line.towers:
			var p: Vector2 = r.towers[ti].pos
			for k in 30:
				var px: Vector2i = to_px.call(prev.lerp(p, k / 30.0))
				if px.x >= 0 and px.y >= 0 and px.x < w and px.y < h:
					img.set_pixelv(px, Color(0.9, 0.1, 0.1))
			var tp: Vector2i = to_px.call(p)
			img.fill_rect(Rect2i(tp - Vector2i(2, 2), Vector2i(5, 5)), Color(0, 0, 0))
			prev = p
	for s: Dictionary in r.sites:
		var tp: Vector2i = to_px.call(s.pos)
		img.fill_rect(Rect2i(tp - Vector2i(3, 3), Vector2i(7, 7)), Color(0, 0.6, 0.2) if s.kind == Ridges.Site.TANK else Color(0.2, 0.4, 1))
	for m: Dictionary in r.masts:
		var tp: Vector2i = to_px.call(m.pos)
		img.fill_rect(Rect2i(tp - Vector2i(2, 2), Vector2i(5, 5)), Color(1, 0, 0))
	for g: Dictionary in r.gates:
		var tp: Vector2i = to_px.call(g.pos)
		img.fill_rect(Rect2i(tp - Vector2i(2, 2), Vector2i(5, 5)), Color(1, 1, 1))
	img.save_png(OS.get_environment("OUT"))
	print("map ", OS.get_environment("OUT"))
