extends "res://tools/rc2_night_aerial/hide_probe.gd"
## heli_night: what is under a pixel? PICK="x,y;x,y" (pixels of the saved shot) casts a ray from the
## camera through each and prints the collider, its path and every GeometryInstance3D within PICK_R
## (default 25) m of the hit with its AABB, so a glowing roof can be named before it is hidden.
## Then the HIDE_PATTERNS pass of hide_probe.gd. Run it like still_shot.gd with TREES_AB=1.


func _trees_ab(path: String) -> void:
	var cam := get_root().get_camera_3d()
	var size := Vector2(get_root().get_visible_rect().size)
	var r := float(OS.get_environment("PICK_R")) if OS.get_environment("PICK_R") != "" else 25.0
	for s in OS.get_environment("PICK").split(";", false):
		var xy := String(s).split(",")
		var px := Vector2(float(xy[0]), float(xy[1])) * size / Vector2(1280, 720)
		var from := cam.project_ray_origin(px)
		var to := from + cam.project_ray_normal(px) * 6000.0
		var q := PhysicsRayQueryParameters3D.create(from, to)
		var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			print("PICK %s: nothing" % s)
			continue
		var p: Vector3 = hit.position
		print("PICK %s: %s at %s (%.0f m)" % [s, (hit.collider as Node).get_path(), p, from.distance_to(p)])
		for n in current_scene.find_children("*", "GeometryInstance3D", true, false):
			var gi := n as GeometryInstance3D
			if not gi.is_visible_in_tree():
				continue
			var bb := gi.global_transform * gi.get_aabb()
			if bb.grow(r).has_point(p) and bb.size.length() < 600.0:
				print("  NEAR %s %s mat=%s" % [gi.get_path(), bb, _mat(gi)])
	await super(path)


func _mat(gi: GeometryInstance3D) -> String:
	var m: Material = gi.material_override
	if m == null and gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null and (gi as MeshInstance3D).mesh.get_surface_count() > 0:
		m = (gi as MeshInstance3D).mesh.surface_get_material(0)
	if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
		return (m as ShaderMaterial).shader.resource_path.get_file()
	return str(m)
