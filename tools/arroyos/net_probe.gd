extends Node
## The arroyo network over a hillshade: OUT=a.png REGION=x0,z0,x1,z1 RES=800 [SNAP=1]
## Prints the network's size and how long it took.
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
	Arroyos.keep_debug = true
	var net := Arroyos.build_now(plan)
	var pts := 0
	for l: Dictionary in net.lines:
		pts += (l.pts as PackedVector2Array).size()
	print("NET %d lines, %d points (%.1f km), grid %s, %d range cells, %d ms" % [net.lines.size(), pts, pts * Arroyos.STEP / 1000.0, net.n, net.sampled, Time.get_ticks_msec() - t0])
	if OS.get_environment("OUT") == "":
		get_tree().quit()
		return
	var reg := OS.get_environment("REGION").split(",")
	var r := Rect2(reg[0].to_float(), reg[1].to_float(), reg[2].to_float() - reg[0].to_float(), reg[3].to_float() - reg[1].to_float())
	var res := int(OS.get_environment("RES")) if OS.get_environment("RES") != "" else 800
	var st := maxf(r.size.x, r.size.y) / res
	var w := int(r.size.x / st)
	var h := int(r.size.y / st)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var H := PackedFloat32Array()
	H.resize((w + 1) * (h + 1))
	for y in h + 1:
		for x in w + 1:
			H[y * (w + 1) + x] = plan.height_at(r.position + Vector2(x, y) * st)
	for y in h:
		for x in w:
			var gx := (H[y * (w + 1) + x + 1] - H[y * (w + 1) + x]) / st
			var gz := (H[(y + 1) * (w + 1) + x] - H[y * (w + 1) + x]) / st
			var s := clampf(0.62 - (gx + gz) * 0.12, 0.0, 1.0)
			var c := Color(s, s * 0.97, s * 0.9)
			if not net.acc.is_empty():
				var wp := r.position + Vector2(x, y) * st
				var ci := int((wp.x - net.origin.x) / Arroyos.CELL)
				var cj := int((wp.y - net.origin.y) / Arroyos.CELL)
				if ci >= 0 and cj >= 0 and ci < net.n.x and cj < net.n.y:
					var a := net.acc[cj * net.n.x + ci]
					if a > 0:
						c = c.lerp(Color(0.1, 0.6, 0.2), clampf(log(float(a)) / log(400.0), 0.0, 1.0) * 0.8)
			img.set_pixel(x, y, c)
	var snap := OS.get_environment("SNAP") == "1"
	var t1 := Time.get_ticks_msec()
	var refs := Arroyos.refs_in(net, r, 0.0)
	for ref in refs:
		var li := ref >> 16
		var pi := ref & 0xffff
		var p: Vector2 = net.lines[li].pts[pi]
		var c := Color(1, 0.2, 0.1)
		if snap:
			p = Arroyos.snapped(net, li, pi)
			c = Color(0.1, 0.4, 1)
		var q := (p - r.position) / st
		var wd: float = net.lines[li].w[pi] * 0.5 / st
		if wd <= 0.0:
			c = Color(0.9, 0.0, 0.9)
		for dy in range(-ceili(wd), ceili(wd) + 1):
			for dx in range(-ceili(wd), ceili(wd) + 1):
				var xx := int(q.x) + dx
				var yy := int(q.y) + dy
				if xx >= 0 and yy >= 0 and xx < w and yy < h and Vector2(dx, dy).length() <= maxf(wd, 1.0):
					img.set_pixel(xx, yy, c)
	print("SNAP %d points %d ms" % [refs.size(), Time.get_ticks_msec() - t1])
	img.save_png(OS.get_environment("OUT"))
	get_tree().quit()
