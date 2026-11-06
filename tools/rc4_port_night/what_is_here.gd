extends SceneTree
## Every visual instance whose bounds hold a point (TRUE world x,y,z), with its material's shader:
## what draws over the yard where a pool should show. Headless (bounds only):
##   godot --headless --path . --script tools/rc4_port_night/what_is_here.gd -- --spawn=3182,6490,101,10 AT=3170,0.5,6480
func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/city.tscn")
	for i in 40:
		await process_frame
	var at := Vector3(3170.0, 0.5, 6480.0)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("AT="):
			var p := a.trim_prefix("AT=").split(",")
			at = Vector3(float(p[0]), float(p[1]), float(p[2]))
	var ws = root.get_node("/root/WorldState")
	var local: Vector3 = ws.call("to_local", at)
	var stack: Array[Node] = [current_scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is VisualInstance3D and (n as VisualInstance3D).is_visible_in_tree():
			var vi := n as VisualInstance3D
			var box: AABB = vi.global_transform * vi.get_aabb()
			if box.grow(0.01).has_point(local):
				var mat := ""
				if n is GeometryInstance3D and (n as GeometryInstance3D).material_override:
					mat = str((n as GeometryInstance3D).material_override.get("shader"))
				elif n is MeshInstance3D and (n as MeshInstance3D).mesh and (n as MeshInstance3D).mesh.get_surface_count() > 0:
					var m: Material = (n as MeshInstance3D).mesh.surface_get_material(0)
					mat = str(m.get("shader").resource_path) if m and m.get("shader") else str(m)
				elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh and (n as MultiMeshInstance3D).multimesh.mesh:
					var mm := (n as MultiMeshInstance3D).multimesh.mesh
					var m2: Material = mm.surface_get_material(0) if mm.get_surface_count() > 0 else null
					if m2 == null and mm is PrimitiveMesh:
						m2 = (mm as PrimitiveMesh).material
					mat = str(m2.get("shader").resource_path) if m2 and m2.get("shader") else str(m2)
				print("HERE %s (%s) box y %.2f..%.2f %s" % [n.get_path(), n.get_class(), box.position.y, box.end.y, mat])
	quit()
