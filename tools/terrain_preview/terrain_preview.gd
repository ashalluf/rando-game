extends Node
## Top-down look at the mountains' shape in seconds, without building a city: samples
## MacroMap.height_at() over a region and writes a hillshade (sun from the north-west, 45
## degrees up) with the drainage field (MacroMap.last_drain) tinted over it - gullies blue, spur
## crests warm - so a change to the height field can be judged before any render.
##   OUT=hills.png REGION=x0,z0,x1,z1 RES=600 SHADE_ONLY=0 \
##     godot --headless --path . res://tools/terrain_preview/terrain_preview.tscn
## REGION defaults to the front and back ranges over the pass, -1800,-4800,2600,-700 (north up).
## RES is the long side in pixels. Prints the height range and the time it took. BENCH=1 also
## times MacroMap.setup(), the far ground's bake and one FULL hill chunk's worth of height_at().

func _ready() -> void:
	await get_tree().process_frame
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var t_setup := Time.get_ticks_msec()
	var macro := MacroMap.new()
	macro.seed = city.world_seed
	macro.setup()
	city.free()
	if OS.get_environment("PROBE") != "":
		for q in OS.get_environment("PROBE").split(";"):
			var xy := q.split(",")
			var pp := Vector2(xy[0].to_float(), xy[1].to_float())
			print("PROBE %s raw %.1f height %.1f zone %d" % [pp, macro.raw_height_at(pp), macro.height_at(pp), macro.zone_at(pp)])
	if macro.hill_roads:
		print("ROADS %d hill roads, %d estates" % [macro.hill_roads.roads.size(), macro.hill_roads.mansions.size()])
	if OS.get_environment("BENCH") == "1":
		var t_bake := Time.get_ticks_msec()
		macro.bake(Vector2.ZERO, 16000.0, 256)
		var t_grid := Time.get_ticks_usec()
		for j in 33:
			for i in 33:
				macro.height_at(Vector2(200.0 + i * 5.6, -1200.0 + j * 5.6))
		print("BENCH setup %d ms, bake %d ms, a FULL hill chunk's 33 x 33 heights %.1f ms" % [t_bake - t_setup,
			(t_grid / 1000) - t_bake, (Time.get_ticks_usec() - t_grid) / 1000.0])
	var reg := [-1800.0, -4800.0, 2600.0, -700.0]
	var r := OS.get_environment("REGION")
	if r != "":
		var parts := r.split(",")
		for i in 4:
			reg[i] = parts[i].to_float()
	var res := int(OS.get_environment("RES")) if OS.get_environment("RES") != "" else 600
	var shade_only := OS.get_environment("SHADE_ONLY") == "1"
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "terrain_preview.png"
	var span := Vector2(reg[2] - reg[0], reg[3] - reg[1])
	var step := maxf(span.x, span.y) / float(res)
	var w := int(span.x / step)
	var h := int(span.y / step)
	var t0 := Time.get_ticks_msec()
	var hts := PackedFloat32Array()
	var drains := PackedFloat32Array()
	hts.resize(w * h)
	drains.resize(w * h)
	var lo := 1e9
	var hi := -1e9
	for y in h:
		for x in w:
			var p := Vector2(reg[0] + (x + 0.5) * step, reg[1] + (y + 0.5) * step)
			var v := macro.height_at(p)
			hts[y * w + x] = v
			drains[y * w + x] = macro.last_drain
			lo = minf(lo, v)
			hi = maxf(hi, v)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var sun := Vector3(-1.0, 1.4, -1.0).normalized()
	for y in h:
		for x in w:
			var hx := hts[y * w + mini(x + 1, w - 1)] - hts[y * w + maxi(x - 1, 0)]
			var hz := hts[mini(y + 1, h - 1) * w + x] - hts[maxi(y - 1, 0) * w + x]
			var n := Vector3(-hx / (2.0 * step), 1.0, -hz / (2.0 * step)).normalized()
			var lit := clampf(n.dot(sun), 0.0, 1.0) * 0.85 + 0.15
			var elev := clampf((hts[y * w + x] - lo) / maxf(hi - lo, 1.0), 0.0, 1.0)
			var c := Color(lit, lit, lit)
			if not shade_only:
				var d := drains[y * w + x]
				c = c * Color(0.85 + 0.25 * elev, 0.85 + 0.15 * elev, 0.8)
				if d > 0.0:
					c = c.lerp(Color(0.15, 0.3, 0.75) * lit * 1.3, d * 0.6)
				else:
					c = c.lerp(Color(0.95, 0.7, 0.35) * lit, -d * 0.5)
			img.set_pixel(x, y, c)
	img.save_png(out)
	print("PREVIEW %s %dx%d, %.1f m a pixel, height %.0f..%.0f m, %d ms" % [out, w, h, step, lo, hi, Time.get_ticks_msec() - t0])
	get_tree().quit()
