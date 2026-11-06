extends SceneTree
## Builds every wheel mesh and prints its triangle count and bounds, without a window.
##
##   godot --headless --path . --script tools/glshot/wheel_probe.gd
func _initialize() -> void:
	var total := 0
	for style in PropFactory.WHEEL_FACES.size():
		for near: bool in [true, false]:
			var m: Mesh = PropFactory.car_wheel(style, 0.35, 0.235, near)
			var tris := 0
			var verts := 0
			for s in m.get_surface_count():
				# Indexed: array_len is the VERTEX count, index_len / 3 is the triangles.
				verts += m.surface_get_array_len(s)
				tris += m.surface_get_array_index_len(s) / 3
			var aabb := m.get_aabb()
			print("style %d %-4s: %6d tris  %6d verts  surfaces %d  aabb size %v" % [
				style, "near" if near else "far", tris, verts, m.get_surface_count(), aabb.size])
			if near:
				total += tris
	var cal: Mesh = PropFactory.car_caliper(0, 0.35, 0.235)
	var ct := 0
	for s in cal.get_surface_count():
		ct += cal.surface_get_array_index_len(s) / 3
	print("caliper: %d tris, aabb %v %v" % [ct, cal.get_aabb().position, cal.get_aabb().size])
	print("material: ", PropFactory.wheel_material(0))
	quit()
