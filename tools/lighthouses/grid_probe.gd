extends SceneTree
## Height grid round a point: godot --headless --path . --script tools/lighthouses/grid_probe.gd -- --at=x,z --step=s --n=k

func _initialize() -> void:
	await process_frame
	var at := Vector2(2300, 6650)
	var step := 20.0
	var n := 10
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at="):
			var p := a.substr(5).split(",")
			at = Vector2(float(p[0]), float(p[1]))
		elif a.begins_with("--step="):
			step = float(a.substr(7))
		elif a.begins_with("--n="):
			n = int(a.substr(4))
	var m := MacroMap.new()
	m.seed = 1337
	m.setup()
	var hdr := "      z\\x"
	for i in range(-n, n + 1):
		hdr += "%6.0f" % (at.x + i * step)
	print(hdr)
	for j in range(-n, n + 1):
		var z := at.y + j * step
		var line := "%9.0f " % z
		for i in range(-n, n + 1):
			var p := Vector2(at.x + i * step, z)
			var zn := m.zone_at(p)
			var c := MacroMap.zone_name(zn).substr(0, 1)
			line += "%5.1f%s" % [m.height_at(p), c]
		print(line)
	quit()
