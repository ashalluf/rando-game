extends SceneTree
## Reads a generated wheel's vertex arrays straight off the CPU and prints, per material class,
## how many vertices carry it and what shading colours they were given. The renderer is not
## involved, so this is the ground truth to check a screenshot against.
##
##   godot --headless --path . --script tools/glshot/wheel_vertex_probe.gd
func _initialize() -> void:
	var m: Mesh = PropFactory.car_wheel(0, 0.35, 0.235, true)
	var arrays := m.surface_get_arrays(0)
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var col: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	print("verts=%d uv=%d col=%d" % [(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
			uv.size(), col.size()])
	var lo := PackedFloat32Array()
	var hi := PackedFloat32Array()
	var n := PackedInt32Array()
	lo.resize(PropFactory.WHEEL_SLOTS)
	hi.resize(PropFactory.WHEEL_SLOTS)
	n.resize(PropFactory.WHEEL_SLOTS)
	lo.fill(9.0)
	hi.fill(-9.0)
	for i in uv.size():
		var s := clampi(int(uv[i].x * float(PropFactory.WHEEL_SLOTS)), 0, PropFactory.WHEEL_SLOTS - 1)
		n[s] += 1
		lo[s] = minf(lo[s], col[i].r)
		hi[s] = maxf(hi[s], col[i].r)
	for s in PropFactory.WHEEL_SLOTS:
		print("  slot %d %-8s n=%6d shade %.3f .. %.3f  (uv.x %.4f)" % [s,
				PropFactory.WHEEL_UNIFORMS[s], n[s], lo[s], hi[s],
				(float(s) + 0.5) / float(PropFactory.WHEEL_SLOTS)])
	quit()
