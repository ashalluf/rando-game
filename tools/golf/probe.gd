extends SceneTree
## Golf course probe (GolfCourse): the snapped site, every hole (par, yards, bunkers), the water
## levels, the cart path, the trees, timings, and a top-down map of the distance fields as a PNG.
## Headless, seconds:
##   godot --headless --path . --script tools/golf/probe.gd      (SEED=n, OUT=map.png, PX=metres a pixel)
func _initialize() -> void:
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1337
	var t0 := Time.get_ticks_msec()
	var macro := MacroMap.new()
	macro.seed = sd
	macro.setup()
	var plan := CityPlan.new()
	plan.seed = sd
	plan.macro = macro
	print("setup ms=", Time.get_ticks_msec() - t0)
	t0 = Time.get_ticks_msec()
	var lay := GolfCourse.layout(plan)
	print("layout ms=", Time.get_ticks_msec() - t0)
	if lay.is_empty():
		print("NO COURSE")
		quit()
		return
	var site: Dictionary = lay.site
	print("site roads x ", site.ix0, "..", site.ix1, " z ", site.iz0, "..", site.iz1, " rect ", lay.rect, " mirror ", lay.mirror)
	var total := 0
	var par := 0
	for h: Dictionary in lay.holes:
		total += int(h.yards)
		par += int(h.par)
		for bk: Dictionary in h.bunkers:
			print("   bunker (%.1f, %.1f) %.1fx%.1f" % [bk.c.x, bk.c.y, bk.a, bk.b])
		print("   tee (%.1f, %.1f) pin (%.1f, %.1f)" % [h.tees[0].c.x, h.tees[0].c.y, h.pin.x, h.pin.y])
		print("hole %d par %d %d yd bunkers %d fairway %d pts green (%.0f, %.0f) %.1fx%.1f" % [h.n, h.par, h.yards, (h.bunkers as Array).size(), (h.fw as PackedVector2Array).size(), h.green.c.x, h.green.c.y, h.green.a, h.green.b])
	print("total ", total, " yd par ", par)
	print("pond level %.2f creek levels %s" % [lay.pond_level, str(lay.creek_levels)])
	print("path pts ", (lay.path as PackedVector2Array).size(), " bridges ", (lay.bridges as Array).size(), " trees ", (lay.trees as Array).size(), " range targets ", (lay.range_targets as Array).size())
	print("club ", lay.club, " park ", lay.park, " range ", lay.range)
	var px := float(OS.get_environment("PX")) if OS.get_environment("PX") != "" else 1.0
	var out := OS.get_environment("OUT")
	if out != "":
		var r: Rect2 = lay.rect
		var w := int(r.size.x / px)
		var hh := int(r.size.y / px)
		var img := Image.create(w, hh, false, Image.FORMAT_RGB8)
		t0 = Time.get_ticks_msec()
		var sub := GolfCourse.gather(lay, r)
		for y in hh:
			for x in w:
				var p := r.position + Vector2(x + 0.5, y + 0.5) * px
				var f := GolfCourse.field(sub, p)
				var c := Color(0.20, 0.36, 0.14)
				if f[0] < 0.0: c = Color(0.36, 0.62, 0.22)
				if f[3] < 0.0: c = Color(0.40, 0.66, 0.26)
				if f[1] < 1.3: c = Color(0.30, 0.66, 0.24)
				if f[1] < 0.0: c = Color(0.22, 0.74, 0.30)
				if f[2] < 0.0: c = Color(0.92, 0.85, 0.66)
				if f[4] < 0.0: c = Color(0.15, 0.30, 0.42)
				if f[5] < 0.0: c = Color(0.75, 0.74, 0.70)
				img.set_pixel(x, y, c)
		for t: Array in lay.trees:
			var q: Vector2 = ((t[0] as Vector2) - r.position) / px
			if q.x >= 0 and q.y >= 0 and q.x < w and q.y < hh:
				img.set_pixel(int(q.x), int(q.y), Color(0.05, 0.12, 0.04) if int(t[1]) != 3 else Color(0.5, 0.4, 0.1))
		for h: Dictionary in lay.holes:
			var q: Vector2 = ((h.pin as Vector2) - r.position) / px
			img.set_pixel(clampi(int(q.x), 0, w - 1), clampi(int(q.y), 0, hh - 1), Color(1, 0.9, 0))
		print("map ms=", Time.get_ticks_msec() - t0)
		img.save_png(out)
		print("wrote ", out)
	quit()
