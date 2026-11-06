extends SceneTree
## Lists every drawn thing whose bounds cover a ground point, with its top and bottom and its
## material: two ground layers within a few centimetres of each other z-fight into stripes.
##   godot --headless --path . --script tools/paving_aa/stack_probe.gd -- --at=x,z
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	var c := Vector2.ZERO
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--at="):
			var p := arg.trim_prefix("--at=").split(",")
			c = Vector2(p[0].to_float(), p[1].to_float())
	for i in 8:
		await process_frame
	var city = current_scene
	var plan = city.get("plan")
	var bi: Vector2i = plan.block_index_at(c)
	var chunk = city.call("_new_chunk", bi, 0)
	chunk.call("build")
	var local := Vector3(c.x, 0.0, c.y) + (chunk as Node3D).global_position
	print("BLOCK ", bi, " chunk at ", (chunk as Node3D).global_position, " point ", local)
	for n in (chunk as Node).find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		var ab: AABB = g.get_aabb()
		var gab: AABB = g.global_transform * ab
		if gab.size.y > 3.0:
			continue
		if OS.get_environment("ALL") != "":
			var mm: Material = g.material_override
			print("  ALL %s y=%.3f..%.3f x=%.1f..%.1f z=%.1f..%.1f mat=%s" % [g.name, gab.position.y, gab.end.y, gab.position.x, gab.end.x, gab.position.z, gab.end.z, (mm as ShaderMaterial).shader.resource_path if mm is ShaderMaterial else str(mm)])
			continue
		if c.x < gab.position.x - (chunk as Node3D).global_position.x or c.x > gab.end.x - (chunk as Node3D).global_position.x:
			continue
		if c.y < gab.position.z - (chunk as Node3D).global_position.z or c.y > gab.end.z - (chunk as Node3D).global_position.z:
			continue
		var mat := ""
		var m: Material = g.material_override
		if m == null and g is MeshInstance3D and (g as MeshInstance3D).mesh != null and (g as MeshInstance3D).mesh.get_surface_count() > 0:
			m = (g as MeshInstance3D).mesh.surface_get_material(0)
		if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
			mat = (m as ShaderMaterial).shader.resource_path
		elif m != null:
			mat = m.get_class()
		print("  %s (%s) y=%.3f..%.3f cast=%d mat=%s" % [g.get_path(), g.get_class(), gab.position.y, gab.end.y, g.cast_shadow, mat])
	quit()
