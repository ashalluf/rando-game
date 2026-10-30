extends SceneTree
## Lists the ground-floor walls near a --spawn point, for framing facades-street stills:
##   godot --headless --path . --script tools/facades_street/probe.gd -- --spawn=x,z,0,0
## (R=metres, default 80; headless is enough: it only reads the Buildings' parts.)
## Each line: the part's true-world centre, size, shops or not, finish, window style, height, and
## for every face an EYE for still_shot.gd (EYE_AGL=1) 6 m out and 3 m along, looking back at it.
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var c := Vector2.ZERO
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spawn="):
			var p := arg.trim_prefix("--spawn=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
	for i in 40:
		await process_frame
	var ws := root.get_node("/root/WorldState")
	var off: Vector3 = ws.get("world_offset")
	var radius := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 80.0
	var found := 0
	for b in current_scene.find_children("*", "StaticBody3D", true, false):
		if not (b.get("parts") is Array) or b.get("seed") == null:
			continue
		for part in b.get("parts"):
			var sz: Vector3 = part.size
			var bottom: float = (part.center as Vector3).y - sz.y * 0.5
			if bottom > 0.01 or part.get("parking", false):
				continue
			var ctr: Vector3 = b.global_transform * (part.center as Vector3) + off
			if Vector2(ctr.x, ctr.z).distance_to(c) > radius:
				continue
			print("WALL ", b.name, " seed=", b.get("seed"), " c=", Vector3(ctr.x, 0, ctr.z).snapped(Vector3.ONE * 0.1),
				" size=", sz.snapped(Vector3.ONE * 0.1), " shop=", part.get("storefront", false), " finish=", b.get("finish"),
				" style=", b.get("window_style"), " back=", b.get("back_face"))
			var basis: Basis = b.global_transform.basis
			for n in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
				var half: float = (sz.x if absf(n.x) > 0.5 else sz.z) * 0.5
				var wn: Vector3 = (basis * n).normalized()
				var side := wn.cross(Vector3.UP)
				var eye: Vector3 = Vector3(ctr.x, 0, ctr.z) + wn * (half + 6.0) + side * 3.0
				var look := (-wn * 6.0 - side * 3.0).normalized()
				var yaw := rad_to_deg(atan2(-look.x, -look.z))
				print("   EYE=", snappedf(eye.x, 0.1), ",1.7,", snappedf(eye.z, 0.1), ",", snappedf(yaw, 1), ",4")
			found += 1
	print("FOUND ", found)
	quit()
