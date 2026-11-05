extends SceneTree
func _initialize() -> void:
	await process_frame
	var m := PropFactory.canopy_blob()
	var a := m.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	print("BLOB verts ", v.size(), " tris ", idx.size() / 3)
	for i in v.size():
		print("BLOB v", i, " ", v[i])
	print("BLOB idx ", idx)
	quit()
