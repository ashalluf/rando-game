extends Node
## The dry creek network (Arroyos) in seconds, headless: its size and build time, and EYE lines
## (still_shot.gd EYE=x,y,z,yaw,pitch) for the culverts where drawn hill roads cross a wash -
## from the road's shoulder looking down the wash, and from the air over it.
##   tools/arroyos/probe.tscn [AT=x,z RADIUS=m] [MAX=n]
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
	var t0 := Time.get_ticks_msec()
	var net := Arroyos.build_now(plan)
	var pts := 0
	for l: Dictionary in net.lines:
		pts += (l.pts as PackedVector2Array).size()
	print("NET %d washes, %.1f km, %d ms" % [net.lines.size(), pts * Arroyos.STEP / 1000.0, Time.get_ticks_msec() - t0])
	var at := Vector2.ZERO
	var radius := 1e9
	if OS.get_environment("AT") != "":
		var v := OS.get_environment("AT").split(",")
		at = Vector2(v[0].to_float(), v[1].to_float())
		radius = OS.get_environment("RADIUS").to_float() if OS.get_environment("RADIUS") != "" else 1500.0
	var most := int(OS.get_environment("MAX")) if OS.get_environment("MAX") != "" else 12
	var found := 0
	var hr := plan.macro.hill_roads
	for li in net.lines.size():
		if found >= most:
			break
		var line: PackedVector2Array = net.lines[li].pts
		for i in range(0, line.size() - 3, 3):
			var a := line[i]
			var b := line[i + 3]
			if a.distance_to(at) > radius:
				continue
			var hit := {}
			for seg: Dictionary in hr.segments_in(Rect2(a, Vector2.ZERO).expand(b).grow(6.0)):
				if seg.draw and Geometry2D.segment_intersects_segment(a, b, seg.a, seg.b) != null:
					hit = seg
			if hit.is_empty():
				continue
			var xx: Vector2 = Geometry2D.segment_intersects_segment(a, b, hit.a, hit.b)
			var hills := true
			for q: Vector2 in [xx + Vector2(80, 0), xx - Vector2(80, 0), xx + Vector2(0, 80), xx - Vector2(0, 80)]:
				hills = hills and plan.macro.zone_at(q) == MacroMap.Zone.HILLS
			if not hills:
				continue
			var x: Vector2 = Geometry2D.segment_intersects_segment(a, b, hit.a, hit.b)
			var rd: Vector2 = (hit.b - hit.a).normalized()
			var flow := (b - a).normalized()
			var shoulder := x - flow * 0.0 + Vector2(rd.y, -rd.x) * 0.0
			var road_y := plan.height_at(x)
			# On the road's downstream edge, looking down the wash.
			var eye := x + flow * (float(hit.width) * 0.5 + 0.5)
			var yaw := rad_to_deg(atan2(-flow.x, -flow.y))
			var down := line[mini(i + 12, line.size() - 1)]
			var drop := road_y - plan.height_at(down)
			var pitch := -rad_to_deg(atan2(drop, eye.distance_to(down)))
			print("CROSSING wash %d at %s road width %.1f fill %.1f  ROAD_EYE=%.1f,%.1f,%.1f,%.0f,%.0f  AIR_EYE=%.1f,%.1f,%.1f,%.0f,-50" % [li, x.round(), hit.width,
				road_y - plan.height_at(down), eye.x, road_y + 1.7, eye.y, yaw, pitch - 4.0,
				x.x - flow.x * 25.0, road_y + 45.0, x.y - flow.y * 25.0, yaw])
			found += 1
			break
	# The widest washes, from the air: 120 m down the wash and 80 m up, looking back up it.
	var best: Array = []
	for li in net.lines.size():
		var ws: PackedFloat32Array = net.lines[li].w
		var line: PackedVector2Array = net.lines[li].pts
		var run := 0
		for i in line.size():
			run = run + 1 if ws[i] > 4.0 else 0
			if run == 40 and line[i].distance_to(at) <= radius:
				best.append([li, i - 20])
				break
	for e: Array in best.slice(0, most):
		var line: PackedVector2Array = net.lines[e[0]].pts
		var p := Arroyos.snapped(net, e[0], e[1])
		var flow := (line[mini(e[1] + 3, line.size() - 1)] - line[maxi(e[1] - 3, 0)]).normalized()
		var cam := p + flow * 110.0
		var y := plan.height_at(cam) + 70.0
		var yaw := rad_to_deg(atan2(flow.x, flow.y))
		var pitch := -rad_to_deg(atan2(y - plan.height_at(p), 110.0))
		print("WASH %d at %s width %.1f  AIR_EYE=%.1f,%.1f,%.1f,%.0f,%.0f  LOW_EYE=%.1f,%.1f,%.1f,%.0f,-8" % [e[0], p.round(), net.lines[e[0]].w[e[1]], cam.x, y, cam.y, yaw, pitch,
			p.x + flow.x * 25.0, plan.height_at(p + flow * 25.0) + 4.0, p.y + flow.y * 25.0, yaw])
	get_tree().quit()
