extends Node
## The reservoir in seconds, headless (no city): prints the fitted level, dam, spillway, trail
## and timings, and with OUT= writes a contour map of the carved ground round it (north up, a
## line every 10 m, white every 50 m; water blue, the dam's arc red, the spillway orange, the
## trail yellow). SEED= another seed; NATURAL=1 draws the ground without the carve.
##   OUT=res.png godot --headless --path . res://tools/reservoir/probe.tscn

func _ready() -> void:
	await get_tree().process_frame
	var macro := MacroMap.new()
	macro.seed = int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	var t0 := Time.get_ticks_msec()
	macro.setup()
	print("SETUP %d ms" % (Time.get_ticks_msec() - t0))
	var res: Reservoir = macro.reservoir
	if res == null:
		print("NO RESERVOIR")
		get_tree().quit()
		return
	var t1 := Time.get_ticks_usec()
	var tmp := Reservoir.new()
	tmp.build(macro)
	print("BUILD %.0f ms" % ((Time.get_ticks_usec() - t1) / 1000.0))
	print("LEVEL %.1f  crest %.1f  toe %.1f  dam height %.1f  crest length %.1f m  base %.1f m  ends %.3f %.3f  centre %s" % [res.level, res.crest, res.toe, res.crest - res.toe, res.crest_length(), res.dam_base, res.dam_a0, res.dam_a1, res.dam_centre])
	print("LAKE area %.0f m2 (%.1f ha)  centre %s" % [res.wet_area(), res.wet_area() / 10000.0, res.lake_centre()])
	var tl := 0.0
	for line in res.trail:
		tl += Reservoir._length(line)
	print("TRAIL %d lines, %.0f m" % [res.trail.size(), tl])
	print("SPILL %s floors %s" % [res.spill, res.spill_floor])
	var t2 := Time.get_ticks_usec()
	for k in 2000:
		macro.raw_height_at(Vector2(-700.0 + (k % 50) * 9.0, -1600.0 + (k / 50) * 9.0))
	print("RAW 2000 heights in the box %.1f ms" % ((Time.get_ticks_usec() - t2) / 1000.0))
	for q in OS.get_environment("PROBE").split(";", false):
		var xy := q.split(",")
		var pp := Vector2(xy[0].to_float(), xy[1].to_float())
		print("PROBE %s raw %.1f height %.1f wet %s" % [pp, macro.raw_height_at(pp), macro.height_at(pp), res.wet(pp)])
	# Walls: 2 m cells in the outer box where the carve moved the ground by over a metre and the
	# slope is over 60 degrees, and the steepest.
	var steep := 0
	var nat_steep := 0
	var moved := 0
	var worst := Vector3.ZERO
	var ob: Rect2 = res._outer
	var stp := 4.0
	var sx := int(ob.size.x / stp)
	var sz := int(ob.size.y / stp)
	for j in sz:
		for i in sx:
			var p := ob.position + Vector2(i * stp, j * stp)
			var hh := macro.height_at(p)
			macro.reservoir = null
			var nat := macro.height_at(p)
			macro.reservoir = res
			if absf(hh - nat) < 1.0:
				continue
			moved += 1
			var gx := (macro.height_at(p + Vector2(2.0, 0.0)) - macro.height_at(p - Vector2(2.0, 0.0))) / 4.0
			var gz := (macro.height_at(p + Vector2(0.0, 2.0)) - macro.height_at(p - Vector2(0.0, 2.0))) / 4.0
			var sl := Vector2(gx, gz).length()
			if sl > 1.73:
				steep += 1
			macro.reservoir = null
			var ngx := (macro.height_at(p + Vector2(2.0, 0.0)) - macro.height_at(p - Vector2(2.0, 0.0))) / 4.0
			var ngz := (macro.height_at(p + Vector2(0.0, 2.0)) - macro.height_at(p - Vector2(0.0, 2.0))) / 4.0
			macro.reservoir = res
			if Vector2(ngx, ngz).length() > 1.73:
				nat_steep += 1
			if sl > worst.z:
				worst = Vector3(p.x, p.y, sl)
	print("WALLS %d of %d carved cells over 60 degrees (%d before the carve); steepest %.0f degrees at (%.0f, %.0f)" % [steep, moved, nat_steep, rad_to_deg(atan(worst.z)), worst.x, worst.y])
	var out := OS.get_environment("OUT")
	if out != "":
		var step := 2.5
		var reg := Reservoir.BOX.grow(60.0)
		var w := int(reg.size.x / step)
		var h := int(reg.size.y / step)
		var hs := PackedFloat32Array()
		hs.resize(w * h)
		var natural := OS.get_environment("NATURAL") == "1"
		var lo := 1e9
		var hi := -1e9
		var keep: Reservoir = macro.reservoir
		if natural:
			macro.reservoir = null
		for y in h:
			for x in w:
				var v := macro.height_at(reg.position + Vector2((x + 0.5) * step, (y + 0.5) * step))
				hs[y * w + x] = v
				lo = minf(lo, v)
				hi = maxf(hi, v)
		macro.reservoir = keep
		var img := Image.create(w, h, false, Image.FORMAT_RGB8)
		for y in h:
			for x in w:
				var p := reg.position + Vector2((x + 0.5) * step, (y + 0.5) * step)
				var v := hs[y * w + x]
				var c := Color(0.25, 0.4, 0.2).lerp(Color(0.9, 0.8, 0.55), clampf((v - lo) / maxf(hi - lo, 1.0), 0.0, 1.0))
				if not natural and res.wet(p) and v < res.level:
					c = Color(0.15, 0.3, 0.6).lerp(Color(0.05, 0.1, 0.3), clampf((res.level - v) / 40.0, 0.0, 1.0))
				var band := floori(v / 10.0)
				for o in [Vector2i(1, 0), Vector2i(0, 1)]:
					var nb := hs[mini(y + o.y, h - 1) * w + mini(x + o.x, w - 1)]
					if floori(nb / 10.0) != band:
						c = Color.WHITE if posmod(maxi(band, floori(nb / 10.0)), 5) == 0 else c.darkened(0.6)
				var q := p - res.dam_centre
				var ang := atan2(q.x, -q.y)
				if ang > res.dam_a0 and ang < res.dam_a1 and q.length() < Reservoir.DAM_RADIUS and q.length() > Reservoir.DAM_RADIUS - res.dam_base:
					c = c.lerp(Color.RED, 0.5)
				if res.spill.size() > 1 and res._spill_query(p).x < Reservoir.SPILL_HALF:
					c = c.lerp(Color.ORANGE, 0.6)
				if res.trail_distance(p) < Reservoir.TRAIL_HALF:
					c = Color.YELLOW
				img.set_pixel(x, y, c)
		img.save_png(out)
		print("MAP %s %dx%d %.0f..%.0f m" % [out, w, h, lo, hi])
	get_tree().quit()
