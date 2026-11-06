extends SceneTree

var _boxes: Array = []

func _gather(n: Node, xf: Transform3D) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh is BoxMesh:
		_boxes.append({"xf": t, "size": ((n as MeshInstance3D).mesh as BoxMesh).size})
	for c in n.get_children():
		_gather(c, t)

func _covered(p: Vector3) -> bool:
	for b in _boxes:
		var l: Vector3 = (b.xf as Transform3D).affine_inverse() * p
		var s: Vector3 = b.size * 0.5
		if absf(l.x) <= s.x and absf(l.y) <= s.y and absf(l.z) <= s.z:
			return true
	return false

func _initialize() -> void:
	var rd := Vector2(-765.0, 1450.0)
	var p := Node3D.new()
	root.add_child(p)
	await process_frame
	LandmarkBeachPiers.build_redondo(rd, p, null, null, true)
	await process_frame
	_gather(p, Transform3D.IDENTITY)
	print("box meshes: ", _boxes.size())
	# Walk the outer edge of the bend at deck height and report gaps.
	var bend := Vector2(rd.x - 14.0 - 150.0, rd.y)
	var holes := 0
	var total := 0
	var runs: Array = []
	var in_hole := false
	for i in 2000:
		var a := -PI * 0.5 - PI * float(i) / 1999.0
		var r := 55.0 + 7.0  # 1 m inside the outer deck edge
		var q := bend + Vector2(cos(a), sin(a)) * r
		var ok := _covered(Vector3(q.x, 6.0, q.y))
		total += 1
		if not ok:
			holes += 1
			if not in_hole:
				runs.append([a, a])
				in_hole = true
			else:
				runs[runs.size() - 1][1] = a
		else:
			in_hole = false
	print("outer edge samples uncovered: %d / %d in %d runs" % [holes, total, runs.size()])
	for r in runs:
		var w: float = absf(r[1] - r[0]) * 55.0
		print("   gap %.2f m wide near angle %.1f deg" % [w, rad_to_deg(r[0])])
	# Same walk 4 m inside the outer edge.
	var h2 := 0
	for i in 2000:
		var a := -PI * 0.5 - PI * float(i) / 1999.0
		var q := bend + Vector2(cos(a), sin(a)) * (55.0 + 4.0)
		if not _covered(Vector3(q.x, 6.0, q.y)):
			h2 += 1
	print("4 m inside outer edge uncovered: %d / 2000" % h2)
	quit()
