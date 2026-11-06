extends SceneTree
## Prints the hero's meshes, surfaces, materials and per-surface bounds (needs mesh data: run
## under opengl3 + Xvfb, not --headless). Used to find the eyeballs for the living face.
func _initialize() -> void:
	var inst := (load("res://assets/models/hero.glb") as PackedScene).instantiate() as Node3D
	get_root().add_child(inst)
	var sk := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk:
		print("BONES ", sk.get_bone_count(), " head ", sk.find_bone("Head"))
		var hb := sk.find_bone("Head")
		print("HEAD_REST ", sk.get_bone_global_rest(hb))
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		print("MESH ", mi.name, " surfaces ", mi.mesh.get_surface_count(), " xf ", mi.transform, " skin ", mi.skin != null)
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			var a := mi.mesh.surface_get_arrays(i)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var lo := Vector3(1e9, 1e9, 1e9)
			var hi := -lo
			for p in v:
				lo = lo.min(p)
				hi = hi.max(p)
			var bs = a[Mesh.ARRAY_BONES]
			var info := ""
			if m and m.resource_name == "hero_eyes":
				# split left / right by x and fit each eyeball's centre and radius
				for side in [-1.0, 1.0]:
					var c := Vector3.ZERO
					var n := 0
					for p in v:
						if signf(p.x) == side:
							c += p
							n += 1
					c /= maxf(n, 1)
					var r := 0.0
					var lo2 := Vector3(1e9, 1e9, 1e9)
					var hi2 := -lo2
					for p in v:
						if signf(p.x) == side:
							r += p.distance_to(c)
							lo2 = lo2.min(p)
							hi2 = hi2.max(p)
					info += " eye%s c=%s r=%.4f lo=%s hi=%s n=%d" % [side, c, r / maxf(n, 1), lo2, hi2, n]
				if bs:
					var bi: PackedInt32Array = bs
					var used := {}
					for b in bi:
						used[b] = true
					info += " bones=" + str(used.keys())
			print("  SURF ", i, " ", m.resource_name if m else "-", " verts ", v.size(), " lo ", lo, " hi ", hi, info)
	quit()
