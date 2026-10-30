extends SceneTree
## Prints each road body's mesh nodes: name, transform to the scene root, mesh AABB, surfaces
## (material name, triangles). Needs mesh data: opengl3 under Xvfb, never --headless.
##   xvfb-run -a godot --rendering-driver opengl3 --path . --script tools/car_cabins/model_probe.gd

func _initialize() -> void:
	for p in ["sedan", "crossover", "pickup", "van", "hatchback", "suv", "minivan", "taxi", "beater"]:
		var scene: PackedScene = load("res://assets/models/road_%s.glb" % p)
		var inst := scene.instantiate() as Node3D
		print("== ", p)
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var xf := Transform3D.IDENTITY
			var n: Node = m
			while n != inst:
				xf = (n as Node3D).transform * xf
				n = n.get_parent()
			var s := ""
			for si in m.mesh.get_surface_count():
				var mat := m.mesh.surface_get_material(si)
				var arr := m.mesh.surface_get_arrays(si)
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				s += " %s:%d" % [mat.resource_name if mat else "?", idx.size() / 3]
			print("  ", m.name, " xf=", xf.origin, " basis_x=", xf.basis.x, " aabb=", m.mesh.get_aabb(), s)
		inst.free()
	quit()
