extends Node
## Prints the tors RockOutcrops plans (counts by kind, sizes, how long the plan took) and, with
## OUT=map.png, draws them over a hillshade of the bake. Headless, about half a minute (the bake).
##
##   godot --headless --path . res://tools/rocks/probe.tscn   [OUT=map.png SEED=1337]
func _ready() -> void:
	var seed := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	var plan := CityPlan.new()
	plan.seed = seed
	plan.macro = MacroMap.new()
	plan.macro.seed = seed
	plan.macro.setup()
	var t0 := Time.get_ticks_msec()
	plan.macro.bake(Vector2.ZERO, 16000.0, 256)
	print("bake ", Time.get_ticks_msec() - t0, " ms")
	t0 = Time.get_ticks_msec()
	var tors: Array = RockOutcrops._plan_tors(plan)
	print("plan ", Time.get_ticks_msec() - t0, " ms")
	var by_kind := {}
	var big := 0
	for t: Dictionary in tors:
		by_kind[t.kind] = int(by_kind.get(t.kind, 0)) + 1
		if float(t.top) > 15.0:
			big += 1
	for k in by_kind:
		print("ROCKS kind ", RockKit.KINDS[k], " ", by_kind[k])
	var summits := tors.filter(func(t: Dictionary) -> bool: return bool(t.get("summit", false)))
	print("ROCKS total ", tors.size(), " standing over 15 m: ", big, " summit crags: ", summits.size())
	# NEAR=x,z: the biggest tors within 900 m, with an EYE 220 m downhill and 25 m over the ground
	# looking at each (still_shot.gd EYE=).
	if OS.get_environment("NEAR") != "":
		var q := OS.get_environment("NEAR").split(",")
		var at := Vector2(q[0].to_float(), q[1].to_float())
		var near: Array = tors.filter(func(t: Dictionary) -> bool: return (t.pos as Vector2).distance_to(at) < 900.0)
		near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.top) > float(b.top))
		for t: Dictionary in near.slice(0, 8):
			var p: Vector2 = t.pos
			var g := Vector2(plan.macro.height_at(p + Vector2(10, 0)) - plan.macro.height_at(p - Vector2(10, 0)),
				plan.macro.height_at(p + Vector2(0, 10)) - plan.macro.height_at(p - Vector2(0, 10)))
			var down := -g.normalized() if g.length() > 1e-3 else Vector2(0, 1)
			var dist := float(OS.get_environment("DIST")) if OS.get_environment("DIST") != "" else 260.0
			var eye := p + down * dist
			var gy := float(t.y) + float(t.sink)
			# Level with the rock's foot (or 25 m over the ground there), so its top stands on the sky.
			var ey := maxf(plan.macro.height_at(eye) + 25.0, gy)
			var yaw := rad_to_deg(atan2(-(p - eye).x, -(p - eye).y))
			var pitch := rad_to_deg(atan2(gy + float(t.top) * 0.4 - ey, dist))
			print("TOR %d %s%s at %s top %.0f m r %.0f  EYE=%.0f,%.1f,%.0f,%.0f,%.0f" % [t.id, RockKit.KINDS[t.kind], " summit" if t.get("summit", false) else "", p, t.top, t.radius, eye.x, ey, eye.y, yaw, pitch])
	# ROAD=x,z: cut banks on the hill roads within 1.5 km, with an EYE on the road looking along it.
	if OS.get_environment("ROAD") != "":
		var q := OS.get_environment("ROAD").split(",")
		var at := Vector2(q[0].to_float(), q[1].to_float())
		var shown := 0
		for seg: Dictionary in plan.macro.hill_roads.segments_in(Rect2(at - Vector2(1500, 1500), Vector2(3000, 3000))):
			if shown >= 6 or not bool(seg.get("draw", true)):
				continue
			var a: Vector2 = seg.a
			var b: Vector2 = seg.b
			var c := (a + b) * 0.5
			var d := (b - a).normalized()
			var n := Vector2(-d.y, d.x)
			var bed := (float(seg.ha) + float(seg.hb)) * 0.5
			var off := float(seg.width) * 0.5 + 3.5
			var cut := maxf(plan.macro.height_at(c + n * off), plan.macro.height_at(c - n * off)) - bed
			if cut < 4.0:
				continue
			var eye := c - d * 30.0
			var yaw := rad_to_deg(atan2(-d.x, -d.y))
			print("BANK cut %.1f m at %s  EYE=%.0f,%.1f,%.0f,%.0f,-4" % [cut, c, eye.x, bed + 2.2, eye.y, yaw])
			shown += 1
	var out := OS.get_environment("OUT")
	if out != "":
		var hi := plan.macro.bake_height
		var n := hi.get_width()
		var img := Image.create(n * 2, n * 2, false, Image.FORMAT_RGB8)
		for y in n * 2:
			for x in n * 2:
				var a := hi.get_pixel(mini(x / 2, n - 1), mini(y / 2, n - 1)).r
				var b := hi.get_pixel(mini(x / 2 + 1, n - 1), mini(y / 2 + 1, n - 1)).r
				var s := clampf(0.55 + (a - b) * 60.0, 0.0, 1.0)
				img.set_pixel(x, y, Color(s, s * 0.95, s * 0.85) if a > 0.004 else Color(0.1, 0.2, 0.35))
		for t: Dictionary in tors:
			var p: Vector2 = (t.pos + Vector2(8000, 8000)) / 16000.0 * float(n * 2)
			var c: Color = [Color(1, 0, 0), Color(1, 0.6, 0), Color(0.2, 0.4, 1)][t.kind]
			img.set_pixel(clampi(int(p.x), 0, n * 2 - 1), clampi(int(p.y), 0, n * 2 - 1), c)
		img.save_png(out)
	get_tree().quit()
