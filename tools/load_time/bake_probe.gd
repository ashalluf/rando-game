extends Node
## Splits the ground bake's cost (MacroMap.bake(), ~24 s cold on the build box) by the calls it
## makes per pixel, over a stride of the real bake's pixels. Headless, a minute:
##   godot --headless --path . res://tools/load_time/bake_probe.tscn
## STRIDE=n every n-th pixel each way of the 512 x 512 bake (default 8). FULL=1 also runs the real
## bake once and times it.

func _ready() -> void:
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var span: float = city.get("macro_span")
	var mm := MacroMap.new()
	mm.seed = city.get("world_seed")
	city.free()
	var t0 := Time.get_ticks_usec()
	mm.setup()
	print("BAKE setup %d ms" % ((Time.get_ticks_usec() - t0) / 1000))
	var res := 512
	var stride := int(OS.get_environment("STRIDE")) if OS.get_environment("STRIDE") != "" else 8
	var step := span / float(res)
	var origin := -Vector2(span, span) * 0.5
	var pts: Array[Vector2] = []
	for py in range(0, res, stride):
		for px in range(0, res, stride):
			pts.append(origin + Vector2((float(px) + 0.5) * step, (float(py) + 0.5) * step))
	var scale := float(res * res) / float(pts.size())
	var parts := {
		"raw_height_at": func(p: Vector2) -> void: mm.raw_height_at(p),
		"height_at": func(p: Vector2) -> void: mm.height_at(p),
		"_relief_at": func(p: Vector2) -> void: mm._relief_at(p, 0.0),
		"Ballpark.carve": func(p: Vector2) -> void: Ballpark.carve(p, 0.0),
		"hill_roads.carve": func(p: Vector2) -> void: mm.hill_roads.carve(p, 0.0) if mm.hill_roads else null,
		"Lighthouses.carve": func(p: Vector2) -> void: Lighthouses.carve(mm, p, 0.0),
		"zone_at": func(p: Vector2) -> void: mm.zone_at(p),
		"district_at": func(p: Vector2) -> void: mm.district_at(p),
		"freeway.blocks": func(p: Vector2) -> void: mm.freeway.blocks(p, MacroMap.BAKE_FREEWAY_MARGIN) if mm.freeway else null,
		"reservoir.wet": func(p: Vector2) -> void: mm.reservoir.wet(p) if mm.reservoir else null,
		"river.in_corridor": func(p: Vector2) -> void: mm.river.in_corridor(p, -LaRiver.CORRIDOR) if mm.river else null,
		"marina.in_water": func(p: Vector2) -> void: mm.marina.in_water(p) if mm.marina else null,
	}
	for k in parts:
		var f: Callable = parts[k]
		var t := Time.get_ticks_usec()
		for p in pts:
			f.call(p)
		var us := float(Time.get_ticks_usec() - t)
		print("BAKE %-18s %6.1f us/px  ~%6d ms for the bake" % [k, us / pts.size(), int(us * scale / 1000.0)])
	if OS.get_environment("FULL") == "1":
		# The real bake twice, with the raw-height memo and without: the time, and that the two
		# images (colour and height) are the same bytes.
		var out := {}
		for memo in [true, false]:
			MacroMap.bake_memo = memo
			var t := Time.get_ticks_usec()
			var img := mm.bake(Vector2.ZERO, span, 256)
			print("BAKE full memo=%s %d ms" % [memo, (Time.get_ticks_usec() - t) / 1000])
			out[memo] = [img.get_data(), mm.bake_height.get_data()]
		MacroMap.bake_memo = true
		print("BAKE identical colour=%s height=%s" % [out[true][0] == out[false][0], out[true][1] == out[false][1]])
	get_tree().quit()
