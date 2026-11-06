extends SceneTree
## Ballpark mesh build: times and triangle counts per level, headless, seconds:
##   godot --headless --path . --script tools/stadium/bench.gd
func _initialize() -> void:
	for level in ["near", "far"]:
		var t0 := Time.get_ticks_usec()
		var c: Dictionary = BallparkBuild._meshes(level)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		print(level, " build %.1f ms" % ms, " stats ", BallparkBuild.stats.get(level), " lot ", BallparkBuild.stats.get("lot_" + level))
		for k in c:
			if c[k] is ArrayMesh:
				var m: ArrayMesh = c[k]
				var tris := 0
				for si in m.get_surface_count():
					var arr := m.surface_get_arrays(si)
					var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
					tris += (idx.size() if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
				print("   ", k, " tris ", tris)
	print("poles ", Ballpark.poles().size(), " palms ", Ballpark.palm_spots().size())
	var cars := 0
	var stalls := 0
	var q := Vector2(-Ballpark.SITE_U, Ballpark.SITE_V0)
	var v := Ballpark.SITE_V0 + 1.0
	while v < Ballpark.SITE_V1:
		var u := -Ballpark.SITE_U + 1.0
		while u < Ballpark.SITE_U:
			if Ballpark.stall_car(Vector2(u, v)) >= 0:
				cars += 1
			u += Ballpark.LOT_STALL_W
		v += Ballpark.LOT_STALL_D
	print("cars (whole site) ~", cars)
	quit()
