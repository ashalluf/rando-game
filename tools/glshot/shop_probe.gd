extends SceneTree
## Lists the storefronts near a --spawn point, for framing shop-interior stills:
##   godot --headless --path . --script tools/glshot/shop_probe.gd -- --spawn=x,z,yaw,pitch,h
## (R=metres, default 90; headless is enough: it only reads the Buildings' parts.)
## Each line: the storefront part's true-world centre at pavement height, its size, the building's
## rotation, and an EYE for still_shot.gd 5 m out from the middle of each face, looking at it.
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
	var found := 0
	var plan = current_scene.get("plan")
	print("DISTRICT ", (load("res://scripts/world/city_plan.gd") as GDScript).call("district_name", plan.district_at(c)))
	for b in current_scene.find_children("*", "StaticBody3D", true, false):
		if not (b.get("parts") is Array) or b.get("seed") == null:
			continue
		for part in b.get("parts"):
			if not part.get("storefront", false):
				continue
			var ctr: Vector3 = b.global_transform * (part.center as Vector3) + off
			if Vector2(ctr.x, ctr.z).distance_to(c) > float(OS.get_environment("R") if OS.get_environment("R") != "" else "90"):
				continue
			var sz: Vector3 = part.size
			var base_y: float = (b.global_transform * ((part.center as Vector3) - Vector3(0, sz.y * 0.5, 0))).y + off.y
			print("SHOP ", b.name, " seed=", b.get("seed"), " c=", Vector3(ctr.x, base_y, ctr.z).snapped(Vector3.ONE * 0.1), " size=", sz.snapped(Vector3.ONE * 0.1), " rot=", snappedf(rad_to_deg(b.global_rotation.y), 1))
			var basis: Basis = b.global_transform.basis
			for n in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
				var half: float = (sz.x if absf(n.x) > 0.5 else sz.z) * 0.5
				var wn: Vector3 = (basis * n).normalized()
				var eye: Vector3 = Vector3(ctr.x, 0, ctr.z) + wn * (half + 5.0)
				var look := -wn
				var yaw := rad_to_deg(atan2(-look.x, -look.z))
				print("   EYE=", snappedf(eye.x, 0.1), ",1.7,", snappedf(eye.z, 0.1), ",", snappedf(yaw, 1), ",-3")
			found += 1
	print("FOUND ", found)
	quit()
