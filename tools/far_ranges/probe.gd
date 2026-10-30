extends Node
## The far ranges' silhouettes in seconds, without a city: marches MacroMap.height_at() out from
## an eye and paints a panorama (each column front to back, nearer ground drawn first, shaded by
## distance like the haze does), then measures the skyline - how many peaks stand out of it and
## how sharp they are (FarRanges.skyline_stats()). Judge a change to the ranges' shape here first.
##   OUT=pano.png EYE=300,275,-650 YAW=0 FOV=70 W=900 H=300 \
##     godot --headless --path . res://tools/far_ranges/probe.tscn
## FAR_RANGES=0 is the old shape (the A/B).

func _ready() -> void:
	await get_tree().process_frame
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var macro := MacroMap.new()
	macro.seed = city.world_seed
	city.free()
	var t0 := Time.get_ticks_msec()
	macro.setup()
	print("SETUP %d ms" % (Time.get_ticks_msec() - t0))
	# TOP=x0,z0,x1,z1,step writes the raw height there as a float image (TOP_OUT, .exr) and quits.
	if OS.get_environment("TOP") != "":
		var r := OS.get_environment("TOP").split(",")
		var x0 := r[0].to_float()
		var z0 := r[1].to_float()
		var st := r[4].to_float()
		var tw := int((r[2].to_float() - x0) / st)
		var th := int((r[3].to_float() - z0) / st)
		var him := Image.create(tw, th, false, Image.FORMAT_RF)
		for j in th:
			for i in tw:
				him.set_pixel(i, j, Color(macro.raw_height_at(Vector2(x0 + (i + 0.5) * st, z0 + (j + 0.5) * st)), 0, 0))
		var fa := FileAccess.open(OS.get_environment("TOP_OUT"), FileAccess.WRITE)
		fa.store_buffer(him.get_data())
		fa.close()
		print("TOP %dx%d" % [tw, th])
		get_tree().quit()
		return
	var e := _vec(OS.get_environment("EYE"), Vector3(300.0, 275.0, -650.0))
	var yaw := float(OS.get_environment("YAW")) if OS.get_environment("YAW") != "" else 0.0
	var fov := float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 70.0
	var w := int(OS.get_environment("W")) if OS.get_environment("W") != "" else 900
	var h := int(OS.get_environment("H")) if OS.get_environment("H") != "" else 300
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "pano.png"
	t0 = Time.get_ticks_msec()
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color(0.62, 0.74, 0.9))
	var sky := PackedFloat32Array()
	# Square pixels, the centre `PITCH` degrees up (default 5).
	var vspan := fov * float(h) / float(w)
	var pitch := float(OS.get_environment("PITCH")) if OS.get_environment("PITCH") != "" else 5.0
	for x in w:
		var az := deg_to_rad(yaw + fov * (0.5 - (x + 0.5) / w))
		# yaw 0 looks north (-z), 90 west (-x).
		var dir := Vector2(-sin(az), -cos(az))
		var top := h
		var best := -90.0
		var best_p := Vector2.ZERO
		var d := 60.0
		while d < 14000.0:
			var p := Vector2(e.x, e.z) + dir * d
			var gy := macro.height_at(p) - d * d / (2.0 * 6371000.0)
			var ang := rad_to_deg(atan2(gy - e.y, d))
			if ang > best:
				best = ang
				best_p = p
			var row := int((vspan * 0.5 + pitch - ang) / vspan * h)
			if row < top:
				var haze := 1.0 - exp(-d / 6500.0)
				var c := Color(0.30, 0.27, 0.20).lerp(Color(0.55, 0.66, 0.82), haze)
				for y in range(maxi(row, 0), top):
					img.set_pixel(x, y, c)
				top = maxi(row, 0)
			d += 8.0 + d * 0.003
		sky.append(best)
		if OS.get_environment("COLS") != "" and str(x) in OS.get_environment("COLS").split(","):
			print("COL %d top %.2f deg at %s (%.0f m) raw %.0f" % [x, best, best_p, best_p.distance_to(Vector2(e.x, e.z)), macro.raw_height_at(best_p)])
	img.save_png(out)
	var st := FarRanges.skyline_stats(sky, fov / w)
	print("PANO %s %dx%d in %d ms" % [out, w, h, Time.get_ticks_msec() - t0])
	print("SKYLINE peaks %d (prominence > 0.25 deg), sharp %.3f, mean %.2f deg" % [st.peaks, st.sharp, st.mean])
	get_tree().quit()


func _vec(s: String, def: Vector3) -> Vector3:
	if s == "":
		return def
	var p := s.split(",")
	return Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float())
