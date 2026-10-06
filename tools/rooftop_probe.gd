extends SceneTree
## Counts the rooftop pieces (Rooftops) over many planned Buildings, headless, in seconds:
##
##   godot --headless --path . --script tools/rooftop_probe.gd
##
## Env: N (buildings, 400), LOT (lot size m, 34), HMIN / HMAX (height band, 30 / 200), FINISH (a
## Building.Finish), BUILD=1 also generates each one (prints the mesh's triangles), SEED0.
func _initialize() -> void:
	for i in 3:
		await process_frame
	var scene := load("res://scenes/props/building.tscn") as PackedScene
	# By path, after the autoloads: Rooftops' class chain compiles against them.
	var R = load("res://scripts/world/rooftops.gd")
	var n := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 400
	var lot := float(OS.get_environment("LOT")) if OS.get_environment("LOT") != "" else 34.0
	var hmin := float(OS.get_environment("HMIN")) if OS.get_environment("HMIN") != "" else 30.0
	var hmax := float(OS.get_environment("HMAX")) if OS.get_environment("HMAX") != "" else 200.0
	var seed0 := int(OS.get_environment("SEED0")) if OS.get_environment("SEED0") != "" else 1000
	var build := OS.get_environment("BUILD") == "1"
	var counts := {}
	# The palms and shrubs are built once for the whole city (the street palms warm them), so
	# warm them here too: the timing is the pieces.
	var PF = load("res://scripts/world/prop_factory.gd")
	for v in PF.PALM_VARIANTS:
		PF.palm(v)
	for v in 4:
		PF.model_shrub(v)
	var planned := 0
	var tris := 0
	var built := 0
	var t0 := Time.get_ticks_usec()
	for i in n:
		var b = scene.instantiate()
		b.seed = seed0 + i * 7919
		b.lot_size = Vector2(lot, lot)
		var t := float(i) / float(maxi(n - 1, 1))
		b.min_height = lerpf(hmin, hmax, t) * 0.88
		b.max_height = lerpf(hmin, hmax, t)
		if OS.get_environment("FINISH") != "":
			b.finish_options.assign([int(OS.get_environment("FINISH"))])
		if build:
			get_root().add_child(b)
			if b.has_meta("rooftops"):
				var p: Dictionary = b.get_meta("rooftops")
				for f: Dictionary in p.feats:
					counts[f.kind] = int(counts.get(f.kind, 0)) + 1
				planned += 1
				tris += int(b.get_meta("rooftops_tris", 0))
				built += 1
			b.queue_free()
		else:
			b.plan_only()
			b.roof_plan()
			var p: Dictionary = R.plan(b)
			if not p.is_empty():
				planned += 1
				for f: Dictionary in p.feats:
					counts[f.kind] = int(counts.get(f.kind, 0)) + 1
			var far: Array = R.far_boxes(b)
			counts["far boxes"] = int(counts.get("far boxes", 0)) + far.size()
			b.free()
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("ROOFTOPS %d buildings %.0f-%.0f m, lot %.0f: %d with pieces %s (%.1f ms total)" % [n, hmin, hmax, lot, planned, counts, ms])
	if build and built > 0:
		print("ROOFTOPS mean triangles a building with pieces: %d" % (tris / built))
		print("ROOFTOPS build time by piece (ms): ", (R.timing as Dictionary).keys().map(func(k): return "%s %.1f" % [k, float(R.timing[k]) / 1000.0]))
	quit()
