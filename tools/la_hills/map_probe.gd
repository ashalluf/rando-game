extends Node
## LA hills map probe: a top-down image of a region - zone, mountains, relief, freeways, river,
## light rail, landmarks - so a hill can be placed between them. Headless, seconds:
##   godot --headless --path . res://tools/la_hills/map_probe.tscn -- --rect=x0,z0,x1,z1 --out=map.png [--step=8]
func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var r := (args.get("rect", "0,-3000,4800,0") as String).split(",")
	var x0 := float(r[0]); var z0 := float(r[1]); var x1 := float(r[2]); var z1 := float(r[3])
	var step := float(args.get("step", "10"))
	var macro := MacroMap.new()
	macro.seed = 1337
	macro.setup()
	var plan := CityPlan.new()
	plan.seed = 1337
	plan.macro = macro
	var w := int((x1 - x0) / step)
	var h := int((z1 - z0) / step)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var hmax := 1.0
	for j in h:
		for i in w:
			var p := Vector2(x0 + i * step, z0 + j * step)
			var raw := macro.raw_height_at(p)
			var rel := macro.relief_at(p)
			var z := macro.zone_at(p)
			var c := Color(0.5, 0.5, 0.5)
			if z == MacroMap.Zone.OCEAN:
				c = Color(0.1, 0.2, 0.5)
			elif raw > 0.5:
				c = Color(0.35 + minf(raw / 600.0, 0.6), 0.3, 0.2)
			else:
				var t := clampf(rel / 40.0, 0.0, 1.0)
				c = Color(0.2 + t * 0.8, 0.5 + t * 0.4, 0.2)
			# contours every 5 m of relief
			if raw <= 0.5 and fmod(rel, 5.0) < 0.35:
				c = c.darkened(0.4)
			img.set_pixel(i, j, c)
	# freeways
	for fr in macro.freeway.routes:
		var pts: PackedVector2Array = fr.points
		for q in pts:
			var i := int((q.x - x0) / step); var j := int((q.y - z0) / step)
			if i >= 0 and j >= 0 and i < w and j < h:
				img.set_pixel(i, j, Color(1, 0, 1))
	if macro.river:
		for q in macro.river.pts:
			var i := int((q.x - x0) / step); var j := int((q.y - z0) / step)
			if i >= 0 and j >= 0 and i < w and j < h:
				img.set_pixel(i, j, Color(0, 1, 1))
	for lm in Landmarks.all():
		var a: Vector2 = lm.anchor
		var i := int((a.x - x0) / step); var j := int((a.y - z0) / step)
		if i >= 1 and j >= 1 and i < w - 1 and j < h - 1:
			for d in [Vector2i(0,0), Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
				img.set_pixel(i + d.x, j + d.y, Color(1, 0, 0))
			if args.has("names"):
				print(lm.id, " ", a, " r=", lm.get("radius", 0))
	img.save_png(args.get("out", "map.png"))
	print("saved ", w, "x", h)
	get_tree().quit()
