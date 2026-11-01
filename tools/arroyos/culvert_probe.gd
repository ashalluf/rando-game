extends Node
## Debug: the field step of the chunks where drawn roads cross washes, without a city, and why a
## culvert was or was not made there; and the washes that do not run downhill.
func _ready() -> void:
	await get_tree().process_frame
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var plan := CityPlan.new()
	plan.seed = city.world_seed
	plan.block_size_range = city.block_size_range
	plan.street_width = city.street_width
	plan.avenue_width = city.avenue_width
	plan.sidewalk_width = city.sidewalk_width
	plan.downtown_radius = city.downtown_radius
	plan.midtown_radius = city.midtown_radius
	plan.macro = MacroMap.new()
	plan.macro.seed = plan.seed
	plan.macro.setup()
	city.free()
	var net := Arroyos.build_now(plan)
	var shown := 0
	for li in net.lines.size():
		var pts: PackedVector2Array = net.lines[li].pts
		var ws: PackedFloat32Array = net.lines[li].w
		var first := -1
		var last := -1
		for i in pts.size():
			if ws[i] > 0.0:
				last = i
				if first < 0:
					first = i
		if last - first < 4:
			continue
		var h0 := plan.macro.raw_height_at(pts[first])
		var h1 := plan.macro.raw_height_at(pts[last])
		if h1 >= h0 + 1.0 and shown < 6:
			shown += 1
			var prof := []
			for i in range(first, last + 1, maxi(1, (last - first) / 10)):
				prof.append("%.0f%s" % [plan.macro.raw_height_at(pts[i]), "" if ws[i] > 0 else "x"])
			print("UPHILL line %d n %d first %d last %d %.1f -> %.1f at %s .. %s: %s" % [li, pts.size(), first, last, h0, h1, pts[first].round(), pts[last].round(), " ".join(prof)])
	var hr := plan.macro.hill_roads
	var tried := 0
	var seen := {}
	for l: Dictionary in net.lines:
		if tried >= 8:
			break
		var pts: PackedVector2Array = l.pts
		for i in range(0, pts.size() - 1, 3):
			var b2 := pts[mini(i + 3, pts.size() - 1)]
			var hit := false
			for seg: Dictionary in hr.segments_in(Rect2(pts[i], Vector2.ZERO).expand(b2).grow(6.0)):
				if seg.draw and Geometry2D.segment_intersects_segment(pts[i], b2, seg.a, seg.b) != null:
					hit = true
			if not hit:
				continue
			var k := plan.block_index_at(pts[i])
			if seen.has(k):
				continue
			seen[k] = true
			tried += 1
			var ch := CityChunk.new()
			ch.plan = plan
			ch.ix = k.x
			ch.iz = k.y
			ch.level = CityChunk.Level.FULL
			ch._tile_n = 0
			var ab := ArroyoBuild.new()
			ab.ch = ch
			ArroyoBuild.debug = true
			while not ab._field():
				pass
			print("CHUNK %s zone %d segs %d culverts %d" % [k, plan.macro.zone_at(ch.owned_rect().get_center()), ab.segs.size(), ab.culverts.size()])
			ch.free()
			break
	get_tree().quit()
