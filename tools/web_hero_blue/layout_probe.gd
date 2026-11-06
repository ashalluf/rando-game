extends SceneTree
func _initialize() -> void:
	var bad := 0
	for fmt in [[true, true], [true, false], [false, true], [false, false]]:
		var a := MultiMesh.new(); var b := MultiMesh.new()
		for m in [a, b]:
			m.transform_format = MultiMesh.TRANSFORM_3D; m.use_colors = fmt[0]; m.use_custom_data = fmt[1]; m.instance_count = 5
		var rows := MultiMeshRows.new(b)
		for i in 5:
			var xf := Transform3D(Basis(Vector3(1+i, 2, 3), Vector3(4, 5+i, 6), Vector3(7, 8, 9+i)), Vector3(10*i, 11, 12))
			var c := Color(0.1*i, 0.2, 0.3, 0.4); var u := Color(1.5, 2.5*i, -3.0, 4.0)
			a.set_instance_transform(i, xf)
			if fmt[0]: a.set_instance_color(i, c)
			if fmt[1]: a.set_instance_custom_data(i, u)
			rows.put(i, xf, c, u)
		rows.commit(5)
		var ba := a.buffer; var bb := b.buffer
		print(fmt, " sizes ", ba.size(), " ", bb.size(), " equal ", ba == bb)
		if ba != bb: bad += 1
	print("LAYOUT_BAD ", bad)
	quit()
