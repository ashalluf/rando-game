extends SceneTree
## Prints one dealership's layout in TRUE world coordinates (framing the auto_row refcam):
##   godot --headless --path . --script tools/rc5_auto_row/probe.gd -- --block=10,3
## Lines: the site, the showroom / service / pylon / tube men / poles, every lot car (kind, body).
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var b := Vector2i(10, 3)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--block="):
			var p := arg.trim_prefix("--block=").split(",")
			b = Vector2i(int(p[0]), int(p[1]))
	for i in 8:
		await process_frame
	var plan = current_scene.get("plan")
	var cd: GDScript = load("res://scripts/world/car_dealers.gd")
	var s: Dictionary = cd.call("site", plan, b.x, b.y)
	if s.is_empty():
		print("AUTOROW no site at ", b)
		quit()
		return
	var L: Dictionary = cd.call("layout", s)
	var xf: Transform3D = cd.call("frame_xf", s, 0.0)
	var w := func(x: float, z: float) -> String:
		var p: Vector3 = xf * Vector3(x, 0.0, z)
		return "%.1f,%.1f" % [p.x, p.z]
	print("AUTOROW site %s used=%s W=%.1f D=%.1f origin=%s out=%s" % [s.name, s.used, L.W, L.D, w.call(0.0, 0.0), xf.basis.z])
	var sr: Rect2 = L.showroom
	print("AUTOROW showroom ", w.call(sr.position.x, sr.position.y), " .. ", w.call(sr.end.x, sr.end.y))
	var vr: Rect2 = L.service
	print("AUTOROW service ", w.call(vr.position.x, vr.position.y), " .. ", w.call(vr.end.x, vr.end.y))
	if not (L.pylon as Array).is_empty():
		print("AUTOROW pylon ", w.call(float(L.pylon[0]), float(L.pylon[1])))
	for t: Array in L.tubes:
		print("AUTOROW tube ", w.call(float(t[0]), float(t[1])))
	for c: Array in L.cars:
		print("AUTOROW car %s v=%d at %s" % [c[3], c[4], w.call(float(c[0]), float(c[1]))])
	quit()
