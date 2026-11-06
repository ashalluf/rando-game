extends SceneTree
## Lists every visible mesh in the city whose bounds are wide (> MIN_W m across) and thin (< MAX_H m
## tall) and lie within REACH m of the camera's height: the candidates for a translucent sheet that
## cuts the frame at the horizon (web-review-5: the Santa Ana bookmark). Same args as city_shot.gd:
##   FRAMES=60 godot --headless --path . --script tools/web_probe/plane_probe.gd -- --spawn=7,420,3,12 \
##     --hour=18.5 --weather=santa_ana
## Headless is fine: it reads node transforms and mesh bounds, not pixels.

func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var frames := int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 40
	var min_w := float(OS.get_environment("MIN_W")) if OS.get_environment("MIN_W") != "" else 40.0
	var max_h := float(OS.get_environment("MAX_H")) if OS.get_environment("MAX_H") != "" else 6.0
	var reach := float(OS.get_environment("REACH")) if OS.get_environment("REACH") != "" else 8.0
	for i in frames:
		await process_frame
	var cam := get_root().get_camera_3d()
	var scene := get_root().get_child(get_root().get_child_count() - 1)
	print("PLANE camera ", cam.global_position if cam else Vector3.ZERO, " near ", cam.near if cam else 0.0)
	if cam:
		var space := cam.get_world_3d().direct_space_state
		for m in [1, 16, 32, 0xFFFFFFFF]:
			var q := PhysicsRayQueryParameters3D.create(cam.global_position + Vector3.UP * 5.0, cam.global_position + Vector3.DOWN * 5.0, m)
			var hit := space.intersect_ray(q)
			print("PLANE below mask %d: %s %s" % [m, hit.get("position", "none"), (hit.get("collider") as Node).get_path() if hit.get("collider") is Node else ""])
	var pl := get_first_node_in_group("player")
	if pl:
		var sw := pl.get_node_or_null("Swim")
		print("PLANE player ", pl.global_position, " swim ", sw.get("swimming") if sw else "none", " water ", sw.get("water") if sw else {})
	for n in get_root().find_children("*", "CanvasItem", true, false):
		var ci := n as CanvasItem
		if ci.is_visible_in_tree() and ci is Control and (ci as Control).get_global_rect().size.x > 300.0:
			print("PLANE UI %s %s rect=%s modulate=%s" % [ci.get_path(), ci.get_class(), (ci as Control).get_global_rect(), ci.modulate])
		elif ci.is_visible_in_tree() and not (ci is Control):
			print("PLANE UI2 %s %s" % [ci.get_path(), ci.get_class()])
	for n in scene.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		var box := g.global_transform * g.get_aabb()
		if g.has_method("get_custom_aabb") and g.get("custom_aabb") is AABB and (g.get("custom_aabb") as AABB).size != Vector3.ZERO:
			box = g.global_transform * (g.get("custom_aabb") as AABB)
		if OS.get_environment("MODE") == "over":
			var cp := cam.global_position
			if not (cp.x > box.position.x and cp.x < box.end.x and cp.z > box.position.z and cp.z < box.end.z and box.end.y > cp.y and box.position.y < cp.y + 3.0 and maxf(box.size.x, box.size.z) < 3000.0):
				continue
		elif maxf(box.size.x, box.size.z) < min_w or box.size.y > max_h:
			continue
		var cy := cam.global_position.y if cam else 0.0
		if absf(box.get_center().y - cy) > reach:
			continue
		var mat := ""
		if g is MeshInstance3D and (g as MeshInstance3D).mesh:
			var m := (g as MeshInstance3D).mesh
			var sm: Material = g.material_override if g.material_override else (m.surface_get_material(0) if m.get_surface_count() > 0 else null)
			if sm is ShaderMaterial and (sm as ShaderMaterial).shader:
				mat = (sm as ShaderMaterial).shader.resource_path
			elif sm:
				mat = sm.get_class() + (" transp" if sm is BaseMaterial3D and (sm as BaseMaterial3D).transparency != 0 else "")
		print("PLANE %s %s box=%s mat=%s" % [g.get_path(), g.get_class(), box, mat])
	quit()
