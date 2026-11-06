extends SceneTree
## A top-down map of the hills' painted ground as HillPlanting works it out (the terrain shader's
## field on the CPU, every octave resolved), hillshaded off the real heights: the brush stands'
## pattern in seconds, before any render (hill-ground-3).
##
##   godot --headless --path . --script tools/hill_ground_3/topdown.gd -- --at=300,-950 --size=600 \
##     --step=2 --out=/tmp/topdown.png
##
## Colours: straw gold, chaparral grey-green, dirt buff, rock grey; HILL_GROUND_3=0 the old field.

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var at := Vector2(300.0, -950.0)
	if args.has("at"):
		var p: PackedStringArray = (args.at as String).split(",")
		at = Vector2(p[0].to_float(), p[1].to_float())
	var size := float(args.get("size", "600"))
	var step := float(args.get("step", "2"))
	var out := String(args.get("out", "/tmp/topdown.png"))
	var plan := CityPlan.new()
	plan.seed = int(args.get("seed", "1337"))
	plan.macro = MacroMap.new()
	plan.macro.seed = plan.seed
	plan.macro.setup()
	var n := int(size / step)
	var hs := PackedFloat32Array()
	var ds := PackedFloat32Array()
	hs.resize((n + 2) * (n + 2))
	ds.resize((n + 2) * (n + 2))
	var o := at - Vector2(size, size) * 0.5
	for j in n + 2:
		for i in n + 2:
			var w := o + Vector2(i, j) * step
			hs[j * (n + 2) + i] = plan.height_at(w)
			ds[j * (n + 2) + i] = plan.macro.last_drain
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var sun := Vector3(-0.55, 0.62, 0.55).normalized()
	var straw := Color(0.62, 0.52, 0.30)
	var chap := Color(0.27, 0.31, 0.24)
	var dirt := Color(0.62, 0.56, 0.46)
	var rock := Color(0.55, 0.54, 0.51)
	var brush_sum := 0.0
	var t0 := Time.get_ticks_msec()
	for j in n:
		for i in n:
			var k := (j + 1) * (n + 2) + i + 1
			var grad := Vector2(hs[k + 1] - hs[k - 1], hs[k + n + 2] - hs[k - n - 2]) / (2.0 * step)
			var w := o + Vector2(i + 1, j + 1) * step
			var g := HillPlanting.ground(w, grad, true, ds[k])
			var c := straw.lerp(chap, float(g.brush)).lerp(dirt, float(g.bare)).lerp(rock, float(g.rocky))
			brush_sum += float(g.brush)
			var nrm := Vector3(-grad.x, 1.0, -grad.y).normalized()
			var l := clampf(nrm.dot(sun), 0.0, 1.0) * 0.8 + 0.35
			if hs[k] < 1.0:
				c = Color(0.3, 0.3, 0.32)
			img.set_pixel(i, j, Color(c.r * l, c.g * l, c.b * l))
	img.save_png(out)
	print("TOPDOWN %s %dx%d brush share %.2f, %d ms" % [out, n, n, brush_sum / float(n * n), Time.get_ticks_msec() - t0])
	quit()
